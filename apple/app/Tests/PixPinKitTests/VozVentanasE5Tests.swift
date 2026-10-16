// Las ventanitas de la voz (tanda E5): el telepronter, Pronunciar, la
// conversacion por turnos y la llamada secreta. Las pruebas de Windows
// (`teleprompter.rs`, `pixpin_voz::telepronter`, `pronunciar.rs`,
// `conversacion.rs`, `llamada.rs`) con la cuenta pura, y lo grabado entrando
// en un chat de verdad, cruzando el puente. Sin ventanas ni microfono.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

private func medidas(_ n: Int, _ alto: CGFloat) -> [MedidaParrafo] {
    (0..<n).map { MedidaParrafo(cima: CGFloat($0) * alto, alto: alto) }
}

private func mensaje(_ id: String, clase: String = "NOTA", texto: String = "", nombre: String = "",
                     ruta: String? = nil) -> MensajeChat {
    MensajeChat(id: id, cuando: 0, clase: clase, texto: texto, nombre: nombre, ruta: ruta, bytes: 0,
                resumen: "", codigoChat: nil, respondeA: nil, emoji: nil, fijado: false,
                referencia: nil, pagina: nil, duracionMs: 0, transcripcion: nil, picos: [],
                enBuzon: false, recuerdaEn: nil, miniapp: nil, esLeccion: false,
                sePuedeRenombrar: false, sePuedeDescribir: false, punto: nil, soloLaFoto: true,
                vieneDe: nil, vieneDeDibujo: nil, recibidoDe: nil, lienzoIa: nil)
}

final class TelepronterE5Tests: XCTestCase {
    func testElTextoSeParteEnParrafosYPierdeLasMarcasDeMarkdown() {
        XCTAssertEqual(Telepronter.parrafos(de: "# Titulo\n\n- **uno** y `dos`\nsigue aqui\n\n> citado"),
                       ["Titulo", "uno y dos sigue aqui", "citado"])
    }

    func testUnTextoVacioNoDaNingunParrafoQueLeer() {
        XCTAssertTrue(Telepronter.parrafos(de: "").isEmpty)
        XCTAssertTrue(Telepronter.parrafos(de: "   \n\n  \n").isEmpty)
        XCTAssertTrue(Telepronter.parrafos(de: "![foto](obra.png)").isEmpty, "una imagen no se lee")
    }

    func testElDesfileBajaALaVelocidadPedidaYSeParaAlFinal() {
        var d = Desfile(parrafos: 4)
        d.medir(medidas(4, 100), altoVisible: 200)
        XCTAssertEqual(d.tope, 200)
        XCTAssertFalse(d.avanzar(1, velocidad: 50))
        XCTAssertEqual(d.y, 50)
        XCTAssertTrue(d.avanzar(10, velocidad: 50), "al llegar al final deja de bajar")
        XCTAssertEqual(d.y, 200)
    }

    func testUnTextoMasCortoQueLaVentanaNoSeMueve() {
        var d = Desfile(parrafos: 1)
        d.medir(medidas(1, 50), altoVisible: 400)
        XCTAssertTrue(d.avanzar(5, velocidad: 150))
        XCTAssertEqual(d.y, 0)
    }

    func testCadaParrafoSeQuedaConElMilisegundoEnQueCruzoLaLinea() {
        var d = Desfile(parrafos: 3)
        d.medir(medidas(3, 100), altoVisible: 200)
        XCTAssertEqual(d.lineaDeLectura, 60, accuracy: 0.001)
        d.apuntar(0)
        XCTAssertEqual([d.tiempo(0), d.tiempo(1), d.tiempo(2)], [0, nil, nil])
        d.empujar(50)
        d.apuntar(5_000)
        XCTAssertEqual(d.tiempo(1), 5_000)
        XCTAssertNil(d.tiempo(2))
    }

