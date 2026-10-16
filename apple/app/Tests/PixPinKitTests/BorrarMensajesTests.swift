// Borrar mensajes del chat: por el `Almacen` (que cruza el puente de
// verdad) y la eleccion de varios con ⌘-clic y ⇧-clic.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class BorrarMensajesTests: XCTestCase {
    func testBorrarQuitaLosMensajesDeLoCargadoYDelDiscoConSuFichero() async throws {
        let raiz = try carpetaTemporal("borrar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        await almacen.abrir(chat: chat)

        let escrita = await almacen.escribir(nota: "primera", en: chat)
        let primera = try XCTUnwrap(escrita)
        let fuera = raiz.appendingPathComponent("fuera", isDirectory: true)
        try FileManager.default.createDirectory(at: fuera, withIntermediateDirectories: true)
        let texto = fuera.appendingPathComponent("medidas.txt")
        try Data("3,20 x 2,10".utf8).write(to: texto)
        let adjuntos = await almacen.adjuntar(urls: [texto], en: chat)
        let adjunto = try XCTUnwrap(adjuntos.first)
        let otraEscrita = await almacen.escribir(nota: "ultima", en: chat)
        let ultima = try XCTUnwrap(otraEscrita)
        let ruta = try XCTUnwrap(adjunto.ruta)
        let resuelta = await almacen.url(deRuta: ruta, en: chat)
        let copia = try XCTUnwrap(resuelta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copia.path))
        let totalAntes = try XCTUnwrap(almacen.totales[chat])

        let n = await almacen.borrar(mensajes: [primera.id, adjunto.id], en: chat)
        XCTAssertEqual(n, 2)
        XCTAssertNil(almacen.error)
        XCTAssertEqual(almacen.mensajes[chat]?.map(\.id), [ultima.id], "solo queda la ultima")
        XCTAssertEqual(almacen.totales[chat], totalAntes - 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copia.path), "el adjunto se borra con su mensaje")
        XCTAssertNil(almacen.urlResuelta(deRuta: "archivos/medidas.txt", en: chat))

        // Al volver a abrir el chat siguen fuera (estan fuera del cuaderno).
        await almacen.abrir(chat: chat)
        XCTAssertEqual(almacen.mensajes[chat]?.map(\.id), [ultima.id])

        // Caso negativo: lo que no esta no se borra ni da error.
        let otra = await almacen.borrar(mensajes: ["no-existe"], en: chat)
        XCTAssertEqual(otra, 0)
        XCTAssertNil(almacen.error)
        XCTAssertEqual(almacen.mensajes[chat]?.count, 1)
        let nada = await almacen.borrar(mensajes: [], en: chat)
        XCTAssertEqual(nada, 0)
    }

    func testElegirVariosConCmdYShiftYOlvidarLoQueYaNoEsta() {
        let orden = ["a", "b", "c", "d", "e"]
        var e = Eleccion()
        XCTAssertTrue(e.vacia)
        e.alternar("b")
        e.tramo(hasta: "d", en: orden)
        XCTAssertEqual(e.enOrden(orden), ["b", "c", "d"])
        e.alternar("c")
        XCTAssertEqual(e.enOrden(orden), ["b", "d"], "⌘-clic en una elegida la suelta")
        // Hacia atras tambien.
        e.tramo(hasta: "a", en: orden)
        XCTAssertEqual(e.enOrden(orden), ["a", "b", "c", "d"])
        e.quedarse(con: ["a", "d", "e"])
        XCTAssertEqual(e.enOrden(orden), ["a", "d"])
        // Caso negativo: sin ancla que se vea, ⇧-clic solo elige esa.
        var f = Eleccion()
        f.tramo(hasta: "c", en: orden)
        XCTAssertEqual(f.enOrden(orden), ["c"])
        f.vaciar()
        XCTAssertTrue(f.vacia)
    }

    func testLaPreguntaDiceLoMismoQueWindowsYCuantos() {
        XCTAssertEqual(ConfirmarBorrar.titulo(cuantos: 1), "Borrar")
        XCTAssertEqual(ConfirmarBorrar.titulo(cuantos: 3), "Borrar 3 mensajes")
        XCTAssertTrue(ConfirmarBorrar.aviso.contains("adjunto se borra"))
        XCTAssertEqual(Almacen.sin(["x"], en: []).count, 0)
    }
}
