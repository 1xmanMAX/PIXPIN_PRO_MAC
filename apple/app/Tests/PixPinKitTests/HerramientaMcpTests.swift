@testable import PixPinKit
import PixPinCore
import XCTest

@MainActor
final class HerramientaMcpTests: XCTestCase {
    func testElPedidoHerramientaDejaSuRespuestaEnElFichero() async throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-mcp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let h = HacerPedidos()
        h.avisar = { _ in }
        h.registrar(almacen: almacen, sincro: nil)
        var hechos: [String] = []
        PedidosDelAsistente.hacer = { json in hechos.append(json); return nil }
        defer { PedidosDelAsistente.hacer = nil }
        let resp = raiz.appendingPathComponent("r1.json")
        await h.hacerYa(Pedido("herramienta", ["nombre": .texto("escribir_en_chat"),
                                               "args": .objeto(["texto": .texto("hola")]),
                                               "respuesta": .texto(resp.path)]))
        let v = try JSONSerialization.jsonObject(with: Data(contentsOf: resp)) as? [String: Any]
        XCTAssertEqual(v?["ok"] as? Bool, true, "\(v ?? [:])")
        XCTAssertTrue(hechos.first?.contains("\"chat\"") ?? false, "\(hechos)")
        // Caso negativo: una herramienta que no existe contesta que no.
        let mal = raiz.appendingPathComponent("r2.json")
        await h.hacerYa(Pedido("herramienta", ["nombre": .texto("volar"), "respuesta": .texto(mal.path)]))
        let w = try JSONSerialization.jsonObject(with: Data(contentsOf: mal)) as? [String: Any]
        XCTAssertEqual(w?["ok"] as? Bool, false)
    }
}
