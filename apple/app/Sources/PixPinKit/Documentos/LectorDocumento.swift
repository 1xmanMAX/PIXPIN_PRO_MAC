// **El lector de documentos como un pin**: un PDF (o un Word o un PowerPoint
// paginados como Office) con tinta, resaltador, goma, marcadores y espacios
// para anotar a cada lado. Es `lector_pdf.rs` de Windows con las piezas de
// Apple:
//
// - Las hojas las pinta **PDFKit** (`PDFView`): desplazar, acercar, buscar y
//   elegir texto son suyos. Un Word o un PowerPoint se maquetan en Rust
//   (`DocumentoOffice`) y cada hoja se pinta una vez en un PDF de una pagina
//   (`PintorOffice`), que se va anadiendo mientras se maqueta el resto.
// - La tinta de cada hoja es un `EditorLienzo` de Rust abierto con
//   `Nucleo.anotarHoja`: el mismo `Gesto` y la misma escena que el lienzo, en
//   las unidades de la hoja (1400 de ancho), y se guarda donde la guardan
//   Windows y Android (`anot-<uid>-p<n>` y su marco) para que viaje.
// - **La tinta no tiembla**: la capa es una vista DENTRO de la del documento
//   de PDFKit, asi que se desplaza con las hojas en el mismo fotograma.
//
// Rendimiento (§4bis del plan):
// - solo se abren las tintas de las hojas que se ven (las que tienen fichero,
//   `hojasConTinta`, o la que se empieza a anotar), con tope; lo que se pinta
//   de cada una se pide a Rust una vez por cambio (`plano`), no por fotograma;
// - guardar va solo, 1 s despues del ultimo trazo, en una cola `.utility`;
// - leyendo (sin herramienta) la capa no recibe el raton: PDFKit elige texto.
//
// Las teclas son las de Windows con ⌘ en vez de Ctrl (tanda B7): ⌘F buscar
// (`BuscadorLector`), ⌘G / ⇧⌘G (y F3) la siguiente y la anterior, ⌘1…9 ir
// al marcador, M poner uno (con su cifra), N negativo y la luna/sol oscuro
// (`TonoLector`), D la pagina que sube sola (`AvanceLector`), G los
// ajustes, F2 cambiar el nombre, ⌘P imprimir, ⇧⌘S compartir, F5 presentar,
// + / − y ⌘0 el aumento, y ⎋ en cascada. La tinta que cambia en el disco
// con el lector abierto se relee o se junta (`AlDiaLector`). L escucha el
// documento en voz alta (D2, `VozDelLector`).

import AppKit
import Combine
import PDFKit
import PixPinCore
import SwiftUI

public extension Notification.Name {
    /// Se guardo lo anotado de un documento: `object` es su ruta.
    static let pixpinDocumentoAnotado = Notification.Name("PixPinDocumentoAnotado")
    /// Cambio el modo oscuro de los visores (luna/sol): `object` es el `Bool`.
    static let pixpinLectoresOscuros = Notification.Name("PixPinLectoresOscuros")
}

/// Los colores de la tinta del lector (la paleta de Excalidraw, como el
/// movil y Windows).
public struct ColorTinta: Identifiable, Equatable, Sendable {
    public let id: String
    public let r: Float, g: Float, b: Float

    public static let todos: [ColorTinta] = [
        .init(id: "negro", r: 0.118, g: 0.118, b: 0.118),
        .init(id: "rojo", r: 0.878, g: 0.192, b: 0.192),
        .init(id: "azul", r: 0.098, g: 0.443, b: 0.761),
        .init(id: "verde", r: 0.184, g: 0.620, b: 0.267),
        .init(id: "amarillo", r: 1.0, g: 0.831, b: 0.231),
    ]

    var color: Color { Color(red: Double(r), green: Double(g), blue: Double(b)) }
}

/// Lo que ve la barra del lector.
@MainActor
public final class ModeloLector: ObservableObject {
    /// `leer`, `lapiz`, `resaltador` o `borrador`.
    @Published public var herramienta = "leer"
    @Published public var color = ColorTinta.todos[0]
    @Published public var espacios: UInt8 = 0
    @Published public var marcas: [MarcaDocumento] = []
    @Published public var pagina = 0
    @Published public var paginas = 0
    @Published public var encima = false
    @Published public var maquetando = false
    @Published public var donde: DondeAnota = .juntoAlDocumento
    @Published public var aviso: String?
    /// El nombre que se ensena (el del mensaje si es de un chat).
    @Published public var nombre = ""
    /// Cambiando el nombre (F2): lo escrito.
    @Published public var renombrando: String?
    /// Un aviso que se va solo («Ahora se llama…»).
    @Published public var nota: String?
    /// Eligiendo el emoticono de un marcador nuevo (M).
    @Published public var poniendoMarca = false
    @Published public var negativo = false
    @Published public var oscuro = false
    @Published public var presentando = false
    @Published public var esPresentacion = false

    weak var controlador: ControladorLector?

    public var anotando: Bool { herramienta != "leer" }
}

/// **La barra del lector**, como la de Windows (`lector_pin.rs`): flota
/// encima de la ventana y sale con el raton (`BarraFlotante`). El asa y el
/// nombre a la izquierda (un clic lo cambia, F2), las herramientas, los
/// botones propios del lector como alla (presentar un PowerPoint, la pagina
/// que sube sola y los ajustes), la luna/sol y al final pantalla completa,
/// el pin (siempre encima) y la ✕.
struct BarraLector: View {
    @ObservedObject var modelo: ModeloLector
    @ObservedObject var avance: AvanceLector
    @ObservedObject var voz = LeerEnVoz.compartida

    /// El nombre con la hoja que se ve: «Tema 3 · 4/20» (como Windows).
    private var nombre: String {
        modelo.paginas > 1 ? "\(modelo.nombre) · \(modelo.pagina + 1)/\(modelo.paginas)" : modelo.nombre
    }

