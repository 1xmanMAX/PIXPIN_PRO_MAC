// **Los favoritos del panel de la barra de menus** (`pixpin_store::bandeja`
// de Windows): que acciones salen como botones grandes debajo de
// «Capturar». Viven en `pixpinmax.toml`, en su propia seccion, como alla:
//
//     [bandeja]
//     favoritos = ["pinear-portapapeles", "anotar", "pinear-en-vivo"]
//
// Se tocan aqui, en Swift, linea a linea y solo esa clave: el resto del
// fichero (comentarios, orden, claves que no conocemos) se queda como
// estaba. El nucleo guarda los demas ajustes «conservando» lo que no
// conoce, asi que nadie pisa a nadie.

import Foundation

public enum FavoritosBandeja {
    /// Los favoritos que dice `texto` (el fichero entero). `nil` si no dice
    /// nada, que no es lo mismo que una lista vacia: quien los quito todos
    /// los quiere sin ninguno, no con los de fabrica.
    public static func deTexto(_ texto: String) -> [String]? {
        let lineas = texto.components(separatedBy: "\n")
        guard let (desde, hasta) = clave(en: lineas) else { return nil }
        let valor = lineas[desde...hasta].joined(separator: "\n")
        guard let igual = valor.firstIndex(of: "=") else { return nil }
        var v: [String] = []
        for nombre in cadenas(String(valor[valor.index(after: igual)...])) {
            let n = nombre.trimmingCharacters(in: .whitespaces)
            if !n.isEmpty, !v.contains(n) { v.append(n) }
        }
        return Array(v.prefix(AccionBandeja.tope))
    }

    /// `texto` con los favoritos puestos y todo lo demas como estaba.
    public static func enTexto(_ texto: String, _ favoritos: [String]) -> String {
        let lista = favoritos.prefix(AccionBandeja.tope)
            .map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: ", ")
        let linea = "favoritos = [\(lista)]"
        var lineas = texto.components(separatedBy: "\n")
        if let (desde, hasta) = clave(en: lineas) {
            lineas.replaceSubrange(desde...hasta, with: [linea])
        } else if let cab = cabecera(en: lineas) {
            lineas.insert(linea, at: cab + 1)
        } else {
            // Sin seccion: al final, separada por una linea en blanco.
            while let ultima = lineas.last, ultima.trimmingCharacters(in: .whitespaces).isEmpty {
                lineas.removeLast()
            }
            if !lineas.isEmpty { lineas.append("") }
            lineas += ["[bandeja]", linea]
        }
        var fuera = lineas.joined(separator: "\n")
        if !fuera.hasSuffix("\n") { fuera += "\n" }
        return fuera
    }

    /// Lee los favoritos; sin fichero o sin seccion, los de fabrica.
    public static func leer(_ ruta: URL) -> [String] {
        (try? String(contentsOf: ruta, encoding: .utf8)).flatMap(deTexto) ?? AccionBandeja.deFabrica
    }

    /// Guarda tocando solo `[bandeja] favoritos` (a un temporal y luego se
    /// cambia el nombre: un corte a medias no deja el fichero roto).
    public static func guardar(_ ruta: URL, _ favoritos: [String]) throws {
        try FileManager.default.createDirectory(at: ruta.deletingLastPathComponent(), withIntermediateDirectories: true)
        let antes = (try? String(contentsOf: ruta, encoding: .utf8)) ?? ""
        try Data(enTexto(antes, favoritos).utf8).write(to: ruta, options: .atomic)
    }

    // MARK: Lo de dentro

    /// Una cabecera de tabla: `[algo]` o `[[algo]]`, con un comentario detras.
    private static func esCabecera(_ linea: String) -> Bool {
        linea.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    private static func cabecera(en lineas: [String]) -> Int? {
        lineas.firstIndex { l in
            var t = l.trimmingCharacters(in: .whitespaces)
            if let c = t.firstIndex(of: "#") { t = String(t[..<c]).trimmingCharacters(in: .whitespaces) }
            return t == "[bandeja]"
        }
    }

    /// Las lineas de `favoritos = [...]` dentro de `[bandeja]` (la lista
    /// puede ocupar varias, si alguien la escribio a mano).
    private static func clave(en lineas: [String]) -> (Int, Int)? {
        guard let cab = cabecera(en: lineas) else { return nil }
        var i = cab + 1
        while i < lineas.count, !esCabecera(lineas[i]) {
            let t = lineas[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("favoritos"), t.dropFirst("favoritos".count).trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                var fin = i
                var abiertos = corchetes(lineas[i])
                while abiertos > 0, fin + 1 < lineas.count {
                    fin += 1
                    abiertos += corchetes(lineas[fin])
                }
                return (i, fin)
            }
            i += 1
        }
        return nil
    }

    /// Cuantos `[` quedan abiertos en la linea (sin contar los de las
    /// cadenas ni los comentarios).
    private static func corchetes(_ linea: String) -> Int {
        var n = 0
        var cadena: Character?
        var escapado = false
        for c in linea {
            if let q = cadena {
                if escapado { escapado = false } else if c == "\\", q == "\"" { escapado = true } else if c == q { cadena = nil }
                continue
            }
            switch c {
            case "\"", "'": cadena = c
            case "#": return n
            case "[": n += 1
            case "]": n -= 1
            default: break
            }
        }
        return n
    }

    /// Las cadenas (`"…"` o `'…'`) de un valor, en orden.
    private static func cadenas(_ s: String) -> [String] {
        var v: [String] = []
        var actual = ""
        var cadena: Character?
        var escapado = false
        var comentario = false
        for c in s {
            if comentario {
                if c == "\n" { comentario = false }
                continue
            }
            if let q = cadena {
                if escapado {
                    actual.append(c)
                    escapado = false
                } else if c == "\\", q == "\"" {
                    escapado = true
                } else if c == q {
                    v.append(actual)
                    actual = ""
                    cadena = nil
                } else {
                    actual.append(c)
                }
                continue
            }
            if c == "#" {
                // Un comentario, hasta el final de su linea.
                comentario = true
                continue
            }
            if c == "\"" || c == "'" { cadena = c }
        }
        return v
    }
}
