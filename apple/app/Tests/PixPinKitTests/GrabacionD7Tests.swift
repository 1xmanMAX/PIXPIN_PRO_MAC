import AVFoundation
import CoreGraphics
import CoreMedia
import ImageIO
@testable import PixPinKit
import XCTest

/// La grabacion en dos fases (D7): la maquina de la sesion, el reloj sin
/// las pausas y el marco que se mueve y se estira (`grabador.rs`).
final class GrabacionD7Tests: XCTestCase {
    // MARK: La maquina

    func testSinRetardoGrabarArrancaYEnPausaVuelve() {
        var m = MaquinaGrabacion()
        XCTAssertTrue(m.abrir())
        XCTAssertFalse(m.abrir(), "no se abre otra encima")
        XCTAssertEqual(m.fase, .esperando)
        XCTAssertEqual(m.grabar(retardo: 0), .arrancar)
        XCTAssertEqual(m.fase, .arrancando)
        XCTAssertEqual(m.grabar(retardo: 0), .nada, "dos pulsaciones no piden dos flujos")
        m.arrancado()
        XCTAssertEqual(m.fase, .grabando)
        XCTAssertEqual(m.alternarPausa(), .pausar)
        XCTAssertEqual(m.fase, .pausada)
        XCTAssertEqual(m.alternarPausa(), .reanudar)
        XCTAssertEqual(m.parar(), .parar)
        m.cerrada()
        XCTAssertFalse(m.enSesion)
    }

    func testConRetardoCuentaYVolverAPulsarSeLaSalta() {
        var m = MaquinaGrabacion()
        m.abrir()
        XCTAssertEqual(m.grabar(retardo: 3), .contar(3))
        XCTAssertEqual(m.fase, .contando)
        XCTAssertFalse(m.fase!.conVideo, "contando el marco aun se mueve")
        XCTAssertEqual(m.grabar(retardo: 3), .arrancar)
        XCTAssertEqual(m.cuentaAcabada(), .nada, "la cuenta ya no arranca otra vez")

        var otra = MaquinaGrabacion()
        otra.abrir()
        _ = otra.grabar(retardo: 2)
        XCTAssertEqual(otra.cuentaAcabada(), .arrancar)
    }

    func testEscAntesCierraYDespuesPara() {
        var m = MaquinaGrabacion()
        m.abrir()
        XCTAssertEqual(m.esc(), .cerrar)
        XCTAssertNil(m.fase)

        m.abrir()
        _ = m.grabar(retardo: 5)
        XCTAssertEqual(m.esc(), .cerrar, "Esc en la cuenta cierra sin grabar")

        m.abrir()
        _ = m.grabar(retardo: 0)
        m.arrancado()
        _ = m.alternarPausa()
        XCTAssertEqual(m.esc(), .parar, "en pausa Esc guarda lo grabado")
    }

    func testElAtajoEmpiezaYLuegoPara() {
        var m = MaquinaGrabacion()
        XCTAssertEqual(m.atajo(retardo: 0), .nada, "sin sesion no hace nada")
        m.abrir()
        XCTAssertEqual(m.atajo(retardo: 0), .arrancar)
        XCTAssertEqual(m.atajo(retardo: 0), .nada, "arrancando, esperar")
        m.arrancado()
        XCTAssertEqual(m.atajo(retardo: 0), .parar)
        XCTAssertEqual(m.parar(), .parar)
    }

    func testSinGrabarNoSePausaNiSePara() {
        var m = MaquinaGrabacion()
        m.abrir()
        XCTAssertEqual(m.alternarPausa(), .nada)
        XCTAssertEqual(m.parar(), .nada)
        XCTAssertEqual(m.fase, .esperando)
    }

    // MARK: El reloj sin pausas

    private func s(_ x: Double) -> CMTime { CMTime(seconds: x, preferredTimescale: 1_000_000) }

