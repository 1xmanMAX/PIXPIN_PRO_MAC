// El visor 3D (`ventana3d.rs` + `gpu3d.rs` de Windows con Metal): IFC,
// Revit, LandXML y puntos de Civil 3D, y un DWG/DXF visto en 3D.
//
// - Girar arrastrando (alrededor del punto tocado), mover con dos dedos o
//   con Mayusculas/el boton derecho, acercar pellizcando o con la rueda
//   (hacia lo que hay bajo el puntero). La camara es la de Windows
//   (`camara*` de Rust: `Orbita`).
// - Clic: que elemento es (un rayo de la camara contra los triangulos, en
//   Rust), resaltado en azul, con lo que mide; «Aislar» deja solo ese.
// - Niveles y categorias se encienden y apagan: solo se rehacen los indices.
// - Caja de seccion con sus tapas, como Revit.
// - El terreno de Civil 3D ya trae el color por cota y las curvas de nivel.
//
// Como el visor de planos, la vista esta parada y pinta solo al cambiar.
//
// Tambien ensena los croquis 3D del movil (`croquis3d.rs` de Windows, B9):
// llegan del chat ya hechos triangulos (`Nucleo.abrirCroquis`) y traen su
// fondo, su tema y desde donde se miran (`ExtrasCroquis`). Solo se ven. Sus
// vistas guardadas en el movil van con las teclas 1 a 9 (E2).
//
// Las teclas, las de Windows (`ventana3d.rs`): ⎋ (suelta lo aislado o lo
// elegido; si no, cierra), F o Inicio todo, B fondo claro u oscuro, C caja
// de seccion, I aislar, L el panel, A aristas, P planta, T siempre encima,
// 1–9 las vistas guardadas, + y −, las flechas giran y ⌘E exporta la vista
// (una foto de lo que se ve, con el original).

import AppKit
import Metal
import MetalKit
import PixPinCore
import SwiftUI

/// El modelo en la tarjeta: los vertices (una vez) y los indices de lo que
/// se ve (se rehacen al filtrar).
public final class ModeloEnTarjeta: @unchecked Sendable {
    public let modelo: Modelo3dApple
    public let resumen: ResumenModelo3d
    /// Lo que pide un croquis del movil; `nil` en un modelo de un fichero.
    public let croquis: ExtrasCroquis?
    let vertices: MTLBuffer?
    private(set) var indices: [MTLBuffer?] = [nil, nil, nil, nil, nil]
    private(set) var cuantos: [Int] = [0, 0, 0, 0, 0]
    let motor: MotorMetal

    enum Clase: Int { case opacos, transparentes, aristas, lineas, puntos }

    init(modelo: Modelo3dApple, motor: MotorMetal) {
        self.modelo = modelo
        self.motor = motor
        resumen = modelo.resumen()
        croquis = modelo.extrasCroquis()
        vertices = motor.bufer(modelo.vertices(), nombre: "vertices 3d")
        poner(modelo.indices())
    }

    /// Sube unos indices nuevos (al filtrar).
    func poner(_ i: Indices3d) {
        let todos = [i.opacos, i.transparentes, i.aristas, i.lineas, i.puntos]
        indices = todos.map { motor.bufer($0, nombre: "indices 3d") }
        cuantos = todos.map { $0.count / 4 }
    }

    func bufer(_ c: Clase) -> (MTLBuffer, Int)? {
        guard let b = indices[c.rawValue], cuantos[c.rawValue] > 0 else { return nil }
        return (b, cuantos[c.rawValue])
    }

    /// Lee y sube (bloquea: desde una `Task` aparte).
    public static func cargar(ruta: String, motor: MotorMetal) throws -> ModeloEnTarjeta {
        ModeloEnTarjeta(modelo: try Modelo3dApple.abrir(ruta: ruta), motor: motor)
    }

    /// Lo mismo con quien lo lee (un croquis del chat).
    static func cargar(_ abrir: () throws -> Modelo3dApple, motor: MotorMetal) throws -> ModeloEnTarjeta {
        ModeloEnTarjeta(modelo: try abrir(), motor: motor)
    }
}

