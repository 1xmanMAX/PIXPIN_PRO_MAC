// Grabar la pantalla (o una zona) a MP4: ScreenCaptureKit (`SCStream`)
// entrega los fotogramas ya en YUV 4:2:0, la forma que come el codificador,
// y `AVAssetWriter` los codifica en H.264 con el codificador POR HARDWARE
// (VideoToolbox). Es lo que en Windows hace `pixpin-record` con Media
// Foundation; aqui sin copiar ni convertir un solo pixel en la CPU.
//
// **En dos fases** (D7, `grabador.rs` de Windows): elegida la zona (o la
// ventana, o la pantalla) con la captura, NO se graba aun. Sale el marco
// azul alrededor, que se mueve y se estira con el raton, y su barra: el
// microfono, el sonido del Mac, «Grabar ↩» y ✕. «Grabar» espera la cuenta
// atras de `[gif] retardo_s` (`pixpinmax.toml`, la misma de Windows) y
// empieza: el marco se pone rojo y la barra pasa a ser el reloj, «Pausar»
// y «Parar ↩». Esc, que se mira aunque el foco este en la app que se
// graba, cierra sin grabar antes de empezar y para despues; el atajo
// (⌃⌥R) empieza y para. La logica (fases, pausas, marco) es pura, en
// `SesionGrabacion.swift`.
//
// - 30 fotogramas por segundo (`minimumFrameInterval`); si la pantalla no
//   cambia, ScreenCaptureKit no manda nada y no se codifica nada.
// - El sonido del sistema (sin el de PixPin) y el microfono son opcionales,
//   cada uno en su pista AAC; el editor los mezcla al guardar.
// - En pausa lo que llega se tira y lo de despues se adelanta lo que duro
//   (`RelojPausas`): el video sale sin el hueco.
// - Se escribe en una carpeta temporal y al parar se abre el editor
//   (`EditorGrabacion`) para verla, recortarla y decidir; el editor la deja
//   en `capturas/` con el nombre de Windows (`captura-AAAAMMDD-HHMMSS.mp4`):
//   nunca hay un MP4 a medias en la galeria.
// - H.264 y no HEVC: lo abren Windows y Android sin extensiones. Por eso una
//   zona mayor que 4096x2304 pixeles se reduce en la propia captura.

import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

@MainActor
public final class GrabadorPantalla: ObservableObject {
    public static let compartido = GrabadorPantalla()

    /// Grabando (o en pausa): hay un video en marcha.
    @Published public private(set) var grabando = false
    /// Hay una sesion abierta (el marco puesto, contando o grabando).
    @Published public private(set) var enSesion = false
    @Published public private(set) var enPausa = false
    /// Cuando empezo la grabacion en marcha.
    @Published public private(set) var desde: Date?

    /// Donde se guardan las grabaciones: la galeria (`capturas/`).
    public var carpetaDeCapturas = carpetaDeDatos().appendingPathComponent("capturas", isDirectory: true)
    /// Avisa de una grabacion guardada (para ensenarla).
    public var alGuardar: ((URL) -> Void)?

    private static let claveSonido = "grabar.sonido"
    private static let claveMicrofono = "grabar.microfono"
    /// Grabar tambien el sonido del sistema (apagado de fabrica).
    public var conSonido: Bool {
        get { UserDefaults.standard.bool(forKey: GrabadorPantalla.claveSonido) }
        set {
            UserDefaults.standard.set(newValue, forKey: GrabadorPantalla.claveSonido)
            objectWillChange.send()
        }
    }

    /// Grabar tambien el microfono (apagado de fabrica).
    public var conMicrofono: Bool {
        get { UserDefaults.standard.bool(forKey: GrabadorPantalla.claveMicrofono) }
        set {
            UserDefaults.standard.set(newValue, forKey: GrabadorPantalla.claveMicrofono)
            objectWillChange.send()
        }
    }

    private var maquina = MaquinaGrabacion()
    private var zona: ZonaDeGrabacion?
    private var marco: MarcoDeZona?
    private var flujo: SCStream?
    private var salida: SalidaGrabacion?
    private var vigiaEsc: Task<Void, Never>?
    private var tic: Task<Void, Never>?
    /// Las pausas en el reloj del sistema, para el reloj de la barra (la
    /// salida lleva las suyas para las muestras).
    private var pausas = RelojPausas()
    private var inicio = CMTime.zero
    private var objetivos: [ObjetivoBoton] = []
    private weak var rotuloTam: NSTextField?
    private weak var rotuloReloj: NSTextField?

    public init() {}