    var body: some View {
        BarraVisor(nombre: nombre, ext: modelo.controlador?.url.pathExtension ?? "",
                 renombrar: { modelo.controlador?.empezarRenombrar() },
                 oscuro: modelo.oscuro, alternarOscuro: { modelo.controlador?.alternarOscuro() },
                 fijar: { modelo.controlador?.ponerEncima($0) }) {
            if modelo.esPresentacion {
                BotonFlotante(simbolo: "play.fill", ayuda: "Presentar (F5)", encendido: modelo.presentando) {
                    modelo.controlador?.presentar()
                }
            }
            BotonVerEditar(editando: modelo.anotando) { modelo.controlador?.alternarEditar() }
            BotonFlotante(simbolo: "speaker.wave.2", ayuda: "Leer en voz alta (L)",
                          encendido: modelo.controlador?.voz.activa == true && voz.vivo) {
                modelo.controlador?.voz.escuchar()
            }
            BotonFlotante(simbolo: "chevron.down.2", ayuda: "Desplazar sola (D)", encendido: avance.activo) {
                modelo.controlador?.alternarAvance()
            }
            Menu {
                Section("Poner aquí") {
                    ForEach(emojisDeMarcas(), id: \.self) { e in
                        Button(e) { modelo.controlador?.ponerMarca(emoji: e) }
                    }
                }
                if !modelo.marcas.isEmpty {
                    Section("Ir a") {
                        ForEach(modelo.marcas, id: \.id) { m in
                            Button("\(m.emoji)  pág. \(Int(m.y) + 1)") { modelo.controlador?.ir(a: m) }
                        }
                    }
                    Button("Quitar todos", role: .destructive) { modelo.controlador?.quitarMarcas() }
                }
            } label: {
                Image(systemName: "bookmark")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .frame(width: 40)
            .help("Marcadores (M)")
            BotonFlotante(simbolo: "square.and.arrow.up", ayuda: "Compartir") {
                modelo.controlador?.compartir()
            }
            BotonFlotante(simbolo: "gearshape", ayuda: "Ajustes (G)") {
                modelo.controlador?.mostrarAjustes(evento: NSApp.currentEvent)
            }
        }
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

/// La ventana del lector: recoge las teclas del lector antes que nadie.
final class VentanaLectorNS: NSWindow {
    weak var controlador: ControladorLector?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let c = controlador, c.tecla(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let c = controlador, c.tecla(event) { return }
        super.keyDown(with: event)
    }

    /// Lo que no puede esperar a quien tiene el teclado: las teclas de
    /// funcion (la caja de texto se las comeria) y ↩ / ⎋ en la caja de
    /// buscar o del nombre.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let c = controlador, c.teclaAntes(event) { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        if controlador?.escape() != true { super.cancelOperation(sender) }
    }
}

/// **La capa de la tinta**, dentro de la vista del documento de PDFKit.
final class CapaTintaNS: NSView {
    weak var controlador: ControladorLector?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Leyendo, el raton es de PDFKit (elegir texto, enlaces).
        guard let c = controlador, c.modelo.anotando else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        controlador?.pintarCapa(en: ctx, sucio: dirtyRect, capa: self)
    }

    override func mouseDown(with event: NSEvent) { controlador?.puntero(.pulsar, event, capa: self) }
    override func mouseDragged(with event: NSEvent) { controlador?.puntero(.mover, event, capa: self) }
    override func mouseUp(with event: NSEvent) { controlador?.puntero(.soltar, event, capa: self) }

    override func rightMouseDown(with event: NSEvent) {
        if controlador?.quitarMarca(en: convert(event.locationInWindow, from: nil), capa: self) != true {
            super.rightMouseDown(with: event)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
}

/// **Un documento abierto en el lector.**
@MainActor
public final class ControladorLector: NSObject, NSWindowDelegate {
    /// La ruta del documento: cambia si se renombra un documento suelto.
    private(set) var url: URL
    let nucleo: Nucleo
    let modelo = ModeloLector()
    let buscador = BuscadorLector()
    let avance = AvanceLector()
    /// Escuchar en voz alta (L): los trozos y lo que suena (D2).
    private(set) lazy var voz = VozDelLector(lector: self)
    let ventana: VentanaLectorNS
    let vistaPDF = PDFView()
    private let capa = CapaTintaNS()
    private let contenedor = NSView()
    private let riel = RielMarcasNS()
    /// La barra, fuera de la ventana (sale con el raton).
    private var barra: BarraFlotante?
    /// Lo que se sabe del disco de cada tinta (solo en `colaGuardar`).
    private let alDia = AlDiaLector()
    private var mirarDisco: Timer?
    private var releyendo: Set<Int> = []
    private var relojAvance: Timer?
    private var ultimoQuedan: CFTimeInterval = 0
    private var tareaNota: DispatchWorkItem?
    /// La tinta adaptada al papel oscuro de cada hoja, y lo ya adaptado.
    private var adaptadas: [Int: (version: UInt64, papel: ColorLienzo, lienzo: LienzoLeido)] = [:]
    private var coloresAdaptados: [ColorLienzo: ColorLienzo] = [:]
    /// Como estaba la vista antes de presentar (F5).
    private var antesDePresentar: (modo: PDFDisplayMode, saltos: Bool, completa: Bool)?
    private let negro = NSView()
    /// La vista del documento que ya se vigila (para no vigilarla dos veces).
    private weak var clipVigilado: NSClipView?
    private var suscripciones: Set<AnyCancellable> = []
    /// Al cambiar de ruta (renombrar un documento suelto).
    var alCambiarRuta: (@MainActor (ControladorLector, URL) -> Void)?

    /// **Las herramientas del lienzo al editar** (el lapiz de la barra): su
    /// barra y su panel de estilo mandan sobre la tinta de todas las hojas
    /// (`lector_tinta.rs` de Windows: «la misma barra, el mismo panel de
    /// propiedades y las mismas teclas que el lienzo»).
    private(set) lazy var tinta: HerramientasDeTinta = {
        let t = HerramientasDeTinta(nucleo: nucleo)
        t.editores = { [weak self] in Array(self?.editores.values ?? [:].values) }
        t.elegir = { [weak self] h in self?.elegir(h) }
        t.deshacer = { [weak self] in self?.deshacer() }
        t.rehacer = { [weak self] in self?.rehacer() }
        t.repintar = { [weak self] in self?.capa.needsDisplay = true }
        return t
    }()

    /// La tinta de cada hoja abierta, y lo ultimo leido de ella.
    private var editores: [Int: EditorLienzo] = [:]
    private var leidos: [Int: (version: UInt64, lienzo: LienzoLeido)] = [:]
    private var cargando: Set<Int> = []
    /// Las hojas con fichero de tinta (las demas no se abren hasta anotarlas).
    private var conTinta: Set<Int> = []
    /// Por orden de uso, para soltar las mas viejas.
    private var usadas: [Int] = []
    private static let topeDeHojas = 16

    /// La hoja del trazo en curso y la ultima anotada (deshacer).
    private var hojaDelTrazo: Int?
    private var ultimaAnotada: Int?
    private var presionTrackpad: Float?

    private let colaGuardar = DispatchQueue(label: "pixpin.lector.guardar", qos: .utility)
    private var guardadoPendiente: DispatchWorkItem?
    private var tareaOffice: Task<Void, Never>?
    private var vigias: [NSObjectProtocol] = []
    var alCerrar: (@MainActor (ControladorLector) -> Void)?

    init(url: URL, nucleo: Nucleo, titulo: String) {
        self.url = url
        self.nucleo = nucleo
        ventana = VentanaLectorNS(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        super.init()
        modelo.controlador = self
        modelo.nombre = titulo
        modelo.esPresentacion = ["ppt", "pptx", "pptm", "ppsx"].contains(url.pathExtension.lowercased())
        ventana.controlador = self
        ventana.title = titulo
        // Lisa y sin marco, como el lector de Windows: su barra flota fuera.
        VentanaLisa.vestirEntera(ventana)
        ventana.isReleasedWhenClosed = false
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.delegate = self
        montar()
    }

    private func montar() {
        // El documento ocupa la ventana entera; la barra flota fuera.
        vistaPDF.displayMode = .singlePageContinuous
        vistaPDF.displaysPageBreaks = true
        vistaPDF.autoScales = true
        vistaPDF.backgroundColor = NSColor.windowBackgroundColor
        // Encima del documento, dentro de la ventana: arriba en medio la caja
        // de buscar, la del nombre y los avisos; abajo la tira de marcadores
        // y la barra de la pagina que sube sola; a la derecha, el riel.
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
        negro.wantsLayer = true
        negro.layer?.backgroundColor = NSColor.black.cgColor
        negro.isHidden = true
        for v in [vistaPDF, negro, riel, arriba, abajo] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        NSLayoutConstraint.activate([
            vistaPDF.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            vistaPDF.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            vistaPDF.topAnchor.constraint(equalTo: contenedor.topAnchor),
            vistaPDF.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
            negro.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            negro.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            negro.topAnchor.constraint(equalTo: contenedor.topAnchor),
            negro.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
            riel.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor, constant: -18),
            riel.widthAnchor.constraint(equalToConstant: RielMarcasNS.lado),
            riel.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: 40),
            riel.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -40),
            arriba.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            arriba.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: 14),
            abajo.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            abajo.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -22),
        ])
        tinta.montar(en: contenedor, modelo: modelo)
        riel.ir = { [weak self] m in self?.ir(a: m) }
        // El riel sigue a los marcadores, los ponga quien los ponga.
        modelo.$marcas.sink { [weak riel] m in riel?.marcas = m }.store(in: &suscripciones)
        ventana.contentView = contenedor
        ventana.setContentSize(NSSize(width: 900, height: 1000))
        ventana.center()
        _ = ventana.setFrameAutosaveName("PixPinLector")
        capa.controlador = self
        let barra = BarraFlotante(ventana: ventana) { BarraLector(modelo: modelo, avance: avance) }
        barra.fija = { modelo.aviso != nil }
        self.barra = barra
        buscador.documento = { [weak self] in (self?.vistaPDF.document, self?.modelo.pagina ?? 0) }
        buscador.mostrar = { [weak self] actual, todas in self?.mostrarBusqueda(actual, todas) }
        let centro = NotificationCenter.default
        for nombre in [Notification.Name.PDFViewScaleChanged, .PDFViewPageChanged, .PDFViewDocumentChanged] {
            vigias.append(centro.addObserver(forName: nombre, object: vistaPDF, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.alMoverse() }
            })
        }
        // Lo anotado por otro en este documento (el asistente, la
        // sincronizacion): se mira el disco ya, sin esperar a la vuelta.
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

    // MARK: Abrir

    /// Lee lo recordado y pone el documento. Un Word o un PowerPoint se
    /// maquetan en segundo plano, hoja a hoja.
    func abrir() {
        ventana.makeKeyAndOrderFront(nil)
        barra?.empezar()
        NSApp.activate()
        let ruta = url.path
        let nucleo = self.nucleo
        Task {
            // Lo recordado: unos ficheros pequenos, pero mira tambien si es
            // el PDF de algun proyecto. Fuera del hilo principal.
            let (lectura, nombre, oscuros) = await Task.detached(priority: .userInitiated) {
                (nucleo.lecturaDeDocumento(documento: ruta), nucleo.nombreDeDocumento(documento: ruta),
                 nucleo.lectoresOscuros())
            }.value
            self.modelo.espacios = lectura.espacios
            self.modelo.marcas = lectura.marcas
            self.modelo.donde = lectura.donde
            self.ponerNombre(nombre)
            // Nunca tocado: manda el aspecto del Mac, como alla el de Windows.
            self.modelo.oscuro = oscuros ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            switch TiposDeDocumento.clase(de: self.url) {
            case .officePaginado:
                self.abrirOffice(lectura)
            default:
                guard let doc = ControladorLector.documento(url: self.url) else {
                    self.modelo.aviso = "No se puede abrir este PDF."
                    return
                }
                self.poner(doc, lectura: lectura)
            }
        }
    }

    /// Un PDF con hojas del lector (las que saben pintarse en negativo).
    static func documento(url: URL) -> PDFDocument? {
        let doc = PDFDocument(url: url)
        doc?.delegate = DelegadoHojas.compartido
        return doc
    }

    private func poner(_ doc: PDFDocument, lectura: LecturaDocumento) {
        TonosDeDocumentos.compartidos.poner(tono, a: doc)
        vistaPDF.document = doc
        modelo.paginas = doc.pageCount
        riel.paginas = doc.pageCount
        ponerFondo()
        engancharCapa()
        ponerMargenes()
        let ruta = url.path
        let n = UInt32(doc.pageCount)
        let nucleo = self.nucleo
        Task {
            let hojas = await Task.detached(priority: .userInitiated) {
                nucleo.hojasConTinta(documento: ruta, paginas: n)
            }.value
            self.conTinta = Set(hojas.map { Int($0) })
            self.cargarVisibles()
        }
        // Por donde se iba y a que aumento.
        if lectura.zoom.isFinite, abs(lectura.zoom - 1) > 0.01 {
            let ajuste = vistaPDF.scaleFactorForSizeToFit
            if ajuste > 0 {
                vistaPDF.autoScales = false
                vistaPDF.scaleFactor = ajuste * CGFloat(lectura.zoom)
            }
        }
        let i = Int(lectura.pagina.rounded(.down))
        if i > 0, i < doc.pageCount, let p = doc.page(at: i) {
            vistaPDF.go(to: p)
        }
        // Se estaba escuchando con el lector cerrado: se engancha a la voz.
        voz.alAbrir()
    }

    private func abrirOffice(_ lectura: LecturaDocumento) {
        modelo.maquetando = true
        let ruta = url.path
        let nucleo = self.nucleo
        tareaOffice = Task { [weak self] in
            let abierto = await Task.detached(priority: .userInitiated) { () -> DocumentoOffice? in
                try? DocumentoOffice.abrir(ruta: ruta, medidor: MedidorCoreText())
            }.value
            guard let office = abierto else {
                self?.modelo.maquetando = false
                self?.modelo.aviso = "No se puede abrir este documento."
                return
            }
            let doc = PDFDocument()
            var n: UInt32 = 0
            while !Task.isCancelled {
                let k = n
                let pagina = await Task.detached(priority: .userInitiated) { () -> Data? in
                    guard let p = office.pagina(n: k),
                          let pintor = try? PintorOffice(pagina: p, imagen: { office.imagen(id: $0) })
                    else { return nil }
                    return pintor.pdf()
                }.value
                let suelta = pagina.flatMap { PDFDocument(data: $0) }
                suelta?.delegate = DelegadoHojas.compartido
                guard let self, let hoja = suelta?.page(at: 0) else { break }
                doc.insert(hoja, at: doc.pageCount)
                if n == 0 {
                    self.poner(doc, lectura: lectura)
                } else {
                    self.modelo.paginas = doc.pageCount
                    self.riel.paginas = doc.pageCount
                    if Int(lectura.pagina) == Int(n) { self.vistaPDF.go(to: hoja) }
                }
                n += 1
            }
            self?.modelo.maquetando = false
            self?.voz.alAbrir()
            if let self, doc.pageCount > 0 {
                let total = UInt32(doc.pageCount)
                let hojas = await Task.detached(priority: .utility) {
                    nucleo.hojasConTinta(documento: ruta, paginas: total)
                }.value
                self.conTinta = Set(hojas.map { Int($0) })
                self.cargarVisibles()
            }
        }
    }

    /// La capa va dentro de la vista del documento de PDFKit: se desplaza con
    /// las hojas en el mismo fotograma.
    private func engancharCapa() {
        guard let doc = vistaPDF.documentView else { return }
        if capa.superview !== doc {
            capa.removeFromSuperview()
            capa.frame = doc.bounds
            capa.autoresizingMask = [.width, .height]
            doc.addSubview(capa)
        }
        if let clip = doc.enclosingScrollView?.contentView, clip !== clipVigilado {
            clipVigilado = clip
            clip.postsBoundsChangedNotifications = true
            vigias.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.alMoverse() }
                })
        }
    }

    // MARK: Hojas y geometria

    /// La hoja `i` en la capa (Y hacia abajo).
    private func geometria(_ pagina: PDFPage) -> GeometriaHoja {
        let enVista = vistaPDF.convert(pagina.bounds(for: vistaPDF.displayBox), from: pagina)
        return GeometriaHoja(rect: capa.convert(enVista, from: vistaPDF))
    }

    /// El alto de una hoja en unidades de la tinta (tal como se ve, girada).
    func alto(_ pagina: PDFPage) -> Float {
        let b = pagina.bounds(for: vistaPDF.displayBox)
        let girada = pagina.rotation % 180 != 0
        return GeometriaHoja.altoDeHoja(ancho: girada ? b.height : b.width, alto: girada ? b.width : b.height)
    }

    private func indice(_ p: PDFPage) -> Int {
        vistaPDF.document?.index(for: p) ?? 0
    }

    private func alMoverse() {
        if let p = vistaPDF.currentPage { modelo.pagina = indice(p) }
        cargarVisibles()
        capa.needsDisplay = true
    }

    /// Abre (fuera del hilo principal) la tinta de las hojas que se ven y
    /// tienen fichero.
    private func cargarVisibles() {
        for p in vistaPDF.visiblePages {
            let i = indice(p)
            guard conTinta.contains(i), editores[i] == nil, !cargando.contains(i) else { continue }
            cargando.insert(i)
            let ruta = url.path, h = alto(p), nucleo = self.nucleo
            Task {
                let ed = await Task.detached(priority: .userInitiated) {
                    try? nucleo.anotarHoja(documento: ruta, pagina: UInt32(i), alto: h)
                }.value
                self.cargando.remove(i)
                if let ed, self.editores[i] == nil {
                    self.guardarEditor(ed, en: i)
                    self.capa.needsDisplay = true
                }
            }
        }
    }

    private func guardarEditor(_ ed: EditorLienzo, en i: Int) {
        editores[i] = ed
        aplicarHerramienta(ed)
        usar(i)
        empezarAMirarElDisco()
    }

    /// Apunta que la hoja `i` se uso; si hay demasiadas abiertas, se guarda y
    /// se suelta la mas vieja que no se ve.
    private func usar(_ i: Int) {
        usadas.removeAll { $0 == i }
        usadas.append(i)
        let visibles = Set(vistaPDF.visiblePages.map(indice))
        while usadas.count > ControladorLector.topeDeHojas,
              let vieja = usadas.first(where: { !visibles.contains($0) && $0 != hojaDelTrazo }) {
            usadas.removeAll { $0 == vieja }
            if let ed = editores.removeValue(forKey: vieja) {
                let alDia = self.alDia
                colaGuardar.async { _ = try? alDia.guardar(vieja, ed) }
            }
            adaptadas[vieja] = nil
            leidos[vieja] = nil
        }
    }

    /// La tinta de la hoja `i`, abriendola ya si hace falta (al empezar a
    /// anotar en ella).
    private func editor(_ i: Int, pagina: PDFPage) -> EditorLienzo? {
        if let ed = editores[i] { return ed }
        do {
            let ed = try nucleo.anotarHoja(documento: url.path, pagina: UInt32(i), alto: alto(pagina))
            guardarEditor(ed, en: i)
            return ed
        } catch {
            modelo.aviso = "No se puede anotar aquí: \(error)"
            return nil
        }
    }

    // MARK: Pintar la capa

    func pintarCapa(en ctx: CGContext, sucio: NSRect, capa: NSView) {
        let papel = tono.papel
        for p in vistaPDF.visiblePages {
            let i = indice(p)
            let g = geometria(p)
            // El papel de los espacios para anotar (en negativo u oscuro,
            // como la hoja).
            let (izq, der) = g.espacios(modelo.espacios)
            ctx.setFillColor(papel.map { $0.cg.copy(alpha: 0.92) ?? $0.cg }
                ?? NSColor.textBackgroundColor.withAlphaComponent(0.92).cgColor)
            for r in [izq, der].compactMap({ $0 }) where r.intersects(sucio) {
                ctx.fill(r)
            }
            if let ed = editores[i] {
                let v = ed.version()
                if leidos[i]?.version != v, let l = try? leerLienzo(ed.plano()) {
                    leidos[i] = (v, l)
                }
                if var l = leidos[i]?.lienzo, !l.figuras.isEmpty {
                    // Sobre papel oscuro la tinta se adapta, como en Windows.
                    if let papel {
                        if let a = adaptadas[i], a.version == v, a.papel == papel {
                            l = a.lienzo
                        } else {
                            l = l.sobrePapel(papel, cache: &coloresAdaptados)
                            adaptadas[i] = (v, papel, l)
                        }
                    }
                    ctx.saveGState()
                    ctx.concatenate(g.transformacion)
                    let k = max(g.escala, 0.0001)
                    let visible = CGRect(x: (sucio.minX - g.rect.minX) / k, y: (sucio.minY - g.rect.minY) / k,
                                         width: sucio.width / k, height: sucio.height / k)
                    PintorLienzo(lienzo: l).pintar(en: ctx, limites: visible)
                    ctx.restoreGState()
                }
            }
            // Los marcadores de esta hoja, con su emoticono.
            for m in modelo.marcas {
                guard let punto = g.punto(de: m, pagina: i) else { continue }
                let lado: CGFloat = 20
                let r = CGRect(x: punto.x - lado / 2, y: punto.y - lado / 2, width: lado, height: lado)
                guard r.intersects(sucio) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                (m.emoji as NSString).draw(in: r, withAttributes: [.font: NSFont.systemFont(ofSize: lado * 0.8)])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // MARK: Anotar

    private func aplicarHerramienta(_ ed: EditorLienzo) {
        tinta.aplicar(a: ed, herramienta: modelo.anotando ? modelo.herramienta : "lapiz", color: modelo.color)
    }

    /// **El lapiz de la barra**: pasa a editar con las herramientas del
    /// lienzo; el ojo vuelve a ver.
    func alternarEditar() {
        if modelo.anotando {
            elegir("leer")
        } else {
            elegir(tinta.alEmpezar)
        }
    }

    func elegir(_ h: String) {
        modelo.herramienta = h
        // La barra del lienzo ensena la misma (si se cambio con una tecla).
        tinta.ensenar(h)
        if h == "resaltador", modelo.color == ColorTinta.todos[0] {
            modelo.color = ColorTinta.todos[4]
        }
        for ed in editores.values { aplicarHerramienta(ed) }
        ventana.invalidateCursorRects(for: capa)
        capa.needsDisplay = true
    }

    func ponerColor(_ c: ColorTinta) {
        modelo.color = c
        if !modelo.anotando { modelo.herramienta = "lapiz" }
        for ed in editores.values { aplicarHerramienta(ed) }
    }

    func puntero(_ fase: FasePuntero, _ evento: NSEvent, capa: NSView) {
        let p = capa.convert(evento.locationInWindow, from: nil)
        if fase == .pulsar {
            let enVista = vistaPDF.convert(p, from: capa)
            guard let pagina = vistaPDF.page(for: enVista, nearest: true) else { return }
            hojaDelTrazo = indice(pagina)
            presionTrackpad = nil
        }
        guard let i = hojaDelTrazo, let pagina = vistaPDF.document?.page(at: i),
              let ed = editor(i, pagina: pagina) else { return }
        let g = geometria(pagina)
        let q = g.aHoja(p)
        let presion: Float? = evento.subtype == .tabletPoint ? Float(evento.pressure) : presionTrackpad
        var mods: UInt32 = 0
        if evento.modifierFlags.contains(.shift) { mods |= 1 }
        if evento.modifierFlags.contains(.option) { mods |= 2 }
        _ = ed.puntero(fase: fase, x: Float(q.x), y: Float(q.y), presion: presion, modificadores: mods,
                       zoom: Float(g.escala))
        // Repintar solo la hoja (y sus margenes).
        capa.setNeedsDisplay(g.rect.insetBy(dx: -g.rect.width * 0.8, dy: -20))
        if fase == .soltar || fase == .cancelar {
            conTinta.insert(i)
            ultimaAnotada = i
            hojaDelTrazo = nil
            usar(i)
            programarGuardado()
        }
    }

    func deshacer() {
        guard let i = ultimaAnotada, let ed = editores[i] else { return }
        if ed.deshacer() {
            capa.needsDisplay = true
            programarGuardado()
        }
    }

    func rehacer() {
        guard let i = ultimaAnotada, let ed = editores[i] else { return }
        if ed.rehacer() {
            capa.needsDisplay = true
            programarGuardado()
        }
    }

    // MARK: Guardar

    private func programarGuardado(espera: TimeInterval = 1.0) {
        guardadoPendiente?.cancel()
        let pares = editores.map { ($0.key, $0.value) }
        let ruta = url.path, alDia = self.alDia
        let tarea = DispatchWorkItem { [weak self] in
            let juntas = ControladorLector.guardarTinta(pares, ruta: ruta, alDia: alDia)
            guard !juntas.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.releer(juntas) } }
        }
        guardadoPendiente = tarea
        colaGuardar.asyncAfter(deadline: .now() + espera, execute: tarea)
    }

    /// Guarda la tinta con cambios (en `colaGuardar`). Devuelve las hojas
    /// que se juntaron con lo que cambio en el disco: hay que releerlas.
    private nonisolated static func guardarTinta(_ editores: [(Int, EditorLienzo)], ruta: String,
                                                 alDia: AlDiaLector) -> [Int] {
        var alguno = false
        var juntas: [Int] = []
        for (i, ed) in editores where ed.sinGuardar() {
            do {
                let r = try alDia.guardar(i, ed)
                alguno = r.escrito || alguno
                if r.junto { juntas.append(i) }
            } catch {
                let texto = "\(error)"
                DispatchQueue.main.async { NSLog("PixPin: no se pudo guardar la tinta: %@", texto) }
            }
        }
        if alguno {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pixpinDocumentoAnotado, object: ruta)
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            }
        }
        return juntas
    }

    /// Lo recordado (aumento, por donde iba, espacios y marcadores), fuera
    /// del hilo principal. `altos`: los de todas las hojas, por si cambian
    /// los espacios (ver `guardar_lectura_de_documento`).
    /// Por donde se va: la hoja de arriba de lo que se ve y en que fraccion
    /// de ella (`2.25`, un cuarto de la tercera).
    func sitioDeLaVista() -> Double {
        var pagina = Double(modelo.pagina)
        if let p = vistaPDF.currentPage {
            let g = geometria(p)
            let arriba = capa.visibleRect.minY
            let f = (arriba - g.rect.minY) / max(g.rect.height, 1)
            pagina = Double(indice(p)) + Double(min(max(f, 0), 0.999))
        }
        return pagina
    }

    /// El alto de cada hoja en unidades de la tinta (lo pide el marco).
    func altos() -> [Float] {
        guard let doc = vistaPDF.document else { return [] }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0).map(alto) }
    }

    /// Los marcadores nuevos (el verde de la voz), pintados y guardados.
    func ponerMarcas(_ m: [MarcaDocumento]) {
        modelo.marcas = m
        capa.needsDisplay = true
        guardarLectura()
    }

    private func guardarLectura() {
        guard let doc = vistaPDF.document, doc.pageCount > 0 else { return }
        let ajuste = vistaPDF.scaleFactorForSizeToFit
        let zoom = vistaPDF.autoScales || ajuste <= 0 ? 1 : Float(vistaPDF.scaleFactor / ajuste)
        let pagina = sitioDeLaVista()
        let altos = self.altos()
        let lectura = LecturaDocumento(zoom: zoom, pagina: pagina, espacios: modelo.espacios,
                                       marcas: modelo.marcas, donde: modelo.donde)
        let ruta = url.path, nucleo = self.nucleo
        colaGuardar.async {
            try? nucleo.guardarLecturaDeDocumento(documento: ruta, lectura: lectura, altos: altos)
        }
    }

    // MARK: Espacios, marcadores, ventana

    private func ponerMargenes() {
        guard let p = vistaPDF.document?.page(at: 0) else { return }
        let ancho = p.bounds(for: vistaPDF.displayBox).width * 0.75
        let izq: CGFloat = modelo.espacios & 1 != 0 ? ancho : 4
        let der: CGFloat = modelo.espacios & 2 != 0 ? ancho : 4
        vistaPDF.pageBreakMargins = NSEdgeInsets(top: 4, left: izq, bottom: 4, right: der)
        vistaPDF.layoutDocumentView()
        capa.needsDisplay = true
    }

    func alternarEspacio(_ lado: UInt8) {
        // Antes de cambiarlos, Rust apunta el marco de la tinta de antes con
        // los espacios de ahora (`fijar_lo_viejo`): se guarda ya.
        guardarLectura()
        modelo.espacios = (modelo.espacios ^ lado) & 3
        ponerMargenes()
        guardarLectura()
    }

    func ponerMarca(emoji: String) {
        guard let p = vistaPDF.currentPage else { return }
        let g = geometria(p)
        let centro = CGPoint(x: g.rect.midX, y: max(capa.visibleRect.minY + 40, g.rect.minY))
        let (x, y) = g.sitio(de: centro, pagina: indice(p))
        modelo.marcas = conMarca(modelo.marcas, x: x, y: y, emoji: emoji,
                                 ahora: Int64(Date().timeIntervalSince1970 * 1000))
        modelo.poniendoMarca = false
        capa.needsDisplay = true
        guardarLectura()
    }

    func ir(a m: MarcaDocumento) {
        guard let doc = vistaPDF.document, let p = doc.page(at: Int(m.y.rounded(.down))) else { return }
        let b = p.bounds(for: vistaPDF.displayBox)
        let f = CGFloat(m.y - m.y.rounded(.down))
        vistaPDF.go(to: CGRect(x: b.minX, y: b.maxY - f * b.height - 40, width: 1, height: 40), on: p)
    }

    func quitarMarcas() {
        modelo.marcas = []
        capa.needsDisplay = true
        guardarLectura()
    }

    /// Clic derecho sobre un marcador: se quita. `true` si habia uno.
    func quitarMarca(en p: CGPoint, capa: NSView) -> Bool {
        for pag in vistaPDF.visiblePages {
            let g = geometria(pag), i = indice(pag)
            let cerca: (MarcaDocumento) -> Bool = { marca in
                guard let q = g.punto(de: marca, pagina: i) else { return false }
                return hypot(q.x - p.x, q.y - p.y) < 14
            }
            if let m = modelo.marcas.first(where: cerca) {
                modelo.marcas.removeAll { $0.id == m.id }
                capa.needsDisplay = true
                guardarLectura()
                return true
            }
        }
        return false
    }

    func ponerEncima(_ si: Bool) {
        modelo.encima = si
        ventana.level = si ? .floating : .normal
    }

    func pantallaCompleta() {
        ventana.toggleFullScreen(nil)
    }

    // MARK: Teclas

    /// Las teclas que llegan antes que a quien tenga el teclado (ver
    /// `VentanaLectorNS.sendEvent`): F2, F3, F5 y F11, y ↩ / ⎋ en las cajas.
    func teclaAntes(_ e: NSEvent) -> Bool {
        // Escribiendo un texto de la tinta, las teclas son del texto.
        if modelo.anotando, tinta.teclaAlTexto(e) { return true }
        switch e.keyCode {
        case 120, 99, 96, 103: return tecla(e)
        default: break
        }
        guard ventana.firstResponder is NSText else { return false }
        let shift = e.modifierFlags.contains(.shift)
        if e.keyCode == 53, modelo.renombrando != nil { cancelarNombre(); return true }
        if modelo.renombrando == nil, buscador.abierto {
            switch e.keyCode {
            case 53:
                buscador.cerrar()
                ventana.makeFirstResponder(vistaPDF)
                return true
            case 36, 76:
                if shift { buscador.anterior() } else { buscador.siguiente() }
                return true
            default: break
            }
        }
        return false
    }

    /// **Las teclas del lector**, las de Windows con ⌘ en vez de Ctrl.
    /// `true` si era suya.
    func tecla(_ e: NSEvent) -> Bool {
        guard e.type == .keyDown else { return false }
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let c = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let escribiendo = ventana.firstResponder is NSText
        // Las de funcion valen siempre.
        switch e.keyCode {
        case 103: pantallaCompleta(); return true // F11, como en Windows
        case 120 where m.isEmpty: empezarRenombrar(); return true // F2
        case 99 where m.isEmpty || m == .shift: // F3 / Mayus+F3
            if m == .shift { buscador.anterior() } else { buscador.siguiente() }
            return true
        case 96 where m.isEmpty: presentar(); return true // F5
        default: break
        }
        if m == [.control, .command], c == "f" { pantallaCompleta(); return true }
        if m == .command {
            switch c {
            case "f":
                modelo.renombrando = nil
                buscador.abrir()
                return true
            case "g": buscador.siguiente(); return true
            case "p": imprimir(); return true
            case "s": programarGuardado(espera: 0); return true
            case "0": aumento(nil); return true
            case "+", "=": aumento(1); return true
            case "-": aumento(-1); return true
            case "[": alternarEspacio(1); return true
            case "]": alternarEspacio(2); return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                // ⌘1…9: al marcador de ese orden (el del riel).
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
            case "z" where !escribiendo: rehacer(); return true
            default: break
            }
        }
        // Sin ⌘, y solo si no se esta escribiendo en otra cosa.
        guard !escribiendo, m.isEmpty || m == .shift else { return false }
        if modelo.presentando, teclaDePresentar(e, c) { return true }
        if modelo.poniendoMarca, let d = Int(c), m.isEmpty {
            // La cifra elige el emoticono (`emoji_de_cifra`: 1…9 y el 0 el decimo).
            let todos = emojisDeMarcas()
            let i = min(d == 0 ? 9 : d - 1, todos.count - 1)
            if i >= 0 { ponerMarca(emoji: todos[i]) }
            return true
        }
        switch e.keyCode {
        case 115: vistaPDF.goToFirstPage(nil); return true // Inicio
        case 119: vistaPDF.goToLastPage(nil); return true // Fin
        default: break
        }
        if c == "+" { aumento(1); return true }
        if c == "-" { aumento(-1); return true }
        guard m.isEmpty else { return false }
        switch c {
        case "a": elegir(modelo.anotando ? "leer" : "lapiz"); return true
        case "p": elegir("lapiz"); return true
        case "h": elegir("resaltador"); return true
        case "e": elegir("borrador"); return true
        case "m": modelo.poniendoMarca.toggle(); return true
        case "d": alternarAvance(); return true
        case "g": mostrarAjustes(evento: nil); return true
        case "n": alternarNegativo(); return true
        case "l": voz.escuchar(); return true
        default: return false
        }
    }

    /// **⎋ en cascada**, como en Windows: lo que se esta haciendo, de lo mas
    /// pequeno a lo mas grande; sin nada, a pantalla completa vuelve a pin y
    /// en pin se cierra. `true` si hizo algo.
    func escape() -> Bool {
        if modelo.renombrando != nil {
            cancelarNombre()
        } else if buscador.abierto {
            buscador.cerrar()
        } else if modelo.presentando {
            presentar()
        } else if vistaPDF.currentSelection != nil {
            vistaPDF.clearSelection()
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

    /// El aumento: +1 acercar, −1 alejar, `nil` la hoja a lo ancho (⌘0).
    private func aumento(_ paso: Int?) {
        switch paso {
        case nil: vistaPDF.autoScales = true
        case let p? where p > 0: vistaPDF.zoomIn(nil)
        default: vistaPDF.zoomOut(nil)
        }
    }

    // MARK: Buscar

    private func mostrarBusqueda(_ actual: PDFSelection?, _ todas: [PDFSelection]) {
        vistaPDF.highlightedSelections = todas.isEmpty ? nil : todas
        if let actual {
            vistaPDF.go(to: actual)
            vistaPDF.setCurrentSelection(actual, animate: true)
        } else if todas.isEmpty {
            vistaPDF.clearSelection()
        }
    }

    // MARK: Negativo y oscuro

    var tono: TonoHojas { TonoHojas(negativo: modelo.negativo, oscuro: modelo.oscuro) }

    /// N: las hojas en negativo y vuelta, como en los pines.
    func alternarNegativo() {
        modelo.negativo.toggle()
        aplicarTono()
    }

    /// La luna/sol: el modo oscuro de todos los visores, que se recuerda.
    func alternarOscuro() {
        modelo.oscuro.toggle()
        aplicarTono()
        let oscuro = modelo.oscuro, nucleo = self.nucleo
        colaGuardar.async { try? nucleo.guardarLectoresOscuros(oscuros: oscuro) }
        NotificationCenter.default.post(name: .pixpinLectoresOscuros, object: oscuro)
    }

    private func ponerFondo() {
        vistaPDF.backgroundColor = modelo.presentando ? .black
            : modelo.oscuro ? NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)
            : NSColor.windowBackgroundColor
    }

    /// Las hojas, con el tono de ahora: PDFKit guarda lo ya pintado de cada
    /// hoja, asi que se le vuelve a dar el documento (en el mismo sitio y al
    /// mismo aumento).
    func aplicarTono() {
        ponerFondo()
        adaptadas = [:]
        coloresAdaptados = [:]
        capa.needsDisplay = true
        guard let doc = vistaPDF.document else { return }
        TonosDeDocumentos.compartidos.poner(tono, a: doc)
        let destino = vistaPDF.currentDestination
        let auto = vistaPDF.autoScales, escala = vistaPDF.scaleFactor
        vistaPDF.document = nil
        vistaPDF.document = doc
        vistaPDF.autoScales = auto
        if !auto { vistaPDF.scaleFactor = escala }
        if let destino { vistaPDF.go(to: destino) }
        ponerMargenes()
        engancharCapa()
        capa.frame = vistaPDF.documentView?.bounds ?? capa.frame
        if buscador.abierto { buscador.abrir() }
    }

    // MARK: La pagina que sube sola

    /// D: pone o quita la barra de la pagina que sube sola.
    func alternarAvance() {
        if avance.activo {
            avance.activo = false
            relojAvance?.invalidate()
            relojAvance = nil
            return
        }
        guard let doc = vistaPDF.document, doc.pageCount > 0 else { return }
        avance.ppm = nucleo.palabrasPorMinuto()
        avance.enMarcha = true
        avance.antes = nil
        avance.activo = true
        avance.quedan = "Contando las palabras…"
        if avance.palabras == nil { contarPalabrasDelDocumento(doc) }
        let r = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.subirSola() }
        }
        RunLoop.main.add(r, forMode: .common)
        relojAvance = r
    }

    /// Las palabras del documento, fuera del hilo principal (un PDF se abre
    /// otra vez alli; un Word o un PowerPoint ya maquetado se lee aqui). Un
    /// escaneo cuenta 250 por hoja, lo de una pagina corriente.
    private func contarPalabrasDelDocumento(_ doc: PDFDocument) {
        let hojas = doc.pageCount
        let deOffice = TiposDeDocumento.clase(de: url) == .officePaginado
        let texto = deOffice ? (doc.string ?? "") : nil
        let url = self.url
        Task {
            let n = await Task.detached(priority: .utility) { () -> Int in
                let t = texto ?? PDFDocument(url: url)?.string ?? ""
                return Int(contarPalabras(texto: t))
            }.value
            self.avance.palabras = n > 0 ? n : hojas * 250
            self.ultimoQuedan = 0
        }
    }

    func cambiarVelocidad(_ sentido: Int32) {
        avance.ppm = otraVelocidadDeLeer(ppm: avance.ppm, sentido: sentido)
        ultimoQuedan = 0
        let ppm = avance.ppm, nucleo = self.nucleo
        colaGuardar.async { try? nucleo.guardarPalabrasPorMinuto(ppm: ppm) }
    }

    /// Una vuelta: baja lo que toque y, cada segundo, lo que queda.
    private func subirSola() {
        guard avance.activo, let doc = vistaPDF.documentView,
              let scroll = doc.enclosingScrollView else { return }
        let clip = scroll.contentView
        let alto = doc.bounds.height
        let palabras = avance.palabras ?? 0
        let porSegundo = CGFloat(velocidadDeBajar(ppm: avance.ppm, palabras: UInt64(palabras), alto: Float(alto)))
        let ahora = CACurrentMediaTime()
        let pixel = 1 / max(ventana.backingScaleFactor, 1)
        let quieta = modelo.anotando || avance.palabras == nil || NSEvent.pressedMouseButtons != 0
        let d = avance.paso(ahora: ahora, porSegundo: porSegundo, quieta: quieta, pixel: pixel)
        if d > 0 {
            let antes = clip.bounds.origin
            var o = antes
            o.y += doc.isFlipped ? d : -d
            let destino = clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin
            clip.scroll(to: destino)
            scroll.reflectScrolledClipView(clip)
            if abs(clip.bounds.origin.y - antes.y) < pixel / 2 { avance.alFinal() }
        }
        if ahora - ultimoQuedan > 1, let n = avance.palabras {
            ultimoQuedan = ahora
            let vista = clip.bounds
            let corrido = doc.isFlipped ? vista.minY : alto - vista.maxY
            let progreso = Float(min(max(corrido / max(alto, 1), 0), 1))
            let hoy = Calendar.current.dateComponents([.hour, .minute], from: Date())
            avance.quedan = rotuloDeLoQueQueda(palabras: UInt64(n), progreso: progreso, ppm: avance.ppm,
                                               ahoraEnMinutos: Int64((hoy.hour ?? 0) * 60 + (hoy.minute ?? 0)))
        }
    }

    // MARK: Ajustes, imprimir, compartir

    /// G o el engranaje: lo que alla va en el panel de ajustes.
    func mostrarAjustes(evento: NSEvent?) {
        let menu = NSMenu()
        func fila(_ titulo: String, _ tecla: String = "", _ mods: NSEvent.ModifierFlags = [],
                  marcada: Bool = false, _ accion: @escaping @MainActor () -> Void) {
            let item = NSMenuItem(title: titulo, action: #selector(AccionMenuLector.hacer(_:)), keyEquivalent: tecla)
            item.keyEquivalentModifierMask = mods
            let a = AccionMenuLector(accion)
            item.target = a
            item.representedObject = a
            item.state = marcada ? .on : .off
            menu.addItem(item)
        }
        fila("Buscar en el documento", "f", .command) { [weak self] in self?.buscador.abrir() }
        if modelo.esPresentacion {
            fila("Presentar (F5)", marcada: modelo.presentando) { [weak self] in self?.presentar() }
        }
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
        fila("Cambiar el nombre (F2)") { [weak self] in self?.empezarRenombrar() }
        fila("Imprimir…", "p", .command) { [weak self] in self?.imprimir() }
        fila("Compartir…", "s", [.command, .shift]) { [weak self] in self?.compartir() }
        fila("Mostrar en el Finder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.url])
        }
        if !modelo.marcas.isEmpty {
            menu.addItem(.separator())
            fila("Quitar los marcadores") { [weak self] in self?.quitarMarcas() }
        }
        menu.addItem(.separator())
        let ayuda = NSMenuItem(title: "A anotar · M marcador · ⌘1…9 ir a él · N negativo · L escuchar · D desplazar sola · ⌘F buscar · ⎋ salir",
                               action: nil, keyEquivalent: "")
        ayuda.isEnabled = false
        menu.addItem(ayuda)
        if let evento, let vista = evento.window?.contentView {
            menu.popUp(positioning: nil, at: vista.convert(evento.locationInWindow, from: nil), in: vista)
        } else {
            let r = contenedor.bounds
            menu.popUp(positioning: nil, at: NSPoint(x: r.midX - 120, y: contenedor.isFlipped ? 60 : r.maxY - 60),
                       in: contenedor)
        }
    }

    /// ⌘P: el dialogo de imprimir del Mac, con las hojas a su tamano.
    func imprimir() {
        guard vistaPDF.document != nil else { return }
        vistaPDF.print(with: NSPrintInfo.shared, autoRotate: true, pageScaling: .pageScaleToFit)
    }

    /// ⇧⌘S: compartir el documento con la hoja comun (D1: el original, su
    /// PDF, sus paginas como imagen; la del Mac en «Más…»). Si tiene tinta,
    /// va tambien el PDF con lo anotado encima (G5).
    func compartir() {
        var ficheros = [url]
        if !conTinta.isEmpty || !editores.isEmpty, let anotado = pdfConTinta() { ficheros.append(anotado) }
        HojaCompartir.abrir(.ficheros(titulo: url.deletingPathExtension().lastPathComponent, ficheros), almacen: nil)
    }

    /// **El PDF con la tinta quemada**: cada hoja como esta y su tinta
    /// encima (la de la capa, en unidades de 1400 de ancho y Y hacia abajo).
    /// En una carpeta temporal; `nil` si no se pudo.
    func pdfConTinta() -> URL? {
        guard let doc = vistaPDF.document else { return nil }
        let (nucleo, ruta) = (self.nucleo, url.path)
        return ControladorLector.pdfConTinta(doc, nombre: url.deletingPathExtension().lastPathComponent) { i, p in
            let ed = self.editores[i] ?? (self.conTinta.contains(i)
                ? try? nucleo.anotarHoja(documento: ruta, pagina: UInt32(i), alto: self.alto(p)) : nil)
            return ed.flatMap { try? leerLienzo($0.plano()) }
        }
    }

    /// Lo puro de [`pdfConTinta`]: cada hoja de `doc` con la tinta que diga
    /// `tinta` encima.
    static func pdfConTinta(_ doc: PDFDocument, nombre: String,
                            tinta: (Int, PDFPage) -> LienzoLeido?) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anotado-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let salida = dir.appendingPathComponent("\(nombre) (anotado).pdf")
        guard let ctx = CGContext(salida as CFURL, mediaBox: nil, nil) else { return nil }
        for i in 0 ..< doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            var caja = p.bounds(for: .cropBox)
            if p.rotation % 180 != 0 { caja = CGRect(x: 0, y: 0, width: caja.height, height: caja.width) }
            var marco = CGRect(origin: .zero, size: caja.size)
            ctx.beginPage(mediaBox: &marco)
            ctx.saveGState()
            p.draw(with: .cropBox, to: ctx)
            ctx.restoreGState()
            if let l = tinta(i, p), !l.figuras.isEmpty {
                let k = caja.width / GeometriaHoja.ancho
                ctx.saveGState()
                ctx.clip(to: marco)
                ctx.translateBy(x: 0, y: caja.height)
                ctx.scaleBy(x: k, y: -k)
                PintorLienzo(lienzo: l).pintar(en: ctx, limites: CGRect(x: 0, y: 0, width: GeometriaHoja.ancho,
                                                                         height: caja.height / k))
                ctx.restoreGState()
            }
            ctx.endPage()
        }
        ctx.closePDF()
        return FileManager.default.fileExists(atPath: salida.path) ? salida : nil
    }

    // MARK: Cambiar el nombre (F2)

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
        ventana.makeFirstResponder(vistaPDF)
    }

    /// ↩: se guarda el nombre. La tinta se guarda antes: un documento suelto
    /// se mueve con sus hermanos y la tinta abierta va con el.
    func confirmarNombre(_ escrito: String) {
        cancelarNombre()
        guardadoPendiente?.cancel()
        let pares = editores.map { ($0.key, $0.value) }
        let ruta = url.path, alDia = self.alDia, nucleo = self.nucleo
        Task {
            let r: DocumentoRenombrado? = await withCheckedContinuation { cont in
                colaGuardar.async {
                    _ = ControladorLector.guardarTinta(pares, ruta: ruta, alDia: alDia)
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
            editores = [:]
            leidos = [:]
            adaptadas = [:]
            usadas = []
            let alDia = self.alDia
            colaGuardar.async { alDia.olvidar() }
            if let n = vistaPDF.document?.pageCount {
                let nucleo = self.nucleo
                Task {
                    let hojas = await Task.detached { nucleo.hojasConTinta(documento: ruta, paginas: UInt32(n)) }.value
                    self.conTinta = Set(hojas.map { Int($0) })
                    self.cargarVisibles()
                    self.capa.needsDisplay = true
                }
            }
            alCambiarRuta?(self, antes)
            avisar("Ahora se llama «\(sinExtension(nombre))»")
        case let .yaExiste(nombre):
            avisar("Ya hay un archivo que se llama «\(nombre)»")
        case .noSePuede, nil:
            avisar("No se pudo cambiar el nombre")
        }
    }

    /// Un aviso arriba que se va solo a los 2,5 s.
    func avisar(_ texto: String) {
        modelo.nota = texto
        tareaNota?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.modelo.nota = nil } }
        tareaNota = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: t)
    }

    // MARK: Presentar (F5)

    /// F5: las hojas de una en una, a pantalla completa y sobre negro; F5 o
    /// ⎋ vuelven. Un PowerPoint se presenta como en Windows
    /// (`Diapositivas`: orador, notas, transiciones) desde la hoja que se
    /// ve, y al salir el lector se queda en la ultima que se vio.
    func presentar() {
        if antesDePresentar == nil, Diapositivas.sePresenta(url) {
            Diapositivas.presentar(url, desde: modelo.pagina) { [weak self] i in
                guard let self, let p = self.vistaPDF.document?.page(at: i) else { return }
                self.vistaPDF.go(to: p)
            }
            return
        }
        if let a = antesDePresentar {
            modelo.presentando = false
            antesDePresentar = nil
            negro.isHidden = true
            vistaPDF.displayMode = a.modo
            vistaPDF.displaysPageBreaks = a.saltos
            vistaPDF.autoScales = true
            ponerFondo()
            ponerMargenes()
            if !a.completa, ventana.styleMask.contains(.fullScreen) { ventana.toggleFullScreen(nil) }
            return
        }
        guard vistaPDF.document != nil else { return }
        antesDePresentar = (vistaPDF.displayMode, vistaPDF.displaysPageBreaks,
                            ventana.styleMask.contains(.fullScreen))
        modelo.presentando = true
        avance.activo = false
        relojAvance?.invalidate()
        relojAvance = nil
        vistaPDF.displayMode = .singlePage
        vistaPDF.displaysPageBreaks = false
        vistaPDF.autoScales = true
        ponerFondo()
        if !ventana.styleMask.contains(.fullScreen) { ventana.toggleFullScreen(nil) }
        ventana.makeFirstResponder(vistaPDF)
    }

    /// Presentando: pasar de hoja y B la pantalla en negro.
    private func teclaDePresentar(_ e: NSEvent, _ c: String) -> Bool {
        switch e.keyCode {
        case 124, 125, 121, 49, 36: vistaPDF.goToNextPage(nil); return true
        case 123, 126, 116, 51: vistaPDF.goToPreviousPage(nil); return true
        default: break
        }
        if c == "b" {
            negro.isHidden.toggle()
            return true
        }
        return false
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

    /// Mira (en la cola de guardar) si la tinta de alguna hoja abierta
    /// cambio en el disco; las que no tienen nada a medias se releen.
    func mirarElDisco() {
        guard !editores.isEmpty else { return }
        let abiertas = editores.mapValues { $0.ruta() }
        let alDia = self.alDia
        colaGuardar.async { [weak self] in
            let cambiadas = alDia.cambiadas(abiertas)
            guard !cambiadas.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.releer(cambiadas) } }
        }
    }

    /// **Relee la tinta de las hojas `hojas`** si aqui no hay nada a medias
    /// (con algo a medias se junta al guardar). La firma se apunta antes de
    /// leer y solo si lo leido llega a ponerse.
    private func releer(_ hojas: [Int]) {
        for i in hojas {
            guard let viejo = editores[i], !viejo.sinGuardar(), hojaDelTrazo != i, !releyendo.contains(i),
                  let pagina = vistaPDF.document?.page(at: i) else { continue }
            releyendo.insert(i)
            let ruta = url.path, h = alto(pagina), nucleo = self.nucleo, rutaTinta = viejo.ruta()
            Task {
                let (visto, ed) = await withCheckedContinuation { cont in
                    colaGuardar.async {
                        let v = AlDiaLector.ver(rutaTinta)
                        cont.resume(returning: (v, try? nucleo.anotarHoja(documento: ruta, pagina: UInt32(i), alto: h)))
                    }
                }
                self.releyendo.remove(i)
                // Se puso a anotar entre medias: se queda lo de aqui.
                guard let ed, self.editores[i] === viejo, !viejo.sinGuardar(), self.hojaDelTrazo != i else { return }
                self.editores[i] = ed
                self.aplicarHerramienta(ed)
                self.leidos[i] = nil
                self.adaptadas[i] = nil
                let alDia = self.alDia
                self.colaGuardar.async { alDia.apuntar(i, visto) }
                self.capa.needsDisplay = true
            }
        }
    }

    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        barra?.terminar()
        // La voz sigue sonando con el lector cerrado: solo se suelta.
        voz.alCerrar()
        tareaOffice?.cancel()
        guardadoPendiente?.cancel()
        guardarLectura()
        let pares = editores.map { ($0.key, $0.value) }
        let ruta = url.path, alDia = self.alDia
        colaGuardar.async { _ = ControladorLector.guardarTinta(pares, ruta: ruta, alDia: alDia) }
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        mirarDisco?.invalidate()
        mirarDisco = nil
        relojAvance?.invalidate()
        relojAvance = nil
        buscador.cerrar()
        self.editores = [:]
        leidos = [:]
        adaptadas = [:]
        capa.removeFromSuperview()
        if let doc = vistaPDF.document { TonosDeDocumentos.compartidos.olvidar(doc) }
        vistaPDF.document = nil
        alCerrar?(self)
    }
}