/// **El estado del visor 3D**: el modelo, el filtro, lo elegido y la caja de
/// seccion (en fracciones de la caja del modelo, de 0 a 1).
@MainActor
public final class VisorModelo3D: ObservableObject {
    @Published public private(set) var datos: ModeloEnTarjeta?
    @Published public private(set) var error: String?
    @Published public private(set) var niveles: [Nivel3d] = []
    @Published public private(set) var categorias: [Categoria3d] = []
    @Published public private(set) var filtro = Filtro3d(nivelesOcultos: [], tiposOcultos: [], aislado: nil)
    @Published public private(set) var elegido: InfoElemento3d?
    @Published public var aristas = true { didSet { vista?.repintar() } }
    @Published public var conCorte = false { didSet { vista?.repintar() } }
    /// La caja de seccion: minimo y maximo de cada eje, de 0 a 1.
    @Published public var corte: [Double] = [0, 0, 0, 1, 1, 1] { didSet { vista?.repintar() } }
    /// El fondo elegido con B (`nil`: el del croquis o el del sistema).
    @Published public private(set) var claro: Bool?
    /// El panel (niveles, categorias, lo elegido): L.
    @Published public var verPanel = false
    /// Siempre encima (T).
    @Published public private(set) var siempreEncima = false
    /// Las vistas guardadas del croquis (1 a 9).
    @Published public private(set) var vistas: [String] = []
    /// El fichero que va como «Original» al exportar (el modelo, o el
    /// `.croquis.gz` del chat).
    public var original: URL?
    public let titulo: String
    public let ruta: String
    /// Quien lee el modelo (fuera del hilo principal).
    private let abrir: @Sendable () throws -> Modelo3dApple
    weak var vista: VistaModeloMetal?

    /// Con `nucleo`, el modelo leido queda en su cache (`cache/bim`, como
    /// Windows): la segunda vez se abre casi al momento.
    public init(ruta: String, titulo: String, nucleo: Nucleo? = nil) {
        self.ruta = ruta
        self.titulo = titulo
        if let nucleo {
            abrir = { try nucleo.abrirModelo(ruta: ruta) }
        } else {
            abrir = { try Modelo3dApple.abrir(ruta: ruta) }
        }
    }

    /// **Un croquis 3D del movil**: `abrir` lo lee del chat
    /// (`Nucleo.abrirCroquis`); `clave` lo distingue de otro.
    public init(clave: String, titulo: String, abrir: @escaping @Sendable () throws -> Modelo3dApple) {
        ruta = clave
        self.titulo = titulo
        self.abrir = abrir
    }

    // MARK: Ordenes (las teclas de Windows)

    /// B: el fondo claro u oscuro.
    public func alternarTema(actual: Bool) {
        claro = !actual
        vista?.repintar()
    }

    /// T: la ventana siempre encima (o no).
    public func alternarEncima() {
        siempreEncima.toggle()
        vista?.window?.level = siempreEncima ? .floating : .normal
    }

    /// ⎋: suelta lo aislado; si no, lo elegido; si no, cierra.
    public func escape() {
        if filtro.aislado != nil {
            aislar()
        } else if elegido != nil {
            elegir(nil)
        } else {
            VentanaLisa.escapar(vista?.window)
        }
    }

    /// 1–9: la vista guardada `i` (desde 0).
    public func irAVista(_ i: Int) { vista?.irAVista(i) }

    /// ⌘E: **exporta lo que se ve** (una foto de la ventana, como Windows,
    /// que pinta con la tarjeta) con el original.
    public func exportar() {
        guard datos != nil, let v = vista else { return NSSound.beep() }
        let titulo = self.titulo, original = self.original
        v.foto { img in
            let p = PreparadoCompartir(titulo: titulo)
            if let img { p.anadir(PiezasCompartir.foto(img, clave: "vista", nombre: titulo)) }
            if let original { PrepararCompartir.anadirOriginales(p, [original]) }
            guard img != nil || original != nil else { return NSSound.beep() }
            HojaCompartir.abrir(.preparado(p), almacen: nil)
        }
    }

