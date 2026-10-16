// La hoja de compartir comun (D1): sus reglas (`hoja_compartir` de
// Windows), lo que prepara de cada cosa, los ficheros que hace (PDF, PNG,
// JPG, SVG, la pagina web), la Salida y «Abrir con…».

import AppKit
import PDFKit
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class CompartirTests: XCTestCase {
    private func compartible(paginas: Int) -> Compartible {
        Compartible(
            titulo: "Obra",
            paginas: (0 ..< paginas).map { PaginaCompartir(clave: "p\($0)", nombre: "Página \($0)", detalle: "") },
            formatos: [
                FormatoCompartir(id: IdFormato.pdf, nombre: "PDF", cuantas: .varias, simbolo: ""),
                FormatoCompartir(id: IdFormato.png, nombre: "PNG", cuantas: .una, simbolo: ""),
                FormatoCompartir(id: IdFormato.original, nombre: "Original", cuantas: .ninguna, simbolo: ""),
            ],
            marcadas: nil)
    }

    // MARK: Las reglas de la hoja

    func testConVariasMarcadasLosFormatosDeUnaPaginaDesaparecen() {
        let c = compartible(paginas: 3)
        var e = EstadoHoja(c)
        XCTAssertEqual(e.marcadas.count, 3, "al abrir, todas")
        XCTAssertEqual(e.visibles(c), [0, 2], "el PNG no se ofrece con tres marcadas")
        // Con una sola marcada, vuelve.
        e.tocarPagina(c, "p1")
        e.tocarPagina(c, "p2")
        XCTAssertEqual(e.marcadas, ["p0"])
        XCTAssertEqual(e.visibles(c), [0, 1, 2])
    }

    func testElegirUnFormatoDeUnaPaginaSeQuedaConLaPrimera() {
        let c = compartible(paginas: 3)
        var e = EstadoHoja(c)
        e.elegirFormato(c, 1)
        XCTAssertEqual(e.marcadas, ["p0"])
        // Tocar otra la cambia, no la suma.
        e.tocarPagina(c, "p2")
        XCTAssertEqual(e.marcadas, ["p2"])
        XCTAssertEqual(e.elegidas(c), ["p2"])
        // Caso negativo: una pagina que no esta no cambia nada.
        e.tocarPagina(c, "nada")
        XCTAssertEqual(e.marcadas, ["p2"])
    }

    func testSinPaginasMarcadasNoHayNadaQuePreparar() {
        let c = compartible(paginas: 2)
        var e = EstadoHoja(c)
        XCTAssertTrue(e.hayQuePreparar(c))
        e.ninguna()
        XCTAssertFalse(e.hayQuePreparar(c))
        XCTAssertTrue(e.elegidas(c).isEmpty)
        // Lo que va entero no necesita paginas.
        e.elegirFormato(c, 2)
        XCTAssertTrue(e.hayQuePreparar(c))
        XCTAssertTrue(e.elegidas(c).isEmpty)
        e.todas(c)
        XCTAssertEqual(e.marcadas.count, 2)
    }

    func testLasFlechasPasanPorLosFormatosQueSeVen() {
        let c = compartible(paginas: 3)
        var e = EstadoHoja(c)
        e.moverFormato(c, 1)
        XCTAssertEqual(e.formato, 2, "salta el PNG, que no se ve")
        e.moverFormato(c, 1)
        XCTAssertEqual(e.formato, 2, "no se pasa del ultimo")
        e.moverFormato(c, -5)
        XCTAssertEqual(e.formato, 0)
    }

    func testLosNombresDeLasFilasYElPeso() {
        XCTAssertEqual(TextosCompartir.nombreDeFila(nombre: "  Plano  ", resumen: "x"), "Plano")
        XCTAssertEqual(TextosCompartir.nombreDeFila(nombre: "", resumen: "Primera\nsegunda"), "Primera")
        XCTAssertEqual(TextosCompartir.nombreDeFila(nombre: "", resumen: ""), "Sin nombre")
        let largo = String(repeating: "a", count: 60)
        XCTAssertEqual(TextosCompartir.nombreDeFila(nombre: largo, resumen: "").count, 49)
        XCTAssertEqual(TextosCompartir.sinExtension("foto.jpeg"), "foto")
        XCTAssertTrue(TextosCompartir.peso(2048, ficheros: 3).hasSuffix("· 3 archivos"))
        XCTAssertFalse(TextosCompartir.peso(2048, ficheros: 1).contains("archivos"))
        XCTAssertEqual(TextosCompartir.queIncluir(2, de: 5), "Qué incluir · 2 de 5")
    }

    // MARK: Texto en paginas

    func testUnTextoLargoSeParteEnPaginasA4() {
        let corto = PiezasCompartir.paginasDeTexto(titulo: "Título", texto: "hola")
        XCTAssertEqual(corto.count, 1)
        XCTAssertEqual(corto[0].first?.tam, PiezasCompartir.letraTitulo)
        let largo = (0 ..< 200).map { "Línea \($0) con algo de texto" }.joined(separator: "\n")
        let paginas = PiezasCompartir.paginasDeTexto(titulo: nil, texto: largo)
        XCTAssertGreaterThan(paginas.count, 2)
        for p in paginas {
            XCTAssertLessThanOrEqual(p.last?.y ?? 0, PiezasCompartir.a4.height - PiezasCompartir.margen)
        }
        // Una linea que no cabe se parte.
        let ancha = String(repeating: "palabra ", count: 80)
        XCTAssertGreaterThan(PiezasCompartir.partir(ancha, tam: 10.5, ancho: 400).count, 1)
        // Caso negativo: un texto vacio da una pagina en blanco, no ninguna.
        XCTAssertEqual(PiezasCompartir.paginasDeTexto(titulo: nil, texto: "").count, 1)
    }

    func testElSvgDeUnTextoVaEscapado() {
        let svg = PiezasCompartir.svgDeTexto([.init(texto: "a < b & \"c\"", y: 48, tam: 10.5)])
        XCTAssertTrue(svg.contains("a &lt; b &amp; &quot;c&quot;"))
        XCTAssertFalse(svg.contains("a < b"))
        XCTAssertTrue(svg.contains("<svg"))
    }

    // MARK: Los ficheros que salen

    func testUnaNotaSaleEnPdfPngJpgSvgWebYTexto() async throws {
        let p = PreparadoCompartir(titulo: "Lista: compra")
        PrepararCompartir.anadirTexto(p, clave: "m1", nombre: "Lista", detalle: "Nota", titulo: nil,
                                      texto: (0 ..< 120).map { "Cosa \($0)" }.joined(separator: "\n"), solo: true)
        XCTAssertGreaterThan(p.piezas.count, 1)
        XCTAssertEqual(p.piezas[1].pagina.nivel, 1, "las paginas de detras van sangradas")
        let c = p.compartible()
        XCTAssertEqual(c.formatos.map(\.id), [IdFormato.web, IdFormato.pdf, IdFormato.png, IdFormato.jpg,
                                              IdFormato.svg, IdFormato.texto])
        let carpeta = try carpetaTemporal("compartir")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let todas = c.paginas.map(\.clave)

        let pdf = try await p.generar(IdFormato.pdf, claves: todas, en: carpeta)
        XCTAssertEqual(pdf.map(\.lastPathComponent), ["Lista- compra.pdf"])
        XCTAssertEqual(PDFDocument(url: pdf[0])?.pageCount, p.piezas.count)

        let png = try await p.generar(IdFormato.png, claves: [todas[0]], en: carpeta)
        let img = try XCTUnwrap(NSImage(contentsOf: png[0]))
        XCTAssertEqual(img.representations.first?.pixelsWide, Int((PiezasCompartir.a4.width * 2).rounded()))
        let jpg = try await p.generar(IdFormato.jpg, claves: [todas[1]], en: carpeta)
        XCTAssertTrue(jpg[0].lastPathComponent.hasSuffix(" - Página 2.jpg"), jpg[0].lastPathComponent)

        let svg = try await p.generar(IdFormato.svg, claves: [todas[0]], en: carpeta)
        XCTAssertTrue(try String(contentsOf: svg[0], encoding: .utf8).contains("Cosa 0"))

        let web = try await p.generar(IdFormato.web, claves: todas, en: carpeta)
        let html = try String(contentsOf: web[0], encoding: .utf8)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Cosa 0"))

        let texto = try await p.generar(IdFormato.texto, claves: [], en: carpeta)
        XCTAssertTrue(try String(contentsOf: texto[0], encoding: .utf8).hasPrefix("Cosa 0\nCosa 1"))

        // Caso negativo: sin paginas marcadas no sale nada.
        do {
            _ = try await p.generar(IdFormato.pdf, claves: [], en: carpeta)
            XCTFail("sin paginas no hay PDF")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Marca alguna página")
        }
    }

    func testUnaFotoSueltaVaPrimeroEntera() async throws {
        let carpeta = try carpetaTemporal("compartir-foto")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let foto = carpeta.appendingPathComponent("fachada.png")
        try escribirPNG(foto, ancho: 300, alto: 200)
        let p = await PrepararCompartir.preparar(.ficheros(titulo: "fachada", [foto]), almacen: nil)
        let c = p.compartible()
        XCTAssertEqual(c.formatos.first?.id, IdFormato.original, "lo natural es mandarla tal cual")
        XCTAssertEqual(c.paginas.count, 1)
        XCTAssertEqual(p.piezas[0].tamano, CGSize(width: 300, height: 200))
        let tal = try await p.generar(IdFormato.original, claves: [], en: carpeta.appendingPathComponent("s"))
        XCTAssertEqual(tal, [foto], "el original no se copia")
        let svg = try await p.generar(IdFormato.svg, claves: [c.paginas[0].clave], en: carpeta.appendingPathComponent("s"))
        XCTAssertTrue(try String(contentsOf: svg[0], encoding: .utf8).contains("data:image/png;base64,"))
        // Caso negativo: un fichero que no esta no da paginas ni original.
        let nada = await PrepararCompartir.preparar(.ficheros(titulo: "x", [carpeta.appendingPathComponent("no.png")]),
                                                    almacen: nil)
        XCTAssertTrue(nada.compartible().formatos.isEmpty)
    }

    func testUnPdfSoloSaleEnSusPaginas() async throws {
        let carpeta = try carpetaTemporal("compartir-pdf")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let p = PreparadoCompartir(titulo: "Hojas")
        PrepararCompartir.anadirTexto(p, clave: "t", nombre: "Hojas", detalle: "", titulo: nil,
                                      texto: (0 ..< 120).map { "Fila \($0)" }.joined(separator: "\n"), solo: false)
        let origen = try await p.generar(IdFormato.pdf, claves: p.piezas.map(\.pagina.clave), en: carpeta)[0]
        let leido = PrepararCompartir.deFicheros(titulo: "Hojas", [origen])
        XCTAssertEqual(leido.piezas.count, p.piezas.count)
        XCTAssertEqual(leido.piezas[0].pagina.nombre, "Página 1")
        let png = try await leido.generar(IdFormato.png, claves: [leido.piezas[0].pagina.clave],
                                          en: carpeta.appendingPathComponent("s"))
        XCTAssertNotNil(NSImage(contentsOf: png[0]))
    }

    func testLosMensajesDeUnChatSalenConSuDibujoYElProyecto() async throws {
        let raiz = try carpetaTemporal("compartir-chat")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        await almacen.abrir(chat: chat)
        let escrita = await almacen.escribir(nota: "Comprar cemento", en: chat)
        let nota = try XCTUnwrap(escrita)
        let creado = await almacen.crearLienzo(en: chat)
        let dibujo = try XCTUnwrap(creado)
        // Un rectangulo en el lienzo.
        let ref = try XCTUnwrap(dibujo.referencia)
        let fichero = raiz.appendingPathComponent("datos").appendingPathComponent("proyectos")
        let lienzos = try FileManager.default.subpathsOfDirectory(atPath: fichero.path)
            .filter { $0.hasSuffix("\(ref).excalidraw") }
        let ruta = fichero.appendingPathComponent(try XCTUnwrap(lienzos.first))
        try Data(##"{"type":"excalidraw","version":2,"elements":[{"id":"r","type":"rectangle","x":0,"y":0,"width":120,"height":60,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":0,"opacity":100,"isDeleted":false}],"appState":{"viewBackgroundColor":"#ffffff"},"files":{}}"##.utf8)
            .write(to: ruta)

        let p = await PrepararCompartir.preparar(.mensajes(chat: chat, titulo: "Obra", [nota, dibujo]), almacen: almacen)
        XCTAssertEqual(p.titulo, "Obra", "varios: el titulo del proyecto")
        XCTAssertEqual(p.piezas.map(\.pagina.clave), [nota.id, dibujo.id])
        XCTAssertTrue(p.compartible().formatos.contains { $0.id == IdFormato.pixpin })
        let carpeta = raiz.appendingPathComponent("salida")
        let pdf = try await p.generar(IdFormato.pdf, claves: [nota.id, dibujo.id], en: carpeta)
        XCTAssertEqual(PDFDocument(url: pdf[0])?.pageCount, 2)
        let paquete = try await p.generar(IdFormato.pixpin, claves: [], en: carpeta)
        XCTAssertEqual(paquete[0].pathExtension, "pixpin")
        XCTAssertEqual(try Data(contentsOf: paquete[0]).prefix(2), Data("PK".utf8))

        // Solo el dibujo: con su Editable y el lienzo dentro de la web.
        let solo = await PrepararCompartir.preparar(.mensajes(chat: chat, titulo: "Obra", [dibujo]), almacen: almacen)
        XCTAssertNotNil(solo.excalidraw)
        XCTAssertTrue(solo.compartible().formatos.contains { $0.id == IdFormato.editable })
        let svg = try await solo.generar(IdFormato.svg, claves: [dibujo.id], en: carpeta)
        XCTAssertTrue(try String(contentsOf: svg[0], encoding: .utf8).contains("<svg"))

        // El proyecto entero, desde la lista.
        let ficha = try XCTUnwrap(almacen.chats.first { $0.id == chat })
        let proyecto = await PrepararCompartir.preparar(.proyectos([ficha]), almacen: almacen)
        XCTAssertEqual(proyecto.piezas.count, 2)
        XCTAssertTrue(proyecto.compartible().formatos.contains { $0.id == IdFormato.editable })
    }

    // MARK: La Salida y «Abrir con…»

    func testLaSalidaSumaArribaSinRepetir() {
        let a = URL(fileURLWithPath: "/tmp/a.pdf"), b = URL(fileURLWithPath: "/tmp/b.png")
        XCTAssertEqual(ModeloSalida.juntar([b], [a]), [b, a])
        XCTAssertEqual(ModeloSalida.juntar([a], [b, a]), [a, b], "lo repetido sube, no se duplica")
        let m = ModeloSalida()
        m.recibir([a, b], titulo: Salida.exportado)
        m.mover(5)
        XCTAssertEqual(m.elegido, 1)
        m.mover(-5)
        XCTAssertEqual(m.actual, a)
        m.vaciar()
        XCTAssertNil(m.actual)
    }

    func testAbrirConDiceQueFaltaElArchivoConSuNombre() throws {
        let falta = URL(fileURLWithPath: "/tmp/pixpin-no-esta/Presupuesto 2026.xlsx")
        let aviso = try XCTUnwrap(AbrirCon.aviso(falta))
        XCTAssertTrue(aviso.contains("Presupuesto 2026.xlsx"))
        XCTAssertFalse(aviso.lowercased().contains("registro"))
        // Caso negativo: uno que si esta no da aviso.
        let carpeta = try carpetaTemporal("abrir-con")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let hay = carpeta.appendingPathComponent("hay.txt")
        try Data("x".utf8).write(to: hay)
        XCTAssertNil(AbrirCon.aviso(hay))
    }
}