    private static var ahora: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }
    private var retardo: Int { AjustesCaptura.actuales().gifRetardo }

    /// **La primera fase**: el marco azul alrededor de `zona` con su
    /// barra. Aun no graba. Con una sesion abierta, no hace nada.
    public func empezar(_ zona: ZonaDeGrabacion) async {
        guard !GrabadorGif.compartido.enSesion, maquina.abrir() else { return }
        self.zona = zona
        enSesion = true
        marco = MarcoDeZona.abrir(zona: zona, rojo: false, contenido: barraDeEspera(), ajustable: true)
        guard let marco else { return cerrarSesion() }
        marco.alCambiar = { [weak self] z in
            self?.zona = z
            self?.rotuloTam?.stringValue = GrabadorPantalla.textoTam(z)
        }
        vigilarEsc()
    }

    /// El atajo de grabar con la sesion abierta: empieza (o se salta la
    /// cuenta atras) y luego para.
    public func alternar() {
        hacer(maquina.atajo(retardo: retardo))
    }

    /// Pausar o seguir.
    public func alternarPausa() {
        hacer(maquina.alternarPausa())
    }

    /// Cierra la sesion sin grabar (✕, o Esc antes de empezar).
    public func cancelar() {
        guard maquina.fase?.conVideo == false else { return }
        hacer(maquina.esc())
    }

    /// Para, cierra el MP4 y abre el editor.
    public func parar() async {
        guard maquina.parar() == .parar else { return }
        await cerrarVideo()
    }

    private func hacer(_ accion: AccionSesion) {
        switch accion {
        case .nada:
            break
        case let .contar(n):
            CuentaAtras.empezar(segundos: n) { [weak self] in
                guard let self else { return }
                self.hacer(self.maquina.cuentaAcabada())
            }
        case .arrancar:
            CuentaAtras.cancelar()
            Task { await arrancar() }
        case .pausar:
            let t = GrabadorPantalla.ahora
            pausas.pausar(t)
            salida?.pausar(t)
            enPausa = true
            marco?.ponerColor(NSColor.systemRed.withAlphaComponent(0.45))
            marco?.ponerContenido(barraDeGrabacion())
            actualizarReloj()
        case .reanudar:
            let t = GrabadorPantalla.ahora
            pausas.reanudar(t)
            salida?.reanudar(t)
            enPausa = false
            marco?.ponerRojo(true)
            marco?.ponerContenido(barraDeGrabacion())
            actualizarReloj()
        case .parar:
            Task { await cerrarVideo() }
        case .cerrar:
            CuentaAtras.cancelar()
            cerrarSesion()
        }
    }

    private func cerrarSesion() {
        vigiaEsc?.cancel()
        vigiaEsc = nil
        tic?.cancel()
        tic = nil
        marco?.cerrar()
        marco = nil
        objetivos = []
        zona = nil
        maquina.cerrada()
        enSesion = false
        enPausa = false
    }

    /// Esc se mira cada 16 ms (como la cuenta atras y el GIF): grabando,
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
                self.hacer(self.maquina.esc())
            }
        }
    }

    // MARK: Las barras

    private func boton(_ titulo: String, tecla: String = "", color: NSColor? = nil,
                       accion: @escaping @MainActor () -> Void) -> NSButton {
        let objetivo = ObjetivoBoton { MainActor.assumeIsolated { accion() } }
        objetivos.append(objetivo)
        let b = NSButton(title: titulo, target: objetivo, action: #selector(ObjetivoBoton.pulsado))
        b.keyEquivalent = tecla
        b.refusesFirstResponder = true
        if let color { b.bezelColor = color }
        return b
    }

    private func casilla(_ titulo: String, _ activa: Bool, accion: @escaping @MainActor (Bool) -> Void) -> NSButton {
        var b: NSButton!
        let objetivo = ObjetivoBoton { MainActor.assumeIsolated { accion(b.state == .on) } }
        objetivos.append(objetivo)
        b = NSButton(checkboxWithTitle: titulo, target: objetivo, action: #selector(ObjetivoBoton.pulsado))
        b.state = activa ? .on : .off
        b.refusesFirstResponder = true
        return b
    }

    private func fila(_ vistas: [NSView]) -> NSView {
        let pila = NSStackView(views: vistas)
        pila.spacing = 8
        pila.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)
        return pila
    }

    nonisolated static func textoTam(_ z: ZonaDeGrabacion) -> String {
        let r = z.rect.standardized
        return "Vídeo · \(Int(r.width.rounded()))×\(Int(r.height.rounded()))"
    }

    /// Esperando: el tamano, microfono, sonido del Mac, Grabar (↩) y ✕.
    private func barraDeEspera() -> NSView {
        objetivos = []
        let rotulo = NSTextField(labelWithString: zona.map(GrabadorPantalla.textoTam) ?? "Vídeo")
        rotulo.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        rotulo.toolTip = "Arrastra el borde para mover o estirar la zona"
        rotuloTam = rotulo
        let micro = casilla("Micrófono", conMicrofono) { [weak self] in self?.conMicrofono = $0 }
        let sistema = casilla("Sonido del Mac", conSonido) { [weak self] in self?.conSonido = $0 }
        let grabar = boton("Grabar ↩", tecla: "\r", color: .controlAccentColor) { [weak self] in
            guard let self else { return }
            self.hacer(self.maquina.grabar(retardo: self.retardo))
        }
        let cerrar = boton("✕") { [weak self] in self?.cancelar() }
        cerrar.toolTip = "Cerrar sin grabar (Esc)"
        return fila([rotulo, micro, sistema, grabar, cerrar])
    }

    /// Grabando: el reloj, Pausar/Seguir y Parar (↩).
    private func barraDeGrabacion() -> NSView {
        objetivos = []
        let reloj = NSTextField(labelWithString: "")
        reloj.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        reloj.textColor = enPausa ? .secondaryLabelColor : .systemRed
        rotuloReloj = reloj
        let pausa = boton(enPausa ? "Seguir" : "Pausar", tecla: " ") { [weak self] in self?.alternarPausa() }
        pausa.toolTip = enPausa ? "Seguir grabando" : "Pausar: lo de la pausa no sale en el vídeo"
        let parar = boton("Parar ↩", tecla: "\r", color: .systemRed) { [weak self] in
            Task { await self?.parar() }
        }
        return fila([reloj, pausa, parar])
    }

    private func actualizarReloj() {
        let t = pausas.activo(desde: inicio, hasta: GrabadorPantalla.ahora).seconds
        rotuloReloj?.stringValue = (enPausa ? "❚❚ " : "● ") + MarcoAjustable.reloj(t)
    }

    // MARK: Grabar

    /// **La segunda fase**: pide el flujo de la zona de ahora y empieza.
    private func arrancar() async {
        guard maquina.fase == .arrancando, flujo == nil, let zona else { return }
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let pantalla = contenido.displays.first(where: { $0.displayID == zona.pantalla }) else {
                throw ErrorGrabacion.sinPantalla
            }
            let yo = ProcessInfo.processInfo.processIdentifier
            let propias = contenido.applications.filter { $0.processID == yo }
            let filtro = SCContentFilter(display: pantalla, excludingApplications: propias, exceptingWindows: [])

            let limites = CGRect(x: 0, y: 0, width: pantalla.width, height: pantalla.height)
            let rect = zona.rect.standardized.intersection(limites)
            guard !rect.isNull, rect.width >= 2, rect.height >= 2 else { throw ErrorGrabacion.zonaVacia }
            let tam = GeometriaGrabacion.tamSalida(puntos: rect.size, escala: zona.escala)
            let sonido = conSonido
            let micro = conMicrofono

            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = tam.ancho
            config.height = tam.alto
            config.scalesToFit = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: GeometriaGrabacion.porSegundo)
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.queueDepth = 6
            config.showsCursor = true
            config.capturesAudio = sonido
            if sonido {
                config.sampleRate = 48_000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = true
            }
            // El microfono por defecto del Mac (pide su permiso la primera
            // vez).
            config.captureMicrophone = micro

            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("pixpin-grabacion-\(UUID().uuidString).mp4")
            let salida = try SalidaGrabacion(url: temporal, ancho: tam.ancho, alto: tam.alto,
                                             conSonido: sonido, conMicrofono: micro)
            salida.alPararse = { [weak self] in
                Task { @MainActor in await self?.parar() }
            }
            let flujo = SCStream(filter: filtro, configuration: config, delegate: salida)
            try flujo.addStreamOutput(salida, type: .screen, sampleHandlerQueue: salida.cola)
            if sonido {
                try flujo.addStreamOutput(salida, type: .audio, sampleHandlerQueue: salida.cola)
            }
            if micro {
                try flujo.addStreamOutput(salida, type: .microphone, sampleHandlerQueue: salida.cola)
            }
            try await flujo.startCapture()
            // Esc o ✕ mientras se pedia el flujo: no se graba.
            guard maquina.fase == .arrancando else {
                try? await flujo.stopCapture()
                _ = await salida.terminar()
                return
            }
            self.flujo = flujo
            self.salida = salida
            maquina.arrancado()
            pausas = RelojPausas()
            inicio = GrabadorPantalla.ahora
            desde = Date()
            grabando = true
            enPausa = false
            // El marco se fija y se pone rojo; la barra pasa a ser el reloj.
            marco?.fijar()
            marco?.ponerRojo(true)
            marco?.ponerContenido(barraDeGrabacion())
            actualizarReloj()
            tic = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.actualizarReloj()
                }
            }
        } catch {
            cerrarSesion()
            PermisoCaptura.avisarDenegado(detalle: "No se pudo grabar la pantalla: \(error.localizedDescription)")
        }
    }

    /// Para el flujo, cierra el MP4 y lo lleva al editor.
    private func cerrarVideo() async {
        guard let flujo, let salida else { return }
        self.flujo = nil
        self.salida = nil
        let empezo = desde ?? Date()
        grabando = false
        desde = nil
        cerrarSesion()
        try? await flujo.stopCapture()
        guard let hecho = await salida.terminar() else {
            NSSound.beep()
            return
        }
        EditorGrabacion.abrir(video: hecho, fecha: empezo, carpeta: carpetaDeCapturas) { [weak self] url in
            self?.alGuardar?(url)
        }
    }
}

