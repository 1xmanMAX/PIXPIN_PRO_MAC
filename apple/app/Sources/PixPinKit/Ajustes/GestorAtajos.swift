// Los atajos globales de PixPin en este Mac: los del catalogo
// (`ComandoAtajo`), las regiones guardadas, silenciarlos todos y los
// programas delante de los cuales no actuan. Como el bucle de atajos de
// Windows (`main.rs` + `comandos.rs` + `regiones.rs`).
//
// **Donde se guarda.** En UserDefaults, no en `pixpinmax.toml`: el TOML no
// viaja entre aparatos y un atajo de Carbon no significa nada en Windows.
// Pero con la misma forma que la tabla `[comandos]` de Windows (nombre →
// «Ctrl+Alt+X», vacio = sin atajo, ausente = el de fabrica) y las mismas
// claves de `[[regiones]]` e `ignorar_programas`, por si un dia se juntan.
//
// **Registrar.** Cada comando con atajo Y con alguien que lo haga
// (`poner(_:accion:)`) se registra en Carbon (`AtajoGlobal`). Si el sistema
// no deja (otra app lo tiene), se dice en Ajustes y en el menu no se ve.
// Mientras se graba un atajo nuevo en Ajustes se sueltan todos (`pausar`):
// si no, pulsar el que ya existe dispararia su comando en vez de grabarse.

import AppKit
import Carbon.HIToolbox
import Foundation

/// Lo que paso al cambiar un atajo.
public enum ResultadoAtajo: Equatable, Sendable {
    case hecho
    /// Hecho, pero puede pisar algo de macOS.
    case hechoConAviso(String)
    /// No se cambio (y por que).
    case rechazado(String)

    public var mensaje: String? {
        switch self {
        case .hecho: nil
        case let .hechoConAviso(t), let .rechazado(t): t
        }
    }
}

@MainActor
public final class GestorAtajos: ObservableObject {
    @Published public private(set) var enlaces = EnlacesAtajos()
    @Published public private(set) var regiones: [RegionGuardada] = []
    /// Apps delante de las cuales los atajos no hacen nada (por nombre).
    @Published public private(set) var ignorados: [String] = []
    /// Todos los atajos soltados (el comando «Silenciar los atajos»).
    @Published public private(set) var silenciados = false
    /// Los comandos cuyo atajo no dejo registrar el sistema.
    @Published public private(set) var fallidos: Set<ComandoAtajo> = []
    @Published public private(set) var regionesFallidas: Set<UUID> = []
    /// Lo guardado que no se entendio (para decirlo en Ajustes).
    @Published public private(set) var noEntendidos: [String] = []
    /// Los comandos que tienen quien los haga (los demas no se ensenan).
    @Published public private(set) var disponibles: Set<ComandoAtajo> = []

    /// Captura una region guardada (sin abrir la captura).
    public var alCapturarRegion: ((RegionGuardada) -> Void)?

    static let claveComandos = "atajos.comandos"
    static let claveRegiones = "atajos.regiones"
    static let claveIgnorar = "atajos.ignorar_programas"
    /// Las del atajo de antes (solo capturar): se migran una vez.
    static let claveViejaTecla = "atajoCaptura.tecla"
    static let claveViejaModificadores = "atajoCaptura.modificadores"

    private let defaults: UserDefaults
    private let conCarbon: Bool
    private var acciones: [ComandoAtajo: @MainActor () -> Void] = [:]
    private var vivos: [ComandoAtajo: AtajoGlobal] = [:]
    private var vivosRegiones: [UUID: AtajoGlobal] = [:]
    private var pausas = 0

    /// Lee lo guardado. `registrar: false` solo para las pruebas (no toca
    /// Carbon y todo «se deja»).
    public init(defaults: UserDefaults = .standard, registrar: Bool = true) {
        self.defaults = defaults
        conCarbon = registrar
        leer()
    }

    // MARK: Comandos

    /// Quien hace el comando `c`. Desde aqui su atajo se registra y sale en
    /// Ajustes y en el menu.
    public func poner(_ c: ComandoAtajo, accion: @escaping @MainActor () -> Void) {
        acciones[c] = accion
        disponibles.insert(c)
        reconciliar()
    }

    public func disponible(_ c: ComandoAtajo) -> Bool { acciones[c] != nil }

    /// El atajo de `c` si de verdad esta registrado (para ensenarlo en el menu).
    public func atajoActivo(de c: ComandoAtajo) -> AtajoGlobal.Combinacion? {
        guard let a = enlaces.atajo(de: c), !fallidos.contains(c), !silenciados else { return nil }
        return a
    }

    /// Hace el comando (desde el menu o por su atajo).
    public func ejecutar(_ c: ComandoAtajo) {
        acciones[c]?()
    }

    /// Lo que pasa al pulsar el atajo: nada si la app de delante esta en
    /// la lista de ignorados.
    private func disparar(_ c: ComandoAtajo) {
        guard !frenteIgnorado() else { return }
        ejecutar(c)
    }

