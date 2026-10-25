// **El video de la reunion con el motor nuevo** (Windows bea497b, 32973c1
// y cdad692, `pixpin-motor-video` y `grabar_clase/video.rs`): con «Vídeo de
// esta pantalla», ademas de la nota se graba la pantalla donde esta la
// ventanita a un MP4 H.264 + AAC con el **mismo sonido** que la nota.
//
// Lo de Windows traducido a lo del Mac:
//
// - **La GPU hasta el codificador**: ScreenCaptureKit da la pantalla ya
//   encogida por la tarjeta al tamano del perfil, en YUV 4:2:0 BT.709
//   sobre IOSurface, y esa misma superficie va al H.264 de VideoToolbox por
//   `AVAssetWriter`: la imagen no baja nunca a la CPU.
// - **El perfil** («Ligero», «Normal», «Nítido») y **la cadena de caidas**
//   (`caminosDelVideo`): la grafica (High, sin B, un fotograma clave cada
//   dos segundos al ritmo maximo); si no abre, a 1080p y 720p; luego el
//   procesador; y por ultimo el modo sencillo. `codificador` dice cual
//   quedo, y la barra lo dice al empezar.
// - **Ritmo variable** (`RitmoDelVideo`): ScreenCaptureKit solo da un
//   fotograma cuando la pantalla cambia. Se escribe en cuanto llega (si
//   paso el minimo del perfil) y, con la pantalla quieta, se repite el
//   ultimo cada segundo. Un fotograma de retraso: el repetido que aun
//   espera cede su sitio al de verdad que llega pegado.
// - **Un solo reloj, el del sonido**: cada bloque de la nota ancla el
//   reloj y cada fotograma va en su ancla mas lo que paso (como mucho un
//   cuarto de segundo por delante). En pausa no se escribe nada; el video
//   acaba donde acaba el sonido. La pista de sonido nunca se pisa.
// - **Si algo sale mal, sigue**: si la pantalla se va (un monitor que se
//   desconecta, el Mac que se duerme) se repite la ultima imagen y se
//   intenta abrir otra vez cada tres segundos (la misma pantalla o, si ya
//   no esta, la principal), tres vueltas cada diez minutos como mucho. Si
//   el codificador no acepta nada en diez segundos, o la pantalla no
//   vuelve, el video se corta y lo grabado hasta ahi vale; la nota sigue.
// - **Colas con tope**: si el codificador se atrasa se salta un fotograma,
//   nunca sonido (el que no entra espera, con tope).

import AppKit
import AVFoundation
import CoreMedia
import PixPinCore
import ScreenCaptureKit
import VideoToolbox

