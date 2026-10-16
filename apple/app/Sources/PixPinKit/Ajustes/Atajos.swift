// El catalogo de comandos que se pueden atar a un atajo global, como el de
// Windows (`pixpin-store/src/comandos.rs`): un nombre estable por comando
// (el contrato con lo guardado), su titulo, el atajo con el que nace y si
// sale en el menu de la barra.
//
// Reglas copiadas de Windows:
// - **El nombre no cambia nunca**; el titulo y el atajo, si.
// - Casi todo nace SIN atajo (D140): solo capturar (⌃⌥X), mostrar u
//   ocultar los pines (⌃2) y, solo en Mac, grabar la pantalla (⌃⌥R).
// - Cadena vacia = el usuario lo quiere sin atajo; no nombrarlo = el de
//   fabrica.
//
// El texto de un atajo es el de Windows («Ctrl+Alt+X»), con `Cmd` para ⌘:
// Ctrl es ⌃, Alt es ⌥ y Shift es ⇧. Aqui solo vive la logica pura (leer,
// escribir, choques); registrar en Carbon lo hace `GestorAtajos`.

import AppKit
import Carbon.HIToolbox
import Foundation

/// Cada cosa de PixPin que se puede atar a un atajo global.
public enum ComandoAtajo: String, CaseIterable, Identifiable, Sendable {
    // En el orden del catalogo de Windows (los nombres son los suyos).
    case capturarRegion = "capturar-region"
    case capturarYCopiar = "capturar-y-copiar"
    case capturarConScroll = "capturar-con-scroll"
    case capturarYAnotar = "capturar-y-anotar"
    case grabarGif = "grabar-gif"
    case capturarUltimaRegion = "capturar-ultima-region"
    case cuentagotas
    case pinear
    case pinearEnVivo = "pinear-en-vivo"
    case pinearPortapapeles = "pinear-portapapeles"
    case anotar
    case anotarCongelada = "anotar-congelada"
    case pinearSeleccion = "pinear-seleccion"
    case capturarConRetardo = "capturar-con-retardo"
    case silenciarAtajos = "silenciar-atajos"
    case alternarPasoDeClics = "alternar-paso-de-clics"
    case alternarPines = "alternar-pines"
    case restaurarUltimoPin = "restaurar-ultimo-pin"
    case cerrarTodosLosPines = "cerrar-todos-los-pines"
    case copiarTexto = "copiar-texto"
    case ventanaEncima = "ventana-encima"
    case abrirChat = "abrir-chat"
    case abrirAjustes = "abrir-ajustes"
    case recibirDelMovil = "recibir-del-movil"
    case salir
    case sincronizar
    case buscar
    /// Solo en Mac: grabar la pantalla en video (o parar).
    case grabarPantalla = "grabar-pantalla"

    public var id: String { rawValue }

    /// El nombre que se guarda (el de Windows).
    public var nombre: String { rawValue }

    public static func desde(nombre: String) -> ComandoAtajo? {
        ComandoAtajo(rawValue: nombre)
    }

    public var titulo: String {
        switch self {
        case .capturarRegion: "Capturar una zona"
        case .capturarYCopiar: "Capturar y copiar"
        case .capturarConScroll: "Captura con scroll"
        case .capturarYAnotar: "Capturar y anotar"
        case .grabarGif: "Grabar un GIF"
        case .capturarUltimaRegion: "Capturar la última zona"
        case .cuentagotas: "Cuentagotas (copiar un color)"
        case .pinear: "Capturar y pinear"
        case .pinearEnVivo: "Pin en vivo"
        case .pinearPortapapeles: "Pinear el portapapeles"
        case .anotar: "Anotar la pantalla"
        case .anotarCongelada: "Anotar la pantalla congelada"
        case .pinearSeleccion: "Pinear lo elegido en el Finder"
        case .capturarConRetardo: "Capturar con retardo"
        case .silenciarAtajos: "Silenciar los atajos"
        case .alternarPasoDeClics: "Pines: dejar pasar el clic"
        case .alternarPines: "Mostrar u ocultar los pines"
        case .restaurarUltimoPin: "Restaurar el último pin"
        case .cerrarTodosLosPines: "Cerrar todos los pines"
        case .copiarTexto: "Copiar el texto de una zona (OCR)"
        case .ventanaEncima: "Ventana encima (pin en vivo de la ventana)"
        case .abrirChat: "Abrir Proyectos"
        case .abrirAjustes: "Abrir Ajustes"
        case .recibirDelMovil: "Recibir del móvil"
        case .salir: "Salir de PixPin"
        case .sincronizar: "Sincronizar"
        case .buscar: "Buscar en PixPin"
        case .grabarPantalla: "Grabar la pantalla"
        }
    }

