// El anotador de pantalla (E3): la regla de cuando guardar, que pantallas
// se guardan, la foto del escritorio y la pastilla (las pruebas de
// `anotador_al_chat.rs`, `pantalla.rs` y `pastilla_pantalla.rs` de
// Windows), y guardar de verdad en «Mensajes guardados» por el puente.

import AppKit
import CoreGraphics
import Foundation
import PixPinCore
import UniformTypeIdentifiers
@testable import PixPinKit
import XCTest

/// Una imagen lisa de `w`x`h` pixeles.
private func lisa(_ w: Int, _ h: Int, _ rgb: (CGFloat, CGFloat, CGFloat)) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// El pixel `(x, y)` (contando desde ARRIBA) como RGBA.
private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var datos = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = CGContext(data: &datos, width: img.width, height: img.height, bitsPerComponent: 8,
                        bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    let i = (y * img.width + x) * 4
    return Array(datos[i..<i + 4])
}

/// Un trazo a mano de `(x, y)` a `(x + 100, y)`.
private func raya(_ ed: EditorLienzo, x: Float, y: Float) {
    _ = ed.puntero(fase: .pulsar, x: x, y: y, presion: 0.5, modificadores: 0, zoom: 1)
    for i in 1...20 {
        _ = ed.puntero(fase: .mover, x: x + Float(i) * 5, y: y, presion: 0.5, modificadores: 0, zoom: 1)
    }
    _ = ed.puntero(fase: .soltar, x: x + 100, y: y, presion: nil, modificadores: 0, zoom: 1)
}

@MainActor
final class AnotadorPantallaE3Tests: XCTestCase {
    // MARK: La regla de guardar (`que_hacer`)

    func testLaReglaDeGuardarPrimeroCreaLuegoPoneAlDiaYSinCambiosNoHaceNada() {
        XCTAssertEqual(PasoAnotador.de(yaGuardada: false, huellaGuardada: nil, ahora: 1), .nuevo)
        XCTAssertEqual(PasoAnotador.de(yaGuardada: true, huellaGuardada: 1, ahora: 2), .alDia)
        // Limpiar lo ya guardado tambien se lleva al lienzo.
        XCTAssertEqual(PasoAnotador.de(yaGuardada: true, huellaGuardada: 1, ahora: nil), .alDia)
        // Casos negativos: sin tinta y sin guardar antes, o sin cambios.
        XCTAssertEqual(PasoAnotador.de(yaGuardada: false, huellaGuardada: nil, ahora: nil), .nada)
        XCTAssertEqual(PasoAnotador.de(yaGuardada: true, huellaGuardada: 1, ahora: 1), .nada)
        XCTAssertEqual(PasoAnotador.de(yaGuardada: true, huellaGuardada: nil, ahora: nil), .nada)
    }

    // MARK: Las pantallas