final class VideoDeClase: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Las horas del motor van en 100 ns.
    static let escala: CMTimeScale = 10_000_000
    /// Bloques de sonido que pueden esperar al codificador: diez segundos.
    static let topeDeSonido = 500

    let url: URL
    let cola = DispatchQueue(label: "PixPin video de la clase", qos: .userInitiated)
    /// El video dejo de grabarse (la nota sigue). Se llama una vez, desde
    /// `cola`.
    var alRomperse: (() -> Void)?
    /// Con que se codifica (la grafica, el procesador o el modo sencillo).
    let codificador: CodificadorVideo

    private var pantalla: CGDirectDisplayID
    private let camino: CaminoDelVideo
    private let muestreo: Int
    private let escritor: AVAssetWriter
    private let entradaVideo: AVAssetWriterInput
    private let adaptador: AVAssetWriterInputPixelBufferAdaptor
    private let entradaAudio: AVAssetWriterInput
    private let formatoAudio: CMAudioFormatDescription
    private let ritmo: RitmoDelVideo
    private var flujo: SCStream?
    /// La barra, que no sale en el video.
    private var fuera: CGWindowID?

    // En `cola`.
    /// El ultimo fotograma nuevo de la pantalla, aun sin escribir, y su hora.
    private var retenido: (imagen: CVPixelBuffer, hora: Int64)?
    /// La ultima imagen dada al video (la que se repite).
    private var ultima: CVPixelBuffer?
    /// El que espera al siguiente para entrar (un fotograma de retraso).
    private var pendiente: (imagen: CVPixelBuffer, instante: Int64, repetido: Bool)?
    private var negro: CVPixelBuffer?
    private var escritos = 0
    private var ultimoInstante: Int64 = -1
    private var sonidoEnEspera: [CMSampleBuffer] = []
    private var temporizador: DispatchSourceTimer?
    private var empezado = false
    private var roto = false
    private var cerrado = false
    /// La pantalla se fue y se esta intentando volver a abrir.
    private var caida = false
    private var reabriendo = false

    /// Prepara el MP4 en `url` para la pantalla `pantalla`, de `pixeles` de
    /// ancho y alto, con `perfil` y sonido mono a `muestreo`: prueba cada
    /// camino de la cadena hasta que uno abre.
    init(url: URL, pantalla: CGDirectDisplayID, pixeles: (ancho: Int, alto: Int), muestreo: Int,
         perfil: PerfilVideo) throws {
        guard let formato = VideoDeClase.formatoMono(muestreo: muestreo) else {
            throw ErrorGrabacion.escritor("el sonido del video no tiene formato")
        }
        let caminos = caminosDelVideo(perfil: perfil, anchoPantalla: UInt32(max(pixeles.ancho, 2)),
                                      altoPantalla: UInt32(max(pixeles.alto, 2)),
                                      hayHardware: VideoDeClase.hayH264PorHardware())
        var abierto: (camino: CaminoDelVideo, escritor: AVAssetWriter, video: AVAssetWriterInput,
                      audio: AVAssetWriterInput)?
        for c in caminos {
            if let e = VideoDeClase.abrir(url, camino: c, muestreo: muestreo, formato: formato) {
                abierto = (c, e.escritor, e.video, e.audio)
                break
            }
        }
        guard let abierto else { throw ErrorGrabacion.escritor("ningun codificador de video arranco") }
        self.url = url
        self.pantalla = pantalla
        self.muestreo = muestreo
        camino = abierto.camino
        codificador = abierto.camino.codificador
        escritor = abierto.escritor
        entradaVideo = abierto.video
        adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: abierto.video,
                                                         sourcePixelBufferAttributes: nil)
        entradaAudio = abierto.audio
        formatoAudio = formato
        ritmo = RitmoDelVideo.nuevo(muestreo: UInt32(muestreo), porSegundo: abierto.camino.porSegundo,
                                    ahora: VideoDeClase.ahora())
        super.init()
    }

    /// **Un camino de la cadena**: el MP4 con su H.264 y su AAC, ya
    /// escribiendo; `nil` si este codificador no abre.
    private static func abrir(_ url: URL, camino c: CaminoDelVideo, muestreo: Int,
                              formato: CMAudioFormatDescription)
        -> (escritor: AVAssetWriter, video: AVAssetWriterInput, audio: AVAssetWriterInput)? {
        try? FileManager.default.removeItem(at: url)
        guard let escritor = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        // El pico de Windows (PeakConstrainedVBR) no tiene clave en
        // `AVAssetWriter`: va la media, que es lo que manda el peso.
        let compresion: [String: Any] = [
            AVVideoAverageBitRateKey: Int(c.bitsMedia),
            AVVideoExpectedSourceFrameRateKey: Int(c.porSegundo),
            AVVideoMaxKeyFrameIntervalKey: Int(c.grupo),
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
        ]
        let especificacion: [String: Any] = c.codificador == .hardware
            ? [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
            : [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(c.ancho),
            AVVideoHeightKey: Int(c.alto),
            AVVideoCompressionPropertiesKey: compresion,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoEncoderSpecificationKey: especificacion,
        ])
        video.expectsMediaDataInRealTime = true
        guard escritor.canAdd(video) else { return nil }
        escritor.add(video)
        // El sonido: AAC mono a 96 kbps, el de la nota de voz.
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: muestreo,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Int(c.bitsAudio),
        ], sourceFormatHint: formato)
        audio.expectsMediaDataInRealTime = true
        guard escritor.canAdd(audio) else { return nil }
        escritor.add(audio)
        guard escritor.startWriting() else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        escritor.startSession(atSourceTime: .zero)
        return (escritor, video, audio)
    }

    /// Si el Mac tiene un H.264 por hardware (casi todos: Apple silicon y
    /// los Intel con T2 o Quick Sync).
    static func hayH264PorHardware() -> Bool {
        var lista: CFArray?
        guard VTCopyVideoEncoderList(nil, &lista) == noErr,
              let codificadores = (lista as NSArray?) as? [[String: Any]] else { return false }
        return codificadores.contains { c in
            (c[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_H264
                && (c[kVTVideoEncoderList_IsHardwareAccelerated as String] as? NSNumber)?.boolValue == true
        }
    }

    // MARK: El reloj

    /// Un instante en 100 ns.
    static func unidades(_ t: CMTime) -> Int64 {
        CMTimeConvertScale(t, timescale: escala, method: .roundTowardNegativeInfinity).value
    }

    /// La hora del sistema (la de los fotogramas de ScreenCaptureKit) en
    /// 100 ns.
    static func ahora() -> Int64 {
        unidades(CMClockGetTime(CMClockGetHostTimeClock()))
    }

    /// El sonido mono `Float32` del bloque de la nota que se acaba de
    /// escribir, que empieza en la muestra `posicion` (lo llama
    /// `AudioDeClase` desde su cola).
    func sonido(_ v: [Float], posicion: UInt64) {
        cola.async { self.ponerSonido(v, posicion) }
    }

    /// Pausa o sigue el video, a la vez que la nota.
    func pausar(_ si: Bool) {
        cola.async {
            self.ritmo.pausar(pausa: si, ahora: VideoDeClase.ahora())
            // Al seguir, la pantalla de antes de la pausa ya no vale.
            if si { self.retenido = nil }
        }
    }

    // MARK: Mirar la pantalla

    /// Empieza a mirar la pantalla, sin la ventana `fuera` (la barra). Si
    /// no se puede, el video queda roto y la nota sigue.
    func empezar(sin fuera: CGWindowID?) async throws {
        self.fuera = fuera
        cola.async { self.arrancarTemporizador() }
        do {
            try await abrirPantalla()
            // Tirado o terminado mientras se abria: no puede quedar la
            // pantalla grabandose sin nadie que la pare.
            let tarde = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                cola.async {
                    if !self.cerrado { self.empezado = true }
                    c.resume(returning: self.cerrado)
                }
            }
            if tarde { await pararPantalla() }
        } catch {
            cola.async { self.romper() }
            throw error
        }
    }

    /// Abre la pantalla de antes (o la principal, si ya no esta) a las
    /// medidas del video, que no cambian.
    private func abrirPantalla() async throws {
        let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let elegida = pantallaDelVideo(antes: pantalla, disponibles: contenido.displays.map(\.displayID),
                                       principal: CGMainDisplayID())
        guard let d = contenido.displays.first(where: { $0.displayID == elegida }) ?? contenido.displays.first else {
            throw ErrorGrabacion.sinPantalla
        }
        let ventanas = fuera.map { id in contenido.windows.filter { $0.windowID == id } } ?? []
        let filtro = SCContentFilter(display: d, excludingWindows: ventanas)
        let config = SCStreamConfiguration()
        config.width = Int(camino.ancho)
        config.height = Int(camino.alto)
        // Encogida en la tarjeta, con bandas si no tiene la misma forma.
        config.scalesToFit = true
        // El tope del perfil, con un 5 % de holgura (`ritmo::minimo_entre`).
        config.minimumFrameInterval = CMTime(value: 95, timescale: CMTimeScale(camino.porSegundo) * 100)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // Se retienen hasta tres (el nuevo, el que espera y el que se
        // repite) y el codificador los suyos.
        config.queueDepth = 8
        config.showsCursor = true
        let flujo = SCStream(filter: filtro, configuration: config, delegate: self)
        try flujo.addStreamOutput(self, type: .screen, sampleHandlerQueue: cola)
        try await flujo.startCapture()
        self.flujo = flujo
        pantalla = d.displayID
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .screen, !cerrado, !roto, muestra.isValid, SalidaGrabacion.esFotogramaCompleto(muestra),
              let imagen = CMSampleBufferGetImageBuffer(muestra) else { return }
        // La hora a la que se capturo (la del sistema); si dice algo raro,
        // la de ahora.
        let ahora = VideoDeClase.ahora()
        var hora = VideoDeClase.unidades(muestra.presentationTimeStamp)
        if !muestra.presentationTimeStamp.isValid || abs(hora - ahora) > Int64(VideoDeClase.escala) { hora = ahora }
        retenido = (imagen, hora)
        decidir()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        cola.async {
            guard !self.cerrado, !self.roto else { return }
            self.flujo = nil
            // Se fue: se repite la ultima imagen mientras se intenta volver,
            // salvo que ya se haya caido demasiadas veces.
            if self.ritmo.otraVuelta(ahora: VideoDeClase.ahora()) {
                self.caida = true
                self.decidir()
            } else {
                self.romper()
            }
        }
    }

    /// Cada tres segundos, mientras la pantalla no este, se intenta otra vez.
    private func mirarSiVuelve(_ ahora: Int64) {
        guard caida, !reabriendo, ritmo.reabrirToca(ahora: ahora) else { return }
        reabriendo = true
        Task {
            let bien = (try? await self.abrirPantalla()) != nil
            self.cola.async {
                self.reabriendo = false
                guard bien else { return }
                if self.cerrado || self.roto {
                    Task { await self.pararPantalla() }
                    return
                }
                self.caida = false
                self.ritmo.reabierta()
            }
        }
    }

    // MARK: Decidir y escribir (en `cola`)

    private func arrancarTemporizador() {
        guard temporizador == nil, !cerrado else { return }
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.setEventHandler { [weak self] in self?.decidir() }
        t.schedule(deadline: .now() + .milliseconds(10), repeating: .never)
        t.resume()
        temporizador = t
    }

    /// **Una vuelta del motor**: lo que diga el ritmo, y dormir justo hasta
    /// que cambie de opinion.
    private func decidir() {
        guard !cerrado, !roto else { return }
        let ahora = VideoDeClase.ahora()
        mirarSiVuelve(ahora)
        let p = ritmo.paso(ahora: ahora, horaRetenida: retenido?.hora)
        switch p.accion {
        case .nuevo:
            if let r = retenido {
                retenido = nil
                poner(r.imagen, en: p.instante, repetido: false, ahora: ahora)
            }
        case .repetir:
            if let imagen = ultima ?? fotogramaNegro() {
                poner(imagen, en: p.instante, repetido: true, ahora: ahora)
            }
        case .esperar:
            break
        }
        guard !roto, let temporizador else { return }
        let espera = ritmo.espera(ahora: ahora, hayRetenido: retenido != nil)
        temporizador.schedule(deadline: .now() + .nanoseconds(Int(espera) * 100), repeating: .never)
    }

    /// Le da una imagen al video en `instante`; entra al codificador la
    /// que esperaba (un fotograma de retraso), salvo que fuera un repetido
    /// al que este de verdad le quita el sitio.
    private func poner(_ imagen: CVPixelBuffer, en instante: Int64, repetido: Bool, ahora: Int64) {
        if let p = pendiente {
            let sustituye = !repetido && ritmo.sustituyeAlRepetido(pendienteEsRepetido: p.repetido,
                                                                   tPendiente: p.instante, tNuevo: instante)
            if !sustituye { escribirFotograma(p.imagen, en: p.instante, ahora: ahora) }
        }
        pendiente = (imagen, instante, repetido)
        ultima = imagen
    }

    private func escribirFotograma(_ imagen: CVPixelBuffer, en instante: Int64, ahora: Int64) {
        guard !roto else { return }
        // Nunca hacia atras ni dos en el mismo instante (un milisegundo).
        let t = max(instante, ultimoInstante + 10_000)
        guard entradaVideo.isReadyForMoreMediaData else {
            // Atrasado: este se salta; si dura, se corta.
            if ritmo.escrito(entro: false, ahora: ahora) { romper() }
            return
        }
        guard adaptador.append(imagen, withPresentationTime: CMTime(value: t, timescale: VideoDeClase.escala)) else {
            return romper()
        }
        ultimoInstante = t
        escritos += 1
        _ = ritmo.escrito(entro: true, ahora: ahora)
    }

    private func ponerSonido(_ v: [Float], _ posicion: UInt64) {
        guard !cerrado, !roto, !v.isEmpty else { return }
        let ahora = VideoDeClase.ahora()
        // Lo que pisa lo ya escrito se recorta; un hueco se deja.
        guard let tramo = ritmo.sonido(posicion: posicion, marcos: UInt64(v.count), ahora: ahora) else { return }
        let salto = Int(min(tramo.salto, UInt64(v.count)))
        if salto < v.count, let m = muestraDeAudio(Array(v[salto...]), en: Int64(tramo.desde)) {
            sonidoEnEspera.append(m)
        }
        vaciarSonido()
        // El sonido ancla el reloj: un fotograma que esperaba al ancla (al
        // seguir de una pausa) ya puede ir.
        if retenido != nil { decidir() }
    }

    /// Da al codificador el sonido que espera, en orden.
    private func vaciarSonido() {
        while let m = sonidoEnEspera.first, entradaAudio.isReadyForMoreMediaData {
            guard entradaAudio.append(m) else { return romper() }
            sonidoEnEspera.removeFirst()
        }
        if sonidoEnEspera.count > VideoDeClase.topeDeSonido {
            sonidoEnEspera.removeFirst(sonidoEnEspera.count - VideoDeClase.topeDeSonido)
        }
    }

    private func romper() {
        guard !roto, !cerrado else { return }
        roto = true
        retenido = nil
        pendiente = nil
        ultima = nil
        temporizador?.cancel()
        temporizador = nil
        alRomperse?()
    }

    private func fotogramaNegro() -> CVPixelBuffer? {
        if negro == nil { negro = VideoDeClase.negro(ancho: Int(camino.ancho), alto: Int(camino.alto)) }
        return negro
    }

    /// Un fotograma negro en YUV de video (Y = 16, Cb = Cr = 128).
    static func negro(ancho: Int, alto: Int) -> CVPixelBuffer? {
        var creado: CVPixelBuffer?
        let atributos: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        guard CVPixelBufferCreate(kCFAllocatorDefault, ancho, alto, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  atributos as CFDictionary, &creado) == kCVReturnSuccess,
              let pb = creado else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        for (plano, valor) in [(0, Int32(16)), (1, Int32(128))] {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, plano) else { continue }
            memset(base, valor, CVPixelBufferGetBytesPerRowOfPlane(pb, plano) * CVPixelBufferGetHeightOfPlane(pb, plano))
        }
        return pb
    }

    /// El formato del sonido que llega: mono `Float32` a `muestreo`.
    static func formatoMono(muestreo: Int) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(muestreo), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
            mBitsPerChannel: 32, mReserved: 0)
        var formato: CMAudioFormatDescription?
        let estado = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                                    layout: nil, magicCookieSize: 0, magicCookie: nil,
                                                    extensions: nil, formatDescriptionOut: &formato)
        return estado == noErr ? formato : nil
    }

    /// Un bloque de sonido como muestra del MP4, empezando en la muestra
    /// `inicio`.
    private func muestraDeAudio(_ v: [Float], en inicio: Int64) -> CMSampleBuffer? {
        let largo = v.count * MemoryLayout<Float>.size
        var creado: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: largo,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: largo,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &creado) == kCMBlockBufferNoErr,
              let bloque = creado else { return nil }
        let copiado = v.withUnsafeBytes { p -> OSStatus in
            guard let base = p.baseAddress else { return OSStatus(-1) }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: bloque, offsetIntoDestination: 0,
                                                 dataLength: largo)
        }
        guard copiado == kCMBlockBufferNoErr else { return nil }
        var muestra: CMSampleBuffer?
        let estado = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: bloque, formatDescription: formatoAudio,
            sampleCount: v.count, presentationTimeStamp: CMTime(value: inicio, timescale: CMTimeScale(muestreo)),
            packetDescriptions: nil, sampleBufferOut: &muestra)
        return estado == noErr ? muestra : nil
    }

    // MARK: Cerrar

    private func pararPantalla() async {
        if let flujo {
            self.flujo = nil
            try? await flujo.stopCapture()
        }
    }

    /// **Cierra el MP4**, con el sonido ya parado (es lo que lo acaba).
    /// `nil` si no se llego a grabar (la pantalla nunca se abrio) o no se
    /// pudo cerrar; un video que se corto a mitad vale hasta donde llego.
    func terminar() async -> URL? {
        await pararPantalla()
        let hecho = await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            cola.async {
                self.temporizador?.cancel()
                self.temporizador = nil
                let ahora = VideoDeClase.ahora()
                let estaba = !self.roto
                self.cerrado = true
                self.retenido = nil
                guard self.empezado, self.escritor.status == .writing else {
                    if self.escritor.status == .writing { self.escritor.cancelWriting() }
                    try? FileManager.default.removeItem(at: self.url)
                    c.resume(returning: nil)
                    return
                }
                if estaba {
                    // Sin ningun fotograma, uno negro que lo cubra todo; y
                    // el que esperaba, que dura hasta el final.
                    if self.escritos == 0, self.pendiente == nil, let n = self.fotogramaNegro() {
                        self.pendiente = (n, 0, true)
                    }
                    if let p = self.pendiente { self.escribirFotograma(p.imagen, en: p.instante, ahora: ahora) }
                }
                self.pendiente = nil
                self.ultima = nil
                guard self.escritos > 0 else {
                    self.escritor.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    c.resume(returning: nil)
                    return
                }
                self.entradaVideo.markAsFinished()
                // El sonido que aun esperaba: un segundo como mucho.
                var vueltas = 0
                while !self.sonidoEnEspera.isEmpty, vueltas < 100, self.escritor.status == .writing {
                    if self.entradaAudio.isReadyForMoreMediaData {
                        if !self.entradaAudio.append(self.sonidoEnEspera.removeFirst()) { break }
                    } else {
                        usleep(10_000)
                        vueltas += 1
                    }
                }
                self.sonidoEnEspera.removeAll()
                self.entradaAudio.markAsFinished()
                // Hasta donde acaba el sonido: las dos pistas duran lo mismo.
                let fin = max(self.ritmo.finalDelVideo(ahora: ahora), self.ultimoInstante + 10_000)
                self.escritor.endSession(atSourceTime: CMTime(value: fin, timescale: VideoDeClase.escala))
                self.escritor.finishWriting {
                    let bien = self.escritor.status == .completed
                    if !bien { try? FileManager.default.removeItem(at: self.url) }
                    c.resume(returning: bien ? self.url : nil)
                }
            }
        }
        // La pantalla que se abrio justo mientras se cerraba.
        await pararPantalla()
        return hecho
    }

    /// Lo deja y borra lo escrito.
    func tirar() async {
        await pararPantalla()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            cola.async {
                self.temporizador?.cancel()
                self.temporizador = nil
                self.cerrado = true
                self.retenido = nil
                self.pendiente = nil
                self.ultima = nil
                self.sonidoEnEspera.removeAll()
                if self.escritor.status == .writing { self.escritor.cancelWriting() }
                try? FileManager.default.removeItem(at: self.url)
                c.resume()
            }
        }
        await pararPantalla()
    }
}
