// Los recordatorios (A4) y el centro de avisos comun (C4): la agenda del
// vigia (las pruebas de `Agenda` y `Vigia` de Windows, sin esperar de
// verdad), los avisos con sus botones (las de `notificaciones.rs`), las
// horas que se ofrecen y el aviso «se van en 24 h» de las capturas, que
// cruza el puente sobre una carpeta temporal. Nada pide permiso de
// notificaciones: fuera de una `.app` no hay centro del sistema.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class AgendaRecordatoriosTests: XCTestCase {
    private func rec(_ id: String, _ segundos: TimeInterval, chat: String = "c1") -> RecordatorioPuesto {
        RecordatorioPuesto(chat: chat, id: id, cuando: Date(timeIntervalSince1970: segundos), texto: "lo de \(id)")
    }

    func testUnRecordatorioEnElPasadoSaltaYaYNoSePierde() {
        var a = AgendaRecordatorios()
        a.programar(rec("viejo", 1))
        a.programar(rec("futuro", 9))
        let salen = a.vencidos(a: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(salen.map(\.id), ["viejo"])
        XCTAssertEqual(a.pendientes.map(\.id), ["futuro"], "el de despues sigue puesto")
    }

    func testDosParaElMismoInstanteSaltanLosDos() {
        var a = AgendaRecordatorios()
        a.programar(rec("uno", 5))
        a.programar(rec("otro", 5))
        XCTAssertEqual(a.vencidos(a: Date(timeIntervalSince1970: 5)).count, 2,
                       "sacar solo el primero dejaria el segundo esperando")
        XCTAssertTrue(a.pendientes.isEmpty)
    }

    func testVolverAPonerloCambiaLaHoraEnVezDeDuplicarlo() {
        var a = AgendaRecordatorios()
        a.programar(rec("m1", 9))
        a.programar(rec("m1", 2))
        XCTAssertEqual(a.pendientes.count, 1)
        XCTAssertEqual(a.proximo?.cuando, Date(timeIntervalSince1970: 2))
        // El mismo id en otro chat es otro recordatorio.
        a.programar(rec("m1", 3, chat: "c2"))
        XCTAssertEqual(a.pendientes.count, 2)
    }

    func testCancelarAlgoQueNoEstaDiceQueNoYNoTocaLoDemas() {
        var a = AgendaRecordatorios()
        let r = rec("m1", 9)
        a.programar(r)
        XCTAssertFalse(a.cancelar("recuerdaEn:c1:m9"))
        XCTAssertEqual(a.pendientes.count, 1)
        XCTAssertTrue(a.cancelar(r.clave))
        XCTAssertNil(a.proximo)
        XCTAssertTrue(a.vencidos(a: .distantFuture).isEmpty, "vacia no saca nada")
    }

    func testLaAgendaVaOrdenadaDelMasProximoAlMasLejano() {
        let a = AgendaRecordatorios([rec("tarde", 9), rec("pronto", 1), rec("medio", 5)])
        XCTAssertEqual(a.pendientes.map(\.id), ["pronto", "medio", "tarde"])
    }

    func testLaHoraDeUnaTareaEsLaDelRelojDeLaPared() {
        // Una tarea `⏰ ... 10:30` es a las 10:30 de aqui, con el huso de
        // ese dia: ida y vuelta sin correrse.
        let ahora = Date(timeIntervalSince1970: 1_790_000_000)
        let local = milisegundosLocales(ahora)
        XCTAssertEqual(fechaDeLocales(local).timeIntervalSince1970, ahora.timeIntervalSince1970, accuracy: 0.001)
        let delNucleo = RecordatorioMac(chat: "c", nombreChat: "Obra", id: "tarea:L:\(local)",
                                        cuandoUtcMs: local - desfaseLocalMs(), texto: "☑ yeso",
                                        tarea: TareaRecordada(lista: "L", indice: 0))
        let puesto = RecordatorioPuesto(delNucleo, desfaseHoy: desfaseLocalMs())
        XCTAssertEqual(puesto.cuando.timeIntervalSince1970, ahora.timeIntervalSince1970, accuracy: 0.001)
        // Un mensaje ya viene en UTC.
        let mensaje = RecordatorioMac(chat: "c", nombreChat: "", id: "m1", cuandoUtcMs: 5000,
                                      texto: "x", tarea: nil)
        XCTAssertEqual(RecordatorioPuesto(mensaje, desfaseHoy: 3_600_000).cuando,
                       Date(timeIntervalSince1970: 5))
    }
}