    func testLasMuestrasDeLaPausaSeTiranYLasDeDespuesSeAdelantan() {
        var r = RelojPausas()
        XCTAssertEqual(r.ajustar(s(5)), s(5))
        r.pausar(s(10))
        XCTAssertTrue(r.enPausa)
        XCTAssertNil(r.ajustar(s(12)))
        r.reanudar(s(14))
        XCTAssertFalse(r.enPausa)
        XCTAssertEqual(r.ajustar(s(9)), s(9), "lo de antes no se toca")
        XCTAssertNil(r.ajustar(s(13)), "una muestra tardia de dentro de la pausa se tira")
        XCTAssertEqual(r.ajustar(s(15)), s(11))
        r.pausar(s(20))
        r.reanudar(s(21))
        XCTAssertEqual(r.ajustar(s(22)), s(17), "las dos pausas se suman")
    }

    func testLoGrabadoDeVerdadNoCuentaLasPausas() {
        var r = RelojPausas()
        r.pausar(s(10))
        r.reanudar(s(14))
        XCTAssertEqual(r.activo(desde: s(0), hasta: s(20)).seconds, 16, accuracy: 1e-6)
        XCTAssertEqual(r.activo(desde: s(12), hasta: s(20)).seconds, 6, accuracy: 1e-6)
        r.pausar(s(25))
        // La pausa abierta tampoco cuenta: el reloj de la barra se queda.
        XCTAssertEqual(r.activo(desde: s(0), hasta: s(30)).seconds, 21, accuracy: 1e-6)
        XCTAssertEqual(r.activo(desde: s(0), hasta: s(40)).seconds, 21, accuracy: 1e-6)
        XCTAssertEqual(r.activo(desde: s(5), hasta: s(1)), .zero)
    }

    // MARK: El marco

    private let zona = CGRect(x: 100, y: 100, width: 400, height: 300)

    func testElCentroDeLaZonaNoAgarraNada() {
        // Si no, el marco secuestraria los clics de la app que se graba.
        XCTAssertNil(MarcoAjustable.asa(en: CGPoint(x: 300, y: 250), zona: zona))
        XCTAssertNil(MarcoAjustable.asa(en: CGPoint(x: 0, y: 0), zona: zona))
    }

    func testCadaBordeYCadaEsquinaDanSuAsa() {
        let a = { (x: CGFloat, y: CGFloat) -> AsaMarco? in MarcoAjustable.asa(en: CGPoint(x: x, y: y), zona: self.zona) }
        XCTAssertEqual(a(96, 96), .norOeste)
        XCTAssertEqual(a(504, 96), .norEste)
        XCTAssertEqual(a(96, 404), .surOeste)
        XCTAssertEqual(a(504, 404), .surEste)
        XCTAssertEqual(a(300, 96), .norte)
        XCTAssertEqual(a(300, 404), .sur)
        XCTAssertEqual(a(96, 250), .oeste)
        XCTAssertEqual(a(504, 250), .este)
    }

    func testMoverNoCambiaElTamanoYUnaEsquinaSoloSusLados() {
        let m = MarcoAjustable.aplicar(.mover, a: zona, dx: 40, dy: -25)
        XCTAssertEqual(m, CGRect(x: 140, y: 75, width: 400, height: 300))
        let e = MarcoAjustable.aplicar(.norOeste, a: zona, dx: 10, dy: 20)
        XCTAssertEqual(e.maxX, 500)
        XCTAssertEqual(e.maxY, 400)
        XCTAssertEqual(e.origin, CGPoint(x: 110, y: 120))
    }

    func testLaZonaNuncaSeDaLaVuelta() {
        let o = MarcoAjustable.aplicar(.oeste, a: zona, dx: 1000, dy: 0)
        XCTAssertEqual(o.width, MarcoAjustable.ladoMinimo)
        XCTAssertEqual(o.maxX, 500)
        let s = MarcoAjustable.aplicar(.sur, a: zona, dx: 0, dy: -1000)
        XCTAssertEqual(s.height, MarcoAjustable.ladoMinimo)
        XCTAssertEqual(s.minY, 100)
    }