    /// Cambia el atajo de `c` (`nil` lo quita) y lo guarda.
    @discardableResult
    public func cambiar(_ c: ComandoAtajo, a nueva: AtajoGlobal.Combinacion?) -> ResultadoAtajo {
        var aviso: String?
        if let nueva {
            if let choque = ChoqueAtajo.de(nueva) {
                if choque.bloquea { return .rechazado(choque.texto) }
                aviso = choque.texto
            }
            if let otro = enlaces.quien(tiene: nueva, salvo: c) {
                return .rechazado("\(nueva.descripcion) ya es de «\(otro.titulo)».")
            }
            if let r = regiones.first(where: { $0.combinacion == nueva }) {
                return .rechazado("\(nueva.descripcion) ya es de la región «\(r.nombre)».")
            }
        }
        let antes = enlaces
        enlaces.poner(c, nueva)
        reconciliar()
        if nueva != nil, fallidos.contains(c), disponible(c), activos {
            enlaces = antes
            reconciliar()
            return .rechazado("\(nueva?.descripcion ?? "") lo tiene otra app o el sistema.")
        }
        guardarComandos()
        return aviso.map { .hechoConAviso($0) } ?? .hecho
    }

    /// Vuelve al atajo de fabrica de `c`.
    @discardableResult
    public func restablecer(_ c: ComandoAtajo) -> ResultadoAtajo {
        guard let fabrica = c.deFabrica else { return cambiar(c, a: nil) }
        if let otro = enlaces.quien(tiene: fabrica, salvo: c) {
            return .rechazado("\(fabrica.descripcion) ya es de «\(otro.titulo)».")
        }
        return cambiar(c, a: fabrica)
    }

    /// Todos a los de fabrica.
    public func restablecerTodos() {
        enlaces = EnlacesAtajos()
        reconciliar()
        guardarComandos()
    }

    // MARK: Silenciar y pausar

    /// Suelta (o vuelve a tomar) todos los atajos.
    public func silenciar(_ si: Bool) {
        guard si != silenciados else { return }
        silenciados = si
        reconciliar()
    }

    /// Suelta todos un momento (mientras se graba uno nuevo en Ajustes).
    public func pausar() {
        pausas += 1
        reconciliar()
    }

    public func reanudar() {
        pausas = max(0, pausas - 1)
        reconciliar()
    }

    private var activos: Bool { !silenciados && pausas == 0 }

    // MARK: Regiones

    public func anadir(_ region: RegionGuardada) {
        regiones.append(region)
        guardarRegiones()
        reconciliar()
    }

    public func quitarRegion(_ id: UUID) {
        regiones.removeAll { $0.id == id }
        guardarRegiones()
        reconciliar()
    }

    public func renombrarRegion(_ id: UUID, a nombre: String) {
        guard let i = regiones.firstIndex(where: { $0.id == id }) else { return }
        let limpio = nombre.trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty else { return }
        regiones[i].nombre = limpio
        guardarRegiones()
    }

    /// Cambia el atajo de una region (`nil` lo quita).
    @discardableResult
    public func cambiarAtajo(region id: UUID, a nueva: AtajoGlobal.Combinacion?) -> ResultadoAtajo {
        guard let i = regiones.firstIndex(where: { $0.id == id }) else { return .rechazado("Esa región ya no está.") }
        var aviso: String?
        if let nueva {
            if let choque = ChoqueAtajo.de(nueva) {
                if choque.bloquea { return .rechazado(choque.texto) }
                aviso = choque.texto
            }
            if let otro = enlaces.quien(tiene: nueva) {
                return .rechazado("\(nueva.descripcion) ya es de «\(otro.titulo)».")
            }
            if let r = regiones.first(where: { $0.id != id && $0.combinacion == nueva }) {
                return .rechazado("\(nueva.descripcion) ya es de la región «\(r.nombre)».")
            }
        }
        let antes = regiones[i].atajo
        regiones[i].atajo = nueva?.texto
        reconciliar()
        if nueva != nil, regionesFallidas.contains(id), activos {
            regiones[i].atajo = antes
            reconciliar()
            return .rechazado("\(nueva?.descripcion ?? "") lo tiene otra app o el sistema.")
        }
        guardarRegiones()
        return aviso.map { .hechoConAviso($0) } ?? .hecho
    }

    // MARK: Programas ignorados

    public func ignorar(_ programa: String) {
        let p = programa.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty,
              !ProgramasIgnorados.estaEnLaLista(nombre: p, paquete: nil, identificador: nil, lista: ignorados)
        else { return }
        ignorados.append(p)
        defaults.set(ignorados, forKey: GestorAtajos.claveIgnorar)
    }

    public func dejarDeIgnorar(_ programa: String) {
        ignorados.removeAll { $0 == programa }
        if ignorados.isEmpty {
            defaults.removeObject(forKey: GestorAtajos.claveIgnorar)
        } else {
            defaults.set(ignorados, forKey: GestorAtajos.claveIgnorar)
        }
    }

