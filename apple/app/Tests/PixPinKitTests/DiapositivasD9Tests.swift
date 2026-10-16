// La tanda D9: presentar un PowerPoint como Windows (`diapositivas.rs`: el
// pase, las teclas, el clic por tercios, el reparto de pantallas, la vista
// del orador, las transiciones) y el visor de HTML (`visor_html.rs`: el
// filtro de guardar y escribir encima sin dejarlo a medias).

import AppKit
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

/// Un `.pptx` de tres diapositivas con `/usr/bin/zip`: la primera con notas,
/// la segunda entra empujando hacia arriba y pasa sola a los 3 s.
private func pptx(en carpeta: URL) throws -> URL {
    let ns = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#
    let rels = #"xmlns="http://schemas.openxmlformats.org/package/2006/relationships""#
    let t = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    let caja = #"<p:sp><p:nvSpPr><p:cNvPr id="2" name="R"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="4572000" cy="5143500"/></a:xfrm><a:prstGeom prst="rect"/><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></p:spPr></p:sp>"#
    func diapositiva(_ transicion: String, notas: Bool) -> (String, String) {
        let rn = notas ? #"<Relationship Id="rN" Type="\#(t)/notesSlide" Target="../notesSlides/notesSlide1.xml"/>"# : ""
        return (#"<p:sld \#(ns)><p:cSld><p:spTree>\#(caja)</p:spTree></p:cSld>\#(transicion)</p:sld>"#,
                #"<Relationships \#(rels)><Relationship Id="rL" Type="\#(t)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>\#(rn)</Relationships>"#)
    }
    let (s1, r1) = diapositiva("", notas: true)
    let (s2, r2) = diapositiva(#"<p:transition spd="med" advTm="3000"><p:push dir="u"/></p:transition>"#, notas: false)
    let (s3, r3) = diapositiva("", notas: false)
    let partes: [(String, String)] = [
        ("[Content_Types].xml", #"<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>"#),
        ("_rels/.rels", #"<Relationships \#(rels)><Relationship Id="r1" Type="\#(t)/officeDocument" Target="ppt/presentation.xml"/></Relationships>"#),
        ("ppt/presentation.xml", #"<p:presentation \#(ns)><p:sldIdLst><p:sldId id="256" r:id="rS1"/><p:sldId id="257" r:id="rS2"/><p:sldId id="258" r:id="rS3"/></p:sldIdLst><p:sldSz cx="9144000" cy="5143500"/></p:presentation>"#),
        ("ppt/_rels/presentation.xml.rels", #"<Relationships \#(rels)><Relationship Id="rS1" Type="\#(t)/slide" Target="slides/slide1.xml"/><Relationship Id="rS2" Type="\#(t)/slide" Target="slides/slide2.xml"/><Relationship Id="rS3" Type="\#(t)/slide" Target="slides/slide3.xml"/></Relationships>"#),
        ("ppt/slides/slide1.xml", s1), ("ppt/slides/_rels/slide1.xml.rels", r1),
        ("ppt/slides/slide2.xml", s2), ("ppt/slides/_rels/slide2.xml.rels", r2),
        ("ppt/slides/slide3.xml", s3), ("ppt/slides/_rels/slide3.xml.rels", r3),
        ("ppt/slideLayouts/slideLayout1.xml", #"<p:sldLayout \#(ns)><p:cSld><p:spTree/></p:cSld></p:sldLayout>"#),
        ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", #"<Relationships \#(rels)><Relationship Id="rM" Type="\#(t)/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>"#),
        ("ppt/slideMasters/slideMaster1.xml", #"<p:sldMaster \#(ns)><p:cSld><p:spTree/></p:cSld></p:sldMaster>"#),
        ("ppt/notesSlides/notesSlide1.xml", #"<p:notes \#(ns)><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="3" name="N"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:bodyPr/><a:p><a:r><a:t>Saludar al publico</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>"#),
    ]
    let raiz = carpeta.appendingPathComponent("partes", isDirectory: true)
    for (nombre, xml) in partes {
        let f = raiz.appendingPathComponent(nombre)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xml.write(to: f, atomically: true, encoding: .utf8)
    }
    let destino = carpeta.appendingPathComponent("charla.pptx")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = raiz
    zip.arguments = ["-q", "-X", "-r", destino.path, "."]
    try zip.run()
    zip.waitUntilExit()
    XCTAssertEqual(zip.terminationStatus, 0)
    return destino
}

final class DiapositivasD9Tests: XCTestCase {
    private var carpeta: URL!

    override func setUpWithError() throws {
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-d9-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: carpeta)
    }

    func testLasTeclasDePowerPointYDeLosMandosPasanDiapositivas() {
        let m = { (k: UInt16, c: String, s: Bool) in CuentasDiapositivas.mando(tecla: k, caracteres: c, mayusculas: s) }
        for k: UInt16 in [124, 125, 121, 49, 36] { XCTAssertEqual(m(k, "", false), .siguiente, "\(k)") }
        for k: UInt16 in [123, 126, 116, 51] { XCTAssertEqual(m(k, "", false), .anterior, "\(k)") }
        XCTAssertEqual(m(35, "p", false), .anterior)
        XCTAssertEqual(m(49, " ", true), .anterior, "⇧Espacio vuelve")
        XCTAssertEqual(m(115, "", false), .primera)
        XCTAssertEqual(m(119, "", false), .ultima)
        XCTAssertEqual(m(53, "", false), .salir)
        XCTAssertEqual(m(11, "b", false), .negro)
        XCTAssertEqual(m(47, ".", false), .negro)
        XCTAssertEqual(m(45, "N", false), .notas)
        XCTAssertEqual(m(17, "t", false), .transiciones)
        // Caso negativo: otra letra no hace nada.
        XCTAssertNil(m(0, "a", false))
    }

    func testUnClicPasaPorTerciosComoElDedoEnElMovil() {
        XCTAssertEqual(CuentasDiapositivas.mando(clicEn: 100, ancho: 900), .anterior)
        XCTAssertEqual(CuentasDiapositivas.mando(clicEn: 450, ancho: 900), .pastilla)
        XCTAssertEqual(CuentasDiapositivas.mando(clicEn: 800, ancho: 900), .siguiente)
    }

    func testElPaseNoDaLaVueltaNiSeSaleDeLaPresentacion() {
        var p = PaseDiapositivas(actual: 0, total: 3)
        XCTAssertTrue(p.aplicar(.anterior))
        XCTAssertEqual(p.actual, 0)
        XCTAssertFalse(p.puedeAnterior)
        _ = p.aplicar(.ultima)
        XCTAssertEqual(p.actual, 2)
        _ = p.aplicar(.siguiente)
        XCTAssertEqual(p.actual, 2, "de la ultima no se pasa")
        XCTAssertFalse(p.puedeSiguiente)
        _ = p.aplicar(.primera)
        XCTAssertEqual(p.actual, 0)
        XCTAssertFalse(p.aplicar(.salir))
    }

    func testEnNegroElPrimerMandoSoloEnciendeLaPantalla() {
        var p = PaseDiapositivas(actual: 1, total: 3)
        _ = p.aplicar(.negro)
        XCTAssertTrue(p.negro)
        // Las notas y las transiciones no lo encienden ni mueven el pase.
        _ = p.aplicar(.notas)
        _ = p.aplicar(.transiciones)
        XCTAssertTrue(p.negro)
        XCTAssertEqual(p.actual, 1)
        _ = p.aplicar(.siguiente)
        XCTAssertFalse(p.negro)
        XCTAssertEqual(p.actual, 2, "PowerPoint: enciende y pasa")
        _ = p.aplicar(.negro)
        _ = p.aplicar(.negro)
        XCTAssertFalse(p.negro, "B otra vez solo enciende")
        XCTAssertEqual(p.actual, 2)
    }

    func testSinSaberCuantasHayNoSePasaDeLaPrimera() {
        var p = PaseDiapositivas()
        XCTAssertTrue(p.puedeSiguiente)
        _ = p.aplicar(.siguiente)
        XCTAssertEqual(p.actual, 0)
    }

    func testUnaDiapositivaApaisadaSeEncajaCentradaConFranjas() {
        let c = CuentasDiapositivas.encajar(CGSize(width: 960, height: 540), en: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(c.width, 1000, accuracy: 0.01)
        XCTAssertEqual(c.height, 562.5, accuracy: 0.01)
        XCTAssertEqual(c.minY, (1000 - 562.5) / 2, accuracy: 0.01)
        let e = CuentasDiapositivas.encajarEntera(CGSize(width: 960, height: 540), en: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(e.minY, e.minY.rounded())
        XCTAssertEqual(e.height, e.height.rounded())
    }

    func testConDosPantallasElOradorSeQuedaLaPrincipal() {
        XCTAssertNil(CuentasDiapositivas.repartir(pantallas: 0, principal: 0))
        let una = CuentasDiapositivas.repartir(pantallas: 1, principal: 0)
        XCTAssertEqual(una?.presentacion, 0)
        XCTAssertNil(una?.orador)
        let dos = CuentasDiapositivas.repartir(pantallas: 2, principal: 0)
        XCTAssertEqual(dos?.presentacion, 1)
        XCTAssertEqual(dos?.orador, 0)
        let otra = CuentasDiapositivas.repartir(pantallas: 3, principal: 2)
        XCTAssertEqual(otra?.orador, 2)
        XCTAssertEqual(otra?.presentacion, 0)
    }

    func testElCronometroYElReloj() {
        XCTAssertEqual(CuentasDiapositivas.cronometro(segundos: 0), "00:00")
        XCTAssertEqual(CuentasDiapositivas.cronometro(segundos: 307), "05:07")
        XCTAssertEqual(CuentasDiapositivas.cronometro(segundos: 3723), "1:02:03")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(CuentasDiapositivas.hora(Date(timeIntervalSince1970: 14 * 3600 + 5 * 60), calendario: cal), "14:05")
    }

    func testLaVistaDelOradorCabeYNoSePisa() {
        for (w, h) in [(1440.0, 900.0), (1920.0, 1080.0), (1024.0, 768.0)] {
            let z = CuentasDiapositivas.zonasOrador(ancho: w, alto: h, pagina: CGSize(width: 960, height: 540))
            let todo = CGRect(x: 0, y: 0, width: w, height: h)
            for r in [z.actual, z.siguiente, z.notas] { XCTAssertTrue(todo.contains(r), "\(r)") }
            XCTAssertFalse(z.actual.intersects(z.siguiente))
            XCTAssertFalse(z.actual.intersects(z.notas))
            XCTAssertFalse(z.siguiente.intersects(z.notas))
            XCTAssertGreaterThan(z.actual.width, z.siguiente.width)
            XCTAssertGreaterThan(z.notas.height, h * 0.2, "sitio para las notas")
        }
    }

    func testLaTransicionSoloAlAvanzarDeUnaEnUna() {
        XCTAssertTrue(CuentasDiapositivas.tocaTransicion(antes: 2, ahora: 3, encendidas: true, ms: 500))
        XCTAssertFalse(CuentasDiapositivas.tocaTransicion(antes: 3, ahora: 2, encendidas: true, ms: 500), "atras, de golpe")
        XCTAssertFalse(CuentasDiapositivas.tocaTransicion(antes: 0, ahora: 5, encendidas: true, ms: 500), "saltando")
        XCTAssertFalse(CuentasDiapositivas.tocaTransicion(antes: 2, ahora: 3, encendidas: false, ms: 500), "T apagadas")
        XCTAssertFalse(CuentasDiapositivas.tocaTransicion(antes: 2, ahora: 3, encendidas: true, ms: 0), "un corte")
        XCTAssertFalse(CuentasDiapositivas.tocaTransicion(antes: 2, ahora: 3, encendidas: true, ms: nil))
        XCTAssertEqual(CuentasDiapositivas.progreso(transcurrido: 0.25, ms: 500), 0.5, accuracy: 0.001)
        XCTAssertEqual(CuentasDiapositivas.progreso(transcurrido: 9, ms: 500), 1)
        XCTAssertEqual(CuentasDiapositivas.progreso(transcurrido: 0, ms: 0), 1)
    }

    func testLasCapasDeRustSePonenEnSuCaja() {
        let caja = CGRect(x: 100, y: 50, width: 800, height: 450)
        // Un empuje hacia la izquierda a medias: la vieja sale por la
        // izquierda y la nueva entra por la derecha.
        let capas = capasDeTransicion(efecto: .empuje(dx: -1, dy: 0), t: 0.5)
        XCTAssertEqual(capas.count, 2)
        let vieja = capas.first { $0.fuente == .vieja }!
        let nueva = capas.first { $0.fuente == .nueva }!
        XCTAssertLessThan(CuentasDiapositivas.trozo(vieja.destino, de: caja).minX, caja.minX)
        XCTAssertGreaterThan(CuentasDiapositivas.trozo(nueva.destino, de: caja).minX, caja.minX)
        XCTAssertEqual(CuentasDiapositivas.trozo([0, 0, 1, 1], de: caja), caja)
        // Al acabar, solo la nueva entera.
        let fin = capasDeTransicion(efecto: .fundido(porNegro: true), t: 1)
        XCTAssertEqual(fin.map(\.fuente), [.nueva])
    }

    func testSoloSePresentaLoQueMaquetaPixPin() {
        XCTAssertTrue(CuentasDiapositivas.sePresenta(URL(fileURLWithPath: "/x/charla.pptx")))
        XCTAssertTrue(CuentasDiapositivas.sePresenta(URL(fileURLWithPath: "/x/CHARLA.PPSX")))
        XCTAssertFalse(CuentasDiapositivas.sePresenta(URL(fileURLWithPath: "/x/vieja.ppt")))
        XCTAssertFalse(CuentasDiapositivas.sePresenta(URL(fileURLWithPath: "/x/acta.docx")))
    }

    func testUnPowerPointSeAbrePintaYDaSusNotasYTransiciones() throws {
        let url = try pptx(en: carpeta)
        let a = try XCTUnwrap(ArchivoDiapositivas.abrir(url))
        XCTAssertEqual(a.total, 3)
        XCTAssertEqual(a.tamano.width / a.tamano.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertTrue(a.notasSiHay(0) == nil, "nada leido aun")
        XCTAssertEqual(a.notas(0), "Saludar al publico")
        XCTAssertEqual(a.notasSiHay(0), .some("Saludar al publico"))
        XCTAssertNil(a.notas(1))
        XCTAssertNil(a.transicion(0))
        let t = try XCTUnwrap(a.transicion(1))
        XCTAssertEqual(t.efecto, .empuje(dx: 0, dy: -1))
        XCTAssertEqual(t.avanceMs, 3000)
        XCTAssertTrue(a.medios(0).isEmpty)
        // Pintada a la medida pedida: la mitad izquierda roja, la derecha
        // blanca (el papel).
        let f = try XCTUnwrap(a.foto(0, pixeles: CGSize(width: 320, height: 180)))
        XCTAssertEqual(f.width, 320)
        XCTAssertEqual(f.height, 180)
        let rep = NSBitmapImageRep(cgImage: f)
        let izq = try XCTUnwrap(rep.colorAt(x: 40, y: 90)?.usingColorSpace(.sRGB))
        let der = try XCTUnwrap(rep.colorAt(x: 280, y: 90)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(izq.redComponent, 0.9)
        XCTAssertLessThan(izq.greenComponent, 0.3)
        XCTAssertGreaterThan(der.greenComponent, 0.9)
        XCTAssertNil(a.foto(7, pixeles: CGSize(width: 320, height: 180)), "una que no existe")
    }

    func testLoQueNoEsUnPowerPointNoSePresenta() throws {
        let falso = carpeta.appendingPathComponent("falso.pptx")
        try Data("no soy un zip".utf8).write(to: falso)
        XCTAssertNil(ArchivoDiapositivas.abrir(falso))
    }
}

final class VisorHtmlD9Tests: XCTestCase {
    private func html(_ relleno: Int) -> Data {
        Data("<html><body>\(String(repeating: "a", count: relleno))</body></html>".utf8)
    }

    func testSoloAbreHtmls() {
        XCTAssertTrue(VisorHtml.seAbre(URL(fileURLWithPath: "/x/informe.html")))
        XCTAssertTrue(VisorHtml.seAbre(URL(fileURLWithPath: "/x/INFORME.HTM")))
        XCTAssertFalse(VisorHtml.seAbre(URL(fileURLWithPath: "/x/plano.pdf")))
        XCTAssertFalse(VisorHtml.seAbre(URL(fileURLWithPath: "/x/pagina.html.txt")))
        XCTAssertTrue(VisorHtml.esLaPagina(nombreSugerido: "tabla.html"))
        XCTAssertFalse(VisorHtml.esLaPagina(nombreSugerido: "tabla.csv"), "un CSV es una descarga de verdad")
    }

    func testElFiltroDeGuardarEsElDeAndroid() {
        XCTAssertTrue(VisorHtml.pareceHtmlCompleto(html(300)))
        XCTAssertFalse(VisorHtml.pareceHtmlCompleto(Data("<html></html>".utf8)), "corto aunque cierre")
        var justo = Data("</html>".utf8)
        justo.append(Data(repeating: 0x20, count: VisorHtml.minimoBytes - justo.count))
        XCTAssertFalse(VisorHtml.pareceHtmlCompleto(justo), "200 justos no pasan")
        justo.append(0x20)
        XCTAssertTrue(VisorHtml.pareceHtmlCompleto(justo))
        XCTAssertFalse(VisorHtml.pareceHtmlCompleto(Data(repeating: 0x61, count: 5000)), "sin cierre")
        XCTAssertTrue(VisorHtml.pareceHtmlCompleto(Data("<HTML><BODY>\(String(repeating: "a", count: 300))</BODY></HTML>".utf8)))
        XCTAssertFalse(VisorHtml.pareceHtmlCompleto(Data(repeating: 0xFF, count: 5000)))
    }

    func testGuardarDejaElFicheroEnteroYNoDejaRestos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-visor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ruta = dir.appendingPathComponent("pagina.html")
        try Data("<html>viejo</html>".utf8).write(to: ruta)
        let nuevo = html(400)
        try VisorHtml.escribirEncima(ruta, nuevo)
        XCTAssertEqual(try Data(contentsOf: ruta), nuevo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pagina.pixpin-tmp").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["pagina.html"])
    }

    func testElPuenteDeclaraElNombreYElMetodoQueEsperaAndroid() {
        let s = ControladorVisorHtml.puente
        XCTAssertTrue(s.contains("window.PixPinVisor"))
        XCTAssertTrue(s.contains("guardar: function(nombre, base64)"))
        XCTAssertTrue(s.contains("messageHandlers.pixpinVisor"))
    }
}
