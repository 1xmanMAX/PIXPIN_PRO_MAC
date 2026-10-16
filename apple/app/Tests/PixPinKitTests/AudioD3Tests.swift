// El audio de la tanda D3: las cuentas del reproductor (las de
// `pixpin_audio::reloj`), el reproductor con un `.m4a` de verdad (saltos,
// ir a, velocidad que sobrevive, la fila), la biblioteca de audio (filtro,
// orden, musica, y entera desde un chat de verdad) y la hora del microfono
// flotante (las pruebas del `Selector` de Windows).

import AVFoundation
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

private func vozDePrueba(_ id: String, cuando: Int64, nombre: String = "", ruta: String? = "archivos/a.m4a",
                         enBuzon: Bool = false, clase: String = "VOZ", transcripcion: String? = nil,
                         duracionMs: Int64 = 3000) -> MensajeChat {
    MensajeChat(id: id, cuando: cuando, clase: clase, texto: "", nombre: nombre, ruta: ruta, bytes: 0,
                resumen: "", codigoChat: nil, respondeA: nil, emoji: nil, fijado: false,
                referencia: nil, pagina: nil, duracionMs: duracionMs, transcripcion: transcripcion, picos: [],
                enBuzon: enBuzon, recuerdaEn: nil, miniapp: nil, esLeccion: false,
                sePuedeRenombrar: false, sePuedeDescribir: false, punto: nil, soloLaFoto: true,
                vieneDe: nil, vieneDeDibujo: nil, recibidoDe: nil, lienzoIa: nil)
}

/// Un `.m4a` de `segundos` de seno.
private func m4aDePrueba(_ url: URL, segundos: Double) throws {
    let escritor = try EscritorVoz(url: url, muestreoDeEntrada: 44_100)
    try escritor.escribir(try senoDePrueba(segundos: segundos, muestreo: 44_100, canales: 1, amplitud: 0.01))
    _ = escritor.terminar()
}

final class CuentasReproductorTests: XCTestCase {
    func testLasVelocidadesSonCincoYCiclanEnElOrdenDelMovil() {
        var v: Float = 1
        var vistas: [Float] = []
        for _ in 0..<5 {
            v = ReproductorVoz.siguienteVelocidad(v)
            vistas.append(v)
        }
        XCTAssertEqual(vistas, [1.25, 1.5, 2.0, 0.75, 1.0])
        XCTAssertEqual(ReproductorVoz.siguienteVelocidad(3.3), 1.0, "una rara vuelve a la primera")
        XCTAssertEqual(VozAlta.rotulo(1.5), "1,5×")
    }

    func testSaltarYIrANoSeSalenDeLaNota() {
        XCTAssertEqual(ReproductorVoz.destinoAlSaltar(posicionMs: 5_000, ms: 10_000, duracionMs: 12_000), 12_000)
        XCTAssertEqual(ReproductorVoz.destinoAlSaltar(posicionMs: 5_000, ms: -10_000, duracionMs: 12_000), 0)
        XCTAssertEqual(ReproductorVoz.destinoAlSaltar(posicionMs: 1_000, ms: 10_000, duracionMs: -5), 0)
        XCTAssertEqual(ReproductorVoz.destinoAlSaltar(posicionMs: .max - 1, ms: 10_000, duracionMs: 9_000), 9_000)
        XCTAssertNil(ReproductorVoz.destinoDeFraccion(0.5, duracionMs: 0), "sin duracion no se rebobina")
        XCTAssertEqual(ReproductorVoz.destinoDeFraccion(0.5, duracionMs: 8_000), 4_000)
        XCTAssertEqual(ReproductorVoz.destinoDeFraccion(.nan, duracionMs: 8_000), 0)
        XCTAssertEqual(ReproductorVoz.destinoDeFraccion(7, duracionMs: 8_000), 8_000)
        XCTAssertEqual(ReproductorVoz.fraccion(posicionMs: 3, duracionMs: 0), 0)
        XCTAssertEqual(ReproductorVoz.fraccion(posicionMs: 2_000, duracionMs: 8_000), 0.25)
    }
}