    /// El atajo con el que nace (`nil`: sin atajo).
    public var deFabrica: AtajoGlobal.Combinacion? {
        switch self {
        case .capturarRegion: .capturar
        case .alternarPines: .alternarPines
        case .grabarPantalla: .grabar
        default: nil
        }
    }

    /// Los grupos de la seccion «Atajos».
    public enum Grupo: String, CaseIterable, Sendable {
        case capturar = "Capturar"
        case pines = "Pines"
        case ventanas = "Ventanas y app"
    }

    public var grupo: Grupo {
        switch self {
        case .capturarRegion, .capturarYCopiar, .capturarConScroll, .capturarYAnotar, .grabarGif,
             .capturarUltimaRegion, .cuentagotas, .anotar, .anotarCongelada, .capturarConRetardo,
             .copiarTexto, .grabarPantalla:
            .capturar
        case .pinear, .pinearEnVivo, .pinearPortapapeles, .pinearSeleccion, .alternarPasoDeClics,
             .alternarPines, .restaurarUltimoPin, .cerrarTodosLosPines, .ventanaEncima:
            .pines
        case .silenciarAtajos, .abrirChat, .abrirAjustes, .recibirDelMovil, .salir, .sincronizar, .buscar:
            .ventanas
        }
    }
}

public extension AtajoGlobal.Combinacion {
    /// Ctrl+2: mostrar u ocultar los pines (el de Windows, tal cual).
    static let alternarPines = AtajoGlobal.Combinacion(tecla: UInt32(kVK_ANSI_2), modificadores: UInt32(controlKey))
}

// MARK: - El texto de un atajo («Ctrl+Alt+X»)

public extension AtajoGlobal.Combinacion {
    /// Como se guarda, en el formato de Windows: `Ctrl+Alt+Shift+Cmd+X`.
    var texto: String {
        var partes: [String] = []
        if modificadores & UInt32(controlKey) != 0 { partes.append("Ctrl") }
        if modificadores & UInt32(optionKey) != 0 { partes.append("Alt") }
        if modificadores & UInt32(shiftKey) != 0 { partes.append("Shift") }
        if modificadores & UInt32(cmdKey) != 0 { partes.append("Cmd") }
        partes.append(AtajoGlobal.Combinacion.textoDeTecla(tecla) ?? "#\(tecla)")
        return partes.joined(separator: "+")
    }

    /// Lee «Ctrl+Alt+X» (sin distinguir mayusculas; acepta Option, Opt,
    /// Control, Command, Win, Mayus). `nil` si no es un atajo valido.
    init?(texto: String) {
        let partes = texto.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard partes.count >= 2, let ultima = partes.last, !ultima.isEmpty,
              let tecla = AtajoGlobal.Combinacion.teclaDeTexto(ultima) else { return nil }
        var mods: UInt32 = 0
        for p in partes.dropLast() {
            let m: Int
            switch p.lowercased() {
            case "ctrl", "control", "⌃": m = controlKey
            case "alt", "option", "opt", "⌥": m = optionKey
            case "shift", "mayus", "mayús", "⇧": m = shiftKey
            case "cmd", "command", "win", "super", "⌘": m = cmdKey
            default: return nil
            }
            // Un modificador repetido es un error de escritura, como en Windows.
            guard mods & UInt32(m) == 0 else { return nil }
            mods |= UInt32(m)
        }
        let c = AtajoGlobal.Combinacion(tecla: tecla, modificadores: mods)
        guard AtajoGlobal.Combinacion.teclaValida(tecla), c.tieneModificadorFuerte else { return nil }
        self = c
    }

