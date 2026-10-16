// **Anotar encima de la zona elegida con el lienzo de verdad**: la misma
// barra de herramientas y el mismo panel de estilo que el lienzo
// (`Lienzo/BarraHerramientasLienzo.swift`, `BarraEstiloLienzo.swift`), como
// en Windows, donde la caja de dibujo es una sola para todos los sitios
// donde se dibuja (`caja_dibujo.rs`).
//
// Como va:
// - al elegir la zona nace un `EditorLienzo` sobre un `.excalidraw` de una
//   carpeta temporal, con el recorte como FONDO fijo (`FondoLienzo`) del
//   tamano de la zona en puntos;
// - su vista (`VistaEditorLienzoNS`) se pone justo encima de la zona con
//   la camara quieta (el mundo (0, 0) en la esquina, al 100 %): lo dibujado
//   cae encima de lo que tiene debajo;
// - mientras no se coja una herramienta de dibujo y no haya nada dibujado,
//   la vista deja pasar el raton a la captura (arrastrar elige otra zona);
// - lo que sale (copiar, pinear, guardar, al chat...) es la hoja pintada
//   con el pintor de exportar del lienzo (`PintorDeHojas`) a la escala de
//   la foto: el recorte pixel a pixel con lo dibujado encima. Sin nada
//   dibujado sale el recorte tal cual (cero copias).
//
// 1-5 siguen siendo las teclas de anotar de la captura de Windows (lapiz,
// flecha, rectangulo, texto y mosaico); las letras del lienzo eligen las
// demas mientras se anota.

import AppKit
import PixPinCore

/// Las cinco herramientas de la captura de Windows, con su tecla (1-5), y
/// la del lienzo que hace lo mismo.
public enum HerramientaAnotar: Int, CaseIterable, Sendable {
    case lapiz = 1, flecha, rectangulo, texto, mosaico

    /// La herramienta del lienzo.
    public var delLienzo: String {
        switch self {
        case .lapiz: "lapiz"
        case .flecha: "flecha"
        case .rectangulo: "rectangulo"
        case .texto: "texto"
        case .mosaico: "mosaico"
        }
    }

    /// La herramienta de una tecla (`1`...`5`).
    public static func deTecla(_ c: String) -> HerramientaAnotar? {
        guard let n = Int(c) else { return nil }
        return HerramientaAnotar(rawValue: n)
    }
}

/// El lienzo encima de una zona de la captura.
@MainActor
final class AnotadorCaptura {
    let modelo: ModeloEditorLienzo
    let vista: VistaEditorLienzoNS
    /// La que se pone en la captura: la vista del lienzo dentro de un marco
    /// que deja pasar el raton mientras no se anota.
    let marco: MarcoAnotador
    /// La zona en puntos de la vista de la captura (origen abajo).
    let zona: CGRect
    private var editor: EditorLienzo { modelo.editor }

    /// El color de partida: el rojo, como el primero de la captura de
    /// Windows (sobre una captura el negro casi no se ve).
    static var colorDePartida: ColorEstilo { OpcionesEstiloLienzo.trazos[1].valor }

    /// Crea el lienzo para `recorte` (los pixeles de la zona) en `carpeta`.
    init(recorte: CGImage, zona: CGRect, carpeta: URL) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let ruta = carpeta.appendingPathComponent("anotacion-\(UUID().uuidString).excalidraw")
        let editor = try EditorLienzo.deFichero(ruta: ruta.path, crear: true)
        let fondo = FondoLienzo(imagen: recorte, tamano: zona.size)
        modelo = ModeloEditorLienzo(editor: editor, titulo: "Captura", fondo: fondo)
        // Sin herramienta de dibujo hasta que se coja una: el raton sigue
        // eligiendo la zona.
        modelo.elegir("seleccion")
        modelo.cambiarEstilo(.trazo(color: AnotadorCaptura.colorDePartida))
        // Trazo limpio (el «arquitecto» de Excalidraw): sobre una captura se
        // senala, no se boceta.
        modelo.cambiarEstilo(.rugosidad(valor: 0))
        self.zona = zona
        vista = VistaEditorLienzoNS(modelo: modelo)
        vista.camaraFija = true
        marco = MarcoAnotador(frame: zona)
        marco.autoresizingMask = []
        vista.frame = marco.bounds
        vista.autoresizingMask = [.width, .height]
        marco.addSubview(vista)
        marco.anotador = self
    }

    /// Si el raton es del lienzo: hay una herramienta de dibujo cogida o
    /// hay algo dibujado (para elegirlo, moverlo o borrarlo con ⌫).
    var activo: Bool {
        modelo.herramienta != "seleccion" || editor.cuantosElementos() > 0
    }

    /// Si hay algo dibujado (o un texto a medias).
    var anotado: Bool { editor.cuantosElementos() > 0 || editor.escribiendo() }

    /// Se esta escribiendo un texto.
    var escribiendo: Bool { editor.escribiendo() }

    /// Hay algo elegido en el lienzo.
    var hayElegidos: Bool { editor.cuantosElegidos() > 0 }

    /// Coge una herramienta del lienzo (la misma otra vez, como en la
    /// captura de Windows, la suelta y vuelve a elegir).
    func tomar(_ id: String) {
        modelo.desplegado = nil
        modelo.elegir(modelo.herramienta == id ? "seleccion" : id)
        marco.window?.invalidateCursorRects(for: vista)
    }

    @discardableResult
    func deshacer() -> Bool {
        guard editor.puedeDeshacer() || editor.escribiendo() else { return false }
        modelo.deshacer()
        return true
    }

    @discardableResult
    func rehacer() -> Bool {
        let antes = editor.version()
        modelo.rehacer()
        return editor.version() != antes
    }

    /// **La zona con lo dibujado**, a `escala` pixeles por punto. `nil` si
    /// no hay nada dibujado (entonces vale el recorte tal cual).
    func imagen(escala: CGFloat) -> CGImage? {
        _ = editor.terminarTexto()
        guard editor.cuantosElementos() > 0 else { return nil }
        let caja = CGRect(origin: .zero, size: zona.size)
        return PintorDeHojas.imagen(editor.plano(), caja: caja, escala: escala, transparente: false,
                                    tapados: modelo.tapados, version: editor.version(),
                                    fotos: { [weak self] in self?.modelo.foto($0) })
    }

    /// Se quita de la captura (sin guardar nada: el fichero es temporal).
    func quitar() {
        modelo.desplegado = nil
        marco.anotador = nil
        marco.removeFromSuperview()
    }
}

/// El marco del lienzo encima de la zona: deja pasar el raton a la captura
/// mientras no se anota.
final class MarcoAnotador: NSView {
    weak var anotador: AnotadorCaptura?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let anotador, anotador.activo else { return nil }
        return super.hitTest(point)
    }
}
