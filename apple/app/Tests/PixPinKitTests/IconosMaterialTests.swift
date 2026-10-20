import SwiftUI
import XCTest
@testable import PixPinKit

@MainActor
final class IconosMaterialTests: XCTestCase {
    /// Todos los trazados de Windows se leen y llenan su caja de 24.
    func testTodosLosIconosSeDibujan() throws {
        for (n, trazos) in TrazadosMaterial.todos {
            for (d, _) in trazos {
                let r = FormaMaterial.leer(d).boundingRect
                XCTAssertFalse(r.isEmpty, n)
                XCTAssertTrue(r.minX > -1 && r.maxX < 25 && r.minY > -1 && r.maxY < 25, "\(n) \(r)")
            }
        }
        // Una hoja de muestra para mirarla.
        let hoja = VStack(alignment: .leading) {
            ForEach(Array(TrazadosMaterial.todos.keys.sorted().chunked(12)), id: \.self) { fila in
                HStack { ForEach(fila, id: \.self) { IconoMaterial(nombre: $0, lado: 32) } }
            }
        }.padding().background(Color.white).foregroundStyle(Color.black)
        if let ruta = ProcessInfo.processInfo.environment["PIXPIN_HOJA_ICONOS"],
           let img = ImageRenderer(content: hoja).nsImage,
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ruta))
        }
    }
}

private extension Array {
    func chunked(_ n: Int) -> [[Element]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) }
    }
}