    func testLaZonaNoSeSaleDeLaPantalla() {
        let pantalla = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fuera = MarcoAjustable.limitar(CGRect(x: 1300, y: -50, width: 400, height: 300), a: pantalla)
        XCTAssertEqual(fuera, CGRect(x: 1040, y: 0, width: 400, height: 300))
        let enorme = MarcoAjustable.limitar(CGRect(x: -10, y: 0, width: 3000, height: 200), a: pantalla)
        XCTAssertEqual(enorme.width, 1440)
        XCTAssertEqual(enorme.minX, 0)
    }

    func testElRelojSeLeeDeUnVistazo() {
        XCTAssertEqual(MarcoAjustable.reloj(0), "0:00")
        XCTAssertEqual(MarcoAjustable.reloj(9.9), "0:09")
        XCTAssertEqual(MarcoAjustable.reloj(75), "1:15")
        XCTAssertEqual(MarcoAjustable.reloj(3725), "1:02:05")
    }
}

/// El editor de la grabacion (D7): recortar, cortar, velocidad, zoom y lo
/// que se exporta (`reproductor.rs`).
final class EditorGrabacionD7Tests: XCTestCase {
    func testSinTocarSeGuardaEntera() {
        let e = EdicionGrabacion(duracion: 10)
        XCTAssertTrue(e.sinCambios)
        XCTAssertEqual(e.tramos, [0...10])
        XCTAssertEqual(e.duracionFinal, 10)
    }

    func testRecortarNoCruzaLosExtremos() {
        var e = EdicionGrabacion(duracion: 10)
        e.ponerInicio(2)
        e.ponerFin(8)
        XCTAssertEqual(e.tramos, [2...8])
        XCTAssertFalse(e.sinCambios)
        // Caso negativo: el principio pasado el final se queda a un tramo.
        e.ponerInicio(9)
        XCTAssertEqual(e.inicio, 8 - EdicionGrabacion.tramoMinimo, accuracy: 1e-9)
        e.ponerFin(-5)
        XCTAssertEqual(e.fin, e.inicio + EdicionGrabacion.tramoMinimo, accuracy: 1e-9)
        e.ponerInicio(-3)
        XCTAssertEqual(e.inicio, 0)
    }

    func testDividirYQuitarUnTramoDeEnMedio() {
        var e = EdicionGrabacion(duracion: 10)
        XCTAssertTrue(e.dividir(en: 3))
        XCTAssertTrue(e.dividir(en: 6))
        XCTAssertFalse(e.dividir(en: 6.05), "pegado a otra division no")
        XCTAssertFalse(e.dividir(en: 0.01), "pegado al borde no")
        XCTAssertEqual(e.segmentos, [0...3, 3...6, 6...10])
        XCTAssertTrue(e.quitarSegmento(en: 4))
        XCTAssertEqual(e.tramos, [0...3, 6...10])
        XCTAssertEqual(e.duracionFinal, 7)
        XCTAssertTrue(e.quitado(4.5))
        XCTAssertFalse(e.quitado(6), "el borde de despues se guarda")
        XCTAssertTrue(e.restaurar(en: 4.5))
        XCTAssertEqual(e.tramos, [0...10])
    }

    func testNoSeQuitaLoUnicoQueQueda() {
        var e = EdicionGrabacion(duracion: 10)
        XCTAssertFalse(e.quitarSegmento(en: 5), "sin divisiones seria quitarlo todo")
        e.dividir(en: 5)
        XCTAssertTrue(e.quitarSegmento(en: 2))
        XCTAssertFalse(e.quitarSegmento(en: 7))
        XCTAssertEqual(e.tramos, [5...10])
    }

