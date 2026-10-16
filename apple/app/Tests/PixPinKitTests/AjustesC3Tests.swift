// La pantalla de Ajustes como la de Windows (C3): las filas, el buscador,
// el punto azul, «Restablecer», «Deshacer» y que todo acabe en el mismo
// `pixpinmax.toml` que lee Windows.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class AjustesC3Tests: XCTestCase {
    private func modelo(_ nombre: String) throws -> (ModeloAjustes, Nucleo, URL, UserDefaults) {
        let dir = try carpetaTemporal(nombre)
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pixpin-pruebas-\(UUID().uuidString)"))
        return (ModeloAjustes(nucleo: nucleo, defaults: defaults), nucleo, dir, defaults)
    }

    func testLasSeccionesDeWindowsTienenFilasYUnIdUnico() {
        for s in SeccionAjustes.allCases {
            XCTAssertFalse(FilasAjustes.de(s).isEmpty, "\(s) sin filas")
        }
        let ids = FilasAjustes.todas.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        // Lo que pedia C3.
        for id in ["idioma", "retardo", "color", "scroll", "gif-ritmo", "gif-retardo", "carpeta", "caducidad",
                   "voz-segundo", "voz-modo", "asistente-motor", "clave-claude", "clave-deepseek",
                   "presencia", "automatica", "lo-mio", "arranque", "tema", "fichero"] {
            XCTAssertTrue(ids.contains(id), "falta \(id)")
        }
    }

    func testElBuscadorEncuentraEnTodasSinTildes() {
        let r = FilasAjustes.buscar("retardo")
        XCTAssertEqual(r.first?.seccion, .captura)
        XCTAssertTrue(FilasAjustes.buscar("lo mio").contains { $0.id == "lo-mio" })
        XCTAssertTrue(FilasAjustes.buscar("CLAVE claude").contains { $0.id == "clave-claude" })
        XCTAssertTrue(FilasAjustes.buscar("no existe esto").isEmpty)
        XCTAssertTrue(FilasAjustes.buscar("  ").isEmpty)
    }

    func testCambiarGuardaEnElTomlYDeshacerVuelve() async throws {
        let (m, nucleo, dir, _) = try modelo("c3-cambiar")
        await m.cargar()
        XCTAssertEqual(m.valores, m.fabrica)
        XCTAssertFalse(FilasAjustes.hayCambios(en: .captura, m))

        m.cambiar { $0.retardoCapturaS = 5 }
        m.cambiar { $0.formatoColor = "hsl" }
        m.cambiar { $0.sincroLoMioManda = true }
        await m.guardar()
        XCTAssertNil(m.error)
        let leido = try nucleo.ajustes()
        XCTAssertEqual(leido.retardoCapturaS, 5)
        XCTAssertEqual(leido.formatoColor, "hsl")
        XCTAssertTrue(leido.sincroLoMioManda)
        let texto = try String(contentsOf: dir.appendingPathComponent("pixpinmax.toml"), encoding: .utf8)
        XCTAssertTrue(texto.contains("retardo_captura_s = 5"))
        XCTAssertTrue(texto.contains("formato_color = \"hsl\""))

        let retardo = try XCTUnwrap(FilasAjustes.de(.captura).first { $0.id == "retardo" })
        XCTAssertTrue(retardo.cambiada(m))
        XCTAssertTrue(FilasAjustes.hayCambios(en: .captura, m))

        m.deshacer()
        XCTAssertFalse(m.valores.sincroLoMioManda)
        XCTAssertEqual(m.valores.formatoColor, "hsl")
        await m.guardar()
        XCTAssertFalse(try nucleo.ajustes().sincroLoMioManda)

        // «Restablecer Captura» en un solo paso, y se deshace entero.
        FilasAjustes.restablecer(.captura, m)
        XCTAssertEqual(m.valores.retardoCapturaS, 3)
        XCTAssertEqual(m.valores.formatoColor, "hex")
        XCTAssertFalse(FilasAjustes.hayCambios(en: .captura, m))
        m.deshacer()
        XCTAssertEqual(m.valores.retardoCapturaS, 5)
        XCTAssertEqual(m.valores.formatoColor, "hsl")
    }

    func testLosControlesRespetanLosRangosDeWindows() async throws {
        let (m, nucleo, _, _) = try modelo("c3-rangos")
        await m.cargar()
        let scroll = try XCTUnwrap(FilasAjustes.de(.captura).first { $0.id == "scroll" })
        guard case let .numero(rango, paso, texto, get, set) = scroll.control else {
            return XCTFail("el scroll es un numero")
        }
        XCTAssertEqual(rango, 2_000 ... 100_000)
        XCTAssertEqual(paso, 2_000)
        set(m, 1_000_000)
        XCTAssertEqual(get(m), 100_000)
        XCTAssertTrue(texto(get(m)).hasSuffix("px"))
        let pensar = try XCTUnwrap(FilasAjustes.de(.asistente).first { $0.id == "asistente-pensar" })
        guard case let .opcion(opciones, getO, setO) = pensar.control else { return XCTFail("pensar es opcion") }
        XCTAssertEqual(opciones.count, 3)
        XCTAssertEqual(getO(m), 0)
        setO(m, 2)
        XCTAssertEqual(m.valores.asistentePensar, false)
        await m.guardar()
        XCTAssertNil(m.error)
        XCTAssertEqual(try nucleo.ajustes().asistentePensar, false)
    }

    func testElIdiomaVaAlTomlYAlMac() async throws {
        let (m, nucleo, _, defaults) = try modelo("c3-idioma")
        await m.cargar()
        m.cambiar { $0.idioma = "en" }
        await m.guardar()
        XCTAssertEqual(try nucleo.ajustes().idioma, "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        m.cambiar { $0.idioma = "sistema" }
        XCTAssertNotEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
    }

    func testElPdfTambienSeDeshace() async throws {
        let (m, nucleo, _, _) = try modelo("c3-pdf")
        await m.cargar()
        XCTAssertEqual(m.pdf, ModeloAjustes.pdfDeFabrica)
        m.cambiarPdf { $0.nivel = .extremo }
        await m.guardar()
        XCTAssertEqual(try nucleo.ajustesPdf().nivel, .extremo)
        XCTAssertTrue(FilasAjustes.hayCambios(en: .general, m))
        m.deshacer()
        XCTAssertEqual(m.pdf?.nivel, .equilibrado)
    }
}