    func testVolverASubirElTextoNoLeQuitaElMinutoALoYaLeido() {
        var d = Desfile(parrafos: 2)
        d.medir(medidas(2, 100), altoVisible: 100)
        d.empujar(100)
        d.apuntar(4_000)
        d.empujar(-100)
        d.apuntar(9_000)
        XCTAssertEqual(d.tiempo(1), 4_000, "el minuto es el de la primera vez")
    }

    func testReiniciarDevuelveElTextoArribaYBorraLosMinutos() {
        var d = Desfile(parrafos: 2)
        d.medir(medidas(2, 100), altoVisible: 100)
        d.empujar(50)
        d.apuntar(1_000)
        d.reiniciar()
        XCTAssertEqual(d.y, 0)
        XCTAssertNil(d.tiempo(0))
    }

    func testElCuerpoPoneElFinalALoQueNoLlegoACruzar() {
        var d = Desfile(parrafos: 2)
        d.medir(medidas(2, 100), altoVisible: 300)
        d.apuntar(2_000)
        XCTAssertEqual(d.cuerpo(["primero", "segundo"], duracionMs: 61_000), "[0:02] primero\n\n[1:01] segundo")
    }

    func testUnMinutoMasAllaDelFinalDeLaGrabacionSeRecorta() {
        var d = Desfile(parrafos: 1)
        d.medir(medidas(1, 100), altoVisible: 300)
        d.apuntar(99_000)
        XCTAssertEqual(d.cuerpo(["uno"], duracionMs: 5_000), "[0:05] uno")
    }

    func testSoloSePintaElTrozoQueSeVe() {
        var d = Desfile(parrafos: 10)
        d.medir(medidas(10, 100), altoVisible: 250)
        XCTAssertEqual(d.visibles, 0..<3)
        d.empujar(400)
        XCTAssertEqual(d.visibles, 4..<7)
        XCTAssertTrue(Desfile(parrafos: 0).visibles.isEmpty)
    }

    func testLaVelocidadSeAcotaYSeDiceConPalabras() {
        XCTAssertEqual(Telepronter.acotarVelocidad(5), Telepronter.velocidadMinima)
        XCTAssertEqual(Telepronter.acotarVelocidad(500), Telepronter.velocidadMaxima)
        XCTAssertEqual(Telepronter.palabra(deVelocidad: 20), "muy lenta")
        XCTAssertEqual(Telepronter.palabra(deVelocidad: Telepronter.velocidadPorDefecto), "lenta")
        XCTAssertEqual(Telepronter.palabra(deVelocidad: 150), "muy rápida")
        XCTAssertEqual(Telepronter.acotarTamano(100), Telepronter.tamanoMaximo)
    }

    func testCambiarDeTextoDejaLosMinutosACeroEnVezDeMezclarlos() {
        var d = Desfile(parrafos: 2)
        d.medir(medidas(2, 100), altoVisible: 300)
        d.apuntar(3_000)
        XCTAssertEqual(d.tiempo(0), 3_000)
        d.medir(medidas(5, 100), altoVisible: 300)
        XCTAssertNil(d.tiempo(0))
    }

    func testConDosPantallasSeLeeEnLaQueNoTieneElChat() {
        let a = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        XCTAssertEqual(Telepronter.pantallaParaLeer(a, principal: 0, juntoA: a[0]), 1)
        XCTAssertEqual(Telepronter.pantallaParaLeer(a, principal: 0, juntoA: a[1]), 0)
    }

    func testConUnaPantallaSeLeeEnEsaYSinSaberDondeEstaElChatNoSeElige() {
        let a = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        XCTAssertEqual(Telepronter.pantallaParaLeer(a, principal: 0, juntoA: a[0]), 0)
        XCTAssertNil(Telepronter.pantallaParaLeer(a, principal: 0, juntoA: nil), "quien llama cae a la principal")
    }