    public func cargar() {
        guard datos == nil, error == nil else { return }
        guard let motor = MotorMetal.compartido else {
            error = "Este Mac no tiene una tarjeta gráfica con Metal."
            return
        }
        let abrir = self.abrir
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<ModeloEnTarjeta, Error> in
                Result { try ModeloEnTarjeta.cargar(abrir, motor: motor) }
            }.value
            switch hecho {
            case let .success(d):
                self.datos = d
                self.niveles = d.modelo.niveles()
                self.categorias = d.modelo.categorias()
                self.vistas = d.modelo.vistasGuardadas()
                self.vista?.alLlegarElModelo()
            case let .failure(e):
                self.error = "No se pudo abrir el modelo: \(e)"
            }
        }
    }

    /// La caja de seccion en coordenadas del modelo (o `nil` sin corte).
    var cajaDeCorte: Caja3d? {
        guard conCorte, let c = datos?.resumen.caja else { return nil }
        func eje(_ a: Float, _ b: Float, _ t: Double) -> Float { a + (b - a) * Float(t) }
        return Caja3d(x0: eje(c.x0, c.x1, min(corte[0], corte[3])), y0: eje(c.y0, c.y1, min(corte[1], corte[4])),
                      z0: eje(c.z0, c.z1, min(corte[2], corte[5])), x1: eje(c.x0, c.x1, max(corte[0], corte[3])),
                      y1: eje(c.y0, c.y1, max(corte[1], corte[4])), z1: eje(c.z0, c.z1, max(corte[2], corte[5])))
    }

    // MARK: Filtros

    public func verNivel(_ i: UInt32, _ ver: Bool) {
        var f = filtro
        f.nivelesOcultos.removeAll { $0 == i }
        if !ver { f.nivelesOcultos.append(i) }
        filtrar(f)
    }

    public func verCategoria(_ tipo: String, _ ver: Bool) {
        var f = filtro
        f.tiposOcultos.removeAll { $0 == tipo }
        if !ver { f.tiposOcultos.append(tipo) }
        filtrar(f)
    }

    public func aislar() {
        var f = filtro
        f.aislado = f.aislado == nil ? elegido?.id : nil
        filtrar(f)
    }

    public func verTodo() { filtrar(Filtro3d(nivelesOcultos: [], tiposOcultos: [], aislado: nil)) }

    /// Rehace los indices fuera del hilo principal; los vertices se quedan.
    private func filtrar(_ f: Filtro3d) {
        guard let d = datos else { return }
        filtro = f
        Task {
            let i = await Task.detached(priority: .userInitiated) { d.modelo.visibles(filtro: f) }.value
            guard self.filtro == f else { return } // ya se pidio otro
            d.poner(i)
            self.vista?.repintar()
        }
    }

    // MARK: Elegir

    func elegir(_ e: Eleccion3d?) {
        elegido = e.flatMap { datos?.modelo.elemento(id: $0.elemento) }
        vista?.repintar()
    }

    public func encuadrar() { vista?.encuadrar() }
}

// MARK: - La vista de Metal

public final class VistaModeloMetal: MTKView {
    let visor: VisorModelo3D
    private let motor: MotorMetal
    private let muestras: Int
    private(set) var camara = Camara3d(objetivo: Punto3d(x: 0, y: 0, z: 0), rumbo: -0.8, altura: 0.5, dist: 10)
    private var radio = 10.0
    private var encuadrado = false
    /// El arrastre: donde empezo, la camara de entonces, el pivote y si giraba.
    private var arrastre: (p: CGPoint, camara: Camara3d, pivote: Punto3d, girar: Bool, movido: Bool)?
    /// El ultimo punto tocado por la rueda: se reusa mientras se sigue girando.
    private var rueda: (cuando: Date, p: CGPoint, fijo: Punto3d)?