final class AvisosComunesTests: XCTestCase {
    func testLaDeUnaTareaTieneHechaMas10YAbrir() {
        // `la_de_una_tarea_tiene_hecha_mas_10_y_abrir` de Windows.
        let r = RecordatorioPuesto(chat: "pr-1", id: "tarea:L1:123", cuando: Date(timeIntervalSince1970: 60),
                                   texto: "☑ Llamar al banco", tarea: TareaRecordada(lista: "L1", indice: 2))
        let a = AvisosRecordatorio.aviso(de: r)
        XCTAssertEqual(a.categoria.acciones.map(\.rotulo), ["Hecha", "+10 min", "Abrir"])
        XCTAssertEqual(a.titulo, "Recordatorio")
        XCTAssertEqual(a.texto, "☑ Llamar al banco")
        XCTAssertEqual(a.id, "recuerdaEn:pr-1:tarea:L1:123")
        XCTAssertEqual(a.cuando, Date(timeIntervalSince1970: 60))
        XCTAssertEqual(AvisosRecordatorio.tarea(de: a.datos), TareaRecordada(lista: "L1", indice: 2))
        XCTAssertEqual(a.datos[AvisosRecordatorio.claveCuando], "60000")
        XCTAssertEqual(a.categoria.alPulsar, .abrir)
    }

    func testLaDeUnMensajeNoTieneHecha() {
        let r = RecordatorioPuesto(chat: "pr-1", id: "m7", cuando: Date(), texto: "comprar yeso")
        let a = AvisosRecordatorio.aviso(de: r)
        XCTAssertEqual(a.categoria, .recordatorio)
        XCTAssertEqual(a.categoria.acciones.map(\.rotulo), ["+10 min", "Abrir"])
        XCTAssertNil(AvisosRecordatorio.tarea(de: a.datos))
        XCTAssertEqual(a.datos[AvisosRecordatorio.claveId], "m7")
        // Sin texto no sale una notificacion en blanco.
        let vacio = AvisosRecordatorio.aviso(de: RecordatorioPuesto(chat: "c", id: "m", cuando: Date(), texto: "  "))
        XCTAssertEqual(vacio.texto, "Recordatorio")
    }

    func testLaDeLasCapturas() {
        // `la_de_las_capturas` de Windows.
        let ahora = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertNil(AvisoCaducidad.aviso(de: [], ahora: ahora), "sin capturas, nada")
        let una = CapturaCaducada(nombre: "captura-0001.png", ruta: "/c/captura-0001.png",
                                  seVa: milisegundos(ahora) + 3_600_000)
        let a = AvisoCaducidad.aviso(de: [una], ahora: ahora)!
        XCTAssertEqual(a.categoria.acciones.map(\.rotulo), ["Conservar", "Abrir"])
        XCTAssertTrue(a.texto.hasPrefix("Esta captura se va"), a.texto)
        XCTAssertEqual(a.imagen?.path, "/c/captura-0001.png")
        XCTAssertEqual(a.datos[AvisoCaducidad.claveNombre], "captura-0001.png")
        let varias = AvisoCaducidad.aviso(de: [una, una, una], ahora: ahora)!
        XCTAssertTrue(varias.texto.contains("3"), varias.texto)
        XCTAssertEqual(varias.categoria.acciones, [.galeria])
        XCTAssertNil(varias.imagen)
    }

    func testCadaBotonVuelveASuAccion() {
        for c in CategoriaAviso.allCases {
            let sistema = CentroAvisos.categoriaDelSistema(c)
            XCTAssertEqual(sistema.identifier, c.rawValue)
            XCTAssertEqual(sistema.actions.map(\.identifier), c.acciones.map(\.rawValue))
            for a in c.acciones {
                XCTAssertEqual(CentroAvisos.accion(a.rawValue, categoria: c), a)
            }
        }
        // Pulsar el aviso entero hace lo suyo; un boton desconocido, nada.
        XCTAssertEqual(CentroAvisos.accion("com.apple.UNNotificationDefaultActionIdentifier", categoria: .recordatorio), .abrir)
        XCTAssertEqual(CentroAvisos.accion("com.apple.UNNotificationDefaultActionIdentifier", categoria: .capturas), .galeria)
        XCTAssertNil(CentroAvisos.accion("otra-cosa", categoria: .recordatorio))
        // Lo que no es una cadena no viaja.
        XCTAssertEqual(CentroAvisos.datos(de: ["chat": "c", "n": 3, 4: "x"]), ["chat": "c"])
    }

    func testLosRecordatoriosSuenanEnLaAppYLasCapturasNo() {
        XCTAssertTrue(CategoriaAviso.recordatorio.suenaEnLaApp)
        XCTAssertTrue(CategoriaAviso.mini.suenaEnLaApp)
        XCTAssertFalse(CategoriaAviso.captura.suenaEnLaApp)
    }

