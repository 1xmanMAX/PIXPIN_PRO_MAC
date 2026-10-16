// Grabar una zona en GIF (modo `G` de la captura, P5 de Windows): la zona
// se elige con la captura y luego, en dos fases como en Windows, el marco
// azul con su barra (el ritmo y «Grabar», Intro) y el rojo grabando (el
// reloj y «Parar», Intro); Esc sale aunque el foco este en otra app. Se
// graba con ScreenCaptureKit a los fotogramas por segundo de `[gif]` (10
// de partida) con tope de 12 s, y se guarda en
// `capturas/captura-AAAAMMDD-HHMMSS.gif`, el nombre de Windows.
//
// Rendimiento (§4bis del plan):
// - ScreenCaptureKit reduce la zona en la propia captura (la tarjeta
//   grafica) a 1 pixel por punto con tope de lado: un GIF no es un video;
// - si la pantalla no cambia, ScreenCaptureKit no manda nada; y un
//   fotograma igual al anterior (misma firma) no se guarda: alarga el
//   retraso del anterior (deduplicar);
// - solo se guardan los fotogramas distintos, con tope de memoria; al
//   parar los escribe `CGImageDestination` (ImageIO), cada uno con su
//   propia paleta (ImageIO cuantiza cada fotograma) y su retraso;
// - el fichero se escribe en una carpeta temporal y se mueve al acabar:
//   nunca hay un GIF a medias en la galeria.

import AppKit
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Deduplicar fotogramas y medir su retraso, sin pantalla (lo prueban las
/// pruebas). Un fotograma con la misma firma que el anterior no se guarda:
/// el anterior dura mas.
public struct DeduplicadorGif {
    /// El retraso minimo que respetan los navegadores (2 centesimas).
    public static let minimoCentesimas = 2
    /// El maximo que cabe en el campo del GIF (16 bits).
    public static let maximoCentesimas = 65_535

    private var ultimaFirma: UInt64?
    private var ultimoTiempo: Double?
    /// Fotogramas distintos vistos.
    public private(set) var distintos = 0
    /// Fotogramas repetidos descartados.
    public private(set) var repetidos = 0

    public init() {}

    /// Lo que hay que hacer con un fotograma que llega en `tiempo`
    /// (segundos): `nil` si se descarta (igual al anterior); si es nuevo, el
    /// retraso en centesimas que le toca al ANTERIOR (o `nil` dentro si es
    /// el primero).
    public enum Paso: Equatable {
        case descartar
        case nuevo(retrasoDelAnterior: Int?)
    }

    public mutating func anadir(firma: UInt64, tiempo: Double) -> Paso {
        if let u = ultimaFirma, u == firma {
            repetidos += 1
            return .descartar
        }
        defer {
            ultimaFirma = firma
            ultimoTiempo = tiempo
            distintos += 1
        }
        guard let t0 = ultimoTiempo else { return .nuevo(retrasoDelAnterior: nil) }
        return .nuevo(retrasoDelAnterior: DeduplicadorGif.centesimas(desde: t0, hasta: tiempo))
    }

    /// Lo que dura el ultimo fotograma si se para en `tiempo`.
    public func retrasoFinal(hasta tiempo: Double) -> Int {
        guard let t0 = ultimoTiempo else { return DeduplicadorGif.minimoCentesimas }
        return DeduplicadorGif.centesimas(desde: t0, hasta: tiempo)
    }

    public static func centesimas(desde a: Double, hasta b: Double) -> Int {
        let c = Int(((b - a) * 100).rounded())
        return min(max(c, minimoCentesimas), maximoCentesimas)
    }

    /// La firma de un fotograma BGRA: FNV-1a de un pixel de cada `paso` en
    /// cada fila (y todas las filas). Barata (un 1/16 de los pixeles) y
    /// suficiente para saber si la pantalla cambio entre dos fotogramas.
    public static func firma(_ base: UnsafeRawPointer, ancho: Int, alto: Int, bytesPorFila: Int, paso: Int = 4) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        let paso = max(paso, 1)
        for y in 0 ..< max(alto, 0) {
            let fila = (base + y * bytesPorFila).assumingMemoryBound(to: UInt32.self)
            var x = 0
            while x < ancho {
                h ^= UInt64(fila[x])
                h = h &* 0x0000_0100_0000_01B3
                x += paso
            }
        }
        return h
    }

    /// El tamano de salida en pixeles: la zona a 1 pixel por punto, con el
    /// lado mayor a `ladoMaximo` como mucho, sin deformar y al menos 2x2.
    public static func tamSalida(puntos: CGSize, ladoMaximo: CGFloat = 960) -> (ancho: Int, alto: Int) {
        let w = max(puntos.width, 2)
        let h = max(puntos.height, 2)
        let f = min(1, ladoMaximo / max(w, h))
        return (max(Int((w * f).rounded(.down)), 2), max(Int((h * f).rounded(.down)), 2))
    }
}

