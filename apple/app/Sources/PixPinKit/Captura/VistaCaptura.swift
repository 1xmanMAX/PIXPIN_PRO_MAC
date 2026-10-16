// La superposicion de la captura: un panel sin bordes por pantalla, encima
// de todo, con la foto congelada, oscurecida salvo la zona elegida.
//
// Rendimiento (§4bis del plan):
// - la vista aloja sus capas (`layer` propio): la foto es el `contents` de
//   una capa y la compone la tarjeta grafica; mover el raton solo cambia un
//   camino (el velo), un borde y una etiqueta, nunca se redibuja la foto;
// - la lupa es otra capa con la MISMA foto y un `contentsRect`: cero copias;
// - nada de temporizadores: todo va por los eventos del raton y el teclado;
// - lo anotado encima lo dibuja el lienzo de verdad, en su propia vista
//   encima de la zona (`AnotadorCaptura`), con la barra y el panel de
//   estilo del lienzo (`BarrasCaptura`). La foto nunca se redibuja.

import AppKit
import CoreText
import QuartzCore

/// Que se elige al arrastrar o hacer clic (las letras de Windows).
enum ModoCaptura {
    /// `Z`: arrastrar una zona; un clic elige la ventana bajo el raton.
    case zona
    /// `V`: solo ventanas (resalta la de debajo; un clic la elige).
    case ventana
    /// `P`: la pantalla entera.
    case pantalla
    /// `T`: como zona, y al soltar saca el texto (OCR).
    case texto
    /// `S`: como zona, y al soltar la recorre bajando (captura con scroll).
    case scroll
    /// `G`: como zona, y al soltar la graba en GIF.
    case gif
    /// `L`: como zona, y al soltar saca un pin en vivo.
    case pinEnVivo

    /// Los de la barra de abajo, con su letra (las de Windows).
    static let enBarra: [(ModoCaptura, String)] = [
        (.zona, "Zona Z"), (.ventana, "Ventana V"), (.pantalla, "Pantalla P"), (.scroll, "Scroll S"),
        (.gif, "GIF G"), (.pinEnVivo, "En vivo L"), (.texto, "Texto T"),
    ]

    /// Si al elegir la zona se hace algo en el acto (sin barra de acciones).
    var actuaAlElegir: Bool {
        switch self {
        case .texto, .scroll, .gif, .pinEnVivo: true
        case .zona, .ventana, .pantalla: false
        }
    }
}

/// Lo que se hace con la zona elegida (la barra y sus atajos).
enum AccionCaptura: Int, CaseIterable {
    case copiar, pinear, alChat, texto, guardar, grabar, cerrar
    /// ⇧⌘S: sin boton, como en Windows.
    case guardarComo

    /// Las que tienen boton en la barra, en su orden.
    static let enBarra: [AccionCaptura] = [.copiar, .pinear, .alChat, .texto, .guardar, .grabar, .cerrar]

    var titulo: String {
        switch self {
        case .copiar: "Copiar"
        case .pinear: "Pinear"
        case .alChat: "Al chat"
        case .texto: "Texto"
        case .guardar: "Guardar"
        case .guardarComo: "Guardar como…"
        case .grabar: "Grabar"
        case .cerrar: "Descartar"
        }
    }

    var simbolo: String {
        switch self {
        case .copiar: "doc.on.doc"
        case .pinear: "pin"
        case .alChat: "bubble.left"
        case .texto: "text.viewfinder"
        case .guardar, .guardarComo: "square.and.arrow.down"
        case .grabar: "record.circle"
        case .cerrar: "xmark"
        }
    }

    /// La tecla en la pastilla del boton.
    var tecla: String {
        switch self {
        case .copiar: "↩"
        case .pinear: "⌘P"
        case .alChat: "⌘M"
        case .texto: "⌘T"
        case .guardar: "⌘S"
        case .guardarComo: "⇧⌘S"
        case .grabar: "⌘G"
        case .cerrar: "Esc"
        }
    }

    var atajo: String {
        switch self {
        case .copiar: "Intro o ⌘C"
        case .pinear: "⌃P o ⌘P"
        case .alChat: "⌃M o ⌘M"
        case .texto: "⌃T o ⌘T"
        case .guardar: "⌃S o ⌘S"
        case .guardarComo: "⇧⌘S"
        case .grabar: "⌃G o ⌘G"
        case .cerrar: "Esc"
        }
    }
}

