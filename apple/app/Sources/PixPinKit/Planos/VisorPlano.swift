// El visor de planos DWG y DXF (`ventana.rs` de Windows con Metal):
// moverse con el trackpad (dos dedos mueven, pellizcar acerca, ⌘ + rueda o
// la rueda del raton acercan donde esta el puntero), la regla con
// enganche, los marcos para imprimir y las capas. Ademas (E2): anotar a mano
// con el lienzo (`AnotarPlano.swift`), exportar (`ExportarPlano.swift`),
// buscar en sus textos (⌘F), sus letras (L) y el fondo claro u oscuro de
// todos los visores (luna/sol, B).
//
// Las teclas, las de Windows: ⎋ (suelta lo de a medias; si no, cierra), ↩
// termina la cota, ⌫ quita el ultimo punto (o el ultimo marco), Supr (fn ⌫)
// el ultimo marco o las cotas, ⌘P imprimir, ⌘E exportar, ⌘F buscar, I
// marcos, A anotar, L letras, F o Inicio todo, B fondo, M medir, T siempre
// encima, 3 en 3D, + y − acercan y las flechas mueven.
//
// **Solo se pinta cuando algo cambia** (§4bis): la `MTKView` esta parada
// (`isPaused`) y pinta al pedirselo (`enableSetNeedsDisplay`). Lo de encima
// (cotas, la mira, lo anotado con el lapiz) va en una vista transparente con
// Core Graphics, que tambien se pinta solo al cambiar.

import AppKit
import Metal
import MetalKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Que hace el raton en el visor.
public enum ModoVisorPlano: String, CaseIterable, Sendable {
    /// Arrastrar mueve el plano.
    case mover
    /// Cada clic pone un punto de la regla (con enganche); doble clic o
    /// Intro la termina y la guarda como cota.
    case medir
    /// Arrastrar dibuja un marco para imprimir.
    case marco
}

/// **El estado del visor de un plano**: lo leido, las capas, lo anotado y
/// lo que se esta midiendo. La vista de Metal lo pinta.
@MainActor
public final class VisorPlano: ObservableObject {
    @Published public private(set) var datos: PlanoEnTarjeta?
    @Published public private(set) var error: String?
    @Published public private(set) var capas: [CapaPlano] = []
    @Published public private(set) var anotado = AnotadoPlano(cotas: [], marcos: [])
    @Published public var modo: ModoVisorPlano = .mover {
        didSet {
            // Medir y marcar no van a la vez que anotar.
            if modo != .mover, anotador != nil { terminarDeAnotar() }
            riel.enmarcando = modo == .marco
            vista?.cambioDeModo()
        }
    }
    /// **Fondo oscuro** (luna/sol, B): el de todos los visores, que se
    /// recuerda (`lectores_oscuros`, como el lector).
    @Published public private(set) var oscuro = false
    /// Anotando con el lienzo encima (A).
    @Published public private(set) var anotando = false { didSet { riel.herramienta = anotando ? "lapiz" : "leer" } }
    /// Siempre encima (T).
    @Published public private(set) var siempreEncima = false
    /// El panel de las capas a la derecha.
    @Published public var verCapas = false
    /// El buscador de textos (⌘F) a la vista, lo hallado y si se busca.
    @Published public var buscando = false
    @Published public private(set) var hallados: [TextoHallado] = []
    @Published public private(set) var buscandoAhora = false
    @Published public private(set) var sinResultado = false
    /// El texto hallado que se ensena (con una marca encima).
    @Published public private(set) var hallado: TextoHallado?
    /// La hoja de las letras (L).
    @Published public var verLetras = false
    /// Las letras que el plano pide y no estan.
    @Published public private(set) var faltan: [String] = []
    /// La medida de la regla en curso (o de la ultima), para la barra.
    @Published public private(set) var medida = ""
    public let titulo: String
    public let ruta: String
    /// El riel (lapiz, marcador, marco) y los marcadores con su vista.
    let riel = ModeloLector()
    private(set) lazy var marcadores = MarcadoresDeVista(documento: URL(fileURLWithPath: ruta), nucleo: nucleo)

    /// Poner un marcador con la vista de ahora: su centro y lo que se ve
    /// (como `Marcador2d` de Windows).
    func ponerMarcador() {
        guard let v = vista else { return }
        let c = v.camara
        marcadores.poner(x: c.centroX, y: c.centroY, ancho: c.px * v.anchoPx, alto: c.px * v.altoPx)
    }

    /// Volver a un marcador: cabe todo lo que se veia.
    func ir(a m: MarcadorDeVista) {
        guard let v = vista, v.anchoPx > 0, v.altoPx > 0 else { return }
        v.ponerCamara(CamaraPlano(centroX: m.x, centroY: m.y, px: max(m.ancho / v.anchoPx, m.alto / v.altoPx)))
    }


    /// Los grupos que se ven.
    private(set) var visibles: Set<UInt32> = []
    /// Lo anotado con el lapiz (la capa del motor del lienzo), solo para verlo.
    private(set) var tinta: LienzoLeido?
    private(set) var encaje: EncajePlano?
    /// Los textos de cada tramo de cada cota (se hacen al cambiar lo anotado).
    private(set) var etiquetas: [[String]] = []
    weak var vista: VistaPlanoMetal?
    /// El nucleo con que se abrio (letras, el modo oscuro, el lienzo).
    private(set) var nucleo: Nucleo?
    /// Lo que hace la tecla 3: el mismo plano en el visor 3D.
    public var alVerEn3D: (() -> Void)?
    /// El lienzo encima mientras se anota.
    private(set) var anotador: AnotadorPlano?
    private var vigias: [NSObjectProtocol] = []
    /// Para no pisar una busqueda con la anterior.
    private var turnoBusqueda = 0

