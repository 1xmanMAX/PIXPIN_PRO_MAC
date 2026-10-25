// El lienzo EDITABLE en Mac: una `NSView` volteada (Y hacia abajo, como el
// mundo del lienzo) que manda el raton, el lapiz y el teclado al
// `EditorLienzo` de Rust (`pixpin-nucleo/src/editor.rs`, el `Gesto` y la
// `Escena` de `pixpin-motor2d`, los mismos de Windows) y pinta lo que le
// devuelve con el lector y el pintor de siempre (`LectorLienzo.swift`,
// `PintorLienzo.swift`).
//
// Rendimiento (§4bis del plan):
// - una llamada al puente por aviso del raton (AppKit ya los agrupa), y la
//   respuesta trae la version: si no cambio, no se repinta;
// - pintar pide a Rust SOLO lo que cae en pantalla (`planoDeVista`), una vez
//   por fotograma y solo si cambio la version, la camara o el tamano; Rust
//   guarda la geometria de lo que no cambio;
// - mover y acercar la vista no toca el documento;
// - guardar va solo, 1 s despues del ultimo cambio, en una cola de fondo
//   (`.utility`): nada de escribir JSON en el hilo principal.

import AppKit
import PixPinCore
import SwiftUI

public extension Notification.Name {
    /// Un lienzo del chat se guardo: `object` es la referencia del dibujo.
    /// La burbuja que lo ensena se vuelve a leer.
    static let pixpinLienzoGuardado = Notification.Name("PixPinLienzoGuardado")
}

// Las herramientas y la barra: `HerramientasLienzo.swift` y
// `BarraHerramientasLienzo.swift`.

/// El estado del editor que ve SwiftUI (la barra) y la vista (el lienzo).
@MainActor
public final class ModeloEditorLienzo: ObservableObject {
    public let editor: EditorLienzo
    /// La referencia del dibujo en el chat (para avisar al guardar), si viene
    /// de un chat.
    public let referencia: String?
    /// La foto de cada `id_objeto`, con su fichero (las pegadas aqui, desde
    /// su sitio temporal hasta que se cierre el editor).
    public private(set) var fotos: [UInt64: URL]

    @Published public private(set) var herramienta: String
    @Published public private(set) var puedeDeshacer = false
    @Published public private(set) var error: String?
    /// Lo que ensena la barra de estilo (lo elegido, o el «actual»).
    @Published public private(set) var estilo: EstiloLienzo
    /// Hay algo elegido: el panel de estilo sale aunque la herramienta no
    /// dibuje (para cambiarle el color a lo elegido).
    @Published public private(set) var hayElegidos = false
    /// El grupo de la barra con su desplegable abierto, si hay uno.
    @Published public var desplegado: GrupoHerramientaLienzo?
    /// **Solo mirar** (Windows, 24-oct, `mirar_editar`): arrastrar mueve el
    /// dibujo y nada se elige ni se edita; sin barra ni panel. El lapiz del
    /// riel (o ⌥R) pasa a editar donde se este, en ventana o a pantalla
    /// completa (25-oct); el lapiz otra vez (o Esc) vuelve a mirar.
    @Published public private(set) var soloMirar = false
    /// **El lienzo de su ventana** (el del chat): abre mirando y lleva el
    /// riel de la derecha (el lapiz y el marco) y el boton de quitar el
    /// panel. El anotador de la captura, los planos y los lectores no: alli
    /// se viene a pintar.
    public private(set) var conRiel = false
    /// La herramienta de antes de coger el marco con el boton del riel.
    private var antesDelMarco: String?
    /// El papel es oscuro: la barra va con el tema oscuro de Excalidraw,
    /// como en Windows (`tema_barra`).
    public let papelOscuro: Bool
    /// El nucleo, para la biblioteca de figuras y recordar la pantalla
    /// completa (`nil` en un lienzo suelto de las pruebas).
    public let nucleo: Nucleo?
    /// El nombre del lienzo, para los ficheros que se exportan.
    public let titulo: String
    /// El fondo fijo (un pin, una foto, una pagina de PDF), si lo hay.
    public let fondo: FondoLienzo?
    /// Lo que ensenan dentro los mosaicos y las lupas (`TapadoLienzo.swift`).
    private(set) lazy var tapados: PintorDeTapados = {
        let t = PintorDeTapados(editor: editor) { [weak self] id in self?.foto(id) }
        t.fondo = fondo
        return t
    }()

    /// La vista que pinta (la pone ella al nacer).
    weak var vista: VistaEditorLienzoNS?
    /// Lo que hace el boton de cerrar si el lienzo no vive en su ventana
    /// (el anotador de la captura). Sin el, cierra la ventana.
    public var alCerrar: (() -> Void)?

    /// Guardar, uno detras de otro y fuera del hilo principal.
    private let colaGuardar = DispatchQueue(label: "pixpin.lienzo.guardar", qos: .utility)
    private var guardadoPendiente: DispatchWorkItem?
    private var cambiosVistos: UInt64

    public init(editor: EditorLienzo, referencia: String? = nil, fotos: [UInt64: URL] = [:],
                nucleo: Nucleo? = nil, titulo: String = "Lienzo", fondo: FondoLienzo? = nil) {
        self.editor = editor
        self.referencia = referencia
        self.fotos = fotos
        self.nucleo = nucleo
        self.titulo = titulo
        self.fondo = fondo
        // Entra en lo exportado (su PNG, para el SVG, se pide al exportar).
        if let fondo { editor.ponerPapel(ancho: Float(fondo.tamano.width), alto: Float(fondo.tamano.height), png: nil) }
        herramienta = editor.herramientaActual()
        cambiosVistos = editor.cambios()
        puedeDeshacer = editor.puedeDeshacer()
        estilo = editor.estilo()
        let papel = (try? leerLienzo(editor.planoDeVista(x: 0, y: 0, zoom: 1, anchoPx: 1, altoPx: 1)))?.fondo
        papelOscuro = papel.map { 0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b < 0.5 } ?? false
    }

    /// **Para quien usa esta barra con otros editores** (los lectores: un
    /// editor por hoja): lo elegido, el estilo y deshacer van tambien a ellos.
    public var alElegir: ((String) -> Void)?
    public var alCambiarEstilo: ((CambioDeEstilo) -> Void)?
    public var alDeshacer: (() -> Void)?
    public var alRehacer: (() -> Void)?

    /// Lo pide la ventana del lienzo al abrirlo: con el riel y mirando.
    public func abrirMirando() {
        conRiel = true
        soloMirar = true
    }

    /// **De mirar a editar** (`mirar = false`) **o al reves**
    /// (`poner_solo_mirar` de Windows): el texto a medias entra y, al mirar,
    /// lo elegido se suelta. La herramienta se queda para cuando se edite.
    public func ponerSoloMirar(_ mirar: Bool) {
        guard mirar != soloMirar else { return }
        if editor.escribiendo() { _ = editor.terminarTexto() }
        desplegado = nil
        if mirar {
            _ = editor.puntero(fase: .cancelar, x: 0, y: 0, presion: nil, modificadores: 0,
                               zoom: Float(vista?.zoom ?? 1))
        }
        soloMirar = mirar
        vista?.trasCambio()
    }