    func testElMenuOfreceLaCajaLasNotasYLosTxtLoUltimoPrimero() {
        let largo = String(repeating: "a", count: 60)
        let v = FuentesTelepronter.entradas(borrador: "  hola ", mensajes: [
            mensaje("1", texto: "\n  Primera nota\notra"),
            mensaje("2", clase: "ARCHIVO", nombre: "guion.md", ruta: "archivos/guion.md"),
            mensaje("3", clase: "ARCHIVO", nombre: "obra.pdf", ruta: "archivos/obra.pdf"),
            mensaje("4", texto: largo),
            mensaje("5", texto: "   "),
        ])
        XCTAssertEqual(v.map(\.rotulo), ["Lo escrito en la caja", String(repeating: "a", count: 48) + "…",
                                         "guion.md", "Primera nota"])
        XCTAssertEqual(v[2].fuente, .adjunto(ruta: "archivos/guion.md"))
        // Caso negativo: sin caja ni nada que leer, el menu esta vacio.
        XCTAssertTrue(FuentesTelepronter.entradas(borrador: " ", mensajes: [mensaje("x", clase: "IMAGEN",
            nombre: "a.png", ruta: "archivos/a.png")]).isEmpty)
    }
}

final class PronunciarE5Tests: XCTestCase {
    func testLaClaseDeGuiaSaleDeLaExtensionYLoDemasNoSirve() {
        XCTAssertEqual(Pronunciar.clase(de: "a/libro.PDF"), .pdf)
        XCTAssertEqual(Pronunciar.clase(de: "foto.jpeg"), .imagen)
        XCTAssertEqual(Pronunciar.clase(de: "frases.md"), .texto)
        XCTAssertNil(Pronunciar.clase(de: "hoja.xlsx"))
        XCTAssertNil(Pronunciar.clase(de: "sin_extension"))
    }

    func testDelChatSalenNotasYAdjuntosQueSirvenLoUltimoPrimero() {
        let v = Pronunciar.guiasDelChat([
            mensaje("1", texto: "\n  Frase para practicar\notra linea"),
            mensaje("2", clase: "ARCHIVO", nombre: "lecturas.pdf", ruta: "archivos/lecturas.pdf"),
            mensaje("3", clase: "ARCHIVO", nombre: "cuentas.xlsx", ruta: "archivos/cuentas.xlsx"),
        ])
        XCTAssertEqual(v.count, 2)
        XCTAssertEqual(v[0].titulo, "📄 lecturas.pdf")
        XCTAssertEqual(v[0].fuente, .adjunto(ruta: "archivos/lecturas.pdf"))
        XCTAssertEqual(v[1].titulo, "✎ Frase para practicar")
    }

    func testLosIdiomasSonLosDelMovilYElPrimeroEsElDeSiempre() {
        XCTAssertEqual(Pronunciar.idiomas.map(\.codigo), ["", "es", "en", "pt", "fr", "de", "it", "ca"])
        XCTAssertEqual(Pronunciar.idiomas[0].nombre, "El de siempre")
    }
}

final class ConversacionE5Tests: XCTestCase {
    func testSinNombreLaPersonaSeLlamaPorSuNumero() {
        let nombres = ["  Pepe ", ""]
        XCTAssertEqual(ConversacionPorTurnos.nombre(nombres, 0), "Pepe")
        XCTAssertEqual(ConversacionPorTurnos.nombre(nombres, 1), "Persona 2")
        XCTAssertEqual(ConversacionPorTurnos.nombre(nombres, 7), "Persona 8")
    }

    func testLasTeclasUnoANueveEligenPersonaYElCeroANadie() {
        XCTAssertEqual(ConversacionPorTurnos.tecla("1"), .persona(0))
        XCTAssertEqual(ConversacionPorTurnos.tecla("9"), .persona(8))
        XCTAssertEqual(ConversacionPorTurnos.tecla("0"), .nadie)
        XCTAssertNil(ConversacionPorTurnos.tecla("a"), "una letra no hace nada")
        XCTAssertNil(ConversacionPorTurnos.tecla(nil))
    }

