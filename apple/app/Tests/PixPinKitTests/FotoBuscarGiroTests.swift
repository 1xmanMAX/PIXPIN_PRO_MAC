// La foto del chat, buscar en todos los chats y el boton de sincronizar que
// gira (Windows 22bf4dc, d106969 y 0470294), por el puente de verdad.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class FotoBuscarGiroTests: XCTestCase {
    private func nucleo() throws -> (Nucleo, URL) {
        let raiz = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-foto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return (try Nucleo.abrir(raiz: raiz.path, nombreDelAparato: "Mac"), raiz)
    }

    func testLaFotoDeEmojiQuedaEnLaListaYComoSiempreLaQuita() throws {
        let (n, raiz) = try nucleo()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let chat = try n.crearChat(nombre: "Obra")
        XCTAssertNil(try n.chats().first { $0.id == chat.id }?.foto)
        let fondos = fondosDeLaFoto()
        XCTAssertEqual(fondos.count, 12)
        try n.ponerFotoEmoji(chat: chat.id, emoji: "🏗️", fondo: fondos[1])
        let foto = try XCTUnwrap(try n.chats().first { $0.id == chat.id }?.foto)
        XCTAssertEqual(foto.tipo, "emoji")
        XCTAssertEqual(foto.emoji, "🏗️")
        XCTAssertEqual(foto.arriba, 0xFFCD6A)
        XCTAssertEqual(foto.abajo, 0xFFA85C)
        // «Como siempre» se escribe, y se pinta como siempre.
        try n.ponerFotoIniciales(chat: chat.id, fondo: nil)
        XCTAssertNil(try n.chats().first { $0.id == chat.id }?.foto)
        XCTAssertTrue(emojisDeLaFoto(consulta: "casa").contains("🏠"))
        XCTAssertTrue(emojisDeLaFoto(consulta: "zzzz").isEmpty)
    }

    func testBuscarEnLosChatsYElFiltroSinTildes() throws {
        let (n, raiz) = try nucleo()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let chat = try n.crearChat(nombre: "Cimentación")
        _ = try n.escribirNota(chat: chat.id, texto: "Pedir cemento y arena", respondeA: nil)
        let r = n.buscadorEnChats().buscar(aguja: "CEMENTO", tope: 20)
        XCTAssertEqual(r.total, 1)
        XCTAssertEqual(r.mensajes.first?.chat, chat.id)
        XCTAssertEqual(r.mensajes.first?.tramos.first?.largo, 7)
        XCTAssertTrue(chatPasaElFiltro(nombre: "Cimentación", resumen: "", aguja: "cimentacion"))
        XCTAssertFalse(chatPasaElFiltro(nombre: "Casa", resumen: "", aguja: "obra"))
        XCTAssertEqual(rotulosDeBuscarEnChats(locale: "es-ES", total: 3, mas: 0).mensajes, "Mensajes · 3")
    }

    func testElBotonGiraMientrasHayVueltasYMarcaElFallo() {
        let e = EstadoDeLaVuelta()
        XCTAssertNil(e.desde)
        e.empieza()
        e.empieza()
        XCTAssertNotNil(e.desde)
        e.acaba(bien: false)
        XCTAssertNotNil(e.desde, "queda otra en marcha")
        e.acaba(bien: nil)
        XCTAssertNil(e.desde)
        XCTAssertTrue(e.fallo, "una cancelada no tapa el fallo")
        // Otra vuelta tapa el fallo de la anterior; pulsar el boton, tambien.
        e.empieza()
        XCTAssertFalse(e.fallo)
        e.acaba(bien: false)
        e.olvidarFallo()
        XCTAssertFalse(e.fallo)
    }
}