enum ErrorGrabacion: LocalizedError {
    case sinPantalla
    case zonaVacia
    case escritor(String)

    var errorDescription: String? {
        switch self {
        case .sinPantalla: return "la pantalla ya no esta"
        case .zonaVacia: return "la zona elegida esta vacia"
        case let .escritor(d): return d
        }
    }
}

/// Recibe los fotogramas y el sonido de ScreenCaptureKit en su cola y los
/// pasa al `AVAssetWriter`. Todo lo suyo pasa en `cola`.
final class SalidaGrabacion: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let cola = DispatchQueue(label: "PixPin grabar pantalla", qos: .userInitiated)
    /// El flujo se paro solo (la pantalla se desconecto, se quito el
    /// permiso...): quien graba tiene que cerrar.
    var alPararse: (() -> Void)?

    private let url: URL
    private let escritor: AVAssetWriter
    private let video: AVAssetWriterInput
    private let sonido: AVAssetWriterInput?
    private let micro: AVAssetWriterInput?
    private var empezado = false
    private var cerrado = false
    /// Las pausas (reloj del sistema, el de las muestras).
    private var pausas = RelojPausas()
    /// El ultimo fotograma escrito y cuando llego (reloj del sistema): al
    /// parar, el video dura hasta el momento de parar aunque la pantalla
    /// llevase un rato quieta.
    private var ultimo = CMTime.invalid
    private var ultimoReloj = CMTime.invalid

    init(url: URL, ancho: Int, alto: Int, conSonido: Bool, conMicrofono: Bool = false) throws {
        try? FileManager.default.removeItem(at: url)
        let escritor = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // El indice delante: el video se puede empezar a ver antes de
        // tenerlo entero (al mandarlo al movil o abrirlo desde la red).
        escritor.shouldOptimizeForNetworkUse = true

        let compresion: [String: Any] = [
            AVVideoAverageBitRateKey: GeometriaGrabacion.bitsPorSegundo(ancho: ancho, alto: alto),
            AVVideoExpectedSourceFrameRateKey: Int(GeometriaGrabacion.porSegundo),
            AVVideoMaxKeyFrameIntervalKey: Int(GeometriaGrabacion.porSegundo) * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let ajustes: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ancho,
            AVVideoHeightKey: alto,
            AVVideoCompressionPropertiesKey: compresion,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            // El codificador de la tarjeta (VideoToolbox), no uno en software.
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ],
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: ajustes)
        video.expectsMediaDataInRealTime = true
        guard escritor.canAdd(video) else { throw ErrorGrabacion.escritor("el MP4 no admite el video") }
        escritor.add(video)

        // Cada sonido en su pista AAC (el del Mac en estereo, el microfono
        // en mono): el editor los mezcla al guardar.
        func pista(canales: Int, bits: Int) -> AVAssetWriterInput? {
            let s = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: canales,
                AVEncoderBitRateKey: bits,
            ])
            s.expectsMediaDataInRealTime = true
            guard escritor.canAdd(s) else { return nil }
            escritor.add(s)
            return s
        }
        self.url = url
        self.escritor = escritor
        self.video = video
        self.sonido = conSonido ? pista(canales: 2, bits: 128_000) : nil
        self.micro = conMicrofono ? pista(canales: 1, bits: 96_000) : nil
        super.init()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard !cerrado, muestra.isValid else { return }
        if tipo == .screen, !SalidaGrabacion.esFotogramaCompleto(muestra) { return }
        // Lo de una pausa se tira; lo de despues, sin el hueco.
        let original = muestra.presentationTimeStamp
        guard let t = pausas.ajustar(original),
              let ajustada = SalidaGrabacion.retemporizar(muestra, menos: CMTimeSubtract(original, t))
        else { return }
        switch tipo {
        case .screen:
            if !empezado {
                guard escritor.startWriting() else {
                    cerrado = true
                    alPararse?()
                    return
                }
                escritor.startSession(atSourceTime: t)
                empezado = true
            }
            if video.isReadyForMoreMediaData, video.append(ajustada) {
                ultimo = t
                ultimoReloj = CMClockGetTime(CMClockGetHostTimeClock())
            }
        case .audio:
            guard empezado, let sonido, sonido.isReadyForMoreMediaData else { return }
            sonido.append(ajustada)
        case .microphone:
            guard empezado, let micro, micro.isReadyForMoreMediaData else { return }
            micro.append(ajustada)
        @unknown default:
            return
        }
    }

    /// La misma muestra `d` antes (el hueco de las pausas). Sin hueco, la
    /// misma.
    static func retemporizar(_ m: CMSampleBuffer, menos d: CMTime) -> CMSampleBuffer? {
        guard d != .zero else { return m }
        var n: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(m, entryCount: 0, arrayToFill: nil, entriesNeededOut: &n) == noErr,
              n > 0 else { return nil }
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: n)
        guard CMSampleBufferGetSampleTimingInfoArray(m, entryCount: n, arrayToFill: &info, entriesNeededOut: &n) == noErr
        else { return nil }
        for i in info.indices {
            info[i].presentationTimeStamp = CMTimeSubtract(info[i].presentationTimeStamp, d)
            if info[i].decodeTimeStamp.isValid {
                info[i].decodeTimeStamp = CMTimeSubtract(info[i].decodeTimeStamp, d)
            }
        }
        var nueva: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: m, sampleTimingEntryCount: n,
                                              sampleTimingArray: &info, sampleBufferOut: &nueva)
        return nueva
    }

    // MARK: Pausar

    func pausar(_ t: CMTime) {
        cola.async { self.pausas.pausar(t) }
    }

    func reanudar(_ t: CMTime) {
        cola.async { self.pausas.reanudar(t) }
    }

    /// Solo los fotogramas con imagen nueva: ScreenCaptureKit tambien manda
    /// avisos de «nada cambio» sin pixeles.
    static func esFotogramaCompleto(_ muestra: CMSampleBuffer) -> Bool {
        guard let adjuntos = CMSampleBufferGetSampleAttachmentsArray(muestra, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let crudo = adjuntos.first?[.status] as? Int,
            let estado = SCFrameStatus(rawValue: crudo) else { return false }
        return estado == .complete
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        alPararse?()
    }

    // MARK: Cerrar

    /// Cierra el MP4. Devuelve su ruta, o `nil` si no llego a escribirse
    /// nada (o fallo).
    func terminar() async -> URL? {
        await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            cola.async {
                self.cerrado = true
                guard self.empezado, self.escritor.status == .writing, self.ultimo.isValid else {
                    if self.escritor.status == .writing { self.escritor.cancelWriting() }
                    try? FileManager.default.removeItem(at: self.url)
                    c.resume(returning: nil)
                    return
                }
                self.video.markAsFinished()
                self.sonido?.markAsFinished()
                self.micro?.markAsFinished()
                // Hasta ahora (o hasta la pausa en curso), no hasta el
                // ultimo fotograma, y sin contar las pausas de en medio (con
                // tope de una hora por si el reloj dijera algo raro).
                let ahora = self.pausas.pausadoDesde ?? CMClockGetTime(CMClockGetHostTimeClock())
                let quieto = self.pausas.activo(desde: self.ultimoReloj, hasta: ahora)
                let extra = CMTimeMinimum(CMTimeMaximum(quieto, .zero), CMTime(value: 3600, timescale: 1))
                self.escritor.endSession(atSourceTime: CMTimeAdd(self.ultimo, extra))
                self.escritor.finishWriting {
                    let bien = self.escritor.status == .completed
                    if !bien { try? FileManager.default.removeItem(at: self.url) }
                    c.resume(returning: bien ? self.url : nil)
                }
            }
        }
    }
}