    func testLoQueSeGrabaConElCeroNoEsDeNadieYNoSale() {
        let t = turnosDeLaConversacion(cambios: [CambioDeTurno(ms: 0, quien: "Ana"),
                                                 CambioDeTurno(ms: 3_000, quien: ""),
                                                 CambioDeTurno(ms: 6_000, quien: "Luis")], finMs: 9_000)
        XCTAssertEqual(t, [TurnoVoz(quien: "Ana", desdeMs: 0, hastaMs: 3_000),
                           TurnoVoz(quien: "Luis", desdeMs: 6_000, hastaMs: 9_000)])
    }
}

final class LlamadaE5Tests: XCTestCase {
    func testSinContestarSeCuelgaALosCuarentaYCincoSegundos() {
        let t0 = Date(timeIntervalSince1970: 1)
        XCTAssertFalse(Llamada.tocaColgar(.sonando, desde: t0, ahora: t0 + 44.999, acaboEn: nil))
        XCTAssertTrue(Llamada.tocaColgar(.sonando, desde: t0, ahora: t0 + 45, acaboEn: nil))
    }

    func testContestadaCuelgaSolaUnPocoDespuesDeAcabarLaNota() {
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(Llamada.tocaColgar(.contestada, desde: t0, ahora: t0 + 999, acaboEn: nil), "mientras suena, no")
        XCTAssertFalse(Llamada.tocaColgar(.contestada, desde: t0, ahora: t0 + 10.5, acaboEn: t0 + 10))
        XCTAssertTrue(Llamada.tocaColgar(.contestada, desde: t0, ahora: t0 + 10.9, acaboEn: t0 + 10))
    }

    func testVolverALlamarOfreceLosMinutosDelMovilConSuRotulo() {
        XCTAssertEqual(Llamada.volverEn, [5, 15, 30, 60, 120])
        XCTAssertEqual(Llamada.volverEn.map(Llamada.rotulo(deVolver:)), ["5 min", "15 min", "30 min", "1 h", "2 h"])
        let t0 = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(Llamada.horaDeVolver(t0, minutos: 15), t0 + 15 * 60)
    }

    func testLaVentanitaVaAbajoALaDerechaDentroDeLaPantalla() {
        let area = CGRect(x: 1920, y: 0, width: 1920, height: 1040)
        let m = Llamada.marco(en: area)
        XCTAssertTrue(area.contains(m))
        XCTAssertGreaterThan(m.minX, area.midX, "a la derecha")
        XCTAssertLessThan(m.minY, area.midY, "abajo")
    }

    func testElMacTraeUnTonoDeLlamada() {
        // En un Mac de verdad esta; si no, suena sin timbre en vez de fallar.
        if let t = Llamada.tono() { XCTAssertTrue(FileManager.default.fileExists(atPath: t.path)) }
    }

    func testSinNombreLaLlamadaSeLlamaLlamadaYLoViejoEsPerdida() {
        XCTAssertEqual(Llamada.titulo("  "), "Llamada")
        XCTAssertEqual(Llamada.titulo("Mamá"), "Mamá")
        XCTAssertEqual(nombreDeLlamada(nombre: "recado.largo.m4a"), "recado.largo")
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(Llamada.aunSuena(t0, ahora: t0 + 30))
        XCTAssertFalse(Llamada.aunSuena(t0, ahora: t0 + 3_600), "vencio con la app cerrada hace una hora")
    }
}

@MainActor
final class VozVentanasEnElChatE5Tests: XCTestCase {
    private func chatDePrueba(_ etiqueta: String) async throws -> (Almacen, String, URL) {
        let raiz = try carpetaTemporal("e5-\(etiqueta)")
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        await almacen.abrir(chat: chat)
        return (almacen, chat, raiz)
    }

    private func audio(_ raiz: URL, _ nombre: String) throws -> URL {
        let u = raiz.appendingPathComponent(nombre)
        try Data("m4a".utf8).write(to: u)
        return u
    }

