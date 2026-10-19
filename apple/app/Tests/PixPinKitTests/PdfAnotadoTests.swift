@testable import PixPinKit
import PDFKit
import PixPinCore
import XCTest

@MainActor
final class PdfAnotadoTests: XCTestCase {
    func testLaTintaQuedaQuemadaEnSuHoja() throws {
        let raiz = try carpetaTemporal("anotado")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.appendingPathComponent("almacen").path, nombreDelAparato: "Mac")
        let pdf = raiz.appendingPathComponent("doc.pdf")
        try pdfConTexto(["hoja uno", "hoja dos"]).write(to: pdf)
        let ed = try nucleo.anotarHoja(documento: pdf.path, pagina: 0, alto: 1866)
        try ed.herramienta(nombre: "lapiz")
        _ = ed.puntero(fase: .pulsar, x: 100, y: 100, presion: nil, modificadores: 0, zoom: 1)
        for k in 1...10 { _ = ed.puntero(fase: .mover, x: 100 + Float(k) * 60, y: 100 + Float(k) * 40, presion: nil, modificadores: 0, zoom: 1) }
        _ = ed.puntero(fase: .soltar, x: 700, y: 500, presion: nil, modificadores: 0, zoom: 1)
        let doc = try XCTUnwrap(PDFDocument(url: pdf))
        let sale = try XCTUnwrap(ControladorLector.pdfConTinta(doc, nombre: "doc") { i, _ in
            i == 0 ? try? leerLienzo(ed.plano()) : nil
        })
        let hecho = try XCTUnwrap(PDFDocument(url: sale))
        XCTAssertEqual(hecho.pageCount, 2)
        XCTAssertTrue(sale.lastPathComponent.hasSuffix("(anotado).pdf"))
        // La hoja 1 lleva algo mas pintado que la de antes (la tinta).
        func tinta(_ d: PDFDocument, _ i: Int) -> Int {
            let img = d.page(at: i)!.thumbnail(of: CGSize(width: 600, height: 800), for: .cropBox)
            let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
            var n = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
                    if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.6 { n += 1 }
                }
            }
            return n
        }
        XCTAssertGreaterThan(tinta(hecho, 0), tinta(doc, 0) + 100, "la tinta se ve en la hoja")
        // Caso negativo: la hoja sin tinta queda igual.
        XCTAssertEqual(tinta(hecho, 1), tinta(doc, 1), accuracy: 30)
    }
}