    func testSeGuardaSoloLaPantallaDondeSeDibujoASuTamano() {
        // Tres pantallas en fila, como las del usuario.
        let m = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                 CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                 CGRect(x: 3840, y: 0, width: 1920, height: 1080)]
        // Un garabato en la del medio.
        XCTAssertEqual(GeometriaAnotador.pantallasConDibujo(m, cajas: [CGRect(x: 2000, y: 100, width: 500, height: 500)]),
                       m[1])
        // Una flecha que cruza dos: las dos.
        XCTAssertEqual(GeometriaAnotador.pantallasConDibujo(m, cajas: [CGRect(x: 1800, y: 10, width: 300, height: 10)]),
                       CGRect(x: 0, y: 0, width: 3840, height: 1080))
        // Casos negativos: sin nada dibujado, o con algo en las tres, entera.
        XCTAssertNil(GeometriaAnotador.pantallasConDibujo(m, cajas: []))
        XCTAssertNil(GeometriaAnotador.pantallasConDibujo(m, cajas: [CGRect(x: 10, y: 10, width: 4990, height: 10)]))
    }

    func testCadaPantallaVaASuSitioDelMundoConLaYHaciaAbajo() {
        // La principal abajo a la izquierda y otra ENCIMA, corrida (AppKit
        // cuenta la Y hacia arriba).
        let principal = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let encima = CGRect(x: 200, y: 900, width: 1920, height: 1080)
        let e = GeometriaAnotador.escritorio([principal, encima])
        XCTAssertEqual(e, CGRect(x: 0, y: 0, width: 2120, height: 1980))
        XCTAssertEqual(GeometriaAnotador.enElMundo(encima, escritorio: e), CGRect(x: 200, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(GeometriaAnotador.enElMundo(principal, escritorio: e), CGRect(x: 0, y: 1080, width: 1440, height: 900))
        // Una a la izquierda (x negativa) no deja el mundo en negativo.
        let izquierda = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let e2 = GeometriaAnotador.escritorio([principal, izquierda])
        XCTAssertEqual(GeometriaAnotador.enElMundo(izquierda, escritorio: e2).origin, CGPoint(x: 0, y: 100))
    }

    func testLaFotoDelEscritorioPoneCadaPantallaEnSuSitioYLoQueNoCubreNingunaSaleNegro() {
        // Dos pantallas de alto distinto (un escritorio en L), una Retina.
        let roja = FotoEnElMundo(marco: CGRect(x: 0, y: 0, width: 4, height: 4), imagen: lisa(8, 8, (1, 0, 0)))
        let azul = FotoEnElMundo(marco: CGRect(x: 4, y: 0, width: 4, height: 2), imagen: lisa(4, 2, (0, 0, 1)))
        let todo = CGRect(x: 0, y: 0, width: 8, height: 4)
        let k = GeometriaAnotador.escala(de: [roja, azul], en: todo)
        XCTAssertEqual(k, 2, "la mas fina manda")
        let img = GeometriaAnotador.componer([roja, azul], region: todo, escala: k)!
        XCTAssertEqual(img.width, 16)
        XCTAssertEqual(img.height, 8)
        XCTAssertEqual(pixel(img, 2, 2), [255, 0, 0, 255])
        XCTAssertEqual(pixel(img, 12, 1), [0, 0, 255, 255], "la azul arriba a la derecha")
        XCTAssertEqual(pixel(img, 12, 6), [0, 0, 0, 255], "debajo de la azul no hay pantalla")
        // Solo la de la derecha: el trozo empieza en ella y a su escala.
        let derecha = CGRect(x: 4, y: 0, width: 4, height: 2)
        XCTAssertEqual(GeometriaAnotador.escala(de: [roja, azul], en: derecha), 1)
        let trozo = GeometriaAnotador.componer([roja, azul], region: derecha, escala: 1)!
        XCTAssertEqual(trozo.width, 4)
        XCTAssertEqual(pixel(trozo, 0, 0), [0, 0, 255, 255])
    }

    // MARK: La vista de cada pantalla

    func testLaVistaDeUnaPantallaMiraSuTrozoYEnVivoNoPintaElPapel() throws {
        let raiz = try carpetaTemporal("anotador-vista")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let ed = try EditorLienzo.deFichero(ruta: raiz.appendingPathComponent("p.excalidraw").path, crear: true)
        try ed.herramienta(nombre: "lapiz")
        // Una raya gruesa en la segunda pantalla (empieza en x = 1440).
        _ = ed.cambiarEstilo(cambio: .grosor(grosor: .grueso))
        raya(ed, x: 1460, y: 40)
        let vista = VistaEditorLienzoNS(modelo: ModeloEditorLienzo(editor: ed))
        vista.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        vista.camaraFija = true
        vista.origenFijo = CGPoint(x: 1440, y: 0)
        vista.papelTransparente = true
        XCTAssertFalse(vista.isOpaque)
        let rep = try XCTUnwrap(vista.bitmapImageRepForCachingDisplay(in: vista.bounds))
        vista.cacheDisplay(in: vista.bounds, to: rep)
        let img = try XCTUnwrap(rep.cgImage)
        let k = img.width / 200
        // El papel no se pinta: se ve lo de debajo.
        XCTAssertEqual(pixel(img, 2 * k, 90 * k)[3], 0)
        // La raya cae en su sitio de ESTA pantalla (x = 20...120, y = 40).
        XCTAssertGreaterThan(pixel(img, 70 * k, 40 * k)[3], 0)
        // Caso negativo: con papel, el papel tapa (opaco).
        vista.papelTransparente = false
        let rep2 = try XCTUnwrap(vista.bitmapImageRepForCachingDisplay(in: vista.bounds))
        vista.cacheDisplay(in: vista.bounds, to: rep2)
        XCTAssertEqual(pixel(try XCTUnwrap(rep2.cgImage), 2 * k, 90 * k)[3], 255)
    }

    // MARK: La pastilla

    func testLaPastillaLlevaLasAccionesDeWindowsEnSuOrdenYDiceComoVolver() {
        XCTAssertEqual(AccionPastilla.allCases, [.atravesar, .limpiar, .copiar, .guardar, .salir])
        XCTAssertTrue(PastillaAnotador.rotulo(pasante: true).contains("volver a dibujar"))
        XCTAssertTrue(PastillaAnotador.rotulo(pasante: false).contains("clic a través"))
        XCTAssertNotEqual(PastillaAnotador.rotulo(pasante: true), PastillaAnotador.rotulo(pasante: false))
    }

    // MARK: Al chat, de verdad

    func testGuardarDejaLaFotoEnMensajesGuardadosConLaTintaEditableYPonerAlDiaNoMandaOtra() throws {
        let raiz = try carpetaTemporal("anotador-pantalla")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.appendingPathComponent("datos").path, nombreDelAparato: "Mac de prueba")
        let ed = try EditorLienzo.deFichero(ruta: raiz.appendingPathComponent("pantalla.excalidraw").path, crear: true)
        try ed.herramienta(nombre: "lapiz")
        // Sin tinta no hay huella (no se guarda nada).
        XCTAssertNil(ed.tintaDePantalla().huella)
        // Una raya en la segunda pantalla (de 100 a 200 puntos del mundo).
        raya(ed, x: 1540, y: 50)
        let tinta = ed.tintaDePantalla()
        XCTAssertNotNil(tinta.huella)
        XCTAssertEqual(tinta.cajas.count, 1)
        let pantallas = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 400, height: 300)]
        let cajas = tinta.cajas.map { CGRect(x: CGFloat($0.x0), y: CGFloat($0.y0),
                                             width: CGFloat($0.x1 - $0.x0), height: CGFloat($0.y1 - $0.y0)) }
        let region = try XCTUnwrap(GeometriaAnotador.pantallasConDibujo(pantallas, cajas: cajas))
        XCTAssertEqual(region, pantallas[1])
        // La foto de debajo de esa pantalla, a 2x.
        let foto = GeometriaAnotador.componer([FotoEnElMundo(marco: pantallas[1], imagen: lisa(800, 600, (0.9, 0.9, 0.9)))],
                                              region: region, escala: 2)!
        let png = raiz.appendingPathComponent("debajo.png")
        try XCTUnwrap(Capturador.codificar(foto, tipo: .png, escala: 2)).write(to: png)
        let g = try nucleo.pantallaAnotadaAlChat(foto: png.path, editor: ed, origenX: Float(region.minX),
                                                 origenY: Float(region.minY), escala: 2)
        XCTAssertEqual(g.lienzo, "foto-\(g.mensaje.id)")
        XCTAssertEqual(g.mensaje.referencia, g.lienzo)
        XCTAssertEqual(g.trazos, 1)
        XCTAssertEqual(g.ancho, 800)
        XCTAssertEqual(g.alto, 600)
        XCTAssertEqual(try nucleo.chatGuardados().id, g.chat, "en Mensajes guardados")
        // Lo que ve la burbuja: la foto anotada con su lienzo.
        XCTAssertEqual(try nucleo.fotoAnotada(chat: g.chat, lienzo: g.lienzo)?.lienzo, g.lienzo)
        // Se sigue dibujando y se pone al dia el MISMO lienzo.
        raya(ed, x: 1450, y: 200)
        XCTAssertNotEqual(ed.tintaDePantalla().huella, tinta.huella)
        XCTAssertEqual(try nucleo.ponerAlDiaPantallaAnotada(guardada: g, editor: ed, origenX: Float(region.minX),
                                                             origenY: Float(region.minY), escala: 2), 2)
        let pagina = try nucleo.ultimosMensajes(chat: g.chat, cuantos: 10)
        XCTAssertEqual(pagina.mensajes.count, 1, "el mismo mensaje, no otro")
    }
}