    init(visor: VisorModelo3D, motor: MotorMetal) {
        self.visor = visor
        self.motor = motor
        muestras = motor.muestras
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), device: motor.dispositivo)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        clearDepth = 1
        sampleCount = muestras
        isPaused = true
        enableSetNeedsDisplay = true
        // Para leer lo pintado al exportar la vista.
        framebufferOnly = false
        visor.vista = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override public var acceptsFirstResponder: Bool { true }

    func repintar() { needsDisplay = true }

    private var escala: Double {
        bounds.width > 0 ? Double(drawableSize.width) / Double(bounds.width) : 2
    }

    private var ancho: UInt32 { UInt32(max(drawableSize.width, 1)) }
    private var alto: UInt32 { UInt32(max(drawableSize.height, 1)) }
    /// Claro u oscuro: el del croquis si lo dice (su fondo deja ver su
    /// tinta); si no, el del sistema.
    var claro: Bool {
        visor.claro ?? visor.datos?.croquis?.claro ?? (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua)
    }

    /// Lo que se pidio fotografiar (⌘E): se lee tras el siguiente pintado.
    private var pedidoDeFoto: ((CGImage?) -> Void)?

    /// **La foto de lo que se ve** (pinta una vez y lee el dibujable).
    func foto(_ listo: @escaping @MainActor (CGImage?) -> Void) {
        pedidoDeFoto = { img in MainActor.assumeIsolated { listo(img) } }
        draw()
    }

    /// La vista guardada `i` del croquis, como la mira el movil.
    func irAVista(_ i: Int) {
        guard i >= 0, let d = visor.datos,
              let c = d.modelo.camaraDeVista(indice: UInt32(i), ancho: ancho, alto: alto, escala: escala) else {
            return NSSound.beep()
        }
        camara = c
        encuadrado = true
        repintar()
    }

    /// P: la planta (desde arriba), encuadrada.
    func planta() {
        guard let d = visor.datos else { return }
        let caja = visor.cajaDeCorte ?? d.croquis?.encuadre ?? d.resumen.cajaUtil
        camara = camaraEncuadrarDesde(caja: caja, ancho: ancho, alto: alto, rumbo: -Double.pi / 2, altura: 1.5697)
        encuadrado = true
        repintar()
    }

    func alLlegarElModelo() {
        guard let d = visor.datos else { return }
        let c = d.resumen.caja
        radio = max(Double(hypot(hypot(c.x1 - c.x0, c.y1 - c.y0), c.z1 - c.z0)) / 2, 1e-3)
        encuadrado = false
        encuadrar()
    }

    func encuadrar() {
        guard let d = visor.datos, drawableSize.width > 0 else { return }
        if let c = d.croquis, let caja = c.encuadre {
            // Un croquis: lo dibujado (sin el suelo), desde donde lo mira
            // el movil de fabrica.
            camara = camaraEncuadrarDesde(caja: caja, ancho: ancho, alto: alto, rumbo: c.rumbo, altura: c.altura)
        } else {
            camara = camaraEncuadrar(caja: d.resumen.cajaUtil, ancho: ancho, alto: alto)
        }
        encuadrado = true
        repintar()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !encuadrado { encuadrar() }
        repintar()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repintar()
    }

    // MARK: Pintar

    /// Lo que el sombreador 3D sabe de la vista (`Vista3d`, 176 bytes).
    static func vista(_ c: Camara3d, ancho: UInt32, alto: UInt32, radio: Double, corte: Caja3d?,
                      elegido: UInt32?, aislado: UInt32?, claro: Bool, radioPuntos: Float) -> PalabrasUniforme {
        var u = PalabrasUniforme()
        for x in camaraMatriz(camara: c, ancho: ancho, alto: alto, radio: radio) { u.f(x) }
        let l = luzDeCamara(c)
        u.f4(l.x, l.y, l.z, 0)
        let o = camaraOjo(camara: c)
        u.f4(Float(o.x), Float(o.y), Float(o.z), 1)
        u.f4(corte == nil ? 0 : 1, 0, radioPuntos, 0)
        u.f4(corte?.x0 ?? 0, corte?.y0 ?? 0, corte?.z0 ?? 0, 0)
        u.f4(corte?.x1 ?? 0, corte?.y1 ?? 0, corte?.z1 ?? 0, 0)
        u.u(elegido.map { $0 + 1 } ?? 0)
        u.f(Float(claro ? 1 : 0))
        u.f(Float(ancho))
        u.f(Float(alto))
        u.u(aislado.map { $0 + 1 } ?? 0)
        u.f(Float(0))
        u.f(Float(0))
        u.f(Float(0))
        return u
    }

    private func tuberia(_ v: String, _ f: String, mezcla: Bool) throws -> MTLRenderPipelineState {
        try motor.tuberia(fuente: SombreadoresCAD.modelo, claveFuente: "modelo", vertice: v, fragmento: f,
                          color: colorPixelFormat, profundidad: depthStencilPixelFormat, muestras: muestras, mezcla: mezcla)
    }

    override public func draw(_ dirtyRect: NSRect) {
        let claro = self.claro
        if let f = visor.datos?.croquis?.fondo {
            clearColor = MTLClearColor(red: Double(f.r), green: Double(f.g), blue: Double(f.b), alpha: 1)
        } else {
            clearColor = claro ? MTLClearColor(red: 0.955, green: 0.958, blue: 0.965, alpha: 1)
                : MTLClearColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
        }
        guard let pasada = currentRenderPassDescriptor, let dibujable = currentDrawable,
              let cb = motor.cola.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pasada) else { return }
        if let d = visor.datos, let vb = d.vertices {
            do {
                try pintar(d, vb, enc, claro: claro)
            } catch {
                NSLog("PixPin 3D: \(error)")
            }
        }
        enc.endEncoding()
        if let pedido = pedidoDeFoto {
            pedidoDeFoto = nil
            leerFoto(dibujable.texture, cb, pedido)
        }
        cb.present(dibujable)
        cb.commit()
    }

    /// Copia lo pintado a la memoria y, al terminar la tarjeta, lo da como
    /// imagen (BGRA, el formato de la vista).
    private func leerFoto(_ t: MTLTexture, _ cb: MTLCommandBuffer, _ listo: @escaping (CGImage?) -> Void) {
        let w = t.width, h = t.height, fila = w * 4
        guard let bufer = motor.dispositivo.makeBuffer(length: fila * h, options: .storageModeShared),
              let blit = cb.makeBlitCommandEncoder() else { return listo(nil) }
        blit.copy(from: t, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1), to: bufer, destinationOffset: 0,
                  destinationBytesPerRow: fila, destinationBytesPerImage: fila * h)
        blit.endEncoding()
        cb.addCompletedHandler { _ in
            let datos = Data(bytes: bufer.contents(), count: fila * h)
            let img = CGDataProvider(data: datos as CFData).flatMap {
                CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: fila,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                            | CGImageAlphaInfo.noneSkipFirst.rawValue),
                        provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
            DispatchQueue.main.async { listo(img) }
        }
    }

    private func pintar(_ d: ModeloEnTarjeta, _ vb: MTLBuffer, _ enc: MTLRenderCommandEncoder, claro: Bool) throws {
        let corte = visor.cajaDeCorte
        let u = VistaModeloMetal.vista(camara, ancho: ancho, alto: alto, radio: radio, corte: corte,
                                       elegido: visor.elegido?.id, aislado: visor.filtro.aislado, claro: claro,
                                       radioPuntos: Float(4.5 * escala))
        let largo = u.bytes
        u.palabras.withUnsafeBytes { b in
            if let base = b.baseAddress {
                enc.setVertexBytes(base, length: largo, index: 1)
                enc.setFragmentBytes(base, length: largo, index: 0)
            }
        }
        enc.setCullMode(.none)
        enc.setVertexBuffer(vb, offset: 0, index: 0)
        let escribe = motor.profundidad(escribe: true), lee = motor.profundidad(escribe: false)
        func dibujar(_ c: ModeloEnTarjeta.Clase, _ tipo: MTLPrimitiveType) {
            guard let par = d.bufer(c) else { return }
            let (ib, n) = par
            enc.drawIndexedPrimitives(type: tipo, indexCount: n, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
        }
        // 1. Lo opaco, un poco hacia atras para que las aristas queden encima.
        enc.setRenderPipelineState(try tuberia("vs_3d", "ps_3d", mezcla: false))
        enc.setDepthStencilState(escribe)
        enc.setDepthBias(800, slopeScale: 1.5, clamp: 0)
        dibujar(.opacos, .triangle)
        // 2. Las aristas, encima.
        enc.setDepthBias(0, slopeScale: 0, clamp: 0)
        if visor.aristas {
            enc.setRenderPipelineState(try tuberia("vs_3d", "ps_arista", mezcla: true))
            enc.setDepthStencilState(lee)
            dibujar(.aristas, .line)
        }
        // 2a. Las tapas de la caja de seccion.
        if corte != nil {
            enc.setRenderPipelineState(try tuberia("vs_3d", "ps_tapa", mezcla: false))
            enc.setDepthStencilState(escribe)
            enc.setDepthBias(800, slopeScale: 1.5, clamp: 0)
            dibujar(.opacos, .triangle)
            enc.setDepthBias(0, slopeScale: 0, clamp: 0)
        }
        // 2b. Las rayas sueltas (curvas de nivel, ejes) y los puntos.
        enc.setRenderPipelineState(try tuberia("vs_3d", "ps_linea", mezcla: true))
        enc.setDepthStencilState(escribe)
        dibujar(.lineas, .line)
        enc.setRenderPipelineState(try tuberia("vs_punto", "ps_punto", mezcla: false))
        dibujar(.puntos, .triangle)
        // 3. Los vidrios, al final y sin tapar.
        enc.setRenderPipelineState(try tuberia("vs_3d", "ps_vidrio", mezcla: true))
        enc.setDepthStencilState(lee)
        dibujar(.transparentes, .triangle)
    }

    // MARK: Gestos

    private func punto(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    /// El pixel (desde arriba a la izquierda, como `camara_rayo`).
    private func pixel(_ p: CGPoint) -> (Double, Double) {
        (Double(p.x) * escala, Double(bounds.height - p.y) * escala)
    }

    /// Lo que hay bajo un punto de la vista.
    private func elegir(_ p: CGPoint) -> Eleccion3d? {
        guard let d = visor.datos else { return nil }
        let (x, y) = pixel(p)
        let r = camaraRayo(camara: camara, x: x, y: y, ancho: ancho, alto: alto)
        return d.modelo.elegir(origen: camaraOjo(camara: camara), direccion: r, filtro: visor.filtro, corte: visor.cajaDeCorte)
    }

    /// El punto bajo el puntero o, sin nada, el del rayo a la distancia del objetivo.
    private func puntoBajo(_ p: CGPoint) -> Punto3d {
        if let e = elegir(p) { return e.punto }
        let (x, y) = pixel(p)
        let r = camaraRayo(camara: camara, x: x, y: y, ancho: ancho, alto: alto)
        let o = camaraOjo(camara: camara)
        return Punto3d(x: o.x + r.x * camara.dist, y: o.y + r.y * camara.dist, z: o.z + r.z * camara.dist)
    }

    private func zoom(_ factor: Double, en p: CGPoint) {
        let fijo: Punto3d
        if let r = rueda, Date().timeIntervalSince(r.cuando) < 0.4, abs(r.p.x - p.x) + abs(r.p.y - p.y) < 4 {
            fijo = r.fijo
        } else {
            fijo = puntoBajo(p)
        }
        rueda = (Date(), p, fijo)
        camara = camaraZoom(camara: camara, factor: factor, fijo: fijo)
        repintar()
    }

    override public func scrollWheel(with e: NSEvent) {
        let p = punto(e)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) && !e.modifierFlags.contains(.control) {
            // Dos dedos: mover (el modelo sigue a los dedos).
            camara = camaraMover(camara: camara, dx: Double(e.scrollingDeltaX) * escala,
                                 dy: Double(e.scrollingDeltaY) * escala, alto: alto)
            repintar()
        } else {
            let paso = e.hasPreciseScrollingDeltas ? Double(e.scrollingDeltaY) / 40 : Double(e.scrollingDeltaY)
            zoom(pow(1.2, -paso), en: p)
        }
    }

    override public func magnify(with e: NSEvent) {
        zoom(1 / max(1 + Double(e.magnification), 0.1), en: punto(e))
    }

    override public func smartMagnify(with e: NSEvent) { encuadrar() }

    override public func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = punto(e)
        let girar = !e.modifierFlags.contains(.shift)
        arrastre = (p, camara, girar ? puntoBajo(p) : camara.objetivo, girar, false)
    }

    override public func rightMouseDown(with e: NSEvent) {
        arrastre = (punto(e), camara, camara.objetivo, false, false)
    }

    private func arrastrar(_ e: NSEvent) {
        guard var a = arrastre else { return }
        let p = punto(e)
        let dx = Double(p.x - a.p.x) * escala, dy = -Double(p.y - a.p.y) * escala
        if !a.movido && abs(dx) + abs(dy) <= 3 { return }
        a.movido = true
        arrastre = a
        if a.girar {
            // Media vuelta por el lado corto de la ventana, sea del tamano que sea.
            let k = Double.pi / Double(max(min(ancho, alto), 1))
            camara = camaraGirar(camara: a.camara, dRumbo: -dx * k, dAltura: dy * k, pivote: a.pivote)
        } else {
            camara = camaraMover(camara: a.camara, dx: dx, dy: dy, alto: alto)
        }
        repintar()
    }

    override public func mouseDragged(with e: NSEvent) { arrastrar(e) }
    override public func rightMouseDragged(with e: NSEvent) { arrastrar(e) }
    override public func rightMouseUp(with e: NSEvent) { arrastre = nil }

    override public func mouseUp(with e: NSEvent) {
        defer { arrastre = nil }
        // Un clic sin arrastrar: que es.
        if let a = arrastre, !a.movido { visor.elegir(elegir(punto(e))) }
    }

    override public func keyDown(with e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let letra = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == .command, letra == "e" { return visor.exportar() }
        guard mods.isEmpty || mods == .shift else { return super.keyDown(with: e) }
        switch e.keyCode {
        case 53: visor.escape()
        case 115: encuadrar() // Inicio
        case 123: girarTeclado(0.26, 0)
        case 124: girarTeclado(-0.26, 0)
        case 126: girarTeclado(0, 0.2)
        case 125: girarTeclado(0, -0.2)
        default:
            switch letra {
            case "f": encuadrar()
            case "b": visor.alternarTema(actual: claro)
            case "c": visor.conCorte.toggle()
            case "i": if visor.elegido != nil || visor.filtro.aislado != nil { visor.aislar() }
            case "l": visor.verPanel.toggle()
            case "a": visor.aristas.toggle()
            case "p": planta()
            case "t": visor.alternarEncima()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": irAVista(Int(letra)! - 1)
            case "+", "=": camara = camaraZoom(camara: camara, factor: 1 / 1.4, fijo: camara.objetivo); repintar()
            case "-": camara = camaraZoom(camara: camara, factor: 1.4, fijo: camara.objetivo); repintar()
            default: super.keyDown(with: e)
            }
        }
    }

    private func girarTeclado(_ r: Double, _ a: Double) {
        camara = camaraGirar(camara: camara, dRumbo: r, dAltura: a, pivote: camara.objetivo)
        repintar()
    }
}