/// **Los lectores abiertos**: uno por documento.
@MainActor
public final class LectoresDeDocumentos {
    public static let compartidos = LectoresDeDocumentos()
    private var abiertos: [String: ControladorLector] = [:]

    /// Abre `url` en el lector (o lo trae delante si ya estaba).
    public func abrir(_ url: URL, nucleo: Nucleo, titulo: String? = nil) {
        let clave = url.standardizedFileURL.path
        if let c = abiertos[clave] {
            c.ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let c = ControladorLector(url: url, nucleo: nucleo, titulo: titulo ?? url.lastPathComponent)
        c.alCerrar = { [weak self] c in
            self?.abiertos = self?.abiertos.filter { $0.value !== c } ?? [:]
        }
        // Un documento suelto renombrado (F2) sigue abierto con su ruta nueva.
        c.alCambiarRuta = { [weak self] c, _ in
            guard let self else { return }
            self.abiertos = self.abiertos.filter { $0.value !== c }
            self.abiertos[c.url.standardizedFileURL.path] = c
        }
        abiertos[clave] = c
        c.abrir()
    }
}

/// Lo que hace una fila del menu de ajustes del lector (G).
@MainActor
final class AccionMenuLector: NSObject {
    private let accion: @MainActor () -> Void

    init(_ accion: @escaping @MainActor () -> Void) {
        self.accion = accion
    }

    @objc func hacer(_ sender: Any?) { accion() }
}
