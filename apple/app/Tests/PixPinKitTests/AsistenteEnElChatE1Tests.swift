// Pruebas del asistente en el chat (E1), sin modelo ni red: el turno lo
// hace `AsistenteEnElChat.turnoDePrueba`, que escribe la respuesta con el
// nucleo de verdad (`iaResponder`). Las del turno con el motor guionado
// estan en Rust (`asistente/en_la_conversacion/pruebas.rs`).

import Foundation
import PixPinCore
import XCTest
@testable import PixPinKit

@MainActor
final class AsistenteEnElChatE1Tests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated { AsistenteEnElChat.turnoDePrueba = nil }
        super.tearDown()
    }

    private func almacen(_ nombre: String) async throws -> (Almacen, String) {
        let dir = try carpetaTemporal("e1-" + nombre)
        let a = try Almacen(raiz: dir, nombreDelAparato: "Mac de prueba")
        await a.cargarChats()
        await a.asegurarAsistente()
        let chat = try XCTUnwrap(a.chats.first { $0.esAsistente }, "el chat «Asistente» existe").id
        await a.abrir(chat: chat)
        return (a, chat)
    }

    /// Un turno que contesta `texto` (y apunta lo que vio).
    private func contesta(_ texto: String) {
        AsistenteEnElChat.turnoDePrueba = { nucleo, chat, inicio, oyente, _, _ in
            oyente.vivo(v: VivoIa(nota: inicio.respuesta.id, texto: "Escribiendo ▍",
                                  pensado: PensadoIa(pensamiento: "", segundos: nil, pensando: false,
                                                     entiendo: "", hare: "", reinicio: false),
                                  pregunta: nil, acabado: false))
            let r = try nucleo.iaResponder(chat: chat, nota: inicio.respuesta.id, texto: texto, lienzo: nil)
            return FinChatIa(respuesta: r, abrirLienzo: nil)
        }
    }

    func testElChatAsistenteExisteUnaVezYVaDetrasDeGuardados() async throws {
        let (a, chat) = try await almacen("fijo")
        _ = try a.nucleo.chatGuardados()
        await a.asegurarAsistente()
        await a.cargarChats()
        XCTAssertEqual(a.chats.filter(\.esAsistente).count, 1)
        XCTAssertEqual(a.chats.map(\.nombre).prefix(2), ["Mensajes guardados", "Asistente"])
        XCTAssertEqual(try a.nucleo.chatAsistente().id, chat)
    }

    func testEnSuChatContestaEnUnaNotaDelAsistente() async throws {
        let (a, chat) = try await almacen("contesta")
        contesta("Hola, soy el asistente.")
        let mE = await a.escribir(nota: "hola", en: chat)
        let m = try XCTUnwrap(mE)
        let turnos = AsistenteEnElChat.compartido.alEnviar([m], chat: chat, almacen: a)
        XCTAssertEqual(turnos.count, 1)
        XCTAssertTrue(AsistenteEnElChat.compartido.ocupado(chat), "ocupado desde que se envia")
        for t in turnos { await t.value }
        XCTAssertFalse(AsistenteEnElChat.compartido.ocupado(chat))
        let ultimo = try XCTUnwrap(a.mensajes[chat]?.last)
        XCTAssertEqual(ultimo.texto, "Hola, soy el asistente.")
        XCTAssertTrue(ultimo.esDelAsistente, "su chapa es ·IA: \(ultimo.codigoChat ?? "-")")
        XCTAssertNil(AsistenteEnElChat.compartido.vivos[ultimo.id], "acabado, ya no esta en vivo")
        // Su propia respuesta no se contesta a si misma.
        XCTAssertTrue(AsistenteEnElChat.compartido.alEnviar([ultimo], chat: chat, almacen: a).isEmpty)
    }

    func testEnOtroChatSoloConLaMencionYCuelgaDeLaPregunta() async throws {
        let (a, _) = try await almacen("mencion")
        await a.crearChat(nombre: "obra")
        let obra = try XCTUnwrap(a.chats.first { $0.nombre == "obra" }).id
        await a.abrir(chat: obra)
        contesta("Dicen hola.")
        let holaE = await a.escribir(nota: "hola a todos", en: obra)
        let hola = try XCTUnwrap(holaE)
        XCTAssertTrue(AsistenteEnElChat.compartido.alEnviar([hola], chat: obra, almacen: a).isEmpty)
        let preguntaE = await a.escribir(nota: "@asistente resume esto", en: obra)
        let pregunta = try XCTUnwrap(preguntaE)
        for t in AsistenteEnElChat.compartido.alEnviar([pregunta], chat: obra, almacen: a) { await t.value }
        let r = try XCTUnwrap(a.mensajes[obra]?.last)
        XCTAssertEqual(r.texto, "Dicen hola.")
        XCTAssertEqual(r.respondeA, pregunta.id)
    }

    func testLaPreguntaEsperaElSiEnLaBurbuja() async throws {
        let (a, chat) = try await almacen("confirmar")
        final class Visto: @unchecked Sendable { var si: Bool? }
        let visto = Visto()
        AsistenteEnElChat.turnoDePrueba = { nucleo, chat, inicio, _, app, _ in
            visto.si = app.confirmar(pregunta: "¿Borrar la lista «Obra»?")
            let r = try nucleo.iaResponder(chat: chat, nota: inicio.respuesta.id, texto: "Hecho.", lienzo: nil)
            return FinChatIa(respuesta: r, abrirLienzo: nil)
        }
        let mE = await a.escribir(nota: "borra la lista obra", en: chat)
        let m = try XCTUnwrap(mE)
        let turnos = AsistenteEnElChat.compartido.alEnviar([m], chat: chat, almacen: a)
        // La tarjeta sale en la burbuja de la respuesta.
        var nota: String?
        for _ in 0 ..< 200 where nota == nil {
            nota = AsistenteEnElChat.compartido.preguntas.keys.first
            if nota == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        let n = try XCTUnwrap(nota, "la pregunta llego a la burbuja")
        XCTAssertEqual(AsistenteEnElChat.compartido.preguntas[n]?.texto, "¿Borrar la lista «Obra»?")
        AsistenteEnElChat.compartido.responder(nota: n, si: true)
        // Dos veces no hace nada (caso negativo).
        AsistenteEnElChat.compartido.responder(nota: n, si: false)
        for t in turnos { await t.value }
        XCTAssertEqual(visto.si, true)
        XCTAssertTrue(AsistenteEnElChat.compartido.preguntas.isEmpty)
    }

    func testPararCortaElTurno() async throws {
        let (a, chat) = try await almacen("parar")
        AsistenteEnElChat.turnoDePrueba = { nucleo, chat, inicio, _, _, corte in
            let hasta = Date().addingTimeInterval(10)
            while !corte.cortado(), Date() < hasta { Thread.sleep(forTimeInterval: 0.01) }
            let r = try nucleo.iaResponder(chat: chat, nota: inicio.respuesta.id,
                                           texto: corte.cortado() ? "⏹ (parado)" : "no paro", lienzo: nil)
            return FinChatIa(respuesta: r, abrirLienzo: nil)
        }
        let mE = await a.escribir(nota: "cuenta hasta mil", en: chat)
        let m = try XCTUnwrap(mE)
        let turnos = AsistenteEnElChat.compartido.alEnviar([m], chat: chat, almacen: a)
        // Mientras contesta, otra pregunta no lanza otro turno.
        let otraE = await a.escribir(nota: "y otra", en: chat)
        let otra = try XCTUnwrap(otraE)
        XCTAssertTrue(AsistenteEnElChat.compartido.alEnviar([otra], chat: chat, almacen: a).isEmpty)
        XCTAssertNotNil(AsistenteEnElChat.compartido.aviso)
        AsistenteEnElChat.compartido.parar(chat)
        for t in turnos { await t.value }
        XCTAssertEqual(a.mensajes[chat]?.first(where: \.esDelAsistente)?.texto, "⏹ (parado)")
        AsistenteEnElChat.compartido.quitarAviso()
    }

    func testLaListaDeArrobaYLaMencion() throws {
        XCTAssertEqual(iaConsultaDeMencion(antes: "dibuja en @pla"), "pla")
        XCTAssertNil(iaConsultaDeMencion(antes: "correo@pla"))
        XCTAssertTrue(iaMencionaAlAsistente(texto: "oye @Asistente, ¿qué es?"))
        XCTAssertFalse(iaMencionaAlAsistente(texto: "correo@asistente.com"))
        let dir = try carpetaTemporal("e1-arroba")
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let chat = try nucleo.chatAsistente().id
        _ = try nucleo.crearLienzo(chat: chat, nombre: "Plano casa")
        XCTAssertEqual(nucleo.iaOpcionesMencion(chat: chat, escrito: "pla").map(\.mencion), ["@lienzo:Plano_casa"])
    }
}
