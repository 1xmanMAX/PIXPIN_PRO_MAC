// **El anotador de pantalla** (E3): el lienzo entero encima de TODAS las
// pantallas, como `ventana_editor/pantalla.rs` de Windows. No es otra
// maquina de dibujar: es el `EditorLienzo` de siempre, con sus herramientas,
// su barra y su panel de estilo, y lo unico que cambia es el sitio:
//
// - **un lienzo para todo el escritorio**: un panel por pantalla, todos con
//   el MISMO editor; cada vista mira su trozo con la camara quieta a 1:1
//   (`origenFijo`, el mundo en puntos del escritorio con el origen arriba a
//   la izquierda). Una flecha que cruza de una pantalla a otra es UNA
//   flecha. (macOS no deja una ventana a caballo de dos pantallas con
//   «Pantallas con Spaces separados», que viene puesto; por eso uno por
//   pantalla y no uno grande como en Windows);
// - **no se navega**: ni rueda ni pellizco mueven la pantalla;
// - **viva**: el papel es transparente y debajo todo sigue moviendose.
//   **Espacio** deja pasar los clics a lo de debajo y los vuelve a coger;
//   **⌘ mantenido** los deja pasar mientras dure (el Ctrl de Windows: con ⌃
//   el clic del Mac seria el derecho). Con el clic a traves la barra se
//   esconde; la pastilla de abajo sigue recibiendo el raton, y **⌥ + doble
//   clic central** (`GestosAlt`) tambien vuelve a dibujar;
// - **congelada**: el fondo es la foto de todas las pantallas hecha ANTES
//   de abrir (un `FondoLienzo` del escritorio entero: el mosaico y la lupa
//   ven lo de debajo);
// - **Esc sale** (si no hay nada elegido; con un texto abierto lo cierra,
//   como en el lienzo). Al salir con algo nuevo dibujado **se guarda solo en
//   «Mensajes guardados»** (`anotador_al_chat`): la foto de lo de debajo con
//   la tinta editable encima, sin preguntar. Escape nunca tira lo dibujado;
// - **la pastilla** (`pastilla_pantalla.rs`): clic a traves, limpiar (se
//   deshace con ⌘Z), copiar la pantalla con lo anotado, guardar ya en
//   «Mensajes guardados» (lo dibujado despues pone al dia EL MISMO lienzo,
//   no otro mensaje) y salir.
//
// La foto de debajo la da ScreenCaptureKit sin las ventanas de PixPin
// (`Instantanea`): en viva no hay que esconder nada ni se nota el parpadeo
// de Windows. Solo se guardan las pantallas donde se dibujo, a su tamano
// (`monitores_con_dibujo`): tres pantallas en fila el movil las reducia
// hasta no leerse.
//
// Rendimiento: nada sondea salvo el reloj del ⌘ mantenido (solo mientras
// se mantiene). La foto de las pantallas, el PNG y escribir el chat van
// fuera del hilo principal, uno detras de otro.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Viva (la pantalla se sigue moviendo debajo) o congelada (sobre una foto).
public enum ModoAnotadorPantalla: Sendable {
    case viva, congelada
}

/// **Lo que toca con lo anotado** al pulsar Guardar o al salir
/// (`anotador_al_chat::que_hacer` de Windows).
enum PasoAnotador: Equatable {
    /// Nada: sin tinta y sin guardar antes, o sin cambios desde lo ultimo.
    case nada
    /// La primera vez con tinta: foto de debajo, mensaje y su lienzo.
    case nuevo
    /// Ya se guardo en esta sesion y se siguio dibujando (o se limpio): el
    /// MISMO lienzo, puesto al dia.
    case alDia

    /// **Pura**: `huellaGuardada` es la de la tinta tal como se mando la
    /// ultima vez (`nil` si entonces no habia), `ahora` la de ahora.
    static func de(yaGuardada: Bool, huellaGuardada: UInt64?, ahora: UInt64?) -> PasoAnotador {
        guard yaGuardada else { return ahora == nil ? .nada : .nuevo }
        return huellaGuardada == ahora ? .nada : .alDia
    }
}

