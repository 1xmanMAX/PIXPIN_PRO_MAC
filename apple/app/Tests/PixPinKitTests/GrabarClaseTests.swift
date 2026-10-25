// Grabar clase o reunion (Windows edd0ffa y 2cc497b) y «Enviar a Anki»
// (2561be0): la mezcla de las dos fuentes (la del motor de audio de
// Windows, por el nucleo), el motor de video (perfil, cadena y ritmo), la
// captura del minuto que suena, lo que se guarda en el chat (por el nucleo
// de verdad) y lo que se dice al mandar a Anki.

import AVFoundation
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class GrabarClaseTests: XCTestCase {
    private let fs = 48_000

    // MARK: La mezcla

    func testLaMezclaDelNucleoVaAlRelojYNoSaleAntesDeEmpezar() throws {
        let m = try MezclaDeAudio.nueva(fuentes: [FuenteDeMezcla(papel: .microfono, muestreo: 44_100, canales: 2),
                                                  FuenteDeMezcla(papel: .equipo, muestreo: 48_000, canales: 2)],
                                        muestreo: UInt32(fs))
        // Un bloque estereo separado, como lo da AVAudioPCMBuffer.
        XCTAssertEqual(m.empujar(fuente: 0, muestras: [Float](repeating: 0.25, count: 882 * 2), canales: 2,
                                 separadas: true), 882)
        // Lo que llego antes de empezar es de antes de empezar.
        let primero = m.mezclar()
        XCTAssertEqual(primero.posicion, 0)
        XCTAssertTrue(primero.muestras.isEmpty)
        XCTAssertEqual(m.llevadoMs(), 0)
        // Caso negativo: una fuente que no existe no entra, ni una salida
        // que el AAC no admite.
        XCTAssertEqual(m.empujar(fuente: 7, muestras: [0, 0], canales: 1, separadas: false), 0)
        XCTAssertThrowsError(try MezclaDeAudio.nueva(fuentes: [], muestreo: UInt32(fs)))
        XCTAssertThrowsError(try MezclaDeAudio.nueva(
            fuentes: [FuenteDeMezcla(papel: .microfono, muestreo: 48_000, canales: 1)], muestreo: 32_000))
    }

    func testUnBloqueMezcladoSeEscribeComoMonoDeLaNota() throws {
        let formato = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MezclaVoz.muestreo,
                                                  channels: 1, interleaved: false))
        let b = try XCTUnwrap(MezclaVoz.bloque([0.5, -0.25, 0.125], formato: formato))
        XCTAssertEqual(b.frameLength, 3)
        XCTAssertEqual(b.floatChannelData?[0][1], -0.25)
        // Caso negativo: nada no da bloque.
        XCTAssertNil(MezclaVoz.bloque([], formato: formato))
    }

    // MARK: La captura del minuto

    func testLaCapturaDelMomentoEsLaUltimaHechaAntes() {
        let c = [CapturaDeLaClase(ms: 2_000, id: "a", ruta: nil), CapturaDeLaClase(ms: 9_000, id: "b", ruta: nil)]
        XCTAssertEqual(ClaseEnElChat.enElMinuto(c, posicionMs: 500), 0, "antes de la primera, la primera")
        XCTAssertEqual(ClaseEnElChat.enElMinuto(c, posicionMs: 9_000), 1)
        XCTAssertEqual(ClaseEnElChat.enElMinuto(c, posicionMs: 8_999), 0)
        XCTAssertNil(ClaseEnElChat.enElMinuto([], posicionMs: 1_000))
    }

    // MARK: El video

    func testElVideoSeGrabaConElPerfilYLaCadenaDeWindows() {
        // Una Retina 16:10 en «Normal»: 1080 de alto y 15 fps, por la grafica
        // primero y el modo sencillo al final.
        let caminos = caminosDelVideo(perfil: .normal, anchoPantalla: 2880, altoPantalla: 1800, hayHardware: true)
        let primero = caminos.first
        XCTAssertEqual(primero?.codificador, .hardware)
        XCTAssertEqual(primero?.ancho, 1728)
        XCTAssertEqual(primero?.alto, 1080)
        XCTAssertEqual(primero?.porSegundo, 15)
        XCTAssertEqual(caminos.last?.codificador, .cpu)
        XCTAssertEqual(perfilDelVideoSiguiente(perfil: .nitido), .ligero)
        XCTAssertEqual(rotuloDeCalidad(perfil: .nitido), "Nítido")
        XCTAssertEqual(videoCon(codificador: .software), "Vídeo con el procesador")
        // Caso negativo: un fotograma negro sale aunque la pantalla no de
        // ninguna imagen, y sin grafica no se intenta.
        XCTAssertNotNil(VideoDeClase.negro(ancho: 1728, alto: 1080))
        XCTAssertFalse(caminosDelVideo(perfil: .ligero, anchoPantalla: 1280, altoPantalla: 720, hayHardware: false)
            .contains { $0.codificador == .hardware })
    }

    func testElRitmoDelVideoEsperaYRepiteCadaSegundo() {
        let s: Int64 = 10_000_000
        let r = RitmoDelVideo.nuevo(muestreo: 0, porSegundo: 15, ahora: 0)
        XCTAssertEqual(r.paso(ahora: 0, horaRetenida: 0).accion, .nuevo)
        XCTAssertEqual(r.paso(ahora: s / 2, horaRetenida: nil).accion, .esperar)
        XCTAssertEqual(r.paso(ahora: s, horaRetenida: nil).accion, .repetir)
        // Caso negativo: en pausa no se escribe nada.
        r.pausar(pausa: true, ahora: s)
        XCTAssertEqual(r.paso(ahora: 3 * s, horaRetenida: 3 * s).accion, .esperar)
    }

    // MARK: Lo que queda en el chat

    @MainActor
    func testLaClaseEntraEnElChatConSusCapturas() async throws {
        let raiz = try carpetaTemporal("grabar-clase")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Física")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Física" }).id
        let audio = raiz.appendingPathComponent("clase.m4a")
        try Data("m4a".utf8).write(to: audio)
        let png = raiz.appendingPathComponent("a.png")
        try Data("png".utf8).write(to: png)
        let mp4 = raiz.appendingPathComponent("clase.m4a.video.mp4")
        try Data("mp4".utf8).write(to: mp4)
        let hecho = try almacen.nucleo.guardarClase(chat: chat, rutaAudio: audio.path, duracionMs: 60_000, picos: [1, 2],
                                                    rutaVideo: mp4.path,
                                                    capturas: [CapturaClase(ms: 65_400, rutaPng: png.path)], desfaseMs: 0)
        let voz = try XCTUnwrap(hecho.voz)
        XCTAssertEqual(voz.clase, "VOZ")
        XCTAssertTrue(voz.nombre.hasPrefix("Clase "))
        XCTAssertEqual(hecho.capturas.count, 1)
        let pie = try XCTUnwrap(hecho.capturas.first?.texto)
        XCTAssertTrue(pie.hasPrefix("⏱ 1:05 · Clase "), pie)
        // El video, detras de la voz, como un archivo `Clase ….mp4` (movido).
        let video = try XCTUnwrap(hecho.video)
        XCTAssertEqual(video.clase, "ARCHIVO")
        XCTAssertTrue(video.nombre.hasPrefix("Clase ") && video.nombre.hasSuffix(".mp4"), video.nombre)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mp4.path))
        let lista = ClaseEnElChat.capturas(voz, chat: chat, nucleo: almacen.nucleo)
        XCTAssertEqual(lista.map(\.ms), [65_400])
        XCTAssertNotNil(lista.first?.ruta)
        // Caso negativo: una foto suelta no es una clase.
        let foto = try XCTUnwrap(hecho.capturas.first)
        XCTAssertTrue(ClaseEnElChat.capturas(foto, chat: chat, nucleo: almacen.nucleo).isEmpty)

        // «Estudiar la clase» sale en la nota, en su captura (en su minuto)
        // y en su video, y abre la nota.
        XCTAssertEqual(ClaseEnElChat.deUnaClase(voz, chat: chat, nucleo: almacen.nucleo)?.voz, voz.id)
        let enLaFoto = try XCTUnwrap(ClaseEnElChat.deUnaClase(foto, chat: chat, nucleo: almacen.nucleo))
        XCTAssertEqual(enLaFoto.voz, voz.id)
        XCTAssertEqual(enLaFoto.ms, 65_400)
        XCTAssertEqual(ClaseEnElChat.deUnaClase(video, chat: chat, nucleo: almacen.nucleo)?.ms, 0)
        let clase = try almacen.nucleo.claseParaEstudiar(chat: chat, mensaje: foto.id)
        XCTAssertEqual(clase.id, voz.id)
        XCTAssertEqual(clase.capturas.map(\.ms), [65_400])
        XCTAssertNotNil(clase.video)
        // Un marcador con nota queda en la nota y se quita.
        let marcada = try almacen.nucleo.ponerMarcadorDeClase(chat: chat, voz: voz.id, ms: 3_000, texto: "ojo")
        XCTAssertEqual(marcada.senales.map(\.texto), ["ojo"])
        XCTAssertTrue(try almacen.nucleo.quitarSenalDeClase(chat: chat, voz: voz.id, ms: 3_000).senales.isEmpty)

        // «Enviar a Anki» sale en la clase y en una nota con tarjetas.
        let c = ChatAbierto(chat: chat, almacen: almacen)
        XCTAssertTrue(c.sePuedeAnki(voz))
        let escrita = await almacen.escribir(nota: "capital :: Lima", en: chat)
        let nota = try XCTUnwrap(escrita)
        XCTAssertTrue(c.sePuedeAnki(nota))
        let otra = await almacen.escribir(nota: "un párrafo suelto", en: chat)
        let suelta = try XCTUnwrap(otra)
        XCTAssertFalse(c.sePuedeAnki(suelta), "sin preguntas no hay tarjetas")
    }

    func testLosDosModosYLasCuentasDeEstudiar() {
        XCTAssertEqual(otroModoDeGrabar(modo: .pantalla), .capturas)
        XCTAssertEqual(otroModoDeGrabar(modo: .capturas), .pantalla)
        // Un clic cerca de una captura se queda en ella; lejos, donde se pulso.
        XCTAssertEqual(clasePegarASenal(x: 51, ancho: 100, duracionMs: 60_000, senales: [30_000], tolerancia: 3), 30_000)
        XCTAssertEqual(clasePegarASenal(x: 60, ancho: 100, duracionMs: 60_000, senales: [30_000], tolerancia: 3), 36_000)
        XCTAssertTrue(ModeloEstudiar.esAMano(.interacting))
        // Caso negativo: el scroll que sigue al sonido no es mover a mano.
        XCTAssertFalse(ModeloEstudiar.esAMano(.animating))
        XCTAssertFalse(ModeloEstudiar.esAMano(.idle))
    }

    func testLoQueSeDiceAlMandarAAnkiEsLoDeWindows() {
        XCTAssertEqual(ChatAbierto.textoDeAnki(.hecho(n: 3, mazo: "PixPin::Física")),
                       "3 tarjetas en Anki, mazo «PixPin::Física»")
        XCTAssertEqual(ChatAbierto.textoDeAnki(.yaEstaban(n: 3, mazo: "PixPin::Física")),
                       "Esas tarjetas ya estaban en «PixPin::Física»")
        XCTAssertTrue(ChatAbierto.textoDeAnki(.fichero(n: 2, mazo: "m", ruta: "/x/a.txt")).contains("/x/a.txt"))
        XCTAssertTrue(ChatAbierto.textoDeAnki(.nada).hasPrefix("Aquí no hay tarjetas"))
    }
}
