// La captura con scroll (modo `S`, `scroll.rs` de Windows): se elige la
// zona con la captura, se cierra la superposicion y se fotografia la zona
// REAL una y otra vez mientras baja; cada fotograma se cose con
// `CosidoScroll` y al terminar la pagina entera va al portapapeles y se
// queda como pin (lo mismo que Windows).
//
// - Con el permiso de Accesibilidad, PixPin baja solo: manda la rueda
//   (`CGEvent` de scroll, tres lineas por paso) al centro de la zona y
//   para cuando la pagina deja de moverse. Sin el permiso, baja el usuario
//   con la rueda o el trackpad y PixPin va fotografiando; «Terminar» para.
// - Topes: 20 000 pixeles de alto, 30 s bajando solo (2 min a mano).
// - Rendimiento: un `SCScreenshotManager.captureImage` por paso (solo la
//   zona, a su resolucion), mirado fuera del hilo principal; de cada
//   fotograma se copian solo las filas nuevas y se suelta en el acto.

import AppKit
import ApplicationServices
import ScreenCaptureKit

@MainActor
public final class CapturaConScroll {
    public static let compartida = CapturaConScroll()

    /// Muescas de rueda por paso (`MUESCAS_POR_PASO` de Windows).
    static let lineasPorPaso: Int32 = 3
    /// Pasos sin nada nuevo que dan la pagina por terminada.
    static let quietosParaParar = 3
    static let segundosSolo: Double = 30
    static let segundosAMano: Double = 120

    /// La pagina cosida (para copiarla y pinearla).
    public var alTerminar: ((CGImage, CGFloat) -> Void)?
    public private(set) var enMarcha = false

    private var pedirParar = false
    private var marco: MarcoDeZona?

    public init() {}

    public func parar() { pedirParar = true }

    public func empezar(_ zona: ZonaDeGrabacion) async {
        guard !enMarcha else { return }
        enMarcha = true
        pedirParar = false
        defer {
            enMarcha = false
            marco?.cerrar()
            marco = nil
        }
        let solo = AXIsProcessTrusted()
        marco = MarcoDeZona.abrir(zona: zona, rojo: false,
                                  texto: solo ? "Con scroll: bajando…" : "Con scroll: desplaza hacia abajo",
                                  boton: "Terminar") { [weak self] in self?.parar() }
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let pantalla = contenido.displays.first(where: { $0.displayID == zona.pantalla }) else {
                throw ErrorGrabacion.sinPantalla
            }
            let yo = ProcessInfo.processInfo.processIdentifier
            let propias = contenido.applications.filter { $0.processID == yo }
            let filtro = SCContentFilter(display: pantalla, excludingApplications: propias, exceptingWindows: [])
            let rect = zona.rect.standardized.intersection(CGRect(x: 0, y: 0, width: pantalla.width, height: pantalla.height))
            guard !rect.isNull, rect.width >= 2, rect.height >= 2 else { throw ErrorGrabacion.zonaVacia }
            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = max(Int((rect.width * zona.escala).rounded()), 2)
            config.height = max(Int((rect.height * zona.escala).rounded()), 2)
            config.showsCursor = false
            config.captureResolution = .best

            let bordes = CGDisplayBounds(zona.pantalla)
            let centro = CGPoint(x: bordes.minX + rect.midX, y: bordes.minY + rect.midY)
            if solo { CGWarpMouseCursorPosition(centro) }

            var cosedor: CosidoScroll.Cosedor?
            var quietos = 0
            var anterior: UInt64?
            let inicio = Date()
            let tope = solo ? CapturaConScroll.segundosSolo : CapturaConScroll.segundosAMano
            bucle: while !pedirParar, Date().timeIntervalSince(inicio) < tope {
                let foto = try await SCScreenshotManager.captureImage(contentFilter: filtro, configuration: config)
                let previo = cosedor
                let (nuevo, resultado, firma) = await Task.detached(priority: .userInitiated) {
                    CapturaConScroll.mirar(foto, cosedor: previo)
                }.value
                cosedor = nuevo
                if let firma, firma == anterior {
                    quietos += 1
                } else {
                    switch resultado {
                    case .primero, .anadido: quietos = 0
                    case .sinMovimiento: quietos += 1
                    case .incierto: break
                    case .lleno: break bucle
                    }
                }
                anterior = firma
                // A mano no se para por estar quieto: el usuario puede estar
                // leyendo. Solo, si: la pagina se acabo.
                if solo, quietos >= CapturaConScroll.quietosParaParar { break }
                if solo { CapturaConScroll.rueda(en: centro) }
                // Que asiente el scroll animado antes de la foto siguiente.
                try await Task.sleep(nanoseconds: solo ? 250_000_000 : 200_000_000)
            }
            let hecho = cosedor
            let pagina = await Task.detached(priority: .userInitiated) { hecho?.terminar() }.value
            if let pagina { alTerminar?(pagina, zona.escala) } else { NSSound.beep() }
        } catch {
            PermisoCaptura.avisarDenegado(detalle: "No se pudo hacer la captura con scroll: \(error.localizedDescription)")
        }
    }

    /// Pasa la foto a BGRA (una copia, que se suelta al volver), la firma y
    /// se la da al cosedor.
    nonisolated static func mirar(_ foto: CGImage, cosedor: CosidoScroll.Cosedor?)
        -> (CosidoScroll.Cosedor?, CosidoScroll.Resultado, UInt64?) {
        let ancho = foto.width
        let alto = foto.height
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: ancho * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info), let datos = ctx.data else { return (cosedor, .incierto, nil) }
        ctx.interpolationQuality = .none
        ctx.draw(foto, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
        let porFila = ctx.bytesPerRow
        let base = UnsafePointer(datos.assumingMemoryBound(to: UInt8.self))
        let firma = DeduplicadorGif.firma(UnsafeRawPointer(base), ancho: ancho, alto: alto, bytesPorFila: porFila)
        var c = cosedor ?? CosidoScroll.Cosedor(ancho: ancho)
        let r = c.anadir(base, ancho: ancho, alto: alto, bytesPorFila: porFila)
        return (c, r, firma)
    }

    /// Tres lineas de rueda hacia abajo en `punto` (coordenadas globales de
    /// Core Graphics). Necesita el permiso de Accesibilidad.
    static func rueda(en punto: CGPoint) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                              wheel1: -lineasPorPaso, wheel2: 0, wheel3: 0) else { return }
        e.location = punto
        e.post(tap: .cghidEventTap)
    }
}

