// El timeline editable (B5) y la galeria completa (B6) por sus modelos,
// cruzando el puente de verdad sobre carpetas de datos temporales.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class TimelineGaleriaEditablesTests: XCTestCase {
    private func almacenTemporal(_ nombre: String) throws -> (Almacen, URL) {
        let raiz = try carpetaTemporal(nombre)
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        return (almacen, raiz)
    }

    // MARK: Timeline

    func testApuntarCorregirBorrarYDeshacer() async throws {
        let (almacen, raiz) = try almacenTemporal("tl-editable")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let modelo = ModeloTimeline(nucleo: almacen.nucleo)
        await modelo.recargar()
        XCTAssertTrue(modelo.momentos.isEmpty)

        // Escribir y ↩: primer renglon titulo, lo demas descripcion; la
        // foto pegada (un temporal) se mueve a los medios.
        let pegada = raiz.appendingPathComponent("pegada.png")
        try escribirPNG(pegada, ancho: 8, alto: 8)
        modelo.texto = "Llegó el yeso\nfaltaban dos sacos"
        modelo.anadirFoto(pegada, temporal: true)
        let hecho = await modelo.enviar()
        XCTAssertTrue(hecho)
        XCTAssertEqual(modelo.texto, "")
        XCTAssertTrue(modelo.pegadas.isEmpty)
        XCTAssertEqual(modelo.momentos.map(\.titulo), ["Llegó el yeso"])
        XCTAssertEqual(modelo.momentos.first?.descripcion, "faltaban dos sacos")
        XCTAssertEqual(modelo.momentos.first?.fotos.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pegada.path))
        // Caso negativo: la caja vacia no apunta nada.
        let nada = await modelo.enviar()
        XCTAssertFalse(nada)

        // ↑ con la caja vacia corrige el ultimo; ↩ guarda.
        await modelo.corregirElUltimo()
        XCTAssertEqual(modelo.texto, "Llegó el yeso\nfaltaban dos sacos")
        XCTAssertNotNil(modelo.corrigiendo)
        modelo.texto = "Llegaron diez sacos"
        await modelo.enviar()
        XCTAssertNil(modelo.corrigiendo)
        XCTAssertEqual(modelo.momentos.first?.titulo, "Llegaron diez sacos")
        XCTAssertEqual(modelo.momentos.first?.descripcion, "")

        // A «Momentos» y la bombilla.
        let m = try XCTUnwrap(modelo.momentos.first)
        await modelo.alternarMomentos(m)
        XCTAssertEqual(modelo.momentos.first?.enMomentos, true)
        await modelo.cambiar(a: .momentos)
        XCTAssertEqual(modelo.archivo.count, 1)
        await modelo.cambiar(a: .hoy)
        await modelo.alternarLeccion(try XCTUnwrap(modelo.momentos.first))
        XCTAssertNotNil(modelo.momentos.first?.leccion)

        // Borrar con deshacer (⌘Z).
        await modelo.borrar(try XCTUnwrap(modelo.momentos.first))
        XCTAssertTrue(modelo.momentos.isEmpty)
        XCTAssertNotNil(modelo.deshacer)
        await modelo.deshacerBorrado()
        XCTAssertEqual(modelo.momentos.count, 1)
        XCTAssertNil(modelo.deshacer)

        // Buscar en todo y exportar lo encontrado.
        modelo.consulta = "SACOS"
        await modelo.buscar()
        XCTAssertEqual(modelo.modo, .buscar)
        XCTAssertEqual(modelo.encontrados.count, 1)
        let pagina = try await modelo.paginaParaExportar()
        XCTAssertEqual(pagina.cuantos, 1)
        XCTAssertTrue(pagina.html.contains("Llegaron diez sacos"))
        // En «Lecciones» el buscador no tapa la pestana.
        await modelo.cambiar(a: .lecciones)
        modelo.consulta = "x"
        XCTAssertEqual(modelo.modo, .pestana(.lecciones))
    }

    func testElCalendarioEligeDiasParaExportar() async throws {
        let (almacen, raiz) = try almacenTemporal("tl-calendario")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let modelo = ModeloTimeline(nucleo: almacen.nucleo)
        _ = await modelo.apuntar(texto: "Pizza 🍕", fotos: [], audio: nil)
        await modelo.cambiar(a: .estado)
        let hoy = try XCTUnwrap(modelo.meses.first?.dias.first { $0.cuantos > 0 })
        XCTAssertEqual(hoy.circulo, .emoticonos(lista: ["🍕"]))
        // Sin eleccion: los dias del mes con algo; con ella, los elegidos.
        XCTAssertEqual(modelo.queExportar(), .dias(isos: [hoy.iso]))
        modelo.elegidos = [hoy.iso]
        XCTAssertEqual(modelo.queExportar(), .dias(isos: [hoy.iso]))
        // Fuera de «Calendario» la eleccion se olvida.
        await modelo.cambiar(a: .hoy)
        XCTAssertTrue(modelo.elegidos.isEmpty)
        XCTAssertEqual(modelo.queExportar(), .ultimas24h)
    }

    // MARK: Galeria

    func testLaGaleriaBuscaYAgrupaPorDias() async throws {
        let (almacen, raiz) = try almacenTemporal("galeria-buscar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let capturas = URL(fileURLWithPath: almacen.nucleo.carpetaCapturas(), isDirectory: true)
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        for n in ["factura-luz.png", "pantalla-1.png"] {
            try escribirPNG(capturas.appendingPathComponent(n), ancho: 16, alto: 16)
        }
        let modelo = ModeloGaleria(almacen: almacen)
        await modelo.recargar()
        XCTAssertEqual(modelo.total, 2)
        XCTAssertEqual(modelo.grupos.count, 1, "las dos son de hoy")
        XCTAssertTrue(ModeloGaleria.rotulo(modelo.grupos[0].fecha).hasPrefix("Hoy"))

        modelo.consulta = "FACTURA"
        await modelo.recargar()
        XCTAssertEqual(modelo.capturas.map(\.nombre), ["factura-luz.png"])
        XCTAssertEqual(modelo.enLaCarpeta, 2, "el subtitulo cuenta todas")
        // El texto de dentro, apuntado por el lector.
        try almacen.nucleo.galeriaPonerTexto(nombre: "pantalla-1.png", texto: "Total a pagar")
        modelo.consulta = "pagar"
        await modelo.recargar()
        XCTAssertEqual(modelo.capturas.map(\.nombre), ["pantalla-1.png"])
        // Caso negativo: nada encaja.
        modelo.consulta = "zzz"
        await modelo.recargar()
        XCTAssertTrue(modelo.capturas.isEmpty)
    }

    func testLosDiasLasColumnasYLosNombresLibres() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let ahora = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertTrue(ModeloGaleria.rotulo(ahora, ahora: ahora, calendario: cal).hasPrefix("Hoy · "))
        XCTAssertTrue(ModeloGaleria.rotulo(ahora.addingTimeInterval(-86_400), ahora: ahora, calendario: cal)
            .hasPrefix("Ayer · "))
        XCTAssertEqual(ModeloGaleria.columnas(ancho: 100), 1)
        XCTAssertEqual(ModeloGaleria.columnas(ancho: 820), 4)

        let raiz = try carpetaTemporal("galeria-libre")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = raiz.appendingPathComponent("c.png")
        XCTAssertEqual(ModeloGaleria.libre(a), a)
        try Data([1]).write(to: a)
        XCTAssertEqual(ModeloGaleria.libre(a).lastPathComponent, "c (2).png")
    }
}
