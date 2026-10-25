// **Que sabe hacer el panel de la barra de menus** (`centro_bandeja/
// acciones.rs` de Windows): cada boton es una `AccionBandeja`, y cada accion
// va por el MISMO camino que su entrada del menu y su atajo
// (`GestorAtajos.ejecutar`, el catalogo de `ComandosApp`). Asi el panel no
// duplica nada.
//
// Aqui va tambien lo puro del panel: el buscador de acciones, los favoritos
// y su icono y color. Se prueba sin ventana.

import Foundation

/// Una cosa que se puede pedir desde el panel.
public enum AccionBandeja: Hashable, Sendable {
    /// Un comando del catalogo (`ComandoAtajo`).
    case comando(ComandoAtajo)
    /// Las entradas de la bandeja que no son comandos (las ventanas), con
    /// los nombres de Windows.
    case lecciones
    case nuevaLeccion
    case galeria
    case tareas
    case abrirDocumento
    case gruposVentanas

    /// Las que no son comandos, con su nombre estable (el de
    /// `[bandeja] favoritos`) y su titulo.
    static let otras: [(accion: AccionBandeja, nombre: String, titulo: String)] = [
        (.lecciones, "lecciones", "Lecciones"),
        (.nuevaLeccion, "nueva-leccion", "Nueva lección"),
        (.galeria, "galeria-capturas", "Galería de capturas"),
        (.tareas, "tareas", "Tareas"),
        (.abrirDocumento, "abrir-documento", "Abrir documento…"),
        (.gruposVentanas, "grupos-ventanas", "Grupos de ventanas"),
    ]

    /// Cuantos favoritos caben: dos filas de cuatro, una con «Añadir».
    public static let tope = 7
    /// Los de fabrica: pinear lo copiado, anotar la pantalla y el pin en vivo.
    public static let deFabrica = ["pinear-portapapeles", "anotar", "pinear-en-vivo"]

    /// El nombre con que se guarda en `[bandeja] favoritos`.
    public var nombre: String {
        if case let .comando(c) = self { return c.nombre }
        return Self.otras.first { $0.accion == self }?.nombre ?? ""
    }

    public static func desde(nombre: String) -> AccionBandeja? {
        if let o = otras.first(where: { $0.nombre == nombre }) { return o.accion }
        guard let c = ComandoAtajo.desde(nombre: nombre) else { return nil }
        let a = AccionBandeja.comando(c)
        return todas().contains(a) ? a : nil
    }

    /// El titulo: los de la maqueta, mas cortos que los del menu.
    public var titulo: String {
        switch self {
        case .comando(.pinearPortapapeles): return "Pinear copiado"
        case .comando(.anotar): return "Anotar pantalla"
        case .comando(.pinearEnVivo): return "Pin en vivo"
        case .comando(.abrirChat): return "Abrir PixPin"
        case let .comando(c): return c.titulo
        default: return Self.otras.first { $0.accion == self }?.titulo ?? ""
        }
    }

    /// Si al pedirla el panel se cierra. Los interruptores lo dejan abierto:
    /// se ve el cambio en el mismo sitio donde se pulso. «Sincronizar ahora»
    /// tambien (en el Mac): el estado de arriba dice como va.
    public var cierraElPanel: Bool {
        switch self {
        case .comando(.alternarPines), .comando(.alternarPasoDeClics), .comando(.silenciarAtajos),
             .comando(.sincronizar): false
        default: true
        }
    }

    /// Si lo que hace mira la pantalla (una captura, anotar encima): el panel
    /// tiene que haberse ido antes, o saldria en la foto.
    public var miraLaPantalla: Bool {
        guard case let .comando(c) = self else { return false }
        switch c {
        case .capturarRegion, .capturarYCopiar, .capturarConScroll, .capturarYAnotar, .capturarUltimaRegion,
             .grabarGif, .grabarPantalla, .grabarClase, .cuentagotas, .pinear, .pinearEnVivo, .anotar, .anotarCongelada,
             .capturarConRetardo, .copiarTexto, .ventanaEncima:
            return true
        default:
            return false
        }
    }

    /// El simbolo (SF Symbols) que hace de icono de Windows.
    public var simbolo: String {
        switch self {
        case let .comando(c):
            switch c {
            case .capturarRegion, .capturarYCopiar: return "viewfinder"
            case .capturarUltimaRegion: return "rectangle.dashed"
            case .capturarConScroll: return "arrow.up.and.down.text.horizontal"
            case .capturarYAnotar, .anotar, .anotarCongelada: return "pencil.tip"
            case .grabarGif: return "record.circle"
            case .grabarPantalla: return "video"
            case .grabarClase: return "mic"
            case .cuentagotas: return "eyedropper"
            case .pinear, .pinearEnVivo, .pinearSeleccion: return "pin"
            case .pinearPortapapeles: return "doc.on.clipboard"
            case .cerrarTodosLosPines: return "xmark"
            case .alternarPines: return "eye.slash"
            case .alternarPasoDeClics: return "cursorarrow.click"
            case .silenciarAtajos: return "keyboard"
            case .capturarConRetardo: return "timer"
            case .restaurarUltimoPin: return "arrow.uturn.backward"
            case .copiarTexto: return "text.viewfinder"
            case .ventanaEncima: return "macwindow.on.rectangle"
            case .abrirChat: return "bubble.left.and.bubble.right"
            case .abrirAjustes: return "gearshape"
            case .sincronizar: return "arrow.triangle.2.circlepath"
            case .salir: return "power"
            case .buscar: return "magnifyingglass"
            case .recibirDelMovil: return "iphone.and.arrow.forward"
            }
        case .lecciones, .nuevaLeccion: return "lightbulb"
        case .galeria: return "photo.on.rectangle"
        case .tareas: return "checklist"
        case .abrirDocumento: return "folder"
        case .gruposVentanas: return "square.on.square"
        }
    }

