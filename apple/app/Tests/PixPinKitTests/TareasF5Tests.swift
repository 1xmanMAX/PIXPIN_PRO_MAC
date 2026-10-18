@testable import PixPinKit
import PixPinCore
import XCTest

final class TareasF5Tests: XCTestCase {
    func testBuscarEncuentraSinTildesYPorEtiqueta() {
        XCTAssertTrue(ModeloTareas.encaja("llamar al banco ⏫ #casa ➕ 2026-10-18", "BANCO #casa"))
        XCTAssertTrue(ModeloTareas.encaja("pagar la calefacción", "calefaccion"))
        XCTAssertTrue(ModeloTareas.encaja("lo que sea", ""))
        // Caso negativo: todas las palabras tienen que estar.
        XCTAssertFalse(ModeloTareas.encaja("llamar al banco", "banco pan"))
    }

    func testLaFilaEnsenaLasChapitasYLaVista() {
        let m = marcasDeTarea(texto: "llamar al banco ⏫ #casa", desfaseMs: 0)
        XCTAssertEqual(m.titulo, "llamar al banco")
        XCTAssertEqual(m.chapitas.first, "⏫")
        XCTAssertEqual(m.vista, "llamar al banco #casa")
        XCTAssertEqual(tareaEntendida(texto: "pan prioridad baja", desfaseMs: 0), "pan 🔽")
    }
}
