// E2, los planos como en Windows: buscar en sus textos, exportar (HTML,
// PDF, PNG), la capa del lienzo encima con la camara del plano, sus letras,
// las teclas del visor y las vistas guardadas del visor 3D. Lo de Metal se
// salta sin tarjeta.

import AppKit
import Metal
import PDFKit
import PixPinCore
@testable import PixPinKit
import XCTest

/// Un DXF con un texto rotulado y una raya (el de las pruebas de Rust).
private let dxfConTexto = "0\nSECTION\n2\nENTITIES\n0\nTEXT\n8\n0\n10\n5\n20\n7\n30\n0\n40\n2.5\n1\nJR. ANTISUYO\n0\nLINE\n8\n0\n10\n0\n20\n0\n30\n0\n11\n50\n21\n0\n31\n0\n0\nENDSEC\n0\nEOF\n"

private func abrir(_ carpeta: URL, _ texto: String = dxfDePrueba, nombre: String = "planta.dxf") throws -> (Nucleo, Plano, URL) {
    let ruta = carpeta.appendingPathComponent(nombre)
    try texto.write(to: ruta, atomically: true, encoding: .utf8)
    let nucleo = try Nucleo.abrir(raiz: carpeta.appendingPathComponent("datos").path, nombreDelAparato: "Mac de prueba")
    return (nucleo, try nucleo.abrirPlano(ruta: ruta.path), ruta)
}

private func motor() throws -> MotorMetal {
    guard let m = MotorMetal(dispositivo: MTLCreateSystemDefaultDevice()) else { throw XCTSkip("Sin tarjeta con Metal") }
    return m
}

