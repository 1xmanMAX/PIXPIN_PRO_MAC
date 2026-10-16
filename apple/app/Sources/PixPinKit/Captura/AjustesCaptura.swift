// Lo que la captura lee de `pixpinmax.toml` (el mismo fichero que Windows,
// `pixpin_store::ajustes`): los segundos de la captura con retardo
// (`retardo_captura_s`) y el formato del color de la lupa
// (`formato_color`). Las dos son claves sueltas de la raiz del TOML (van
// antes de la primera `[seccion]`).
//
// Solo se leen: cambiarlas es de la pantalla de Ajustes (C3), que escribe
// por el nucleo conservando el fichero. Leerlas aqui sin cruzar el puente
// es a proposito: abrir la captura no espera a Rust ni a nada, y un fichero
// roto o sin esas claves da los valores de fabrica de Windows (3 s, HEX).

import Foundation

/// El formato del color de la lupa (`FormatoColorLupa` de Windows).
public enum FormatoColorLupa: String, Sendable {
    case hex, rgb, hsl

    /// Lo que hace ⇧ sola en la captura: HEX ↔ RGB (y de HSL, a HEX).
    public var siguiente: FormatoColorLupa {
        switch self {
        case .hex: .rgb
        case .rgb, .hsl: .hex
        }
    }

    /// El color como texto, listo para ensenar y copiar (`texto_color` de
    /// Windows: `#RRGGBB`, `rgb(r, g, b)`, `hsl(h, s%, l%)`).
    public func texto(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
        switch self {
        case .hex:
            return MedidasCaptura.hex(r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            // La misma cuenta entera en milesimas que Windows, para que los
            // dos sistemas den el mismo texto.
            let (r, g, b) = (Int(r), Int(g), Int(b))
            let mayor = max(r, g, b), menor = min(r, g, b)
            let l = (mayor + menor) * 1000 / 510
            let delta = mayor - menor
            var h = 0, s = 0
            if delta != 0 {
                s = l > 500 ? delta * 1000 / (510 - mayor - menor) : delta * 1000 / (mayor + menor)
                if mayor == r {
                    h = ((60 * (g - b) / delta) % 360 + 360) % 360
                } else if mayor == g {
                    h = 60 * (b - r) / delta + 120
                } else {
                    h = 60 * (r - g) / delta + 240
                }
            }
            return "hsl(\(h), \((s + 5) / 10)%, \((l + 5) / 10)%)"
        }
    }
}

/// Lo de la captura que viene de `pixpinmax.toml`.
public struct AjustesCaptura: Equatable, Sendable {
    /// Segundos de la captura con retardo (de fabrica, 3; 0 = sin espera).
    public var retardoSegundos: Int
    public var formatoColor: FormatoColorLupa
    /// `[gif] por_segundo`: fotogramas por segundo del GIF (10).
    public var gifPorSegundo = 10
    /// `[gif] retardo_s`: segundos entre «Grabar» y el primer fotograma (0).
    public var gifRetardo = 0

    public static let deFabrica = AjustesCaptura(retardoSegundos: 3, formatoColor: .hex)

    /// El tope de la espera: mas de un minuto solo puede ser un error.
    public static let retardoMaximo = 60

    public init(retardoSegundos: Int, formatoColor: FormatoColorLupa) {
        self.retardoSegundos = retardoSegundos
        self.formatoColor = formatoColor
    }

    /// Los ritmos del GIF que se ofrecen (`RITMOS` de Windows).
    public static let ritmosGif = [5, 10, 15, 20, 25, 30]

    /// El ritmo ofrecido mas cercano a `n` (`indice_de_ritmo` de Windows).
    public static func ritmoGif(cercaDe n: Int) -> Int {
        ritmosGif.min { abs($0 - n) < abs($1 - n) } ?? 10
    }

    /// Lee las claves de la raiz de un TOML y las de `[gif]`. Lo que falte
    /// o no se entienda se queda como de fabrica.
    public static func leer(toml: String) -> AjustesCaptura {
        var a = deFabrica
        var seccion = ""
        for linea in toml.split(whereSeparator: \.isNewline) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            // Una `retardo_captura_s` dentro de otra tabla no es la nuestra.
            if l.hasPrefix("[") {
                seccion = l.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            guard !l.hasPrefix("#"), let igual = l.firstIndex(of: "=") else { continue }
            let clave = l[..<igual].trimmingCharacters(in: .whitespaces)
            var valor = l[l.index(after: igual)...].trimmingCharacters(in: .whitespaces)
            if let almohadilla = valor.firstIndex(of: "#") {
                valor = valor[..<almohadilla].trimmingCharacters(in: .whitespaces)
            }
            if seccion == "gif" {
                if clave == "por_segundo", let n = Int(valor), n > 0 { a.gifPorSegundo = min(n, 60) }
                if clave == "retardo_s", let n = Int(valor), n >= 0 { a.gifRetardo = min(n, retardoMaximo) }
                continue
            }
            guard seccion.isEmpty else { continue }
            switch clave {
            case "retardo_captura_s":
                if let n = Int(valor), n >= 0 { a.retardoSegundos = min(n, retardoMaximo) }
            case "formato_color":
                let limpio = valor.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
                if let f = FormatoColorLupa(rawValue: limpio) { a.formatoColor = f }
            default:
                break
            }
        }
        return a
    }

    /// El fichero de ajustes de la carpeta de datos.
    public static var fichero: URL {
        carpetaDeDatos().appendingPathComponent("pixpinmax.toml")
    }

    /// Los de ahora (de fabrica si no hay fichero o no se puede leer).
    public static func actuales(_ url: URL = fichero) -> AjustesCaptura {
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return deFabrica }
        return leer(toml: texto)
    }
}
