// **El visor reflujado de Word y libros, con su tinta** (tanda E7): es
// `visor.rs` de Windows (el `VisorHtmlActivity` del movil) con las piezas de
// Apple. Un Word, un EPUB (o una pagina, un Markdown, un texto) se leen como
// en el movil: una columna de texto que se adapta, con la letra que uno
// quiere, y se anota encima sin que nada tiemble.
//
// - **La maqueta es la del movil y la de Windows** (`documentos/reflujo.rs`
//   y `reflujo/maqueta.rs` del nucleo, K16): la misma hoja de estilo, las
//   mismas letras (Noto Serif y Roboto, incrustadas en el nucleo y abiertas
//   aqui con Core Text) y los mismos cortes de renglon. Core Text solo dice
//   lo que avanza cada letra (`MedidorCoreTextReflujo`); los renglones los
//   parte Rust y aqui se pintan por donde se partieron. Con la columna
//   fijada (`anot-<uid>.maqueta`) los tres aparatos parten igual y la tinta
//   cae en la misma palabra.
// - **La tinta** es un `EditorLienzo` de Rust (`Nucleo.anotarReflujo`) en
//   las unidades del lector (el cero en el borde de la columna) y se guarda
//   donde la guardan Windows y Android (`anot-<uid>` y su marco), asi viaja.
//   La primera vez que se anota se fijan la columna y la letra.
// - **Lo de los lectores**: la barra flotante (`BarraFlotante`), buscar
//   (`BuscadorLector`, ⌘F, ⌘G, F3), el modo oscuro y el negativo
//   (`TonoHojas`, la luna/sol de todos los visores), escuchar
//   (`VozDelReflujo` sobre `LeerEnVoz`, con el verde en `.voz`), la pagina
//   que sube sola (`AvanceLector`), marcadores con su riel, el indice (I),
//   cambiar el nombre (F2) y lo anotado al dia con el disco (`AlDiaLector`).
//
// Rendimiento: abrir y colocar van fuera del hilo principal; colocar se
// repite solo si cambian la columna o la letra. Se pinta solo lo que se ve:
// los bloques estan en orden de altura y se busca el primero que asoma. Los
// renglones de cada bloque se guardan ya hechos (`CTLine`) hasta que cambie
// la maqueta o el tono, y las imagenes se descodifican al verse.
//
// Las teclas son las de Windows con ⌘ en vez de Ctrl: + / − la letra, T el
// tipo, B el grosor, A anotar (P lapiz, H resaltador, E goma), M marcador,
// ⌘1…9 ir a el, I indice, G ajustes, D que suba sola, N negativo, L
// escuchar, F2 el nombre, ⌘F buscar, ⌘+ / ⌘− / ⌘0 el aumento, ⌘[ / ⌘] mas
// espacio a un lado (con ⇧, menos), ⇧⌘S compartir, ⌘P imprimir y ⎋ en
// cascada.

import AppKit
import Combine
import CoreText
import PixPinCore
import SwiftUI

// MARK: - Las letras del movil

/// **Las letras del lector** con Core Text: las del movil incrustadas en el
/// nucleo (`letrasDeLectura`), abiertas en memoria una vez, y Courier New del
/// Mac. Mide y pinta el mismo sitio, asi lo medido y lo pintado son la misma
/// letra. Se usa desde el hilo que coloca y desde el que pinta: con cerrojo.
final class LetrasDeLecturaMac: @unchecked Sendable {
    static let compartidas = LetrasDeLecturaMac()

    private struct Clave: Hashable {
        let familia: String
        let negrita: Bool
        let cursiva: Bool
    }

    private struct ConTam: Hashable {
        let clave: Clave
        let tam: CGFloat
    }

    private let cerrojo = NSLock()
    private var descriptores: [Clave: CTFontDescriptor]?
    private var letras: [ConTam: CTFont] = [:]

    /// Un peso de CSS pinta con la negrita de 600 para arriba (lo que hace el
    /// navegador con una familia de dos pesos: 600 y 800 buscan la 700).
    static func esNegrita(_ peso: UInt16) -> Bool { peso >= 600 }

    private func cargarSinCerrojo() -> [Clave: CTFontDescriptor] {
        if let d = descriptores { return d }
        var d: [Clave: CTFontDescriptor] = [:]
        for l in letrasDeLectura() {
            guard let lista = CTFontManagerCreateFontDescriptorsFromData(l.datos as CFData) as? [CTFontDescriptor],
                  let primero = lista.first else { continue }
            d[Clave(familia: l.familia, negrita: l.negrita, cursiva: l.cursiva)] = primero
        }
        descriptores = d
        return d
    }

    /// La letra `familia` a `tam`, con su negrita y su cursiva si las hay
    /// (si no, la recta de la misma familia).
    func letra(familia: String, negrita: Bool, cursiva: Bool, tam: CGFloat) -> CTFont {
        let k = Clave(familia: familia, negrita: negrita, cursiva: cursiva)
        cerrojo.lock()
        defer { cerrojo.unlock() }
        if let f = letras[ConTam(clave: k, tam: tam)] { return f }
        let d = cargarSinCerrojo()
        let f: CTFont
        if let desc = d[k] ?? d[Clave(familia: familia, negrita: negrita, cursiva: false)]
            ?? d[Clave(familia: familia, negrita: false, cursiva: false)] {
            f = CTFontCreateWithFontDescriptor(desc, tam, nil)
        } else {
            // Courier New (la del ancho fijo) es del Mac.
            var base = CTFontCreateWithName((familia == "Courier New" ? "CourierNewPSMT" : familia) as CFString, tam, nil)
            var rasgos: CTFontSymbolicTraits = []
            if negrita { rasgos.insert(.traitBold) }
            if cursiva { rasgos.insert(.traitItalic) }
            if !rasgos.isEmpty, let con = CTFontCreateCopyWithSymbolicTraits(base, tam, nil, rasgos, rasgos) {
                base = con
            }
            f = base
        }
        letras[ConTam(clave: k, tam: tam)] = f
        return f
    }

    /// **El parrafo con su letra y sus tramos**, listo para Core Text.
    func atribuido(_ texto: String, familia: String, peso: UInt16, tam: CGFloat, tramos: [TramoReflujo],
                   color: CGColor? = nil) -> NSAttributedString {
        let s = NSMutableAttributedString(string: texto)
        let largo = (texto as NSString).length
        let negrita = LetrasDeLecturaMac.esNegrita(peso)
        var base: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): letra(familia: familia, negrita: negrita,
                                                                           cursiva: false, tam: tam),
        ]
        if let color { base[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        s.setAttributes(base, range: NSRange(location: 0, length: largo))
        for t in tramos {
            let r = NSRange(location: Int(t.inicio), length: Int(t.longitud))
            guard r.location < largo else { continue }
            let rr = NSRange(location: r.location, length: min(r.length, largo - r.location))
            let f = letra(familia: t.mono ? "Courier New" : familia, negrita: t.negrita || negrita,
                          cursiva: t.cursiva, tam: tam)
            s.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: f, range: rr)
        }
        return s
    }

    /// Lo que avanza cada unidad UTF-16 (el racimo entero en su primera).
    func avances(_ texto: String, familia: String, peso: UInt16, tam: CGFloat, tramos: [TramoReflujo]) -> [Float] {
        let largo = (texto as NSString).length
        var v = [Float](repeating: 0, count: largo)
        guard largo > 0 else { return v }
        let linea = CTLineCreateWithAttributedString(atribuido(texto, familia: familia, peso: peso, tam: tam,
                                                               tramos: tramos))
        guard let corridas = CTLineGetGlyphRuns(linea) as? [CTRun] else { return v }
        for run in corridas {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var indices = [CFIndex](repeating: 0, count: n)
            var avances = [CGSize](repeating: .zero, count: n)
            CTRunGetStringIndices(run, CFRange(location: 0, length: n), &indices)
            CTRunGetAdvances(run, CFRange(location: 0, length: n), &avances)
            for k in 0..<n where indices[k] >= 0 && indices[k] < largo {
                v[indices[k]] += Float(avances[k].width)
            }
        }
        return v
    }
}

/// **El medidor del nucleo**: Core Text con las letras del movil.
final class MedidorCoreTextReflujo: MedidorReflujo, @unchecked Sendable {
    func avances(texto: String, familia: String, peso: UInt16, tam: Float, tramos: [TramoReflujo]) -> [Float] {
        LetrasDeLecturaMac.compartidas.avances(texto, familia: familia, peso: peso, tam: CGFloat(tam), tramos: tramos)
    }
}

// MARK: - El tono de la pagina

/// Los colores de la pagina con el tono de los lectores: en claro, papel
/// blanco; en oscuro, el papel oscuro de las hojas (`TonoHojas.papelOscuro`)
/// con los colores del modo noche del movil, que son los de Windows. El
/// negativo cambia el uno por el otro; la interfaz y la tinta (adaptada al
/// papel) quedan como estan.
struct ColoresReflujo: Equatable {
    var papel: CGColor
    var texto: CGColor
    var apagado: CGColor
    var raya: CGColor
    var celda: CGColor
    var cristal: CGColor
    var oscuro: Bool

