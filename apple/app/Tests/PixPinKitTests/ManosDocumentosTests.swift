@testable import PixPinKit
import AppKit
import PDFKit
import PixPinCore
import XCTest

final class ManosDocumentosTests: XCTestCase {
    /// Un PDF de una hoja con texto, hecho aqui.
    private func pdf(_ texto: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("manos-\(UUID().uuidString).pdf")
        var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &caja, nil))
        ctx.beginPDFPage(nil)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = ns
        NSAttributedString(string: texto, attributes: [.font: NSFont.systemFont(ofSize: 48)])
            .draw(at: CGPoint(x: 60, y: 700))
        NSGraphicsContext.current = nil
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    func testMideYPintaLaHojaYVisionLeeSusPalabrasConSuSitio() throws {
        let url = try pdf("Presupuesto final")
        defer { try? FileManager.default.removeItem(at: url) }
        let m = ManosDelAsistente.medidas(url)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].ancho, 595, accuracy: 0.5)
        XCTAssertEqual(m[0].alto, 842, accuracy: 0.5)
        let png = try XCTUnwrap(ManosDelAsistente.pintar(url, pagina: 0, ancho: 1200))
        let img = try XCTUnwrap(NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(img.width, 1200)
        let ps = ManosDelAsistente.palabras(img)
        let textos = ps.map { $0.texto.lowercased() }
        XCTAssertTrue(textos.contains("presupuesto"), "\(textos)")
        let p = try XCTUnwrap(ps.first { $0.texto.lowercased() == "presupuesto" })
        // Arriba de la hoja (y desde arriba), a la izquierda.
        XCTAssertLessThan(p.y, Float(img.height) / 3)
        XCTAssertLessThan(p.x, Float(img.width) / 2)
        // Caso negativo: una hoja que no existe, o un fichero que no es PDF.
        XCTAssertNil(ManosDelAsistente.pintar(url, pagina: 5, ancho: 100))
        XCTAssertTrue(ManosDelAsistente.medidas(URL(fileURLWithPath: "/no/esta.pdf")).isEmpty)
    }
}
