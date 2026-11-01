@testable import PixPinKit
import PixPinCore
import SwiftUI
import XCTest

@MainActor
final class HorarioSemanaTests: XCTestCase {
    func testPonerMoverYBorrarUnaClaseQuedaEnElHorario() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("semana-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let m = ModeloSemana(nucleo: nucleo)
        m.cambiar { _ = $0.anadirAsignatura(escrito: "Física") }
        XCTAssertEqual(m.asignaturas.map(\.nombre), ["Física"])
        m.cambiar { $0.soltar(asignatura: 0, dia: 2, minuto: 10 * 60) }
        XCTAssertEqual(m.bloques.first?.dia, 2)
        m.cambiar { $0.mover(i: 0, dia: 4, inicio: 11 * 60) }
        XCTAssertEqual(m.bloques.first?.dia, 4)
        XCTAssertEqual(m.bloques.first?.inicio, 11 * 60)
        let texto = try String(contentsOfFile: nucleo.ficheroDelHorario(), encoding: .utf8)
        XCTAssertTrue(texto.contains("Física"), texto)
        m.cambiar { $0.borrar(i: 0) }
        XCTAssertTrue(m.bloques.isEmpty)
        XCTAssertNil(m.error)
        XCTAssertEqual(VentanaHorario.color(0xFF0000), Color(red: 1, green: 0, blue: 0))
    }

    /// El «+» de «Nueva asignatura»: la guarda, le crea su lista de tareas
    /// y, si se repite, no anade otra; borrar una clase se deshace.
    func testAnadirUnaAsignaturaConElMasYDeshacer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("semana-mas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let m = ModeloSemana(nucleo: nucleo)
        XCTAssertNil(m.anadir("   "))
        XCTAssertEqual(m.anadir("Geometría @A-12"), "Geometría")
        XCTAssertEqual(m.asignaturas.map(\.aula), ["A-12"])
        XCTAssertEqual(m.aviso, "Arrastra «Geometría» a la semana")
        let texto = try String(contentsOfFile: nucleo.ficheroDelHorario(), encoding: .utf8)
        XCTAssertTrue(texto.contains("## Asignaturas\nAsignatura Geometría @A-12\n"), texto)
        let listas = try nucleo.tareas(desfaseMs: 0)
        XCTAssertNotNil(nucleo.listaDeAsignatura(listas: listas, asignatura: "geometria"))
        XCTAssertEqual(m.anadir("GEOMETRIA"), "Geometría")
        XCTAssertEqual(m.asignaturas.count, 1)
        m.cambiar { $0.soltar(asignatura: 0, dia: 0, minuto: 8 * 60) }
        m.cambiar { $0.borrar(i: 0) }
        XCTAssertTrue(m.bloques.isEmpty)
        m.deshacer()
        XCTAssertEqual(m.bloques.count, 1)
        XCTAssertNil(m.error)
    }
}