    @MainActor
    func testLoQueLlegaAntesDeApuntarseSeEntregaDespues() {
        // La app se abre pulsando una notificacion: la respuesta llega antes
        // de que el vigia se apunte a su categoria.
        let centro = CentroAvisos()
        centro.responder(.mini, .abrir, ["id": "x"])
        var oidas: [(AccionAviso, [String: String])] = []
        centro.alResponder([.mini]) { a, d in oidas.append((a, d)) }
        XCTAssertEqual(oidas.count, 1)
        XCTAssertEqual(oidas.first?.0, .abrir)
        XCTAssertEqual(oidas.first?.1, ["id": "x"])
        // «Cerrar» no llega a nadie.
        centro.responder(.mini, .cerrar, [:])
        XCTAssertEqual(oidas.count, 1)
    }

    @MainActor
    func testSinCentroDelSistemaNoSePoneNadaYSeDiceEnLaApp() {
        // Fuera de una `.app` (las pruebas): `poner` dice que no saldra.
        let centro = CentroAvisos()
        centro.preparar()
        XCTAssertEqual(centro.permiso, .sinPaquete)
        XCTAssertFalse(centro.poner(Aviso(id: "x", categoria: .capturas, titulo: "t", texto: "x")))
    }
}

final class AtajosDeHoraTests: XCTestCase {
    private var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }

    private func a(_ dia: Int, _ hora: Int, _ minuto: Int = 0) -> Date {
        calendario.date(from: DateComponents(year: 2026, month: 10, day: dia, hour: hora, minute: minuto))!
    }

    func testNingunaDeLasHorasQueSeOfrecenCaeEnElPasado() {
        for ahora in [a(16, 9, 30), a(16, 18, 30), a(16, 23, 30)] {
            for atajo in AtajosDeHora.atajos(ahora: ahora, calendario: calendario) {
                XCTAssertGreaterThan(atajo.cuando, ahora, "«\(atajo.titulo)» sonaria en el acto")
            }
        }
    }

    func testEstaTardePulsadoDeNocheEsLaTardeDeManana() {
        XCTAssertEqual(AtajosDeHora.aLas(18, dias: 0, ahora: a(16, 22), calendario: calendario), a(17, 18))
        XCTAssertEqual(AtajosDeHora.aLas(9, dias: 1, ahora: a(16, 9, 30), calendario: calendario), a(17, 9))
    }

    func testLaHoraSeLeeConSuFechaCuandoNoEsDeHoy() {
        XCTAssertEqual(AtajosDeHora.legible(a(16, 9, 30), ahora: a(16, 9), calendario: calendario), "09:30")
        XCTAssertEqual(AtajosDeHora.legible(a(17, 9), ahora: a(16, 9), calendario: calendario), "17/10 09:00")
    }
}

final class AvisoCaducidadTests: XCTestCase {
    func testLasQueSeVanEnUnDiaSeAvisanUnaVezPorSesion() throws {
        let raiz = try carpetaTemporal("aviso-caducidad")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let datos = raiz.appendingPathComponent("datos", isDirectory: true)
        let nucleo = try Nucleo.abrir(raiz: datos.path, nombreDelAparato: "Mac de prueba")
        let capturas = URL(fileURLWithPath: nucleo.carpetaCapturas(), isDirectory: true)
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        try Data(#"{"desde": 0}"#.utf8).write(to: datos.appendingPathComponent("capturas-caducidad.json"))
        for (n, dias) in [("pronto.png", 6.5), ("luego.png", 2.0)] {
            let url = capturas.appendingPathComponent(n)
            try Data("png".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-dias * 86_400)],
                                                  ofItemAtPath: url.path)
        }
        let barrendero = BarrenderoCapturas(nucleo: nucleo)
        barrendero.dias = { 7 }
        barrendero.tirar = { _ in XCTFail("no hay nada caducado") }
        let avisos = Caja<[Aviso]>([])
        barrendero.avisar = { avisos.valor.append($0) }
        XCTAssertEqual(barrendero.barrer().avisadas, ["pronto.png"])
        XCTAssertEqual(avisos.valor.map(\.categoria), [.captura])
        XCTAssertEqual(avisos.valor.first?.datos[AvisoCaducidad.claveNombre], "pronto.png")
        // Caso negativo: la siguiente vuelta no la repite.
        XCTAssertTrue(barrendero.barrer().avisadas.isEmpty)
        XCTAssertEqual(avisos.valor.count, 1)
    }
}

/// Algo que se cambia desde un cierre `@Sendable` en las pruebas.
private final class Caja<T>: @unchecked Sendable {
    var valor: T
    init(_ v: T) { valor = v }
}
