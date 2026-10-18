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

    @MainActor
    func testElPinDeUnaTareaPoneSuNotaYSeRelee() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pin-tarea-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let l = try nucleo.apuntarTarea(texto: "llamar al banco prioridad alta", desfaseMs: 0)
        let m = ModeloPinTarea(chat: l.chat, lista: l.mensaje, titulo: "llamar al banco", nucleo: nucleo)
        m.releer()
        XCTAssertFalse(m.seFue)
        XCTAssertEqual(m.marcas?.prioridad, "alta")
        m.ponerNota("no abren")
        XCTAssertEqual(m.marcas?.nota, "no abren")
        m.marcar(true)
        XCTAssertTrue(m.hecha)
        // Caso negativo: una tarea que no esta.
        let otra = ModeloPinTarea(chat: l.chat, lista: l.mensaje, titulo: "nada", nucleo: nucleo)
        otra.releer()
        XCTAssertNil(otra.marcas)
        // Y el pin se abre una vez por tarea.
        PinesDeTareas.compartidos.abrir(chat: l.chat, lista: l.mensaje, titulo: "llamar al banco", nucleo: nucleo)
        PinesDeTareas.compartidos.abrir(chat: l.chat, lista: l.mensaje, titulo: "llamar al banco", nucleo: nucleo)
        XCTAssertEqual(PinesDeTareas.compartidos.cuantos, 1)
        PinesDeTareas.compartidos.cerrar("\(l.chat)/\(l.mensaje)/llamar al banco")
    }
}