/// El panel de cada pantalla. Sin bordes no podria recibir el teclado: se
/// le deja ser ventana clave (sin activar la app, para no robar el foco a
/// la app de debajo al cerrar).
final class PanelCaptura: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Un panel que cubre `foto.pantalla` con su vista y su barra.
    @MainActor
    static func abrir(foto: FotoDePantalla, ventanas: [VentanaVisible], capturador: Capturador) -> PanelCaptura {
        let marco = foto.pantalla.frame
        let panel = PanelCaptura(contentRect: marco, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.setFrame(marco, display: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none

        // Las ventanas que tocan esta pantalla, en sus coordenadas.
        let locales = ventanas.compactMap { v -> VentanaVisible? in
            let r = GeometriaCaptura.enPantalla(v.marco, origenPantalla: marco.origin)
            let dentro = GeometriaCaptura.ajustar(r, a: CGRect(origin: .zero, size: marco.size))
            return dentro.isEmpty ? nil : VentanaVisible(marco: dentro, nombre: v.nombre)
        }
        let limites = NSRect(origin: .zero, size: marco.size)
        let contenedor = NSView(frame: limites)
        let vista = VistaCaptura(frame: limites, foto: foto.imagen,
                                 escalaPantalla: foto.pantalla.backingScaleFactor, ventanas: locales)
        vista.capturador = capturador
        vista.autoresizingMask = [.width, .height]
        contenedor.addSubview(vista)
        let modos = VistaCaptura.hacerBarraModos(destino: vista)
        contenedor.addSubview(modos)
        vista.barraModos = modos
        // Encima de todo, las barras de la zona (acciones, la del lienzo y
        // su panel de estilo).
        let barras = HospedajeBarrasCaptura(estado: vista.barras)
        barras.frame = limites
        barras.autoresizingMask = [.width, .height]
        contenedor.addSubview(barras)
        vista.barras.intro = capturador.accionIntro
        vista.barras.disponibles = Set(AccionCaptura.allCases.filter { capturador.disponible($0) })
        vista.barras.alPulsar = { [weak capturador, weak vista] a in
            guard let capturador, let vista else { return }
            capturador.accion(a, en: vista)
        }
        panel.contentView = contenedor
        vista.colocarBarraModos()
        panel.initialFirstResponder = vista
        panel.makeFirstResponder(vista)
        return panel
    }
}

final class VistaCaptura: NSView {
    weak var capturador: Capturador?
    /// Lo que ensenan las barras de la zona (`BarrasCaptura.swift`).
    let barras = EstadoBarrasCaptura()
    /// Donde cae la barra de acciones (para que la de los modos no la pise).
    private var rectAcciones: CGRect?
    weak var barraModos: NSView?

    private var foto: CGImage?
    private var ventanas: [VentanaVisible]
    private let escalaPantalla: CGFloat

    /// La zona elegida o la que se esta arrastrando (puntos de la vista).
    private(set) var seleccion: CGRect = .zero
    /// Si ya hay zona y se esperan acciones.
    private(set) var elegida = false
    private var resaltada: VentanaVisible?
    private var inicio: CGPoint?
    private var arrastrando = false
    private var seguimiento: NSTrackingArea?

    /// El lienzo encima de la zona (`AnotadorCaptura`), desde que hay zona.
    private(set) var anotador: AnotadorCaptura?
    /// El color bajo el raton (para `C`).
    private(set) var colorBajoRaton: (UInt8, UInt8, UInt8)?
    /// Donde estaba la lupa (para rehacer su texto al cambiar el formato).
    private var puntoLupa = CGPoint(x: -1, y: -1)
    /// ⇧ se pulso sola (sin otra tecla en medio): al soltarla cambia el
    /// formato del color (`mayus_sola` de Windows).
    private var mayusSola = false
    /// La pantalla se ve en vivo (sin la foto).
    private var vivo = false

    private let raiz = CALayer()
    private let capaFoto = CALayer()
    private let capaVelo = CAShapeLayer()
    private let capaBorde = CAShapeLayer()
    private let capaEtiqueta = CATextLayer()
    private let capaLupa = CALayer()
    private let capaColor = CATextLayer()
    private let fuente = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    /// La lupa: ensena `ladoLupa` puntos de la foto en `tamLupa` puntos.
    private let ladoLupa: CGFloat = 16
    private let tamLupa: CGFloat = 112

    // Los controles de las barras que cambian de estado.
    var selectorModo: NSSegmentedControl?
    var selectorProporcion: NSSegmentedControl?
    var campoMedidas: NSTextField?
    var botonRepetir: NSButton?

    init(frame: NSRect, foto: CGImage, escalaPantalla: CGFloat, ventanas: [VentanaVisible]) {
        self.foto = foto
        self.ventanas = ventanas
        self.escalaPantalla = escalaPantalla
        super.init(frame: frame)
        // Vista que aloja capas: la capa es nuestra y no se redibuja sola.
        layer = raiz
        wantsLayer = true
        raiz.backgroundColor = NSColor.black.cgColor

        capaFoto.contents = foto
        capaFoto.contentsGravity = .resize

        capaVelo.fillColor = NSColor(white: 0, alpha: 0.45).cgColor
        capaVelo.fillRule = .evenOdd

        capaBorde.fillColor = nil
        capaBorde.strokeColor = NSColor.controlAccentColor.cgColor
        capaBorde.lineWidth = 1.5

        capaEtiqueta.font = fuente
        capaEtiqueta.fontSize = fuente.pointSize
        capaEtiqueta.foregroundColor = NSColor.white.cgColor
        capaEtiqueta.backgroundColor = NSColor(white: 0, alpha: 0.72).cgColor
        capaEtiqueta.cornerRadius = 4
        capaEtiqueta.alignmentMode = .center
        capaEtiqueta.isHidden = true

        capaLupa.contents = foto
        capaLupa.contentsGravity = .resize
        capaLupa.magnificationFilter = .nearest
        capaLupa.borderColor = NSColor.white.cgColor
        capaLupa.borderWidth = 1.5
        capaLupa.cornerRadius = 8
        capaLupa.masksToBounds = true
        capaLupa.isHidden = true

        capaColor.font = fuente
        capaColor.fontSize = 11
        capaColor.foregroundColor = NSColor.white.cgColor
        capaColor.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        capaColor.cornerRadius = 4
        capaColor.alignmentMode = .center
        capaColor.isHidden = true

        for capa in [capaFoto, capaVelo, capaBorde, capaEtiqueta, capaLupa, capaColor] {
            capa.contentsScale = escalaPantalla
            raiz.addSublayer(capa)
        }
        colocarCapas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("no se crea desde un nib") }

    // MARK: - Capas

    override func setFrameSize(_ nuevo: NSSize) {
        super.setFrameSize(nuevo)
        colocarCapas()
    }

    private func colocarCapas() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for capa in [capaFoto, capaVelo, capaBorde] { capa.frame = bounds }
        CATransaction.commit()
        redibujar()
    }

    /// Lo que se ilumina ahora: la zona elegida o arrastrada, o la ventana
    /// bajo el raton.
    private var zonaVisible: CGRect {
        if elegida || arrastrando { return seleccion }
        return resaltada?.marco ?? .zero
    }

    private func redibujar() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let zona = zonaVisible
        let velo = CGMutablePath()
        velo.addRect(bounds)
        if !zona.isEmpty { velo.addRect(zona) }
        capaVelo.path = velo
        capaBorde.path = zona.isEmpty ? nil : CGPath(rect: zona, transform: nil)

        // Con la barra del lienzo encima de la zona, la etiqueta quedaria
        // debajo: las medidas ya salen en la barra de los modos.
        guard !zona.isEmpty, let foto, !(elegida && anotador != nil) else {
            capaEtiqueta.isHidden = true
            return
        }
        let px = GeometriaCaptura.rectEnPixeles(zona, tamVista: bounds.size, ancho: foto.width, alto: foto.height)
        var texto = "\(Int(px.width)) × \(Int(px.height))"
        if !elegida, !arrastrando, let nombre = resaltada?.nombre, !nombre.isEmpty {
            texto = "\(nombre)  ·  \(texto)"
        }
        if let par = capturador?.proporcion.par {
            texto += "  ·  \(par.0):\(par.1)"
        }
        capaEtiqueta.string = texto
        let tam = (texto as NSString).size(withAttributes: [.font: fuente])
        let ancho = min(tam.width.rounded(.up) + 14, bounds.width)
        let alto = tam.height.rounded(.up) + 4
        var origen = CGPoint(x: zona.minX, y: zona.maxY + 4)
        if origen.y + alto > bounds.maxY { origen.y = zona.maxY - alto - 4 }
        origen.x = max(bounds.minX, min(origen.x, bounds.maxX - ancho))
        origen.y = max(bounds.minY, origen.y)
        capaEtiqueta.frame = CGRect(origin: origen, size: CGSize(width: ancho, height: alto))
        capaEtiqueta.isHidden = false
    }

    private func moverLupa(a p: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        puntoLupa = p
        guard !elegida, !vivo, let foto, bounds.contains(p) else {
            capaLupa.isHidden = true
            capaColor.isHidden = true
            colorBajoRaton = nil
            return
        }
        var origen = CGPoint(x: p.x + 20, y: p.y - 20 - tamLupa)
        if origen.x + tamLupa > bounds.maxX { origen.x = p.x - 20 - tamLupa }
        if origen.y - 36 < bounds.minY { origen.y = p.y + 20 + 36 }
        capaLupa.frame = CGRect(origin: origen, size: CGSize(width: tamLupa, height: tamLupa))
        capaLupa.contentsRect = GeometriaCaptura.rectDeLupa(en: p, lado: ladoLupa, tamVista: bounds.size)
        capaLupa.isHidden = false

        // El color del pixel: un recorte de 1x1 (sin copiar la foto) pintado
        // en un mapa de bits de 4 bytes.
        colorBajoRaton = VistaCaptura.color(de: foto, en: p, tamVista: bounds.size)
        if let c = colorBajoRaton {
            let formato = capturador?.formatoColor ?? .hex
            capaColor.string = "\(formato.texto(c.0, c.1, c.2))\nC copia · ⇧ \(formato.siguiente.rawValue.uppercased())"
            capaColor.frame = CGRect(x: origen.x - 24, y: origen.y - 34, width: tamLupa + 48, height: 32)
            capaColor.isHidden = false
        } else {
            capaColor.isHidden = true
        }
    }

    /// Vuelve a escribir el texto de la lupa (otro formato de color).
    func refrescarLupa() { moverLupa(a: puntoLupa) }

    /// En vivo: sin la foto ni la lupa, el panel deja ver la pantalla.
    func ponerVivo(_ si: Bool) {
        vivo = si
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capaFoto.isHidden = si
        raiz.backgroundColor = si ? NSColor.clear.cgColor : NSColor.black.cgColor
        CATransaction.commit()
        window?.isOpaque = !si
        window?.backgroundColor = si ? .clear : .black
        moverLupa(a: puntoLupa)
    }

    /// Una foto nueva de la pantalla (al volver de en vivo).
    func cambiarFoto(_ nueva: CGImage) {
        foto = nueva
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capaFoto.contents = nueva
        capaLupa.contents = nueva
        CATransaction.commit()
        // El lienzo sin nada dibujado lleva debajo la foto nueva.
        if elegida, let a = anotador, !a.anotado {
            quitarAnotador()
            prepararAnotador()
            colocarBarra()
        }
    }

    /// Las flechas: la zona elegida se mueve `dx`, `dy` puntos sin salirse
    /// de la pantalla (`deslizar_dentro` de Windows).
    func desplazar(dx: CGFloat, dy: CGFloat) {
        guard elegida else { return }
        seleccion = GeometriaCaptura.deslizar(seleccion, dx: dx, dy: dy, dentroDe: bounds)
        redibujar()
        colocarBarra()
    }

    /// El color (sRGB) del pixel de la foto bajo el punto `p` de la vista.
    nonisolated static func color(de foto: CGImage, en p: CGPoint, tamVista: CGSize) -> (UInt8, UInt8, UInt8)? {
        guard let px = MedidasCaptura.pixel(en: p, tamVista: tamVista, ancho: foto.width, alto: foto.height),
              let uno = foto.cropping(to: CGRect(x: px.x, y: px.y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let hecho = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(uno, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return hecho ? (bytes[0], bytes[1], bytes[2]) : nil
    }

    /// Lo que mide la barra de acciones (se mide una vez).
    private static let tamAcciones = BarraAccionesCaptura.tamano()

    /// Coloca las barras de la zona (acciones debajo, la del lienzo encima
    /// y el panel de estilo al lado) y las ensena.
    private func colocarBarra() {
        let botones = BotonBarraLienzo.barraDeCaptura
        let alto = MedidasBarraLienzo.lado + 2 * MedidasBarraLienzo.relleno
        let ancho = BotonBarraLienzo.anchoDeFila(botones[...])
        let sitio = GeometriaCaptura.barras(seleccion: seleccion, acciones: VistaCaptura.tamAcciones,
                                            herramientas: CGSize(width: ancho, height: alto),
                                            anchoPanel: 200, limites: bounds)
        // A las coordenadas de SwiftUI (origen arriba).
        func volteado(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
        }
        barras.acciones = volteado(sitio.acciones)
        barras.herramientas = volteado(sitio.herramientas)
        barras.panel = CGPoint(x: sitio.panel.x, y: bounds.height - sitio.panel.y)
        barras.modelo = anotador?.modelo
        barras.visibles = true
        rectAcciones = sitio.acciones
        colocarBarraModos()
    }

    /// Esconde las barras de la zona.
    private func esconderBarras() {
        barras.visibles = false
        barras.modelo?.desplegado = nil
        rectAcciones = nil
    }

    /// La barra de los modos, abajo en el centro; arriba si la zona o la
    /// barra de acciones la tapan.
    func colocarBarraModos() {
        guard let barraModos else { return }
        let t = barraModos.frame.size
        var o = CGPoint(x: (bounds.midX - t.width / 2).rounded(), y: bounds.minY + 24)
        let abajo = CGRect(origin: o, size: t)
        let tapaBarra = rectAcciones.map { abajo.intersects($0) } ?? false
        if elegida, abajo.intersects(seleccion) || tapaBarra {
            o.y = bounds.maxY - t.height - 36
        }
        barraModos.setFrameOrigin(o)
        actualizarBarraModos()
    }

    // MARK: - Lo que pide el capturador

    /// Vuelve a elegir desde cero (otra pantalla empezo una zona, o clic
    /// derecho). Lo anotado se va con la zona.
    func reiniciar() {
        seleccion = .zero
        elegida = false
        inicio = nil
        arrastrando = false
        quitarAnotador()
        esconderBarras()
        redibujar()
        colocarBarraModos()
    }

    /// Elige `r` como zona y ensena la barra (o hace lo del modo).
    func elegir(_ r: CGRect) {
        let zona = GeometriaCaptura.ajustar(r, a: bounds)
        guard !zona.isEmpty else { return }
        if zona != seleccion { quitarAnotador() }
        seleccion = zona
        elegida = true
        resaltada = nil
        moverLupa(a: CGPoint(x: -1, y: -1))
        redibujar()
        prepararAnotador()
        redibujar()
        colocarBarra()
        capturador?.alElegir(en: self)
    }

    /// Elige la pantalla entera (la tecla `P`).
    func elegirPantalla() { elegir(bounds) }

    /// La pantalla de esta vista (para recordar su ultima zona).
    var numeroDePantalla: CGDirectDisplayID? { window?.screen?.numeroDePantalla }

    /// El trozo elegido de la foto, en pixeles, con lo anotado dentro. Sin
    /// anotar, `cropping(to:)` no copia ni recodifica: comparte los pixeles
    /// de la foto; anotado, es un mapa de bits nuevo del tamano del recorte.
    func recorte() -> CGImage? {
        guard elegida, let foto else { return nil }
        let px = GeometriaCaptura.rectEnPixeles(seleccion, tamVista: bounds.size, ancho: foto.width, alto: foto.height)
        guard !px.isEmpty, let trozo = foto.cropping(to: px) else { return nil }
        return anotador?.imagen(escala: escalaFoto) ?? trozo
    }

    /// Si hay algo anotado (entonces el recorte ya es una copia aparte).
    var anotada: Bool { anotador?.anotado ?? false }

    /// La zona elegida para grabarla en video (`Grabar/`): su pantalla y la
    /// zona en puntos con el origen arriba, como la pide ScreenCaptureKit.
    func zonaDeGrabacion() -> ZonaDeGrabacion? {
        guard elegida, let numero = window?.screen?.numeroDePantalla else { return nil }
        let rect = GeometriaGrabacion.desdeVista(seleccion, altoPantalla: bounds.height)
        return ZonaDeGrabacion(pantalla: numero, rect: rect, escala: escalaFoto)
    }

    /// La zona elegida en coordenadas globales de AppKit (para el pin en
    /// vivo).
    func zonaGlobal() -> CGRect? {
        guard elegida, let w = window else { return nil }
        return seleccion.offsetBy(dx: w.frame.minX, dy: w.frame.minY)
    }

    /// Pixeles por punto de la foto (para el PPP del PNG).
    var escalaFoto: CGFloat {
        guard let foto, bounds.width > 0 else { return escalaPantalla }
        return CGFloat(foto.width) / bounds.width
    }

    /// El tamano de la foto entera, en pixeles.
    var tamFoto: CGSize {
        guard let foto else { return .zero }
        return CGSize(width: foto.width, height: foto.height)
    }

    /// Suelta la foto (al cerrar): las capas dejan de retenerla.
    func soltar() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capaFoto.contents = nil
        capaLupa.contents = nil
        CATransaction.commit()
        quitarAnotador()
        esconderBarras()
        foto = nil
        ventanas = []
        resaltada = nil
    }

    // MARK: - Medidas, proporcion y repetir

    /// Aplica la proporcion a la zona ya elegida (en el sitio).
    func aplicarProporcion(_ p: ProporcionCaptura) {
        actualizarBarraModos()
        guard elegida else {
            redibujar()
            return
        }
        elegir(MedidasCaptura.ajustar(seleccion, a: p, limites: bounds))
    }

    /// Las medidas tecleadas (en pixeles): desde la esquina de la zona o
    /// centradas. `false` si no se entienden.
    @discardableResult
    func aplicarMedidas(_ texto: String) -> Bool {
        guard let m = MedidasCaptura.leer(texto) else { return false }
        let r = MedidasCaptura.zona(ancho: m.ancho, alto: m.alto, escala: escalaFoto,
                                    seleccion: elegida ? seleccion : nil, limites: bounds)
        guard !r.isEmpty else { return false }
        capturador?.empezo(en: self)
        elegir(r)
        return true
    }

    /// `R`: la ultima zona de esta pantalla. `false` si no hay.
    @discardableResult
    func repetirUltima() -> Bool {
        guard let n = numeroDePantalla, let r = UltimaZona().leer(pantalla: n) else { return false }
        capturador?.empezo(en: self)
        elegir(r)
        return true
    }

    // MARK: - Anotar (con el lienzo)

    /// Pone el lienzo encima de la zona (si aun no esta). No en los modos
    /// que hacen algo al elegir: ahi no se anota.
    private func prepararAnotador() {
        guard elegida, anotador == nil, let capturador, !capturador.modo.actuaAlElegir, !capturador.esCuentagotas,
              let foto, let contenedor = superview else { return }
        let px = GeometriaCaptura.rectEnPixeles(seleccion, tamVista: bounds.size, ancho: foto.width, alto: foto.height)
        guard !px.isEmpty, let trozo = foto.cropping(to: px),
              let a = try? AnotadorCaptura(recorte: trozo, zona: seleccion, carpeta: capturador.carpetaDeAnotar)
        else { return }
        a.modelo.alCerrar = { [weak capturador] in capturador?.cerrar() }
        a.vista.teclaPrevia = { [weak self] e in self?.teclaDelLienzo(e) ?? false }
        // Encima de la foto y debajo de las barras.
        contenedor.addSubview(a.marco, positioned: .above, relativeTo: self)
        anotador = a
        barras.modelo = a.modelo
        // La vista del lienzo no se lleva el teclado hasta que se anote.
        window?.makeFirstResponder(self)
    }

    private func quitarAnotador() {
        guard let a = anotador else { return }
        anotador = nil
        barras.modelo = nil
        a.quitar()
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
    }

    /// Coge una herramienta de anotar (1-5; la misma otra vez la suelta).
    func tomar(_ h: HerramientaAnotar) { tomar(lienzo: h.delLienzo) }

    /// Coge una herramienta del lienzo. Con una de dibujo, el teclado es
    /// del lienzo (sus letras, escribir un texto, ⌫).
    func tomar(lienzo id: String) {
        guard elegida else { return }
        if anotador == nil { prepararAnotador() }
        guard let a = anotador else { return NSSound.beep() }
        capturador?.conFotoCongelada { [weak self] in
            guard let self, let a = self.anotador else { return }
            a.tomar(id)
            self.window?.makeFirstResponder(a.activo ? a.vista : self)
        }
        _ = a
    }

    @discardableResult
    func deshacer() -> Bool { anotador?.deshacer() ?? false }

    @discardableResult
    func rehacer() -> Bool { anotador?.rehacer() ?? false }

    /// Las teclas que llegan al lienzo mientras se anota (antes de que las
    /// vea el): las de la captura se quedan aqui; las demas, del lienzo.
    private func teclaDelLienzo(_ e: NSEvent) -> Bool {
        guard let capturador, let a = anotador else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) { return false }
        // Sin herramienta ni dibujo, las teclas vuelven a la captura.
        guard a.activo else {
            window?.makeFirstResponder(self)
            return capturador.tecla(e) || true
        }
        switch e.keyCode {
        case 53: // Esc: suelta lo elegido; sin nada elegido, descarta
            if a.hayElegidos { return false }
            capturador.cerrar()
            return true
        case 36, 76, 49, 123, 124, 125, 126: // Intro; Espacio y flechas no
            return capturador.tecla(e) || true
        default:
            break
        }
        if mods.isDisjoint(with: [.option, .shift]), let h = HerramientaAnotar.deTecla(e.charactersIgnoringModifiers ?? "") {
            tomar(h)
            return true
        }
        return false
    }

    func actualizarBarraModos() {
        guard let capturador else { return }
        if let i = ModoCaptura.enBarra.firstIndex(where: { $0.0 == capturador.modo }) {
            selectorModo?.selectedSegment = i
        }
        selectorProporcion?.selectedSegment = capturador.proporcion.rawValue
        if let n = numeroDePantalla { botonRepetir?.isEnabled = UltimaZona().leer(pantalla: n) != nil }
        if let foto, elegida, let campo = campoMedidas {
            let px = GeometriaCaptura.rectEnPixeles(seleccion, tamVista: bounds.size, ancho: foto.width, alto: foto.height)
            campo.placeholderString = "\(Int(px.width)) × \(Int(px.height))"
        } else {
            campoMedidas?.placeholderString = "ancho × alto"
        }
    }

    // MARK: - Raton

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let seguimiento { removeTrackingArea(seguimiento) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        seguimiento = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func punto(_ e: NSEvent) -> CGPoint {
        convert(e.locationInWindow, from: nil)
    }

    /// Resalta la ventana bajo `p` (si aun no hay zona).
    func seguirRaton(a p: CGPoint) {
        guard !elegida, inicio == nil else { return }
        let modo = capturador?.modo ?? .zona
        let nueva = modo == .pantalla ? nil : ventanas.first { $0.marco.contains(p) }
        if nueva?.marco != resaltada?.marco {
            resaltada = nueva
            redibujar()
        }
        moverLupa(a: p)
    }

    override func mouseEntered(with e: NSEvent) {
        window?.makeKey()
        capturador?.activar(self)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with e: NSEvent) {
        moverLupa(a: CGPoint(x: -1, y: -1))
        if !elegida, resaltada != nil {
            resaltada = nil
            redibujar()
        }
    }

    override func mouseMoved(with e: NSEvent) {
        let p = punto(e)
        NSCursor.crosshair.set()
        seguirRaton(a: p)
    }

    override func mouseDown(with e: NSEvent) {
        let p = punto(e)
        window?.makeFirstResponder(self)
        if let capturador, capturador.esCuentagotas {
            seguirRaton(a: p)
            capturador.copiarColor(de: self)
            return
        }
        // Anotando (lo dibuja el lienzo, encima), fuera de la zona no pasa
        // nada: clic derecho vuelve a elegir.
        if elegida, anotador?.activo == true { return }
        capturador?.empezo(en: self)
        if capturador?.modo == .pantalla {
            elegirPantalla()
            return
        }
        esconderBarras()
        quitarAnotador()
        elegida = false
        seleccion = .zero
        arrastrando = false
        inicio = p
        colocarBarraModos()
    }

    override func mouseDragged(with e: NSEvent) {
        let p = punto(e)
        guard let inicio else { return }
        if !arrastrando, GeometriaCaptura.esArrastre(desde: inicio, hasta: p) { arrastrando = true }
        if arrastrando, capturador?.modo != .ventana {
            let r = MedidasCaptura.atado(desde: inicio, hasta: p, proporcion: capturador?.proporcion ?? .libre)
            seleccion = GeometriaCaptura.ajustar(r, a: bounds)
            redibujar()
        }
        moverLupa(a: p)
    }

    override func mouseUp(with e: NSEvent) {
        let p = punto(e)
        guard inicio != nil else { return }
        let zona = seleccion
        let fueArrastre = arrastrando && capturador?.modo != .ventana
        inicio = nil
        arrastrando = false
        if fueArrastre, zona.width >= 2, zona.height >= 2 {
            elegir(zona)
        } else {
            // Un clic: la ventana de debajo o, si no hay, la pantalla.
            elegir(ventanas.first { $0.marco.contains(p) }?.marco ?? bounds)
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        if elegida || inicio != nil {
            reiniciar()
            seguirRaton(a: punto(e))
        } else {
            capturador?.cerrar()
        }
    }

    // MARK: - Teclado (lo decide el capturador, que sabe que pantalla manda)

    override func flagsChanged(with e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let soloMayus = mods.subtracting([.capsLock, .numericPad, .function]) == .shift
        if soloMayus {
            mayusSola = true
        } else {
            // Se solto (o se le junto otra): solo cuenta si iba sola.
            if mayusSola, mods.isDisjoint(with: [.shift, .command, .control, .option]) {
                capturador?.cambiarFormatoColor()
            }
            mayusSola = false
        }
        super.flagsChanged(with: e)
    }

    override func keyDown(with e: NSEvent) {
        mayusSola = false
        // Anotando, las teclas son del lienzo (que primero pregunta a la
        // captura por las suyas: `teclaDelLienzo`).
        if let a = anotador, a.activo {
            window?.makeFirstResponder(a.vista)
            a.vista.keyDown(with: e)
            return
        }
        if capturador?.tecla(e) != true { super.keyDown(with: e) }
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let conMando = mods.contains(.command) || mods.contains(.control)
        // Sin ⌘ ni ⌃, la tecla es de quien escribe (el texto anotado o el
        // campo de las medidas), no un atajo.
        if !conMando, window?.firstResponder !== self { return false }
        if capturador?.tecla(e) == true { return true }
        return super.performKeyEquivalent(with: e)
    }

    override func cancelOperation(_ sender: Any?) {
        capturador?.cerrar()
    }

    // MARK: - Barras

    @objc func cambiadoModo(_ control: NSSegmentedControl) {
        let i = control.selectedSegment
        guard i >= 0, i < ModoCaptura.enBarra.count else { return }
        capturador?.cambiarModo(ModoCaptura.enBarra[i].0, desde: self)
    }

    @objc func cambiadaProporcion(_ control: NSSegmentedControl) {
        guard let p = ProporcionCaptura(rawValue: control.selectedSegment) else { return }
        capturador?.cambiarProporcion(p, desde: self)
    }

    @objc func tecleadasMedidas(_ campo: NSTextField) {
        let texto = campo.stringValue
        campo.stringValue = ""
        window?.makeFirstResponder(self)
        if !texto.isEmpty, !aplicarMedidas(texto) { NSSound.beep() }
    }

    @objc func pulsadoRepetir(_ boton: NSButton) {
        if !repetirUltima() { NSSound.beep() }
    }

    private static func fondoDeBarra(_ contenido: NSView) -> NSView {
        let fondo = NSVisualEffectView()
        fondo.material = .hudWindow
        fondo.blendingMode = .withinWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 10
        fondo.layer?.masksToBounds = true
        fondo.frame = NSRect(origin: .zero, size: contenido.fittingSize)
        contenido.frame = fondo.bounds
        contenido.autoresizingMask = [.width, .height]
        fondo.addSubview(contenido)
        return fondo
    }

    /// La barra de abajo: los modos con su letra, «ancho × alto», las
    /// proporciones y repetir la ultima zona.
    static func hacerBarraModos(destino: VistaCaptura) -> NSView {
        let modos = NSSegmentedControl(labels: ModoCaptura.enBarra.map { $0.1 }, trackingMode: .selectOne,
                                       target: destino, action: #selector(VistaCaptura.cambiadoModo(_:)))
        modos.refusesFirstResponder = true
        let campo = NSTextField(string: "")
        campo.placeholderString = "ancho × alto"
        campo.toolTip = "Medidas exactas en píxeles (p. ej. 1280x720) e Intro"
        campo.target = destino
        campo.action = #selector(VistaCaptura.tecleadasMedidas(_:))
        campo.translatesAutoresizingMaskIntoConstraints = false
        campo.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let proporciones = NSSegmentedControl(labels: ProporcionCaptura.allCases.map { $0.rotulo },
                                              trackingMode: .selectOne, target: destino,
                                              action: #selector(VistaCaptura.cambiadaProporcion(_:)))
        proporciones.refusesFirstResponder = true
        let repetir = NSButton(title: "Repetir R", target: destino, action: #selector(VistaCaptura.pulsadoRepetir(_:)))
        repetir.refusesFirstResponder = true
        repetir.toolTip = "Repetir la última zona de esta pantalla (R)"
        let fila = NSStackView(views: [modos, campo, proporciones, repetir])
        fila.orientation = .horizontal
        fila.spacing = 8
        fila.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        destino.selectorModo = modos
        destino.selectorProporcion = proporciones
        destino.campoMedidas = campo
        destino.botonRepetir = repetir
        return fondoDeBarra(fila)
    }
}