    /// El lapiz del riel (o ⌥R).
    public func alternarMirar() { ponerSoloMirar(!soloMirar) }

    /// **El boton del marco del riel** (`DestinoRiel::Imprimir` del lienzo
    /// de Windows): coge el marco (mirando, pasa a editar) y, pulsado otra
    /// vez, vuelve a la de antes.
    public func alternarMarco() {
        if herramienta == "marco" {
            elegir(antesDelMarco.flatMap { $0 == "marco" ? nil : $0 } ?? "seleccion")
            return
        }
        ponerSoloMirar(false)
        antesDelMarco = herramienta
        elegir("marco")
    }

    public func elegir(_ nombre: String) {
        alElegir?(nombre)
        do {
            try editor.herramienta(nombre: nombre)
            herramienta = editor.herramientaActual()
            estilo = editor.estilo()
            hayElegidos = editor.cuantosElegidos() > 0
            vista?.trasCambio()
        } catch {
            self.error = "\(error)"
        }
    }

    /// Un mando de la barra de estilo: queda para lo proximo y, si hay algo
    /// elegido, se le aplica (un paso de deshacer).
    public func cambiarEstilo(_ cambio: CambioDeEstilo) {
        alCambiarEstilo?(cambio)
        _ = editor.cambiarEstilo(cambio: cambio)
        estilo = editor.estilo()
        vista?.trasCambio()
    }

    /// Tras algo que pudo cambiar lo elegido o la herramienta desde dentro
    /// (soltar, pegar): la barra vuelve a mirar al editor.
    func refrescarBarra() {
        estilo = editor.estilo()
        let elegidos = editor.cuantosElegidos() > 0
        if elegidos != hayElegidos { hayElegidos = elegidos }
        let h = editor.herramientaActual()
        if h != herramienta { herramienta = h }
    }

    /// Apunta la foto de una imagen recien pegada.
    func anadirFoto(_ id: UInt64, _ url: URL) {
        fotos[id] = url
    }

    /// Las fotos ya leidas de este lienzo, suyas: la cache compartida la
    /// vacia el sistema cuando quiere y la foto se quedaba en un recuadro
    /// gris para siempre.
    private var fotosLeidas: [UInt64: CGImage] = [:]
    private var leyendo: Set<UInt64> = []
    private var fotosReleidas = false

    /// El bitmap de una foto del lienzo; si aun no esta, se lee y se repinta.
    func foto(_ id: UInt64) -> CGImage? {
        if let img = fotosLeidas[id] { return img }
        if fotos[id] == nil, !fotosReleidas {
            // Una imagen que no se apunto al abrir (pegada en otro aparato,
            // llegada al sincronizar): se vuelven a pedir sus rutas.
            fotosReleidas = true
            for f in editor.imagenes() where fotos[f.idObjeto] == nil { fotos[f.idObjeto] = URL(fileURLWithPath: f.ruta) }
        }
        guard let url = fotos[id] else { return nil }
        if let img = Miniaturas.compartidas.enCache(url, lado: 2048) {
            fotosLeidas[id] = img
            return img
        }
        if !leyendo.contains(id) {
            leyendo.insert(id)
            Task { [weak self] in
                let img = await Miniaturas.compartidas.cargar(url, lado: 2048)
                guard let self else { return }
                self.leyendo.remove(id)
                if let img {
                    self.fotosLeidas[id] = img
                    self.vista?.repintarFotos()
                }
            }
        }
        return nil
    }

    /// Las imagenes del pintor: las fotos y lo de dentro de los mosaicos y
    /// las lupas, a `escala` pixeles por unidad.
    func imagenes(escala: CGFloat) -> (UInt64) -> CGImage? {
        let version = editor.version()
        return { [weak self] id in
            guard let self else { return nil }
            // Primero las fotos: el id de una foto sale de su `fileId` y
            // puede tener los bits altos puestos, como un mosaico o una lupa;
            // tomarla por uno de ellos la dejaba en un recuadro gris.
            if self.fotos[id] != nil { return self.foto(id) }
            if PintorDeTapados.esTapado(id) {
                return self.tapados.imagen(id, version: version, escala: escala)
            }
            return self.foto(id)
        }
    }

    public func deshacer() {
        if let alDeshacer { return alDeshacer() }
        _ = editor.deshacer()
        vista?.trasCambio()
    }

    public func rehacer() {
        if let alRehacer { return alRehacer() }
        _ = editor.rehacer()
        vista?.trasCambio()
    }

    public func borrarSeleccion() {
        if editor.borrarSeleccion() { vista?.trasCambio() }
    }

    /// Lo llama la vista tras cada cosa que puede cambiar el documento: si
    /// cambio, se programa el guardado (1 s despues del ULTIMO cambio).
    func revisarCambios() {
        let cambios = editor.cambios()
        guard cambios != cambiosVistos else { return }
        cambiosVistos = cambios
        let puede = editor.puedeDeshacer()
        if puede != puedeDeshacer { puedeDeshacer = puede }
        programarGuardado(dentroDe: 1.0)
    }

    private func programarGuardado(dentroDe segundos: Double) {
        guardadoPendiente?.cancel()
        let tarea = DispatchWorkItem { [editor, referencia] in
            ModeloEditorLienzo.guardarYa(editor, referencia: referencia)
        }
        guardadoPendiente = tarea
        colaGuardar.asyncAfter(deadline: .now() + segundos, execute: tarea)
    }

    /// Guarda ahora (al cerrar la ventana): termina el texto que se estaba
    /// escribiendo y escribe en la cola de fondo. El editor vive lo que dure
    /// la tarea aunque la ventana ya no este.
    public func guardarAlCerrar() {
        guardadoPendiente?.cancel()
        guardadoPendiente = nil
        _ = editor.terminarTexto()
        let editor = self.editor
        let referencia = self.referencia
        colaGuardar.async { ModeloEditorLienzo.guardarYa(editor, referencia: referencia) }
    }

    /// En la cola de fondo: escribe y, si escribio, avisa en el principal.
    private nonisolated static func guardarYa(_ editor: EditorLienzo, referencia: String?) {
        let escrito: Bool
        do {
            escrito = try editor.guardar()
        } catch {
            let texto = "\(error)"
            DispatchQueue.main.async {
                NSLog("PixPin: no se pudo guardar el lienzo: %@", texto)
            }
            return
        }
        guard escrito else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pixpinLienzoGuardado, object: referencia)
            // La sincronizacion sola cuenta sus 30 s de calma desde aqui.
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        }
    }
}