@MainActor
final class ReproductorD3Tests: XCTestCase {
    func testUnFicheroQueNoEsAudioNoDejaLaBarraPuesta() {
        let r = ReproductorVoz()
        XCTAssertFalse(r.cargar(Pista(id: "x", url: URL(fileURLWithPath: "/no/existe.m4a"), titulo: "x"),
                                arrancar: false))
        XCTAssertFalse(r.hayAlgo)
        // Sin nada cargado, las ordenes no revientan ni inventan estado.
        r.atras()
        r.irA(fraccion: 0.5)
        r.seguir()
        XCTAssertFalse(r.sonando)
        XCTAssertEqual(r.posicionMs, 0)
    }

    func testSaltosIrAYLaVelocidadQueSobreviveAParar() throws {
        let carpeta = try carpetaTemporal("audio-d3")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let url = carpeta.appendingPathComponent("nota de obra.m4a")
        try m4aDePrueba(url, segundos: 12)
        let r = ReproductorVoz()
        XCTAssertTrue(r.cargar(Pista(id: "n1", url: url, titulo: ""), arrancar: false))
        XCTAssertTrue(r.hayAlgo)
        XCTAssertEqual(r.titulo, "nota de obra", "sin titulo, el nombre sin extension")
        XCTAssertEqual(Double(r.duracionMs), 12_000, accuracy: 100)
        r.adelante()
        XCTAssertEqual(Double(r.posicionMs), 10_000, accuracy: 50)
        r.adelante()
        XCTAssertEqual(Double(r.posicionMs), Double(r.duracionMs), accuracy: 100, "no se pasa del final")
        r.irA(fraccion: 0.25)
        XCTAssertEqual(Double(r.posicionMs), 3_000, accuracy: 100)
        r.atras()
        XCTAssertEqual(r.posicionMs, 0)
        XCTAssertEqual(r.otraVelocidad(), 1.25)
        r.parar()
        XCTAssertFalse(r.hayAlgo)
        XCTAssertEqual(r.velocidad, 1.25, "parar no olvida la velocidad")
    }

    func testLaFilaSuenaSeguidaYAlAcabarSeQuedaAlPrincipio() throws {
        let carpeta = try carpetaTemporal("audio-d3-fila")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let a = carpeta.appendingPathComponent("a.m4a"), b = carpeta.appendingPathComponent("b.m4a")
        try m4aDePrueba(a, segundos: 1)
        try m4aDePrueba(b, segundos: 1)
        let r = ReproductorVoz()
        r.mudo = true
        r.poner([Pista(id: "a", url: a, titulo: "A"), Pista(id: "b", url: b, titulo: "B")])
        r.pausar()
        XCTAssertEqual(r.actual, "a")
        XCTAssertEqual(r.cola.map(\.id), ["b"])
        r.acabo()
        XCTAssertEqual(r.actual, "b")
        XCTAssertTrue(r.cola.isEmpty)
        r.pausar()
        r.acabo()
        XCTAssertEqual(r.actual, "b", "la ultima se queda cargada")
        XCTAssertFalse(r.sonando)
        XCTAssertEqual(r.posicionMs, 0)
        XCTAssertEqual(r.acabadas, 2)
        // Tocar otra cosa suelta la fila.
        r.poner([Pista(id: "a", url: a, titulo: "A"), Pista(id: "b", url: b, titulo: "B")])
        r.alternar("b", url: b, titulo: "B")
        r.pausar()
        XCTAssertTrue(r.cola.isEmpty)
        r.parar()
    }
}

