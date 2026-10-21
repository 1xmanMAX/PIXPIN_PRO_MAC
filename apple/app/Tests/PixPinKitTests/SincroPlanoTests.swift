@testable import PixPinKit
import MetalKit
import XCTest

final class SincroPlanoTests: XCTestCase {
    @MainActor func testLaCapaDeMetalVaConLaTransaccion() throws {
        guard let motor = MotorMetal.compartido else { throw XCTSkip("sin Metal") }
        let v = VistaPlanoMetal(visor: VisorPlano(ruta: "/nada.dwg", titulo: "x"), motor: motor)
        print("CAPA", String(describing: v.layer), (v.layer as? CAMetalLayer)?.presentsWithTransaction as Any)
    }
}
