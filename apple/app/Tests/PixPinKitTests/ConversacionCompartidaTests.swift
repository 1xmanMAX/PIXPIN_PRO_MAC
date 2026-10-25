// Un chat compartido como conversacion (`Chat/ConversacionCompartida.swift`,
// Windows b89c058 y e3f1d60): el «+» lo crea compartido conmigo dentro, la
// chapa lo ve y lo mio va a la derecha, por el puente de verdad.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class ConversacionCompartidaTests: XCTestCase {
    func testElChatCompartidoNaceConmigoDentroYLoMioVaALaDerecha() async throws {
        let raiz = try carpetaTemporal("conversacion-compartida")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let nuevo = try almacen.nucleo.crearChatCompartido(nombre: "Tesis")
        XCTAssertTrue(nuevo.compartido)
        let chapas = try almacen.nucleo.chapasDeCompartidos()
        XCTAssertEqual(chapas.map(\.ficha), [nuevo.ficha.id])
        XCTAssertEqual(TextosCompartido.chapa(chapas[0].personas), "Compartido · 1 persona")
        XCTAssertEqual(TextosCompartido.chapa(3), "Compartido · 3 personas")

        let escrita = await almacen.escribir(nota: "hola", en: nuevo.ficha.id)
        let m = try XCTUnwrap(escrita)
        XCTAssertNotNil(m.aparato, "lo escrito aqui lleva el codigo de este aparato")
        let c = try XCTUnwrap(almacen.nucleo.conversacionDelChat(
            ficha: nuevo.ficha.id,
            mensajes: [AutoriaDeMensaje(id: m.id, cuando: m.cuando, aparato: m.aparato)],
            desfaseMs: desfaseLocalMs()))
        XCTAssertEqual(c.personas, 1)
        XCTAssertEqual(c.lados.first?.mio, true)
        XCTAssertNil(c.lados.first?.nombre)

        // Caso negativo: un chat normal no tiene lados, se ve como siempre.
        await almacen.crearChat(nombre: "Casa")
        let casa = try XCTUnwrap(almacen.chats.first { $0.nombre == "Casa" }).id
        XCTAssertNil(try almacen.nucleo.conversacionDelChat(ficha: casa, mensajes: [], desfaseMs: 0))
    }
}