@MainActor
public final class GrabadorGif: ObservableObject {
    public static let compartido = GrabadorGif()

    /// Fotogramas por segundo de partida (`RITMOS[1]` de Windows); el de
    /// cada sesion sale de `[gif] por_segundo` y se cambia en la barra.
    public nonisolated static let porSegundo: Int32 = 10
    /// Tope de reloj (`TIEMPO_MAXIMO` de Windows): mas largo es un video.
    public nonisolated static let segundosMaximos: Double = 12
    /// Tope de memoria de los fotogramas entregados a ImageIO.
    public nonisolated static let memoriaMaxima = 160 * 1024 * 1024

    @Published public private(set) var grabando = false
    /// Hay una sesion abierta (esperando con el marco azul, contando o
    /// grabando).
    @Published public private(set) var enSesion = false
    public var carpetaDeCapturas = carpetaDeDatos().appendingPathComponent("capturas", isDirectory: true)
    public var alGuardar: ((URL) -> Void)?

    private var flujo: SCStream?
    private var salida: SalidaGif?
    private var marco: MarcoDeZona?
    private var tope: Task<Void, Never>?
    private var vigiaEsc: Task<Void, Never>?
    private var desde = Date()
    private var zona: ZonaDeGrabacion?
    /// Los fotogramas por segundo de esta sesion.
    public private(set) var ritmo = Int(GrabadorGif.porSegundo)
    private var retardo = 0
    private var objetivos: [ObjetivoBoton] = []
    private weak var rotuloRitmo: NSTextField?
    private weak var rotuloReloj: NSTextField?

    public init() {}

    /// **La grabacion en dos fases** (`gif.rs` de Windows): primero el
    /// marco azul alrededor de la zona con su barra (el ritmo, «Grabar»);
    /// Intro (o el boton, o el atajo otra vez) empieza y vuelve a parar.
    /// Esc, que se mira aunque el foco este en la app que se graba, cierra
    /// sin grabar antes de empezar y para (guardando) despues.
    public func empezar(_ zona: ZonaDeGrabacion) async {
        guard !enSesion, !grabando, flujo == nil, !GrabadorPantalla.compartido.enSesion else { return }
        let ajustes = AjustesCaptura.actuales()
        ritmo = AjustesCaptura.ritmoGif(cercaDe: ajustes.gifPorSegundo)
        retardo = ajustes.gifRetardo
        self.zona = zona
        enSesion = true
        // El marco se mueve y se estira con el raton hasta grabar (D7).
        marco = MarcoDeZona.abrir(zona: zona, rojo: false, contenido: barraDeEspera(), ajustable: true)
        guard marco != nil else { return cerrarSesion() }
        marco?.alCambiar = { [weak self] in self?.zona = $0 }
        vigilarEsc()
    }

    /// El atajo de grabar GIF con la sesion abierta: empieza o para.
    public func alternar() {
        if grabando {
            Task { await parar() }
        } else if enSesion, flujo == nil {
            grabar()
        }
    }

    /// Cierra la sesion sin grabar (Esc antes de empezar, o la ✕).
    public func cancelar() {
        guard enSesion, !grabando else { return }
        CuentaAtras.cancelar()
        cerrarSesion()
    }

    private func cerrarSesion() {
        vigiaEsc?.cancel()
        vigiaEsc = nil
        marco?.cerrar()
        marco = nil
        objetivos = []
        zona = nil
        enSesion = false
    }

