// **Las herramientas del lienzo encima de un documento** (`lector_tinta.rs`
// de Windows: «la tinta del visor es la misma del editor avanzado, con las
// mismas herramientas»). Al pulsar el lapiz de la barra del pin, arriba en
// medio sale la barra de herramientas del lienzo y, a la izquierda, su panel
// de estilo; mandan sobre la tinta de todas las hojas abiertas del visor
// (un `EditorLienzo` por hoja en el PDF, uno solo en el libro). Sin lo que
// no tiene sentido sobre un documento (`Anfitrion::Lector`).

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class HerramientasDeTinta {
    /// Las tintas abiertas ahora.
    var editores: () -> [EditorLienzo] = { [] }
    /// Elegir una herramienta en el visor (lo hace el visor: abre la tinta,
    /// fija la columna...).
    var elegir: (String) -> Void = { _ in }
    var deshacer: () -> Void = {}
    var rehacer: () -> Void = {}
    var repintar: () -> Void = {}
    /// Los cambios de estilo hechos al editar, para las tintas que se abran despues.
    private var estilos: [CambioDeEstilo] = []
    private let nucleo: Nucleo?

    init(nucleo: Nucleo?) { self.nucleo = nucleo }

    /// La barra y el panel: un editor de mentira que no se guarda; lo que se
    /// pulsa en el va a las tintas de verdad.
    private(set) lazy var modelo: ModeloEditorLienzo? = {
        let ruta = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-herramientas-\(UUID().uuidString).excalidraw").path
        guard let ed = try? EditorLienzo.deFichero(ruta: ruta, crear: true) else { return nil }
        let m = ModeloEditorLienzo(editor: ed, nucleo: nucleo, titulo: "")
        m.alElegir = { [weak self] h in self?.elegir(h) }
        m.alCambiarEstilo = { [weak self] c in
            guard let self else { return }
            self.estilos.append(c)
            if self.estilos.count > 64 { self.estilos.removeFirst() }
            for ed in self.editores() { _ = ed.cambiarEstilo(cambio: c) }
            self.repintar()
        }
        m.alDeshacer = { [weak self] in self?.deshacer() }
        m.alRehacer = { [weak self] in self?.rehacer() }
        return m
    }()

    /// Pone en `ed` la herramienta y el estilo de ahora (`color`: el de las
    /// teclas P/H/E mientras no se haya tocado el panel).
    func aplicar(a ed: EditorLienzo, herramienta h: String, color: ColorTinta) {
        try? ed.herramienta(nombre: h)
        if estilos.isEmpty {
            ed.tintaColor(r: color.r, g: color.g, b: color.b, a: 1)
        } else {
            for c in estilos { _ = ed.cambiarEstilo(cambio: c) }
        }
    }

    /// La barra ensena la herramienta elegida con una tecla.
    func ensenar(_ h: String) {
        guard h != "leer", let m = modelo, m.herramienta != h else { return }
        try? m.editor.herramienta(nombre: h)
        m.refrescarBarra()
    }

    /// Con que se empieza al pulsar el lapiz: la ultima, o el lapiz.
    var alEmpezar: String {
        let h = modelo?.herramienta ?? "lapiz"
        return h.isEmpty || h == "seleccion" ? "lapiz" : h
    }

    /// **Escribir un texto de la tinta** (la herramienta de texto, como en el
    /// lienzo): mientras una hoja esta escribiendo, el teclado es suyo.
    /// `true` si la tecla era para ella.
    func teclaAlTexto(_ e: NSEvent) -> Bool {
        guard let ed = editores().first(where: { $0.escribiendo() }) else { return false }
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function, .shift])
        let nombre: String?
        switch e.keyCode {
        case 51: nombre = "retroceso"
        case 117: nombre = "suprimir"
        case 123: nombre = "izquierda"
        case 124: nombre = "derecha"
        case 115: nombre = "inicio"
        case 119: nombre = "fin"
        case 36, 76: nombre = "entrar"
        case 53: nombre = "escape"
        default: nombre = nil
        }
        if let nombre {
            if ed.tecla(nombre: nombre) { repintar() }
            return true
        }
        // Con ⌘ son atajos (⌘Z, ⌘C…): no son letras.
        guard !m.contains(.command), !m.contains(.control), let t = e.characters, !t.isEmpty else { return false }
        if ed.teclear(texto: t) { repintar() }
        return true
    }

    /// Las dos vistas que van encima del documento.
    func montar(en contenedor: NSView, modelo lector: ModeloLector) {
        let barra = NSHostingView(rootView: BarraDeTinta(lector: lector, herramientas: self))
        let panel = NSHostingView(rootView: PanelDeTinta(lector: lector, herramientas: self))
        for v in [barra, panel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        let arriba = barra.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: MedidasBarraLienzo.distanciaBorde)
        let arribaPanel = panel.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: MedidasBarraLienzo.yPanel)
        NSLayoutConstraint.activate([
            barra.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            barra.widthAnchor.constraint(lessThanOrEqualTo: contenedor.widthAnchor, constant: -16),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: contenedor.bottomAnchor, constant: -8),
            arriba,
            panel.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor, constant: MedidasBarraLienzo.distanciaBorde),
            arribaPanel,
        ])
        // Si la barra del pin no cabe encima de la ventana (pegada arriba de
        // la pantalla o a pantalla completa) va dentro: las herramientas
        // bajan lo que mide para que no las tape.
        let colocar: @MainActor () -> Void = { [weak contenedor] in
            guard let v = contenedor?.window, let pantalla = v.screen else { return }
            let dentro = v.frame.maxY + BarraFlotante.separacion + BarraFlotante.alto > pantalla.visibleFrame.maxY
            let baja: CGFloat = dentro ? BarraFlotante.alto + BarraFlotante.separacion : 0
            arriba.constant = MedidasBarraLienzo.distanciaBorde + baja
            arribaPanel.constant = MedidasBarraLienzo.yPanel + baja
        }
        for n in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                  NSWindow.didExitFullScreenNotification, NSWindow.didEnterFullScreenNotification] {
            vigias.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak contenedor] aviso in
                guard (aviso.object as? NSWindow) === contenedor?.window else { return }
                MainActor.assumeIsolated { colocar() }
            })
        }
        DispatchQueue.main.async { colocar() }
    }

    private var vigias: [NSObjectProtocol] = []
}