    func testLosQuitadosQueSeTocanSeJuntan() {
        var e = EdicionGrabacion(duracion: 10)
        e.dividir(en: 2); e.dividir(en: 4); e.dividir(en: 8)
        e.quitarSegmento(en: 3)
        e.quitarSegmento(en: 5)
        XCTAssertEqual(e.quitados, [2...8])
        XCTAssertEqual(e.tramos, [0...2, 8...10])
    }

    func testRecorteYCortesJuntos() {
        var e = EdicionGrabacion(duracion: 10)
        e.dividir(en: 1); e.dividir(en: 4)
        e.quitarSegmento(en: 2)
        e.ponerInicio(2)
        e.ponerFin(9)
        XCTAssertEqual(e.tramos, [4...9], "el corte que empieza antes del principio no deja un tramo raro")
    }

    func testLaVelocidadCambiaLoQueDuraYQueMomentoToca() {
        var e = EdicionGrabacion(duracion: 10)
        e.dividir(en: 3); e.dividir(en: 6)
        e.quitarSegmento(en: 4)
        XCTAssertEqual(e.original(enSalida: 0), 0)
        XCTAssertEqual(e.original(enSalida: 3.5), 6.5, accuracy: 1e-9, "salta lo quitado")
        e.siguienteVelocidad()
        XCTAssertEqual(e.velocidad, 2)
        XCTAssertEqual(e.duracionFinal, 3.5)
        XCTAssertEqual(e.original(enSalida: 2), 7, accuracy: 1e-9)
        XCTAssertEqual(e.original(enSalida: 99), 10, "pasado el final, el ultimo")
        e.siguienteVelocidad(); e.siguienteVelocidad()
        XCTAssertEqual(e.velocidad, 0.25, "da la vuelta")
    }

    func testLaVistaPreviaSaltaLoQuitadoYDaLaVuelta() {
        var e = EdicionGrabacion(duracion: 10)
        e.dividir(en: 3); e.dividir(en: 6)
        e.quitarSegmento(en: 4)
        e.ponerInicio(1)
        e.ponerFin(9)
        XCTAssertNil(e.salto(desde: 2))
        XCTAssertEqual(e.salto(desde: 0.5), 1, "antes del principio, al principio")
        XCTAssertEqual(e.salto(desde: 3), 6, "en lo quitado, a lo siguiente")
        XCTAssertEqual(e.salto(desde: 9), 1, "al acabar, vuelta a empezar")
    }

    func testElPasoAFotogramaSaltaLoQuitadoPorLosDosLados() {
        var e = EdicionGrabacion(duracion: 10)
        e.dividir(en: 3); e.dividir(en: 6)
        e.quitarSegmento(en: 4)
        let f = 1.0 / 30
        XCTAssertEqual(e.paso(desde: 3 - f / 2, adelante: true), 6)
        XCTAssertEqual(e.paso(desde: 6, adelante: false), 3 - f, accuracy: 1e-9)
        XCTAssertEqual(e.paso(desde: 0, adelante: false), 10 - f, accuracy: 1e-9, "da la vuelta")
        XCTAssertEqual(e.paso(desde: 10 - f / 2, adelante: true), 0, "y por el otro lado")
    }

    func testElZoomNoSeSaleDelVideo() {
        var e = EdicionGrabacion(duracion: 5)
        let tam = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(e.zonaVisible(en: tam), CGRect(origin: .zero, size: tam))
        XCTAssertEqual(e.transformacion(en: tam), .identity)
        e.zoom = 2
        e.centro = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(e.zonaVisible(en: tam), CGRect(x: 480, y: 270, width: 960, height: 540))
        // En la esquina, empujada para no salirse.
        e.centro = CGPoint(x: 1, y: 0)
        XCTAssertEqual(e.zonaVisible(en: tam), CGRect(x: 960, y: 0, width: 960, height: 540))
        // La transformacion lleva esa esquina al origen y la estira al doble.
        let t = e.transformacion(en: tam)
        XCTAssertEqual(CGPoint(x: 960, y: 0).applying(t), .zero)
        XCTAssertEqual(CGPoint(x: 1920, y: 540).applying(t), CGPoint(x: 1920, y: 1080))
    }

