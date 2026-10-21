@testable import PixPinKit
import PixPinCore
import ImageIO
import XCTest

/// El grafito se pinta con su mapa de casillas (como Windows), no liso.
final class GrafitoTests: XCTestCase {
    func testElGrafitoSaleComoSuMapa() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("grafito-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("g.excalidraw").path, crear: true)
        try ed.herramienta(nombre: "grafito")
        _ = ed.puntero(fase: .pulsar, x: 50, y: 50, presion: nil, modificadores: 0, zoom: 1)
        for i in 1 ... 20 {
            _ = ed.puntero(fase: .mover, x: 50 + Float(i) * 8, y: 50 + Float(i) * 3, presion: nil, modificadores: 0, zoom: 1)
        }
        _ = ed.puntero(fase: .soltar, x: 210, y: 110, presion: nil, modificadores: 0, zoom: 1)
        let leido = try leerLienzo(ed.planoDeVista(x: 0, y: 0, zoom: 1, anchoPx: 800, altoPx: 600))
        let mapas = leido.figuras.compactMap { f -> UInt64? in
            if case let .imagen(id, _, _, _, _, _) = f, id & GrafitosPintados.bit != 0 { return id }
            return nil
        }
        XCTAssertEqual(mapas.count, 1, "el trazo de grafito va como su mapa")
        XCTAssertNotNil(GrafitosPintados.imagen(mapas[0]), "y sus pixeles se pueden pintar")
        if let destino = ProcessInfo.processInfo.environment["PIXPIN_FOTO_GRAFITO"],
           let ctx = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            ctx.translateBy(x: 0, y: 200); ctx.scaleBy(x: 1, y: -1)
            PintorLienzo(lienzo: leido).pintar(en: ctx, limites: CGRect(x: 0, y: 0, width: 300, height: 200))
            if let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destino) as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
            }
        }
        // Caso negativo: el lapiz normal sigue liso.
        try ed.herramienta(nombre: "lapiz")
        _ = ed.puntero(fase: .pulsar, x: 50, y: 300, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: 150, y: 320, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 150, y: 320, presion: nil, modificadores: 0, zoom: 1)
        let otra = try leerLienzo(ed.planoDeVista(x: 0, y: 0, zoom: 1, anchoPx: 800, altoPx: 600))
        XCTAssertEqual(otra.figuras.filter { if case let .imagen(id, _, _, _, _, _) = $0 { return id & GrafitosPintados.bit != 0 }; return false }.count, 1)
    }
}