    static func de(_ t: TonoHojas) -> ColoresReflujo {
        let rgb = { (r: Int, g: Int, b: Int) in
            CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        if t.oscuro != t.negativo {
            let p = TonoHojas.papelOscuro
            return ColoresReflujo(papel: CGColor(srgbRed: p.r, green: p.g, blue: p.b, alpha: 1),
                                  texto: rgb(0xE4, 0xE2, 0xE6), apagado: rgb(0x9A, 0x9A, 0xA2),
                                  raya: rgb(0x3A, 0x3A, 0x42), celda: rgb(0x4A, 0x4A, 0x52),
                                  cristal: rgb(0x26, 0x26, 0x2C), oscuro: true)
        }
        return ColoresReflujo(papel: rgb(0xFF, 0xFF, 0xFF), texto: rgb(0x1E, 0x1E, 0x22),
                              apagado: rgb(0x6A, 0x6A, 0x72), raya: rgb(0xCF, 0xCF, 0xD6),
                              celda: rgb(0xA8, 0xA8, 0xB0), cristal: rgb(0xF1, 0xF1, 0xF4), oscuro: false)
    }

    func de(_ t: TinteReflujo) -> CGColor {
        switch t {
        case .texto: texto
        case .apagado: apagado
        case .raya: raya
        }
    }
}

// MARK: - Lo que ve la barra

/// Lo propio del visor reflujado (lo comun a los lectores va en `ModeloLector`).
@MainActor
final class ModeloReflujo: ObservableObject {
    @Published var tamano: UInt32 = 100
    @Published var tipo: UInt8 = 0
    @Published var grosor: UInt8 = 1
    /// La columna fijada (hay tinta): la letra no se puede cambiar.
    @Published var fijada = false
    @Published var indice: [EntradaIndiceReflujo] = []
    @Published var colocando = true
    @Published var candado = false
}

/// **La barra del visor**, como la de los lectores: el asa y el nombre, las
/// herramientas, los colores, los marcadores, la letra, el indice, escuchar,
/// la pagina que sube sola, los ajustes, la luna/sol, pantalla completa, el
/// pin y la ✕.
struct BarraReflujo: View {
    @ObservedObject var modelo: ModeloLector
    @ObservedObject var reflujo: ModeloReflujo
    @ObservedObject var avance: AvanceLector
    @ObservedObject var voz = LeerEnVoz.compartida
    weak var visor: ControladorReflujo?

    static let tipos = ["Serif", "Sans", "Ancho fijo", "A mano"]
    static let grosores = ["Fina", "Normal", "Gruesa", "Negra"]