@MainActor
final class BibliotecaAudioTests: XCTestCase {
    func testSoloTraeNotasDeVozConFicheroYFueraDelBuzon() {
        let filas = BibliotecaAudio.filas([
            vozDePrueba("a", cuando: 10),
            vozDePrueba("b", cuando: 20, ruta: nil),
            vozDePrueba("c", cuando: 30, ruta: "   "),
            vozDePrueba("d", cuando: 40, clase: "NOTA"),
            vozDePrueba("e", cuando: 50, enBuzon: true),
        ], chat: "c1", musica: [])
        XCTAssertEqual(filas.map(\.id), ["a"])
        XCTAssertEqual(filas[0].chat, "c1")
    }

    func testLaMusicaVaPrimeroYEnCadaGrupoLoMasNuevoArriba() {
        let filas = BibliotecaAudio.ordenar(BibliotecaAudio.filas([
            vozDePrueba("n1", cuando: 100), vozDePrueba("n2", cuando: 300), vozDePrueba("m1", cuando: 50),
        ], chat: "c", musica: ["m1"]))
        XCTAssertEqual(filas.map(\.id), ["m1", "n2", "n1"])
        XCTAssertEqual(filas[0].grupo, .musica)
    }

    func testElTituloQuitaLaExtensionYLaLetraSoloCuentaConAlgoEscrito() {
        XCTAssertEqual(BibliotecaAudio.titulo(nombre: "lectura-1758351600000.m4a", cuando: 0), "lectura-1758351600000")
        XCTAssertEqual(BibliotecaAudio.titulo(nombre: "sin extension", cuando: 0), "sin extension")
        XCTAssertEqual(BibliotecaAudio.titulo(nombre: ".oculto", cuando: 0), ".oculto")
        XCTAssertTrue(BibliotecaAudio.titulo(nombre: "", cuando: 0).hasPrefix("Voz · "))
        let f = BibliotecaAudio.filas([vozDePrueba("v", cuando: 1, transcripcion: "  "),
                                       vozDePrueba("w", cuando: 2, transcripcion: "hola", duracionMs: -5)],
                                      chat: "c", musica: [])
        XCTAssertEqual(f.map(\.tieneLetra), [false, true])
        XCTAssertEqual(f[1].duracionMs, 0, "una duracion negativa no pinta una barra al reves")
    }

    func testLaMusicaSeLeeDelCuaderno() throws {
        let carpeta = try carpetaTemporal("biblioteca-cuaderno")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let cuaderno = carpeta.appendingPathComponent("guardados.jsonl")
        try """
        {"id":"m1","clase":"VOZ","estadoDelTexto":"letra"}
        {"id":"n1","clase":"VOZ","estadoDelTexto":"bien","texto":"letra"}
        no es json "letra"
        {"id":"x","clase":"VOZ","estadoDelTexto":7}
        """.write(to: cuaderno, atomically: true, encoding: .utf8)
        XCTAssertEqual(BibliotecaAudio.idsDeMusica(cuaderno: cuaderno), ["m1"])
        XCTAssertTrue(BibliotecaAudio.idsDeMusica(cuaderno: carpeta.appendingPathComponent("no")).isEmpty)
    }

    func testLaBibliotecaEnteraDeUnChatDeVerdad() async throws {
        let raiz = try carpetaTemporal("biblioteca-chat")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        await almacen.abrir(chat: chat)
        let url = raiz.appendingPathComponent("grabando.m4a")
        let escritor = try EscritorVoz(url: url, muestreoDeEntrada: 44_100)
        try escritor.escribir(try senoDePrueba(segundos: 1.0, muestreo: 44_100, canales: 1))
        let hecho = await almacen.adjuntarVoz(escritor.terminar(), en: chat)
        let m = try XCTUnwrap(hecho)
        _ = await almacen.escribir(nota: "no es audio", en: chat)

        let filas = await BibliotecaAudio.leer(almacen.nucleo)
        XCTAssertEqual(filas.map(\.id), [m.id])
        XCTAssertEqual(filas[0].chat, chat)
        XCTAssertEqual(filas[0].grupo, .notas)
        let suena = try XCTUnwrap(filas[0].url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: suena.path))
        XCTAssertEqual(filas[0].titulo, (m.nombre as NSString).deletingPathExtension)
    }
}