/// Una foto de una pantalla, en el mundo del anotador.
struct FotoEnElMundo {
    /// Donde esta la pantalla, en puntos del escritorio (Y hacia abajo).
    let marco: CGRect
    let imagen: CGImage
}

/// Las cuentas del escritorio, todas puras.
enum GeometriaAnotador {
    /// El escritorio: lo que cubren todas las pantallas (coordenadas de AppKit).
    static func escritorio(_ pantallas: [CGRect]) -> CGRect {
        pantallas.reduce(CGRect.null) { $0.union($1) }
    }

    /// Una pantalla (coordenadas de AppKit, Y hacia arriba) en el mundo del
    /// anotador: puntos del escritorio con el origen ARRIBA a la izquierda.
    static func enElMundo(_ pantalla: CGRect, escritorio e: CGRect) -> CGRect {
        CGRect(x: pantalla.minX - e.minX, y: e.maxY - pantalla.maxY,
               width: pantalla.width, height: pantalla.height)
    }

    /// **El trozo que merece guardarse** (`monitores_con_dibujo`): la union
    /// de las pantallas que tocan algo dibujado. `nil`: entera (nada
    /// dibujado, o tocan todas).
    static func pantallasConDibujo(_ pantallas: [CGRect], cajas: [CGRect]) -> CGRect? {
        let tocan = pantallas.filter { p in cajas.contains { $0.intersects(p) } }
        guard !tocan.isEmpty, tocan.count < pantallas.count else { return nil }
        return tocan.reduce(CGRect.null) { $0.union($1) }
    }

    /// Los pixeles por punto con que se guarda `region`: los de la pantalla
    /// mas fina que toca (una Retina junto a una normal sale a 2x).
    static func escala(de fotos: [FotoEnElMundo], en region: CGRect) -> CGFloat {
        fotos.filter { $0.marco.intersects(region) }
            .map { CGFloat($0.imagen.width) / max($0.marco.width, 1) }
            .max() ?? 1
    }