    func testLaLecturaDelTelepronterEntraConSuTextoYSuNombre() async throws {
        let (almacen, chat, raiz) = try await chatDePrueba("lectura")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let u = try audio(raiz, "lectura-1758351600000.m4a")
        let g = GrabacionVoz(rutaOrigen: u.path, duracionMs: 12_500, picos: [10, 20_000],
                             texto: "[0:00] primero\n\n[0:07] segundo", turnos: [])
        let hecho = await almacen.adjuntarGrabacion(g, en: chat)
        let m = try XCTUnwrap(hecho, almacen.error ?? "")
        XCTAssertEqual(m.clase, "VOZ")
        XCTAssertEqual(m.nombre, "lectura-1758351600000.m4a")
        XCTAssertEqual(m.transcripcion, "[0:00] primero\n\n[0:07] segundo")
        XCTAssertEqual(m.picos, [10, 20_000])
        XCTAssertEqual(almacen.mensajes[chat]?.last?.id, m.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path), "el grabado ya esta dentro del proyecto")
    }

    func testLaConversacionSePasaATextoConLosNombres() async throws {
        let (almacen, chat, raiz) = try await chatDePrueba("conversacion")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let u = try audio(raiz, "conversacion-1.m4a")
        let turnos = [TurnoVoz(quien: "Ana", desdeMs: 0, hastaMs: 4_000),
                      TurnoVoz(quien: "Luis", desdeMs: 4_000, hastaMs: 9_000)]
        let hecho = await almacen.adjuntarGrabacion(
            GrabacionVoz(rutaOrigen: u.path, duracionMs: 9_000, picos: [], texto: nil, turnos: turnos), en: chat)
        let m = try XCTUnwrap(hecho, almacen.error ?? "")
        let conTexto = await almacen.ponerTranscripcion(
            [SegmentoVoz(desdeMs: 300, texto: "buenos dias"), SegmentoVoz(desdeMs: 4_500, texto: "hola")],
            en: m.id, chat: chat)
        XCTAssertEqual(conTexto?.transcripcion, "[0:00] **Ana:** buenos dias\n\n[0:04] **Luis:** hola")
    }

    func testUnaNotaDeVozEsUnaLlamadaSecretaConQuienLlama() async throws {
        let (almacen, chat, raiz) = try await chatDePrueba("llamada")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let u = try audio(raiz, "recado.m4a")
        let hecho = await almacen.adjuntarGrabacion(
            GrabacionVoz(rutaOrigen: u.path, duracionMs: 3_000, picos: [], texto: nil, turnos: []), en: chat)
        let m = try XCTUnwrap(hecho, almacen.error ?? "")
        let r = RecordatorioPuesto(chat: chat, id: m.id, cuando: Date(), texto: "")
        let nucleo = almacen.nucleo
        XCTAssertEqual(Recordatorios.llamada(de: r, nucleo: nucleo)?.nombre, "recado")
        XCTAssertEqual(QuienLlama.actual(m, nucleo: nucleo), "recado")
        QuienLlama.poner("  Mamá ", en: m, nucleo: nucleo)
        XCTAssertEqual(QuienLlama.actual(m, nucleo: nucleo), "Mamá")
        // Lo apunta en el Mac (fuera del hilo): se espera a que llegue.
        for _ in 0..<50 where nucleo.quienLlama(mensaje: m.id) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(Recordatorios.llamada(de: r, nucleo: nucleo)?.nombre, "Mamá")
        // Casos negativos: una tarea o una nota escrita no llaman.
        let tarea = RecordatorioPuesto(chat: chat, id: m.id, cuando: Date(), texto: "",
                                       tarea: TareaRecordada(lista: "l", indice: 0))
        XCTAssertNil(Recordatorios.llamada(de: tarea, nucleo: nucleo))
        let nota = await almacen.escribir(nota: "a las diez", en: chat)
        let n = try XCTUnwrap(nota)
        XCTAssertNil(Recordatorios.llamada(de: RecordatorioPuesto(chat: chat, id: n.id, cuando: Date(), texto: ""),
                                           nucleo: nucleo))
    }
}
