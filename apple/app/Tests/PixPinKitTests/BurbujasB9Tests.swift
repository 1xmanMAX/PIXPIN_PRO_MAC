// Lo que llega al chat y antes no se veia (B9): la hoja-pagina, el
// proyecto entero, el croquis 3D, la foto anotada en el movil y lo de
// debajo de la burbuja (punto de proyecto, de donde viene, de quien llego).

import CoreGraphics
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class BurbujasB9Tests: XCTestCase {
    /// Un chat «Obra» con estas lineas de cuaderno (como las deja la
    /// sincronizacion), ya abierto en el almacen.
    private func chatCon(_ lineas: [String], en raiz: URL) async throws -> (Almacen, String, URL) {
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        let carpeta = raiz.appendingPathComponent("datos/proyectos/\(chat)", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data((lineas.joined(separator: "\n") + "\n").utf8)
            .write(to: carpeta.appendingPathComponent("guardados.jsonl"))
        await almacen.abrir(chat: chat)
        return (almacen, chat, carpeta)
    }

    func testLoQueTraeElMovilLlegaALaBurbujaConSuPunto() async throws {
        let raiz = try carpetaTemporal("b9-campos")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let (almacen, chat, _) = try await chatCon([
            #"{"id":"1","cuando":1,"clase":"IMAGEN","ruta":"archivos/f.png","nombre":"f.png","recibidoDe":"Max phone · K7Q2","vieneDe":{"texto":"PDF «Plano» → página 3","dibujo":"D1"},"soloLaFoto":false}"#,
            #"{"id":"2","cuando":2,"clase":"NOTA","texto":"hola","lienzoIa":"dib-ia"}"#,
            #"{"id":"3","cuando":3,"clase":"PROYECTO","referencia":"no-existe","nombre":"Casa"}"#,
            #"{"id":"4","cuando":4,"clase":"CROQUIS","referencia":"cr-1","texto":"Escalera\nde caracol"}"#,
        ], en: raiz)
        let m = try XCTUnwrap(almacen.mensajes[chat])
        XCTAssertEqual(m.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(m[0].recibidoDe, "Max phone · K7Q2")
        XCTAssertEqual(m[0].vieneDe, "PDF «Plano» → página 3")
        XCTAssertEqual(m[0].vieneDeDibujo, "D1")
        XCTAssertFalse(m[0].soloLaFoto)
        XCTAssertEqual(m[0].punto, false, "una foto solo en el chat: rojo")
        XCTAssertEqual(m[1].lienzoIa, "dib-ia")
        XCTAssertNil(m[1].punto, "una nota no lleva punto")
        XCTAssertEqual(m[2].punto, false, "un proyecto que ya no existe: rojo")
        XCTAssertEqual(m[3].punto, false)
        XCTAssertEqual(BurbujaCroquis.titulo(m[3]), "Escalera")
        // El croquis aun no ha llegado: no se puede abrir.
        XCTAssertNil(almacen.nucleo.croquisDelChat(chat: chat, referencia: "cr-1"))
        XCTAssertThrowsError(try almacen.nucleo.abrirCroquis(chat: chat, referencia: "cr-1"))
    }

    func testUnProyectoQueExisteSaleVerde() async throws {
        let raiz = try carpetaTemporal("b9-proyecto")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Casa")
        let casa = try XCTUnwrap(almacen.chats.first { $0.nombre == "Casa" }).id
        let carpeta = raiz.appendingPathComponent("datos/proyectos/\(casa)", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data(#"{"id":"p","cuando":1,"clase":"PROYECTO","referencia":"\#(casa)","nombre":"Casa"}"#.utf8 + Data("\n".utf8))
            .write(to: carpeta.appendingPathComponent("guardados.jsonl"))
        await almacen.abrir(chat: casa)
        XCTAssertEqual(almacen.mensajes[casa]?.first?.punto, true)
    }

    func testLaHojaPaginaDiceSuFondoYAbrirlaEstrenaSuDibujo() async throws {
        let raiz = try carpetaTemporal("b9-pagina")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let (almacen, chat, carpeta) = try await chatCon([
            #"{"id":"p1","cuando":1,"clase":"PAGINA","pagina":0,"nombre":"Plano · 1"}"#,
        ], en: raiz)
        try Data(#"{"id":"X","nombre":"Obra","hojas":[{"id":"h1","pagina":0}],"delMovil":1}"#.utf8)
            .write(to: carpeta.appendingPathComponent("proyecto.json"))
        // Sin documento ni imagen: no hay nada que ensenar.
        XCTAssertNil(try almacen.nucleo.hojaDePagina(chat: chat, id: "p1"))
        let png = carpeta.appendingPathComponent("archivos/pagina-01.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        try escribirPNG(png, ancho: 60, alto: 80)
        let hoja = try XCTUnwrap(almacen.nucleo.hojaDePagina(chat: chat, id: "p1"))
        XCTAssertEqual(hoja.imagen.map { URL(fileURLWithPath: $0).lastPathComponent }, "pagina-01.png")
        XCTAssertNil(hoja.pdf)
        XCTAssertNil(hoja.dibujo)
        let leida = PaginaLeida(hoja: hoja, dibujo: nil)
        XCTAssertEqual(leida.fuente, .imagen(URL(fileURLWithPath: hoja.imagen!)))
        // Abrirla para dibujar: dibujo nuevo, en su hoja y en su mensaje.
        let dibujo = try XCTUnwrap(almacen.nucleo.estrenarDibujoDePagina(chat: chat, id: "p1"))
        XCTAssertTrue(dibujo.hasPrefix("dib-"))
        XCTAssertEqual(try almacen.nucleo.hojaDePagina(chat: chat, id: "p1")?.dibujo, dibujo)
        let proyecto = try String(contentsOf: carpeta.appendingPathComponent("proyecto.json"), encoding: .utf8)
        XCTAssertTrue(proyecto.contains(dibujo))
        XCTAssertTrue(proyecto.contains("delMovil"), "lo que no se entiende sigue")
    }

    func testLaFotoAnotadaSeLeeDeSuLienzoPropio() async throws {
        let raiz = try carpetaTemporal("b9-foto")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let (almacen, chat, carpeta) = try await chatCon([
            #"{"id":"m1","cuando":1,"clase":"IMAGEN","ruta":"archivos/f.png","nombre":"f.png"}"#,
        ], en: raiz)
        let png = carpeta.appendingPathComponent("archivos/f.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        try escribirPNG(png, ancho: 40, alto: 30)
        let m = try XCTUnwrap(almacen.mensajes[chat]?.first)
        XCTAssertEqual(lienzoDeLaFoto(m), "foto-m1")
        // Sin lienzo: la foto sola.
        XCTAssertNil(try almacen.nucleo.fotoAnotada(chat: chat, lienzo: "foto-m1"))
        let anotada = await leerFotoAnotada(m, chat: chat, almacen: almacen)
        XCTAssertNil(anotada)
        // «Anotar encima» le estrena su lienzo, con la foto dentro.
        let id = try almacen.nucleo.asegurarLienzoDeFoto(chat: chat, id: "m1")
        XCTAssertEqual(id, "foto-m1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: carpeta.appendingPathComponent("lienzos/foto-m1.excalidraw").path))
        // Solo con la foto aun no hay nada dibujado que ensenar.
        XCTAssertNil(try almacen.nucleo.fotoAnotada(chat: chat, lienzo: id))
        XCTAssertThrowsError(try almacen.nucleo.fotoAnotada(chat: chat, lienzo: "../x"))
    }

    func testLaCajaDeLaFotoAnotadaRecortaALaFotoSalvoQueSePidaTodo() {
        let foto = CGRect(x: 0, y: 0, width: 100, height: 80)
        let todo = CGRect(x: -20, y: 10, width: 150, height: 50)
        XCTAssertEqual(cajaDeFotoAnotada(foto: foto, todo: todo, soloLaFoto: true), foto)
        XCTAssertEqual(cajaDeFotoAnotada(foto: foto, todo: todo, soloLaFoto: false),
                       CGRect(x: -20, y: 0, width: 150, height: 80))
        // Sin foto en el lienzo, lo dibujado.
        XCTAssertEqual(cajaDeFotoAnotada(foto: nil, todo: todo, soloLaFoto: true), todo)
        XCTAssertNil(cajaDeFotoAnotada(foto: nil, todo: nil, soloLaFoto: true))
    }

    func testIconosDeLasClasesNuevas() {
        XCTAssertEqual(Burbuja.icono("PROYECTO"), "folder")
        XCTAssertEqual(Burbuja.icono("CROQUIS"), "cube.transparent")
        XCTAssertEqual(Burbuja.icono("COSA_NUEVA"), "doc", "lo que no se conoce sigue saliendo")
    }
}