    private func frenteIgnorado() -> Bool {
        guard !ignorados.isEmpty, let app = NSWorkspace.shared.frontmostApplication else { return false }
        return ProgramasIgnorados.estaEnLaLista(nombre: app.localizedName,
                                                paquete: app.bundleURL?.lastPathComponent,
                                                identificador: app.bundleIdentifier,
                                                lista: ignorados)
    }

    // MARK: Registrar en Carbon

    /// Deja registrados justo los que tocan: con atajo, con accion y sin
    /// silenciar ni pausar.
    private func reconciliar() {
        var fallan: Set<ComandoAtajo> = []
        for c in ComandoAtajo.allCases {
            let quiere = activos && acciones[c] != nil ? enlaces.atajo(de: c) : nil
            guard let quiere else {
                vivos[c]?.quitar()
                vivos[c] = nil
                continue
            }
            guard conCarbon else { continue }
            if let vivo = vivos[c], vivo.combinacion == quiere, vivo.registrado { continue }
            vivos[c]?.quitar()
            vivos[c] = AtajoGlobal(quiere) { [weak self] in self?.disparar(c) }
            if vivos[c] == nil { fallan.insert(c) }
        }
        var fallanRegiones: Set<UUID> = []
        let ids = Set(regiones.map(\.id))
        for (id, vivo) in vivosRegiones where !ids.contains(id) {
            vivo.quitar()
            vivosRegiones[id] = nil
        }
        for r in regiones {
            let quiere = activos && r.esUtil ? r.combinacion : nil
            guard let quiere else {
                vivosRegiones[r.id]?.quitar()
                vivosRegiones[r.id] = nil
                continue
            }
            guard conCarbon else { continue }
            if let vivo = vivosRegiones[r.id], vivo.combinacion == quiere, vivo.registrado { continue }
            vivosRegiones[r.id]?.quitar()
            let id = r.id
            vivosRegiones[id] = AtajoGlobal(quiere) { [weak self] in self?.dispararRegion(id) }
            if vivosRegiones[id] == nil { fallanRegiones.insert(id) }
        }
        // Mientras se pausa no se sabe si fallarian: se queda lo de antes.
        guard activos else { return }
        if fallan != fallidos { fallidos = fallan }
        if fallanRegiones != regionesFallidas { regionesFallidas = fallanRegiones }
    }

    private func dispararRegion(_ id: UUID) {
        guard !frenteIgnorado(), let r = regiones.first(where: { $0.id == id }) else { return }
        alCapturarRegion?(r)
    }

    // MARK: Guardar y leer

    private func leer() {
        var e = EnlacesAtajos()
        var raros: [String] = []
        if let tabla = defaults.dictionary(forKey: GestorAtajos.claveComandos) as? [String: String] {
            raros = e.aplicar(tabla: tabla)
        } else if defaults.object(forKey: GestorAtajos.claveViejaTecla) != nil,
                  defaults.object(forKey: GestorAtajos.claveViejaModificadores) != nil {
            // El atajo de capturar de antes (solo se podia cambiar ese).
            let vieja = AtajoGlobal.Combinacion(
                tecla: UInt32(truncatingIfNeeded: defaults.integer(forKey: GestorAtajos.claveViejaTecla)),
                modificadores: UInt32(truncatingIfNeeded: defaults.integer(forKey: GestorAtajos.claveViejaModificadores)))
            if AtajoGlobal.Combinacion.teclaValida(vieja.tecla), vieja.tieneModificadorFuerte {
                e.poner(.capturarRegion, vieja)
            }
        }
        // Dos con el mismo atajo: el segundo se queda sin el (se dice).
        while let par = e.choque() {
            let (a, b) = par
            raros.append("\(b.nombre) tenía el mismo atajo que \(a.nombre)")
            e.poner(b, nil)
        }
        enlaces = e
        noEntendidos = raros
        if let datos = defaults.data(forKey: GestorAtajos.claveRegiones),
           let leidas = try? JSONDecoder().decode([RegionGuardada].self, from: datos) {
            regiones = leidas
        }
        ignorados = defaults.stringArray(forKey: GestorAtajos.claveIgnorar) ?? []
    }

    private func guardarComandos() {
        let tabla = enlaces.tabla
        if tabla.isEmpty {
            defaults.removeObject(forKey: GestorAtajos.claveComandos)
        } else {
            defaults.set(tabla, forKey: GestorAtajos.claveComandos)
        }
        defaults.removeObject(forKey: GestorAtajos.claveViejaTecla)
        defaults.removeObject(forKey: GestorAtajos.claveViejaModificadores)
    }

    private func guardarRegiones() {
        if regiones.isEmpty {
            defaults.removeObject(forKey: GestorAtajos.claveRegiones)
        } else if let datos = try? JSONEncoder().encode(regiones) {
            defaults.set(datos, forKey: GestorAtajos.claveRegiones)
        }
    }
}
