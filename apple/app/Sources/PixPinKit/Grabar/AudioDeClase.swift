// **El sonido de una clase o una reunion** (Windows 2cc497b y, con el
// motor de audio nuevo, 38204cb y 06f842c): el microfono, lo que suena en
// el Mac (Meet, Zoom, el video de la clase) o los dos, mezclados en UN solo
// `.m4a` de nota de voz (AAC mono, `EscritorVoz`).
//
// - El microfono, con AVAudioEngine (su grifo, como `GrabadoraVoz`).
// - El sonido del Mac, con ScreenCaptureKit (`SCStream` con `capturesAudio`,
//   sin el sonido de PixPin): el equivalente del modo loopback de Windows.
//   El flujo pide una pantalla aunque solo se quiera el sonido: se le da la
//   principal a 2x2 pixeles y un fotograma por segundo, y no se le pone
//   salida de imagen (no se codifica nada).
// - **La mezcla es la de Windows** (`MezclaDeAudio` del nucleo, que es
//   `pixpin-motor-audio`): cada bloque del sistema cruza entero al nucleo
//   (`MezclaVoz.empujar`), con su muestreo y sus canales; alli se corrige la
//   deriva de cada tarjeta, el microfono lleva paso alto y realce de la voz,
//   se suma y pasa por el limitador. Una fuente callada (macOS no manda nada
//   del sistema mientras no suena) es silencio y no para a la otra, y la
//   nota sigue al reloj de la pared, para que las capturas hechas durante la
//   grabacion caigan en su minuto.
// - En pausa lo que llega se tira y el reloj de la nota no corre.
// - Con video, cada bloque que se escribe en la nota va tambien a `copia`
//   con su posicion: es el sonido del MP4 y su reloj (`VideoDeClase`).
//
// Rendimiento (§4bis): nada se guarda en memoria mas alla de los anillos
// del nucleo; todo pasa en una cola serie con prioridad de usuario, y un
// temporizador de 20 ms saca lo mezclado y lo escribe.

import AVFoundation
import CoreMedia
import Foundation
import PixPinCore
import ScreenCaptureKit

/// Que se graba: el microfono, el sonido del Mac o los dos (`Fuentes`).
public struct FuentesClase: Equatable, Sendable {
    public var microfono: Bool
    public var equipo: Bool

    public init(microfono: Bool, equipo: Bool) {
        self.microfono = microfono
        self.equipo = equipo
    }

    public var alguna: Bool { microfono || equipo }
}

public enum ErrorAudioClase: Error, Equatable {
    case sinMicrofono
    /// No se pudo abrir el sonido del Mac (`SinSonidoDelEquipo`).
    case sinSonidoDelEquipo
    case formato(String)
}

