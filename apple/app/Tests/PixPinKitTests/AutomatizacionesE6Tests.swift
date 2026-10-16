// Las automatizaciones (E6): el pedido `automatizacion` de `HacerPedidos`
// (crear, apagar, correr, borrar, con los textos de Windows), una vuelta
// entera por el nucleo con unas manos de Swift de mentira (el puente de
// UniFFI de ida y vuelta) y lo que mira el motor en la carpeta de capturas.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

/// Unas manos de mentira: apuntan lo que el nucleo les pide.
final class ManosDePrueba: ManosAutomatizacion, @unchecked Sendable {
    private let cerrojo = NSLock()
    private(set) var pedidos: [String] = []
    private(set) var preguntas: [(String, String)] = []
    private(set) var empezadas: [String] = []
    private(set) var acabadas: [InformeAutomatizacion] = []

    func empieza(id: String, nombre: String) {
        cerrojo.withLock { empezadas.append(nombre) }
    }

    func confirmar(pregunta: String) -> Bool { false }

    func pedido(json: String) -> String? {
        cerrojo.withLock { pedidos.append(json) }
        return nil
    }

    func asistente(pedido: String, proyecto: String?, imagenes: [String], bloquear: String) -> RespuestaPaso {
        cerrojo.withLock { preguntas.append((pedido, bloquear)) }
        return RespuestaPaso(bien: true, texto: "dos tareas")
    }

    func acabo(informe: InformeAutomatizacion) {
        cerrojo.withLock { acabadas.append(informe) }
    }
}