/// El marco alrededor de una zona que se graba o se recorre (rojo: GIF;
/// azul: scroll), pintado por FUERA para no salir en lo capturado, y una
/// barrita con un rotulo y un boton. No sale en las capturas: PixPin se
/// excluye de todos sus filtros de ScreenCaptureKit.
@MainActor
final class MarcoDeZona {
    private let borde: NSPanel
    private let barra: NSPanel
    /// El destino del boton (el boton no lo retiene).
    private let objetivo: ObjetivoBoton?
    /// La zona de ahora (cambia si se mueve o se estira el marco).
    private(set) var zona: ZonaDeGrabacion
    /// El marco de su pantalla (AppKit) para colocar el borde y la barra.
    private let pantalla: CGRect
    private let visible: CGRect
    /// Avisa de la zona nueva al moverla o estirarla con el raton (solo
    /// en un marco `ajustable`).
    var alCambiar: ((ZonaDeGrabacion) -> Void)?

    private init(borde: NSPanel, barra: NSPanel, objetivo: ObjetivoBoton?,
                 zona: ZonaDeGrabacion, pantalla: NSScreen) {
        self.borde = borde
        self.barra = barra
        self.objetivo = objetivo
        self.zona = zona
        self.pantalla = pantalla.frame
        self.visible = pantalla.visibleFrame
    }