/// **La grabadora de la clase**: abre las fuentes, mezcla y escribe. Lo
/// suyo pasa en `cola`; lo que se lee desde la barra (tiempo, nivel) lo da
/// la mezcla, que se puede leer desde cualquier hilo.
final class AudioDeClase: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// El muestreo de la nota (el de Windows y el del video).
    static let muestreo: Double = MezclaVoz.muestreo
    /// El sonido del Mac, como se le pide a ScreenCaptureKit.
    static let muestreoDelEquipo: Double = 48_000
    static let canalesDelEquipo = 2

    let url: URL
    let fuentes: FuentesClase
    let cola = DispatchQueue(label: "PixPin grabar clase", qos: .userInitiated)

    private let escritor: EscritorVoz
    private let formatoNota: AVAudioFormat
    /// La mezcla: se crea al abrir (hace falta el formato del microfono).
    private var mezcla: MezclaDeAudio?
    private let monoDelEquipo: AMono?
    private var motor: AVAudioEngine?
    private var flujo: SCStream?
    private var tic: DispatchSourceTimer?
    /// Lo que se escribe en la nota y donde empieza, para el video (en
    /// `cola`). Se pone antes de `empezar`.
    var copia: (([Float], UInt64) -> Void)?
    private var indiceEquipo: UInt32 { fuentes.microfono ? 1 : 0 }
    /// En `cola`: ya se saco lo ultimo.
    private var cerrado = false

    init(url: URL, fuentes: FuentesClase) throws {
        guard let nota = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioDeClase.muestreo,
                                       channels: 1, interleaved: false) else {
            throw ErrorAudioClase.formato("mono")
        }
        self.url = url
        self.fuentes = fuentes
        formatoNota = nota
        monoDelEquipo = AMono(muestreo: AudioDeClase.muestreoDelEquipo)
        escritor = try EscritorVoz(url: url, muestreoDeEntrada: AudioDeClase.muestreo)
        super.init()
    }

    // MARK: Lo que mira la barra

    var enPausa: Bool { mezcla?.enPausa() ?? false }

    /// El nivel de lo ultimo que entro, de 0 a 1.
    var nivel: Float { mezcla?.nivel() ?? 0 }

    /// Lo que lleva la nota, sin las pausas (el minuto de una captura).
    var llevadoMs: Int64 { mezcla?.llevadoMs() ?? 0 }

    // MARK: Abrir

    /// Abre las fuentes y empieza a escribir. El permiso del microfono (y el
    /// de grabar la pantalla, para el sonido del Mac) se pide antes.
    func empezar() async throws {
        // La mezcla, con el formato de cada fuente tal cual.
        var lista: [FuenteDeMezcla] = []
        var motor: AVAudioEngine?
        if fuentes.microfono {
            let m = AVAudioEngine()
            let formato = m.inputNode.outputFormat(forBus: 0)
            guard formato.sampleRate > 0, formato.channelCount > 0 else { throw ErrorAudioClase.sinMicrofono }
            lista.append(FuenteDeMezcla(papel: .microfono, muestreo: UInt32(formato.sampleRate.rounded()),
                                        canales: UInt16(formato.channelCount)))
            motor = m
        }
        if fuentes.equipo {
            lista.append(FuenteDeMezcla(papel: .equipo, muestreo: UInt32(AudioDeClase.muestreoDelEquipo),
                                        canales: UInt16(AudioDeClase.canalesDelEquipo)))
        }
        let mezcla: MezclaDeAudio
        do {
            mezcla = try MezclaDeAudio.nueva(fuentes: lista, muestreo: UInt32(AudioDeClase.muestreo))
        } catch {
            throw ErrorAudioClase.formato("\(error)")
        }
        self.mezcla = mezcla
        if let motor { try abrirMicrofono(motor, en: mezcla) }
        if fuentes.equipo {
            do {
                try await abrirEquipo()
            } catch {
                pararMicrofono()
                throw ErrorAudioClase.sinSonidoDelEquipo
            }
        }
        // El cero: lo que entro mientras se abria lo demas no cuenta.
        cola.sync { _ = mezcla.mezclar() }
        let periodo = Int(periodoDeLaMezclaMs())
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.schedule(deadline: .now() + .milliseconds(periodo), repeating: .milliseconds(periodo))
        t.setEventHandler { [weak self] in self?.alPasoDelReloj() }
        t.resume()
        tic = t
    }

    private func abrirMicrofono(_ motor: AVAudioEngine, en mezcla: MezclaDeAudio) throws {
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        let alterno = AMono(muestreo: formato.sampleRate)
        // El grifo corre en su hilo: cada bloque cruza entero al nucleo.
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { bloque, _ in
            MezclaVoz.empujar(bloque, fuente: 0, en: mezcla, alterno: alterno)
        }
        motor.prepare()
        do {
            try motor.start()
        } catch {
            entrada.removeTap(onBus: 0)
            throw ErrorAudioClase.sinMicrofono
        }
        self.motor = motor
    }

    private func abrirEquipo() async throws {
        let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let pantalla = contenido.displays.first else { throw ErrorAudioClase.sinSonidoDelEquipo }
        let yo = ProcessInfo.processInfo.processIdentifier
        let propias = contenido.applications.filter { $0.processID == yo }
        let filtro = SCContentFilter(display: pantalla, excludingApplications: propias, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        config.capturesAudio = true
        config.sampleRate = Int(AudioDeClase.muestreoDelEquipo)
        config.channelCount = AudioDeClase.canalesDelEquipo
        config.excludesCurrentProcessAudio = true
        let flujo = SCStream(filter: filtro, configuration: config, delegate: self)
        try flujo.addStreamOutput(self, type: .audio, sampleHandlerQueue: cola)
        try await flujo.startCapture()
        self.flujo = flujo
    }

    // MARK: SCStreamOutput (en `cola`)

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .audio, !cerrado, muestra.isValid, let mezcla,
              let descripcion = muestra.formatDescription else { return }
        let formato = AVAudioFormat(cmAudioFormatDescription: descripcion)
        let cual = indiceEquipo
        let alterno = monoDelEquipo
        try? muestra.withAudioBufferList { (lista, _) in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: formato, bufferListNoCopy: lista.unsafePointer) else { return }
            MezclaVoz.empujar(pcm, fuente: cual, en: mezcla, alterno: alterno)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Sin el sonido del Mac (se quito el permiso...): el microfono sigue
        // y la nota sigue al reloj con silencio.
        cola.async { [weak self] in self?.flujo = nil }
    }

    // MARK: Escribir (en `cola`)

    private func alPasoDelReloj() {
        guard !cerrado, let mezcla else { return }
        escribir(mezcla.mezclar())
    }

    private func escribir(_ b: BloqueMezclado) {
        guard let pcm = MezclaVoz.bloque(b.muestras, formato: formatoNota) else { return }
        try? escritor.escribir(pcm)
        copia?(b.muestras, b.posicion)
    }

    // MARK: Pausar y cerrar

    func pausar(_ si: Bool) {
        mezcla?.pausar(pausa: si)
    }

    private func pararMicrofono() {
        motor?.inputNode.removeTap(onBus: 0)
        motor?.stop()
        motor = nil
    }

    private func pararFuentes() async {
        pararMicrofono()
        if let flujo {
            self.flujo = nil
            try? await flujo.stopCapture()
        }
        tic?.cancel()
        tic = nil
    }

    /// Para, escribe lo que quede y cierra el `.m4a`.
    func terminar() async -> NotaGrabada {
        await pararFuentes()
        return await withCheckedContinuation { (c: CheckedContinuation<NotaGrabada, Never>) in
            cola.async {
                if !self.cerrado, let mezcla = self.mezcla {
                    self.escribir(mezcla.terminar())
                }
                self.cerrado = true
                c.resume(returning: self.escritor.terminar())
            }
        }
    }

    /// Para sin guardar: el fichero se borra.
    func cancelar() async {
        await pararFuentes()
        let url = await withCheckedContinuation { (c: CheckedContinuation<URL, Never>) in
            cola.async {
                self.cerrado = true
                c.resume(returning: self.escritor.terminar().url)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}