    /// Un atajo global necesita Control, Option o Comando: una letra sola
    /// (o con Mayusculas) se comeria lo que el usuario escribe en otras apps.
    var tieneModificadorFuerte: Bool {
        modificadores & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    /// Las teclas que valen como final de un atajo global: letras, cifras y
    /// F1-F20 (las de Windows). Intro, Esc, flechas o Espacio no: se las
    /// quitariamos a todas las apps.
    static func teclaValida(_ codigo: UInt32) -> Bool {
        textoDeTecla(codigo) != nil
    }

    static func textoDeTecla(_ codigo: UInt32) -> String? {
        letrasYCifras[Int(codigo)] ?? funciones.firstIndex(of: Int(codigo)).map { "F\($0 + 1)" }
    }

    static func teclaDeTexto(_ t: String) -> UInt32? {
        let m = t.uppercased()
        if let (codigo, _) = letrasYCifras.first(where: { $0.value == m }) { return UInt32(codigo) }
        if m.hasPrefix("F"), let n = Int(m.dropFirst()), n >= 1, n <= funciones.count {
            return UInt32(funciones[n - 1])
        }
        return nil
    }

    private static let letrasYCifras: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    private static let funciones = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                    kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                                    kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// Los modificadores de Carbon a partir de los de una pulsacion.
    static func modificadores(de flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return UInt32(m)
    }

    /// Como lo ensena el Mac: `⌃⌥X`.
    var descripcion: String {
        var s = ""
        if modificadores & UInt32(controlKey) != 0 { s += "⌃" }
        if modificadores & UInt32(optionKey) != 0 { s += "⌥" }
        if modificadores & UInt32(shiftKey) != 0 { s += "⇧" }
        if modificadores & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (AtajoGlobal.Combinacion.textoDeTecla(tecla) ?? "#\(tecla)")
    }
}

// MARK: - Choques con macOS

/// Por que un atajo no conviene: lo tiene macOS (no se deja) o puede pisar
/// algo (se deja, pero se avisa).
public enum ChoqueAtajo: Equatable, Sendable {
    /// Es del sistema o de todas las apps: no se acepta.
    case sistema(String)
    /// Puede pisar algo del sistema: se acepta con un aviso.
    case aviso(String)

    public var texto: String {
        switch self {
        case let .sistema(t), let .aviso(t): t
        }
    }

    public var bloquea: Bool {
        if case .sistema = self { return true }
        return false
    }

