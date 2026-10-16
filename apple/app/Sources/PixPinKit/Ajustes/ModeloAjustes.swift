// Lo que se guarda de los Ajustes, cada cosa en su sitio:
//
// - En `pixpinmax.toml` (el MISMO fichero de Windows, por el nucleo de Rust
//   `Nucleo.ajustes`/`guardarAjustes`), lo que vale en los dos sistemas:
//   `valores` (idioma, captura, GIF, caducidad, sincronizar, voz y
//   asistente) y `pdf` (`[pdf]`, por `ajustesPdf`).
// - En este Mac: el tema (UserDefaults), los atajos (`GestorAtajos`) y
//   «Abrir al iniciar sesion» (`SMAppService.mainApp`, que es la verdad: si
//   el usuario lo quita en Ajustes del Sistema, aqui se ve quitado).
//
// Como en Windows, cada cambio se puede deshacer (⌘Z, hasta 100 pasos) y
// cada ajuste sabe si esta como de fabrica (el punto azul) y volver a el.
//
// Leer y escribir el TOML va fuera del hilo principal (§4bis.3).

import AppKit
import Foundation
import PixPinCore
import ServiceManagement

/// El aspecto de la app. De fabrica sigue al sistema.
public enum Tema: String, CaseIterable, Identifiable, Sendable {
    case sistema
    case claro
    case oscuro

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .sistema: return "Como el sistema"
        case .claro: return "Claro"
        case .oscuro: return "Oscuro"
        }
    }

    static let clave = "tema"

    public static func guardado(_ d: UserDefaults = .standard) -> Tema {
        d.string(forKey: clave).flatMap(Tema.init(rawValue:)) ?? .sistema
    }

    public func guardar(_ d: UserDefaults = .standard) {
        if self == .sistema { d.removeObject(forKey: Tema.clave) } else { d.set(rawValue, forKey: Tema.clave) }
    }

    /// `nil` sigue al sistema (y cambia solo con el).
    public var apariencia: NSAppearance? {
        switch self {
        case .sistema: return nil
        case .claro: return NSAppearance(named: .aqua)
        case .oscuro: return NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    public func aplicar() {
        NSApplication.shared.appearance = apariencia
    }
}

@MainActor
public final class ModeloAjustes: ObservableObject {
    /// Lo de `pixpinmax.toml` (los de fabrica hasta `cargar`).
    @Published public private(set) var valores: AjustesMac
    /// Los de fabrica de Windows (`Ajustes::default`).
    public let fabrica: AjustesMac
    /// `[pdf]` de `pixpinmax.toml` (`nil` hasta `cargar`).
    @Published public private(set) var pdf: AjustesPdf?
    @Published public private(set) var abrirAlIniciar = false
    /// «Abrir al iniciar sesion» espera el visto bueno en Ajustes del Sistema.
    @Published public private(set) var esperaAprobacion = false
    @Published public var tema: Tema {
        didSet {
            tema.guardar(defaults)
            tema.aplicar()
        }
    }
    @Published public private(set) var error: String?
    @Published public private(set) var cargado = false
    /// Lo que «Deshacer» devuelve, el mas reciente al final.
    @Published public private(set) var historial: [Paso] = []

    /// Un paso de «Deshacer»: como estaba antes de un cambio.
    public enum Paso: Equatable {
        case toml(AjustesMac)
        case pdf(AjustesPdf)
    }

    /// Cuantos pasos guarda «Deshacer» (los de Windows).
    public static let pasosDeHistorial = 100

    /// Los de fabrica de `[pdf]` (`Pdf::default` de Windows).
    public static let pdfDeFabrica = AjustesPdf(aligerarAlEntrar: true, nivel: .equilibrado)

    public let nucleo: Nucleo
    /// La sincronizacion de la app, para encender o apagar la automatica.
    public weak var sincro: Sincronizador?
    private let defaults: UserDefaults

    public init(nucleo: Nucleo, sincro: Sincronizador? = nil, defaults: UserDefaults = .standard) {
        self.nucleo = nucleo
        self.sincro = sincro
        self.defaults = defaults
        fabrica = nucleo.ajustesDeFabrica()
        valores = fabrica
        tema = Tema.guardado(defaults)
        leerAbrirAlIniciar()
    }

    /// La carpeta de datos (la de `proyectos/`, `sincro/`, `pixpinmax.toml`).
    public var carpetaDatos: URL { URL(fileURLWithPath: nucleo.raiz(), isDirectory: true) }

    /// `pixpinmax.toml`.
    public var ficheroAjustes: String { nucleo.rutaAjustes() }

    /// La carpeta de las capturas (`<datos>/capturas`).
    public var carpetaCapturas: URL { URL(fileURLWithPath: nucleo.carpetaCapturas(), isDirectory: true) }

    // Lo de antes, que siguen usando otros sitios y las pruebas.
    public var diasCaducidad: Int { Int(valores.diasCaducidad) }
    public var sincroAutomatica: Bool { valores.sincroAutomatica }

    /// Lee el TOML y pasa la sincronizacion sola al `Sincronizador`.
    public func cargar() async {
        let nucleo = self.nucleo
        let r = await Task.detached(priority: .utility) { () -> Result<(AjustesMac, AjustesPdf), Error> in
            do { return .success((try nucleo.ajustes(), try nucleo.ajustesPdf())) } catch { return .failure(error) }
        }.value
        switch r {
        case let .success((a, p)):
            valores = a
            pdf = p
            sincro?.automatica = a.sincroAutomatica
            error = nil
        case let .failure(e):
            error = "No se pudo leer pixpinmax.toml: \(ModeloAjustes.texto(de: e))"
        }
        leerAbrirAlIniciar()
        cargado = true
    }

    /// **Cambia lo del TOML** y lo guarda (en la cola de guardados). Lo de
    /// antes queda para «Deshacer».
    public func cambiar(_ cambio: (inout AjustesMac) -> Void) {
        var nuevo = valores
        cambio(&nuevo)
        guard nuevo != valores else { return }
        apuntar(.toml(valores))
        poner(nuevo)
    }

    /// Cambia `[pdf]` y lo guarda.
    public func cambiarPdf(_ cambio: (inout AjustesPdf) -> Void) {
        let antes = pdf ?? ModeloAjustes.pdfDeFabrica
        var nuevo = antes
        cambio(&nuevo)
        guard nuevo != antes else { return }
        apuntar(.pdf(antes))
        ponerPdf(nuevo)
    }

    /// Deshace el ultimo cambio (⌘Z).
    public func deshacer() {
        guard let paso = historial.popLast() else { return }
        switch paso {
        case let .toml(a): poner(a)
        case let .pdf(p): ponerPdf(p)
        }
    }

    public var sePuedeDeshacer: Bool { !historial.isEmpty }

    private func apuntar(_ paso: Paso) {
        historial.append(paso)
        if historial.count > ModeloAjustes.pasosDeHistorial {
            historial.removeFirst(historial.count - ModeloAjustes.pasosDeHistorial)
        }
    }

    private func poner(_ nuevo: AjustesMac) {
        let antes = valores
        valores = nuevo
        sincro?.automatica = nuevo.sincroAutomatica
        if nuevo.idioma != antes.idioma {
            ModeloAjustes.aplicar(idioma: nuevo.idioma, en: defaults)
        }
        let guardado = programarGuardado()
        // La presencia la abre o la cierra el `Sincronizador` al releer el
        // TOML: despues de escribirlo.
        if nuevo.sincroPresencia != antes.sincroPresencia, let sincro {
            Task { [weak sincro] in
                await guardado.value
                await sincro?.refrescar()
            }
        }
    }

    private func ponerPdf(_ nuevo: AjustesPdf) {
        pdf = nuevo
        let previo = ultimoGuardado
        let nucleo = self.nucleo
        ultimoGuardado = Task { [weak self] in
            await previo?.value
            let fallo = await Task.detached(priority: .utility) { () -> String? in
                do { try nucleo.guardarAjustesPdf(nuevos: nuevo); return nil } catch { return ModeloAjustes.texto(de: error) }
            }.value
            self?.error = fallo.map { "No se pudo guardar: \($0)" }
        }
    }

    /// El idioma de la app (`AppleLanguages` de este programa): vale desde el
    /// proximo arranque, como en Windows. «sistema» lo deja en el del Mac.
    nonisolated static func aplicar(idioma: String, en defaults: UserDefaults) {
        switch idioma {
        case "es", "en": defaults.set([idioma], forKey: "AppleLanguages")
        default: defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    public func fijar(diasCaducidad dias: Int) {
        let d = UInt32(max(0, min(400, dias)))
        cambiar { $0.diasCaducidad = d }
    }

    public func fijar(sincroAutomatica s: Bool) {
        cambiar { $0.sincroAutomatica = s }
    }

    /// El ultimo guardado en marcha: los guardados van **uno detras de
    /// otro** (dos escrituras a la vez de `pixpinmax.toml` se pisaban, y
    /// quien leyera en medio veia el fichero a medias).
    private var ultimoGuardado: Task<Void, Never>?

    /// Pone un guardado en la cola, ya mismo (en orden con los cambios).
    @discardableResult
    private func programarGuardado() -> Task<Void, Never> {
        let previo = ultimoGuardado
        let t = Task { [weak self] in
            await previo?.value
            await self?.guardarAhora()
        }
        ultimoGuardado = t
        return t
    }

    /// Escribe lo de este modelo en `pixpinmax.toml`, conservando lo demas
    /// (despues de los guardados que ya esperaban).
    public func guardar() async {
        await programarGuardado().value
    }

    private func guardarAhora() async {
        let nuevos = valores
        let nucleo = self.nucleo
        let fallo = await Task.detached(priority: .utility) { () -> String? in
            do {
                try nucleo.guardarAjustes(nuevos: nuevos)
                return nil
            } catch {
                return ModeloAjustes.texto(de: error)
            }
        }.value
        if let fallo {
            error = "No se pudo guardar: \(fallo)"
        } else {
            error = nil
        }
    }

    /// Abre `pixpinmax.toml` en el editor de texto (lo crea si aun no esta,
    /// con lo de ahora).
    public func abrirFicheroAjustes() async {
        let url = URL(fileURLWithPath: ficheroAjustes)
        if !FileManager.default.fileExists(atPath: url.path) { await guardar() }
        let ws = NSWorkspace.shared
        if ws.urlForApplication(toOpen: url) != nil {
            ws.open(url)
        } else if let editor = ws.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            ws.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            ws.activateFileViewerSelecting([url])
        }
    }

    public func mostrarCarpetaCapturas() {
        try? FileManager.default.createDirectory(at: carpetaCapturas, withIntermediateDirectories: true)
        NSWorkspace.shared.open(carpetaCapturas)
    }

    // MARK: Abrir al iniciar sesion

    private func leerAbrirAlIniciar() {
        let estado = SMAppService.mainApp.status
        abrirAlIniciar = estado == .enabled
        esperaAprobacion = estado == .requiresApproval
    }

    public func fijar(abrirAlIniciar quiere: Bool) {
        do {
            if quiere {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "No se pudo cambiar «Abrir al iniciar sesión»: \(error.localizedDescription)"
        }
        leerAbrirAlIniciar()
    }

    /// Abre Ajustes del Sistema > General > Elementos de inicio.
    public func abrirElementosDeInicio() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public func mostrarCarpetaEnFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([carpetaDatos])
    }

    nonisolated static func texto(de error: Error) -> String {
        if let e = error as? ErrorNucleo {
            switch e {
            case let .Disco(d), let .Lienzo(d), let .Sincro(d), let .Argumento(d), let .Ajustes(d), let .Asistente(d):
                return d
            case let .NoExiste(que):
                return "no existe: \(que)"
            }
        }
        return error.localizedDescription
    }
}
