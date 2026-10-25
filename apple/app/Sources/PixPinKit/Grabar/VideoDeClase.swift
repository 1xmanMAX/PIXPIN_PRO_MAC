// **El video de la reunion** (Windows 20162e9 y df01da9,
// `grabar_clase/video.rs`): con «Video de esta pantalla», ademas de la nota
// se graba la pantalla donde esta la ventanita a un MP4 H.264 + AAC con el
// **mismo sonido** que la nota de voz.
//
// - La pantalla, con ScreenCaptureKit (`SCStream`, con el cursor y sin la
//   barra de la clase), ya encogida por la tarjeta al tamano de Windows:
//   10 fotogramas por segundo y como mucho 1280x720 (`videoDeLaClase`).
// - El sonido: `AudioDeClase` le pasa cada bloque mezclado que escribe en la
//   nota (`copia`), y ese sonido es tambien el **reloj del video**: cada
//   fotograma se fecha con las muestras recibidas
//   (`fotogramasDebidosDeLaClase`), asi que las dos pistas no se separan,
//   en pausa (no llega sonido) no se escribe ningun fotograma y el video se
//   acaba cuando se acaba el sonido.
// - Un fotograma nuevo solo cuando toca: si la pantalla no cambio se repite
//   el ultimo; si se fue atrasado se escribe solo el ultimo que toca. El
//   primero empieza en el cero aunque llegue tarde, y si la pantalla tarda
//   mas de 5 s en dar su primera imagen se empieza en negro.
// - `AVAssetWriter` con el codificador de la tarjeta (VideoToolbox), como
//   `GrabadorPantalla`. Si el video se corta a mitad (la pantalla se fue, se
//   quito el permiso), la nota sigue y lo grabado hasta ahi vale.

import AppKit
import AVFoundation
import CoreMedia
import PixPinCore
import ScreenCaptureKit
import VideoToolbox

