// Grabar clase o reunion (Windows edd0ffa y 2cc497b) y «Enviar a Anki»
// (2561be0): la mezcla de las dos fuentes (la de `pixpin-audio`, al
// numero), la captura del minuto que suena, lo que se guarda en el chat
// (por el nucleo de verdad) y lo que se dice al mandar a Anki.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class GrabarClaseTests: XCTestCase {
    private let fs = 48_000
    private var cuarto: Int { fs / 4 }

    // MARK: La mezcla

    func testConLasDosALaParSeSumanMuestraAMuestra() {
        var m = MezcladorClase(fuentes: 2, muestreo: fs)
        m.empuja(0, [0.25, 0.5, 0.125])
        m.empuja(1, [0.25, 0.25])
        XCTAssertEqual(m.sacar(), [0.5, 0.75], "solo lo que tienen las dos")
        m.empuja(1, [0.125])
        XCTAssertEqual(m.sacar(), [0.25])
        XCTAssertEqual(m.enEspera, 0)
    }

    func testDosVocesAltasSeRecortan() {
        var m = MezcladorClase(fuentes: 2, muestreo: fs)
        m.empuja(0, [0.75, -0.75])
        m.empuja(1, [0.75, -0.75])
        XCTAssertEqual(m.sacar(), [1, -1])
    }

    func testElSonidoDelMacCalladoNoParaAlMicrofono() {
        var m = MezcladorClase(fuentes: 2, muestreo: fs)
        m.empuja(0, [Float](repeating: 0.5, count: cuarto / 2))
        XCTAssertTrue(m.sacar().isEmpty, "medio cuarto de segundo: aun se espera")
        m.empuja(0, [Float](repeating: 0.5, count: cuarto))
        let salio = m.sacar()
        XCTAssertFalse(salio.isEmpty)
        XCTAssertTrue(salio.allSatisfy { $0 == 0.5 }, "el microfono, con silencio debajo")
        // Caso negativo: no se lo come todo; deja algo por si llegaba tarde.
        XCTAssertTrue(m.enEspera > 0 && m.enEspera < cuarto)
    }

    func testLaNotaSigueAlRelojAunqueNoLlegueNada() {
        var m = MezcladorClase(fuentes: 1, muestreo: fs)
        m.alinear(escritas: 0, esperadas: Int64(fs))
        let salio = m.sacar()
        XCTAssertEqual(salio.count, fs)
        XCTAssertTrue(salio.allSatisfy { $0 == 0 })
        // Caso negativo: dentro de la holgura no se mete nada.
        var n = MezcladorClase(fuentes: 1, muestreo: fs)
        n.alinear(escritas: 0, esperadas: Int64(cuarto / 2))
        XCTAssertEqual(n.enEspera, 0)
    }

    func testAlPararSaleTodoYEnPausaSeTira() {
        var m = MezcladorClase(fuentes: 2, muestreo: fs)
        m.empuja(0, [0.25, 0.5, 0.75])
        m.empuja(1, [0.25])
        XCTAssertEqual(m.resto(), [0.5, 0.5, 0.75])
        m.empuja(0, [Float](repeating: 0.5, count: 10))
        m.vaciar()
        XCTAssertEqual(m.enEspera, 0)
        XCTAssertTrue(m.resto().isEmpty)
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

    func testElVideoSeGrabaAlTamanoYRitmoDeWindows() {
        let v = videoDeLaClase(anchoPantalla: 2880, altoPantalla: 1800)
        XCTAssertEqual(v.ancho, 1152)
        XCTAssertEqual(v.alto, 720)
        XCTAssertEqual(v.porSegundo, 10)
        XCTAssertEqual(fotogramasDebidosDeLaClase(muestras: 48_000, muestreo: 48_000), 11)
        // Caso negativo: un fotograma negro sale aunque la pantalla no de
        // ninguna imagen.
        XCTAssertNotNil(VideoDeClase.negro(ancho: Int(v.ancho), alto: Int(v.alto)))
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

    func testLoQueSeDiceAlMandarAAnkiEsLoDeWindows() {
        XCTAssertEqual(ChatAbierto.textoDeAnki(.hecho(n: 3, mazo: "PixPin::Física")),
                       "3 tarjetas en Anki, mazo «PixPin::Física»")
        XCTAssertEqual(ChatAbierto.textoDeAnki(.yaEstaban(n: 3, mazo: "PixPin::Física")),
                       "Esas tarjetas ya estaban en «PixPin::Física»")
        XCTAssertTrue(ChatAbierto.textoDeAnki(.fichero(n: 2, mazo: "m", ruta: "/x/a.txt")).contains("/x/a.txt"))
        XCTAssertTrue(ChatAbierto.textoDeAnki(.nada).hasPrefix("Aquí no hay tarjetas"))
    }
}
