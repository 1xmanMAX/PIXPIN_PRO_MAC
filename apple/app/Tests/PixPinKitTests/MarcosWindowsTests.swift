import PDFKit
import XCTest
@testable import PixPinKit

@MainActor
final class MarcosWindowsTests: XCTestCase {
    /// Las unidades de Windows: 1400 de ancho por hoja, seguidas con 18 de
    /// hueco y la Y hacia abajo; ida y vuelta sin perder nada.
    func testLasUnidadesDelLectorSonLasDeWindows() throws {
        let doc = PDFDocument()
        for _ in 0..<2 {
            let img = NSImage(size: NSSize(width: 600, height: 800), flipped: false) { r in
                NSColor.white.setFill(); r.fill(); return true
            }
            doc.insert(PDFPage(image: img)!, at: doc.pageCount)
        }
        let h = HojasDelLector(doc, caja: .mediaBox)
        let b = doc.page(at: 1)!.bounds(for: .mediaBox)
        XCTAssertEqual(h.altos[0], 1400 * 800 / 600, accuracy: 0.01)
        XCTAssertEqual(h.arriba[1], h.altos[0] + 18, accuracy: 0.01)
        // Arriba a la izquierda de la hoja 2 = (0, arriba[1]).
        let u = h.unidades(CGPoint(x: b.minX, y: b.maxY), hoja: 1, bounds: b)
        XCTAssertEqual(u.x, 0, accuracy: 0.01)
        XCTAssertEqual(u.y, h.arriba[1], accuracy: 0.01)
        let p = h.punto(CGPoint(x: 700, y: h.arriba[1] + 100), bounds: b, hoja: h.hoja(de: h.arriba[1] + 100))
        XCTAssertEqual(p.x, b.midX, accuracy: 0.01)
        XCTAssertEqual(h.hoja(de: h.arriba[1] + 100), 1)
    }
}
