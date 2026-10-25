// **El sonido de una clase o una reunion** (Windows 2cc497b,
// `pixpin-audio/src/entrada.rs` y `mezclador.rs`): el microfono, lo que
// suena en el Mac (Meet, Zoom, el video de la clase) o los dos, mezclados en
// UN solo `.m4a` de nota de voz (AAC mono, `EscritorVoz`).
//
// - El microfono, con AVAudioEngine (su grifo, como `GrabadoraVoz`).
// - El sonido del Mac, con ScreenCaptureKit (`SCStream` con `capturesAudio`,
//   sin el sonido de PixPin): el equivalente del modo loopback de Windows.
//   El flujo pide una pantalla aunque solo se quiera el sonido: se le da la
//   principal a 2x2 pixeles y un fotograma por segundo, y no se le pone
//   salida de imagen (no se codifica nada).
// - Cada fuente se pasa a mono a 48 kHz y se mezcla en `MezcladorClase`, la
//   copia del de Windows: se suma muestra a muestra recortando, una fuente
//   callada no para a la otra (macOS tampoco manda nada del sistema mientras
//   no suena) y la nota sigue al reloj de la pared, para que las capturas
//   hechas durante la grabacion caigan en su minuto.
// - En pausa lo que llega se tira y el reloj de la nota no corre.
// - Con video (Windows 20162e9), cada bloque que se escribe en la nota va
//   tambien a `copia` (`pixpin_audio::Copia`): es el sonido del MP4 y su
//   reloj (`VideoDeClase`).
//
// Rendimiento (§4bis): nada se guarda en memoria mas alla de la holgura de
// un cuarto de segundo; todo pasa en una cola serie con prioridad de
// usuario, y un temporizador de 100 ms alinea con el reloj y vacia.

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// **Juntar dos fuentes en una nota** (`pixpin_audio::mezclador::Mezclador`
/// de Windows, al numero): las colas de cada fuente, ya en mono y al
/// muestreo de la grabacion. Puro: lo prueban las pruebas.
public struct MezcladorClase {
    /// Cuanto puede adelantarse una fuente a otra antes de que a la otra se
    /// le ponga silencio (`HOLGURA_MS`).
    public static let holguraMs = 250

    private var colas: [[Float]]
    private let holgura: Int

    /// Para `fuentes` fuentes (una o dos) a `muestreo` hercios.
    public init(fuentes: Int, muestreo: Int) {
        colas = Array(repeating: [], count: max(fuentes, 1))
        holgura = max(muestreo * MezcladorClase.holguraMs / 1000, 1)
    }

    /// Lo que acaba de llegar de la fuente `cual`.
    public mutating func empuja(_ cual: Int, _ muestras: [Float]) {
        guard colas.indices.contains(cual) else { return }
        colas[cual].append(contentsOf: muestras)
    }

    /// Lo que espera en la cola mas larga.
    public var enEspera: Int { colas.map(\.count).max() ?? 0 }

    /// **Al paso del reloj**: si con lo ya escrito y lo que espera no se
    /// llega a lo que marca el reloj, menos la holgura, lo que falta es
    /// silencio en todas las fuentes.
    public mutating func alinear(escritas: Int64, esperadas: Int64) {
        let larga = enEspera
        let hay = escritas + Int64(larga)
        guard esperadas > hay + Int64(holgura) else { return }
        let hasta = larga + Int(esperadas - hay)
        for i in colas.indices where colas[i].count < hasta {
            colas[i].append(contentsOf: [Float](repeating: 0, count: hasta - colas[i].count))
        }
    }

    /// **Lo que ya se puede escribir**: lo que tienen todas las fuentes, y
    /// si una se adelanto mas de la holgura, tambien eso, con silencio en
    /// las que no llegaron.
    public mutating func sacar() -> [Float] {
        let corta = colas.map(\.count).min() ?? 0
        let larga = enEspera
        let n = larga > corta + holgura ? larga - holgura / 2 : corta
        return mezclar(n)
    }

    /// **Al parar**: todo lo que quede.
    public mutating func resto() -> [Float] {
        mezclar(enEspera)
    }

    /// En pausa: lo que llega se tira.
    public mutating func vaciar() {
        for i in colas.indices { colas[i].removeAll(keepingCapacity: true) }
    }

    private mutating func mezclar(_ n: Int) -> [Float] {
        guard n > 0 else { return [] }
        var suma = [Float](repeating: 0, count: n)
        for i in colas.indices {
            let toma = min(n, colas[i].count)
            for k in 0..<toma { suma[k] += colas[i][k] }
            colas[i].removeFirst(toma)
        }
        for k in suma.indices { suma[k] = min(max(suma[k], -1), 1) }
        return suma
    }
}

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

