// El menu de un mensaje del chat (`Chat/MenuMensaje.swift`): lo que escribe
// en el cuaderno por el `Almacen` (que cruza el puente de verdad) y las
// horas de recordar, que son las de Windows.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class MenuMensajeTests: XCTestCase {
    private func almacenConChats(_ etiqueta: String) async throws -> (URL, Almacen, String, String) {
        let raiz = try carpetaTemporal(etiqueta)
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        await almacen.crearChat(nombre: "Casa")
        let obra = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        let casa = try XCTUnwrap(almacen.chats.first { $0.nombre == "Casa" }).id
        await almacen.abrir(chat: obra)
        return (raiz, almacen, obra, casa)
    }

    func testResponderFijarEtiquetarYRecordarCambianElMensajeCargado() async throws {
        let (raiz, almacen, obra, _) = try await almacenConChats("menu-cambiar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let escrita = await almacen.escribir(nota: "medir la puerta", en: obra)
        let a = try XCTUnwrap(escrita)
        let respuesta = await almacen.escribir(nota: "2,10", en: obra, respondeA: a.id)
        let r = try XCTUnwrap(respuesta)
        XCTAssertEqual(r.respondeA, a.id, "la respuesta lleva `respondeA`")

        let fijado = await almacen.cambiar(mensaje: a.id, en: obra, .fijar(fijado: true))
        XCTAssertEqual(fijado?.fijado, true)
        XCTAssertEqual(almacen.mensajes[obra]?.first?.fijado, true, "lo cargado se pone al dia")
        _ = await almacen.cambiar(mensaje: a.id, en: obra, .etiqueta(emoji: MenuMensaje.etiquetas[0]))
        _ = await almacen.cambiar(mensaje: a.id, en: obra, .recordar(cuando: 1_900_000_000_000))
        await almacen.abrir(chat: obra)
        let leido = try XCTUnwrap(almacen.mensajes[obra]?.first { $0.id == a.id })
        XCTAssertEqual(leido.emoji, "\u{2B50}")
        XCTAssertEqual(leido.recuerdaEn, 1_900_000_000_000)
        XCTAssertTrue(leido.fijado)

        // El estado del chat: etiquetar con la puesta la quita.
        let c = ChatAbierto(chat: obra, almacen: almacen)
        c.etiquetar(leido, "\u{2B50}")
        try await esperar { almacen.mensajes[obra]?.first { $0.id == a.id }?.emoji == nil }

        // Caso negativo: lo que no esta no cambia nada ni da error.
        let nada = await almacen.cambiar(mensaje: "no-esta", en: obra, .rescatar)
        XCTAssertNil(nada)
        XCTAssertNil(almacen.error)
    }

    func testReenviarLlevaUnaCopiaAlOtroChat() async throws {
        let (raiz, almacen, obra, casa) = try await almacenConChats("menu-reenviar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let escrita = await almacen.escribir(nota: "llevar esto", en: obra)
        let a = try XCTUnwrap(escrita)
        let n = await almacen.reenviar(mensajes: [a.id], de: obra, a: casa)
        XCTAssertEqual(n, 1)
        await almacen.abrir(chat: casa)
        XCTAssertEqual(almacen.mensajes[casa]?.map(\.texto), ["llevar esto"])
        XCTAssertNotEqual(almacen.mensajes[casa]?.first?.id, a.id)
        XCTAssertEqual(almacen.mensajes[obra]?.count, 1, "el de aqui se queda")
        // Caso negativo: a un chat que no existe no va nada.
        let mal = await almacen.reenviar(mensajes: [a.id], de: obra, a: "no-existe")
        XCTAssertEqual(mal, 0)
        XCTAssertNotNil(almacen.error)
    }

    func testCopiarJuntaLosTextosSinLasMiniapps() {
        func m(_ id: String, _ clase: String, _ texto: String) -> MensajeChat {
            MensajeChat(id: id, cuando: 0, clase: clase, texto: texto, nombre: "", ruta: nil, bytes: 0,
                        resumen: texto, codigoChat: nil, respondeA: nil, emoji: nil, fijado: false,
                        referencia: nil, pagina: nil, duracionMs: 0, transcripcion: nil, picos: [],
                        enBuzon: false, recuerdaEn: nil, miniapp: nil, esLeccion: false,
                        sePuedeRenombrar: false, sePuedeDescribir: false, punto: nil, soloLaFoto: true,
                        vieneDe: nil, vieneDeDibujo: nil, recibidoDe: nil, lienzoIa: nil)
        }
        let lista = [m("1", "NOTA", "  uno \n"), m("2", "MINIAPP", "{\"x\":1}"), m("3", "IMAGEN", "pie"), m("4", "NOTA", "  ")]
        XCTAssertEqual(ChatAbierto.textoParaCopiar(lista), "uno\n\npie")
        XCTAssertTrue(ChatAbierto.sePuedeCopiar(lista[0]))
        // Casos negativos: una mini-app y un texto en blanco no se copian.
        XCTAssertFalse(ChatAbierto.sePuedeCopiar(lista[1]))
        XCTAssertFalse(ChatAbierto.sePuedeCopiar(lista[3]))
        var voz = m("5", "VOZ", "")
        voz.nombre = "Clase.m4a"
        XCTAssertEqual(ChatAbierto.nombreParaEscribir(voz), "Clase", "un audio se escribe sin su .m4a")
    }

    func testLasHorasDeRecordarSonLasDeWindows() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let ahora = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 20, minute: 5)))
        let atajos = HorasDeRecordar.atajos(ahora: ahora, calendario: cal)
        XCTAssertEqual(atajos.map(\.titulo), ["Dentro de 10 minutos", "Dentro de 1 hora", "Dentro de 3 horas",
                                              "Esta tarde (18:00)", "Mañana (9:00)"])
        XCTAssertEqual(atajos[0].cuando.timeIntervalSince(ahora), 600)
        // «Esta tarde» a las ocho de la noche es manana a las 18.
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: atajos[3].cuando), DateComponents(day: 16, hour: 18))
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: atajos[4].cuando), DateComponents(day: 16, hour: 9))

        // La hora escrita (`hora_escrita` de Windows).
        func hm(_ s: String) -> [Int]? {
            HorasDeRecordar.horaEscrita(s, ahora: ahora, calendario: cal).map {
                let c = cal.dateComponents([.day, .hour, .minute], from: $0)
                return [c.day!, c.hour!, c.minute!]
            }
        }
        XCTAssertEqual(hm("21:30"), [15, 21, 30])
        XCTAssertEqual(hm("21.30"), [15, 21, 30])
        XCTAssertEqual(hm("2130"), [15, 21, 30])
        XCTAssertEqual(hm("930"), [16, 9, 30], "ya paso hoy: manana")
        XCTAssertEqual(hm("9"), [16, 9, 0])
        XCTAssertEqual(hm("21:"), [15, 21, 0], "a medio escribir, en punto")
        // Casos negativos: lo que no es una hora.
        XCTAssertNil(hm("25:00"))
        XCTAssertNil(hm("9:75"))
        XCTAssertNil(hm("las ocho"))
        XCTAssertNil(hm(""))
        XCTAssertNil(hm("12345"))

        XCTAssertEqual(HorasDeRecordar.legible(atajos[1].cuando, ahora: ahora, calendario: cal), "21:05")
        XCTAssertEqual(HorasDeRecordar.legible(atajos[4].cuando, ahora: ahora, calendario: cal), "16/10 09:00")
    }

    /// Espera (poco) a que se cumpla algo que hace una tarea.
    private func esperar(_ cumple: () -> Bool) async throws {
        for _ in 0 ..< 100 where !cumple() {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(cumple())
    }
}
