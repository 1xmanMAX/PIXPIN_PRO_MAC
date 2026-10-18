@testable import PixPinKit
import PixPinCore
import XCTest

@MainActor
final class AsistenteF9Tests: XCTestCase {
    func testLaRespuestaSeVeConListasYNegritas() {
        let a = NotaDelAsistente.formateado("### Hoy\n- **pan**\n1) leche")
        let texto = String(a.characters)
        XCTAssertEqual(texto, "Hoy\n•  pan\n1. leche")
        let negritas = a.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(a[$0.range].characters) }
        XCTAssertEqual(negritas, ["Hoy", "pan"])
        // Caso negativo: un texto normal no cambia.
        XCTAssertEqual(String(NotaDelAsistente.formateado("5 * 3 = 15").characters), "5 * 3 = 15")
    }

    func testLaPastillaNombraElMotor() {
        XCTAssertEqual(CabeceraDelAsistente.nombre(de: "claude"), "Claude Haiku")
        XCTAssertEqual(CabeceraDelAsistente.nombre(de: ""), "Local")
        XCTAssertEqual(CabeceraDelAsistente.nombre(de: "otro"), "Local")
    }

    func testConversacionNuevaEsUnaNotaDelAsistente() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("f9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let chat = try nucleo.chatAsistente().id
        let m = try nucleo.iaConversacionNueva(chat: chat)
        XCTAssertTrue(m.esDelAsistente)
        XCTAssertTrue(m.texto.hasPrefix("🧹"))
    }
}