/// Pasa bloques de cualquier formato PCM a mono `Float32` a `muestreo`.
/// Lo usa un solo hilo cada vez.
final class AMono {
    let formato: AVAudioFormat
    private var conversor: AVAudioConverter?
    private var entrada: AVAudioFormat?

    init?(muestreo: Double) {
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: muestreo, channels: 1,
                                    interleaved: false) else { return nil }
        formato = f
    }

    func muestras(_ b: AVAudioPCMBuffer) -> [Float] {
        guard b.frameLength > 0 else { return [] }
        let f = b.format
        // Lo normal (mismo muestreo, `Float32` sin entrelazar): a mano.
        if f.sampleRate == formato.sampleRate, f.commonFormat == .pcmFormatFloat32, !f.isInterleaved,
           let datos = b.floatChannelData {
            let n = Int(b.frameLength)
            let canales = max(Int(f.channelCount), 1)
            var v = [Float](repeating: 0, count: n)
            let peso = 1 / Float(canales)
            for c in 0..<canales {
                let canal = datos[c]
                for i in 0..<n { v[i] += canal[i] * peso }
            }
            return v
        }
        if conversor == nil || entrada?.isEqual(f) != true {
            conversor = AVAudioConverter(from: f, to: formato)
            conversor?.downmix = true
            entrada = f
        }
        guard let conversor else { return [] }
        let capacidad = AVAudioFrameCount((Double(b.frameLength) * formato.sampleRate / f.sampleRate).rounded(.up)) + 32
        guard let salida = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: capacidad) else { return [] }
        var dado = false
        var fallo: NSError?
        let estado = conversor.convert(to: salida, error: &fallo) { _, situacion in
            if dado {
                situacion.pointee = .noDataNow
                return nil
            }
            dado = true
            situacion.pointee = .haveData
            return b
        }
        guard estado != .error, let d = salida.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: d[0], count: Int(salida.frameLength)))
    }
}