    /// El color de la ficha de un favorito (`0xRRGGBB`): verde los pines,
    /// naranja anotar, morado la voz y el color, azul capturar; gris lo demas.
    public var color: UInt32 {
        switch self {
        case let .comando(c):
            switch c {
            case .pinear, .pinearEnVivo, .pinearPortapapeles, .pinearSeleccion, .restaurarUltimoPin,
                 .cerrarTodosLosPines, .alternarPines, .alternarPasoDeClics:
                return 0x248A3D
            case .anotar, .anotarCongelada, .capturarYAnotar:
                return 0xB86E00
            case .grabarGif, .copiarTexto, .cuentagotas:
                return 0x8E44B8
            case .grabarClase:
                return 0xC9302C
            case .capturarRegion, .capturarYCopiar, .capturarConScroll, .capturarUltimaRegion,
                 .capturarConRetardo, .grabarPantalla:
                return 0x0060DF
            default:
                return 0x48484A
            }
        case .lecciones, .nuevaLeccion: return 0x9A7400
        case .tareas: return 0x1F7A3A
        default: return 0x48484A
        }
    }

    /// Todas las que el panel puede ofrecer: el catalogo y luego las
    /// ventanas. Sin «Salir» (va aparte, al fondo y en rojo) ni «Recibir del
    /// movil» (cuelga de Sincronizar). `disponible` quita los comandos que
    /// este Mac aun no sabe hacer.
    public static func todas(disponible: (ComandoAtajo) -> Bool = { _ in true }) -> [AccionBandeja] {
        ComandoAtajo.allCases
            .filter { $0 != .salir && $0 != .recibirDelMovil && disponible($0) }
            .map { AccionBandeja.comando($0) } + otras.map(\.accion)
    }

    // MARK: Lo fijo del panel

    /// La fila de modos de «Capturar». Como en Windows, sin «Ventana» ni
    /// «Pantalla»: la zona ya engancha ventanas y ⌘A coge la pantalla.
    public static let modos: [(comando: ComandoAtajo, titulo: String)] = [
        (.capturarRegion, "Zona"),
        (.capturarConScroll, "Scroll"),
        (.grabarGif, "GIF"),
        (.copiarTexto, "Texto"),
        (.capturarConRetardo, "Retardo"),
        (.cuentagotas, "Color"),
    ]

    /// Las ventanas de la rejilla de abajo.
    public static let ventanas: [AccionBandeja] = [.comando(.abrirChat), .tareas, .lecciones, .abrirDocumento]
}

// MARK: - Favoritos y buscador

public enum ReglasBandeja {
    /// Los favoritos que dicen los nombres guardados; lo que ya no existe se
    /// salta, sin repetir y hasta el tope.
    public static func favoritos(de nombres: [String]) -> [AccionBandeja] {
        var v: [AccionBandeja] = []
        for a in nombres.compactMap(AccionBandeja.desde(nombre:)) where !v.contains(a) {
            v.append(a)
        }
        return Array(v.prefix(AccionBandeja.tope))
    }

    /// Pone o quita un favorito. `false` si no cabe (ya hay el tope).
    @discardableResult
    public static func alternarFavorito(_ favoritos: inout [AccionBandeja], _ a: AccionBandeja) -> Bool {
        if let i = favoritos.firstIndex(of: a) {
            favoritos.remove(at: i)
            return true
        }
        guard favoritos.count < AccionBandeja.tope else { return false }
        favoritos.append(a)
        return true
    }

    /// En minusculas y sin tildes: «Galería» y «galeria» son lo mismo.
    public static func normalizar(_ s: String) -> String {
        let sin = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
        return String(sin.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }.map(Character.init))
    }

    /// **El buscador de acciones.** Vale una accion si cada palabra aparece
    /// en su titulo; primero las que EMPIEZAN por lo escrito, luego las que
    /// tienen una palabra que empieza asi, y al final el resto.
    public static func buscar(_ consulta: String, en titulos: [(AccionBandeja, String)]) -> [AccionBandeja] {
        let q = normalizar(consulta)
        let palabras = q.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let primera = palabras.first else { return [] }
        let entera = q.trimmingCharacters(in: .whitespaces)
        var conNota: [(nota: Int, i: Int, a: AccionBandeja)] = []
        for (i, (a, t)) in titulos.enumerated() {
            let t = normalizar(t)
            guard palabras.allSatisfy({ t.contains($0) }) else { continue }
            let nota = t.hasPrefix(entera) ? 0
                : t.split(whereSeparator: \.isWhitespace).contains { $0.hasPrefix(primera) } ? 1 : 2
            conNota.append((nota, i, a))
        }
        return conNota.sorted { ($0.nota, $0.i) < ($1.nota, $1.i) }.map(\.a)
    }

    /// «hace 2 min», «hace 3 h», «ayer»… para el estado de la cabecera.
    public static func haceCuanto(_ cuando: Int64, ahora: Int64) -> String {
        let min = max(0, ahora - cuando) / 60_000
        switch min {
        case 0: return "ahora mismo"
        case 1...59: return "hace \(min) min"
        case 60...1439: return "hace \(min / 60) h"
        case 1440...2879: return "ayer"
        default: return "hace \(min / 1440) días"
        }
    }

    /// El estado de la sincronizacion de la cabecera.
    public static func estadoSincro(ultima: Int64, ahora: Int64) -> String {
        ultima > 0 ? "Sincronizado \(haceCuanto(ultima, ahora: ahora))" : "Sin sincronizar todavía"
    }
}