final class PlanosE2PuenteTests: XCTestCase {
    func testLosTextosDelPlanoSeBuscanSinMirarMayusculasNiPuntos() throws {
        let carpeta = try carpetaTemporal("textos-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (_, plano, _) = try abrir(carpeta, dxfConTexto, nombre: "calle.dxf")
        let h = try plano.buscarTextos(consulta: "jr antisuyo", max: 5)
        XCTAssertEqual(h.map(\.texto), ["JR. ANTISUYO"])
        XCTAssertEqual(h[0].x, 5, accuracy: 1e-6)
        XCTAssertGreaterThan(h[0].ancho, h[0].alto * 10, "se ve lo de alrededor")
        // Caso negativo.
        XCTAssertTrue(try plano.buscarTextos(consulta: "Collasuyo", max: 5).isEmpty)
    }

    func testLaPaginaWebLlevaLasCapasYLasCotasYUnDxfNoSeExportaADxf() throws {
        let carpeta = try carpetaTemporal("web-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (_, plano, _) = try abrir(carpeta)
        let u = plano.resumen().cajaUtil
        let anotado = AnotadoPlano(cotas: [CotaPlano(puntos: [PuntoPlano(x: u.x0, y: u.y0), PuntoPlano(x: u.x1, y: u.y0)])],
                                   marcos: [u])
        let html = try plano.paginaWeb(anotado: anotado, claro: true)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("\"n\":\"Muros\",\"on\":true"))
        XCTAssertTrue(html.contains("\"cotas\":[["))
        XCTAssertFalse(plano.esDwg())
        XCTAssertThrowsError(try plano.exportarDxf(salida: carpeta.appendingPathComponent("x.dxf").path))
        XCTAssertTrue(plano.letrasQueFaltan().isEmpty)
    }

    func testLaCapaDelLienzoSeAbreSinDejarFicherosHastaQueSeDibuja() throws {
        let carpeta = try carpetaTemporal("anotar-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (_, plano, _) = try abrir(carpeta)
        let ed = try plano.anotar()
        XCTAssertEqual(ed.cuantosElementos(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plano.rutaDeLaCapa()))
        // Sin capa no hay hoja que poner.
        XCTAssertFalse(try plano.ponerHoja(encaje: plano.encaje()))
    }

    func testLasLetrasDeLosPlanosSeAnadenSoloSiSonLetras() throws {
        let carpeta = try carpetaTemporal("letras-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let nucleo = try Nucleo.abrir(raiz: carpeta.appendingPathComponent("datos").path, nombreDelAparato: "Mac")
        let shx = carpeta.appendingPathComponent("romans.shx"), txt = carpeta.appendingPathComponent("nota.txt")
        try Data("x".utf8).write(to: shx)
        try Data("x".utf8).write(to: txt)
        XCTAssertEqual(nucleo.anadirLetrasDePlanos(rutas: [shx.path, txt.path]), 1)
        XCTAssertEqual(nucleo.letrasDePlanos(), 1)
        XCTAssertEqual(nucleo.quitarLetrasDePlanos(), 1)
        XCTAssertEqual(nucleo.letrasDePlanos(), 0)
    }

    func testUnModeloSinVistasGuardadasNoTieneCamaraDeVista() throws {
        let carpeta = try carpetaTemporal("vistas-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let csv = carpeta.appendingPathComponent("puntos.csv")
        try puntosDePrueba.write(to: csv, atomically: true, encoding: .utf8)
        let m = try Modelo3dApple.abrir(ruta: csv.path)
        XCTAssertTrue(m.vistasGuardadas().isEmpty)
        XCTAssertNil(m.camaraDeVista(indice: 0, ancho: 800, alto: 600, escala: 2))
    }
}

@MainActor
final class PlanosE2SwiftTests: XCTestCase {
    /// Lo que cae bajo un punto de la vista es lo mismo en el plano y en el
    /// lienzo de encima: la capa no se separa del plano al mover o acercar.
    func testLaCamaraDelLienzoSigueALaDelPlano() {
        let camara = CamaraPlano(centroX: 100, centroY: 50, px: 0.5)
        let encaje = EncajePlano(u: 0.25, ceroX: 10, ceroY: 80)
        let escala = 2.0, tam = CGSize(width: 400, height: 300)
        let c = AnotadorPlano.camaraDelLienzo(camara, escala: escala, tamano: tam, encaje: encaje)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 60), CGPoint(x: 400, y: 300)] {
            // En el plano (la vista de Metal, Y hacia arriba).
            let d = camara.aDibujo(x: Double(p.x) * escala, y: Double(p.y) * escala,
                                   ancho: Double(tam.width) * escala, alto: Double(tam.height) * escala)
            let enLaCapa = CGPoint(x: (d.x - encaje.ceroX) / encaje.u, y: (encaje.ceroY - d.y) / encaje.u)
            // En el lienzo (Y hacia abajo).
            let q = CGPoint(x: p.x, y: tam.height - p.y)
            let delLienzo = CGPoint(x: c.origen.x + q.x / c.zoom, y: c.origen.y + q.y / c.zoom)
            XCTAssertEqual(delLienzo.x, enLaCapa.x, accuracy: 1e-6)
            XCTAssertEqual(delLienzo.y, enLaCapa.y, accuracy: 1e-6)
        }
    }

    func testLaHojaDelPdfTieneElLadoLargoDeUnA3() {
        let t = ExportarPlano.tamanoDeHoja(CajaPlano(x0: 0, y0: 0, x1: 200, y1: 100), lado: 1190.55, margen: 28)
        XCTAssertEqual(t.width, 1190.55, accuracy: 1e-6)
        XCTAssertEqual(t.height, (1190.55 - 56) / 2 + 56, accuracy: 1e-6)
    }

    @MainActor
    func testLoPreparadoPasaTalCualALaHoja() async {
        let p = PreparadoCompartir(titulo: "Plano")
        PrepararCompartir.anadirOriginales(p, [URL(fileURLWithPath: "/no/existe.dxf")])
        let r = await PrepararCompartir.preparar(.preparado(p), almacen: nil)
        XCTAssertTrue(r === p)
    }
}

@MainActor
final class PlanosE2MetalTests: XCTestCase {
    func testElPdfLlevaUnaHojaPorMarcoYLaImagenElPlanoPintado() throws {
        let m = try motor()
        let carpeta = try carpetaTemporal("exportar-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (nucleo, _, ruta) = try abrir(carpeta)
        let d = try PlanoEnTarjeta.cargar(ruta: ruta.path, nucleo: nucleo, motor: m)
        let u = d.resumen.cajaUtil
        let mitad = CajaPlano(x0: u.x0, y0: u.y0, x1: (u.x0 + u.x1) / 2, y1: u.y1)
        let encima = EncimaPapel(cotas: [CotaPlano(puntos: [PuntoPlano(x: u.x0, y: u.y0), PuntoPlano(x: u.x1, y: u.y0)])],
                                 medida: { String(format: "%.2f", $0) })
        let visibles = Set(d.plano.gruposVisibles())
        let pdf = try XCTUnwrap(ExportarPlano.pdf(d, visibles: visibles, marcos: [u, mitad], util: u, encima: encima))
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 2)
        // Sin marcos, una hoja: el plano entero.
        let uno = try XCTUnwrap(ExportarPlano.pdf(d, visibles: visibles, marcos: [], util: u, encima: nil))
        XCTAssertEqual(PDFDocument(data: uno)?.pageCount, 1)
        let img = try XCTUnwrap(ExportarPlano.imagen(d, visibles: visibles, region: u, encima: encima))
        XCTAssertEqual(max(img.width, img.height), 3200)
        // Hay algo pintado sobre el blanco.
        let datos = try XCTUnwrap(img.dataProvider?.data as Data?)
        var pintados = 0
        for i in stride(from: 0, to: datos.count, by: 4 * 97) where datos[i] < 200 || datos[i + 1] < 200 { pintados += 1 }
        XCTAssertGreaterThan(pintados, 0)
        // Caso negativo: una region vacia no da imagen.
        XCTAssertNil(ExportarPlano.imagen(d, visibles: visibles, region: CajaPlano(x0: 1, y0: 1, x1: 1, y1: 1), encima: nil))
    }

    /// A pone el lienzo encima del plano con su camara y A otra vez lo quita
    /// y vuelve a leer lo anotado; ⌘E con el plano abierto prepara la hoja.
    func testAnotarPoneElLienzoEncimaConLaCamaraDelPlano() async throws {
        let m = try motor()
        let carpeta = try carpetaTemporal("visor-e2")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (nucleo, _, ruta) = try abrir(carpeta)
        let visor = VisorPlano(ruta: ruta.path, titulo: "planta")
        let vista = VistaPlanoMetal(visor: visor, motor: m)
        visor.cargar(nucleo: nucleo)
        for _ in 0 ..< 200 where visor.datos == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(visor.datos)
        visor.alternarAnotar()
        let a = try XCTUnwrap(visor.anotador)
        XCTAssertTrue(visor.anotando)
        XCTAssertTrue(a.vista.superview === vista)
        XCTAssertTrue(a.vista.camaraDeFuera === vista)
        XCTAssertGreaterThan(a.vista.zoom, 0)
        // Medir deja de anotar.
        visor.modo = .medir
        XCTAssertFalse(visor.anotando)
        for _ in 0 ..< 100 where a.vista.superview != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(a.vista.superview)
        // Lo que ofrece el «Exportar»: HTML, PDF, PNG, JPG y el original (un DXF no da DXF).
        let p = try XCTUnwrap(ExportarPlano.preparar(visor))
        XCTAssertEqual(p.compartible().formatos.map(\.id), ["web", "pdf", "png", "jpg", "original"])
        let hecho = try await p.generar("web", claves: [], en: carpeta.appendingPathComponent("salida"))
        XCTAssertTrue(try String(contentsOf: hecho[0], encoding: .utf8).hasPrefix("<!DOCTYPE html>"))
    }

    private func tecla(_ letra: String, codigo: UInt16, mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0,
                         context: nil, characters: letra, charactersIgnoringModifiers: letra, isARepeat: false,
                         keyCode: codigo)!
    }

    func testLasTeclasDelVisorSonLasDeWindows() throws {
        let m = try motor()
        let visor = VisorPlano(ruta: "/no/existe.dxf", titulo: "Prueba")
        let vista = VistaPlanoMetal(visor: visor, motor: m)
        var en3D = false
        visor.alVerEn3D = { en3D = true }
        // M mide, I marca, ⎋ vuelve a mover.
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("m", codigo: 46), visor: visor, vista: vista))
        XCTAssertEqual(visor.modo, .medir)
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("i", codigo: 34), visor: visor, vista: vista))
        XCTAssertEqual(visor.modo, .marco)
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("\u{1b}", codigo: 53), visor: visor, vista: vista))
        XCTAssertEqual(visor.modo, .mover)
        // B el fondo (y otra vez, el de antes), 3 en 3D, ⌘F buscar.
        let antes = visor.oscuro
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("b", codigo: 11), visor: visor, vista: vista))
        XCTAssertNotEqual(visor.oscuro, antes)
        VistaPlanoMetal.tecla(tecla("b", codigo: 11), visor: visor, vista: vista)
        XCTAssertEqual(visor.oscuro, antes)
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("3", codigo: 20), visor: visor, vista: vista))
        XCTAssertTrue(en3D)
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("f", codigo: 3, mods: .command), visor: visor, vista: vista))
        XCTAssertTrue(visor.buscando)
        // Las flechas mueven lo que se ve.
        let c = vista.camara
        XCTAssertTrue(VistaPlanoMetal.tecla(tecla("", codigo: 124), visor: visor, vista: vista))
        XCTAssertNotEqual(vista.camara, c)
        // Caso negativo: una letra que no es del visor no se usa.
        XCTAssertFalse(VistaPlanoMetal.tecla(tecla("q", codigo: 12), visor: visor, vista: vista))
    }
}