    /// **La foto de `region`** con cada pantalla en su sitio, a `escala`
    /// pixeles por punto. Lo que ninguna pantalla cubre (un escritorio en L)
    /// sale negro, como en Windows (`unir_fotos`).
    static func componer(_ fotos: [FotoEnElMundo], region: CGRect, escala: CGFloat) -> CGImage? {
        let w = max(1, Int((region.width * escala).rounded()))
        let h = max(1, Int((region.height * escala).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        for f in fotos where f.marco.intersects(region) {
            // El contexto va con la Y hacia arriba: se cuenta desde abajo.
            let destino = CGRect(x: (f.marco.minX - region.minX) * escala,
                                 y: (region.maxY - f.marco.maxY) * escala,
                                 width: f.marco.width * escala, height: f.marco.height * escala)
            ctx.draw(f.imagen, in: destino)
        }
        return ctx.makeImage()
    }
}

/// Lo que ensena la pastilla.
@MainActor
final class EstadoPastillaAnotador: ObservableObject {
    @Published var pasante = false
    /// Lo que se acaba de hacer («Guardado en Mensajes guardados»), un rato.
    @Published var aviso: String?
    /// Si hay almacen (sin el, el boton de guardar sale apagado).
    @Published var puedeGuardar = true
}

/// Los botones de la pastilla (`pastilla_pantalla::Accion`).
enum AccionPastilla: CaseIterable {
    case atravesar, limpiar, copiar, guardar, salir

    var simbolo: String {
        switch self {
        case .atravesar: "hand.raised"
        case .limpiar: "trash"
        case .copiar: "doc.on.doc"
        case .guardar: "bookmark"
        case .salir: "xmark"
        }
    }

    var titulo: String {
        switch self {
        case .atravesar: "Clic a través"
        case .limpiar: "Limpiar"
        case .copiar: "Copiar"
        case .guardar: "Guardar en Mensajes guardados"
        case .salir: "Salir"
        }
    }
}

/// **La pastilla de abajo**: los cinco botones y lo que dice debajo.
struct PastillaAnotador: View {
    @ObservedObject var estado: EstadoPastillaAnotador
    let alPulsar: (AccionPastilla) -> Void

    /// Lo que dice debajo de los botones (`anotador-rotulo-*` de Windows).
    static func rotulo(pasante: Bool) -> String {
        pasante ? "⌥ + doble clic central: volver a dibujar"
            : "Espacio o ⌥ + doble clic central: clic a través"
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                ForEach(AccionPastilla.allCases, id: \.self) { a in
                    if a == .salir {
                        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 22)
                            .padding(.horizontal, 4)
                    }
                    Button { alPulsar(a) } label: {
                        Image(systemName: a == .atravesar && estado.pasante ? "hand.raised.fill" : a.simbolo)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                            .background(fondo(a), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .disabled(a == .guardar && !estado.puedeGuardar)
                    .opacity(a == .guardar && !estado.puedeGuardar ? 0.4 : 1)
                    .help(a.titulo)
                    .accessibilityLabel(a.titulo)
                }
            }
            Text(estado.aviso ?? PastillaAnotador.rotulo(pasante: estado.pasante))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15, opacity: 0.95),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    private func fondo(_ a: AccionPastilla) -> Color {
        a == .atravesar && estado.pasante
            ? Color(.sRGB, red: 0.0, green: 0.40, blue: 0.85, opacity: 0.95)
            : Color.white.opacity(0.06)
    }
}

/// La barra del lienzo y su panel de estilo, arriba de la pantalla
/// principal del anotador.
private struct BarraAnotadorVista: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    @ObservedObject var zonas: ZonasBarraAnotador

    var body: some View {
        let botones = BotonBarraLienzo.barraDeCaptura
        ZStack(alignment: .top) {
            if modelo.desplegado != nil {
                // Un clic fuera del desplegable lo cierra.
                Color.black.opacity(0.001)
                    .onTapGesture { modelo.desplegado = nil }
            }
            VStack(spacing: 8) {
                BarraHerramientasLienzo(modelo: modelo, botones: botones, corte: botones.count)
                    .fixedSize()
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ZonasAnotadorClave.self, value: [g.frame(in: .named("anotador"))])
                    })
                if modelo.hayElegidos || !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) {
                    HStack {
                        PanelEstiloLienzo(modelo: modelo)
                            .fixedSize()
                            .background(GeometryReader { g in
                                Color.clear.preference(key: ZonasAnotadorClave.self,
                                                       value: [g.frame(in: .named("anotador"))])
                            })
                        Spacer()
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "anotador")
        .overlayPreferenceValue(AnclasGruposLienzo.self) { anclas in
            MenuGrupoLienzo(modelo: modelo, anclas: anclas)
        }
        .onPreferenceChange(ZonasAnotadorClave.self) { z in
            MainActor.assumeIsolated { zonas.zonas = z }
        }
    }
}

private struct ZonasAnotadorClave: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

/// Donde caen la barra y el panel (ahi se queda el raton; fuera, el lienzo).
@MainActor
final class ZonasBarraAnotador: ObservableObject {
    var zonas: [CGRect] = []
}

/// La vista que hospeda la barra: solo se queda el raton en sus islas.
private final class HospedajeBarraAnotador: NSHostingView<BarraAnotadorVista> {
    let zonas: ZonasBarraAnotador
    weak var modelo: ModeloEditorLienzo?

    init(modelo: ModeloEditorLienzo, zonas: ZonasBarraAnotador) {
        self.zonas = zonas
        self.modelo = modelo
        super.init(rootView: BarraAnotadorVista(modelo: modelo, zonas: zonas))
    }

    @available(*, unavailable)
    required init(rootView: BarraAnotadorVista) { fatalError("se crea con init(modelo:zonas:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("no se crea desde un nib") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        let p = isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
        let dentro = zonas.zonas.contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
            || modelo?.desplegado != nil
        return dentro ? super.hitTest(point) : nil
    }
}

/// Un panel del anotador: coge el teclado sin activar la app y avisa tras
/// cada evento (para que las demas pantallas repinten lo que cambio).
final class PanelAnotador: NSPanel {
    var trasEvento: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        trasEvento?(event)
    }
}

