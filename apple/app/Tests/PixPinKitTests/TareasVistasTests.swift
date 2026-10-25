@testable import PixPinKit
import PixPinCore
import XCTest

/// Las vistas de Tareas (Tarjetas, Kanban, Horario) y «clase» y «carpeta»
/// en Buscar (Windows 5139e5d y 22c3ce2, 25-oct-2026).
final class TareasVistasTests: XCTestCase {
    func testLasVistasSinListaYSusAtajos() {
        XCTAssertEqual(VistaTareas.todas.map(\.rotulo), ["Tarjetas", "Kanban", "Horario"])
        XCTAssertEqual(VistaTareas.todas.map(\.letraAtajo), ["t", "k", "h"])
        XCTAssertEqual(VistaTareas.horario.pista, "Horario · ⌃⌘H")
        // Lo que el Mac guardaba antes abre en las tarjetas.
        XCTAssertEqual(vistaTareasDeTexto(texto: "Por fecha"), .tarjetas)
        XCTAssertEqual(vistaTareasDeTexto(texto: VistaPedidaDeTareas.horario.rawValue), .horario)
    }

    func testClaseYCarpetasEnBuscar() {
        XCTAssertTrue(accionesBuscar(para: "clase").contains(.grabarClase))
        XCTAssertTrue(accionesBuscar(para: "reunión").contains(.grabarClase))
        XCTAssertEqual(AccionBuscar.consultaDeCarpetas("carpeta Diario de obra"), "Diario de obra")
        XCTAssertEqual(AccionBuscar.consultaDeCarpetas("carp"), "")
        XCTAssertTrue(AccionBuscar.soloCarpetas("Cuaderno x"))
        // Sin carpetas leidas, crearla; con una que se llama asi, no.
        XCTAssertEqual(accionesBuscar(para: "carpeta diario"), [.nuevaCarpeta("diario")])
        let c = CarpetaDeFlow(chat: "1", nombreChat: "Obra", id: "2", nombre: "Diario", paginas: 2,
                              grabacion: false, cuando: 0)
        let g = CarpetaDeFlow(chat: "1", nombreChat: "Obra", id: "3", nombre: "Diario clase", paginas: 1,
                              grabacion: true, cuando: 0)
        let v = accionesBuscar(para: "carpeta diario", carpetas: CarpetasDeFlow(carpetas: [c, g], exacta: true))
        XCTAssertEqual(v, [.carpeta(c), .paginaEnCarpeta(c), .carpeta(g)], "la grabada sin «Nueva página»")
        // Casos negativos: otra palabra no es de las carpetas.
        XCTAssertNil(AccionBuscar.consultaDeCarpetas("car"))
        XCTAssertNil(AccionBuscar.consultaDeCarpetas("galeria carpeta"))
        XCTAssertFalse(AccionBuscar.soloCarpetas("carp"))
    }
}