    /// Esc se mira cada 16 ms (como la cuenta atras): durante la grabacion
    /// el foco esta en la app que se graba, no en la barra.
    private func vigilarEsc() {
        vigiaEsc?.cancel()
        vigiaEsc = Task { @MainActor [weak self] in
            var antes = CGEventSource.keyState(.combinedSessionState, key: 53)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let ahora = CGEventSource.keyState(.combinedSessionState, key: 53)
                defer { antes = ahora }
                // Al bajar la tecla, no mientras sigue pulsada.
                guard ahora, !antes else { continue }
                if self.grabando {
                    await self.parar()
                } else {
                    self.cancelar()
                }
                return
            }
        }
    }

    // MARK: Las barras

    private func boton(_ titulo: String, tecla: String = "", azul: Bool = false,
                       accion: @escaping @MainActor () -> Void) -> NSButton {
        let objetivo = ObjetivoBoton { MainActor.assumeIsolated { accion() } }
        objetivos.append(objetivo)
        let b = NSButton(title: titulo, target: objetivo, action: #selector(ObjetivoBoton.pulsado))
        b.keyEquivalent = tecla
        b.refusesFirstResponder = true
        if azul { b.bezelColor = .controlAccentColor }
        return b
    }

    private func fila(_ vistas: [NSView]) -> NSView {
        let pila = NSStackView(views: vistas)
        pila.spacing = 8
        pila.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)
        return pila
    }

    /// Esperando: «GIF · 10 fps», − y +, Grabar (Intro) y ✕ (Esc).
    private func barraDeEspera() -> NSView {
        objetivos = []
        let rotulo = NSTextField(labelWithString: textoRitmo)
        rotulo.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        rotuloRitmo = rotulo
        let menos = boton("−") { [weak self] in self?.cambiarRitmo(-1) }
        let mas = boton("+") { [weak self] in self?.cambiarRitmo(1) }
        menos.toolTip = "Menos fotogramas por segundo"
        mas.toolTip = "Más fotogramas por segundo"
        let grabar = boton("Grabar ↩", tecla: "\r", azul: true) { [weak self] in self?.grabar() }
        let cerrar = boton("✕") { [weak self] in self?.cancelar() }
        cerrar.toolTip = "Cerrar sin grabar (Esc)"
        return fila([rotulo, menos, mas, grabar, cerrar])
    }

    private var textoRitmo: String { "GIF · \(ritmo) fps" }

    private func cambiarRitmo(_ paso: Int) {
        let ritmos = AjustesCaptura.ritmosGif
        let i = ritmos.firstIndex(of: ritmo) ?? 1
        ritmo = ritmos[min(max(i + paso, 0), ritmos.count - 1)]
        rotuloRitmo?.stringValue = textoRitmo
    }

    /// Grabando: el reloj y Parar (Intro).
    private func barraDeGrabacion() -> NSView {
        objetivos = []
        let reloj = NSTextField(labelWithString: "● 0:00")
        reloj.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        reloj.textColor = .systemRed
        rotuloReloj = reloj
        let parar = boton("Parar ↩", tecla: "\r") { [weak self] in Task { await self?.parar() } }
        parar.bezelColor = .systemRed
        return fila([reloj, parar])
    }

    /// «Grabar»: tras el retardo de los ajustes (con su cuenta atras),
    /// empieza.
    private func grabar() {
        guard enSesion, !grabando, flujo == nil, let zona else { return }
        if retardo > 0 {
            CuentaAtras.empezar(segundos: retardo) { [weak self] in
                Task { await self?.arrancar(zona) }
            }
        } else {
            Task { await arrancar(zona) }
        }
    }

    private func arrancar(_ zona: ZonaDeGrabacion) async {
        guard enSesion, !grabando, flujo == nil else { return }
        // La de ahora: el marco pudo moverse durante la cuenta atras.
        let zona = self.zona ?? zona
        marco?.fijar()
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
            let tam = DeduplicadorGif.tamSalida(puntos: rect.size)

            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = tam.ancho
            config.height = tam.alto
            config.scalesToFit = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(ritmo))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 3
            config.showsCursor = true

            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("pixpin-gif-\(UUID().uuidString).gif")
            let salida = SalidaGif(url: temporal)
            salida.alPararse = { [weak self] in Task { @MainActor in await self?.parar() } }
            let flujo = SCStream(filter: filtro, configuration: config, delegate: salida)
            try flujo.addStreamOutput(salida, type: .screen, sampleHandlerQueue: salida.cola)
            try await flujo.startCapture()
            self.flujo = flujo
            self.salida = salida
            desde = Date()
            grabando = true
            // El marco se pone rojo y la barra pasa a ser el reloj y Parar.
            marco?.ponerRojo(true)
            marco?.ponerContenido(barraDeGrabacion())
            tope = Task { [weak self] in
                let inicio = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self else { return }
                    let t = Date().timeIntervalSince(inicio)
                    let s = Int(t)
                    self.rotuloReloj?.stringValue = "● \(s / 60):" + String(format: "%02d", s % 60)
                    if t >= GrabadorGif.segundosMaximos {
                        await self.parar()
                        return
                    }
                }
            }
        } catch {
            cerrarSesion()
            PermisoCaptura.avisarDenegado(detalle: "No se pudo grabar el GIF: \(error.localizedDescription)")
        }
    }

    public func parar() async {
        guard let flujo, let salida else { return }
        self.flujo = nil
        self.salida = nil
        tope?.cancel()
        tope = nil
        grabando = false
        cerrarSesion()
        let empezo = desde
        try? await flujo.stopCapture()
        guard let hecho = await salida.terminar() else {
            NSSound.beep()
            return
        }
        let carpeta = carpetaDeCapturas
        let destino = await Task.detached(priority: .utility) { () -> URL? in
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                let destino = GeometriaCaptura.rutaNueva(en: carpeta, fecha: empezo)
                    .deletingPathExtension().appendingPathExtension("gif")
                try FileManager.default.moveItem(at: hecho, to: destino)
                return destino
            } catch {
                try? FileManager.default.removeItem(at: hecho)
                return nil
            }
        }.value
        if let destino { alGuardar?(destino) } else { NSSound.beep() }
    }
}

