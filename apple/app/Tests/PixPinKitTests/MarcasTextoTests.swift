@testable import PixPinKit
import XCTest

final class MarcasTextoTests: XCTestCase {
    private let palabras: [(texto: String, caja: CGRect, renglon: Int)] = [
        ("Total", CGRect(x: 0.1, y: 0.8, width: 0.1, height: 0.05), 0),
        ("de", CGRect(x: 0.22, y: 0.8, width: 0.04, height: 0.05), 0),
        ("señalización", CGRect(x: 0.28, y: 0.8, width: 0.2, height: 0.05), 0),
        ("vial,", CGRect(x: 0.1, y: 0.7, width: 0.08, height: 0.05), 1),
    ]

    func testLoElegidoSeEncuentraYDaUnaCajaPorRenglon() {
        let c = MarcasDeTexto.cajas(de: "de senalizacion vial", en: palabras)
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0].minX, 0.22, accuracy: 0.001)
        XCTAssertEqual(c[0].maxX, 0.48, accuracy: 0.001)
        // Elegido desde media palabra.
        XCTAssertEqual(MarcasDeTexto.cajas(de: "tal de", en: palabras).count, 1)
        let t = MarcasDeTexto.trazos(.subrayado, color: 0, cajas: c)
        XCTAssertEqual(t.count, 2)
        XCTAssertTrue(t[0].herramienta.esMarcaDeTexto)
        // Casos negativos: lo que no esta, y nada elegido.
        XCTAssertTrue(MarcasDeTexto.cajas(de: "presupuesto", en: palabras).isEmpty)
        XCTAssertTrue(MarcasDeTexto.cajas(de: "  ", en: palabras).isEmpty)
        XCTAssertFalse(HerramientaAnotacion.deBarra.contains(.resaltado), "no van en la barra")
    }
}