    public init(ruta: String, titulo: String) {
        self.ruta = ruta
        self.titulo = titulo
        // Otro visor cambio la luna/sol: este tambien.
        vigias.append(NotificationCenter.default.addObserver(forName: .pixpinLectoresOscuros, object: nil,
                                                             queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let o = n.object as? Bool, o != self.oscuro else { return }
                self.oscuro = o
                self.vista?.repintar()
            }
        })
    }

    /// Lee el plano fuera del hilo principal y lo sube a la tarjeta.
    public func cargar(nucleo: Nucleo) {
        guard datos == nil, error == nil else { return }
        guard let motor = MotorMetal.compartido else {
            error = "Este Mac no tiene una tarjeta gráfica con Metal."
            return
        }
        self.nucleo = nucleo
        let ruta = self.ruta
        Task {
            // Nunca tocado: manda el aspecto del Mac, como en el lector.
            let guardado = await Task.detached(priority: .userInitiated) { nucleo.lectoresOscuros() }.value
            self.oscuro = guardado ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            self.vista?.repintar()
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<PlanoEnTarjeta, Error> in
                Result { try PlanoEnTarjeta.cargar(ruta: ruta, nucleo: nucleo, motor: motor) }
            }.value
            switch hecho {
            case let .success(d):
                self.poner(d)
            case let .failure(e):
                self.error = "No se pudo abrir el plano: \(e)"
            }
        }
    }

    private func poner(_ d: PlanoEnTarjeta) {
        datos = d
        visibles = Set(d.plano.gruposVisibles())
        capas = d.plano.capas()
        anotado = d.plano.anotado()
        faltan = d.plano.letrasQueFaltan()
        rehacerEtiquetas()
        leerTinta()
        vista?.alLlegarElPlano()
    }

    /// **Vuelve a leer el plano** (con letras nuevas): fuera lo de la
    /// tarjeta y otra vez desde el principio (la cache lo lee de nuevo).
    public func releer() {
        guard let nucleo else { return }
        if anotador != nil { terminarDeAnotar() }
        datos = nil
        error = nil
        capas = []
        visibles = []
        tinta = nil
        vista?.repintar()
        cargar(nucleo: nucleo)
    }

    /// Lo anotado con el lapiz (Windows y Android) se ve encima, tal cual.
    private func leerTinta() {
        guard let d = datos else { return }
        let ruta = d.plano.rutaDeLaCapa()
        encaje = d.plano.encaje()
        guard FileManager.default.fileExists(atPath: ruta) else {
            tinta = nil
            vista?.repintar()
            return
        }
        Task {
            let leida = await Task.detached(priority: .utility) { () -> LienzoLeido? in
                guard let l = try? Lienzo.deFichero(ruta: ruta) else { return nil }
                return try? leerLienzo(l.plano())
            }.value
            self.tinta = leida
            self.vista?.repintar()
        }
    }

    private func rehacerEtiquetas() {
        guard let p = datos?.plano else { etiquetas = []; return }
        etiquetas = anotado.cotas.map { c in
            zip(c.puntos, c.puntos.dropFirst()).map { a, b in p.textoDeMedida(distancia: hypot(b.x - a.x, b.y - a.y)) }
        }
    }

    // MARK: Capas

    public func ponerCapa(_ nombre: String, encendida: Bool) {
        guard let p = datos?.plano, p.ponerCapa(nombre: nombre, encendida: encendida) else { return }
        visibles = Set(p.gruposVisibles())
        capas = p.capas()
        vista?.repintar()
    }

    public func todasLasCapas(_ encendidas: Bool) {
        guard let p = datos?.plano else { return }
        for c in capas { _ = p.ponerCapa(nombre: c.nombre, encendida: encendidas) }
        visibles = Set(p.gruposVisibles())
        capas = p.capas()
        vista?.repintar()
    }

    // MARK: Regla, cotas y marcos

    /// El texto de una medida (con la unidad del plano).
    func texto(_ d: Double) -> String { datos?.plano.textoDeMedida(distancia: d) ?? String(format: "%.3f", d) }

    func ponerMedida(_ t: String) {
        if medida != t { medida = t }
    }

    /// Guarda en la capa (la que viaja) una cota nueva.
    func anadirCota(_ puntos: [PuntoPlano]) {
        guard puntos.count >= 2 else { return }
        var a = anotado
        a.cotas.append(CotaPlano(puntos: puntos))
        guardar(a)
    }

    func anadirMarco(_ c: CajaPlano) {
        var a = anotado
        a.marcos.append(c)
        guardar(a)
    }

    public func borrarCotas() {
        var a = anotado
        a.cotas = []
        guardar(a)
    }

    /// Una ficha de abajo: mira el marco `i` entero, con un margen.
    func irAMarco(_ i: Int) {
        guard i < anotado.marcos.count, let v = vista else { return }
        let m = anotado.marcos[i]
        let ancho = max(m.x1 - m.x0, (m.y1 - m.y0) * v.anchoPx / max(v.altoPx, 1)) * 1.1
        v.mirar(centroX: (m.x0 + m.x1) / 2, centroY: (m.y0 + m.y1) / 2, ancho: ancho)
    }

    public func borrarMarcos() {
        var a = anotado
        a.marcos = []
        guardar(a)
    }

    /// Quita el ultimo marco para imprimir (⌫ o Supr marcando).
    public func quitarUltimoMarco() {
        guard !anotado.marcos.isEmpty else { return }
        var a = anotado
        a.marcos.removeLast()
        guardar(a)
    }

    /// Lo anotado se ve al momento y se escribe fuera del hilo principal.
    private func guardar(_ a: AnotadoPlano) {
        guard let p = datos?.plano else { return }
        anotado = a
        rehacerEtiquetas()
        vista?.repintar()
        Task.detached(priority: .utility) {
            do {
                _ = try p.guardarAnotado(anotado: a)
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    // MARK: Ordenes de la barra

    public func encuadrar() { vista?.encuadrar() }

    /// Las cotas y lo anotado, para el papel (imprimir y exportar).
    func encimaParaPapel() -> EncimaPapel {
        let p = datos?.plano
        return EncimaPapel(cotas: anotado.cotas,
                           medida: { d in p?.textoDeMedida(distancia: d) ?? String(format: "%.3f", d) },
                           tinta: tinta, encaje: encaje)
    }

    public func imprimir() {
        guard let d = datos, let v = vista else { return }
        if anotador != nil { terminarDeAnotar() }
        ImpresionPlano.imprimir(d, visibles: visibles, region: anotado.marcos.last ?? v.cajaVisible(),
                                titulo: titulo, encima: encimaParaPapel(), ventana: v.window)
    }

    /// ⌘E: la hoja de compartir con los formatos del plano.
    public func exportar() {
        guard datos != nil else { return }
        if anotador != nil {
            // Primero lo anotado, guardado y leido: va en lo exportado.
            terminarDeAnotar { [weak self] in self.map { ExportarPlano.abrir($0) } }
            return
        }
        ExportarPlano.abrir(self)
    }

    /// **Luna/sol** (B): el fondo de todos los visores, que se recuerda.
    public func alternarOscuro() {
        oscuro.toggle()
        vista?.repintar()
        let o = oscuro
        if let nucleo { Task.detached(priority: .utility) { try? nucleo.guardarLectoresOscuros(oscuros: o) } }
        NotificationCenter.default.post(name: .pixpinLectoresOscuros, object: o)
    }

    /// T: la ventana siempre encima (o no).
    public func alternarEncima() {
        siempreEncima.toggle()
        vista?.window?.level = siempreEncima ? .floating : .normal
    }

    /// I: los marcos para imprimir (otra vez, a mover).
    public func alternarMarcos() { modo = modo == .marco ? .mover : .marco }

    /// M: medir (otra vez, a mover).
    public func alternarMedir() { modo = modo == .medir ? .mover : .medir }

    /// 3: el mismo plano en 3D.
    public func verEn3D() { alVerEn3D?() }

    /// Cierra la ventana del plano.
    public func cerrar() { VentanaLisa.escapar(vista?.window) }

    // MARK: Anotar (A)

    /// A: empieza o termina de anotar con el lienzo.
    public func alternarAnotar() {
        if anotador != nil { terminarDeAnotar() } else { empezarAnotar() }
    }

    private func empezarAnotar() {
        guard let d = datos, let v = vista else { return }
        if modo != .mover { modo = .mover }
        do {
            let a = try AnotadorPlano(plano: d.plano, nucleo: nucleo, titulo: titulo)
            anotador = a
            anotando = true
            v.ponerAnotador(a)
        } catch {
            NSSound.beep()
            NSLog("PixPin planos: no se puede anotar: \(error)")
        }
    }

    /// Termina de anotar: guarda y vuelve a leer lo anotado (las cotas y
    /// los marcos pudieron cambiar con el lienzo).
    func terminarDeAnotar(_ despues: (() -> Void)? = nil) {
        guard let a = anotador else { despues?(); return }
        anotador = nil
        anotando = false
        vista?.quitarAnotador()
        Task {
            await a.terminar()
            if let p = self.datos?.plano {
                self.anotado = p.anotado()
                self.rehacerEtiquetas()
            }
            self.leerTinta()
            self.vista?.repintar()
            despues?()
        }
    }

    // MARK: Buscar en los textos (⌘F)

    /// Busca `consulta` en los textos del plano (la primera vez los lee:
    /// fuera del hilo principal) y lleva al primero.
    public func buscar(_ consulta: String) {
        guard let p = datos?.plano else { return }
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        turnoBusqueda += 1
        let turno = turnoBusqueda
        guard !q.isEmpty else {
            hallados = []
            hallado = nil
            sinResultado = false
            vista?.repintar()
            return
        }
        buscandoAhora = true
        Task {
            let r = await Task.detached(priority: .userInitiated) { try? p.buscarTextos(consulta: q, max: 50) }.value
            guard turno == self.turnoBusqueda else { return }
            self.buscandoAhora = false
            self.hallados = r ?? []
            self.sinResultado = (r ?? []).isEmpty
            if let h = self.hallados.first { self.mirar(h) } else { self.hallado = nil; self.vista?.repintar() }
        }
    }

    /// Lleva la vista a un texto hallado y lo marca.
    public func mirar(_ h: TextoHallado) {
        hallado = h
        vista?.mirar(centroX: h.centroX, centroY: h.centroY, ancho: h.ancho)
    }

    public func cerrarBusqueda() {
        buscando = false
        hallado = nil
        vista?.repintar()
        if let v = vista { v.window?.makeFirstResponder(v) }
    }

    // MARK: Letras (L)

    /// Añade letras (SHX, TTF, OTF, TTC) y vuelve a leer el plano con ellas.
    public func anadirLetras(_ urls: [URL]) {
        guard let nucleo, !urls.isEmpty else { return }
        let rutas = urls.map(\.path)
        Task {
            let n = await Task.detached(priority: .userInitiated) { nucleo.anadirLetrasDePlanos(rutas: rutas) }.value
            if n > 0 { self.releer() } else { NSSound.beep() }
        }
    }

    /// Quita las letras del usuario y vuelve a leer el plano.
    public func quitarLetras() {
        guard let nucleo else { return }
        Task {
            let n = await Task.detached(priority: .userInitiated) { nucleo.quitarLetrasDePlanos() }.value
            if n > 0 { self.releer() }
        }
    }

    /// Cuantas letras puso el usuario.
    public var letrasMias: UInt32 { nucleo?.letrasDePlanos() ?? 0 }
}

// MARK: - La vista de Metal

/// **El plano en Metal.** Una `MTKView` parada que pinta solo al cambiar
/// algo; los gestos mueven la camara (`CamaraPlano`).
public final class VistaPlanoMetal: MTKView {
    let visor: VisorPlano
    private let motor: MotorMetal
    private let pintor: PintorPlano
    private(set) var camara = CamaraPlano(centroX: 0, centroY: 0, px: 1) {
        didSet { seguirAnotador() }
    }
    private var encuadrado = false
    /// Volver a una vista guardada (un marcador).
    func ponerCamara(_ c: CamaraPlano) {
        encuadrado = true
        camara = c
        needsDisplay = true
    }
    private let encima = CapaEncimaPlano()
    private var seguimiento: NSTrackingArea?

    // La regla y el marco.
    private(set) var cadena: [PuntoPlano] = []
    private(set) var mira: Enganche?
    private(set) var marcoEnCurso: (PuntoPlano, PuntoPlano)?
    private var arrastre: CGPoint?

    init(visor: VisorPlano, motor: MotorMetal) {
        self.visor = visor
        self.motor = motor
        let muestras = motor.muestras
        pintor = PintorPlano(motor: motor, color: .bgra8Unorm, muestras: muestras)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), device: motor.dispositivo)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .invalid
        sampleCount = muestras
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        // El plano y lo de encima (tinta, marcos) en el mismo fotograma:
        // sin esto la tinta iba un paso por detras al mover.
        (layer as? CAMetalLayer)?.presentsWithTransaction = true
        encima.vista = self
        encima.frame = bounds
        encima.autoresizingMask = [.width, .height]
        addSubview(encima)
        encima.wantsLayer = true
        encima.layer?.actions = ["contents": NSNull()]
        visor.vista = self
        try? pintor.preparar()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override public var acceptsFirstResponder: Bool { true }
    override public var isOpaque: Bool { true }

    /// Pinta otra vez (y lo de encima).
    func repintar() {
        needsDisplay = true
        encima.needsDisplay = true
    }

    /// **Al mover la camara**: el plano, lo de encima y la tinta que se esta
    /// anotando se pintan YA y en la misma transaccion (la capa de Metal va
    /// con ella): si cada uno esperaba a su ciclo, la tinta y los marcos
    /// iban un paso por detras del plano.
    func repintarYa() {
        // Sin el fundido que Core Animation pone al cambiar el contenido de
        // una capa: con el, la tinta dejaba un rastro detras del plano.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draw()
        encima.display()
        if let a = visor.anotador?.vista { a.display() }
        CATransaction.commit()
    }

    /// Pixeles por punto de la pantalla.
    var escala: Double {
        bounds.width > 0 ? Double(drawableSize.width) / Double(bounds.width) : Double(window?.backingScaleFactor ?? 2)
    }

    var anchoPx: Double { Double(drawableSize.width) }
    var altoPx: Double { Double(drawableSize.height) }

    /// El fondo: el de la luna/sol de los visores (`VisorPlano.oscuro`).
    private var oscuro: Bool { visor.oscuro }

    /// El punto del dibujo bajo un punto de la vista.
    func aDibujo(_ p: CGPoint) -> PuntoPlano {
        camara.aDibujo(x: Double(p.x) * escala, y: Double(p.y) * escala, ancho: anchoPx, alto: altoPx)
    }

    /// El punto de la vista de un punto del dibujo.
    func aVista(_ p: PuntoPlano) -> CGPoint {
        let q = camara.aPixel(p, ancho: anchoPx, alto: altoPx)
        let e = escala
        return CGPoint(x: q.x / e, y: q.y / e)
    }

    /// Lo que se ve, en el dibujo.
    func cajaVisible() -> CajaPlano { camara.caja(ancho: anchoPx, alto: altoPx) }

    func alLlegarElPlano() {
        encuadrado = false
        encuadrar()
    }

    func encuadrar() {
        guard let d = visor.datos, anchoPx > 0, altoPx > 0 else { return }
        camara = CamaraPlano.encuadrar(d.resumen.cajaUtil, ancho: anchoPx, alto: altoPx)
        encuadrado = true
        repintar()
    }

    func cambioDeModo() {
        cadena = []
        mira = nil
        marcoEnCurso = nil
        visor.ponerMedida("")
        window?.invalidateCursorRects(for: self)
        repintar()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !encuadrado { encuadrar() }
        seguirAnotador()
        repintar()
    }

    // MARK: Anotar, buscar

    /// Pone el lienzo encima (anotando): dentro de esta vista, encima de
    /// todo, con la camara del plano.
    func ponerAnotador(_ a: AnotadorPlano) {
        a.vista.frame = bounds
        a.vista.camaraDeFuera = self
        // ⎋ sin nada elegido deja de anotar; ⌘E, ⌘P y ⌘F son del visor.
        a.vista.teclaPrevia = { [weak self, weak a] e in
            guard let self, let a else { return false }
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function])
            if e.keyCode == 53, mods.isEmpty, a.modelo.editor.cuantosElegidos() == 0 {
                self.visor.alternarAnotar()
                return true
            }
            if mods == .command, ["e", "p", "f"].contains(e.charactersIgnoringModifiers?.lowercased() ?? "") {
                return VistaPlanoMetal.tecla(e, visor: self.visor, vista: self)
            }
            return false
        }
        addSubview(a.vista, positioned: .above, relativeTo: encima)
        seguirAnotador()
        window?.makeFirstResponder(a.vista)
        repintar()
    }

    func quitarAnotador() {
        window?.makeFirstResponder(self)
        repintar()
    }

    private func seguirAnotador() {
        visor.anotador?.seguir(camara, escala: escala, tamano: bounds.size)
    }

    /// Mira a `(centroX, centroY)` con `ancho` del dibujo a lo ancho.
    func mirar(centroX: Double, centroY: Double, ancho: Double) {
        guard anchoPx > 0, ancho > 0 else { return }
        camara = CamaraPlano(centroX: centroX, centroY: centroY, px: ancho / anchoPx)
        encuadrado = true
        repintar()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repintar()
    }

    override public func resetCursorRects() {
        addCursorRect(bounds, cursor: visor.modo == .mover ? .openHand : .crosshair)
    }

    // MARK: Pintar

    override public func draw(_ dirtyRect: NSRect) {
        let oscuro = self.oscuro
        clearColor = oscuro ? MTLClearColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
            : MTLClearColor(red: 0.99, green: 0.988, blue: 0.976, alpha: 1)
        guard let pasada = currentRenderPassDescriptor, let dibujable = currentDrawable,
              let cb = motor.cola.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pasada) else { return }
        if let d = visor.datos {
            do {
                try pintor.pintar(d, visibles: visor.visibles, camara: camara, ancho: anchoPx, alto: altoPx,
                                  oscuro: oscuro, en: enc)
            } catch {
                NSLog("PixPin planos: \(error)")
            }
        }
        enc.endEncoding()
        cb.commit()
        cb.waitUntilScheduled()
        dibujable.present()
    }

    // MARK: Gestos

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let s = seguimiento { removeTrackingArea(s) }
        let s = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(s)
        seguimiento = s
    }

    private func punto(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    /// Acercar `factor` dejando quieto el punto `p` de la vista.
    private func zoom(_ factor: Double, en p: CGPoint) {
        camara = camara.zoom(factor, x: Double(p.x) * escala, y: Double(p.y) * escala, ancho: anchoPx, alto: altoPx)
        repintarYa()
    }

    override public func scrollWheel(with e: NSEvent) {
        let p = punto(e)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) && !e.modifierFlags.contains(.control) {
            // Dos dedos en el trackpad: el plano sigue a los dedos.
            camara = camara.mover(dx: Double(e.scrollingDeltaX) * escala, dy: -Double(e.scrollingDeltaY) * escala)
            repintarYa()
        } else {
            // La rueda del raton (o ⌘ + dos dedos): acercar donde esta el puntero.
            let paso = e.hasPreciseScrollingDeltas ? Double(e.scrollingDeltaY) / 40 : Double(e.scrollingDeltaY)
            zoom(pow(1.2, paso), en: p)
        }
    }

    override public func magnify(with e: NSEvent) {
        zoom(1 + Double(e.magnification), en: punto(e))
    }

    override public func smartMagnify(with e: NSEvent) {
        encuadrar()
    }

    /// El enganche de la regla bajo el puntero (a 8 puntos de la pantalla).
    private func enganche(_ p: CGPoint) -> Enganche {
        let d = aDibujo(p)
        guard let plano = visor.datos?.plano else { return Enganche(x: d.x, y: d.y, tipo: .libre) }
        let radio = 8 * escala * camara.px
        return plano.enganchar(x: d.x, y: d.y, radio: radio, desde: cadena.last)
    }

    private func actualizarMedida() {
        var puntos = cadena
        if let m = mira { puntos.append(PuntoPlano(x: m.x, y: m.y)) }
        guard puntos.count >= 2 else {
            visor.ponerMedida(cadena.isEmpty ? "" : "Clic: otro punto · doble clic o Intro: guardar · Esc: soltar")
            return
        }
        var total = 0.0
        for (a, b) in zip(puntos, puntos.dropFirst()) { total += hypot(b.x - a.x, b.y - a.y) }
        let ultimo = hypot(puntos[puntos.count - 1].x - puntos[puntos.count - 2].x,
                           puntos[puntos.count - 1].y - puntos[puntos.count - 2].y)
        visor.ponerMedida(puntos.count > 2 ? "\(visor.texto(ultimo)) · total \(visor.texto(total))" : visor.texto(ultimo))
    }

    override public func mouseMoved(with e: NSEvent) {
        guard visor.modo != .mover, visor.datos != nil else { return }
        mira = enganche(punto(e))
        if visor.modo == .medir { actualizarMedida() }
        encima.needsDisplay = true
    }

    override public func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = punto(e)
        switch visor.modo {
        case .mover:
            arrastre = p
            NSCursor.closedHand.push()
        case .medir:
            let m = enganche(p)
            let q = PuntoPlano(x: m.x, y: m.y)
            if e.clickCount >= 2 {
                terminarCadena()
            } else if cadena.last != q {
                cadena.append(q)
            }
            actualizarMedida()
            encima.needsDisplay = true
        case .marco:
            let m = enganche(p)
            let q = PuntoPlano(x: m.x, y: m.y)
            marcoEnCurso = (q, q)
            encima.needsDisplay = true
        }
    }

    override public func mouseDragged(with e: NSEvent) {
        let p = punto(e)
        switch visor.modo {
        case .mover:
            guard let a = arrastre else { return }
            camara = camara.mover(dx: Double(p.x - a.x) * escala, dy: Double(p.y - a.y) * escala)
            arrastre = p
            repintarYa()
        case .medir:
            mira = enganche(p)
            actualizarMedida()
            encima.needsDisplay = true
        case .marco:
            guard let a = marcoEnCurso?.0 else { return }
            let m = enganche(p)
            mira = m
            marcoEnCurso = (a, PuntoPlano(x: m.x, y: m.y))
            encima.needsDisplay = true
        }
    }

    override public func mouseUp(with e: NSEvent) {
        if arrastre != nil {
            arrastre = nil
            NSCursor.pop()
        }
        if visor.modo == .marco, let enCurso = marcoEnCurso {
            let (a, b) = enCurso
            marcoEnCurso = nil
            let c = CajaPlano(x0: min(a.x, b.x), y0: min(a.y, b.y), x1: max(a.x, b.x), y1: max(a.y, b.y))
            // Un clic sin arrastrar no es un marco.
            if (c.x1 - c.x0) / camara.px > 4 && (c.y1 - c.y0) / camara.px > 4 { visor.anadirMarco(c) }
            encima.needsDisplay = true
        }
    }

    // El boton derecho siempre mueve el plano, en cualquier modo.
    override public func rightMouseDown(with e: NSEvent) { arrastre = punto(e) }

    override public func rightMouseDragged(with e: NSEvent) {
        guard let a = arrastre else { return }
        let p = punto(e)
        camara = camara.mover(dx: Double(p.x - a.x) * escala, dy: Double(p.y - a.y) * escala)
        arrastre = p
        repintarYa()
    }

    override public func rightMouseUp(with e: NSEvent) { arrastre = nil }

    func terminarCadena() {
        let puntos = cadena
        cadena = []
        if puntos.count >= 2 { visor.anadirCota(puntos) }
        actualizarMedida()
        encima.needsDisplay = true
    }

    override public func keyDown(with e: NSEvent) {
        if !VistaPlanoMetal.tecla(e, visor: visor, vista: self) { super.keyDown(with: e) }
    }

    /// Mueve la vista un 15 % de lo que se ve (las flechas de Windows).
    func desplazarTeclado(_ fx: Double, _ fy: Double) {
        // Lo que se ve en pixeles (aun sin dibujable, por el tamano de la vista).
        let w = max(anchoPx, Double(bounds.width) * escala), h = max(altoPx, Double(bounds.height) * escala)
        camara = camara.mover(dx: -fx * 0.15 * w, dy: -fy * 0.15 * h)
        repintar()
    }

    /// **Las teclas del visor de planos** (las de `ventana.rs` de Windows).
    /// Dice si la uso. Tambien las mira el lienzo mientras se anota (las
    /// que no son del lienzo: ⌘E, ⌘P, ⌘F, ⎋ sin nada a medias).
    @discardableResult
    static func tecla(_ e: NSEvent, visor: VisorPlano, vista v: VistaPlanoMetal) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let letra = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == .command {
            switch letra {
            case "e": visor.exportar()
            case "p": visor.imprimir()
            case "f": visor.buscando = true
            default: return false
            }
            return true
        }
        guard mods.isEmpty || mods == .shift else { return false }
        switch e.keyCode {
        case 53: // Esc: lo de a medias; si no, deja el modo; si no, cierra
            if !v.cadena.isEmpty || v.marcoEnCurso != nil {
                v.soltarLoDeAMedias()
            } else if visor.anotando {
                visor.alternarAnotar()
            } else if visor.buscando {
                visor.cerrarBusqueda()
            } else if visor.modo != .mover {
                visor.modo = .mover
            } else {
                visor.cerrar()
            }
        case 36, 76: // Intro: la cota a medias, guardada
            v.terminarCadena()
        case 51: // ⌫: el ultimo punto de la regla, o el ultimo marco
            if !v.cadena.isEmpty {
                v.quitarUltimoPunto()
            } else if visor.modo == .marco {
                visor.quitarUltimoMarco()
            } else {
                return false
            }
        case 117: // Supr: marcando, el ultimo marco; si no, las cotas
            if visor.modo == .marco { visor.quitarUltimoMarco() } else { visor.borrarCotas() }
        case 115: v.encuadrar() // Inicio
        case 123: v.desplazarTeclado(-1, 0)
        case 124: v.desplazarTeclado(1, 0)
        case 126: v.desplazarTeclado(0, 1)
        case 125: v.desplazarTeclado(0, -1)
        default:
            switch letra {
            case "f": v.encuadrar()
            case "m": visor.alternarMedir()
            case "i": visor.alternarMarcos()
            case "a": visor.alternarAnotar()
            case "l": visor.verLetras = true
            case "b": visor.alternarOscuro()
            case "t": visor.alternarEncima()
            case "3": visor.verEn3D()
            case "+", "=": v.acercarTeclado(1.4)
            case "-": v.acercarTeclado(1 / 1.4)
            default: return false
            }
        }
        return true
    }

    func acercarTeclado(_ f: Double) { zoom(f, en: CGPoint(x: bounds.midX, y: bounds.midY)) }

    func soltarLoDeAMedias() {
        cadena = []
        marcoEnCurso = nil
        actualizarMedida()
        encima.needsDisplay = true
    }

    func quitarUltimoPunto() {
        guard !cadena.isEmpty else { return }
        cadena.removeLast()
        actualizarMedida()
        encima.needsDisplay = true
    }
}