    /// Lo que se sabe de `c` frente a los atajos de macOS (`nil`: libre).
    public static func de(_ c: AtajoGlobal.Combinacion) -> ChoqueAtajo? {
        let ctrl = c.modificadores & UInt32(controlKey) != 0
        let alt = c.modificadores & UInt32(optionKey) != 0
        let shift = c.modificadores & UInt32(shiftKey) != 0
        let cmd = c.modificadores & UInt32(cmdKey) != 0
        let t = Int(c.tecla)
        guard c.tieneModificadorFuerte else {
            return .sistema("Usa Control, Option o Comando con la tecla.")
        }
        // Las capturas de macOS: ⇧⌘3, ⇧⌘4, ⇧⌘5 y ⇧⌘6 (con ⌃ copian).
        if cmd, shift, !alt, [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6].contains(t) {
            return .sistema("\(c.descripcion) es de las capturas de macOS.")
        }
        // ⌘ solo (o con ⇧) y una letra o cifra: es de cada app (⌘C, ⌘Q, ⌘H,
        // ⌘M, ⇧⌘N...). Como atajo global se lo quitariamos a todas.
        if cmd, !ctrl, !alt {
            return .sistema("\(c.descripcion) lo usan las apps (⌘ con una tecla): elige otro con ⌃ u ⌥.")
        }
        // ⌥⌘H oculta las demas, ⌥⌘M minimiza todas, ⌥⌘D el Dock.
        if cmd, alt, !ctrl, !shift, [kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_D].contains(t) {
            return .sistema("\(c.descripcion) es de macOS (ocultar, minimizar o el Dock).")
        }
        // ⌃⌘Q bloquea la pantalla y ⌃⌘F es la pantalla completa.
        if ctrl, cmd, !alt, !shift, [kVK_ANSI_Q, kVK_ANSI_F].contains(t) {
            return .sistema("\(c.descripcion) es de macOS (bloquear o pantalla completa).")
        }
        // ⌃1…⌃9: los escritorios de Mission Control (si se encienden).
        if ctrl, !alt, !cmd, !shift,
           [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
            kVK_ANSI_8, kVK_ANSI_9].contains(t) {
            return .aviso("\(c.descripcion) es «ir al Escritorio \(AtajoGlobal.Combinacion.textoDeTecla(c.tecla) ?? "")» si está encendido en Ajustes del Sistema.")
        }
        // ⌃F1…⌃F8: moverse con el teclado (menu, Dock, ventanas).
        if ctrl, !alt, !cmd, [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8].contains(t) {
            return .aviso("\(c.descripcion) es de «Teclado → Navegación» de macOS.")
        }
        // ⌃⌘D: buscar en el diccionario.
        if ctrl, cmd, !alt, !shift, t == kVK_ANSI_D {
            return .aviso("\(c.descripcion) busca en el Diccionario.")
        }
        return nil
    }
}

// MARK: - Los atajos de todos los comandos

/// Que atajo tiene cada comando: los de fabrica y, encima, lo que cambio el
/// usuario (como `Enlaces` de Windows).
public struct EnlacesAtajos: Equatable, Sendable {
    /// Lo cambiado: `nil` = sin atajo; lo que no esta = el de fabrica.
    public private(set) var cambiados: [ComandoAtajo: AtajoGlobal.Combinacion?] = [:]

    public init() {}

    public func atajo(de c: ComandoAtajo) -> AtajoGlobal.Combinacion? {
        if let cambiado = cambiados[c] { return cambiado }
        return c.deFabrica
    }

    public mutating func poner(_ c: ComandoAtajo, _ atajo: AtajoGlobal.Combinacion?) {
        if atajo == c.deFabrica { cambiados[c] = nil } else { cambiados[c] = .some(atajo) }
    }

    public mutating func restablecer(_ c: ComandoAtajo) {
        cambiados[c] = nil
    }

    /// El comando que ya tiene `atajo` (sin contar `salvo`).
    public func quien(tiene atajo: AtajoGlobal.Combinacion, salvo: ComandoAtajo? = nil) -> ComandoAtajo? {
        ComandoAtajo.allCases.first { $0 != salvo && self.atajo(de: $0) == atajo }
    }

    /// Dos comandos con el mismo atajo (el segundo nunca se dispararia).
    public func choque() -> (ComandoAtajo, ComandoAtajo)? {
        let todos = ComandoAtajo.allCases
        for (i, a) in todos.enumerated() {
            guard let atajoA = atajo(de: a) else { continue }
            if let b = todos.dropFirst(i + 1).first(where: { atajo(de: $0) == atajoA }) { return (a, b) }
        }
        return nil
    }