@MainActor
final class AutomatizacionesE6Tests: XCTestCase {
    /// Una carpeta de prueba nueva (cada prueba la borra al acabar).
    private func carpeta() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-e6-\(UUID().uuidString)")
    }

    func testElPedidoAutomatizacionCreaApagaYBorra() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let h = HacerPedidos()
        var avisos: [String] = []
        h.avisar = { avisos.append($0) }
        h.registrar(almacen: almacen, sincro: nil)
        let receta: ValorPedido = .objeto([
            "nombre": .texto("Resumen"),
            "disparador": .objeto(["tipo": .texto("a_la_hora"), "hora": .texto("08:00"), "dias": .lista([.numero(1)])]),
            "pasos": .texto("[\"Resume mis tareas pendientes\"]"),
        ])
        await h.hacerYa(Pedido("automatizacion", ["operacion": .texto("crear"), "receta": receta]))
        XCTAssertEqual(avisos.last, "Automatización «Resumen» creada.")
        let lista = try almacen.nucleo.automatizaciones()
        XCTAssertEqual(lista.count, 1)
        XCTAssertEqual(lista[0].detalle, "lun a las 08:00 · «Resume mis tareas pendientes»")
        let id = lista[0].id
        await h.hacerYa(Pedido("automatizacion", ["operacion": .texto("desactivar"), "id": .texto(id)]))
        XCTAssertEqual(avisos.last, "Automatización «Resumen» apagada.")
        XCTAssertFalse(try almacen.nucleo.automatizaciones()[0].activa)
        await h.hacerYa(Pedido("automatizacion", ["operacion": .texto("borrar"), "id": .texto(id)]))
        XCTAssertEqual(avisos.last, "Automatización «Resumen» borrada.")
        XCTAssertTrue(try almacen.nucleo.automatizaciones().isEmpty)
        // Casos negativos: una receta que hace bucle no se guarda (y se dice
        // por que), y un id que no esta se dice.
        let bucle: ValorPedido = .objeto([
            "nombre": .texto("x"), "disparador": .texto("al_capturar"),
            "pasos": .lista([.objeto(["herramienta": .texto("capturar_pantalla")])]),
        ])
        await h.hacerYa(Pedido("automatizacion", ["operacion": .texto("crear"), "receta": bucle]))
        XCTAssertTrue(avisos.last?.hasPrefix("No se pudo guardar la automatización:") == true, avisos.last ?? "")
        XCTAssertTrue(avisos.last?.contains("bucle") == true)
        await h.hacerYa(Pedido("automatizacion", ["operacion": .texto("ejecutar"), "id": .texto("no-esta")]))
        XCTAssertEqual(avisos.last, "No hay ninguna automatización «no-esta».")
        XCTAssertTrue(try almacen.nucleo.automatizaciones().isEmpty)
    }

    func testUnaVueltaEnteraConLasManosDeSwift() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let nucleo = almacen.nucleo
        let paso1 = PasoAutomatizacion(esAsistente: true, herramienta: "", args: [],
                                       pedido: "Resume lo de {fecha}", proyecto: nil, imagenes: [])
        let paso2 = PasoAutomatizacion(esAsistente: false, herramienta: "escribir_en_chat",
                                       args: [ArgAutomatizacion(nombre: "texto", valor: "{nombre}: {resultado}")],
                                       pedido: "", proyecto: nil, imagenes: [])
        var ficha = EditorAutomatizacion.nueva()
        ficha.nombre = "Resumen al chat"
        ficha.pasos = [paso1, paso2]
        XCTAssertNil(nucleo.automatizacionRevisar(ficha: ficha))
        let id = try nucleo.automatizacionGuardar(ficha: ficha)
        let manos = ManosDePrueba()
        let informes = try await Task.detached {
            try nucleo.automatizacionesDisparar(disparo: .aMano(id: id), desfaseMs: 0, manos: manos)
        }.value
        XCTAssertEqual(informes.count, 1)
        XCTAssertTrue(informes[0].bien, informes[0].resumen)
        XCTAssertEqual(manos.empezadas, ["Resumen al chat"])
        XCTAssertEqual(manos.acabadas.count, 1)
        XCTAssertEqual(manos.preguntas.first?.1, "a_mano")
        XCTAssertTrue(manos.preguntas.first?.0.hasPrefix("Resume lo de 20") == true)
        XCTAssertEqual(manos.pedidos.count, 1)
        XCTAssertTrue(manos.pedidos[0].contains("\"accion\":\"chat\""), manos.pedidos[0])
        XCTAssertTrue(manos.pedidos[0].contains("Resumen al chat: dos tareas"), manos.pedidos[0])
        XCTAssertEqual(nucleo.automatizacionesHistorial().first?.id, id)
        // Caso negativo: un disparo que no es el suyo no la corre.
        let nada = try await Task.detached {
            try nucleo.automatizacionesDisparar(disparo: .captura(ruta: "/tmp/x.png"), desfaseMs: 0, manos: manos)
        }.value
        XCTAssertTrue(nada.isEmpty)
        XCTAssertEqual(manos.empezadas.count, 1)
    }

    func testLoQueHariaBucleSeBloqueaDentroDeUnPaso() {
        XCTAssertNotNil(automatizacionBloqueada(disparador: "al_capturar", accion: "capturar"))
        XCTAssertNotNil(automatizacionBloqueada(disparador: "a_mano", accion: "automatizacion"))
        // Sin automatizacion en marcha, nada se bloquea.
        XCTAssertNil(MotorAutomatizaciones.compartido.bloqueado("capturar"))
        XCTAssertNil(automatizacionBloqueada(disparador: "al_capturar", accion: "chat"))
    }

    func testElMotorSoloMiraLasImagenesDeLaCarpeta() throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        for n in ["captura-1.png", "foto.JPG", ".tmp-escribiendo.png", "notas.txt"] {
            try Data([1]).write(to: raiz.appendingPathComponent(n))
        }
        XCTAssertEqual(MotorAutomatizaciones.imagenes(en: raiz).sorted(), ["captura-1.png", "foto.JPG"])
        // Caso negativo: una carpeta que no esta no tiene ninguna.
        XCTAssertTrue(MotorAutomatizaciones.imagenes(en: raiz.appendingPathComponent("no")).isEmpty)
    }
}