/// La vista que edita. Camara: `origen` es el punto del mundo en la esquina
/// de arriba a la izquierda y `zoom` los puntos de pantalla por unidad.
public final class VistaEditorLienzoNS: NSView, NSTextInputClient {
    let modelo: ModeloEditorLienzo
    private var editor: EditorLienzo { modelo.editor }

    public private(set) var origen = CGPoint.zero
    public private(set) var zoom: CGFloat = 1
    /// **La camara quieta** (el anotador de la captura): el mundo (0, 0)
    /// en la esquina, al 100 %, sin desplazar ni acercar. Lo dibujado cae
    /// justo encima de lo que tiene debajo.
    public var camaraFija = false {
        didSet { if camaraFija { encajar() } }
    }
    /// Con la camara quieta, el punto del mundo en la esquina (el anotador
    /// de pantalla: cada pantalla mira su trozo del escritorio).
    public var origenFijo = CGPoint.zero {
        didSet { if camaraFija { encajar() } }
    }
    /// **Papel transparente** (el anotador de pantalla vivo): no se pinta
    /// el papel y se ve lo que hay debajo de la ventana.
    public var papelTransparente = false {
        didSet { needsDisplay = true }
    }
    /// Quien hospeda el lienzo ve antes cada tecla (salvo mientras se
    /// escribe un texto) y se queda las que use (`true`).
    public var teclaPrevia: ((NSEvent) -> Bool)?
    static let zoomMinimo: CGFloat = 0.05
    static let zoomMaximo: CGFloat = 30
    /// **La camara la lleva otra vista** (el visor de planos: su capa de
    /// tinta encima del plano). La rueda, pellizcar y el boton del medio van
    /// a esa vista, que mueve las dos y pone esta con `ponerCamara`.
    public weak var camaraDeFuera: NSView?

    /// Pone la camara (quien la lleva de fuera): `origen` en la esquina de
    /// arriba a la izquierda y `zoom` puntos por unidad del mundo.
    public func ponerCamara(origen: CGPoint, zoom: CGFloat) {
        guard origen != self.origen || zoom != self.zoom, zoom.isFinite, zoom > 0 else { return }
        self.origen = origen
        self.zoom = zoom
        needsDisplay = true
    }

    /// Lo ultimo pedido a Rust y con que se pidio: si nada cambio, se pinta
    /// esto sin cruzar el puente.
    private var leido: LienzoLeido?
    private var clave: (version: UInt64, x: CGFloat, y: CGFloat, zoom: CGFloat, w: CGFloat, h: CGFloat)?
    private var versionVista: UInt64 = 0
    private var encajada = false
    /// La presion del Force Touch del ultimo `pressureChange` (0...1).
    private var presionTrackpad: Float?
    /// Lo que el metodo de entrada esta componiendo (una tilde muerta): no
    /// se escribe hasta que llega el `insertText`.
    private var marcado = ""
    /// El gesto de pararse: una sola espera de una vez (ver
    /// `RelojFormaRapida.swift`).
    let reloj = RelojFormaRapida(temblorPx: CGFloat(formaRapidaTemblorPx()))
    /// La raya de calibrar mientras se arrastra (no es un elemento: el
    /// motor no la pinta), en el mundo.
    private var rayaDeCalibrar: (desde: CGPoint, hasta: CGPoint)?
    /// Se esta soltando una imagen encima.
    private var soltandoImagen = false

    public init(modelo: ModeloEditorLienzo) {
        self.modelo = modelo
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        modelo.vista = self
        wantsLayer = true
        // Desde macOS 14 una NSView NO recorta por defecto, y `draw` llena
        // el `dirtyRect`, que puede pasar de sus bordes: el fondo del lienzo
        // tapaba la barra de herramientas entera (el usuario no veia
        // ninguna herramienta).
        clipsToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // Que el contenido cambie de golpe (sin fundido): encima de un plano
        // que se mueve, el fundido se veia como tinta que va detras.
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        registerForDraggedTypes(ImagenPegadaLienzo.tiposDelTablero)
        reloj.alPararse = { [weak self] in
            // Vence en la cola principal (`RelojFormaRapida.conDispatch`).
            MainActor.assumeIsolated { self?.alPararse() }
        }
        // Las fotos del lienzo: se cargan reducidas y se repinta una vez.
        let fotos = modelo.fotos
        if !fotos.isEmpty {
            Task { [weak self] in
                var alguna = false
                for url in Set(fotos.values) {
                    if await Miniaturas.compartidas.cargar(url, lado: 2048) != nil { alguna = true }
                }
                if alguna { self?.clave = nil; self?.needsDisplay = true }
            }
        }
    }

    /// Llego una foto que faltaba: se pinta otra vez.
    func repintarFotos() {
        clave = nil
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override public var isFlipped: Bool { true }
    override public var acceptsFirstResponder: Bool { true }
    override public var isOpaque: Bool { !papelTransparente }

    /// Los colores ya adaptados al papel oscuro.
    private var coloresOscuros: [ColorLienzo: ColorLienzo] = [:]
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Con la camara quieta la hospeda otra vista, que decide el foco.
        if !camaraFija { window?.makeFirstResponder(self) }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !encajada, newSize.width > 10, newSize.height > 10 {
            encajada = true
            encajar()
        }
    }

    /// El centro de lo que se ve, en el mundo (`centro_de_la_vista`): ahi
    /// entran las figuras.
    var centroMundo: CGPoint {
        CGPoint(x: origen.x + bounds.width / zoom / 2, y: origen.y + bounds.height / zoom / 2)
    }

    /// Lo dibujado entero en la vista (o el origen al 100 % si esta vacio).
    public func encajar() {
        if camaraFija {
            origen = origenFijo
            zoom = 1
            needsDisplay = true
            return
        }
        // Con fondo, se mira el fondo entero (`encuadre_inicial`).
        let conFondo = modelo.fondo.map { f in
            let c = f.caja.union(editor.caja().map {
                CGRect(x: CGFloat($0.x0), y: CGFloat($0.y0), width: CGFloat($0.x1 - $0.x0), height: CGFloat($0.y1 - $0.y0))
            } ?? f.caja)
            return CajaLienzo(x0: Float(c.minX), y0: Float(c.minY), x1: Float(c.maxX), y1: Float(c.maxY))
        }
        guard let caja = conFondo ?? editor.caja() else {
            origen = .zero
            zoom = 1
            needsDisplay = true
            return
        }
        let margen: CGFloat = 40
        let ancho = CGFloat(caja.x1 - caja.x0), alto = CGFloat(caja.y1 - caja.y0)
        let z = min((bounds.width - margen * 2) / max(ancho, 1),
                    (bounds.height - margen * 2) / max(alto, 1), 1)
        zoom = max(VistaEditorLienzoNS.zoomMinimo, z)
        origen = CGPoint(x: CGFloat(caja.x0) - (bounds.width / zoom - ancho) / 2,
                         y: CGFloat(caja.y0) - (bounds.height / zoom - alto) / 2)
        needsDisplay = true
    }