final class SelectorHoraTests: XCTestCase {
    /// Las 14:20 de un dia cualquiera, en un reloj sin cambios de hora.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let dia: TimeInterval = 86_400
    private var ahora: Date { Date(timeIntervalSince1970: 20_000 * dia + 14 * 3600 + 20 * 60) }

    func testLaHoraNaceUnaHoraMasTardeYEnPunto() {
        let s = SelectorHora.nuevo(ahora, calendario: cal)
        XCTAssertTrue(s.reloj == (15, 0))
        XCTAssertEqual(s.cuando, Date(timeIntervalSince1970: 20_000 * dia + 15 * 3600))
        let tarde = Date(timeIntervalSince1970: 20_000 * dia + 23 * 3600 + 30 * 60)
        XCTAssertEqual(SelectorHora.nuevo(tarde, calendario: cal).cuando, Date(timeIntervalSince1970: 20_001 * dia))
    }

    func testLosAtajosSon15MinUnaHoraYMananaALas9() {
        let a = SelectorHora.atajos(ahora, calendario: cal).map(\.cuando)
        XCTAssertEqual(a, [ahora.addingTimeInterval(900), ahora.addingTimeInterval(3600),
                           Date(timeIntervalSince1970: 20_001 * dia + 9 * 3600)])
        let madrugada = Date(timeIntervalSince1970: 20_000 * dia + 3600)
        XCTAssertEqual(SelectorHora.atajos(madrugada, calendario: cal)[2].cuando,
                       Date(timeIntervalSince1970: 20_001 * dia + 9 * 3600))
    }

    func testLasFlechasMuevenYNuncaDejanLaHoraEnElPasado() {
        var s = SelectorHora.nuevo(ahora, calendario: cal)
        s.moverHora(1, ahora: ahora)
        XCTAssertTrue(s.reloj == (16, 0))
        s.moverMinutos(1, ahora: ahora)
        XCTAssertTrue(s.reloj == (16, 5))
        s.moverMinutos(-2, ahora: ahora)
        XCTAssertTrue(s.reloj == (15, 55))
        s.moverHora(-2, ahora: ahora)
        XCTAssertTrue(s.reloj == (13, 55))
        XCTAssertEqual(s.cuando, Date(timeIntervalSince1970: 20_001 * dia + 13 * 3600 + 55 * 60), "mañana, no el pasado")
        var t = SelectorHora.nuevo(ahora, calendario: cal)
        t.atajo(ahora.addingTimeInterval(13 * 60), ahora: ahora)
        XCTAssertTrue(t.reloj == (14, 33))
        t.moverMinutos(1, ahora: ahora)
        XCTAssertTrue(t.reloj == (14, 35))
        t.atajo(ahora.addingTimeInterval(13 * 60), ahora: ahora)
        t.moverMinutos(-1, ahora: ahora)
        XCTAssertTrue(t.reloj == (14, 30))
        t.moverMinutos(-1, ahora: ahora)
        XCTAssertTrue(t.reloj == (14, 25))
        t.moverMinutos(-1, ahora: ahora)
        XCTAssertTrue(t.reloj == (14, 25), "las 14:20 ya no es el futuro")
    }

    func testLoTecleadoPoneLaHoraYLoQueNoEsHoraSeDice() {
        var s = SelectorHora.nuevo(ahora, calendario: cal)
        for c in "18:30" { s.teclear(c, ahora: ahora) }
        XCTAssertTrue(s.reloj == (18, 30))
        XCTAssertFalse(s.escritoMal(ahora: ahora))
        for _ in 0..<4 { s.borrar(ahora: ahora) }
        s.teclear("9", ahora: ahora)
        XCTAssertTrue(s.reloj == (19, 0))
        s.teclear("7", ahora: ahora)
        XCTAssertTrue(s.escritoMal(ahora: ahora))
        XCTAssertTrue(s.reloj == (19, 0))
        let antes = s
        s.teclear("x", ahora: ahora)
        XCTAssertEqual(s, antes)
    }
}
