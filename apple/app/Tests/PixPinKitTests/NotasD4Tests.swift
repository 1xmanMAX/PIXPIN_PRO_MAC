// La tanda D4: las notas Markdown en el editor de Windows (su misma pagina
// en un `WKWebView`). Se abre de verdad, fuera de la pantalla: la pagina
// habla con Rust por el puente, ensena la nota, sirve sus fotos por
// `pixpin-nota://` y, al cerrar, guarda lo ultimo antes.

import AppKit
import Foundation
import PixPinCore
@testable import PixPinKit
import WebKit
import XCTest

/// Un PNG de 3 x 2 de verdad.
private func png() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
final class NotasD4Tests: XCTestCase {
    private func esperar(_ que: String, segundos: Double = 15, hasta: () -> Bool) {
        let limite = Date().addingTimeInterval(segundos)
        while !hasta(), Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(hasta(), "no llego: \(que)")
    }

    /// Lo que da un JavaScript de la pagina (esperando a que conteste).
    private func js(_ web: WKWebView, _ codigo: String) -> Any? {
        var r: Any?
        var hecho = false
        web.evaluateJavaScript(codigo) { v, _ in r = v; hecho = true }
        let limite = Date().addingTimeInterval(5)
        while !hecho, Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return r
    }

    func testLaNotaSeAbreEnLaPaginaDeWindowsVeSusFotosYGuardaAlCerrar() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-d4-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.path, nombreDelAparato: "Mac")
        let chat = try nucleo.crearChat(nombre: "Obra")
        // Una foto junto a la nota, nombrada como la nombra el movil.
        let m0 = try nucleo.escribirNota(chat: chat.id, texto: "x", respondeA: nil)
        let sesion0 = try nucleo.abrirNota(destino: .mensaje(chat: chat.id, mensaje: m0.id), ingles: false)
        let origen = raiz.appendingPathComponent("planta.png")
        try png().write(to: origen)
        let insertar = try XCTUnwrap(sesion0.adjuntarFicheros(rutas: [origen.path]))
        let datos = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(insertar.utf8)) as? [String: Any])
        let renglonFoto = try XCTUnwrap(datos["texto"] as? String)
        XCTAssertTrue(renglonFoto.hasPrefix("![planta.png](pixpin:files/"), renglonFoto)

        let m = try nucleo.escribirNota(chat: chat.id, texto: "# Visita\n\nLa losa **lista**\n\n\(renglonFoto)\n", respondeA: nil)
        let sesion = try nucleo.abrirNota(destino: .mensaje(chat: chat.id, mensaje: m.id), ingles: false)
        XCTAssertEqual(sesion.titulo(), "Visita")
        let c = ControladorNotaWeb(sesion: sesion, chat: chat.id, mensaje: m, almacen: nil)
        var cerrada = false
        c.alCerrar = { _ in cerrada = true }

        // La pagina pide «listo», Rust le da la nota y CodeMirror la ensena.
        esperar("el texto en el editor") {
            ((js(c.web, "document.querySelector('.cm-content')?.innerText ?? ''") as? String) ?? "").contains("La losa")
        }
        // Las marcas del Markdown no se ven: la negrita es negrita.
        let negrita = js(c.web, "!!document.querySelector('.cm-content .pp-negrita, .cm-content strong, .cm-content .tok-strong')") as? Bool
        XCTAssertEqual(negrita, true)
        // La foto llega por `pixpin-nota://` y se decodifica.
        esperar("la foto servida") {
            ((js(c.web, "Math.max(0, ...[...document.querySelectorAll('img')].map(i => i.naturalWidth))") as? Double) ?? 0) == 3
        }
        // Las teclas del menu dicen ⌘ (el rotulo de Windows era Ctrl+B).
        XCTAssertTrue(notaPagina().contains("\"⌘B\""))

        // Se escribe y se cierra: la pagina guarda lo ultimo antes de irse.
        _ = js(c.web, """
            (() => { const v = document.querySelector('.cm-content').cmView.view;
                     v.dispatch({ changes: { from: v.state.doc.length, insert: '- [ ] curado' }, userEvent: 'input.type' });
                     return v.state.doc.length })()
            """)
        XCTAssertFalse(c.windowShouldClose(c.ventana), "no se cierra hasta que la pagina guarde")
        esperar("guardada y cerrada") { cerrada }
        let ultimo = try nucleo.ultimosMensajes(chat: chat.id, cuantos: 10).mensajes.first { $0.id == m.id }
        XCTAssertEqual(ultimo?.texto.hasSuffix("- [ ] curado"), true, ultimo?.texto ?? "")
    }

    func testUnMdSueltoSeAbreEnElEditorDeNotas() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-d4md-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.path, nombreDelAparato: "Mac")
        let md = raiz.appendingPathComponent("apuntes.md")
        try "# Apuntes\nhola".write(to: md, atomically: true, encoding: .utf8)
        let s = try nucleo.abrirNota(destino: .fichero(ruta: md.path), ingles: false)
        XCTAssertEqual(s.fichero(), md.path)
        XCTAssertEqual(s.titulo(), "Apuntes")
        // Caso negativo: uno que no esta no se abre (no se pisa nada).
        XCTAssertThrowsError(try nucleo.abrirNota(destino: .fichero(ruta: raiz.appendingPathComponent("no.md").path), ingles: false))
    }
}
