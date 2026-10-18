// **Lo que sabe el panel de la barra de menus** (el `Panel` de
// `centro_bandeja.rs`): lo buscado, si se eligen favoritos, los favoritos,
// los interruptores, las ultimas capturas y los numeros de Tareas y
// Lecciones. La vista (`VistaBandeja`) solo lo ensena.
//
// No hace las acciones: las pide (`alPedir`) a quien tiene el panel
// (`IconoBandeja`), que lo cierra si toca y las hace por el mismo camino que
// el menu y el atajo. Lo unico que hace por su cuenta es lo de sus
// miniaturas (pinear, copiar, borrar con «Deshacer»), como la galeria.

import AppKit
import Combine
import PixPinCore
import SwiftUI

@MainActor
public final class ModeloBandeja: ObservableObject {
    // MARK: Lo buscado y los favoritos

    @Published public var consulta = "" {
        didSet { if consulta != oldValue { elegida = 0 } }
    }
    /// Eligiendo favoritos: la lista entera, con su marca.
    @Published public var editando = false
    /// La fila elegida con las flechas (en la lista).
    @Published public var elegida = 0
    @Published public private(set) var favoritos: [AccionBandeja] = []

    // MARK: Lo que se ensena

    @Published public private(set) var capturas: [CapturaGaleria] = []
    @Published public private(set) var minis: [String: NSImage] = [:]
    /// La miniatura con el raton encima (sus botones salen solo en ella).
    @Published public var encima: Int?
    /// Pendientes de las listas de entrada, y lecciones para repasar hoy.
    @Published public private(set) var tareas: Int?
    @Published public private(set) var lecciones: Int?
    @Published public private(set) var aLaVista = 0
    @Published public private(set) var ocultos = false
    @Published public private(set) var pasantes = false
    @Published public private(set) var silenciados = false
    @Published public private(set) var ultimaSincro: Int64 = 0
    @Published public private(set) var sincronizando = false
    /// El aviso de abajo, y si lleva «Deshacer».
    @Published public private(set) var aviso: String?
    @Published public private(set) var puedeDeshacer = false
    /// Lo que mide lo de dentro (para que la ventana se ajuste).
    @Published public var altoContenido: CGFloat = 0

    let atajos: GestorAtajos
    let nucleo: Nucleo?
    let sincro: Sincronizador?
    /// Pide una accion a quien tiene el panel.
    var alPedir: ((AccionBandeja) -> Void)?
    /// Cierra el panel (Esc al final, abrir una captura).
    var alCerrar: (() -> Void)?

    private var borradas: [CapturaBorrada] = []
    private var quitarAviso: Task<Void, Never>?
    private var vigias: Set<AnyCancellable> = []