final class VideoDeClase: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    let cola = DispatchQueue(label: "PixPin video de la clase", qos: .userInitiated)
    /// El video dejo de grabarse (la nota sigue). Se llama una vez, desde
    /// `cola`.
    var alRomperse: (() -> Void)?

    private let pantalla: CGDirectDisplayID
    private let ajustes: VideoDeLaClase
    private let muestreo: Int
    private let escritor: AVAssetWriter
    private let entradaVideo: AVAssetWriterInput
    private let adaptador: AVAssetWriterInputPixelBufferAdaptor
    private let entradaAudio: AVAssetWriterInput
    private let formatoAudio: CMAudioFormatDescription
    private var flujo: SCStream?

    // En `cola`.
    /// La ultima imagen de la pantalla.
    private var ultimo: CVPixelBuffer?
    private var negro: CVPixelBuffer?
    /// Muestras de sonido escritas: el reloj.
    private var muestras: Int64 = 0
    /// Fotogramas que ya tocaban al escribir el ultimo.
    private var hechos: UInt64 = 0
    private var empezado = false
    private var roto = false
    private var cerrado = false

    /// Prepara el MP4 en `url` para la pantalla `pantalla`, de
    /// `pixeles` de ancho y alto, con sonido mono a `muestreo`.
    init(url: URL, pantalla: CGDirectDisplayID, pixeles: (ancho: Int, alto: Int), muestreo: Int) throws {
        let ajustes = videoDeLaClase(anchoPantalla: UInt32(max(pixeles.ancho, 2)),
                                     altoPantalla: UInt32(max(pixeles.alto, 2)))
        guard let formato = VideoDeClase.formatoMono(muestreo: muestreo) else {
            throw ErrorGrabacion.escritor("el sonido del video no tiene formato")
        }
        try? FileManager.default.removeItem(at: url)
        let escritor = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let porSegundo = Int(ajustes.porSegundo)
        let compresion: [String: Any] = [
            AVVideoAverageBitRateKey: Int(ajustes.bitsPorSegundo),
            AVVideoExpectedSourceFrameRateKey: porSegundo,
            AVVideoMaxKeyFrameIntervalKey: porSegundo * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(ajustes.ancho),
            AVVideoHeightKey: Int(ajustes.alto),
            AVVideoCompressionPropertiesKey: compresion,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        guard escritor.canAdd(video) else { throw ErrorGrabacion.escritor("el MP4 no admite el video") }
        escritor.add(video)
        // El sonido: AAC mono a 96 kbps, el de la nota de voz.
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: muestreo,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Int(ajustes.bitsAudio),
        ], sourceFormatHint: formato)
        audio.expectsMediaDataInRealTime = true
        guard escritor.canAdd(audio) else { throw ErrorGrabacion.escritor("el MP4 no admite el sonido") }
        escritor.add(audio)
        guard escritor.startWriting() else {
            throw ErrorGrabacion.escritor(escritor.error?.localizedDescription ?? "no se pudo abrir el MP4")
        }
        escritor.startSession(atSourceTime: .zero)

        self.url = url
        self.pantalla = pantalla
        self.ajustes = ajustes
        self.muestreo = muestreo
        self.escritor = escritor
        entradaVideo = video
        adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        entradaAudio = audio
        formatoAudio = formato
        super.init()
    }

    /// El sonido mono `Float32` del bloque de la nota que se acaba de
    /// escribir (lo llama `AudioDeClase` desde su cola).
    func sonido(_ v: [Float]) {
        cola.async { self.poner(v, fin: false) }
    }

    // MARK: Mirar la pantalla

    /// Empieza a mirar la pantalla, sin la ventana `fuera` (la barra). Si
    /// no se puede, el video queda roto y la nota sigue.
    func empezar(sin fuera: CGWindowID?) async throws {
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let d = contenido.displays.first(where: { $0.displayID == pantalla }) ?? contenido.displays.first else {
                throw ErrorGrabacion.sinPantalla
            }
            let ventanas = fuera.map { id in contenido.windows.filter { $0.windowID == id } } ?? []
            let filtro = SCContentFilter(display: d, excludingWindows: ventanas)
            let config = SCStreamConfiguration()
            config.width = Int(ajustes.ancho)
            config.height = Int(ajustes.alto)
            config.scalesToFit = true
            // Algo menos que el ritmo del video: el tope solo ahorra copias.
            config.minimumFrameInterval = CMTime(value: 2, timescale: CMTimeScale(ajustes.porSegundo) * 3)
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.queueDepth = 6
            config.showsCursor = true
            let flujo = SCStream(filter: filtro, configuration: config, delegate: self)
            try flujo.addStreamOutput(self, type: .screen, sampleHandlerQueue: cola)
            try await flujo.startCapture()
            self.flujo = flujo
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

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .screen, !cerrado, !roto, muestra.isValid, SalidaGrabacion.esFotogramaCompleto(muestra),
              let imagen = CMSampleBufferGetImageBuffer(muestra) else { return }
        ultimo = imagen
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        cola.async { self.romper() }
    }

    // MARK: Escribir (en `cola`)

    private func romper() {
        guard !roto, !cerrado else { return }
        roto = true
        ultimo = nil
        alRomperse?()
    }

    private func poner(_ v: [Float], fin: Bool) {
        guard !cerrado, !roto else { return }
        if !v.isEmpty {
            if entradaAudio.isReadyForMoreMediaData, let m = muestraDeAudio(v, en: muestras) {
                guard entradaAudio.append(m) else { return romper() }
            }
            muestras += Int64(v.count)
        }
        let debidos = fotogramasDebidosDeLaClase(muestras: UInt64(muestras), muestreo: UInt32(muestreo))
        guard debidos > hechos else { return }
        // Sin imagen aun: se espera un poco antes de empezar en negro.
        let ms = muestras * 1000 / Int64(max(muestreo, 1))
        if hechos == 0, ultimo == nil, ms < ajustes.esperaPrimeroMs, !fin { return }
        guard let imagen = ultimo ?? fotogramaNegro(), entradaVideo.isReadyForMoreMediaData else { return }
        // El ultimo que toca; el primero cubre desde el cero.
        let indice = hechos == 0 ? 0 : Int64(debidos - 1)
        let cuando = CMTime(value: indice, timescale: CMTimeScale(ajustes.porSegundo))
        guard adaptador.append(imagen, withPresentationTime: cuando) else { return romper() }
        hechos = debidos
    }

    private func fotogramaNegro() -> CVPixelBuffer? {
        if negro == nil { negro = VideoDeClase.negro(ancho: Int(ajustes.ancho), alto: Int(ajustes.alto)) }
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
                // Lo que toque al final (en negro si la pantalla no llego a
                // dar ninguna imagen).
                self.poner([], fin: true)
                self.cerrado = true
                self.ultimo = nil
                guard self.empezado, self.hechos > 0, self.escritor.status == .writing else {
                    if self.escritor.status == .writing { self.escritor.cancelWriting() }
                    try? FileManager.default.removeItem(at: self.url)
                    c.resume(returning: nil)
                    return
                }
                self.entradaVideo.markAsFinished()
                self.entradaAudio.markAsFinished()
                self.escritor.endSession(atSourceTime: CMTime(value: max(self.muestras, 1),
                                                              timescale: CMTimeScale(self.muestreo)))
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
                self.cerrado = true
                self.ultimo = nil
                if self.escritor.status == .writing { self.escritor.cancelWriting() }
                try? FileManager.default.removeItem(at: self.url)
                c.resume()
            }
        }
        await pararPantalla()
    }
}
