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

    /// Las dos vistas que van encima del documento.
    func montar(en contenedor: NSView, modelo lector: ModeloLector) {
        let barra = NSHostingView(rootView: BarraDeTinta(lector: lector, herramientas: self))
        let panel = NSHostingView(rootView: PanelDeTinta(lector: lector, herramientas: self))
        for v in [barra, panel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        NSLayoutConstraint.activate([
            barra.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            barra.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: MedidasBarraLienzo.distanciaBorde),
            panel.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor, constant: MedidasBarraLienzo.distanciaBorde),
            panel.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: MedidasBarraLienzo.yPanel),
        ])
    }
}

private struct BarraDeTinta: View {
    @ObservedObject var lector: ModeloLector
    let herramientas: HerramientasDeTinta

    var body: some View {
        if lector.anotando, let m = herramientas.modelo {
            BarraHerramientasLienzo(modelo: m, botones: BotonBarraLienzo.barraDelLector,
                                    corte: BotonBarraLienzo.barraDelLector.count)
        }
    }
}

private struct PanelDeTinta: View {
    @ObservedObject var lector: ModeloLector
    let herramientas: HerramientasDeTinta

    var body: some View {
        if lector.anotando, let m = herramientas.modelo { PanelSiDibuja(modelo: m) }
    }
}

private struct PanelSiDibuja: View {
    @ObservedObject var modelo: ModeloEditorLienzo

    var body: some View {
        if !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) { PanelEstiloLienzo(modelo: modelo) }
    }
}
