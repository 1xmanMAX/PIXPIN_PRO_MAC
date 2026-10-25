// Los marcadores del lienzo con su vista (Windows, `ventana_editor/marcas.rs`):
// las teclas (⌘M, las cifras de la tira, ⌘1…9, ⎋) y que poner una marca la
// deja junto al dibujo con su vista, por el puente de verdad.

import AppKit
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class MarcasLienzoTests: XCTestCase {
    private func tecla(_ letras: String, _ codigo: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: letras, charactersIgnoringModifiers: letras,
                         isARepeat: false, keyCode: codigo)!
    }

    @MainActor
    func testLasTeclasPonenLaMarcaYPonerlaGuardaSuVista() throws {
        let carpeta = try carpetaTemporal("marcas-lienzo")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ruta = carpeta.appendingPathComponent("m.excalidraw").path
        let ed = try EditorLienzo.deFichero(ruta: ruta, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed)
        let vista = VistaEditorLienzoNS(modelo: modelo)
        // Fuera de su ventana (el anotador) no hay marcas: las teclas siguen.
        XCTAssertFalse(vista.teclaDeMarcas(tecla("m", 46, .command)))
        modelo.abrirMirando()
        XCTAssertNotNil(modelo.marcas)

        // ⌘M abre la tira y su cifra elige el emoticono.
        XCTAssertTrue(vista.teclaDeMarcas(tecla("m", 46, .command)))
        XCTAssertEqual(modelo.poniendoMarca, .eligiendo)
        XCTAssertTrue(vista.teclaDeMarcas(tecla("2", 19)))
        XCTAssertEqual(modelo.poniendoMarca, .plantando(emojisDeMarcas()[1]))
        // ⎋ deja de ponerla, y sin poner no se la queda.
        XCTAssertTrue(vista.teclaDeMarcas(tecla("\u{1b}", 53)))
        XCTAssertEqual(modelo.poniendoMarca, .no)
        XCTAssertFalse(vista.teclaDeMarcas(tecla("\u{1b}", 53)))
        // ⌘7 sin septima marca se consume igual.
        XCTAssertTrue(vista.teclaDeMarcas(tecla("7", 26, .command)))

        // Poner una: va junto al dibujo, con la vista de ahora.
        let camara = CamaraDelLienzo(x: 10, y: 20, zoom: 2)
        let id = modelo.marcas!.poner(x: 100, y: 200, emoji: "⭐", camara: camara, anchoPx: 800, altoPx: 600)
        modelo.refrescarMarcas()
        XCTAssertEqual(modelo.listaMarcas.map(\.id), [id])
        XCTAssertTrue(modelo.listaMarcas[0].conVista)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ruta + ".pixpin-marcas"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ruta + ".pixpin-vistas"))
        // Su destino es la camara de entonces.
        XCTAssertEqual(modelo.marcas!.destino(id: id, camara: CamaraDelLienzo(x: 0, y: 0, zoom: 1),
                                              anchoPx: 800, altoPx: 600, bajoLaBarra: 60), camara)
        // Quitarla se lleva los dos ficheros (un dibujo suelto no viaja).
        modelo.quitarMarca(id)
        XCTAssertTrue(modelo.listaMarcas.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ruta + ".pixpin-vistas"))
    }
}