    var body: some View {
        HStack(spacing: 8) {
            AsaBarra()
            Button { visor?.empezarRenombrar() } label: {
                Text(modelo.nombre)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .help("Cambiar el nombre (F2)")
            Divider().frame(height: 22)
            Picker("", selection: Binding(get: { modelo.herramienta }, set: { visor?.elegir($0) })) {
                Image(systemName: "book").help("Leer").tag("leer")
                Image(systemName: "pencil.tip").help("Lápiz (P)").tag("lapiz")
                Image(systemName: "highlighter").help("Resaltador (H)").tag("resaltador")
                Image(systemName: "eraser").help("Goma (E)").tag("borrador")
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            HStack(spacing: 4) {
                ForEach(ColorTinta.todos) { c in
                    Circle().fill(c.color).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary, lineWidth: modelo.color == c ? 2 : 0))
                        .onTapGesture { visor?.ponerColor(c) }
                        .help(c.id)
                }
            }
            Divider().frame(height: 18)
            Menu {
                Button("Letra más grande (+)") { visor?.cambiarTamano(true) }
                Button("Letra más pequeña (−)") { visor?.cambiarTamano(false) }
                Section("Tipo (T)") {
                    ForEach(0..<BarraReflujo.tipos.count, id: \.self) { i in
                        Toggle(BarraReflujo.tipos[i], isOn: Binding(get: { Int(reflujo.tipo) == i },
                                                                    set: { _ in visor?.ponerTipo(UInt8(i)) }))
                    }
                }
                Section("Grosor (B)") {
                    ForEach(0..<BarraReflujo.grosores.count, id: \.self) { i in
                        Toggle(BarraReflujo.grosores[i], isOn: Binding(get: { Int(reflujo.grosor) == i },
                                                                       set: { _ in visor?.ponerGrosor(UInt8(i)) }))
                    }
                }
            } label: {
                Image(systemName: reflujo.fijada ? "textformat.size.larger" : "textformat.size")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .frame(width: 34)
            .help(reflujo.fijada ? "La letra está fijada: hay tinta encima" : "La letra (+ / −, T, B) · \(reflujo.tamano) %")
            Menu {
                Section("Poner aquí") {
                    ForEach(emojisDeMarcas(), id: \.self) { e in
                        Button(e) { visor?.ponerMarca(emoji: e) }
                    }
                }
                let propias = modelo.marcas.filter { $0.emoji != VozAlta.emojiDeVoz }
                if !propias.isEmpty {
                    Section("Ir a") {
                        ForEach(modelo.marcas, id: \.id) { m in
                            Button("\(m.emoji)  \(Int((m.y * 100).rounded())) %") { visor?.ir(a: m) }
                        }
                    }
                    Button("Quitar todos", role: .destructive) { visor?.quitarMarcas() }
                }
            } label: {
                Image(systemName: "bookmark")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .frame(width: 34)
            .help("Marcadores (M)")
            if !reflujo.indice.isEmpty {
                Menu {
                    ForEach(Array(reflujo.indice.enumerated()), id: \.offset) { _, e in
                        Button(String(repeating: "   ", count: max(Int(e.nivel) - 1, 0)) + e.titulo) {
                            visor?.ir(aBloque: e.bloque)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .frame(width: 34)
                .help("Índice (I)")
            }
            Button { visor?.deshacer() } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Deshacer (⌘Z)")
            if reflujo.colocando { ProgressView().controlSize(.small) }
            if modelo.donde == .chat {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color(white: 0.78))
                    .help("Lo anotado viaja con el mensaje a tus otros aparatos")
            }
            Divider().frame(height: 22)
            BotonFlotante(simbolo: "speaker.wave.2", ayuda: "Escuchar (L)",
                          encendido: visor?.voz.activa == true && voz.vivo) {
                visor?.voz.escuchar()
            }
            BotonFlotante(simbolo: "chevron.down.2", ayuda: "Desplazar sola (D)", encendido: avance.activo) {
                visor?.alternarAvance()
            }
            BotonFlotante(simbolo: "gearshape", ayuda: "Ajustes (G)") {
                visor?.mostrarAjustes(evento: NSApp.currentEvent)
            }
            BotonFlotante(simbolo: modelo.oscuro ? "sun.max" : "moon",
                          ayuda: modelo.oscuro ? "Modo claro" : "Modo oscuro") {
                visor?.alternarOscuro()
            }
            BotonFlotante(simbolo: "arrow.up.left.and.arrow.down.right", ayuda: "Pantalla completa (⌃⌘F)") {
                visor?.ventana.toggleFullScreen(nil)
            }
            BotonFlotante(simbolo: modelo.encima ? "pin.fill" : "pin", ayuda: "Siempre encima, como un pin",
                          encendido: modelo.encima) {
                visor?.ponerEncima(!modelo.encima)
            }
            BotonFlotante(simbolo: "xmark", ayuda: "Cerrar (⌘W)") {
                VentanaLisa.cerrar(visor?.ventana)
            }
        }
        .fixedSize()
        .buttonStyle(.borderless)
        .overlay(alignment: .bottom) {
            if let aviso = modelo.aviso {
                Text(aviso).font(.caption).padding(4)
                    .background(.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .offset(y: 30)
            }
        }
    }
}

// MARK: - La ventana y la pagina

/// La ventana del visor: recoge sus teclas antes que nadie.
final class VentanaReflujoNS: NSWindow {
    weak var visor: ControladorReflujo?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let v = visor, v.tecla(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let v = visor, v.tecla(event) { return }
        super.keyDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let v = visor, v.teclaAntes(event) { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        if visor?.escape() != true { super.cancelOperation(sender) }
    }
}

/// Lo que se ve fuera de la pagina a lo ancho va centrado: con la columna
/// mas estrecha que la ventana, la columna en medio.
final class ClipCentrado: NSClipView {
    override func constrainBoundsRect(_ propuesto: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(propuesto)
        if let doc = documentView {
            let f = doc.frame
            if f.width < r.width {
                r.origin.x = f.minX - (r.width - f.width) / 2
            }
        }
        return r
    }
}

/// **La pagina**: el documento colocado y su tinta, en unidades del lector
/// (los limites del documento son sus `bounds`, con el cero en el borde de
/// la columna y la Y hacia abajo). El aumento es el de la vista de desplazar.
final class PaginaReflujoNS: NSView {
    weak var visor: ControladorReflujo?
    private var arrastre: (desde: NSPoint, origen: NSPoint)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ sucio: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        visor?.pintar(en: ctx, sucio: sucio)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let v = visor else { return }
        if v.modelo.anotando {
            v.puntero(.pulsar, event, en: self)
        } else if let clip = enclosingScrollView?.contentView {
            arrastre = (event.locationInWindow, clip.bounds.origin)
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let v = visor else { return }
        if v.modelo.anotando {
            v.puntero(.mover, event, en: self)
        } else if let a = arrastre, let scroll = enclosingScrollView {
            // Mover con la mano: lo de debajo del raton sigue al raton.
            let k = max(scroll.magnification, 0.0001)
            let dx = (event.locationInWindow.x - a.desde.x) / k
            let dy = (event.locationInWindow.y - a.desde.y) / k
            let clip = scroll.contentView
            let o = NSPoint(x: v.reflujo.candado ? clip.bounds.origin.x : a.origen.x - dx, y: a.origen.y + dy)
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let v = visor else { return }
        if v.modelo.anotando {
            v.puntero(.soltar, event, en: self)
        } else if arrastre != nil {
            arrastre = nil
            NSCursor.pop()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if visor?.modelo.anotando == true { visor?.deshacer() } else { super.rightMouseDown(with: event) }
    }

    override func resetCursorRects() {
        if visor?.modelo.anotando == true { addCursorRect(visibleRect, cursor: .crosshair) }
    }
}

// MARK: - El visor

/// **Un Word o un libro abierto en el visor reflujado.**
@MainActor
public final class ControladorReflujo: NSObject, NSWindowDelegate {
    private(set) var url: URL
    let nucleo: Nucleo
    let modelo = ModeloLector()
    let reflujo = ModeloReflujo()
    let buscador = BuscadorLector()
    let avance = AvanceLector()
    private(set) lazy var voz = VozDelReflujo(visor: self)
    let ventana: VentanaReflujoNS
    let pagina = PaginaReflujoNS()
    let desplazar = NSScrollView()
    private let contenedor = NSView()
    private let riel = RielMarcasNS()
    private var barra: BarraFlotante?

    /// El documento y lo colocado.
    private(set) var documento: DocumentoReflujo?
    private(set) var maqueta: MaquetaReflujo?
    /// Lo que se recuerda (y viaja).
    private(set) var lectura: LecturaReflujo?
    /// Con que columna y letra se coloco: si cambian, se vuelve a colocar.
    private var colocadoCon: (Float, UInt32, UInt8, UInt8)?
    private var colocandoAhora: (Float, UInt32, UInt8, UInt8)?
    /// Los renglones ya hechos de cada colocado, y las imagenes vistas.
    private var lineas: [Int: [(CTLine, CGFloat)]] = [:]
    private var imagenes: [UInt32: CGImage] = [:]
    private var descodificando: Set<UInt32> = []
    private var colores = ColoresReflujo.de(TonoHojas())

    /// La tinta (solo con la columna fijada).
    private var editor: EditorLienzo?
    private var leido: (version: UInt64, lienzo: LienzoLeido)?
    private var adaptada: (version: UInt64, oscuro: Bool, lienzo: LienzoLeido)?
    private var coloresAdaptados: [ColorLienzo: ColorLienzo] = [:]
    private var trazando = false
    private let alDia = AlDiaLector()
    private var mirarDisco: Timer?

    /// Buscar: lo encontrado y la actual.
    private var encontradas: [CoincidenciaReflujo] = []
    private var actualBuscada: Int?
    private var marcarBuscadas = false
    /// Escuchar: el colocado que suena y la palabra.
    var sonando: Int? { didSet { pagina.needsDisplay = true } }
    var palabra: NSRange? { didSet { pagina.needsDisplay = true } }

    private let colaGuardar = DispatchQueue(label: "pixpin.reflujo.guardar", qos: .utility)
    private var guardadoPendiente: DispatchWorkItem?
    private var relojAvance: Timer?
    private var ultimoQuedan: CFTimeInterval = 0
    private var tareaNota: DispatchWorkItem?
    private var recolocar: DispatchWorkItem?
    private var vigias: [NSObjectProtocol] = []
    private var suscripciones: Set<AnyCancellable> = []
    var alCerrar: (@MainActor (ControladorReflujo) -> Void)?
    var alCambiarRuta: (@MainActor (ControladorReflujo, URL) -> Void)?

    init(url: URL, nucleo: Nucleo, titulo: String) {
        self.url = url
        self.nucleo = nucleo
        ventana = VentanaReflujoNS(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
        super.init()
        modelo.nombre = titulo
        ventana.visor = self
        ventana.title = titulo
        VentanaLisa.vestirEntera(ventana)
        ventana.isReleasedWhenClosed = false
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.delegate = self
        montar()
    }

    private func montar() {
        pagina.visor = self
        let clip = ClipCentrado()
        clip.drawsBackground = true
        desplazar.contentView = clip
        desplazar.documentView = pagina
        desplazar.hasVerticalScroller = true
        desplazar.hasHorizontalScroller = true
        desplazar.autohidesScrollers = true
        desplazar.allowsMagnification = true
        desplazar.minMagnification = 0.1
        desplazar.maxMagnification = CGFloat(aumentoMaximoDeLectura())
        desplazar.drawsBackground = true
        let modelo = self.modelo, buscador = self.buscador, avance = self.avance
        let arriba = NSHostingView(rootView: VStack(spacing: 8) {
            CajaNombre(modelo: modelo,
                       confirmar: { [weak self] t in self?.confirmarNombre(t) },
                       cancelar: { [weak self] in self?.cancelarNombre() })
            CajaBuscar(buscador: buscador)
            NotaLector(modelo: modelo)
        }.fixedSize())
        let abajo = NSHostingView(rootView: VStack(spacing: 8) {
            TiraMarcas(modelo: modelo) { [weak self] e in self?.ponerMarca(emoji: e) }
            BarraEscuchar(voz: LeerEnVoz.compartida) { [weak self] in self?.url.path ?? "" }
            BarraAvance(avance: avance,
                        cambiar: { [weak self] s in self?.cambiarVelocidad(s) },
                        cerrar: { [weak self] in self?.alternarAvance() })
        }.fixedSize())
        for v in [desplazar, riel, arriba, abajo] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        NSLayoutConstraint.activate([
            desplazar.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            desplazar.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            desplazar.topAnchor.constraint(equalTo: contenedor.topAnchor),
            desplazar.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
            riel.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor, constant: -18),
            riel.widthAnchor.constraint(equalToConstant: RielMarcasNS.lado),
            riel.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: 40),
            riel.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -40),
            arriba.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            arriba.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: 14),
            abajo.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            abajo.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -22),
        ])
        // Los marcadores de un Word son fracciones del documento: el riel de
        // una sola «pagina», y su rotulo, el tanto por ciento.
        riel.paginas = 1
        riel.rotulo = { m in "\(m.emoji)  \(Int((m.y * 100).rounded())) %" }
        riel.ir = { [weak self] m in self?.ir(a: m) }
        modelo.$marcas.sink { [weak riel] m in riel?.marcas = m }.store(in: &suscripciones)
        ventana.contentView = contenedor
        ventana.setContentSize(NSSize(width: 900, height: 1000))
        ventana.center()
        _ = ventana.setFrameAutosaveName("PixPinVisorReflujo")
        let reflujo = self.reflujo
        let barra = BarraFlotante(ventana: ventana) { [weak self] in
            BarraReflujo(modelo: modelo, reflujo: reflujo, avance: avance, visor: self)
        }
        barra.fija = { modelo.aviso != nil }
        self.barra = barra
        buscador.buscarEnTexto = { [weak self] q in self?.buscar(q) ?? (0, nil) }
        buscador.mostrarEnTexto = { [weak self] actual, marcar in self?.mostrarBuscada(actual, marcar: marcar) }
        let centro = NotificationCenter.default
        clip.postsBoundsChangedNotifications = true
        vigias.append(centro.addObserver(forName: NSView.boundsDidChangeNotification, object: clip,
                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.alMoverse() }
        })
        vigias.append(centro.addObserver(forName: NSView.frameDidChangeNotification, object: desplazar,
                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.alCambiarElTamano() }
        })
        desplazar.postsFrameChangedNotifications = true
        vigias.append(centro.addObserver(forName: .pixpinDocumentoAnotado, object: nil, queue: .main) { [weak self] n in
            let ruta = n.object as? String
            MainActor.assumeIsolated {
                if let self, ruta == self.url.path { self.mirarElDisco() }
            }
        })
        vigias.append(centro.addObserver(forName: .pixpinLectoresOscuros, object: nil, queue: .main) { [weak self] n in
            let oscuro = n.object as? Bool
            MainActor.assumeIsolated {
                if let self, let oscuro, oscuro != self.modelo.oscuro {
                    self.modelo.oscuro = oscuro
                    self.aplicarTono()
                }
            }
        })
    }

    // MARK: Abrir y colocar

    /// Lee el documento y lo recordado (fuera del hilo principal) y coloca.
    func abrir() {
        ventana.makeKeyAndOrderFront(nil)
        barra?.empezar()
        NSApp.activate()
        aplicarTono()
        let ruta = url.path, nucleo = self.nucleo
        Task {
            let (doc, lectura, nombre, oscuros) = await Task.detached(priority: .userInitiated) {
                (try? DocumentoReflujo.abrir(ruta: ruta), nucleo.lecturaDeReflujo(documento: ruta),
                 nucleo.nombreDeDocumento(documento: ruta), nucleo.lectoresOscuros())
            }.value
            self.ponerNombre(nombre)
            self.modelo.oscuro = oscuros ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            self.aplicarTono()
            guard let doc else {
                self.reflujo.colocando = false
                self.modelo.aviso = "No se puede abrir este documento."
                return
            }
            self.documento = doc
            self.reflujo.indice = doc.indice()
            self.ponerLectura(lectura)
            if lectura.zoom.isFinite, lectura.zoom > 0 { self.desplazar.magnification = CGFloat(lectura.zoom) }
            self.colocarSiHaceFalta(irA: lectura.sitio)
            if lectura.columna > 0 { self.abrirTinta(siHay: true) }
        }
    }

    private func ponerLectura(_ l: LecturaReflujo) {
        lectura = l
        modelo.donde = l.donde
        reflujo.tamano = l.tamano
        reflujo.tipo = l.tipo
        reflujo.grosor = l.grosor
        reflujo.fijada = l.columna > 0
        reflujo.candado = l.sinLado
        desplazar.hasHorizontalScroller = !l.sinLado
        modelo.marcas = ControladorReflujo.marcas(de: l)
    }

    /// Los marcadores como los pinta el riel (`y` es la fraccion), con el
    /// verde de la voz en su sitio (`lista_del_riel`).
    static func marcas(de l: LecturaReflujo) -> [MarcaDocumento] {
        var v = l.marcadores.map { MarcaDocumento(id: Int64(bitPattern: $0.id), x: 0.5, y: Double($0.fraccion), emoji: $0.emoji) }
        if let verde = l.voz {
            v.append(MarcaDocumento(id: -1, x: 0.5, y: Double(verde.fraccion), emoji: VozAlta.emojiDeVoz))
        }
        return v.sorted { $0.y < $1.y }
    }

    /// La columna que toca: la fijada si hay tinta; si no, la que cabe.
    var columna: Float {
        if let l = lectura, l.columna > 0 { return Float(l.columna) }
        return columnaDeLecturaQueCabe(ancho: Float(desplazar.frame.width))
    }

    /// Coloca (fuera del hilo principal) si cambiaron la columna o la letra,
    /// y vuelve al mismo punto del documento (o a `irA`).
    private func colocarSiHaceFalta(irA: Float? = nil) {
        guard let doc = documento, let l = lectura else { return }
        let clave = (columna, l.tamano, l.tipo, l.grosor)
        if let c = colocadoCon, c == clave, irA == nil { return }
        if let c = colocandoAhora, c == clave { return }
        colocandoAhora = clave
        reflujo.colocando = true
        let donde = irA ?? fraccion()
        Task {
            let m = await Task.detached(priority: .userInitiated) {
                doc.colocar(columna: clave.0, tamano: clave.1, tipo: clave.2, grosor: clave.3,
                            medidor: MedidorCoreTextReflujo())
            }.value
            // Otra cosa se pidio mientras: manda lo ultimo.
            guard let c = self.colocandoAhora, c == clave else { return }
            self.colocandoAhora = nil
            self.colocadoCon = clave
            self.maqueta = m
            self.lineas = [:]
            self.encontradas = []
            self.reflujo.colocando = false
            self.ponerLimites()
            self.irA(fraccion: donde)
            if self.buscador.abierto, !self.buscador.consultaLimpia.isEmpty { self.buscador.buscar(ir: false) }
            self.voz.alColocar()
        }
    }

    private func alCambiarElTamano() {
        ponerLimites()
        guard lectura?.columna == 0 else { return }
        // Sin tinta, la columna sigue a la ventana (un momento despues de
        // dejar de estirarla).
        recolocar?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.colocarSiHaceFalta() } }
        recolocar = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: t)
    }

