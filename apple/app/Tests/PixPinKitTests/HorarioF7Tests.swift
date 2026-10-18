@testable import PixPinKit
import PixPinCore
import XCTest

@MainActor
final class HorarioF7Tests: XCTestCase {
    func testLaLlamadaDelHorarioLlevaSuDetalleYSeReconoce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("horario-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let antes = Recordatorios.firma(nucleo)
        let ruta = try nucleo.ficheroDelHorario()
        XCTAssertEqual(ruta, nucleo.rutaDelHorario())
        XCTAssertNotEqual(Recordatorios.firma(nucleo), antes, "crear el horario cambia la firma")
        try "Lun Mar Mie Jue Vie Sab Dom 9:00-10:00 Física\n> repasar el tema 3\n"
            .write(toFile: ruta, atomically: true, encoding: .utf8)
        let a = try XCTUnwrap(nucleo.avisosDelHorario(desfaseMs: desfaseLocalMs()).first)
        XCTAssertEqual(a.nombre, "Física")
        let l = LlamadaSecreta(audio: a.audio ?? "", nombre: a.nombre, chat: "", mensaje: a.id)
        let m = ModeloLlamada(l, nucleo: nucleo, detalle: a.detalle, texto: a.texto)
        XCTAssertTrue(m.esDelHorario)
        XCTAssertEqual(m.textoALeer, "repasar el tema 3")
        XCTAssertTrue(m.detalle.hasPrefix("09:00–10:00"))
        // Caso negativo: la nota de un chat no es del horario.
        let otra = ModeloLlamada(LlamadaSecreta(audio: "", nombre: "x", chat: "c", mensaje: "m1"), nucleo: nucleo)
        XCTAssertFalse(otra.esDelHorario)
    }
}
