// Los tres relojes de las mini-apps (cronometro, temporizador y alarma) por
// el puente: el documento es el de Windows y el movil, y el tiempo se
// calcula con la hora que se le pasa (nada duerme en estas pruebas).

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class RelojesMiniTests: XCTestCase {
    func testElCronometroGuardaElInstanteYCalculaAlMirar() throws {
        var d = try XCTUnwrap(miniDocumentoNuevo(miniapp: "cronometro", titulo: "Series", moneda: "EUR"))
        d = miniCronometroCambiar(documento: d, accion: .arrancarOParar, ahoraMs: 1000)
        d = miniCronometroCambiar(documento: d, accion: .vuelta, ahoraMs: 11250)
        let c = miniCronometroLeer(documento: d, ahoraMs: 66300)
        XCTAssertTrue(c.corriendo)
        XCTAssertEqual(c.tablero, "1:05,3")
        XCTAssertEqual(c.vueltas, ["0:10,2"])
        d = miniCronometroCambiar(documento: d, accion: .arrancarOParar, ahoraMs: 66300)
        XCTAssertEqual(d, "# Series\n\n- llevado: 65300\n- vueltas: 10250")
        XCTAssertEqual(miniCronometroLeer(documento: d, ahoraMs: 9_999_999).transcurrido, 65300, "parado no corre")
    }

    func testElTemporizadorEscribeFinEnYNoSeAjustaEnMarcha() throws {
        var d = try XCTUnwrap(miniDocumentoNuevo(miniapp: "temporizador", titulo: "Pasta", moneda: "EUR"))
        XCTAssertEqual(miniTemporizadorLeer(documento: d, ahoraMs: 0).tablero, "5:00")
        d = miniTemporizadorCambiar(documento: d, accion: .duracion(ms: 60000), ahoraMs: 0)
        d = miniTemporizadorCambiar(documento: d, accion: .arrancarOParar, ahoraMs: 1000)
        XCTAssertEqual(d, "# Pasta\n\n- duracion: 60000\n- finEn: 61000")
        XCTAssertEqual(miniTemporizadorCambiar(documento: d, accion: .minutos(minutos: 5), ahoraMs: 2000), d)
        XCTAssertTrue(miniTemporizadorLeer(documento: d, ahoraMs: 61000).vencido)
        XCTAssertEqual(miniCuandoAvisa(miniapp: "temporizador", documento: d, ahoraMs: 2000, desfaseLocalMs: 0), 61000)
        XCTAssertNil(miniCuandoAvisa(miniapp: "temporizador", documento: d, ahoraMs: 61000, desfaseLocalMs: 0))
        XCTAssertEqual(miniDuracionTecleada(texto: "1:30"), 90000)
        XCTAssertNil(miniDuracionTecleada(texto: "1:75"))
    }

    func testLaAlarmaSeEscribeConTildeYTecleadaSeEnciende() throws {
        var d = try XCTUnwrap(miniDocumentoNuevo(miniapp: "alarma", titulo: "Despertar", moneda: "EUR"))
        XCTAssertFalse(miniAlarmaLeer(documento: d).activa)
        let h = try XCTUnwrap(miniHoraTecleada(texto: "705"))
        d = miniAlarmaCambiar(documento: d, accion: .hora(hora: h.hora, minuto: h.minuto))
        XCTAssertEqual(d, "# Despertar\n\n- hora: 7:05\n- activa: sí")
        d = miniAlarmaCambiar(documento: d, accion: .horas(horas: -8))
        XCTAssertEqual(miniAlarmaLeer(documento: d).tablero, "23:05")
        // A medianoche UTC sin desfase: hoy a las 23:05.
        XCTAssertEqual(miniCuandoAvisa(miniapp: "alarma", documento: d, ahoraMs: 0, desfaseLocalMs: 0),
                       (23 * 60 + 5) * 60000)
        XCTAssertNil(miniHoraTecleada(texto: "25:00"))
    }

    @MainActor
    func testTocarUnTemporizadorPoneYQuitaSuAviso() throws {
        let d = try XCTUnwrap(miniDocumentoNuevo(miniapp: "temporizador", titulo: "Té", moneda: "EUR"))
        let doc = DocumentoMini(miniapp: "temporizador", documento: d, nucleo: nil, chat: nil, mensaje: nil)
        XCTAssertTrue(doc.idAviso.hasPrefix("local:"), "sin mensaje, un aviso suelto")
        let ahora = milisegundos()
        doc.cambiar { miniTemporizadorCambiar(documento: $0, accion: .arrancarOParar, ahoraMs: ahora) }
        let puesto = try XCTUnwrap(AvisosMini.compartido.puestos[doc.idAviso])
        XCTAssertEqual(puesto.texto, "Té")
        XCTAssertEqual(puesto.cuando.timeIntervalSince1970, Double(ahora + 300_000) / 1000, accuracy: 0.01)
        doc.cambiar { miniTemporizadorCambiar(documento: $0, accion: .arrancarOParar, ahoraMs: ahora) }
        XCTAssertNil(AvisosMini.compartido.puestos[doc.idAviso], "parado no avisa")
    }

    func testLosAvisosDeLosChatsLlevanElPrefijoDelMovil() throws {
        let dir = try carpetaTemporal("relojes")
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let chat = try nucleo.chatGuardados().id
        let m = try nucleo.crearMiniapp(chat: chat, miniapp: "alarma", titulo: "Pastilla", moneda: "EUR")
        XCTAssertTrue(try nucleo.avisosMiniapps(desfaseLocalMs: 0).isEmpty, "nace apagada")
        let d0 = try nucleo.documentoMiniapp(chat: chat, mensaje: m.id)
        let d1 = miniAlarmaCambiar(documento: d0, accion: .activar)
        XCTAssertTrue(try nucleo.guardarMiniapp(chat: chat, mensaje: m.id, anterior: d0, documento: d1))
        let avisos = try nucleo.avisosMiniapps(desfaseLocalMs: desfaseLocalMs())
        XCTAssertEqual(avisos.map(\.id), ["mini:\(m.id)"])
        XCTAssertEqual(avisos.first?.texto, "Pastilla")
    }
}