    /// **De donde a donde va el documento a lo ancho** (`visor::limites`):
    /// sin tinta, la columna; con tinta o anotando, sus dos espacios. Una
    /// tabla mas ancha que la columna se despliega a la derecha.
    func limites() -> (CGFloat, CGFloat) {
        guard let m = maqueta, let l = lectura else { return (0, CGFloat(columna)) }
        let c = CGFloat(m.columna)
        let tablas = m.colocados.compactMap { $0.caja.map { CGFloat($0.x + $0.ancho) } }.max() ?? c
        var (izq, der) = (CGFloat(0), c)
        if l.columna > 0 || modelo.anotando {
            let lados = ladosDeLaColumna(lectura: l, columna: m.columna)
            izq = -CGFloat(lados.first ?? 0)
            der = c + CGFloat(lados.last ?? 0)
        }
        return (izq, max(der, tablas))
    }

    /// La pagina a la medida de lo colocado, con el cero en el borde de la
    /// columna, y el aumento dentro de sus topes.
    private func ponerLimites() {
        guard let m = maqueta else { return }
        let (izq, der) = limites()
        let renglon = CGFloat(16 * Float(lectura?.tamano ?? 100) / 100 * 1.45)
        let alto = CGFloat(m.alto) + renglon * 4
        let ancho = der - izq
        let antes = desplazar.contentView.bounds.origin
        pagina.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        pagina.bounds = NSRect(x: izq, y: 0, width: ancho, height: alto)
        desplazar.minMagnification = CGFloat(aumentoMinimoDeLectura(anchoDoc: Float(ancho),
                                                                      vista: Float(desplazar.frame.width)))
        if desplazar.magnification < desplazar.minMagnification {
            desplazar.magnification = desplazar.minMagnification
        }
        let clip = desplazar.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: antes, size: clip.bounds.size)).origin)
        desplazar.reflectScrolledClipView(clip)
        pagina.needsDisplay = true
        ventana.invalidateCursorRects(for: pagina)
    }

    // MARK: Donde se esta

    private var altoDoc: CGFloat { CGFloat(maqueta?.alto ?? 0) }

    /// Por donde se va, de 0 a 1 (lo de arriba de lo que se ve).
    func fraccion() -> Float {
        guard altoDoc > 0 else { return lectura?.sitio ?? 0 }
        let arriba = desplazar.contentView.bounds.minY
        return Float(min(max(arriba / altoDoc, 0), 1))
    }

    /// Lleva lo de arriba de la vista a `y` (en unidades del documento).
    func irA(y: CGFloat) {
        let clip = desplazar.contentView
        var o = clip.bounds.origin
        o.y = y
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
        desplazar.reflectScrolledClipView(clip)
    }

    func irA(fraccion f: Float) {
        irA(y: CGFloat(f) * altoDoc)
    }

    func ir(a m: MarcaDocumento) {
        irA(fraccion: Float(m.y))
    }

    func ir(aBloque b: UInt32) {
        guard let m = maqueta, let c = m.colocados.first(where: { ($0.bloque ?? 0) >= b && $0.bloque != nil }) else { return }
        irA(y: CGFloat(c.y) - 12)
    }

    private func alMoverse() {
        pagina.needsDisplay = true
    }

    // MARK: Pintar

    /// Pinta lo que se ve: el papel, cada bloque (con sus rayas de tabla y
    /// sus imagenes), lo encontrado, lo que suena y la tinta.
    func pintar(en ctx: CGContext, sucio: NSRect) {
        ctx.setFillColor(colores.papel)
        ctx.fill(sucio)
        guard let m = maqueta else { return }
        let linea = 1 / max(desplazar.magnification, 0.0001)
        let cs = m.colocados
        // Los bloques van en orden de altura: el primero que asoma.
        var i = 0, hasta = cs.count
        while i < hasta {
            let mitad = (i + hasta) / 2
            let c = cs[mitad]
            let fondo = max(CGFloat(c.y + c.alto), c.caja.map { CGFloat($0.y + $0.alto) } ?? 0)
            if fondo < sucio.minY - 400 { i = mitad + 1 } else { hasta = mitad }
        }
        // Lo que suena, en ambar, debajo del texto.
        if let s = sonando, s < cs.count {
            let c = cs[s]
            let r = CGRect(x: CGFloat(c.sangria) - 4, y: CGFloat(c.y) - 2, width: CGFloat(c.ancho) + 8,
                           height: CGFloat(c.alto) + 4)
            ctx.setFillColor(VozDelLector.ambar.cgColor)
            ctx.fill(r)
            if let p = palabra {
                ctx.setFillColor(VozDelLector.ambarPalabra.cgColor)
                for q in cajas(de: s, NSRange(location: p.location, length: p.length)) { ctx.fill(q) }
            }
        }
        // Lo encontrado.
        if marcarBuscadas, !encontradas.isEmpty {
            for (k, e) in encontradas.enumerated() {
                let c = Int(e.colocado)
                guard c < cs.count, CGFloat(cs[c].y) < sucio.maxY + 40,
                      CGFloat(cs[c].y + cs[c].alto) > sucio.minY - 40 else { continue }
                ctx.setFillColor((k == actualBuscada ? BuscadorLector.colorActual : BuscadorLector.colorMarca).cgColor)
                for q in cajas(de: c, NSRange(location: Int(e.inicio), length: Int(e.largo))) {
                    ctx.addPath(CGPath(roundedRect: q, cornerWidth: 2, cornerHeight: 2, transform: nil))
                    ctx.fillPath()
                }
            }
        }
        var k = i
        while k < cs.count {
            let c = cs[k]
            if CGFloat(c.y) > sucio.maxY + 40, c.caja.map({ CGFloat($0.y) > sucio.maxY }) ?? true { break }
            pintarColocado(k, c, en: ctx, linea: linea)
            k += 1
        }
        pintarTinta(en: ctx, sucio: sucio)
    }

    private func pintarColocado(_ k: Int, _ c: ColocadoReflujo, en ctx: CGContext, linea: CGFloat) {
        if let caja = c.caja {
            let r = CGRect(x: CGFloat(caja.x), y: CGFloat(caja.y), width: CGFloat(caja.ancho), height: CGFloat(caja.alto))
            if caja.relleno {
                ctx.setFillColor(colores.cristal)
                ctx.fill(r)
            }
            ctx.setFillColor(colores.celda)
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: linea, height: r.height))
            ctx.fill(CGRect(x: r.maxX - linea, y: r.minY, width: linea, height: r.height))
            if caja.arriba { ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: linea)) }
            if caja.abajo { ctx.fill(CGRect(x: r.minX, y: r.maxY - linea, width: r.width, height: linea)) }
        }
        switch c.clase {
        case .regla, .capitulo:
            ctx.setFillColor(colores.raya)
            ctx.fill(CGRect(x: CGFloat(c.sangria), y: CGFloat(c.y), width: CGFloat(c.ancho), height: CGFloat(c.alto)))
            return
        default: break
        }
        let hueco = CGRect(x: CGFloat(c.sangria), y: CGFloat(c.y), width: CGFloat(c.ancho), height: CGFloat(c.alto))
        if c.recuadro {
            if let n = c.imagen {
                if let img = imagen(n) {
                    ctx.saveGState()
                    ctx.translateBy(x: hueco.minX, y: hueco.maxY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: CGRect(origin: .zero, size: hueco.size))
                    ctx.restoreGState()
                } else {
                    ctx.setFillColor(colores.cristal)
                    ctx.fill(hueco)
                }
                return
            }
            ctx.setStrokeColor(colores.apagado)
            ctx.setLineWidth(linea)
            ctx.stroke(hueco.insetBy(dx: linea / 2, dy: linea / 2))
        }
        guard !c.texto.isEmpty else { return }
        let renglon = CGFloat(c.tam * c.interlineado)
        for (n, (l, x)) in lineas(de: k, c).enumerated() {
            let y0 = CGFloat(c.y) + CGFloat(n) * renglon
            let f = LetrasDeLecturaMac.compartidas.letra(familia: c.familia, negrita: LetrasDeLecturaMac.esNegrita(c.peso),
                                                         cursiva: false, tam: CGFloat(c.tam))
            let asc = CTFontGetAscent(f), desc = CTFontGetDescent(f)
            // El medio interlineado de CSS arriba y abajo de la letra.
            let base = y0 + (renglon - (asc + desc)) / 2 + asc
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: x, y: base)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(l, ctx)
            ctx.restoreGState()
        }
    }

    /// Los renglones de un colocado, partidos donde los partio Rust, con
    /// donde empieza cada uno segun su alineacion.
    private func lineas(de k: Int, _ c: ColocadoReflujo) -> [(CTLine, CGFloat)] {
        if let l = lineas[k] { return l }
        let letras = LetrasDeLecturaMac.compartidas
        let todo = letras.atribuido(c.texto, familia: c.familia, peso: c.peso, tam: CGFloat(c.tam), tramos: c.tramos,
                                    color: colores.de(c.tinte))
        let largo = todo.length
        var pares: [(Int, Int)] = stride(from: 0, to: c.renglones.count - 1, by: 2).map {
            (Int(c.renglones[$0]), Int(c.renglones[$0 + 1]))
        }
        if pares.isEmpty { pares = [(0, largo)] }
        let salida: [(CTLine, CGFloat)] = pares.map { a, b in
            let a = min(a, largo), b = min(max(b, a), largo)
            let l = CTLineCreateWithAttributedString(todo.attributedSubstring(from: NSRange(location: a, length: b - a)))
            let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
            let x: CGFloat
            switch c.alineacion {
            case .izquierda: x = CGFloat(c.sangria)
            case .centro: x = CGFloat(c.sangria) + (CGFloat(c.ancho) - w) / 2
            case .derecha: x = CGFloat(c.sangria) + CGFloat(c.ancho) - w
            }
            return (l, x)
        }
        lineas[k] = salida
        return salida
    }

    /// **Las cajas de unas letras** de un colocado (lo encontrado, la palabra
    /// que suena), en unidades del documento.
    func cajas(de k: Int, _ r: NSRange) -> [CGRect] {
        guard let m = maqueta, k < m.colocados.count else { return [] }
        let c = m.colocados[k]
        let renglon = CGFloat(c.tam * c.interlineado)
        var pares: [(Int, Int)] = stride(from: 0, to: c.renglones.count - 1, by: 2).map {
            (Int(c.renglones[$0]), Int(c.renglones[$0 + 1]))
        }
        if pares.isEmpty { pares = [(0, (c.texto as NSString).length)] }
        var v: [CGRect] = []
        for (n, ((a, b), (l, x))) in zip(pares, lineas(de: k, c)).enumerated() {
            let i = max(r.location, a), f = min(NSMaxRange(r), b)
            guard f > i else { continue }
            let x0 = CTLineGetOffsetForStringIndex(l, i - a, nil)
            let x1 = CTLineGetOffsetForStringIndex(l, f - a, nil)
            v.append(CGRect(x: x + x0, y: CGFloat(c.y) + CGFloat(n) * renglon, width: max(x1 - x0, 2), height: renglon))
        }
        return v
    }

    private func imagen(_ n: UInt32) -> CGImage? {
        if let i = imagenes[n] { return i }
        guard !descodificando.contains(n), let doc = documento else { return nil }
        descodificando.insert(n)
        Task {
            let img = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let datos = doc.imagen(n: n),
                      let fuente = CGImageSourceCreateWithData(datos as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(fuente, 0, nil)
            }.value
            if let img { self.imagenes[n] = img }
            self.pagina.needsDisplay = true
        }
        return nil
    }

    private func pintarTinta(en ctx: CGContext, sucio: NSRect) {
        guard let ed = editor else { return }
        let v = ed.version()
        if leido?.version != v, let l = try? leerLienzo(ed.plano()) { leido = (v, l) }
        guard var l = leido?.lienzo, !l.figuras.isEmpty else { return }
        if colores.oscuro {
            if let a = adaptada, a.version == v, a.oscuro {
                l = a.lienzo
            } else {
                let p = TonoHojas.papelOscuro
                l = l.sobrePapel(p, cache: &coloresAdaptados)
                adaptada = (v, true, l)
            }
        }
        PintorLienzo(lienzo: l).pintar(en: ctx, limites: sucio)
    }

    // MARK: Tono

    var tono: TonoHojas { TonoHojas(negativo: modelo.negativo, oscuro: modelo.oscuro) }

    func aplicarTono() {
        colores = ColoresReflujo.de(tono)
        let papel = NSColor(cgColor: colores.papel) ?? .white
        desplazar.backgroundColor = papel
        desplazar.contentView.backgroundColor = papel
        lineas = [:]
        adaptada = nil
        coloresAdaptados = [:]
        pagina.needsDisplay = true
    }

    func alternarNegativo() {
        modelo.negativo.toggle()
        aplicarTono()
    }

    func alternarOscuro() {
        modelo.oscuro.toggle()
        aplicarTono()
        let oscuro = modelo.oscuro, nucleo = self.nucleo
        colaGuardar.async { try? nucleo.guardarLectoresOscuros(oscuros: oscuro) }
        NotificationCenter.default.post(name: .pixpinLectoresOscuros, object: oscuro)
    }

    // MARK: La letra

    /// Cambia algo de la letra, **si se puede**: con tinta encima la letra
    /// esta fijada (el texto se partiria en otros renglones y lo anotado
    /// quedaria sobre otras palabras). Se dice por que no.
    private func cambiarLetra(_ cambio: (inout LecturaReflujo) -> Void) {
        guard var l = lectura else { return }
        if l.columna > 0 {
            avisar("La letra está fijada: hay tinta encima y el texto no puede moverse de su sitio")
            return
        }
        cambio(&l)
        ponerLectura(l)
        guardarLectura()
        colocarSiHaceFalta()
    }

    func cambiarTamano(_ mas: Bool) {
        cambiarLetra { $0.tamano = tamanoDeLetraVecino(actual: $0.tamano, mas: mas) }
    }

    func ponerTipo(_ t: UInt8) { cambiarLetra { $0.tipo = t } }
    func ponerGrosor(_ g: UInt8) { cambiarLetra { $0.grosor = g } }

    // MARK: Anotar

    /// Abre la tinta (fuera del hilo principal). `siHay`: solo si ya tiene
    /// fichero (al abrir el documento).
    private func abrirTinta(siHay: Bool) {
        guard editor == nil else { return }
        let ruta = url.path, nucleo = self.nucleo
        Task {
            let ed = await Task.detached(priority: .userInitiated) { () -> EditorLienzo? in
                if siHay, !nucleo.hayTintaDeReflujo(documento: ruta) { return nil }
                return try? nucleo.anotarReflujo(documento: ruta)
            }.value
            guard let ed, self.editor == nil else { return }
            self.ponerEditor(ed)
        }
    }

    private func ponerEditor(_ ed: EditorLienzo) {
        editor = ed
        leido = nil
        adaptada = nil
        aplicarHerramienta(ed)
        empezarAMirarElDisco()
        pagina.needsDisplay = true
    }

    private func aplicarHerramienta(_ ed: EditorLienzo) {
        try? ed.herramienta(nombre: modelo.anotando ? modelo.herramienta : "lapiz")
        let c = modelo.color
        ed.tintaColor(r: c.r, g: c.g, b: c.b, a: 1)
    }

    /// **Elegir una herramienta**. La primera vez que se anota se fija la
    /// columna (y con ella la letra): lo anotado sigue encima de su palabra
    /// la proxima vez, aunque la ventana sea otra.
    func elegir(_ h: String) {
        if h != "leer", var l = lectura, l.columna == 0, maqueta != nil {
            l.columna = UInt32(columna.rounded())
            ponerLectura(l)
            guardarLecturaYa()
        }
        modelo.herramienta = h
        if h == "resaltador", modelo.color == ColorTinta.todos[0] { modelo.color = ColorTinta.todos[4] }
        if h != "leer" {
            modelo.poniendoMarca = false
            if let ed = editor {
                aplicarHerramienta(ed)
            } else {
                do {
                    let ed = try nucleo.anotarReflujo(documento: url.path)
                    ponerEditor(ed)
                } catch {
                    modelo.aviso = "No se puede anotar aquí: \(error)"
                }
            }
        } else {
            programarGuardado()
        }
        ponerLimites()
        ventana.invalidateCursorRects(for: pagina)
    }

    func ponerColor(_ c: ColorTinta) {
        modelo.color = c
        if !modelo.anotando { elegir("lapiz") } else if let ed = editor { aplicarHerramienta(ed) }
    }

    func puntero(_ fase: FasePuntero, _ evento: NSEvent, en vista: NSView) {
        guard let ed = editor else { return }
        let p = vista.convert(evento.locationInWindow, from: nil)
        let presion: Float? = evento.subtype == .tabletPoint ? Float(evento.pressure) : nil
        var mods: UInt32 = 0
        if evento.modifierFlags.contains(.shift) { mods |= 1 }
        if evento.modifierFlags.contains(.option) { mods |= 2 }
        trazando = fase == .pulsar || fase == .mover
        _ = ed.puntero(fase: fase, x: Float(p.x), y: Float(p.y), presion: presion, modificadores: mods,
                       zoom: Float(desplazar.magnification))
        pagina.needsDisplay = true
        if fase == .soltar || fase == .cancelar {
            trazando = false
            programarGuardado()
        }
    }

    func deshacer() {
        if editor?.deshacer() == true {
            pagina.needsDisplay = true
            programarGuardado()
        }
    }

    func rehacer() {
        if editor?.rehacer() == true {
            pagina.needsDisplay = true
            programarGuardado()
        }
    }

    // MARK: Guardar

    private func programarGuardado(espera: TimeInterval = 1.0) {
        guardadoPendiente?.cancel()
        guard let ed = editor else { return }
        let ruta = url.path, alDia = self.alDia
        let tarea = DispatchWorkItem { [weak self] in
            let junto = ControladorReflujo.guardarTinta(ed, ruta: ruta, alDia: alDia)
            guard junto else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.releer() } }
        }
        guardadoPendiente = tarea
        colaGuardar.asyncAfter(deadline: .now() + espera, execute: tarea)
    }

    /// Guarda la tinta (en `colaGuardar`). `true` si se junto con lo que
    /// cambio en el disco: hay que releerla.
    private nonisolated static func guardarTinta(_ ed: EditorLienzo, ruta: String, alDia: AlDiaLector) -> Bool {
        guard ed.sinGuardar() else { return false }
        do {
            let r = try alDia.guardar(0, ed)
            if r.escrito {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .pixpinDocumentoAnotado, object: ruta)
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                }
            }
            return r.junto
        } catch {
            let texto = "\(error)"
            DispatchQueue.main.async { NSLog("PixPin: no se pudo guardar la tinta del visor: %@", texto) }
            return false
        }
    }

    /// Lo recordado, con el sitio y el aumento de ahora.
    private func lecturaDeAhora() -> LecturaReflujo? {
        guard var l = lectura else { return nil }
        if maqueta != nil { l.sitio = fraccion() }
        l.zoom = Float(desplazar.magnification)
        return l
    }

    func guardarLectura() {
        guard let l = lecturaDeAhora() else { return }
        lectura = l
        let ruta = url.path, nucleo = self.nucleo
        colaGuardar.async { try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l) }
    }

    /// Lo mismo, ya (antes de abrir la tinta, que necesita la columna).
    private func guardarLecturaYa() {
        guard let l = lecturaDeAhora() else { return }
        lectura = l
        let ruta = url.path, nucleo = self.nucleo
        colaGuardar.sync { _ = try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l) }
    }

    // MARK: Al dia con el disco

    private func empezarAMirarElDisco() {
        guard mirarDisco == nil else { return }
        let r = Timer(timeInterval: AlDiaLector.mirarCada, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirarElDisco() }
        }
        RunLoop.main.add(r, forMode: .common)
        mirarDisco = r
    }

    func mirarElDisco() {
        guard let ed = editor else { return }
        let abiertas = [0: ed.ruta()]
        let alDia = self.alDia
        colaGuardar.async { [weak self] in
            guard !alDia.cambiadas(abiertas).isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.releer() } }
        }
    }

    /// Relee la tinta si aqui no hay nada a medias (con algo a medias se
    /// junta al guardar).
    private func releer() {
        guard let viejo = editor, !viejo.sinGuardar(), !trazando else { return }
        let ruta = url.path, nucleo = self.nucleo, rutaTinta = viejo.ruta()
        Task {
            let (visto, ed) = await withCheckedContinuation { cont in
                colaGuardar.async {
                    let v = AlDiaLector.ver(rutaTinta)
                    cont.resume(returning: (v, try? nucleo.anotarReflujo(documento: ruta)))
                }
            }
            guard let ed, self.editor === viejo, !viejo.sinGuardar(), !self.trazando else { return }
            self.ponerEditor(ed)
            let alDia = self.alDia
            self.colaGuardar.async { alDia.apuntar(0, visto) }
        }
    }

    // MARK: Marcadores y espacios

    func ponerMarca(emoji: String) {
        guard var l = lectura else { return }
        l.marcadores = conMarcadorDeLectura(marcadores: l.marcadores, fraccion: fraccion(), emoji: emoji,
                                            ahora: UInt64(Date().timeIntervalSince1970 * 1000))
        modelo.poniendoMarca = false
        ponerLectura(l)
        guardarLectura()
    }

    func quitarMarcas() {
        guard var l = lectura else { return }
        l.marcadores = []
        ponerLectura(l)
        guardarLectura()
    }

    /// El verde de la voz (`parrafo`, `fraccion`), o sin el.
    func ponerVerde(_ v: VozReflujo?) {
        guard var l = lectura else { return }
        l.voz = v
        ponerLectura(l)
        guardarLectura()
    }

    /// **Un paso mas o menos de espacio a un lado** (los mandos de abajo del
    /// movil). La tinta cuenta desde el borde de la columna: ni el texto ni
    /// lo anotado se mueven.
    func espacio(izquierda: Bool, mas: Bool) {
        guard let l = lectura else { return }
        guard let nueva = otroEspacioDeLado(lectura: l, columnaMedida: columna, izquierda: izquierda, mas: mas) else {
            avisar(mas ? "No cabe más espacio a ese lado" : "Ya no hay espacio a ese lado")
            return
        }
        let fijaAhora = l.columna == 0
        ponerLectura(nueva)
        if fijaAhora { guardarLecturaYa() } else { guardarLectura() }
        ponerLimites()
    }

    func alternarCandado() {
        guard var l = lectura else { return }
        l.sinLado.toggle()
        ponerLectura(l)
        guardarLectura()
        avisar(l.sinLado ? "Solo sube y baja" : "También se mueve a los lados")
    }

    // MARK: Buscar

    private func buscar(_ q: String) -> (total: Int, primera: Int?) {
        guard let doc = documento else { return (0, nil) }
        encontradas = doc.buscar(consulta: q)
        let arriba = desplazar.contentView.bounds.minY
        let cs = maqueta?.colocados ?? []
        let primera = encontradas.firstIndex { e in
            Int(e.colocado) < cs.count && CGFloat(cs[Int(e.colocado)].y + cs[Int(e.colocado)].alto) >= arriba
        }
        return (encontradas.count, encontradas.isEmpty ? nil : primera ?? 0)
    }

    /// Marca lo encontrado y lleva la vista a la actual si no se ve: a un
    /// tercio de la ventana, que se lea tambien lo de antes.
    private func mostrarBuscada(_ actual: Int?, marcar: Bool) {
        actualBuscada = actual
        marcarBuscadas = marcar
        pagina.needsDisplay = true
        guard let a = actual, a < encontradas.count else { return }
        let e = encontradas[a]
        guard let r = cajas(de: Int(e.colocado), NSRange(location: Int(e.inicio), length: Int(e.largo))).first else { return }
        let visto = desplazar.contentView.bounds
        // Arriba queda la caja de buscar: lo que cae debajo no se ve.
        let tapado = 70 / max(desplazar.magnification, 0.0001)
        if r.minY < visto.minY + tapado || r.maxY > visto.maxY {
            irA(y: r.minY - visto.height / 3)
        }
        if r.minX < visto.minX || r.maxX > visto.maxX {
            let clip = desplazar.contentView
            var o = clip.bounds.origin
            o.x = r.minX - visto.width / 3
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
            desplazar.reflectScrolledClipView(clip)
        }
    }

    // MARK: La pagina que sube sola

    func alternarAvance() {
        if avance.activo {
            avance.activo = false
            relojAvance?.invalidate()
            relojAvance = nil
            return
        }
        guard let doc = documento, maqueta != nil else { return }
        // Son las dos barras de abajo: la una cierra la otra.
        voz.dejar()
        avance.ppm = nucleo.palabrasPorMinuto()
        avance.enMarcha = true
        avance.antes = nil
        avance.activo = true
        avance.quedan = "Contando las palabras…"
        if avance.palabras == nil {
            let n = Int(doc.palabras())
            if n == 0 {
                avance.activo = false
                avisar("Este documento no tiene texto")
                return
            }
            avance.palabras = n
        }
        ultimoQuedan = 0
        let r = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.subirSola() }
        }
        RunLoop.main.add(r, forMode: .common)
        relojAvance = r
    }

    func cambiarVelocidad(_ sentido: Int32) {
        avance.ppm = otraVelocidadDeLeer(ppm: avance.ppm, sentido: sentido)
        ultimoQuedan = 0
        let ppm = avance.ppm, nucleo = self.nucleo
        colaGuardar.async { try? nucleo.guardarPalabrasPorMinuto(ppm: ppm) }
    }

    private func subirSola() {
        guard avance.activo else { return }
        let clip = desplazar.contentView
        let alto = altoDoc
        let palabras = avance.palabras ?? 0
        let porSegundo = CGFloat(velocidadDeBajar(ppm: avance.ppm, palabras: UInt64(palabras), alto: Float(alto)))
        let ahora = CACurrentMediaTime()
        let pixel = 1 / max(ventana.backingScaleFactor * desplazar.magnification, 0.0001)
        let quieta = modelo.anotando || NSEvent.pressedMouseButtons != 0
        let d = avance.paso(ahora: ahora, porSegundo: porSegundo, quieta: quieta, pixel: pixel)
        if d > 0 {
            let antes = clip.bounds.origin.y
            irA(y: antes + d)
            if abs(clip.bounds.origin.y - antes) < pixel / 2 { avance.alFinal() }
        }
        if ahora - ultimoQuedan > 1, let n = avance.palabras {
            ultimoQuedan = ahora
            let hoy = Calendar.current.dateComponents([.hour, .minute], from: Date())
            avance.quedan = rotuloDeLoQueQueda(palabras: UInt64(n), progreso: fraccion(), ppm: avance.ppm,
                                               ahoraEnMinutos: Int64((hoy.hour ?? 0) * 60 + (hoy.minute ?? 0)))
        }
    }

    // MARK: Teclas

    /// Las que llegan antes que a quien tenga el teclado: F2, F3 y F11, y
    /// ↩ / ⎋ en las cajas.
    func teclaAntes(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 120, 99, 103: return tecla(e)
        default: break
        }
        guard ventana.firstResponder is NSText else { return false }
        let shift = e.modifierFlags.contains(.shift)
        if e.keyCode == 53, modelo.renombrando != nil { cancelarNombre(); return true }
        if modelo.renombrando == nil, buscador.abierto {
            switch e.keyCode {
            case 53:
                buscador.cerrar()
                ventana.makeFirstResponder(pagina)
                return true
            case 36, 76:
                if shift { buscador.anterior() } else { buscador.siguiente() }
                return true
            default: break
            }
        }
        return false
    }

    /// **Las teclas del visor**, las de Windows con ⌘ en vez de Ctrl.
    func tecla(_ e: NSEvent) -> Bool {
        guard e.type == .keyDown else { return false }
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let c = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let escribiendo = ventana.firstResponder is NSText
        switch e.keyCode {
        case 103: ventana.toggleFullScreen(nil); return true // F11
        case 120 where m.isEmpty: empezarRenombrar(); return true // F2
        case 99 where m.isEmpty || m == .shift: // F3 / Mayus+F3
            if m == .shift { buscador.anterior() } else { buscador.siguiente() }
            return true
        default: break
        }
        if m == [.control, .command], c == "f" { ventana.toggleFullScreen(nil); return true }
        if m == .command {
            switch c {
            case "f":
                modelo.renombrando = nil
                buscador.abrir()
                return true
            case "g": buscador.siguiente(); return true
            case "p": imprimir(); return true
            case "s": programarGuardado(espera: 0); guardarLectura(); return true
            case "0": aumento(nil); return true
            case "+", "=": aumento(1); return true
            case "-": aumento(-1); return true
            case "[": espacio(izquierda: true, mas: true); return true
            case "]": espacio(izquierda: false, mas: true); return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                if let n = Int(c), n <= modelo.marcas.count { ir(a: modelo.marcas[n - 1]) }
                return true
            default: break
            }
            if !escribiendo {
                if c == "z" { deshacer(); return true }
                if c == "y" { rehacer(); return true }
            }
        }
        if m == [.command, .shift] {
            switch c {
            case "g": buscador.anterior(); return true
            case "s": compartir(); return true
            case "+", "=": aumento(1); return true
            case "[", "{": espacio(izquierda: true, mas: false); return true
            case "]", "}": espacio(izquierda: false, mas: false); return true
            case "z" where !escribiendo: rehacer(); return true
            default: break
            }
        }
        guard !escribiendo, m.isEmpty || m == .shift else { return false }
        if modelo.poniendoMarca, let d = Int(c), m.isEmpty {
            let todos = emojisDeMarcas()
            let i = min(d == 0 ? 9 : d - 1, todos.count - 1)
            if i >= 0 { ponerMarca(emoji: todos[i]) }
            return true
        }
        let visto = desplazar.contentView.bounds.height
        switch e.keyCode {
        case 115: irA(y: 0); return true // Inicio
        case 119: irA(y: altoDoc); return true // Fin
        case 116: irA(y: desplazar.contentView.bounds.minY - visto * 0.9); return true // RePag
        case 121: irA(y: desplazar.contentView.bounds.minY + visto * 0.9); return true // AvPag
        case 49: // Espacio (con ⇧, hacia arriba)
            irA(y: desplazar.contentView.bounds.minY + (m == .shift ? -1 : 1) * visto * 0.9)
            return true
        case 125: irA(y: desplazar.contentView.bounds.minY + 60); return true
        case 126: irA(y: desplazar.contentView.bounds.minY - 60); return true
        default: break
        }
        if c == "+" { cambiarTamano(true); return true }
        if c == "-" { cambiarTamano(false); return true }
        guard m.isEmpty else { return false }
        switch c {
        case "a": elegir(modelo.anotando ? "leer" : "lapiz"); return true
        case "p": elegir("lapiz"); return true
        case "h": elegir("resaltador"); return true
        case "e": elegir("borrador"); return true
        case "m": modelo.poniendoMarca.toggle(); return true
        case "t": ponerTipo(UInt8((Int(reflujo.tipo) + 1) % BarraReflujo.tipos.count)); return true
        case "b": ponerGrosor(UInt8((Int(reflujo.grosor) + 1) % BarraReflujo.grosores.count)); return true
        case "i": mostrarIndice(); return true
        case "d": alternarAvance(); return true
        case "g": mostrarAjustes(evento: nil); return true
        case "n": alternarNegativo(); return true
        case "l": voz.escuchar(); return true
        default: return false
        }
    }

    /// **⎋ en cascada**: lo que se esta haciendo, de lo mas pequeno a lo mas
    /// grande; sin nada, a pantalla completa vuelve y en ventana se cierra.
    func escape() -> Bool {
        if modelo.renombrando != nil {
            cancelarNombre()
        } else if buscador.abierto {
            buscador.cerrar()
        } else if modelo.poniendoMarca {
            modelo.poniendoMarca = false
        } else if voz.activa {
            voz.dejar()
        } else if avance.activo {
            alternarAvance()
        } else if modelo.anotando {
            elegir("leer")
        } else if ventana.styleMask.contains(.fullScreen) {
            ventana.toggleFullScreen(nil)
        } else {
            VentanaLisa.cerrar(ventana)
        }
        return true
    }

    /// El aumento: +1 acercar, −1 alejar, `nil` la columna a su tamano (⌘0).
    private func aumento(_ paso: Int?) {
        let k: CGFloat
        switch paso {
        case nil: k = 1
        case let p? where p > 0: k = desplazar.magnification * 1.15
        default: k = desplazar.magnification / 1.15
        }
        desplazar.animator().magnification = min(max(k, desplazar.minMagnification), desplazar.maxMagnification)
    }

    // MARK: Indice, ajustes, imprimir, compartir

    /// I: el indice, en un menu donde se esta.
    func mostrarIndice() {
        guard !reflujo.indice.isEmpty else {
            avisar("Este documento no tiene índice")
            return
        }
        let menu = NSMenu()
        for e in reflujo.indice {
            let titulo = String(repeating: "   ", count: max(Int(e.nivel) - 1, 0)) + e.titulo
            let item = NSMenuItem(title: titulo, action: #selector(AccionMenuLector.hacer(_:)), keyEquivalent: "")
            let a = AccionMenuLector { [weak self] in self?.ir(aBloque: e.bloque) }
            item.target = a
            item.representedObject = a
            menu.addItem(item)
        }
        let r = contenedor.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: r.midX - 150, y: r.maxY - 70), in: contenedor)
    }

    /// G o el engranaje: lo que en Windows va en su panel.
    func mostrarAjustes(evento: NSEvent?) {
        let menu = NSMenu()
        func fila(_ titulo: String, _ tecla: String = "", _ mods: NSEvent.ModifierFlags = [],
                  marcada: Bool = false, activa: Bool = true, _ accion: @escaping @MainActor () -> Void) {
            let item = NSMenuItem(title: titulo, action: #selector(AccionMenuLector.hacer(_:)), keyEquivalent: tecla)
            item.keyEquivalentModifierMask = mods
            let a = AccionMenuLector(accion)
            item.target = a
            item.representedObject = a
            item.state = marcada ? .on : .off
            item.isEnabled = activa
            menu.addItem(item)
        }
        fila("Buscar en el documento", "f", .command) { [weak self] in self?.buscador.abrir() }
        fila("Índice (I)", activa: !reflujo.indice.isEmpty) { [weak self] in self?.mostrarIndice() }
        fila("Escuchar (L)", marcada: voz.activa && LeerEnVoz.compartida.leyendo) { [weak self] in self?.voz.escuchar() }
        let leida = LeerEnVoz.compartida
        let idioma = voz.activa ? leida.idioma : VozAlta.idiomaDeLaApp
        let puesta = VozAlta.voz(para: idioma, preferida: VozAlta.preferida(lengua: idioma))?.identifier
        let voces = NSMenuItem(title: "Voz para leer", action: nil, keyEquivalent: "")
        voces.submenu = menuDeVoces(idioma: idioma, puesta: puesta) { v in leida.ponerVoz(v) }
        menu.addItem(voces)
        fila("Desplazar sola (D)", marcada: avance.activo) { [weak self] in self?.alternarAvance() }
        fila("Negativo (N)", marcada: modelo.negativo) { [weak self] in self?.alternarNegativo() }
        fila("Modo oscuro", marcada: modelo.oscuro) { [weak self] in self?.alternarOscuro() }
        menu.addItem(.separator())
        let libre = lectura?.columna == 0
        fila("Letra más grande (+)", activa: libre) { [weak self] in self?.cambiarTamano(true) }
        fila("Letra más pequeña (−)", activa: libre) { [weak self] in self?.cambiarTamano(false) }
        fila("Otro tipo de letra (T)", activa: libre) { [weak self] in
            guard let self else { return }
            self.ponerTipo(UInt8((Int(self.reflujo.tipo) + 1) % BarraReflujo.tipos.count))
        }
        fila("Otro grosor (B)", activa: libre) { [weak self] in
            guard let self else { return }
            self.ponerGrosor(UInt8((Int(self.reflujo.grosor) + 1) % BarraReflujo.grosores.count))
        }
        menu.addItem(.separator())
        fila("Más espacio a la izquierda", "[", .command) { [weak self] in self?.espacio(izquierda: true, mas: true) }
        fila("Menos espacio a la izquierda", "[", [.command, .shift]) { [weak self] in self?.espacio(izquierda: true, mas: false) }
        fila("Más espacio a la derecha", "]", .command) { [weak self] in self?.espacio(izquierda: false, mas: true) }
        fila("Menos espacio a la derecha", "]", [.command, .shift]) { [weak self] in self?.espacio(izquierda: false, mas: false) }
        fila("Solo subir y bajar (candado)", marcada: reflujo.candado) { [weak self] in self?.alternarCandado() }
        menu.addItem(.separator())
        fila("Cambiar el nombre (F2)") { [weak self] in self?.empezarRenombrar() }
        fila("Imprimir…", "p", .command) { [weak self] in self?.imprimir() }
        fila("Compartir…", "s", [.command, .shift]) { [weak self] in self?.compartir() }
        fila("Mostrar en el Finder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.url])
        }
        if TiposDeDocumento.clase(de: url) == .officePaginado {
            fila("Ver sus páginas, como Office") { [weak self] in
                guard let self else { return }
                LectoresDeDocumentos.compartidos.abrir(self.url, nucleo: self.nucleo, titulo: self.modelo.nombre)
            }
        }
        if !(lectura?.marcadores.isEmpty ?? true) {
            menu.addItem(.separator())
            fila("Quitar los marcadores") { [weak self] in self?.quitarMarcas() }
        }
        menu.addItem(.separator())
        let ayuda = NSMenuItem(title: "A anotar · + − T B letra · M marcador · I índice · L escuchar · D desplazar sola · ⌘F buscar · ⎋ salir",
                               action: nil, keyEquivalent: "")
        ayuda.isEnabled = false
        menu.addItem(ayuda)
        if let evento, let vista = evento.window?.contentView {
            menu.popUp(positioning: nil, at: vista.convert(evento.locationInWindow, from: nil), in: vista)
        } else {
            let r = contenedor.bounds
            menu.popUp(positioning: nil, at: NSPoint(x: r.midX - 120, y: r.maxY - 60), in: contenedor)
        }
    }

    /// ⌘P: el documento entero como se ve (con su tinta), en las hojas que
    /// toquen.
    func imprimir() {
        guard maqueta != nil else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        NSPrintOperation(view: pagina, printInfo: info).runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func compartir() {
        let r = contenedor.bounds
        let ancla = NSRect(x: r.midX - 1, y: r.maxY - 10, width: 2, height: 2)
        NSSharingServicePicker(items: [url]).show(relativeTo: ancla, of: contenedor, preferredEdge: .minY)
    }

    func ponerEncima(_ si: Bool) {
        modelo.encima = si
        ventana.level = si ? .floating : .normal
    }

    // MARK: El nombre (F2)

    private func ponerNombre(_ nombre: String) {
        modelo.nombre = nombre
        ventana.title = nombre
    }

    func empezarRenombrar() {
        buscador.cerrar()
        modelo.renombrando = (modelo.nombre as NSString).deletingPathExtension
    }

    func cancelarNombre() {
        modelo.renombrando = nil
        ventana.makeFirstResponder(pagina)
    }

    /// ↩: se guarda el nombre. Lo anotado se guarda antes: un documento
    /// suelto se mueve con sus hermanos.
    func confirmarNombre(_ escrito: String) {
        cancelarNombre()
        guardadoPendiente?.cancel()
        let ed = editor, ruta = url.path, alDia = self.alDia, nucleo = self.nucleo
        let l = lecturaDeAhora()
        Task {
            let r: DocumentoRenombrado? = await withCheckedContinuation { cont in
                colaGuardar.async {
                    if let ed { _ = ControladorReflujo.guardarTinta(ed, ruta: ruta, alDia: alDia) }
                    if let l { try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l) }
                    cont.resume(returning: try? nucleo.renombrarDocumento(documento: ruta, escrito: escrito))
                }
            }
            self.renombrado(r)
        }
    }

    private func renombrado(_ r: DocumentoRenombrado?) {
        let sinExtension = { (n: String) in (n as NSString).deletingPathExtension }
        switch r {
        case .sinCambios:
            return
        case let .enElChat(nombre):
            ponerNombre(nombre)
            avisar("Ahora se llama «\(sinExtension(nombre))»")
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        case let .enDisco(nombre, ruta):
            let antes = url
            url = URL(fileURLWithPath: ruta)
            ponerNombre(nombre)
            // La tinta abierta era de la ruta de antes: se vuelve a abrir.
            editor = nil
            leido = nil
            let alDia = self.alDia
            colaGuardar.async { alDia.olvidar() }
            if lectura?.columna ?? 0 > 0 { abrirTinta(siHay: true) }
            alCambiarRuta?(self, antes)
            avisar("Ahora se llama «\(sinExtension(nombre))»")
        case let .yaExiste(nombre):
            avisar("Ya hay un archivo que se llama «\(nombre)»")
        case .noSePuede, nil:
            avisar("No se pudo cambiar el nombre")
        }
    }

    func avisar(_ texto: String) {
        modelo.nota = texto
        tareaNota?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.modelo.nota = nil } }
        tareaNota = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: t)
    }

    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        barra?.terminar()
        voz.alCerrar()
        guardadoPendiente?.cancel()
        guardarLectura()
        if let ed = editor {
            let ruta = url.path, alDia = self.alDia
            colaGuardar.async { _ = ControladorReflujo.guardarTinta(ed, ruta: ruta, alDia: alDia) }
        }
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        mirarDisco?.invalidate()
        mirarDisco = nil
        relojAvance?.invalidate()
        relojAvance = nil
        buscador.cerrar()
        editor = nil
        alCerrar?(self)
    }
}