/// **La grabadora de la clase**: abre las fuentes, mezcla y escribe. Lo
/// suyo pasa en `cola`; lo que se lee desde la barra (tiempo, nivel) va con
/// cerrojo.
final class AudioDeClase: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// El muestreo de la nota: el de las dos fuentes, sin adivinar.
    static let muestreo: Double = 48_000

    let url: URL
    let fuentes: FuentesClase
    let cola = DispatchQueue(label: "PixPin grabar clase", qos: .userInitiated)

    private let escritor: EscritorVoz
    private var mezclador: MezcladorClase
    private let monoDelEquipo: AMono
    private var motor: AVAudioEngine?
    private var flujo: SCStream?
    private var tic: DispatchSourceTimer?
    private let indiceMicrofono = 0
    /// Lo que se escribe en la nota, para el video (en `cola`). Se pone
    /// antes de `empezar`.
    var copia: (([Float]) -> Void)?
    private var indiceEquipo: Int { fuentes.microfono ? 1 : 0 }

    // Con cerrojo: lo que mira la barra.
    private let cerrojo = NSLock()
    private var _enPausa = false
    private var _nivel: Float = 0
    /// El reloj de la nota: cuando empezo y lo que llevan las pausas.
    private var inicio: Date?
    private var pausadoDesde: Date?
    private var pausado: TimeInterval = 0
    private var cerrado = false

    init(url: URL, fuentes: FuentesClase) throws {
        guard let mono = AMono(muestreo: AudioDeClase.muestreo) else { throw ErrorAudioClase.formato("mono") }
        self.url = url
        self.fuentes = fuentes
        escritor = try EscritorVoz(url: url, muestreoDeEntrada: AudioDeClase.muestreo)
        mezclador = MezcladorClase(fuentes: (fuentes.microfono ? 1 : 0) + (fuentes.equipo ? 1 : 0),
                                   muestreo: Int(AudioDeClase.muestreo))
        monoDelEquipo = mono
        super.init()
    }

    // MARK: Lo que mira la barra

    var enPausa: Bool {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return _enPausa
    }

    /// El nivel de lo ultimo que entro, de 0 a 1.
    var nivel: Float {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return _enPausa ? 0 : _nivel
    }

    /// Lo que lleva la nota, sin las pausas (el minuto de una captura).
    var llevadoMs: Int64 {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return llevadoSinCerrojo(Date())
    }

    private func llevadoSinCerrojo(_ ahora: Date) -> Int64 {
        guard let inicio else { return 0 }
        let parado = pausado + (pausadoDesde.map { ahora.timeIntervalSince($0) } ?? 0)
        return Int64(max(ahora.timeIntervalSince(inicio) - parado, 0) * 1000)
    }

    // MARK: Abrir

    /// Abre las fuentes y empieza a escribir. El permiso del microfono (y el
    /// de grabar la pantalla, para el sonido del Mac) se pide antes.
    func empezar() async throws {
        if fuentes.microfono { try abrirMicrofono() }
        if fuentes.equipo {
            do {
                try await abrirEquipo()
            } catch {
                pararMicrofono()
                throw ErrorAudioClase.sinSonidoDelEquipo
            }
        }
        cerrojo.lock()
        inicio = Date()
        cerrojo.unlock()
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.alPasoDelReloj() }
        t.resume()
        tic = t
    }

    private func abrirMicrofono() throws {
        let motor = AVAudioEngine()
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0, let mono = AMono(muestreo: AudioDeClase.muestreo) else {
            throw ErrorAudioClase.sinMicrofono
        }
        let cual = indiceMicrofono
        // El grifo corre en su hilo: pasa a mono ahi y deja la mezcla a la cola.
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { [weak self] bloque, _ in
            let v = mono.muestras(bloque)
            guard !v.isEmpty else { return }
            self?.cola.async { self?.entra(cual, v) }
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
        config.sampleRate = Int(AudioDeClase.muestreo)
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        let flujo = SCStream(filter: filtro, configuration: config, delegate: self)
        try flujo.addStreamOutput(self, type: .audio, sampleHandlerQueue: cola)
        try await flujo.startCapture()
        self.flujo = flujo
    }

    // MARK: SCStreamOutput (en `cola`)

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .audio, muestra.isValid, let descripcion = muestra.formatDescription else { return }
        let formato = AVAudioFormat(cmAudioFormatDescription: descripcion)
        let v: [Float] = (try? muestra.withAudioBufferList { (lista, _) -> [Float] in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: formato, bufferListNoCopy: lista.unsafePointer) else {
                return []
            }
            return monoDelEquipo.muestras(pcm)
        }) ?? []
        guard !v.isEmpty else { return }
        entra(indiceEquipo, v)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Sin el sonido del Mac (se quito el permiso...): el microfono sigue
        // y la nota sigue al reloj con silencio.
        cola.async { [weak self] in self?.flujo = nil }
    }

    // MARK: Mezclar (en `cola`)

    private func entra(_ cual: Int, _ v: [Float]) {
        guard !cerrado else { return }
        if enPausa { return }
        mezclador.empuja(cual, v)
        escribir(mezclador.sacar())
    }

    private func alPasoDelReloj() {
        guard !cerrado else { return }
        if enPausa {
            mezclador.vaciar()
            return
        }
        let esperadas = llevadoMs * Int64(AudioDeClase.muestreo) / 1000
        mezclador.alinear(escritas: escritor.muestrasEscritas, esperadas: esperadas)
        escribir(mezclador.sacar())
    }

    private func escribir(_ v: [Float]) {
        guard !v.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: monoDelEquipo.formato,
                                                   frameCapacity: AVAudioFrameCount(v.count)),
              let d = b.floatChannelData else { return }
        v.withUnsafeBufferPointer { p in d[0].update(from: p.baseAddress!, count: v.count) }
        b.frameLength = AVAudioFrameCount(v.count)
        try? escritor.escribir(b)
        copia?(v)
        let pico = v.reduce(Float(0)) { max($0, abs($1)) }
        cerrojo.lock()
        _nivel = pico
        cerrojo.unlock()
    }

    // MARK: Pausar y cerrar

    func pausar(_ si: Bool) {
        cerrojo.lock()
        if si, !_enPausa {
            pausadoDesde = Date()
        } else if !si, _enPausa, let desde = pausadoDesde {
            pausado += Date().timeIntervalSince(desde)
            pausadoDesde = nil
        }
        _enPausa = si
        cerrojo.unlock()
        if si { cola.async { [weak self] in self?.mezclador.vaciar() } }
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
                if !self.enPausa {
                    let esperadas = self.llevadoMs * Int64(AudioDeClase.muestreo) / 1000
                    self.mezclador.alinear(escritas: self.escritor.muestrasEscritas, esperadas: esperadas)
                    self.escribir(self.mezclador.resto())
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