    /// Lee la tabla guardada (nombre → «Ctrl+Alt+X», vacio = sin atajo).
    /// Devuelve lo que no entiende, para decirlo y no tumbar nada.
    @discardableResult
    public mutating func aplicar(tabla: [String: String]) -> [String] {
        var desconocidos: [String] = []
        for (nombre, texto) in tabla.sorted(by: { $0.key < $1.key }) {
            guard let c = ComandoAtajo.desde(nombre: nombre) else {
                desconocidos.append(nombre)
                continue
            }
            if texto.trimmingCharacters(in: .whitespaces).isEmpty {
                poner(c, nil)
            } else if let a = AtajoGlobal.Combinacion(texto: texto) {
                poner(c, a)
            } else {
                desconocidos.append("\(nombre) = \(texto)")
            }
        }
        return desconocidos
    }

    /// La tabla para guardar: solo lo cambiado (vacio = sin atajo).
    public var tabla: [String: String] {
        var t: [String: String] = [:]
        for (c, a) in cambiados { t[c.nombre] = a?.texto ?? "" }
        return t
    }
}

// MARK: - Regiones guardadas

/// Una zona de la pantalla con nombre y su atajo (las `[[regiones]]` de
/// Windows): captura ese trozo sin abrir la captura. Las medidas son puntos
/// globales con el origen arriba a la izquierda de la pantalla principal
/// (las de Core Graphics), como los pixeles de escritorio de Windows.
public struct RegionGuardada: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var nombre: String
    public var x: Int
    public var y: Int
    public var ancho: Int
    public var alto: Int
    /// «Ctrl+Alt+1», o `nil`/vacio sin atajo.
    public var atajo: String?

    enum CodingKeys: String, CodingKey { case nombre, x, y, ancho, alto, atajo }

    public init(nombre: String, x: Int, y: Int, ancho: Int, alto: Int, atajo: String? = nil) {
        self.nombre = nombre
        self.x = x
        self.y = y
        self.ancho = ancho
        self.alto = alto
        self.atajo = atajo
    }

    /// Si se puede capturar (una de lado cero daria una imagen vacia).
    public var esUtil: Bool { ancho > 0 && alto > 0 }

    public var combinacion: AtajoGlobal.Combinacion? {
        atajo.flatMap { AtajoGlobal.Combinacion(texto: $0) }
    }

    /// El rectangulo en coordenadas de Core Graphics.
    public var rectCG: CGRect { CGRect(x: x, y: y, width: ancho, height: alto) }

    /// El rectangulo en coordenadas de AppKit (origen abajo a la izquierda).
    public func rectAppKit(altoPantallaPrincipal alto: CGFloat) -> CGRect {
        GeometriaCaptura.desdeCoordenadasCG(rectCG, altoPantallaPrincipal: alto)
    }

    /// Una region a partir de una zona en coordenadas de AppKit.
    public static func desde(appKit r: CGRect, altoPantallaPrincipal alto: CGFloat, nombre: String) -> RegionGuardada {
        let cg = GeometriaCaptura.desdeCoordenadasCG(r, altoPantallaPrincipal: alto)
        return RegionGuardada(nombre: nombre, x: Int(cg.minX.rounded()), y: Int(cg.minY.rounded()),
                              ancho: Int(cg.width.rounded()), alto: Int(cg.height.rounded()))
    }
}

// MARK: - Programas ignorados

public enum ProgramasIgnorados {
    /// Si la app de delante esta en la lista (por nombre, por el del
    /// paquete sin `.app` o por su identificador; sin distinguir
    /// mayusculas). Como el `ignorar_programas` de Windows con sus `.exe`.
    public static func estaEnLaLista(nombre: String?, paquete: String?, identificador: String?,
                                     lista: [String]) -> Bool {
        func base(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespaces).lowercased()
            for fin in [".app", ".exe"] where t.hasSuffix(fin) { t.removeLast(fin.count) }
            return t
        }
        let mios = [nombre, paquete, identificador].compactMap { $0 }.map(base).filter { !$0.isEmpty }
        return lista.contains { mios.contains(base($0)) }
    }
}
