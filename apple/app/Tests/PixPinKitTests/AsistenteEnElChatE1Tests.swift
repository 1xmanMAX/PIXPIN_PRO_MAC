// Pruebas del asistente en el chat (E1), sin modelo ni red: el turno lo
// hace `AsistenteEnElChat.turnoDePrueba`, que escribe la respuesta con el
// nucleo de verdad (`iaResponder`). Las del turno con el motor guionado
// estan en Rust (`asistente/en_la_conversacion/pruebas.rs`).

import AppKit
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
                                  pregunta: nil, eleccion: nil, acabado: false))
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
            let hasta = Date().addingTimeInterval(60)
            while !corte.cortado(), Date() < hasta { Thread.sleep(forTimeInterval: 0.01) }
            let r = try nucleo.iaResponder(chat: chat, nota: inicio.respuesta.id,
                                           texto: corte.cortado() ? "⏹ (parado)" : "no paro", lienzo: nil)
            return FinChatIa(respuesta: r, abrirLienzo: nil)
        }
        let mE = await a.escribir(nota: "cuenta hasta mil", en: chat)
        let m = try XCTUnwrap(mE)
        let turnos = AsistenteEnElChat.compartido.alEnviar([m], chat: chat, almacen: a)
        // Sin carreras: se espera a que la respuesta haya nacido (el turno
        // de prueba no acaba hasta que se pare).
        var nacida = false
        for _ in 0 ..< 500 where !nacida {
            nacida = try a.nucleo.ultimosMensajes(chat: chat, cuantos: 10).mensajes.contains(where: \.esDelAsistente)
            if !nacida { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        XCTAssertTrue(nacida, "la respuesta nace al enviar")
        XCTAssertTrue(AsistenteEnElChat.compartido.ocupado(chat))
        // Mientras contesta, otra pregunta no lanza otro turno.
        let otraE = await a.escribir(nota: "y otra", en: chat)
        let otra = try XCTUnwrap(otraE)
        XCTAssertTrue(AsistenteEnElChat.compartido.alEnviar([otra], chat: chat, almacen: a).isEmpty)
        XCTAssertNotNil(AsistenteEnElChat.compartido.aviso)
        AsistenteEnElChat.compartido.parar(chat)
        for t in turnos { await t.value }
        XCTAssertFalse(AsistenteEnElChat.compartido.ocupado(chat))
        // Lo que quedo en el cuaderno (no lo cargado, que se relee aparte).
        let respuesta = try a.nucleo.ultimosMensajes(chat: chat, cuantos: 10).mensajes.first(where: \.esDelAsistente)
        XCTAssertEqual(respuesta?.texto, "⏹ (parado)")
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

    func testLosOjosPintanLaVistaConElPintorDelLienzoYSusEtiquetas() throws {
        let doc = ##"{"type":"excalidraw","version":2,"elements":[{"id":"a","type":"rectangle","x":0,"y":0,"width":100,"height":80,"strokeColor":"#e03131","backgroundColor":"#e03131","fillStyle":"solid","version":1,"isDeleted":false}],"appState":{},"files":{}}"##
        let plano = try Lienzo.deJson(texto: doc).plano()
        let v = VistaParaPintar(plano: plano, imagenes: [], x0: -30, y0: -30, x1: 130, y1: 110, ancho: 320, alto: 280,
                                escala: 2, rayas: [RayaVista(x0: 0, y0: 10, x1: 320, y1: 10)],
                                rotulos: [RotuloVista(texto: "#7", x: 250, y: 240, etiqueta: true)])
        let png = try XCTUnwrap(OjosDelAsistente.pintar(v))
        let img = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(img.pixelsWide, 320)
        XCTAssertEqual(img.pixelsHigh, 280)
        // El rectangulo rojo, en su sitio: (50, 40) del mundo -> (160, 140).
        let rojo = try XCTUnwrap(img.colorAt(x: 160, y: 140)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(rojo.redComponent, 0.7)
        XCTAssertLessThan(rojo.greenComponent, 0.4)
        // La etiqueta, sobre amarillo; y el papel, blanco.
        let amarillo = try XCTUnwrap(img.colorAt(x: 249, y: 240)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(amarillo.redComponent, 0.9)
        XCTAssertGreaterThan(amarillo.greenComponent, 0.75)
        XCTAssertLessThan(amarillo.blueComponent, 0.5)
        let papel = try XCTUnwrap(img.colorAt(x: 300, y: 60)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(papel.blueComponent, 0.95)
        // Una vista vacia no se pinta (caso negativo).
        XCTAssertNil(OjosDelAsistente.pintar(VistaParaPintar(plano: plano, imagenes: [], x0: 0, y0: 0, x1: 1, y1: 1,
                                                             ancho: 0, alto: 0, escala: 1, rayas: [], rotulos: [])))
    }
}