// MARK: - Escuchar

/// **Escuchar un Word o un libro** (`visor::escuchar` de Windows): cada
/// colocado con texto es un «parrafo» de la voz; lo que suena va en ambar,
/// con la palabra que se dice mas fuerte; la vista lo sigue si se estaba
/// mirando; y el verde (`anot-<uid>.voz`, `parrafo:fraccion`) se mueve con
/// lo que se oye, asi la proxima vez se empieza por ahi, aqui, en Windows o
/// en el movil. La voz es de la app (`LeerEnVoz`): cerrar el visor no la
/// calla, y al volver a abrirlo se engancha.
@MainActor
final class VozDelReflujo: LectorEnganchado {
    weak var visor: ControladorReflujo?
    private(set) var enganchada = false
    private var engancharAlColocar = true

    init(visor: ControladorReflujo) {
        self.visor = visor
    }

    private var voz: LeerEnVoz { .compartida }
    private var clave: String { visor?.url.path ?? "" }

    var activa: Bool { enganchada && voz.suena(clave) }

    /// Donde empieza cada parrafo de la voz, de 0 a 1.
    private func fracciones(_ m: MaquetaReflujo) -> [Float] {
        let alto = max(m.alto, 1)
        return m.paraLeer.map { min(max(m.colocados[Int($0)].y / alto, 0), 1) }
    }