    // MARK: Pintar

    override public func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let version = editor.version()
        let w = bounds.width, h = bounds.height
        if let c = clave, c.version == version, c.x == origen.x, c.y == origen.y,
           c.zoom == zoom, c.w == w, c.h == h {
            // Nada cambio: lo de antes.
        } else {
            let plano = editor.planoDeVista(x: Float(origen.x), y: Float(origen.y), zoom: Float(zoom),
                                            anchoPx: Float(w), altoPx: Float(h))
            leido = try? leerLienzo(plano)
            clave = (version, origen.x, origen.y, zoom, w, h)
        }
        versionVista = version
        let fondo = leido?.fondo.cg ?? CGColor(gray: 1, alpha: 1)
        if papelTransparente {
            ctx.clear(dirtyRect)
        } else {
            ctx.setFillColor(fondo)
            ctx.fill(dirtyRect)
        }
        guard var leido else { return }
        // Papel oscuro: la tinta adaptada para que se lea (el negro de la
        // letra pasa a claro), como `contraste::adaptar` de Windows.
        let p = leido.fondo
        if 0.299 * p.r + 0.587 * p.g + 0.114 * p.b < 0.5 {
            leido = leido.sobrePapel(p, cache: &coloresOscuros)
        }
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -origen.x, y: -origen.y)
        let visible = CGRect(x: origen.x, y: origen.y, width: w / zoom, height: h / zoom)
        if let fondo = modelo.fondo, fondo.caja.intersects(visible) { fondo.pintar(en: ctx) }
        let escala = zoom * (window?.backingScaleFactor ?? 2)
        PintorLienzo(lienzo: leido, imagen: modelo.imagenes(escala: escala)).pintar(en: ctx, limites: visible)
        if let raya = rayaDeCalibrar {
            // La raya de calibrar: a trazos, del grosor de un punto de pantalla.
            ctx.setStrokeColor(CGColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 0.95))
            ctx.setLineWidth(1.5 / zoom)
            ctx.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
            ctx.move(to: raya.desde)
            ctx.addLine(to: raya.hasta)
            ctx.strokePath()
        }
        ctx.restoreGState()
        if soltandoImagen {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(bounds.insetBy(dx: 1.5, dy: 1.5))
        }
    }

    /// **La estela del laser se apaga sola**: mientras el motor diga que se
    /// anima, se repinta a cada fotograma aunque la version no cambie.
    private var reloj60: Timer?

    private func seguirAnimando() {
        guard reloj60 == nil, editor.animando() else { return }
        reloj60 = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return t.invalidate() }
                self.clave = nil
                self.needsDisplay = true
                if !self.editor.animando() {
                    t.invalidate()
                    self.reloj60 = nil
                }
            }
        }
    }

    /// Tras algo que pudo cambiar el dibujo: repinta si cambio la version y
    /// avisa al modelo (guardar, la barra).
    func trasCambio(version: UInt64? = nil) {
        let v = version ?? editor.version()
        if v != versionVista {
            needsDisplay = true
            // Lo elegido pudo cambiar: la barra de estilo lo ensena.
            modelo.refrescarBarra()
        }
        window?.invalidateCursorRects(for: self)
        modelo.revisarCambios()
    }

    /// La espera del gesto de pararse vencio con el boton aun pulsado.
    private func alPararse() {
        if editor.formaRapida() { needsDisplay = true }
    }

    /// Tras soltar con una herramienta de medir: el cajetin que pida; con
    /// la zona, su foto.
    private func atenderPeticion() {
        guard ["escalar", "cota", "zona"].contains(modelo.herramienta),
              let peticion = editor.tomarPeticion() else { return }
        let editor = self.editor
        switch peticion {
        case let .zona(x0, y0, x1, y1):
            sacarZona(CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0)))
        case let .calibrar(largoPx):
            CajetinMedida.calibrar(unidades: editor.unidadesDeMedida(), en: window) { [weak self] valor, unidad in
                if editor.calibrar(largoPx: largoPx, valor: valor, unidad: unidad) { self?.trasCambio() }
            }
        case let .dictarCota(id, largo, grados, unidad):
            CajetinMedida.dictarCota(largo: largo, grados: grados, unidad: unidad, en: window) { [weak self] l, g in
                if editor.dictarCota(id: id, largo: l, grados: g) { self?.trasCambio() }
            }
        }
    }

    // MARK: Raton y lapiz

    private func alMundo(_ evento: NSEvent) -> CGPoint {
        let p = convert(evento.locationInWindow, from: nil)
        return CGPoint(x: origen.x + p.x / zoom, y: origen.y + p.y / zoom)
    }

    private func modificadores(_ evento: NSEvent) -> UInt32 {
        var m: UInt32 = 0
        if evento.modifierFlags.contains(.shift) { m |= 1 }
        if evento.modifierFlags.contains(.option) { m |= 2 }
        return m
    }

    /// La presion: la de la tableta si es una muestra de lapiz, la del Force
    /// Touch si el trackpad la esta dando, y si no ninguna (raton).
    private func presion(_ evento: NSEvent) -> Float? {
        if evento.subtype == .tabletPoint { return Float(evento.pressure) }
        return presionTrackpad
    }

    private func mandar(_ fase: FasePuntero, _ evento: NSEvent) {
        let p = alMundo(evento)
        let v = editor.puntero(fase: fase, x: Float(p.x), y: Float(p.y), presion: presion(evento),
                               modificadores: modificadores(evento), zoom: Float(zoom))
        if fase == .mover {
            if v != versionVista { needsDisplay = true }
        } else {
            trasCambio(version: v)
        }
        seguirAnimando()
    }

    /// **La foto de una zona** (F8): lo que hay dentro de `caja` (el papel y
    /// lo dibujado), a la escala de la foto de Windows (`zona::escala_de_la_foto`:
    /// el lado mayor a 1600 px, entre 1 y 4 por unidad), recortada en redondo
    /// y con su filo; entra encima, corrida y elegida.
    private func sacarZona(_ caja: CGRect) {
        let k = min(4, max(1, 1600 / max(caja.width, caja.height, 1)))
        let plano = editor.planoDeVista(x: Float(caja.minX), y: Float(caja.minY), zoom: Float(k),
                                        anchoPx: Float(caja.width * k), altoPx: Float(caja.height * k))
        guard let img = PintorDeHojas.imagen(plano, caja: caja, escala: k, transparente: false,
                                             tapados: modelo.tapados, version: editor.version(),
                                             fotos: { [weak self] in self?.modelo.foto($0) }),
              let redonda = PintorDeHojas.enRedondo(img, papelDeNoche: modelo.papelOscuro),
              let png = PintorDeHojas.png(redonda),
              let foto = try? editor.ponerCopiaDeZona(png: png, x0: Float(caja.minX), y0: Float(caja.minY),
                                                      x1: Float(caja.maxX), y1: Float(caja.maxY), zoom: Float(zoom))
        else {
            NSSound.beep()
            return
        }
        let url = URL(fileURLWithPath: foto.ruta)
        modelo.anadirFoto(foto.idObjeto, url)
        trasCambio()
        Task { [weak self] in
            if await Miniaturas.compartidas.cargar(url, lado: 2048) != nil {
                self?.clave = nil
                self?.needsDisplay = true
            }
        }
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Mirando, arrastrar mueve el dibujo (la mano del «view mode» de
        // Excalidraw): nada va al editor.
        if modelo.soloMirar { return }
        presionTrackpad = nil
        // Un clic en el lienzo cierra el desplegable de la barra.
        if modelo.desplegado != nil { modelo.desplegado = nil }
        mandar(.pulsar, event)
        let enVista = convert(event.locationInWindow, from: nil)
        // El gesto de pararse, solo trazando a mano (una pregunta por trazo).
        if HerramientaLienzo.aMano.contains(modelo.herramienta) {
            reloj.pulsar(en: enVista, esperaMs: editor.esperaFormaMs())
        } else {
            reloj.soltar()
        }
        if modelo.herramienta == "escalar" {
            let p = alMundo(event)
            rayaDeCalibrar = (p, p)
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        if modelo.soloMirar { return desplazar(dx: event.deltaX, dy: event.deltaY) }
        mandar(.mover, event)
        reloj.mover(a: convert(event.locationInWindow, from: nil))
        if let raya = rayaDeCalibrar {
            rayaDeCalibrar = (raya.desde, alMundo(event))
            needsDisplay = true
        }
    }

    override public func mouseUp(with event: NSEvent) {
        if modelo.soloMirar { return }
        reloj.soltar()
        mandar(.soltar, event)
        presionTrackpad = nil
        if rayaDeCalibrar != nil {
            rayaDeCalibrar = nil
            needsDisplay = true
        }
        atenderPeticion()
    }

    override public func pressureChange(with event: NSEvent) {
        // Solo mientras se aprieta de verdad (fase 1 en adelante).
        presionTrackpad = event.stage >= 1 ? Float(max(0, min(1, event.pressure))) : nil
    }

    override public func tabletPoint(with event: NSEvent) {
        // Las muestras de la tableta sin boton pulsado no dibujan.
    }

    // Arrastrar con el boton del medio: mover la vista.
    override public func otherMouseDragged(with event: NSEvent) {
        if let fuera = camaraDeFuera { return fuera.otherMouseDragged(with: event) }
        desplazar(dx: event.deltaX, dy: event.deltaY)
    }

    // MARK: Mover y acercar la vista

    private func desplazar(dx: CGFloat, dy: CGFloat) {
        guard !camaraFija else { return }
        origen.x -= dx / zoom
        origen.y -= dy / zoom
        needsDisplay = true
    }

    /// Acerca `factor` veces dejando quieto el punto de la vista `foco`.
    private func acercar(_ factor: CGFloat, en foco: CGPoint) {
        guard !camaraFija else { return }
        let nuevo = max(VistaEditorLienzoNS.zoomMinimo, min(VistaEditorLienzoNS.zoomMaximo, zoom * factor))
        guard nuevo != zoom else { return }
        let mundo = CGPoint(x: origen.x + foco.x / zoom, y: origen.y + foco.y / zoom)
        zoom = nuevo
        origen = CGPoint(x: mundo.x - foco.x / zoom, y: mundo.y - foco.y / zoom)
        needsDisplay = true
    }

    override public func scrollWheel(with event: NSEvent) {
        if let fuera = camaraDeFuera { return fuera.scrollWheel(with: event) }
        let foco = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            // Cmd o Ctrl + rueda: acercar, como en Windows.
            let paso = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
            acercar(CGFloat(exp(Double(paso))), en: foco)
        } else if event.hasPreciseScrollingDeltas {
            // Dos dedos en el trackpad: mover la vista.
            desplazar(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        } else {
            // La rueda del raton: lineas, no puntos.
            desplazar(dx: event.scrollingDeltaX * 12, dy: event.scrollingDeltaY * 12)
        }
    }

    override public func magnify(with event: NSEvent) {
        if let fuera = camaraDeFuera { return fuera.magnify(with: event) }
        acercar(1 + event.magnification, en: convert(event.locationInWindow, from: nil))
    }

    override public func smartMagnify(with event: NSEvent) {
        if let fuera = camaraDeFuera { return fuera.smartMagnify(with: event) }
        // Doble toque con dos dedos: encajar el dibujo o volver al 100 %.
        if abs(zoom - 1) < 0.01 {
            encajar()
        } else {
            acercar(1 / zoom, en: convert(event.locationInWindow, from: nil))
        }
    }

    // MARK: Teclado

    override public func keyDown(with event: NSEvent) {
        let teclas = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if editor.escribiendo() {
            // El texto: el metodo de entrada compone (tildes, emoji) y llega
            // por `insertText`/`doCommand`.
            interpretKeyEvents([event])
            return
        }
        if let teclaPrevia, teclaPrevia(event) { return }
        // ⌥R (el Alt+R de Windows): de mirar a editar y vuelta. La R por su
        // tecla (15): con ⌥ el caracter ya no es una erre.
        if modelo.conRiel, teclas == .option, event.keyCode == 15 {
            modelo.alternarMirar()
            return
        }
        if modelo.soloMirar { return teclaMirando(event, teclas) }
        switch event.keyCode {
        case 51, 117: // borrar, suprimir
            modelo.borrarSeleccion()
            return
        case 53: // Esc: suelta lo elegido / lo que iba a medias; si no hay nada, sale
            if modelo.desplegado == nil, editor.cuantosElegidos() == 0, rayaDeCalibrar == nil {
                // Editando el lienzo, Esc vuelve antes a mirar
                // (`escape_vuelve_a_mirar`); mirando, sale.
                if modelo.conRiel { modelo.ponerSoloMirar(true) } else { VentanaLisa.escapar(window) }
                return
            }
            modelo.desplegado = nil
            reloj.soltar()
            rayaDeCalibrar = nil
            let v = editor.puntero(fase: .cancelar, x: 0, y: 0, presion: nil, modificadores: 0,
                                   zoom: Float(zoom))
            trasCambio(version: v)
            return
        default:
            break
        }
        if teclas.isEmpty, let letra = event.charactersIgnoringModifiers?.lowercased().first,
           let h = HerramientaLienzo.deTecla(letra) {
            modelo.elegir(h.id)
            return
        }
        // 1, 2 y 3: los tres grosores, como en Windows (`tecla_a_pluma`).
        if teclas.isEmpty, let c = event.charactersIgnoringModifiers, let g = OpcionesEstiloLienzo.grosor(tecla: c) {
            modelo.cambiarEstilo(.grosor(grosor: g))
            return
        }
        // Sacar el dibujo, como en Windows (Ctrl+P, Ctrl+Mayus+S, E y C).
        let letra = event.charactersIgnoringModifiers?.lowercased()
        if teclas == .command, letra == "p" {
            modelo.imprimir()
            return
        }
        // F11 de Windows: ⌃⌘F, la pantalla completa del Mac (si el menu
        // Visualizacion no se la llevo antes). Se recuerda para el siguiente.
        if teclas == [.control, .command], letra == "f" {
            window?.toggleFullScreen(nil)
            return
        }
        if teclas == [.command, .shift] {
            switch letra {
            case "s": modelo.compartir(); return
            case "e": modelo.exportar(); return
            case "c": modelo.copiarComoPNG(); return
            default: break
            }
        }
        if teclas == .command, event.charactersIgnoringModifiers == "a" {
            editor.seleccionarTodo()
            trasCambio()
            return
        }
        if teclas == .command, event.charactersIgnoringModifiers == "v" {
            // Si el menu Edicion no se lo llevo antes.
            paste(nil)
            return
        }
        super.keyDown(with: event)
    }

    /// **Las teclas mirando**: Esc sale; quedan la pantalla completa y
    /// sacar el dibujo (imprimir, compartir, exportar, copiar). Las letras de
    /// las herramientas, borrar, ⌘A y ⌘V no: mirando nada se edita.
    private func teclaMirando(_ event: NSEvent, _ teclas: NSEvent.ModifierFlags) {
        let letra = event.charactersIgnoringModifiers?.lowercased()
        if event.keyCode == 53 {
            VentanaLisa.escapar(window)
        } else if teclas == [.control, .command], letra == "f" {
            window?.toggleFullScreen(nil)
        } else if teclas == .command, letra == "p" {
            modelo.imprimir()
        } else if teclas == [.command, .shift], letra == "s" {
            modelo.compartir()
        } else if teclas == [.command, .shift], letra == "e" {
            modelo.exportar()
        } else if teclas == [.command, .shift], letra == "c" {
            modelo.copiarComoPNG()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Pegar y soltar imagenes

    /// ⌘V (Edicion ▸ Pegar): una imagen del portapapeles, en el centro de lo
    /// que se ve.
    @objc public func paste(_ sender: Any?) {
        guard !modelo.soloMirar, !editor.escribiendo(), let fuente = ImagenPegadaLienzo.origen(en: .general) else {
            NSSound.beep()
            return
        }
        let centro = CGPoint(x: origen.x + bounds.width / zoom / 2, y: origen.y + bounds.height / zoom / 2)
        pegar(fuente, en: centro)
    }

    /// El boton de imagen de la barra: un fichero, en el centro de lo que se
    /// ve.
    func meterImagen(desde url: URL) {
        let centro = CGPoint(x: origen.x + bounds.width / zoom / 2, y: origen.y + bounds.height / zoom / 2)
        pegar(.fichero(url), en: centro)
    }

    /// Convierte a PNG fuera del hilo principal y lo pega centrado en
    /// `centro` (mundo); despues lee su miniatura y repinta.
    private func pegar(_ fuente: ImagenPegadaLienzo.Origen, en centro: CGPoint) {
        let editor = self.editor
        let ancho = Float(bounds.width / zoom), alto = Float(bounds.height / zoom)
        Task { [weak self] in
            let hecho = await Task.detached(priority: .userInitiated) { () -> ImagenDelLienzo? in
                guard let png = ImagenPegadaLienzo.png(de: fuente) else { return nil }
                return try? editor.pegarImagen(png: png, centroX: Float(centro.x), centroY: Float(centro.y),
                                               anchoVista: ancho, altoVista: alto)
            }.value
            guard let self else { return }
            guard let foto = hecho else {
                NSSound.beep()
                return
            }
            let url = URL(fileURLWithPath: foto.ruta)
            self.modelo.anadirFoto(foto.idObjeto, url)
            self.trasCambio()
            if await Miniaturas.compartidas.cargar(url, lado: 2048) != nil {
                self.clave = nil
                self.needsDisplay = true
            }
        }
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !modelo.soloMirar, ImagenPegadaLienzo.origen(en: sender.draggingPasteboard) != nil else { return [] }
        soltandoImagen = true
        needsDisplay = true
        return .copy
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        soltandoImagen = false
        needsDisplay = true
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        soltandoImagen = false
        needsDisplay = true
        guard let fuente = ImagenPegadaLienzo.origen(en: sender.draggingPasteboard) else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        pegar(fuente, en: CGPoint(x: origen.x + p.x / zoom, y: origen.y + p.y / zoom))
        return true
    }

    // NSTextInputClient: solo lo que hace falta para escribir un texto del
    // lienzo con cualquier teclado. No hay texto que seleccionar aqui.

    public func insertText(_ string: Any, replacementRange: NSRange) {
        marcado = ""
        let texto: String
        if let a = string as? NSAttributedString { texto = a.string } else { texto = (string as? String) ?? "" }
        guard !texto.isEmpty else { return }
        if editor.teclear(texto: texto) { trasCambio() }
    }

    override public func doCommand(by selector: Selector) {
        let nombre: String?
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)): nombre = "retroceso"
        case #selector(NSResponder.deleteForward(_:)): nombre = "suprimir"
        case #selector(NSResponder.moveLeft(_:)): nombre = "izquierda"
        case #selector(NSResponder.moveRight(_:)): nombre = "derecha"
        case #selector(NSResponder.moveToBeginningOfLine(_:)): nombre = "inicio"
        case #selector(NSResponder.moveToEndOfLine(_:)): nombre = "fin"
        case #selector(NSResponder.insertNewline(_:)): nombre = "entrar"
        case #selector(NSResponder.cancelOperation(_:)): nombre = "escape"
        default: nombre = nil
        }
        if let nombre, editor.tecla(nombre: nombre) { trasCambio() }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let a = string as? NSAttributedString { marcado = a.string } else { marcado = (string as? String) ?? "" }
    }

    public func unmarkText() { marcado = "" }

    public func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    public func markedRange() -> NSRange {
        marcado.isEmpty ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (marcado as NSString).length)
    }

    public func hasMarkedText() -> Bool { !marcado.isEmpty }

    public func attributedSubstring(forProposedRange range: NSRange,
                                    actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // La ventanita del metodo de entrada (japones, chino, el acento
        // mantenido) va JUNTO AL CURSOR del texto, como en cualquier editor:
        // su raya en el mundo, pasada a la vista y a la pantalla.
        let enVista = rectanguloDelCursor() ?? NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 20)
        let enVentana = convert(enVista, to: nil)
        return window?.convertToScreen(enVentana) ?? .zero
    }

    /// El cursor del texto en coordenadas de la vista. `nil` si no se escribe.
    func rectanguloDelCursor() -> NSRect? {
        guard let c = editor.cajaDelCursor() else { return nil }
        return VistaEditorLienzoNS.aVista(c, origen: origen, zoom: zoom)
    }

    /// Una caja del mundo en la vista (volteada, Y hacia abajo), con un
    /// punto de ancho como minimo.
    static func aVista(_ c: CajaLienzo, origen: CGPoint, zoom: CGFloat) -> NSRect {
        let x = (CGFloat(c.x0) - origen.x) * zoom
        let y = (CGFloat(c.y0) - origen.y) * zoom
        return NSRect(x: x, y: y, width: max(1, CGFloat(c.x1 - c.x0) * zoom),
                      height: max(1, CGFloat(c.y1 - c.y0) * zoom))
    }

    public func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    // MARK: Cursor

    override public func resetCursorRects() {
        let cursor: NSCursor = modelo.soloMirar ? .openHand : (modelo.herramienta == "seleccion" ? .arrow : .crosshair)
        addCursorRect(bounds, cursor: cursor)
    }
}

