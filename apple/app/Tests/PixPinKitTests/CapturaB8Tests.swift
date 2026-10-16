// La captura que faltaba (B8): la cuenta atras, los ajustes de la captura,
// el formato del color y mover la zona con las flechas.

import AppKit
import CoreGraphics
@testable import PixPinKit
import XCTest

final class CapturaB8Tests: XCTestCase {
    func testLaCuentaEmpiezaEnElTotalYAcabaEnUno() {
        // El fallo del redondeo hacia abajo: una cuenta de tres no ensenaria
        // nunca el tres (`cuenta_atras.rs` de Windows).
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 0), 3)
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 0.001), 3)
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 0.999), 3)
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 1.0), 2)
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 2.001), 1)
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 2.999), 1)
    }

    func testAlLlegarNoQuedaNada() {
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 3), 0)
        // Pasarse de largo no da un numero negativo.
        XCTAssertEqual(CuentaAtras.quedan(total: 3, transcurrido: 9), 0)
    }

    func testElCartelVaAbajoALaDerecha() {
        let r = CuentaAtras.marco(en: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(r, CGRect(x: 1440 - 108 - 24, y: 24, width: 108, height: 108))
        // En una segunda pantalla, en su esquina y no en la de la primera.
        let otra = CuentaAtras.marco(en: CGRect(x: 1440, y: -200, width: 1920, height: 1080))
        XCTAssertEqual(otra.maxX, 1440 + 1920 - 24)
        XCTAssertEqual(otra.minY, -200 + 24)
    }

    func testLosAjustesSeLeenDeLaRaizDelToml() {
        let toml = """
        # Ajustes de PixPin
        idioma = "es"
        formato_color = "rgb"
        retardo_captura_s = 7 # segundos

        [capturas]
        dias_caducidad = 3
        """
        let a = AjustesCaptura.leer(toml: toml)
        XCTAssertEqual(a.retardoSegundos, 7)
        XCTAssertEqual(a.formatoColor, .rgb)
    }

    func testSinFicheroOConBasuraSalenLosDeFabrica() {
        XCTAssertEqual(AjustesCaptura.leer(toml: ""), .deFabrica)
        XCTAssertEqual(AjustesCaptura.deFabrica.retardoSegundos, 3)
        let malo = AjustesCaptura.leer(toml: "retardo_captura_s = -2\nformato_color = \"cmyk\"")
        XCTAssertEqual(malo, .deFabrica)
        // Una clave igual dentro de otra tabla no es la de la raiz.
        let dentro = AjustesCaptura.leer(toml: "[gif]\nretardo_captura_s = 9")
        XCTAssertEqual(dentro.retardoSegundos, 3)
        // Un numero enorme se queda en el tope.
        XCTAssertEqual(AjustesCaptura.leer(toml: "retardo_captura_s = 100000").retardoSegundos,
                       AjustesCaptura.retardoMaximo)
    }

    func testElGifLeeSuSeccionYSeQuedaEnLosRitmosDeWindows() {
        let toml = """
        retardo_captura_s = 4

        [gif]
        por_segundo = 15
        retardo_s = 2
        """
        let a = AjustesCaptura.leer(toml: toml)
        XCTAssertEqual(a.retardoSegundos, 4)
        XCTAssertEqual(a.gifPorSegundo, 15)
        XCTAssertEqual(a.gifRetardo, 2)
        XCTAssertEqual(AjustesCaptura.deFabrica.gifPorSegundo, 10)
        // `indice_de_ritmo` de Windows: el ofrecido mas cercano.
        XCTAssertEqual(AjustesCaptura.ritmoGif(cercaDe: 11), 10)
        XCTAssertEqual(AjustesCaptura.ritmoGif(cercaDe: 1), 5)
        XCTAssertEqual(AjustesCaptura.ritmoGif(cercaDe: 1000), 30)
    }

    func testElColorSeEscribeEnLosTresFormatosDeWindows() {
        XCTAssertEqual(FormatoColorLupa.hex.texto(255, 59, 48), "#FF3B30")
        XCTAssertEqual(FormatoColorLupa.rgb.texto(255, 59, 48), "rgb(255, 59, 48)")
        // Los de `lupa.rs` de Windows.
        XCTAssertEqual(FormatoColorLupa.hsl.texto(255, 0, 0), "hsl(0, 100%, 50%)")
        XCTAssertEqual(FormatoColorLupa.hsl.texto(128, 128, 128), "hsl(0, 0%, 50%)")
        XCTAssertEqual(FormatoColorLupa.hsl.texto(0, 0, 255), "hsl(240, 100%, 50%)")
    }

    func testMayusAlternaHexYRgb() {
        XCTAssertEqual(FormatoColorLupa.hex.siguiente, .rgb)
        XCTAssertEqual(FormatoColorLupa.rgb.siguiente, .hex)
        XCTAssertEqual(FormatoColorLupa.hsl.siguiente, .hex)
    }

    func testLasFlechasMuevenLaZonaSinSacarlaDeLaPantalla() {
        let pantalla = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let zona = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(GeometriaCaptura.deslizar(zona, dx: 10, dy: -1, dentroDe: pantalla),
                       CGRect(x: 110, y: 99, width: 200, height: 100))
        // Al llegar al borde se queda pegada, sin encoger.
        XCTAssertEqual(GeometriaCaptura.deslizar(zona, dx: -500, dy: 0, dentroDe: pantalla).minX, 0)
        let arriba = GeometriaCaptura.deslizar(zona, dx: 0, dy: 5000, dentroDe: pantalla)
        XCTAssertEqual(arriba.maxY, 800)
        XCTAssertEqual(arriba.size, zona.size)
    }

    @MainActor
    func testLasBarrasSoloSeQuedanElRatonEnSusIslas() throws {
        let estado = EstadoBarrasCaptura()
        let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless],
                               backing: .buffered, defer: false)
        let contenedor = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        ventana.contentView = contenedor
        let barras = HospedajeBarrasCaptura(estado: estado)
        barras.frame = contenedor.bounds
        contenedor.addSubview(barras)
        // Escondidas, nada.
        XCTAssertNil(barras.hitTest(NSPoint(x: 100, y: 100)))
        // La de acciones arriba a la izquierda (origen arriba, el de SwiftUI).
        estado.acciones = CGRect(origin: CGPoint(x: 20, y: 20), size: BarraAccionesCaptura.tamano())
        estado.visibles = true
        for _ in 0 ..< 5 {
            barras.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(estado.zonas.isEmpty, "la isla apunta donde esta")
        // Dentro de la isla (en AppKit, origen abajo), el raton es suyo...
        let dentro = NSPoint(x: 40, y: 600 - 40)
        XCTAssertNotNil(barras.hitTest(dentro))
        // ...y fuera pasa a la captura.
        XCTAssertNil(barras.hitTest(NSPoint(x: 600, y: 100)))
    }
}
