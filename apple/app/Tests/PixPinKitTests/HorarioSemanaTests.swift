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
}