// MARK: - Lo de encima

/// **Lo que va encima del plano**, con Core Graphics: lo anotado con el
/// lapiz, las cotas (naranja, como Windows y Android), los marcos para
/// imprimir (azul), la regla en curso y la mira del enganche. No recibe el
/// raton: todo lo atiende la vista de Metal.
final class CapaEncimaPlano: NSView {
    weak var vista: VistaPlanoMetal?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static let naranja = NSColor(srgbRed: 1, green: 0x8a / 255.0, blue: 0, alpha: 1)
    static let azul = NSColor(srgbRed: 0x3d / 255.0, green: 0x8b / 255.0, blue: 1, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        guard let v = vista, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let visor = v.visor
        pintarHallado(v, visor, ctx)
        // Anotando, la capa entera (tambien las cotas y los marcos) la
        // pinta el lienzo de encima.
        guard !visor.anotando else { return }
        pintarTinta(v, visor, ctx)
        // Los marcos para imprimir.
        ctx.setLineWidth(1.2)
        ctx.setStrokeColor(CapaMarcosPDF.azul.cgColor)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        for m in visor.anotado.marcos {
            ctx.stroke(rect(v, m))
        }
        ctx.setLineDash(phase: 0, lengths: [])
        // Su numero abajo a la izquierda, como en los demas visores.
        for (i, m) in visor.anotado.marcos.enumerated() {
            let r = rect(v, m)
            let t = "\(i + 1)" as NSString
            let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                                                      .foregroundColor: NSColor.white]
            let tam = t.size(withAttributes: atr)
            let caja = CGRect(x: r.minX, y: r.minY, width: max(16, tam.width + 6), height: 16)
            ctx.setFillColor(CapaMarcosPDF.azul.cgColor)
            ctx.fill(caja)
            NSGraphicsContext.saveGraphicsState()
            t.draw(at: CGPoint(x: caja.midX - tam.width / 2, y: caja.midY - tam.height / 2), withAttributes: atr)
            NSGraphicsContext.restoreGraphicsState()
        }
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        if let m = v.marcoEnCurso {
            let (a, b) = m
            ctx.stroke(rect(v, CajaPlano(x0: min(a.x, b.x), y0: min(a.y, b.y), x1: max(a.x, b.x), y1: max(a.y, b.y))))
        }
        ctx.setLineDash(phase: 0, lengths: [])
        // Las cotas guardadas y la regla en curso.
        for (k, c) in visor.anotado.cotas.enumerated() {
            let textos = k < visor.etiquetas.count ? visor.etiquetas[k] : []
            cadena(v, c.puntos, textos: textos, ctx: ctx)
        }
        if !v.cadena.isEmpty {
            var puntos = v.cadena
            if let m = v.mira { puntos.append(PuntoPlano(x: m.x, y: m.y)) }
            let textos = zip(puntos, puntos.dropFirst()).map { a, b in visor.texto(hypot(b.x - a.x, b.y - a.y)) }
            cadena(v, puntos, textos: textos, ctx: ctx)
        }
        if let m = v.mira, visor.modo != .mover { pintarMira(v.aVista(PuntoPlano(x: m.x, y: m.y)), m.tipo, ctx) }
    }

    /// El texto hallado (⌘F): un recuadro amarillo alrededor.
    private func pintarHallado(_ v: VistaPlanoMetal, _ visor: VisorPlano, _ ctx: CGContext) {
        guard let h = visor.hallado else { return }
        let largo = Double(max(h.texto.count, 1))
        let caja = CajaPlano(x0: h.x - h.alto * 0.3, y0: h.y - h.alto * 0.3,
                             x1: h.x + h.alto * largo * 0.75, y1: h.y + h.alto * 1.3)
        let r = rect(v, caja).insetBy(dx: -4, dy: -4)
        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.25).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(r)
    }

    private func rect(_ v: VistaPlanoMetal, _ c: CajaPlano) -> CGRect {
        let a = v.aVista(PuntoPlano(x: c.x0, y: c.y0)), b = v.aVista(PuntoPlano(x: c.x1, y: c.y1))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Una cadena de cotas: la raya, sus puntos y cada medida en su tramo.
    private func cadena(_ v: VistaPlanoMetal, _ puntos: [PuntoPlano], textos: [String], ctx: CGContext) {
        let q = puntos.map { v.aVista($0) }
        guard q.count >= 2 else {
            if let p = q.first { marca(p, ctx) }
            return
        }
        ctx.setStrokeColor(CapaEncimaPlano.naranja.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addLines(between: q)
        ctx.strokePath()
        for p in q { marca(p, ctx) }
        let atributos: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: CapaEncimaPlano.naranja.withAlphaComponent(0.9),
        ]
        for (i, t) in textos.enumerated() where i + 1 < q.count {
            let m = CGPoint(x: (q[i].x + q[i + 1].x) / 2, y: (q[i].y + q[i + 1].y) / 2)
            let s = NSAttributedString(string: " \(t) ", attributes: atributos)
            let tam = s.size()
            s.draw(at: CGPoint(x: m.x - tam.width / 2, y: m.y + 3))
        }
    }

    private func marca(_ p: CGPoint, _ ctx: CGContext) {
        ctx.setFillColor(CapaEncimaPlano.naranja.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
    }

    /// La mira: un cuadrado en un punto, una escuadra en la perpendicular,
    /// una cruz en la raya y un circulo libre (las marcas de AutoCAD).
    private func pintarMira(_ p: CGPoint, _ tipo: TipoEnganche, _ ctx: CGContext) {
        let r: CGFloat = 6
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        switch tipo {
        case .punto:
            ctx.stroke(CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        case .perpendicular:
            ctx.addLines(between: [CGPoint(x: p.x - r, y: p.y + r), CGPoint(x: p.x - r, y: p.y - r), CGPoint(x: p.x + r, y: p.y - r)])
            ctx.addLines(between: [CGPoint(x: p.x - r, y: p.y), CGPoint(x: p.x, y: p.y), CGPoint(x: p.x, y: p.y - r)])
            ctx.strokePath()
        case .enLaRaya:
            ctx.addLines(between: [CGPoint(x: p.x - r, y: p.y - r), CGPoint(x: p.x + r, y: p.y + r)])
            ctx.addLines(between: [CGPoint(x: p.x - r, y: p.y + r), CGPoint(x: p.x + r, y: p.y - r)])
            ctx.strokePath()
        case .libre:
            ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
            ctx.strokeEllipse(in: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r))
        }
    }

    /// Lo anotado con el lapiz, en su sitio: `x = cero_x + x_capa * u`,
    /// `y = cero_y - y_capa * u` (la y de la capa baja).
    private func pintarTinta(_ v: VistaPlanoMetal, _ visor: VisorPlano, _ ctx: CGContext) {
        guard let tinta = visor.tinta, let e = visor.encaje, e.u > 0 else { return }
        let c = v.camara
        let s = c.px * v.escala // unidades del dibujo por punto
        let a = e.u / s
        let t = CGAffineTransform(a: a, b: 0, c: 0, d: -a,
                                  tx: (e.ceroX - c.centroX) / s + Double(v.bounds.midX),
                                  ty: (e.ceroY - c.centroY) / s + Double(v.bounds.midY))
        ctx.saveGState()
        ctx.concatenate(t)
        let limites = v.bounds.applying(t.inverted())
        PintorLienzo(lienzo: tinta).pintar(en: ctx, limites: limites)
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI

/// La vista de Metal dentro de SwiftUI.
struct LienzoMetalPlano: NSViewRepresentable {
    let visor: VisorPlano
    let motor: MotorMetal

    func makeNSView(context _: Context) -> VistaPlanoMetal { VistaPlanoMetal(visor: visor, motor: motor) }
    func updateNSView(_ v: VistaPlanoMetal, context _: Context) { v.repintar() }
}

/// **La ventana de un plano**: la barra (modos, anotar, encuadrar, buscar,
/// luna/sol, letras, 3D, exportar, imprimir, encima), el plano y el panel
/// de capas. Anotando, encima flotan la barra y el panel del lienzo.
public struct VentanaPlanoView: View {
    @ObservedObject var visor: VisorPlano
    @State private var consulta = ""
    @FocusState private var enLaBusqueda: Bool

    public init(visor: VisorPlano, alVerEn3D: @escaping () -> Void) {
        self.visor = visor
        visor.alVerEn3D = alVerEn3D
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    contenido
                    if visor.anotando, let a = visor.anotador {
                        HerramientasDelPlano(modelo: a.modelo)
                    }
                    if visor.buscando { busqueda.padding(10).frame(maxWidth: .infinity, alignment: .topTrailing) }
                    if visor.datos != nil && !visor.verCapas {
                        RielDeVistas(modelo: visor.riel, marcadores: visor.marcadores,
                                     lapiz: { visor.alternarAnotar() }, marcar: { visor.ponerMarcador() },
                                     marco: { visor.alternarMarcos() },
                                     ir: { visor.ir(a: $0) })
                    }

                    // Las fichas 1, 2, 3… de los marcos, abajo a la izquierda.
                    if visor.datos != nil && (!visor.anotado.marcos.isEmpty || visor.modo == .marco) {
                        fichasDeMarcos
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(14)
                    }

                    // Las capas, un menu flotante (no una columna fija).
                    if visor.verCapas && visor.datos != nil {
                        PanelFlotantePlano(alto: min(380, 52 + CGFloat(visor.capas.count) * 26)) { panelCapas }
                    }
                }
            }
        }
        .sheet(isPresented: $visor.verLetras) { LetrasDelPlanoView(visor: visor) }
    }

    private var fichasDeMarcos: some View {
        HStack(spacing: 6) {
            ForEach(Array(visor.anotado.marcos.indices), id: \.self) { i in
                Button { visor.irAMarco(i) } label: {
                    Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: CapaMarcosPDF.azul)))
                }
                .buttonStyle(.plain)
                .help("Ir al marco \(i + 1)")
            }
            if visor.modo == .marco {
                Text(visor.anotado.marcos.isEmpty ? "Arrastra para poner un marco · I sale"
                     : "Arrastra: otro marco · Supr quita el último · ⌘P imprime · I sale")
                    .font(.system(size: 11)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Color(white: 0.08, opacity: 0.9)))
            }
        }
    }

    @ViewBuilder private var contenido: some View {
        if let error = visor.error {
            ContentUnavailableView("No se puede ver el plano", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let motor = MotorMetal.compartido {
            ZStack {
                LienzoMetalPlano(visor: visor, motor: motor)
                if visor.datos == nil { ProgressView("Leyendo el plano…") }
            }
        } else {
            ContentUnavailableView("Sin Metal", systemImage: "cpu", description: Text("Este Mac no tiene una tarjeta gráfica con Metal."))
        }
    }

    /// El buscador de textos (⌘F): lo hallado, el mas grande primero.
    private var busqueda: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar en el plano", text: $consulta)
                    .textFieldStyle(.plain)
                    .focused($enLaBusqueda)
                    .onSubmit { visor.buscar(consulta) }
                    .onExitCommand { visor.cerrarBusqueda() }
                if visor.buscandoAhora { ProgressView().controlSize(.small) }
                Button { visor.cerrarBusqueda() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if visor.sinResultado {
                Text("No está en los textos del plano").font(.callout).foregroundStyle(.secondary)
            }
            if !visor.hallados.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(visor.hallados.enumerated()), id: \.offset) { _, h in
                            Button { visor.mirar(h) } label: {
                                Text(h.texto).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3).padding(.horizontal, 4)
                                    .background(visor.hallado == h ? Color.accentColor.opacity(0.2) : .clear,
                                                in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
        .onAppear { enLaBusqueda = true }
    }

    private var panelCapas: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Capas").font(.headline)
                Spacer()
                Button("Todas") { visor.todasLasCapas(true) }.buttonStyle(.link)
                Button("Ninguna") { visor.todasLasCapas(false) }.buttonStyle(.link)
            }
            .padding(8)
            List(visor.capas, id: \.nombre) { c in
                Toggle(isOn: Binding(get: { c.encendida }, set: { visor.ponerCapa(c.nombre, encendida: $0) })) {
                    Text(c.nombre)
                        .foregroundStyle(c.enElPlano ? .primary : .secondary)
                        .lineLimit(1)
                        .help(c.enElPlano ? c.nombre : "\(c.nombre) (apagada en el plano)")
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// La barra del lienzo, su desplegable y el panel de estilo, encima del
/// plano mientras se anota (los de `EditorLienzoView`).
struct HerramientasDelPlano: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    /// Pegada al borde de arriba (la barra del visor flota fuera de la
    /// ventana; dentro se esconde sola), como en Windows.
    private let bajar: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let corte = BotonBarraLienzo.cortePara(ancho: geo.size.width - 2 * MedidasBarraLienzo.distanciaBorde)
            let filas: CGFloat = corte < BotonBarraLienzo.barra.count ? 2 : 1
            ZStack(alignment: .top) {
                if modelo.desplegado != nil {
                    Color.black.opacity(0.001)
                        .onTapGesture { modelo.desplegado = nil }
                }
                BarraHerramientasLienzo(modelo: modelo, corte: corte)
                    .padding(.top, MedidasBarraLienzo.distanciaBorde + bajar)
                    .padding(.horizontal, MedidasBarraLienzo.distanciaBorde)
                if modelo.hayElegidos || !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) {
                    PanelEstiloLienzo(modelo: modelo)
                        .padding(.leading, MedidasBarraLienzo.distanciaBorde)
                        .padding(.top, MedidasBarraLienzo.yPanel + bajar
                                 + (filas - 1) * (MedidasBarraLienzo.lado + MedidasBarraLienzo.relleno))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .overlayPreferenceValue(AnclasGruposLienzo.self) { anclas in
            MenuGrupoLienzo(modelo: modelo, anclas: anclas)
        }
    }
}

/// **Las letras del plano** (L, el boton «Aa» de Windows y Android): las
/// que pide y no estan, y las del usuario (`fuentes-shx`), que mandan sobre
/// las del sistema y las de PixPin. Con una nueva, el plano se vuelve a leer.
struct LetrasDelPlanoView: View {
    @ObservedObject var visor: VisorPlano
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Letras del plano").font(.title3.bold())
            if visor.faltan.isEmpty {
                Text("No falta ninguna letra que el plano nombre.").foregroundStyle(.secondary)
            } else {
                Text("Este plano pide letras que no están aquí; sus textos salen con otras parecidas y pueden no caber en sus recuadros:")
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(visor.faltan, id: \.self) { Text($0).font(.callout.monospaced()) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            Text("Las SHX suelen estar en la carpeta Fonts de AutoCAD o junto al plano que te mandaron; las TrueType, en las letras del sistema. Las que añadas aquí mandan sobre las del Mac y las de PixPin.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Añadir letras (SHX, TTF, OTF, TTC)…") { elegir() }
                Button("Quitar las mías (\(visor.letrasMias))") { visor.quitarLetras(); cerrar() }
                    .disabled(visor.letrasMias == 0)
                Spacer()
                Button("Listo") { cerrar() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func elegir() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = ["shx", "ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Elige las letras que pide el plano"
        guard p.runModal() == .OK else { return }
        visor.anadirLetras(p.urls)
        cerrar()
    }
}


/// **La barra del pin del plano** (la comun de los visores, `BarraVisor`):
/// el lapiz anota con el lienzo; mover, medir y marcos; ver entero, borrar,
/// buscar, letras, 3D, exportar, imprimir y capas.
struct BarraPlanoPin: View {
    @ObservedObject var visor: VisorPlano

    var body: some View {
        BarraVisor(nombre: visor.titulo, ext: (visor.ruta as NSString).pathExtension,
                   oscuro: visor.oscuro, alternarOscuro: { visor.alternarOscuro() },
                   fijar: { si in if si != visor.siempreEncima { visor.alternarEncima() } },
                   menu: [
                    EntradaMenuVisor("Buscar en los textos (⌘F)", "magnifyingglass") { visor.buscando.toggle() },
                    EntradaMenuVisor(visor.faltan.isEmpty ? "Letras del plano (L)" : "Faltan \(visor.faltan.count) letras (L)", "textformat") { visor.verLetras = true },
                    EntradaMenuVisor("Ver en 3D (3)", "cube") { visor.verEn3D() },
                    EntradaMenuVisor("Exportar: HTML, PDF, PNG, DXF… (⌘E)", "square.and.arrow.up", separar: true) { visor.exportar() },
                    EntradaMenuVisor("Imprimir (⌘P)", "printer") { visor.imprimir() },
                    EntradaMenuVisor("Borrar las cotas", "ruler", activa: !visor.anotado.cotas.isEmpty, destructivo: true, separar: true) { visor.borrarCotas() },
                    EntradaMenuVisor("Borrar los marcos", "rectangle.dashed", activa: !visor.anotado.marcos.isEmpty, destructivo: true) { visor.borrarMarcos() },
                   ]) {
            BotonFlotante(simbolo: "hand.raised", ayuda: "Mover", encendido: visor.modo == .mover) { visor.modo = .mover }
            BotonFlotante(simbolo: "ruler", ayuda: "Medir (M)", encendido: visor.modo == .medir) { visor.modo = .medir }
            if !visor.medida.isEmpty {
                Text(visor.medida)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color(white: 0.78))
                    .lineLimit(1)
                    .fixedSize()
            }
            BotonFlotante(simbolo: "viewfinder", ayuda: "Ver el plano entero (F)") { visor.encuadrar() }
            BotonFlotante(simbolo: "square.3.layers.3d", ayuda: "Capas", encendido: visor.verCapas) { visor.verCapas.toggle() }
        }
        .disabled(visor.datos == nil)
    }
}

/// Un panel que flota arriba a la derecha, bajo la barra del visor: las
/// capas del plano o los niveles del modelo, solo al pedirlos.
struct PanelFlotantePlano<Contenido: View>: View {
    var alto: CGFloat = 380
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        contenido()
            .frame(width: 240)
            .frame(height: alto)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.top, BarraFlotante.alto + 2 * BarraFlotante.separacion)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
