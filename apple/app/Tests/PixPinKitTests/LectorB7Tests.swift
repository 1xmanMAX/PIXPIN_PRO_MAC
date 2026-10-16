// El lector de la tanda B7: buscar dentro del documento, las hojas en
// negativo y en oscuro, la pagina que sube sola, el riel de marcadores y la
// tinta al dia con el disco (releer lo que cambio, juntar al guardar).

import AppKit
import CoreText
import Foundation
import PDFKit
import PixPinCore
@testable import PixPinKit
import XCTest

/// Un PDF de `hojas` hojas con texto de verdad (se puede buscar en el).
private func pdfConTexto(_ hojas: [String]) -> Data {
    let datos = NSMutableData()
    var caja = CGRect(x: 0, y: 0, width: 300, height: 400)
    let consumidor = CGDataConsumer(data: datos as CFMutableData)!
    let ctx = CGContext(consumer: consumidor, mediaBox: &caja, nil)!
    for texto in hojas {
        ctx.beginPDFPage(nil)
        let linea = CTLineCreateWithAttributedString(NSAttributedString(
            string: texto, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        ctx.textPosition = CGPoint(x: 20, y: 300)
        CTLineDraw(linea, ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return datos as Data
}

/// Un contexto de 10 x 10 en RGB con `pintar` hecho, y el color de su centro.
private func pixel(_ pintar: (CGContext) -> Void) -> (r: Int, g: Int, b: Int) {
    let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    pintar(ctx)
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let i = (5 * 10 + 5) * 4
    return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
}

@MainActor
final class LectorB7Tests: XCTestCase {
    // MARK: Buscar

    func testBuscarSinMayusculasNiTildesDaLaVueltaYEmpiezaDondeSeLee() throws {
        let doc = try XCTUnwrap(PDFDocument(data: pdfConTexto([
            "El Árbol de la ciencia", "nada por aqui", "un arbol y otro ARBOL",
        ])))
        let b = BuscadorLector()
        var saltos: [Int] = []
        b.documento = { (doc, 1) }
        b.mostrar = { actual, _ in
            if let p = actual?.pages.first { saltos.append(doc.index(for: p)) }
        }
        b.consulta = "arbol"
        b.abrir()
        b.buscar(ir: true)
        let limite = Date().addingTimeInterval(10)
        while b.buscando, Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(b.total, 3)
        // Se leia la hoja 1: la primera es la de la hoja 2, no la del principio.
        XCTAssertEqual(b.rotulo, "2 de 3")
        XCTAssertEqual(saltos.last, 2)
        b.siguiente()
        XCTAssertEqual(b.rotulo, "3 de 3")
        b.siguiente()
        XCTAssertEqual(b.rotulo, "1 de 3", "del final, vuelta a la primera")
        XCTAssertEqual(saltos.last, 0)
        b.anterior()
        XCTAssertEqual(b.rotulo, "3 de 3", "y de la primera, a la ultima")
        // Caso negativo: lo que no esta, y solo espacios, no encuentran nada.
        b.consulta = "zanahoria"
        b.buscar(ir: true)
        while b.buscando, Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(b.total, 0)
        XCTAssertEqual(b.rotulo, "Sin resultados")
        b.consulta = "   "
        b.buscar(ir: true)
        XCTAssertEqual(b.total, 0)
        XCTAssertEqual(b.rotulo, "")
        b.cerrar()
        XCTAssertFalse(b.abierto)
    }

    // MARK: Negativo y oscuro

    func testLasHojasDelLectorSeInviertenYEnOscuroConservanElTono() throws {
        let doc = try XCTUnwrap(PDFDocument(data: pdfConTexto(["hola"])))
        doc.delegate = DelegadoHojas.compartido
        XCTAssertTrue(doc.page(at: 0) is HojaLector, "las hojas las da el delegado")
        let hoja = CGRect(x: 0, y: 0, width: 10, height: 10)
        let rojo: (CGContext) -> Void = { c in
            c.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            c.fill(CGRect(x: 4, y: 4, width: 2, height: 2))
        }
        // Lo blanco del papel, en negativo, es negro; el rojo, cian.
        let blanco = pixel { HojaLector.pintar(TonoHojas(negativo: true), en: $0, hoja: hoja) { _ in } }
        XCTAssertEqual(blanco.r, 0)
        let negativoRojo = pixel { HojaLector.pintar(TonoHojas(negativo: true), en: $0, hoja: hoja, contenido: rojo) }
        XCTAssertLessThan(negativoRojo.r, 60)
        XCTAssertGreaterThan(negativoRojo.g, 180)
        // En oscuro el papel es el gris de la barra y el rojo sigue rojo.
        let papel = pixel { HojaLector.pintar(TonoHojas(oscuro: true), en: $0, hoja: hoja) { _ in } }
        XCTAssertLessThan(abs(papel.r - 0x1F), 6)
        let oscuroRojo = pixel { HojaLector.pintar(TonoHojas(oscuro: true), en: $0, hoja: hoja, contenido: rojo) }
        XCTAssertGreaterThan(oscuroRojo.r, oscuroRojo.g + 40, "el tono se queda: \(oscuroRojo)")
        // Caso negativo: sin tono, la hoja no se toca.
        XCTAssertNil(TonoHojas().papel)
        XCTAssertEqual(TonosDeDocumentos.compartidos.tono(de: doc), TonoHojas())
    }

    func testLaTintaNegraSeAclaraSobreElPapelOscuro() {
        let negro = ColorLienzo(r: 0.1, g: 0.1, b: 0.1, a: 1)
        let l = LienzoLeido(fondo: negro, caja: nil, figuras: [.tinta(CGPath(rect: .zero, transform: nil), negro)])
        var cache: [ColorLienzo: ColorLienzo] = [:]
        let sobreNegro = l.sobrePapel(ColorLienzo(r: 0, g: 0, b: 0, a: 1), cache: &cache)
        guard case let .tinta(_, c) = sobreNegro.figuras[0] else { return XCTFail("otra figura") }
        XCTAssertGreaterThan(c.r, 0.5)
        // Caso negativo: el amarillo del resaltador ya se lee y no cambia.
        let amarillo = ColorLienzo(r: 1, g: 0.831, b: 0.231, a: 1)
        let otro = LienzoLeido(fondo: negro, caja: nil, figuras: [.tinta(CGPath(rect: .zero, transform: nil), amarillo)])
        guard case let .tinta(_, a) = otro.sobrePapel(ColorLienzo(r: 0, g: 0, b: 0, a: 1), cache: &cache).figuras[0]
        else { return XCTFail("otra figura") }
        XCTAssertEqual(a.r, amarillo.r, accuracy: 0.01)
    }

    // MARK: La pagina que sube sola y el riel

    func testLaPaginaSubeSolaSinPerderLoQueNoLlegaAUnPixel() {
        let a = AvanceLector()
        a.activo = true
        // Sin barra o parada no baja nada.
        XCTAssertEqual(a.paso(ahora: 0, porSegundo: 30, quieta: false, pixel: 1), 0, "la primera vuelta solo apunta")
        // 30 por segundo durante 0,05 s: 1,5 -> baja 1 y guarda 0,5.
        XCTAssertEqual(a.paso(ahora: 0.05, porSegundo: 30, quieta: false, pixel: 1), 1)
        XCTAssertEqual(a.paso(ahora: 0.10, porSegundo: 30, quieta: false, pixel: 1), 2)
        // Un hueco largo cuenta como una decima.
        XCTAssertEqual(a.paso(ahora: 5.0, porSegundo: 30, quieta: false, pixel: 1), 3)
        // Caso negativo: anotando (quieta) no corre ni acumula.
        XCTAssertEqual(a.paso(ahora: 5.1, porSegundo: 30, quieta: true, pixel: 1), 0)
        a.alFinal()
        XCTAssertFalse(a.enMarcha)
        XCTAssertEqual(a.paso(ahora: 6, porSegundo: 30, quieta: false, pixel: 1), 0)
        XCTAssertEqual(otraVelocidadDeLeer(ppm: 230, sentido: 1), 240)
    }

    func testElRielPoneCadaMarcadorASuAlturaDelDocumento() {
        let m = { (y: Double) in MarcaDocumento(id: Int64(y * 10), x: 0.5, y: y, emoji: "⭐") }
        let z = RielMarcasNS.zonas(marcas: [m(0), m(5), m(10)], paginas: 10, alto: 222)
        XCTAssertEqual(z.count, 3)
        XCTAssertEqual(z[0].minY, RielMarcasNS.lado / 2, accuracy: 0.01)
        XCTAssertEqual(z[1].midY, 111, accuracy: 0.5, "a mitad del documento, a mitad del riel")
        XCTAssertLessThanOrEqual(z[2].maxY, 222)
        // Caso negativo: sin hojas, no hay riel.
        XCTAssertTrue(RielMarcasNS.zonas(marcas: [m(1)], paginas: 0, alto: 200).isEmpty)
    }

    // MARK: Al dia con el disco

    func testLaTintaQueCambiaEnElDiscoSeVeYLaDeAquiNoSePisa() throws {
        let raiz = try carpetaTemporal("al-dia")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.appendingPathComponent("almacen").path, nombreDelAparato: "Mac")
        let pdf = raiz.appendingPathComponent("suelto.pdf")
        try pdfConTexto(["hoja"]).write(to: pdf)
        let ed = try nucleo.anotarHoja(documento: pdf.path, pagina: 0, alto: 1866)
        let alDia = AlDiaLector()
        func trazo(_ desde: CGFloat) {
            try? ed.herramienta(nombre: "lapiz")
            _ = ed.puntero(fase: .pulsar, x: Float(desde), y: 100, presion: nil, modificadores: 0, zoom: 1)
            for k in 1...6 {
                _ = ed.puntero(fase: .mover, x: Float(desde) + Float(k) * 20, y: 100 + Float(k) * 5,
                               presion: nil, modificadores: 0, zoom: 1)
            }
            _ = ed.puntero(fase: .soltar, x: Float(desde) + 120, y: 130, presion: nil, modificadores: 0, zoom: 1)
        }
        trazo(10)
        XCTAssertEqual(try alDia.guardar(0, ed).escrito, true)
        let ruta = ed.ruta()
        // Lo propio no cuenta como cambio de fuera.
        XCTAssertEqual(alDia.cambiadas([0: ruta]), [])
        // Otro (el movil, el asistente) anade un trazo en el disco.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ruta)))
            as? [String: Any])
        var elementos = json["elements"] as? [[String: Any]] ?? []
        elementos.append(["id": "del-movil", "type": "freedraw", "x": 300, "y": 300, "width": 50, "height": 0,
                          "strokeWidth": 2, "version": 1, "versionNonce": 7, "updated": 1, "isDeleted": false,
                          "points": [[0, 0], [50, 0]]])
        json["elements"] = elementos
        Thread.sleep(forTimeInterval: 0.02)
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: ruta))
        XCTAssertEqual(alDia.cambiadas([0: ruta]), [0], "cambio en el disco: hay que releerla")
        // Aqui se anota a la vez: al guardar se junta y queda lo de los dos.
        trazo(500)
        let r = try alDia.guardar(0, ed)
        XCTAssertTrue(r.escrito && r.junto)
        let junto = try String(contentsOfFile: ruta, encoding: .utf8)
        XCTAssertTrue(junto.contains("del-movil"), "lo que llego no se pisa")
        let otra = try nucleo.anotarHoja(documento: pdf.path, pagina: 0, alto: 1866)
        XCTAssertEqual(otra.cuantosElementos(), 3, "los dos trazos de aqui y el del movil")
        // Releida, ya no hay nada nuevo.
        alDia.apuntar(0, AlDiaLector.ver(ruta))
        XCTAssertEqual(alDia.cambiadas([0: ruta]), [])
    }
}