    public init(atajos: GestorAtajos, nucleo: Nucleo?, sincro: Sincronizador?) {
        self.atajos = atajos
        self.nucleo = nucleo
        self.sincro = sincro
        favoritos = ReglasBandeja.favoritos(de: AccionBandeja.deFabrica)
        // La sincronizacion y los atajos cambian con el panel abierto.
        sincro?.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.leerSincro() }
        }.store(in: &vigias)
        atajos.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.leerInterruptores() }
        }.store(in: &vigias)
    }

    // MARK: Al abrir

    /// Al abrir el panel: todo al dia y lo buscado de antes, fuera.
    public func alAbrir() {
        consulta = ""
        editando = false
        elegida = 0
        encima = nil
        aviso = nil
        puedeDeshacer = false
        if let ruta = rutaAjustes {
            favoritos = ReglasBandeja.favoritos(de: FavoritosBandeja.leer(ruta))
        }
        leerInterruptores()
        leerSincro()
        Task { await cargar() }
    }

    var rutaAjustes: URL? { nucleo.map { URL(fileURLWithPath: $0.rutaAjustes()) } }

    func leerInterruptores() {
        let p = GestorPines.compartido
        aLaVista = p.aLaVista
        ocultos = p.todosOcultos
        pasantes = p.mayoriaPasante
        silenciados = atajos.silenciados
    }

    private func leerSincro() {
        ultimaSincro = sincro?.filas.map(\.ultimaVez).max() ?? 0
        sincronizando = sincro?.ocupado ?? false
    }

    /// Las capturas, sus miniaturas y los numeros, fuera del hilo principal.
    func cargar() async {
        guard let nucleo else { return }
        let desfase = desfaseLocalMs()
        let (pagina, tareas, lecciones) = await Task.detached(priority: .userInitiated) {
            () -> ([CapturaGaleria], Int?, Int?) in
            let p = (try? nucleo.galeria(desde: 0, cuantos: UInt32(ModeloBandeja.cuantasCapturas), dias: 0,
                                         desfaseMs: desfase))?.capturas ?? []
            let t = (try? nucleo.tareas(desfaseMs: desfase)).map { $0.filter(\.esInbox).reduce(0) { $0 + Int($1.pendientes) } }
            let l = (try? nucleo.lecciones(filtro: FiltroLecciones(texto: "", etiqueta: nil, soloParaRepasar: true),
                                           desde: 0, cuantas: 0)).map { Int($0.paraRepasar) }
            return (p, t, l)
        }.value
        capturas = pagina
        self.tareas = tareas
        self.lecciones = lecciones
        for c in pagina where minis[c.ruta] == nil && !ModeloBandeja.esVideo(c.ruta) {
            let url = URL(fileURLWithPath: c.ruta)
            if let img = await Miniatura.fueraDelPrincipal({ Miniatura.de(url: url, ladoMaximo: 256) }) {
                minis[c.ruta] = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
            }
        }
    }

    public static let cuantasCapturas = 4

    nonisolated static func esVideo(_ ruta: String) -> Bool {
        TiposQueAbre.videos.contains(URL(fileURLWithPath: ruta).pathExtension.lowercased())
    }

    // MARK: La lista (buscar y elegir favoritos)

    /// Las acciones que este Mac sabe hacer, con su titulo.
    var titulos: [(AccionBandeja, String)] {
        AccionBandeja.todas(disponible: { [atajos] in atajos.disponible($0) }).map { ($0, $0.titulo) }
    }

    /// Lo que sale en la lista: lo encontrado o, eligiendo favoritos sin
    /// buscar nada, todas.
    public var filas: [AccionBandeja] {
        if editando, consulta.trimmingCharacters(in: .whitespaces).isEmpty { return titulos.map(\.0) }
        return ReglasBandeja.buscar(consulta, en: titulos)
    }

    /// Hay lista (buscando o eligiendo) en vez del panel entero.
    public var enLista: Bool { editando || !consulta.trimmingCharacters(in: .whitespaces).isEmpty }

    /// El atajo de un comando, como lo ensena el Mac («⌃⌥X»).
    public func chapita(_ a: AccionBandeja) -> String? {
        guard case let .comando(c) = a else { return nil }
        return atajos.atajoActivo(de: c)?.descripcion
    }

    // MARK: Lo que se pulsa

    public func pedir(_ a: AccionBandeja) {
        alPedir?(a)
        // Un interruptor deja el panel abierto: se ve el cambio ahi mismo.
        if !a.cierraElPanel { DispatchQueue.main.async { [weak self] in self?.leerInterruptores() } }
    }

    public func empezarAEditar() {
        editando = true
        consulta = ""
        elegida = 0
    }

    public func terminarDeEditar() {
        editando = false
        consulta = ""
    }

    /// Intro o clic en una fila: hacerla o, eligiendo favoritos, marcarla.
    public func activarFila(_ i: Int) {
        let f = filas
        guard f.indices.contains(i) else { return }
        elegida = i
        guard editando else { return pedir(f[i]) }
        if ReglasBandeja.alternarFavorito(&favoritos, f[i]) {
            guardarFavoritos()
        } else {
            avisar("Ya hay \(AccionBandeja.tope) favoritos: quita uno antes.")
        }
    }

    private func guardarFavoritos() {
        guard let ruta = rutaAjustes else { return }
        do { try FavoritosBandeja.guardar(ruta, favoritos.map(\.nombre)) } catch { avisar("No se pudo: \(error.localizedDescription)") }
    }

    // MARK: El teclado (solo con el panel delante)

    /// Esc: borra lo buscado, sale de elegir favoritos y al final cierra.
    public func escape() {
        if !consulta.isEmpty {
            consulta = ""
        } else if editando {
            editando = false
        } else {
            alCerrar?()
        }
    }

    public func intro() {
        if enLista { activarFila(elegida) } else { pedir(.comando(.capturarRegion)) }
    }

    public func mover(_ paso: Int) {
        let n = filas.count
        guard enLista, n > 0 else { return }
        elegida = min(max(elegida + paso, 0), n - 1)
    }

    // MARK: Las miniaturas

    public func url(_ i: Int) -> URL? {
        capturas.indices.contains(i) ? URL(fileURLWithPath: capturas[i].ruta) : nil
    }

    public func abrirCaptura(_ i: Int) {
        guard let u = url(i) else { return }
        NSWorkspace.shared.open(u)
        alCerrar?()
    }

    /// Por el mismo camino que «Abrir con PixPin»: un pin.
    public func pinearCaptura(_ i: Int) {
        guard let u = url(i) else { return }
        if GestorPines.compartido.pinear(fichero: u) { alCerrar?() } else { avisar("No se pudo: no es una imagen") }
    }

    public func copiarCaptura(_ i: Int) {
        guard let u = url(i), let img = NSImage(contentsOf: u) else { return avisar("No se pudo: no se lee") }
        let p = NSPasteboard.general
        p.clearContents()
        p.writeObjects([img])
        avisar("Copiada")
    }

    /// A la papelera de PixPin, con «Deshacer» (no se pregunta antes).
    public func borrarCaptura(_ i: Int) {
        guard capturas.indices.contains(i), let nucleo else { return }
        let nombre = capturas[i].nombre
        do {
            borradas = try nucleo.borrarCapturas(nombres: [nombre])
            capturas.remove(at: i)
            encima = nil
            avisar("A la papelera", deshacer: true)
            Task { await cargar() }
        } catch {
            avisar("No se pudo: \(error.localizedDescription)")
        }
    }

    public func deshacer() {
        guard !borradas.isEmpty, let nucleo else { return }
        let b = borradas
        borradas = []
        let vueltas = (try? nucleo.devolverCapturas(borradas: b)) ?? 0
        avisar(vueltas > 0 ? "Devuelta" : "No se pudo: ya no esta en la papelera")
        Task { await cargar() }
    }

    func avisar(_ t: String, deshacer: Bool = false) {
        aviso = t
        puedeDeshacer = deshacer
        quitarAviso?.cancel()
        quitarAviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deshacer ? 8 : 3))
            guard !Task.isCancelled else { return }
            self?.aviso = nil
            self?.puedeDeshacer = false
        }
    }
}