    /// **Escuchar** (L o el boton): con la barra puesta, play/pausa; si no,
    /// se empieza por el verde o, si no hay, por lo que asoma arriba.
    func escuchar() {
        if activa {
            voz.alternar()
            return
        }
        guard let visor, let m = visor.maqueta else { return }
        let idx = m.paraLeer.map { Int($0) }
        guard !idx.isEmpty else {
            visor.avisar("Este documento no tiene texto que leer")
            return
        }
        // Escuchar cierra la pagina que sube sola.
        if visor.avance.activo { visor.alternarAvance() }
        let fr = fracciones(m)
        let arriba = visor.desplazar.contentView.bounds.minY
        let porArriba = idx.firstIndex { CGFloat(m.colocados[$0].y + m.colocados[$0].alto) > arriba + 4 } ?? 0
        let desde = visor.lectura?.voz.flatMap { parrafoDelVerde(fracciones: fr, verde: $0) }.map { Int($0) } ?? porArriba
        // A la voz se le da el texto tal cual: las palabras que avisa caen
        // asi en su sitio del colocado y se resaltan alli.
        let parrafos = idx.map { m.colocados[$0].texto }
        let muestra = String(parrafos.dropFirst(desde).prefix(40).joined(separator: " ").prefix(4000))
        let idioma = VozAlta.idiomaParaLeer(muestra: muestra, lang: "", delEquipo: VozAlta.idiomaDeLaApp)
        let titulo = visor.documento.map { $0.titulo() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? (visor.modelo.nombre as NSString).deletingPathExtension
        let doc = LeerEnVoz.Documento(clave: clave, titulo: titulo, parrafos: parrafos, idioma: idioma,
                                      apuntar: VozDelReflujo.apuntarElVerde(ruta: clave, nucleo: visor.nucleo,
                                                                            fracciones: fr))
        guard voz.arrancar(doc, lector: self) else {
            visor.avisar("El Mac no tiene voz para «\(VozAlta.partes(idioma).lengua)»: Ajustes del Sistema › Accesibilidad › Contenido leído")
            return
        }
        enganchada = true
        voz.leer(desde: desde)
        visor.modelo.poniendoMarca = false
    }

    func dejar() {
        if activa { voz.soltar() }
    }

    /// Ya hay algo colocado: si se estaba escuchando este documento con el
    /// visor cerrado, se engancha y va al parrafo que suena.
    func alColocar() {
        guard engancharAlColocar, let visor, let m = visor.maqueta else { return }
        engancharAlColocar = false
        guard voz.suena(clave), !enganchada else { return }
        enganchada = voz.enganchar(self, clave: clave, cuantos: m.paraLeer.count)
        if enganchada, let k = m.paraLeer[safe: voz.actual].map({ Int($0) }) {
            let visto = visor.desplazar.contentView.bounds.height
            visor.irA(y: max(CGFloat(m.colocados[k].y) - visto * 0.25, 0))
            visor.sonando = k
        }
    }

    func alCerrar() {
        voz.desenganchar(self)
        enganchada = false
    }

    // MARK: Lo que avisa la voz

    /// **Suena otro parrafo**: el verde se mueve a el y, si el de antes se
    /// veia, la vista lo sigue (anotando no se mueve).
    func vozSuena(_ i: Int, primero: Bool) {
        guard let visor, let m = visor.maqueta, let k = m.paraLeer[safe: i].map({ Int($0) }) else { return }
        visor.sonando = k
        visor.palabra = nil
        let c = m.colocados[k]
        let clip = visor.desplazar.contentView.bounds
        let antesSeVeia: Bool = {
            guard !primero, i > 0, let j = m.paraLeer[safe: i - 1].map({ Int($0) }) else { return true }
            let a = m.colocados[j]
            return CGFloat(a.y + a.alto) > clip.minY && CGFloat(a.y) < clip.maxY
        }()
        let y = CGFloat(c.y), abajo = CGFloat(c.y + c.alto)
        if !visor.modelo.anotando, antesSeVeia, y < clip.minY + clip.height * 0.08 || abajo > clip.minY + clip.height * 0.85 {
            visor.irA(y: max(y - clip.height * 0.25, 0))
        }
        visor.ponerVerde(VozReflujo(parrafo: UInt32(i), fraccion: min(max(c.y / max(m.alto, 1), 0), 1)))
    }

    func vozPalabra(_ r: NSRange?) {
        visor?.palabra = r
    }

    /// Acabado el documento, el verde se quita: la proxima vez se empieza
    /// por lo que se este viendo.
    func vozAcabo() {
        visor?.sonando = nil
        visor?.palabra = nil
        visor?.ponerVerde(nil)
    }

    func vozFuera() {
        enganchada = false
        visor?.sonando = nil
        visor?.palabra = nil
    }

    /// **El verde con el visor cerrado**: la voz sigue sonando y en cada
    /// parrafo mueve el verde del documento (el que viaja); al acabar lo
    /// quita.
    static func apuntarElVerde(ruta: String, nucleo: Nucleo, fracciones: [Float]) -> @MainActor (Int?) -> Void {
        let cola = DispatchQueue(label: "pixpin.voz.verde.reflujo", qos: .utility)
        return { i in
            let verde = i.map { VozReflujo(parrafo: UInt32($0), fraccion: fracciones[safe: $0] ?? 0) }
            cola.async {
                var l = nucleo.lecturaDeReflujo(documento: ruta)
                l.voz = verde
                try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l)
            }
        }
    }
}