    func testElClicEnLoAcercadoCentraEseSitioDelVideo() {
        var e = EdicionGrabacion(duracion: 5)
        let tam = CGSize(width: 1000, height: 500)
        // Sin zoom, el clic es el sitio tal cual.
        e.centrar(enVista: CGPoint(x: 0.25, y: 0.5), tam: tam)
        XCTAssertEqual(e.centro, CGPoint(x: 0.25, y: 0.5))
        // A 2x se ve la mitad izquierda (centro 0.25, pegado al borde):
        // un clic en el centro de lo que se ve sigue siendo el 0.25.
        e.zoom = 2
        e.centrar(enVista: CGPoint(x: 0.5, y: 0.5), tam: tam)
        XCTAssertEqual(e.centro.x, 0.25, accuracy: 1e-9)
        // Y uno en el borde derecho de lo que se ve, el centro del video.
        e.centrar(enVista: CGPoint(x: 1, y: 0.5), tam: tam)
        XCTAssertEqual(e.centro.x, 0.5, accuracy: 1e-9)
    }

    func testElZoomDaLaVuelta() {
        var e = EdicionGrabacion(duracion: 5)
        for z in [1.5, 2, 3, 1] {
            e.siguienteZoom()
            XCTAssertEqual(e.zoom, z)
        }
    }

    func testElClicEnLaVistaPreviaVaALaFraccionDelVideo() {
        // Video 16:9 en una vista cuadrada: bandas arriba y abajo.
        let v = CGSize(width: 1600, height: 900)
        let vista = CGSize(width: 400, height: 400)
        let c = EdicionGrabacion.fraccion(de: CGPoint(x: 200, y: 200), vista: vista, video: v)
        XCTAssertEqual(c!.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c!.y, 0.5, accuracy: 1e-9)
        XCTAssertNil(EdicionGrabacion.fraccion(de: CGPoint(x: 200, y: 10), vista: vista, video: v), "en la banda no")
    }

    func testElGifTieneLosFotogramasDeLoGuardado() {
        var e = EdicionGrabacion(duracion: 4)
        e.dividir(en: 1); e.dividir(en: 3)
        e.quitarSegmento(en: 2)
        let m = e.momentosGif(porSegundo: 10)
        XCTAssertEqual(m.count, 20)
        XCTAssertEqual(m[0], 0)
        XCTAssertEqual(m[10], 3, accuracy: 1e-9, "salta lo quitado")
        e.velocidad = 2
        XCTAssertEqual(e.momentosGif(porSegundo: 10).count, 10)
    }

    func testDeshacerVuelveAtrasYNoGuardaLoQueNoCambia() {
        var h = HistorialEdicion(EdicionGrabacion(duracion: 10))
        XCTAssertFalse(h.puedeDeshacer)
        h.cambiar { $0.dividir(en: 5) }
        h.cambiar { _ = $0.quitarSegmento(en: 2) }
        h.cambiar { _ = $0.dividir(en: 5) }
        h.deshacer()
        XCTAssertEqual(h.actual.tramos, [0...10])
        XCTAssertEqual(h.actual.divisiones, [5])
        h.deshacer()
        XCTAssertFalse(h.puedeDeshacer)
    }

    func testUnArrastreEnteroEsUnSoloPasoDeDeshacer() {
        var h = HistorialEdicion(EdicionGrabacion(duracion: 10))
        h.cambiar { $0.ponerInicio(1) }
        h.retocar { $0.ponerInicio(2) }
        h.retocar { $0.ponerInicio(3) }
        XCTAssertEqual(h.actual.inicio, 3)
        h.deshacer()
        XCTAssertEqual(h.actual.inicio, 0)
        XCTAssertFalse(h.puedeDeshacer)
    }