private struct BarraDeTinta: View {
    @ObservedObject var lector: ModeloLector
    let herramientas: HerramientasDeTinta

    var body: some View {
        if lector.anotando, let m = herramientas.modelo {
            // En una ventana estrecha no se corta: se desliza de lado.
            let barra = BarraHerramientasLienzo(modelo: m, botones: BotonBarraLienzo.barraDelLector,
                                                corte: BotonBarraLienzo.barraDelLector.count)
            ViewThatFits(in: .horizontal) {
                barra
                ScrollView(.horizontal, showsIndicators: false) { barra.padding(.horizontal, 2) }
            }
        }
    }
}

private struct PanelDeTinta: View {
    @ObservedObject var lector: ModeloLector
    let herramientas: HerramientasDeTinta

    var body: some View {
        if lector.anotando, let m = herramientas.modelo {
            // Si no cabe a lo alto, se desliza en vez de cortarse.
            ViewThatFits(in: .vertical) {
                PanelSiDibuja(modelo: m)
                ScrollView(.vertical, showsIndicators: false) { PanelSiDibuja(modelo: m) }
            }
        }
    }
}

private struct PanelSiDibuja: View {
    @ObservedObject var modelo: ModeloEditorLienzo

    var body: some View {
        if !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) { PanelEstiloLienzo(modelo: modelo) }
    }
}