// MARK: - Los visores abiertos

/// **Los visores reflujados abiertos**: uno por documento.
@MainActor
public final class VisoresReflujo {
    public static let compartidos = VisoresReflujo()
    private var abiertos: [String: ControladorReflujo] = [:]

    /// Si este documento se lee en el visor reflujado: un Word de ahora o un
    /// libro (lo demas que sabe abrir tiene ya su sitio en la app).
    public nonisolated static func seLee(_ url: URL) -> Bool {
        ["docx", "docm", "epub"].contains(url.pathExtension.lowercased())
            && seAbreEnElVisor(nombre: url.lastPathComponent)
    }

    /// Abre `url` en el visor (o lo trae delante si ya estaba).
    public func abrir(_ url: URL, nucleo: Nucleo, titulo: String? = nil) {
        let clave = url.standardizedFileURL.path
        if let c = abiertos[clave] {
            c.ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let c = ControladorReflujo(url: url, nucleo: nucleo, titulo: titulo ?? url.lastPathComponent)
        c.alCerrar = { [weak self] c in
            self?.abiertos = self?.abiertos.filter { $0.value !== c } ?? [:]
        }
        c.alCambiarRuta = { [weak self] c, _ in
            guard let self else { return }
            self.abiertos = self.abiertos.filter { $0.value !== c }
            self.abiertos[c.url.standardizedFileURL.path] = c
        }
        abiertos[clave] = c
        c.abrir()
    }
}
