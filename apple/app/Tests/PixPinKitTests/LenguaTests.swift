// Los catorce idiomas de Windows en la interfaz del Mac (`Lengua.swift`):
// los textos salen del catalogo de `pixpin-store` por el puente, el selector
// guarda el mismo codigo que Windows y el arabe va de derecha a izquierda.

import Foundation
import PixPinCore
@testable import PixPinKit
import SwiftUI
import XCTest

@MainActor
final class LenguaTests: XCTestCase {
    func testEnLasPruebasLosTextosSonLosDeWindowsEnEspanol() {
        XCTAssertEqual(Lengua.t("ajustes-idioma"), "Idioma")
        XCTAssertEqual(Lengua.t("ajustes2-sec-general"), "General")
        XCTAssertEqual(Lengua.t("carpeta-paginas", ["n": 1]), "1 página")
        XCTAssertEqual(Lengua.t("carpeta-paginas", ["n": 3]), "3 páginas")
        XCTAssertEqual(Lengua.direccion, .leftToRight)
    }

    func testElSelectorTieneElDelMacYLosCatorceConSuNombre() {
        let o = Lengua.opciones
        XCTAssertEqual(o.count, 15)
        XCTAssertEqual(o.first?.valor, "sistema")
        XCTAssertEqual(o.first?.nombre, "El de macOS")
        XCTAssertEqual(Lengua.codigos, ["es", "en", "zh-CN", "hi", "ar", "pt-BR", "fr", "de", "ja", "ru", "ko",
                                        "it", "id", "tr"])
        XCTAssertTrue(o.contains { $0.nombre == "日本語" })
    }

    func testOtroIdiomaTraduceYElArabeVaDeDerechaAIzquierda() {
        let en = CatalogoDeTextos.nuevo(idioma: "en", localeSistema: "es")
        XCTAssertEqual(en.t(clave: "ajustes-idioma"), "Language")
        let ar = CatalogoDeTextos.nuevo(idioma: "ar", localeSistema: "es")
        XCTAssertTrue(ar.deDerechaAIzquierda())
        XCTAssertEqual(ar.etiqueta(), "ar-SA")
        let mac = CatalogoDeTextos.nuevo(idioma: "sistema", localeSistema: "fr-CA")
        XCTAssertTrue(mac.sigueAlSistema())
        XCTAssertEqual(mac.etiqueta(), "fr-FR")
    }

    func testElIdiomaPoneElDeMacOSParaEstaApp() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "pixpin-lengua-\(UUID().uuidString)"))
        ModeloAjustes.aplicar(idioma: "ja", en: d)
        XCTAssertEqual(d.stringArray(forKey: "AppleLanguages"), ["ja"])
        ModeloAjustes.aplicar(idioma: "zh-CN", en: d)
        XCTAssertEqual(d.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        ModeloAjustes.aplicar(idioma: "sistema", en: d)
        XCTAssertNil(d.object(forKey: "AppleLanguages"))
    }
}
