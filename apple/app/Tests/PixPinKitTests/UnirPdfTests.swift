@testable import PixPinKit
import AppKit
import PDFKit
import XCTest

final class UnirPdfTests: XCTestCase {
    private func pdf(_ hojas: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID().uuidString).pdf")
        var caja = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ctx = CGContext(url as CFURL, mediaBox: &caja, nil)!
        for _ in 0 ..< hojas { ctx.beginPDFPage(nil); ctx.endPDFPage() }
        ctx.closePDF()
        return url
    }

    func testUneLasHojasEnOrden() throws {
        let a = pdf(2), b = pdf(3)
        let u = try XCTUnwrap(ChatAbierto.unir([a, b]))
        XCTAssertEqual(PDFDocument(url: u)?.pageCount, 5)
        XCTAssertTrue(u.lastPathComponent.hasSuffix("(unido).pdf"))
        // Caso negativo: uno que no es un PDF.
        XCTAssertNil(ChatAbierto.unir([a, URL(fileURLWithPath: "/no/esta.pdf")]))
    }
}