/// La vista de AppKit dentro de SwiftUI.
struct LienzoEditable: NSViewRepresentable {
    let modelo: ModeloEditorLienzo

    func makeNSView(context: Context) -> VistaEditorLienzoNS {
        VistaEditorLienzoNS(modelo: modelo)
    }

    func updateNSView(_ vista: VistaEditorLienzoNS, context: Context) {
        vista.window?.invalidateCursorRects(for: vista)
    }
}

/// **El editor del lienzo**, como el de Windows (y Excalidraw): el lienzo
/// llena la ventana y encima flotan la barra de herramientas, centrada
/// arriba, y el panel de estilo a la izquierda. El lienzo de su ventana
/// lleva ademas el riel de la derecha y abre mirando (sin barra ni panel).
public struct EditorLienzoView: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    @ObservedObject private var panel = PanelLienzoQuitado.compartido

    public init(modelo: ModeloEditorLienzo) { self.modelo = modelo }

    public var body: some View {
        GeometryReader { geo in
            // Si no cabe en una fila, la barra se parte en dos (`corte_para`
            // de Windows) y el panel baja con ella.
            let barra = BotonBarraLienzo.barra
            let corte = BotonBarraLienzo.cortePara(ancho: geo.size.width - 2 * MedidasBarraLienzo.distanciaBorde)
            let filas: CGFloat = corte < barra.count ? 2 : 1
            let anchoBarra = corte < barra.count
                ? max(BotonBarraLienzo.anchoDeFila(barra[..<corte]), BotonBarraLienzo.anchoDeFila(barra[corte...]))
                : BotonBarraLienzo.anchoDeFila(barra[...])
            // Lo de debajo de la barra y, si la barra le cae encima al panel
            // (ventana estrecha), el boton de quitarlo baja con el panel
            // (`area_del_panel` de Windows).
            let abajoBarra = MedidasBarraLienzo.distanciaBorde + filas * MedidasBarraLienzo.lado
                + (filas - 1) * MedidasBarraLienzo.relleno + 2 * MedidasBarraLienzo.relleno
            let pisa = (geo.size.width - anchoBarra) / 2
                < MedidasBarraLienzo.distanciaBorde + MedidasBarraLienzo.anchoPanel
            let arribaBoton = pisa ? abajoBarra + 8 : MedidasBarraLienzo.distanciaBorde
            ZStack(alignment: .top) {
                LienzoEditable(modelo: modelo)
                if modelo.soloMirar {
                    PastillaMirando()
                        .padding(.top, MedidasBarraLienzo.distanciaBorde)
                        .allowsHitTesting(false)
                } else {
                    if modelo.desplegado != nil {
                        // Un clic fuera del desplegable lo cierra.
                        Color.black.opacity(0.001)
                            .onTapGesture { modelo.desplegado = nil }
                    }
                    BarraHerramientasLienzo(modelo: modelo, corte: corte)
                        .padding(.top, MedidasBarraLienzo.distanciaBorde)
                        .padding(.horizontal, MedidasBarraLienzo.distanciaBorde)
                    if modelo.hayElegidos || !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) {
                        if modelo.conRiel {
                            // El boton de quitar el panel (y de sacarlo),
                            // arriba a la izquierda, y el panel debajo.
                            VStack(alignment: .leading, spacing: 8) {
                                BotonPlegarPanel(panel: panel, tema: TemaBarraLienzo.de(modelo))
                                if !panel.quitado { PanelEstiloLienzo(modelo: modelo) }
                            }
                            .padding(.leading, MedidasBarraLienzo.distanciaBorde)
                            .padding(.top, arribaBoton)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            PanelEstiloLienzo(modelo: modelo)
                                .padding(.leading, MedidasBarraLienzo.distanciaBorde)
                                .padding(.top, MedidasBarraLienzo.yPanel
                                         + (filas - 1) * (MedidasBarraLienzo.lado + MedidasBarraLienzo.relleno))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                if modelo.conRiel {
                    // El riel, a la vista tambien mirando: su lapiz edita.
                    RielLienzo(modelo: modelo)
                        .padding(.top, max(abajoBarra + 8, BarraFlotante.alto + 2 * BarraFlotante.separacion + 8))
                        .padding(.trailing, MedidasBarraLienzo.distanciaBorde)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                cuerpo
            }
        }
        .overlayPreferenceValue(AnclasGruposLienzo.self) { anclas in
            MenuGrupoLienzo(modelo: modelo, anclas: anclas)
        }
    }

    @ViewBuilder
    private var cuerpo: some View {
        ZStack {
            if let error = modelo.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// **El panel de estilo quitado** (Windows, 24-oct, `panel_dibujo::PLEGADO`):
/// lo dice el boton de arriba a la izquierda y vale para todos los lienzos
/// de la sesion, no solo el de esta ventana. No se recuerda al cerrar.
@MainActor
final class PanelLienzoQuitado: ObservableObject {
    static let compartido = PanelLienzoQuitado()
    @Published var quitado = false
}

/// **El boton de mostrar y quitar el panel** (`panel_lateral::boton_plegar`):
/// una isla de 36 como la del panel, con la flecha para quitarlo y la
/// paleta para sacarlo.
struct BotonPlegarPanel: View {
    @ObservedObject var panel: PanelLienzoQuitado
    let tema: TemaBarraLienzo
    @State private var encima = false

    var body: some View {
        Button {
            panel.quitado.toggle()
        } label: {
            Simbolo(nombre: panel.quitado ? "paintpalette" : "chevron.left", lado: 18)
                .foregroundStyle(tema.icono)
                .frame(width: MedidasBarraLienzo.ladoPlegar, height: MedidasBarraLienzo.ladoPlegar)
                .background(encima ? tema.hover : Color.clear, in: RoundedRectangle(cornerRadius: MedidasBarraLienzo.radio))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(IslaLienzo(tema: tema))
        .onHover { encima = $0 }
        .help(panel.quitado ? "Mostrar las propiedades" : "Quitar las propiedades")
    }
}

/// **El riel del lienzo** (`marcas::pintar_riel` de Windows, sin los
/// marcadores, que el lienzo del Mac aun no tiene): el lapiz, pulsado
/// editando (el mismo de los visores), y el marco, pulsado con la
/// herramienta Marco puesta.
struct RielLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo

    var body: some View {
        VStack(spacing: 2) {
            BotonDelRiel(simbolo: "pencil",
                      ayuda: modelo.soloMirar ? "Editar (⌥R)" : "Volver a mirar (⌥R o Esc)",
                      encendido: !modelo.soloMirar) { modelo.alternarMirar() }
            BotonDelRiel(simbolo: "rectangle.dashed", ayuda: "Marcos para imprimir (C)",
                      encendido: modelo.herramienta == "marco" && !modelo.soloMirar) { modelo.alternarMarco() }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        .fixedSize()
    }
}

/// Un boton del riel: 28 x 28, pulsado en azul (el `BotonRiel` de los
/// visores, aqui para que su inicializador se vea desde este fichero).
private struct BotonDelRiel: View {
    let simbolo: String
    let ayuda: String
    var encendido = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Simbolo(nombre: simbolo, lado: 15)
                .foregroundStyle(encendido ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(encendido ? Color(red: 0, green: 0.376, blue: 0.875)
                          : encima ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
        .onHover { encima = $0 }
    }
}

/// **La pastilla de solo mirar** (`presentar::pintar_solo_mirar`): negra
/// translucida, arriba en el centro.
struct PastillaMirando: View {
    var body: some View {
        Text("Solo mirar · el lápiz de la derecha edita")
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.62)))
    }
}

/// Abre los lienzos en ventanas propias, una por dibujo: abrir otra vez el
/// mismo la trae al frente.
@MainActor
public final class VentanasDeLienzo: NSObject, NSWindowDelegate {
    public static let compartidas = VentanasDeLienzo()

    private struct Abierta {
        let ventana: NSWindow
        let modelo: ModeloEditorLienzo
        let barra: BarraFlotante
    }

    private var abiertas: [String: Abierta] = [:]

    /// Abre el dibujo `referencia` del chat. El fichero se lee fuera del
    /// hilo principal. Con `fondo`, sobre una imagen o una pagina de PDF
    /// fija (`abrir_sobre` de Windows: la hoja-pagina de un proyecto, la
    /// imagen de un pin).
    public func abrir(referencia: String, en chat: String, titulo: String, almacen: Almacen,
                      fondo: FuenteFondoLienzo? = nil) {
        let clave = chat + "\u{0}" + referencia
        if let abierta = abiertas[clave] {
            abierta.ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let nucleo = almacen.nucleo
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<(EditorLienzo, [UInt64: URL]), Error> in
                do {
                    let editor = try nucleo.editarLienzo(chat: chat, dibujo: referencia)
                    var fotos: [UInt64: URL] = [:]
                    for f in editor.imagenes() { fotos[f.idObjeto] = URL(fileURLWithPath: f.ruta) }
                    return .success((editor, fotos))
                } catch {
                    return .failure(error)
                }
            }.value
            switch hecho {
            case let .success((editor, fotos)):
                self.mostrar(ModeloEditorLienzo(editor: editor, referencia: referencia, fotos: fotos,
                                                nucleo: nucleo, titulo: titulo,
                                                fondo: fondo.flatMap { FondoLienzo($0) }),
                             clave: clave, titulo: titulo)
            case .failure:
                NSSound.beep()
            }
        }
    }

    private func mostrar(_ modelo: ModeloEditorLienzo, clave: String, titulo: String) {
        if let abierta = abiertas[clave] {
            abierta.ventana.makeKeyAndOrderFront(nil)
            return
        }
        let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        ventana.title = titulo
        // Lisa como en Windows, donde el lienzo en ventana lleva la barra de
        // los pines: una franja fina con −, ☐ y ✕ planos (por ella se arrastra)
        // y el lienzo debajo, sin semaforo ni titulo.
        VentanaLisa.vestirEntera(ventana)
        ventana.isReleasedWhenClosed = false
        // Abre mirando, con el riel (Windows, 24-oct, `mirar_editar`).
        modelo.abrirMirando()
        ventana.contentViewController = NSHostingController(rootView: EditorLienzoView(modelo: modelo))
        ventana.setContentSize(NSSize(width: 1000, height: 720))
        ventana.center()
        VentanaLisa.recordar(ventana, clave: "lienzo")
        ventana.delegate = self
        ventana.identifier = NSUserInterfaceItemIdentifier(clave)
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        // La barra del pin, la de todos los visores (`modo_ventana.rs` de
        // Windows: «que use la misma barra que los pines»).
        let barra = BarraFlotante(ventana: ventana) {
            BarraVisor(nombre: titulo, ext: "excalidraw") { EmptyView() }
        }
        barra.empezar()
        abiertas[clave] = Abierta(ventana: ventana, modelo: modelo, barra: barra)
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Como se dejo el ultimo lienzo (F11 de Windows, `modo_ventana`).
        if modelo.nucleo?.lienzoPantallaCompleta() == true { ventana.toggleFullScreen(nil) }
    }

    /// F11 (⌃⌘F en el Mac): se apunta para el siguiente lienzo.
    public func windowDidEnterFullScreen(_ notification: Notification) {
        recordarModo(notification, pantallaCompleta: true)
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        recordarModo(notification, pantallaCompleta: false)
    }

    private func recordarModo(_ notification: Notification, pantallaCompleta: Bool) {
        guard let ventana = notification.object as? NSWindow,
              let clave = ventana.identifier?.rawValue,
              let abierta = abiertas[clave] else { return }
        try? abierta.modelo.nucleo?.recordarLienzoPantallaCompleta(si: pantallaCompleta)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let ventana = notification.object as? NSWindow,
              let clave = ventana.identifier?.rawValue,
              let abierta = abiertas[clave] else { return }
        // El asistente ya no dibuja aqui (E1).
        abierta.modelo.editor.cerrado()
        // El editor lo retiene la tarea de guardar hasta que termine; la
        // vista y el modelo se sueltan con la ventana.
        abierta.modelo.guardarAlCerrar()
        abiertas[clave] = nil
    }

    /// Al frente: lo que dibuje el asistente viene a este lienzo (E1).
    public func windowDidBecomeKey(_ notification: Notification) {
        guard let ventana = notification.object as? NSWindow,
              let clave = ventana.identifier?.rawValue,
              let abierta = abiertas[clave] else { return }
        abierta.modelo.editor.alFrente()
    }

    /// **El asistente toco un lienzo abierto** (desde su hilo, con el
    /// cerrojo de la escena): cada ventana mira su version y, si cambio,
    /// repinta y programa el guardado como tras un gesto.
    public func alCambiarDesdeFuera() {
        for abierta in abiertas.values { abierta.modelo.vista?.trasCambio() }
    }
}