// MARK: - SwiftUI

struct LienzoMetalModelo: NSViewRepresentable {
    let visor: VisorModelo3D
    let motor: MotorMetal

    func makeNSView(context _: Context) -> VistaModeloMetal { VistaModeloMetal(visor: visor, motor: motor) }
    func updateNSView(_ v: VistaModeloMetal, context _: Context) { v.repintar() }
}

/// **La ventana de un modelo 3D**: la barra, el modelo y el panel (niveles,
/// categorias, caja de seccion y lo elegido).
public struct VentanaModeloView: View {
    @ObservedObject var visor: VisorModelo3D

    public init(visor: VisorModelo3D) { self.visor = visor }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                contenido
                // Niveles y categorias, un menu flotante al pulsar su boton.
                if visor.verPanel && visor.datos != nil {
                    PanelFlotantePlano { panel.listStyle(.plain).scrollContentBackground(.hidden) }
                }
            }
        }
    }

    @ViewBuilder private var contenido: some View {
        if let error = visor.error {
            ContentUnavailableView("No se puede ver el modelo", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let motor = MotorMetal.compartido {
            ZStack {
                LienzoMetalModelo(visor: visor, motor: motor)
                if visor.datos == nil { ProgressView("Leyendo el modelo…") }
            }
        } else {
            ContentUnavailableView("Sin Metal", systemImage: "cpu", description: Text("Este Mac no tiene una tarjeta gráfica con Metal."))
        }
    }

    private var panel: some View {
        List {
            if let e = visor.elegido {
                Section("Elegido") {
                    LabeledContent("Categoría", value: e.categoria)
                    if !e.nombre.isEmpty { LabeledContent("Nombre", value: e.nombre) }
                    if let n = e.nivel { LabeledContent("Nivel", value: n) }
                    LabeledContent("Clase", value: e.tipo)
                    if e.volumen > 0 {
                        LabeledContent(e.cerrado ? "Volumen" : "Volumen (aprox.)", value: String(format: "%.3f", e.volumen))
                    }
                    if e.planta > 0 { LabeledContent("Área en planta", value: String(format: "%.3f", e.planta)) }
                    if e.alzado > 0 { LabeledContent("Área en alzado", value: String(format: "%.3f", e.alzado)) }
                    LabeledContent("Superficie", value: String(format: "%.3f", e.superficie))
                }
            }
            if visor.conCorte {
                Section("Caja de sección") {
                    ForEach(0 ..< 3, id: \.self) { k in
                        let eje = ["X", "Y", "Z"][k]
                        Slider(value: $visor.corte[k], in: 0 ... 1) { Text("\(eje) desde") }
                        Slider(value: $visor.corte[k + 3], in: 0 ... 1) { Text("\(eje) hasta") }
                    }
                }
            }
            if !visor.niveles.isEmpty {
                Section("Niveles") {
                    ForEach(visor.niveles, id: \.indice) { n in
                        Toggle(isOn: Binding(get: { !visor.filtro.nivelesOcultos.contains(n.indice) },
                                             set: { visor.verNivel(n.indice, $0) })) {
                            Text("\(n.nombre) · \(String(format: "%.2f", n.cota)) m").lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Section("Categorías") {
                ForEach(visor.categorias, id: \.tipo) { c in
                    Toggle(isOn: Binding(get: { !visor.filtro.tiposOcultos.contains(c.tipo) },
                                         set: { visor.verCategoria(c.tipo, $0) })) {
                        Text("\(c.nombre) (\(c.elementos))").lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .listStyle(.sidebar)
    }
}


/// **La barra del pin del modelo 3D** (la comun, `BarraVisor`).
struct BarraModeloPin: View {
    @ObservedObject var visor: VisorModelo3D

    var body: some View {
        let claro = visor.claro ?? visor.datos?.croquis?.claro ?? false
        BarraVisor(nombre: visor.titulo, ext: visor.original?.pathExtension ?? "ifc",
                   oscuro: !claro, alternarOscuro: { visor.vista.map { visor.alternarTema(actual: $0.claro) } },
                   fijar: { si in if si != visor.siempreEncima { visor.alternarEncima() } }) {
            BotonFlotante(simbolo: "viewfinder", ayuda: "Ver el modelo entero (F)") { visor.encuadrar() }
            BotonFlotante(simbolo: "cube.transparent", ayuda: "Aristas (A)", encendido: visor.aristas) { visor.aristas.toggle() }
            BotonFlotante(simbolo: "square.split.bottomrightquarter", ayuda: "Caja de sección (C)",
                          encendido: visor.conCorte) { visor.conCorte.toggle() }
            BotonFlotante(simbolo: "square.grid.3x3.topleft.filled", ayuda: "Planta: desde arriba (P)") { visor.vista?.planta() }
            BotonFlotante(simbolo: visor.filtro.aislado == nil ? "scope" : "eye",
                          ayuda: visor.filtro.aislado == nil ? "Aislar lo elegido" : "Ver todo",
                          encendido: visor.filtro.aislado != nil) { visor.aislar() }
            if !visor.vistas.isEmpty {
                Menu {
                    ForEach(Array(visor.vistas.prefix(9).enumerated()), id: \.offset) { i, n in
                        Button("\(i + 1)  \(n)") { visor.irAVista(i) }
                    }
                } label: { Image(systemName: "camera.viewfinder") }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .frame(width: 28)
                    .help("Las vistas guardadas en el móvil (1–9)")
            }
            BotonFlotante(simbolo: "square.and.arrow.up", ayuda: "Exportar lo que se ve, con el original (⌘E)") { visor.exportar() }
            BotonFlotante(simbolo: "sidebar.right", ayuda: "Niveles y categorías (L)", encendido: visor.verPanel) { visor.verPanel.toggle() }
        }
        .disabled(visor.datos == nil)
    }
}