/// Recibe los fotogramas en su cola, descarta los repetidos y entrega los
/// demas a ImageIO con su retraso. Todo lo suyo pasa en `cola`.
final class SalidaGif: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let cola = DispatchQueue(label: "PixPin grabar GIF", qos: .userInitiated)
    var alPararse: (() -> Void)?

    private let url: URL
    private var dedup = DeduplicadorGif()
    /// Los fotogramas distintos con su retraso (centesimas), en orden. El
    /// ultimo espera a saber cuanto dura (`nil`).
    private var fotogramas: [(CGImage, Int?)] = []
    private var bytes = 0
    private var cerrado = false

    init(url: URL) {
        self.url = url
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .screen, !cerrado, muestra.isValid, SalidaGrabacion.esFotogramaCompleto(muestra),
              let px = CMSampleBufferGetImageBuffer(muestra) else { return }
        let t = muestra.presentationTimeStamp.seconds
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let ancho = CVPixelBufferGetWidth(px)
        let alto = CVPixelBufferGetHeight(px)
        let porFila = CVPixelBufferGetBytesPerRow(px)
        let firma = DeduplicadorGif.firma(UnsafeRawPointer(base), ancho: ancho, alto: alto, bytesPorFila: porFila)
        switch dedup.anadir(firma: firma, tiempo: t) {
        case .descartar:
            return
        case let .nuevo(retraso):
            if let retraso, let i = fotogramas.indices.last { fotogramas[i].1 = retraso }
        }
        // Copia propia de los pixeles: el bufer vuelve al grupo de
        // ScreenCaptureKit en cuanto se suelta.
        let tam = porFila * alto
        guard bytes + tam <= GrabadorGif.memoriaMaxima else {
            cerrado = true
            alPararse?()
            return
        }
        let datos = Data(bytes: base, count: tam)
        guard let proveedor = CGDataProvider(data: datos as CFData) else { return }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let imagen = CGImage(width: ancho, height: alto, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: porFila,
                                   space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: info, provider: proveedor, decode: nil, shouldInterpolate: false,
                                   intent: .defaultIntent) else { return }
        fotogramas.append((imagen, nil))
        bytes += tam
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        alPararse?()
    }

    /// Escribe el GIF con ImageIO (cada fotograma con su paleta y su
    /// retraso) y suelta los fotogramas. `nil` si no hubo nada.
    func terminar() async -> URL? {
        await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            cola.async {
                self.cerrado = true
                let ahora = CMClockGetTime(CMClockGetHostTimeClock()).seconds
                let lista = self.fotogramas
                self.fotogramas = []
                let ultimoRetraso = self.dedup.retrasoFinal(hasta: ahora)
                let bien = SalidaGif.escribirGif(lista.map { ($0.0, $0.1 ?? ultimoRetraso) }, en: self.url)
                if !bien { try? FileManager.default.removeItem(at: self.url) }
                c.resume(returning: bien ? self.url : nil)
            }
        }
    }

    /// Un GIF que se repite sin fin, con paleta propia por fotograma.
    static func escribirGif(_ fotogramas: [(CGImage, Int)], en url: URL) -> Bool {
        guard !fotogramas.isEmpty else { return false }
        try? FileManager.default.removeItem(at: url)
        guard let destino = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                            fotogramas.count, nil) else { return false }
        let fichero: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0,
                                            kCGImagePropertyGIFHasGlobalColorMap: false],
        ]
        CGImageDestinationSetProperties(destino, fichero as CFDictionary)
        for (imagen, centesimas) in fotogramas {
            let segundos = Double(centesimas) / 100
            let propiedades: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: segundos,
                                                kCGImagePropertyGIFUnclampedDelayTime: segundos],
            ]
            CGImageDestinationAddImage(destino, imagen, propiedades as CFDictionary)
        }
        return CGImageDestinationFinalize(destino)
    }
}