    /// La zona (puntos de su pantalla, origen arriba) en coordenadas
    /// globales de AppKit, dado el marco de esa pantalla.
    nonisolated static func marcoGlobal(_ r: CGRect, pantalla: CGRect) -> CGRect {
        let r = r.standardized
        return CGRect(x: pantalla.minX + r.minX, y: pantalla.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// El marco con una barrita de un rotulo y un boton (Esc lo pulsa).
    static func abrir(zona: ZonaDeGrabacion, rojo: Bool, texto: String, boton: String,
                      accion: @escaping () -> Void) -> MarcoDeZona? {
        let rotulo = NSTextField(labelWithString: texto)
        rotulo.font = .systemFont(ofSize: 12, weight: .medium)
        let objetivo = ObjetivoBoton(accion)
        let b = NSButton(title: boton, target: objetivo, action: #selector(ObjetivoBoton.pulsado))
        b.bezelColor = rojo ? .systemRed : .controlAccentColor
        b.keyEquivalent = "\u{1b}"
        let pila = NSStackView(views: [rotulo, b])
        pila.spacing = 10
        pila.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)
        return abrir(zona: zona, rojo: rojo, contenido: pila, objetivo: objetivo)
    }

    /// El marco con `contenido` en su barra (quien lo pone retiene los
    /// destinos de sus botones, o pasa uno en `objetivo`). `ajustable`: el
    /// anillo de alrededor se agarra con el raton para mover y estirar la
    /// zona (`grabador.rs` de Windows) hasta `fijar()`; el centro sigue
    /// dejando pasar los clics a la app de debajo.
    static func abrir(zona: ZonaDeGrabacion, rojo: Bool, contenido: NSView,
                      objetivo: ObjetivoBoton? = nil, ajustable: Bool = false) -> MarcoDeZona? {
        guard let pantalla = NSScreen.screens.first(where: { $0.numeroDePantalla == zona.pantalla }) else { return nil }
        let r = marcoGlobal(zona.rect, pantalla: pantalla.frame)
        let margen = ajustable ? MarcoAjustable.margen : MarcoAjustable.grosor
        let fuera = r.insetBy(dx: -margen, dy: -margen)

        let borde = NSPanel(contentRect: fuera, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        borde.isOpaque = false
        borde.backgroundColor = .clear
        borde.hasShadow = false
        // Ajustable NO se toca `ignoresMouseEvents`: asi el servidor de
        // ventanas deja pasar los clics por lo transparente (el centro) y
        // el anillo casi invisible los recibe. Ponerlo en `false` haria
        // que el marco se tragase los clics de toda la zona.
        if !ajustable { borde.ignoresMouseEvents = true }
        borde.level = .screenSaver
        borde.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        borde.isReleasedWhenClosed = false
        let vista = VistaMarco(frame: NSRect(origin: .zero, size: fuera.size), margen: margen, ajustable: ajustable)
        vista.color = rojo ? .systemRed : .controlAccentColor
        borde.contentView = vista
        borde.orderFrontRegardless()

        let tam = contenido.fittingSize
        let barra = PanelConTeclado(contentRect: NSRect(origin: origenBarra(tam: tam, fuera: fuera, pantalla: pantalla.frame,
                                                                           visible: pantalla.visibleFrame), size: tam),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        barra.isOpaque = false
        barra.backgroundColor = .clear
        barra.level = .screenSaver
        barra.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        barra.isReleasedWhenClosed = false
        barra.contentView = fondo(contenido, tam: tam)
        barra.makeKeyAndOrderFront(nil)

        let marco = MarcoDeZona(borde: borde, barra: barra, objetivo: objetivo, zona: zona, pantalla: pantalla)
        vista.alArrastrar = { [weak marco] asa, inicial, dx, dy in
            marco?.arrastrar(asa, desde: inicial, dx: dx, dy: dy)
        }
        vista.zonaActual = { [weak marco] in marco?.zona.rect ?? .zero }
        return marco
    }

    /// Debajo del marco a la derecha; si no cabe, encima; si tampoco,
    /// dentro arriba.
    private static func origenBarra(tam: CGSize, fuera: CGRect, pantalla: CGRect, visible: CGRect) -> CGPoint {
        var origen = CGPoint(x: fuera.maxX - tam.width, y: fuera.minY - tam.height - 6)
        if origen.y < visible.minY { origen.y = fuera.maxY + 6 }
        if origen.y + tam.height > visible.maxY { origen.y = fuera.minY + 8 }
        origen.x = min(max(pantalla.minX + 8, origen.x), pantalla.maxX - tam.width - 8)
        return origen
    }

    /// Mueve o estira la zona (el raton en el anillo).
    private func arrastrar(_ asa: AsaMarco, desde inicial: CGRect, dx: CGFloat, dy: CGFloat) {
        let nueva = MarcoAjustable.limitar(MarcoAjustable.aplicar(asa, a: inicial, dx: dx, dy: dy),
                                           a: CGRect(origin: .zero, size: pantalla.size))
        guard nueva != zona.rect else { return }
        zona.rect = nueva
        let fuera = MarcoDeZona.marcoGlobal(nueva, pantalla: pantalla)
            .insetBy(dx: -MarcoAjustable.margen, dy: -MarcoAjustable.margen)
        borde.setFrame(fuera, display: true)
        borde.contentView?.needsDisplay = true
        barra.setFrameOrigin(MarcoDeZona.origenBarra(tam: barra.frame.size, fuera: fuera, pantalla: pantalla, visible: visible))
        alCambiar?(zona)
    }

    /// Deja de moverse: desde aqui el raton atraviesa el marco entero
    /// (grabando no se cambia la zona).
    func fijar() {
        borde.ignoresMouseEvents = true
        (borde.contentView as? VistaMarco)?.ajustable = false
        NSCursor.arrow.set()
    }

    /// El panel de la barra (para darle el teclado).
    var panelDeBarra: NSPanel { barra }

    /// Rojo (grabando) o azul (esperando).
    func ponerRojo(_ rojo: Bool) {
        ponerColor(rojo ? .systemRed : .controlAccentColor)
    }

    /// El color del borde (rojo apagado en pausa).
    func ponerColor(_ color: NSColor) {
        (borde.contentView as? VistaMarco)?.color = color
    }

    /// Cambia lo de dentro de la barra (y su tamano, sin moverla de su
    /// esquina derecha).
    func ponerContenido(_ contenido: NSView) {
        let tam = contenido.fittingSize
        var marco = barra.frame
        marco.origin.x = marco.maxX - tam.width
        marco.size = tam
        barra.setFrame(marco, display: true)
        barra.contentView = MarcoDeZona.fondo(contenido, tam: tam)
    }

    private static func fondo(_ contenido: NSView, tam: CGSize) -> NSView {
        let fondo = NSVisualEffectView()
        fondo.material = .hudWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 10
        fondo.layer?.masksToBounds = true
        fondo.frame = NSRect(origin: .zero, size: tam)
        contenido.frame = fondo.bounds
        contenido.autoresizingMask = [.width, .height]
        fondo.addSubview(contenido)
        return fondo
    }

    func cerrar() {
        borde.orderOut(nil)
        barra.orderOut(nil)
        borde.close()
        barra.close()
    }
}

/// El borde del marco, pintado por FUERA de la zona. Ajustable, el anillo
/// de agarre lleva un relleno casi transparente para recibir el raton (el
/// centro, transparente del todo, lo deja pasar) y cambia el cursor segun
/// lo que se agarre.
final class VistaMarco: NSView {
    let margen: CGFloat
    var ajustable: Bool {
        didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    var color: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    /// `(asa, zona al empezar, dx, dy)`, con y hacia ABAJO.
    var alArrastrar: ((AsaMarco, CGRect, CGFloat, CGFloat) -> Void)?
    var zonaActual: (() -> CGRect)?

    private var agarre: (asa: AsaMarco, raton: CGPoint, zona: CGRect)?

    init(frame: NSRect, margen: CGFloat, ajustable: Bool) {
        self.margen = margen
        self.ajustable = ajustable
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// La zona dentro de la vista.
    private var dentro: NSRect { bounds.insetBy(dx: margen, dy: margen) }

    override func draw(_ dirtyRect: NSRect) {
        if ajustable {
            let anillo = NSBezierPath(rect: bounds)
            anillo.append(NSBezierPath(rect: dentro).reversed)
            NSColor(white: 0, alpha: 0.012).setFill()
            anillo.fill()
        }
        let g = MarcoAjustable.grosor
        let linea = NSBezierPath(rect: dentro.insetBy(dx: -g / 2, dy: -g / 2))
        linea.lineWidth = g
        color.setStroke()
        linea.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Lo agarrado bajo un punto de la vista (origen abajo).
    private func asa(en p: NSPoint) -> AsaMarco? {
        guard ajustable else { return nil }
        let arriba = CGPoint(x: p.x, y: bounds.height - p.y)
        let zona = CGRect(x: margen, y: margen, width: bounds.width - 2 * margen, height: bounds.height - 2 * margen)
        return MarcoAjustable.asa(en: arriba, zona: zona)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard agarre == nil else { return }
        cursor(asa(en: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseExited(with event: NSEvent) {
        if agarre == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let a = asa(en: convert(event.locationInWindow, from: nil)), let zona = zonaActual?() else { return }
        agarre = (a, NSEvent.mouseLocation, zona)
        if a == .mover { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let agarre, ajustable else { return }
        let ahora = NSEvent.mouseLocation
        alArrastrar?(agarre.asa, agarre.zona, ahora.x - agarre.raton.x, -(ahora.y - agarre.raton.y))
    }

    override func mouseUp(with event: NSEvent) {
        agarre = nil
        cursor(asa(en: convert(event.locationInWindow, from: nil))).set()
    }

    private func cursor(_ asa: AsaMarco?) -> NSCursor {
        switch asa {
        case nil: .arrow
        case .mover: .openHand
        case .norte: .frameResize(position: .top, directions: .all)
        case .sur: .frameResize(position: .bottom, directions: .all)
        case .este: .frameResize(position: .right, directions: .all)
        case .oeste: .frameResize(position: .left, directions: .all)
        case .norEste: .frameResize(position: .topRight, directions: .all)
        case .norOeste: .frameResize(position: .topLeft, directions: .all)
        case .surEste: .frameResize(position: .bottomRight, directions: .all)
        case .surOeste: .frameResize(position: .bottomLeft, directions: .all)
        }
    }
}

/// Un panel sin bordes que puede recibir el teclado (Esc en su boton).
final class PanelConTeclado: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// El destino de un boton de AppKit que llama a un cierre.
final class ObjetivoBoton: NSObject {
    private let cierre: () -> Void
    init(_ cierre: @escaping () -> Void) { self.cierre = cierre }
    @objc func pulsado() { cierre() }
}
