// Las carpetas de paginas del chat (`Chat/Carpetas.swift`,
// `Compartir/PdfDeCarpeta.swift`): crearlas con una pagina, llenarlas desde
// el chat y su PDF con el indice, por el `Almacen` (que cruza el puente de
// verdad).

import Foundation
import PDFKit
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class CarpetasTests: XCTestCase {
    func testUnaCarpetaNaceConSuPaginaSeLlenaDesdeElChatYSaleEnPdf() async throws {
        let raiz = try carpetaTemporal("carpetas")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Diario")
        let chat = try XCTUnwrap(almacen.chats.first { $0.nombre == "Diario" }).id
        await almacen.abrir(chat: chat)
        let creado = await almacen.crearLienzo(en: chat)
        let lienzo = try XCTUnwrap(creado)
        XCTAssertTrue(CarpetasDelChat.seOfrece(lienzo))
        XCTAssertTrue(CarpetasDelChat.aLaVista(lienzo), "un lienzo lo lleva a la vista")

        // «Nueva carpeta con esta página»: nace con el lienzo dentro y con
        // el nombre listo para escribirlo.
        let c = ChatAbierto(chat: chat, almacen: almacen)
        c.crearCarpeta(primera: lienzo)
        try await esperar { almacen.mensajes[chat]?.contains(where: CarpetasDelChat.esCarpeta) == true }
        let carpeta = try XCTUnwrap(almacen.mensajes[chat]?.first(where: CarpetasDelChat.esCarpeta))
        XCTAssertEqual(carpeta.nombre, "Cuaderno")
        XCTAssertEqual(c.escritura, .renombrar(carpeta))
        XCTAssertTrue(carpeta.sePuedeRenombrar)
        XCTAssertEqual(CarpetasDelChat.detalle(carpeta), "1 página")
        XCTAssertFalse(CarpetasDelChat.seOfrece(carpeta), "una carpeta no entra en otra")

        // Una nota entra desde su menu («Más»), con el titulo de la serie.
        let escrita = await almacen.escribir(nota: "entre medias", en: chat)
        let nota = try XCTUnwrap(escrita)
        XCTAssertFalse(CarpetasDelChat.aLaVista(nota))
        c.anadir(nota, a: carpeta.id)
        try await esperar {
            almacen.mensajes[chat]?.first { $0.id == carpeta.id }.map(CarpetasDelChat.detalle) == "2 páginas"
        }
        let leida = await CarpetasDelChat.leer(carpeta.id, chat: chat, almacen: almacen)
        let enOrden = try XCTUnwrap(leida)
        XCTAssertEqual(enOrden.paginas.map(\.titulo), ["Página 1", "Página 2"], "sigue la serie de la carpeta")

        // El PDF: el lienzo vacio no da pagina; la nota si, con su marcador.
        let preparada = await PdfDeCarpeta.preparar(enOrden, chat: chat, almacen: almacen)
        XCTAssertEqual(preparada.indice.map(\.titulo), ["Página 2"])
        let datos = try XCTUnwrap(PdfDeCarpeta.pdf(preparada))
        let doc = try XCTUnwrap(PDFDocument(data: datos))
        XCTAssertEqual(doc.pageCount, 1)
        XCTAssertEqual(doc.outlineRoot?.numberOfChildren, 1)
        XCTAssertEqual(doc.outlineRoot?.child(at: 0)?.label, "Página 2")
        XCTAssertEqual(nombreDelPdfDeCarpeta(titulo: enOrden.nombre), "Cuaderno.pdf")

        // Caso negativo: una carpeta sin nada que exportar no da PDF.
        let vacia = CarpetaDePaginas(id: carpeta.id, nombre: "Vacía", paginas: [], mensaje: carpeta)
        let sinNada = await PdfDeCarpeta.preparar(vacia, chat: chat, almacen: almacen)
        XCTAssertNil(PdfDeCarpeta.pdf(sinNada))
    }

    /// Espera (poco) a que se cumpla algo que hace una tarea.
    private func esperar(_ cumple: () -> Bool) async throws {
        for _ in 0 ..< 100 where !cumple() {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(cumple())
    }
}