    func testElFormatoYSuNombre() {
        XCTAssertEqual(FormatoGrabacion.mp4.siguiente, .gif)
        XCTAssertEqual(FormatoGrabacion.gif.siguiente, .mp4)
        XCTAssertEqual(FormatoGrabacion.gif.rotulo, "GIF")
        XCTAssertEqual(FormatoGrabacion.mp4.ext, "mp4")
    }
}

/// Exportar de verdad (sin pantalla): un MP4 hecho aqui, con un tramo
/// quitado, a 2x y con zoom, y lo mismo en GIF.
@MainActor
final class ExportarGrabacionD7Tests: XCTestCase {
    /// Un MP4 de `segundos` a 30 por segundo, cada segundo de un color.
    private func videoDePrueba(segundos: Int, ancho: Int = 320, alto: Int = 180) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("d7-\(UUID().uuidString).mp4")
        let escritor = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: ancho, AVVideoHeightKey: alto,
        ])
        let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ancho, kCVPixelBufferHeightKey as String: alto,
        ])
        escritor.add(entrada)
        XCTAssertTrue(escritor.startWriting())
        escritor.startSession(atSourceTime: .zero)
        for i in 0 ..< segundos * 30 {
            while !entrada.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var px: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptador.pixelBufferPool!, &px)
            let b = px!
            CVPixelBufferLockBaseAddress(b, [])
            let gris = UInt8((i / 30) * 80 % 256)
            memset(CVPixelBufferGetBaseAddress(b), Int32(gris), CVPixelBufferGetDataSize(b))
            CVPixelBufferUnlockBaseAddress(b, [])
            adaptador.append(b, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        entrada.markAsFinished()
        await escritor.finishWriting()
        XCTAssertEqual(escritor.status, .completed)
        return url
    }

    func testElMp4SaleSinLoQuitadoALaVelocidadYConElZoom() async throws {
        let fuente = try await videoDePrueba(segundos: 3)
        defer { try? FileManager.default.removeItem(at: fuente) }
        let asset = AVURLAsset(url: fuente)
        var e = EdicionGrabacion(duracion: try await asset.load(.duration).seconds)
        e.dividir(en: 1); e.dividir(en: 2)
        e.quitarSegmento(en: 1.5)
        e.velocidad = 2
        e.zoom = 2
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("d7-sale-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: destino) }
        try await ExportadorGrabacion.mp4(asset, edicion: e, tam: CGSize(width: 320, height: 180), a: destino)
        let sale = AVURLAsset(url: destino)
        let dura = try await sale.load(.duration).seconds
        XCTAssertEqual(dura, 1, accuracy: 0.1, "2 s guardados a 2x")
        let pista = try await sale.loadTracks(withMediaType: .video).first
        let tam = try await pista?.load(.naturalSize)
        XCTAssertEqual(tam, CGSize(width: 320, height: 180), "el zoom no cambia el tamano")
    }

    func testElGifTieneSusFotogramasYElTamanoDeLoQueSeVe() async throws {
        let fuente = try await videoDePrueba(segundos: 2)
        defer { try? FileManager.default.removeItem(at: fuente) }
        let asset = AVURLAsset(url: fuente)
        var e = EdicionGrabacion(duracion: try await asset.load(.duration).seconds)
        e.ponerFin(1)
        e.zoom = 2
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("d7-sale-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: destino) }
        try await ExportadorGrabacion.gif(asset, edicion: e, tam: CGSize(width: 320, height: 180), a: destino)
        let fuenteGif = try XCTUnwrap(CGImageSourceCreateWithURL(destino as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(fuenteGif), 10, "un segundo a 10 por segundo")
        let primera = try XCTUnwrap(CGImageSourceCreateImageAtIndex(fuenteGif, 0, nil))
        XCTAssertEqual(primera.width, 160, "a 2x se ve la mitad")
        XCTAssertEqual(primera.height, 90)
    }
}
