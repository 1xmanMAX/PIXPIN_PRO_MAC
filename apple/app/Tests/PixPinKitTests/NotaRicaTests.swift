// La nota rica del chat (Windows 974d5ba, `Chat/NotaRica.swift`): que
// burbuja va con formato, que sus fotos salen en album y que la ruta de una
// foto nunca se ve como texto.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

final class NotaRicaTests: XCTestCase {
    func testUnaNotaLlanaSigueComoSiempre() {
        let notas = NotasRicas()
        XCTAssertNil(notas.pura("hola, que tal"))
        XCTAssertNil(notas.pura("dos\nrenglones"))
        XCTAssertNotNil(notas.pura("**Pendiente:** la escalera"))
    }

    func testLasFotosSeguidasSonUnAlbumSinRutaALaVista() throws {
        let texto = "Visita\n![](pixpin:files/guardados/pc/c/notas/1-a.png)\n![planta|300](pixpin:files/guardados/pc/c/notas/2-b.jpg)"
        let nota = try XCTUnwrap(NotasRicas().pura(texto))
        let fotos = NotasRicas.fotos(de: nota)
        XCTAssertEqual(fotos.count, 2)
        XCTAssertEqual(fotos.map(\.indice), [0, 1])
        XCTAssertEqual(fotos[1].alt, "planta", "sin el ancho del editor")
        XCTAssertNil(fotos[0].ruta, "sin mirar el disco no hay fichero")
        // Ningun bloque de texto lleva la ruta.
        for b in nota.bloques {
            if case let .texto(_, t, _, _) = b { XCTAssertFalse(t.contains("pixpin:files")) }
        }
    }

    func testElAlbumLlenaElAnchoComoWindows() {
        let a = albumDeNota(proporciones: [1, 1], ancho: 260, altoSolo: 270, altoFila: 180, hueco: 2)
        XCTAssertEqual(a.cajas.count, 2)
        XCTAssertEqual(a.cajas[0].y, a.cajas[1].y, "dos en una fila")
        XCTAssertEqual(Double(a.cajas[1].x + a.cajas[1].ancho), 260, accuracy: 0.01)
        XCTAssertTrue(esFotoDeNota(nombre: "Foto.HEIC"))
        XCTAssertFalse(esFotoDeNota(nombre: "plano.pdf"))
    }
}