/// **El anotador de pantalla.** Uno para toda la app.
@MainActor
public final class AnotadorPantalla {
    public static let compartido = AnotadorPantalla()

    /// El almacen del chat, para guardar en «Mensajes guardados» (sin el,
    /// no se guarda: el boton sale apagado).
    public weak var almacen: Almacen?
    /// Copiar (la pila de capturas). Sin el, se copia suelta.
    public var alCopiar: ((CGImage, CGFloat) -> Void)?

    public private(set) var modo: ModoAnotadorPantalla = .viva
    /// Si esta en pantalla.
    public var abierto: Bool { modelo != nil }
    /// El clic a traves fijo (Espacio, la pastilla, ⌥ + doble clic central).
    public private(set) var pasante = false
    /// El de ⌘ mantenido.
    private var pasanteMomentaneo = false

    private(set) var modelo: ModeloEditorLienzo?
    private var paneles: [PanelAnotador] = []
    private var vistas: [VistaEditorLienzoNS] = []
    private var barra: HospedajeBarraAnotador?
    private let zonas = ZonasBarraAnotador()
    private let estado = EstadoPastillaAnotador()
    private var pastilla: PanelAnotador?
    /// El panel de la pantalla con la barra (el que coge el teclado).
    private weak var panelPrincipal: PanelAnotador?
    /// El escritorio (coordenadas de AppKit) y las pantallas en el mundo.
    private var escritorio = CGRect.zero
    private var pantallas: [CGRect] = []
    /// Las fotos de la congelada (las de antes de abrir).
    private var fotos: [FotoEnElMundo] = []
    private var carpeta: URL?
    private var versionVista: UInt64 = 0
    private var vigiaTeclas: Any?
    private var relojComando: Timer?
    private var relojAviso: Task<Void, Never>?
    private var abriendo = false

    /// Lo guardado en esta sesion: donde quedo y con que se llevo la tinta
    /// a la foto (el origen de la foto en el mundo y sus pixeles por punto).
    struct Guardada {
        let pantalla: PantallaAnotada
        let origen: CGPoint
        let escala: CGFloat
    }

    private var yaGuardada = false
    private var huellaGuardada: UInt64?
    /// El ultimo guardado lanzado: cada uno espera al anterior (el que pone
    /// al dia necesita saber donde quedo el primero).
    private var guardado: Task<Guardada?, Never>?

    public init() {}

    // MARK: - Abrir y cerrar

    /// Abre el anotador en `modo`. Si ya esta abierto, no hace nada.
    public func abrir(_ modo: ModoAnotadorPantalla) {
        guard !abierto, !abriendo else { return }
        self.modo = modo
        guard modo == .congelada else { return montar() }
        guard PermisoCaptura.asegurar() else { return }
        abriendo = true
        Task { @MainActor in
            defer { self.abriendo = false }
            do {
                let tomadas = try await Instantanea.fotografiarTodas()
                guard !tomadas.isEmpty else { return }
                self.fotos = self.enElMundo(tomadas)
                self.montar()
            } catch {
                PermisoCaptura.avisarDenegado(detalle: "No se pudo capturar la pantalla: \(error.localizedDescription)")
            }
        }
    }

    /// **⌥ + doble clic central**: abre el anotador vivo y, abierto,
    /// alterna el clic a traves (`gestos::EscuchaAnotador` de Windows).
    public func abrirOAlternar() {
        if abierto { alternarPasante() } else { abrir(.viva) }
    }

    private func enElMundo(_ tomadas: [FotoDePantalla]) -> [FotoEnElMundo] {
        let e = GeometriaAnotador.escritorio(NSScreen.screens.map(\.frame))
        return tomadas.map { FotoEnElMundo(marco: GeometriaAnotador.enElMundo($0.pantalla.frame, escritorio: e),
                                           imagen: $0.imagen) }
    }

