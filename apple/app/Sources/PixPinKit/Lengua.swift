// **El idioma de la interfaz**, el de Windows (`Catalogo` de
// `pixpin-store`): los catorce idiomas de `i18n/<etiqueta>/main.ftl` son la
// unica fuente de los textos, aqui y en Windows. Cada texto se pide por su
// clave al nucleo (`CatalogoDeTextos`), que hace los plurales de cada lengua.
//
// El idioma es el de `idioma` de `pixpinmax.toml` (el mismo campo y los
// mismos codigos que Windows: sincroniza) o, con «sistema», el del Mac. Como
// en Windows, vale desde el arranque: el catalogo se crea una vez.
//
// El arabe va de derecha a izquierda (`direccion`, que pone
// `idiomaDeLaApp()` en la raiz de cada ventana) y las fechas y los numeros
// salen con el `Locale` del idioma elegido (`locale`).

import Foundation
import PixPinCore
import SwiftUI

public enum Lengua {
    /// El catalogo de la app, del `pixpinmax.toml` de la carpeta de datos.
    /// En las pruebas, siempre en espanol (comparan los textos de Windows en
    /// espanol, sea cual sea el idioma del Mac que las pasa).
    public static let catalogo: CatalogoDeTextos = enPruebas
        ? CatalogoDeTextos.nuevo(idioma: "es", localeSistema: "es")
        : textosDeLaApp(raiz: carpetaDeDatos().path, localeSistema: localeDelMac)

    /// Si corre dentro de XCTest.
    static var enPruebas: Bool { NSClassFromString("XCTestCase") != nil }

    /// El idioma del Mac: el de Ajustes del Sistema, no el que esta app se
    /// pone en `AppleLanguages` (`ModeloAjustes.aplicar(idioma:en:)`).
    public static var localeDelMac: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let lista = global?["AppleLanguages"] as? [String], let primero = lista.first {
            return primero
        }
        return Locale.preferredLanguages.first ?? "es"
    }

    /// El texto de `clave` en el idioma de la app.
    public static func t(_ clave: String) -> String {
        catalogo.t(clave: clave)
    }

    /// El texto de `clave` con sus `{ $argumentos }` (los numeros eligen el
    /// plural de cada lengua).
    public static func t(_ clave: String, _ argumentos: [String: Any]) -> String {
        var textos: [String: String] = [:]
        for (k, v) in argumentos { textos[k] = "\(v)" }
        return catalogo.conArgumentos(clave: clave, argumentos: textos)
    }

    /// Si se escribe de derecha a izquierda (el arabe).
    public static let deDerechaAIzquierda: Bool = catalogo.deDerechaAIzquierda()

    /// La direccion de la interfaz.
    public static var direccion: LayoutDirection {
        deDerechaAIzquierda ? .rightToLeft : .leftToRight
    }

    /// El `Locale` de las fechas y los numeros: el del Mac si se sigue al
    /// sistema (con su region), el del idioma elegido si no.
    public static let locale: Locale =
        catalogo.sigueAlSistema() ? Locale.autoupdatingCurrent : Locale(identifier: catalogo.etiqueta())

    /// `.dateTime` con el `Locale` del idioma de la app: los dias y los
    /// meses en su lengua (`fecha.formatted(Lengua.fechas.day().month())`).
    public static var fechas: Date.FormatStyle { Date.FormatStyle(locale: locale) }

    /// Las opciones del selector de Ajustes: «el del Mac» y los catorce, cada
    /// uno con su nombre en su lengua, y el codigo que va al fichero.
    public static var opciones: [OpcionDeIdioma] { catalogo.opcionesDeIdioma() }

    /// Los catorce codigos de `idioma` (sin «sistema»): `es`, `zh-CN`…
    public static var codigos: [String] { opciones.map(\.valor).filter { $0 != "sistema" } }
}

public extension View {
    /// La direccion (el arabe, de derecha a izquierda) y el `Locale` del
    /// idioma de la app, para la raiz de una ventana.
    func idiomaDeLaApp() -> some View {
        environment(\.layoutDirection, Lengua.direccion)
            .environment(\.locale, Lengua.locale)
    }
}