    private func montar() {
        let lista = NSScreen.screens
        guard !lista.isEmpty else { return }
        escritorio = GeometriaAnotador.escritorio(lista.map(\.frame))
        pantallas = lista.map { GeometriaAnotador.enElMundo($0.frame, escritorio: escritorio) }
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-anotador-\(UUID().uuidString)", isDirectory: true)
        let editor: EditorLienzo
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            editor = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("pantalla.excalidraw").path,
                                                crear: true)
        } catch {
            NSSound.beep()
            return
        }
        self.carpeta = carpeta
        // Congelada: la foto del escritorio entero, de fondo fijo.
        var fondo: FondoLienzo?
        if modo == .congelada {
            let todo = CGRect(origin: .zero, size: escritorio.size)
            if let img = GeometriaAnotador.componer(fotos, region: todo,
                                                     escala: GeometriaAnotador.escala(de: fotos, en: todo)) {
                fondo = FondoLienzo(imagen: img, tamano: escritorio.size)
            }
        }
        let modelo = ModeloEditorLienzo(editor: editor, nucleo: almacen?.nucleo, titulo: "Pantalla", fondo: fondo)
        // El lapiz en la mano y el rojo de la captura, con trazo limpio.
        modelo.elegir("lapiz")
        modelo.cambiarEstilo(.trazo(color: AnotadorCaptura.colorDePartida))
        modelo.cambiarEstilo(.rugosidad(valor: 0))
        modelo.alCerrar = { [weak self] in self?.salir() }
        self.modelo = modelo
        versionVista = editor.version()
        estado.pasante = false
        estado.aviso = nil
        estado.puedeGuardar = almacen != nil
        pasante = false
        pasanteMomentaneo = false
        yaGuardada = false
        huellaGuardada = nil
        guardado = nil

        // La pantalla del raton lleva la barra y la pastilla.
        let raton = NSEvent.mouseLocation
        let principal = lista.first { $0.frame.contains(raton) } ?? lista[0]
        var panelPrincipal: PanelAnotador?
        for (pantalla, mundo) in zip(lista, pantallas) {
            let panel = PanelAnotador(contentRect: pantalla.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.setFrame(pantalla.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = modo == .congelada
            panel.backgroundColor = modo == .congelada ? .black : .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            // Explicito: si no, lo transparente dejaria pasar el raton.
            panel.ignoresMouseEvents = false
            let limites = NSRect(origin: .zero, size: pantalla.frame.size)
            let contenedor = NSView(frame: limites)
            let vista = VistaEditorLienzoNS(modelo: modelo)
            vista.frame = limites
            vista.autoresizingMask = [.width, .height]
            vista.camaraFija = true
            vista.origenFijo = mundo.origin
            vista.papelTransparente = modo == .viva
            vista.teclaPrevia = { [weak self] e in self?.tecla(e) ?? false }
            contenedor.addSubview(vista)
            if pantalla == principal {
                let barra = HospedajeBarraAnotador(modelo: modelo, zonas: zonas)
                barra.frame = limites
                barra.autoresizingMask = [.width, .height]
                contenedor.addSubview(barra)
                self.barra = barra
                panelPrincipal = panel
                modelo.vista = vista
            }
            panel.contentView = contenedor
            panel.trasEvento = { [weak self, weak vista] e in
                guard let self else { return }
                // La pantalla donde se pulsa es la que manda en el lienzo.
                if e.type == .leftMouseDown, let vista { self.modelo?.vista = vista }
                self.alDia()
            }
            paneles.append(panel)
            vistas.append(vista)
        }
        self.panelPrincipal = panelPrincipal
        for panel in paneles where panel !== panelPrincipal { panel.orderFrontRegardless() }
        panelPrincipal?.makeKeyAndOrderFront(nil)
        if let v = modelo.vista { panelPrincipal?.makeFirstResponder(v) }
        ponerPastilla(en: principal)
        vigilarComando()
    }

    /// La pastilla, abajo en el centro de `pantalla` (sobre el Dock).
    private func ponerPastilla(en pantalla: NSScreen) {
        let vista = PastillaAnotador(estado: estado) { [weak self] a in self?.pulsar(a) }
        let host = NSHostingView(rootView: vista)
        let tam = host.fittingSize
        host.frame = NSRect(origin: .zero, size: tam)
        let panel = PanelAnotador(contentRect: NSRect(origin: .zero, size: tam),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host
        panel.trasEvento = { [weak self] _ in self?.alDia() }
        let z = pantalla.visibleFrame
        panel.setFrameOrigin(CGPoint(x: z.midX - tam.width / 2, y: z.minY + 12))
        panel.orderFrontRegardless()
        pastilla = panel
    }

    /// **Sale**: guarda solo lo nuevo en «Mensajes guardados» y cierra.
    public func salir() {
        guard abierto else { return }
        _ = guardarEnElChat()
        let ultimo = guardado
        let carpeta = self.carpeta
        cerrarVentanas()
        // El fichero temporal del lienzo, cuando haya acabado lo lanzado
        // (y su guardado de 1 s).
        Task {
            _ = await ultimo?.value
            try? await Task.sleep(for: .seconds(2))
            if let carpeta { try? FileManager.default.removeItem(at: carpeta) }
        }
    }

    private func cerrarVentanas() {
        if let vigiaTeclas { NSEvent.removeMonitor(vigiaTeclas) }
        vigiaTeclas = nil
        relojComando?.invalidate()
        relojComando = nil
        relojAviso?.cancel()
        modelo?.desplegado = nil
        for panel in paneles + [pastilla].compactMap({ $0 }) {
            panel.trasEvento = nil
            panel.orderOut(nil)
            panel.close()
        }
        paneles = []
        vistas = []
        barra = nil
        pastilla = nil
        modelo = nil
        fotos = []
        carpeta = nil
        pasante = false
        pasanteMomentaneo = false
    }

    // MARK: - Lo que se hace

    private func pulsar(_ a: AccionPastilla) {
        switch a {
        case .atravesar: alternarPasante()
        case .limpiar: limpiar()
        case .copiar: copiar()
        case .guardar: guardarAhora()
        case .salir: salir()
        }
    }

    /// Las otras pantallas repintan si el dibujo cambio.
    private func alDia() {
        guard let editor = modelo?.editor else { return }
        let v = editor.version()
        guard v != versionVista else { return }
        versionVista = v
        for vista in vistas { vista.needsDisplay = true }
    }

    /// Las teclas propias del anotador (`pantalla::tecla` de Windows); las
    /// demas son del lienzo.
    private func tecla(_ e: NSEvent) -> Bool {
        guard let modelo else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let letra = e.charactersIgnoringModifiers?.lowercased()
        switch e.keyCode {
        case 53 where mods.isEmpty:
            // Esc sin nada elegido: salir. Con algo, lo suelta el lienzo.
            guard modelo.editor.cuantosElegidos() == 0, modelo.desplegado == nil else { return false }
            salir()
            return true
        case 49 where mods.isEmpty && modo == .viva:
            alternarPasante()
            return true
        default:
            break
        }
        if mods == .command, letra == "z" || letra == "y" {
            letra == "z" ? modelo.deshacer() : modelo.rehacer()
            alDia()
            return true
        }
        if mods == [.command, .shift], letra == "z" {
            modelo.rehacer()
            alDia()
            return true
        }
        return false
    }

    /// Espacio, la pastilla o ⌥ + doble clic central (solo viva: en la
    /// congelada no hay nada vivo debajo).
    public func alternarPasante() {
        guard abierto, modo == .viva else { return }
        pasante.toggle()
        aplicarPasante()
    }

    private func aplicarPasante() {
        let p = pasante || pasanteMomentaneo
        for panel in paneles { panel.ignoresMouseEvents = p }
        barra?.isHidden = pasante
        if pasante { modelo?.desplegado = nil }
        estado.pasante = pasante
        if !p { panelPrincipal?.makeKeyAndOrderFront(nil) }
    }

    /// ⌘ mantenido (viva): el clic pasa mientras dure. El ⌘ se suelta a
    /// veces con otra app delante, asi que mientras dura se mira el teclado
    /// cada 50 ms (y solo entonces).
    private func vigilarComando() {
        vigiaTeclas = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, self.abierto, self.modo == .viva, !self.pasante else { return }
                let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                guard mods == .command, !self.pasanteMomentaneo else { return }
                self.pasanteMomentaneo = true
                self.aplicarPasante()
                self.relojComando?.invalidate()
                self.relojComando = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
                    MainActor.assumeIsolated {
                        guard let self, self.abierto else { return t.invalidate() }
                        guard !NSEvent.modifierFlags.contains(.command) else { return }
                        t.invalidate()
                        self.relojComando = nil
                        self.pasanteMomentaneo = false
                        self.aplicarPasante()
                    }
                }
            }
            return e
        }
    }

    /// **Limpiar**: toda la tinta fuera, en UN paso que ⌘Z devuelve (en el
    /// movil no se podia; aqui un ⌘Z que no devuelve cinco minutos de
    /// flechas seria el peor fallo posible). Sin nada, nada que deshacer.
    public func limpiar() {
        guard let modelo, modelo.editor.cuantosElementos() > 0 else { return }
        _ = modelo.editor.terminarTexto()
        modelo.editor.seleccionarTodo()
        modelo.borrarSeleccion()
        alDia()
    }

    /// Lo que se ve en un aviso de la pastilla, un rato.
    private func avisar(_ texto: String) {
        estado.aviso = texto
        relojAviso?.cancel()
        relojAviso = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.estado.aviso = nil
        }
    }

    /// La foto de lo de debajo (congelada: la de antes de abrir).
    private func fotoDeDebajo() async -> [FotoEnElMundo] {
        if modo == .congelada { return fotos }
        guard let tomadas = try? await Instantanea.fotografiarTodas() else { return [] }
        return enElMundo(tomadas)
    }

    /// Las cajas de la tinta, en el mundo.
    private static func cajas(_ t: TintaDePantalla) -> [CGRect] {
        t.cajas.map { CGRect(x: CGFloat($0.x0), y: CGFloat($0.y0),
                             width: CGFloat($0.x1 - $0.x0), height: CGFloat($0.y1 - $0.y0)) }
    }

    /// **Copiar**: la pantalla con lo anotado (las pantallas donde se
    /// dibujo; sin nada, todas), al portapapeles.
    public func copiar() {
        guard let modelo else { return }
        _ = modelo.editor.terminarTexto()
        let editor = modelo.editor
        let todas = pantallas
        let enteras = CGRect(origin: .zero, size: escritorio.size)
        let cajas = AnotadorPantalla.cajas(editor.tintaDePantalla())
        let region = GeometriaAnotador.pantallasConDibujo(todas, cajas: cajas) ?? enteras
        let tapados = modelo.tapados
        Task { @MainActor [weak self] in
            guard let self else { return }
            let debajo = await self.fotoDeDebajo()
            let k = GeometriaAnotador.escala(de: debajo, en: region)
            guard let base = GeometriaAnotador.componer(debajo, region: region, escala: k) else { return NSSound.beep() }
            var final = base
            if editor.cuantosElementos() > 0,
               let tinta = PintorDeHojas.imagen(editor.plano(), caja: region, escala: k, transparente: true,
                                                tapados: tapados, version: editor.version(),
                                                fotos: { modelo.foto($0) }),
               let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            {
                let todo = CGRect(x: 0, y: 0, width: base.width, height: base.height)
                ctx.draw(base, in: todo)
                ctx.draw(tinta, in: todo)
                final = ctx.makeImage() ?? base
            }
            if let alCopiar = self.alCopiar { alCopiar(final, k) } else { Capturador.copiar(final, escala: k) }
            if self.abierto { self.avisar("Copiada al portapapeles") }
        }
    }

    /// **Guardar ya** en «Mensajes guardados» (el boton de la pastilla). Lo
    /// que se dibuje despues pone al dia ese mismo lienzo.
    public func guardarAhora() {
        guard almacen != nil else { return NSSound.beep() }
        if guardarEnElChat() == .nada { avisar("Nada nuevo que guardar") }
    }

    /// **Guarda lo anotado** segun `PasoAnotador`: la primera vez con
    /// tinta, la foto de debajo con la tinta editable; despues, el MISMO
    /// lienzo puesto al dia; sin nada nuevo, nada. Devuelve lo que hizo.
    @discardableResult
    private func guardarEnElChat() -> PasoAnotador {
        guard let almacen, let modelo else { return .nada }
        let editor = modelo.editor
        _ = editor.terminarTexto()
        let tinta = editor.tintaDePantalla()
        let paso = PasoAnotador.de(yaGuardada: yaGuardada, huellaGuardada: huellaGuardada, ahora: tinta.huella)
        let previo = guardado
        switch paso {
        case .nada:
            return .nada
        case .nuevo:
            yaGuardada = true
            huellaGuardada = tinta.huella
            let region = GeometriaAnotador.pantallasConDibujo(pantallas, cajas: AnotadorPantalla.cajas(tinta))
                ?? CGRect(origin: .zero, size: escritorio.size)
            let congeladas = modo == .congelada ? fotos : nil
            guardado = Task { @MainActor [weak self] in
                _ = await previo?.value
                let debajo: [FotoEnElMundo]
                if let congeladas {
                    debajo = congeladas
                } else {
                    debajo = (try? await Instantanea.fotografiarTodas()).map { tomadas in
                        let e = GeometriaAnotador.escritorio(NSScreen.screens.map(\.frame))
                        return tomadas.map { FotoEnElMundo(marco: GeometriaAnotador.enElMundo($0.pantalla.frame, escritorio: e),
                                                           imagen: $0.imagen) }
                    } ?? []
                }
                let k = GeometriaAnotador.escala(de: debajo, en: region)
                let nucleo = almacen.nucleo
                let hecho: Guardada? = await Task.detached(priority: .userInitiated) {
                    guard !debajo.isEmpty,
                          let foto = GeometriaAnotador.componer(debajo, region: region, escala: k),
                          let png = Capturador.codificar(foto, tipo: .png, escala: k) else { return nil }
                    let fichero = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pixpin-pantalla-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at: fichero) }
                    do {
                        try png.write(to: fichero)
                        let p = try nucleo.pantallaAnotadaAlChat(foto: fichero.path, editor: editor,
                                                                 origenX: Float(region.minX), origenY: Float(region.minY),
                                                                 escala: Float(k))
                        return Guardada(pantalla: p, origen: region.origin, escala: k)
                    } catch {
                        return nil
                    }
                }.value
                if let hecho {
                    almacen.anadir([hecho.pantalla.mensaje], en: hecho.pantalla.chat)
                }
                self?.contar(hecho != nil)
                return hecho
            }
        case .alDia:
            huellaGuardada = tinta.huella
            guardado = Task { @MainActor [weak self] in
                guard let g = await previo?.value else {
                    self?.contar(false)
                    return nil
                }
                let nucleo = almacen.nucleo
                let bien = await Task.detached(priority: .userInitiated) {
                    (try? nucleo.ponerAlDiaPantallaAnotada(guardada: g.pantalla, editor: editor,
                                                           origenX: Float(g.origen.x), origenY: Float(g.origen.y),
                                                           escala: Float(g.escala))) != nil
                }.value
                if bien {
                    // La burbuja lo vuelve a leer.
                    NotificationCenter.default.post(name: .pixpinLienzoGuardado, object: g.pantalla.lienzo)
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                }
                self?.contar(bien)
                return g
            }
        }
        return paso
    }

    /// Dice como fue: en la pastilla si sigue abierto; si no, con un aviso
    /// (el globo de Windows).
    private func contar(_ bien: Bool) {
        let texto = bien ? "Guardado en Mensajes guardados" : "No se pudo guardar en Mensajes guardados"
        if abierto {
            avisar(texto)
        } else {
            CentroAvisos.compartido.avisar(Aviso(id: "pixpin.anotador-pantalla", categoria: .mini,
                                                 titulo: "Pantalla anotada", texto: texto))
        }
        if !bien { NSSound.beep() }
    }
}
