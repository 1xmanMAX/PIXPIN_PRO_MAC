// **Las filas de Ajustes**, las de `ventana_ajustes.rs` de Windows
// (`filas_de_seccion`): cada seccion con sus grupos y cada opcion con su
// explicacion debajo y su control. Con los mismos textos y rangos, para que
// los dos sistemas digan lo mismo del mismo `pixpinmax.toml`.
//
// Son datos y no vistas: asi el buscador busca en todas, «Restablecer
// <seccion>» recorre las suyas y las pruebas las comprueban sin pintar nada.
// Cada fila del TOML sabe si esta como de fabrica (`cambiada`, el punto
// azul) y volver a ella (`restablecer`).
//
// Lo que Windows tiene y aqui no sale: «Pinear» (palabras magicas), «Lienzo»
// (iman, suavizado y herramientas: los lleva el agente del lienzo), «Apps»
// (el «Abrir con» de macOS va en el Info.plist) y «Avanzado» de Windows
// (rendimiento y filtro del lapiz de Direct2D, sin sentido en un Mac).

import AppKit
import PixPinCore
import SwiftUI

/// Las secciones de la columna, en el orden de Windows.
public enum SeccionAjustes: String, CaseIterable, Identifiable, Sendable {
    case general, captura, voz, asistente, atajos, sincro, apariencia, avanzado

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .general: Lengua.t("ajustes2-sec-general")
        case .captura: Lengua.t("ajustes2-sec-captura")
        case .voz: Lengua.t("ajustes2-sec-voz")
        case .asistente: Lengua.t("ajustes2-sec-asistente")
        case .atajos: Lengua.t("ajustes2-sec-atajos")
        case .sincro: Lengua.t("ajustes2-sec-sincro")
        case .apariencia: Lengua.t("ajustes2-sec-apariencia")
        case .avanzado: Lengua.t("ajustes2-sec-avanzado")
        }
    }

    public var subtitulo: String {
        switch self {
        case .general: Lengua.t("ajustes2-sec-general-sub")
        case .captura: Lengua.t("ajustes2-sec-captura-sub")
        case .voz: Lengua.t("ajustes2-sec-voz-sub")
        case .asistente: Lengua.t("ajustes2-sec-asistente-sub")
        case .atajos: "Pulsa «Cambiar» y luego la combinación. ⌫ la deja sin atajo; Esc cancela."
        case .sincro: "Cómo se encuentra este Mac con el móvil y los demás equipos."
        case .apariencia: "El aspecto de PinDesk."
        case .avanzado: "El archivo de ajustes y la carpeta de datos."
        }
    }

    public var icono: String {
        switch self {
        case .general: "gearshape"
        case .captura: "crop"
        case .voz: "mic"
        case .asistente: "sparkles"
        case .atajos: "keyboard"
        case .sincro: "arrow.triangle.2.circlepath"
        case .apariencia: "paintpalette"
        case .avanzado: "slider.horizontal.3"
        }
    }
}

/// El control de la derecha de una fila.
public enum ControlAjuste {
    case interruptor(get: @MainActor (ModeloAjustes) -> Bool, set: @MainActor (ModeloAjustes, Bool) -> Void)
    /// Botones de opcion (el segmentado de Windows).
    case opcion([String], get: @MainActor (ModeloAjustes) -> Int, set: @MainActor (ModeloAjustes, Int) -> Void)
    /// − valor +, con su texto.
    case numero(ClosedRange<Int>, paso: Int, texto: (Int) -> String,
                get: @MainActor (ModeloAjustes) -> Int, set: @MainActor (ModeloAjustes, Int) -> Void)
    case boton(String, @MainActor (ModeloAjustes) -> Void)
    /// Algo propio (la clave de la nube, las secciones de otros).
    case vista(@MainActor (ModeloAjustes) -> AnyView)
    case nada
}

/// Una fila: titulo, explicacion y control.
public struct FilaAjuste: Identifiable {
    public let id: String
    public let seccion: SeccionAjustes
    public let grupo: String
    public let titulo: String
    public let ayuda: String
    public let control: ControlAjuste
    /// Si no esta como de fabrica (el punto azul).
    public var cambiada: @MainActor (ModeloAjustes) -> Bool = { _ in false }
    /// La vuelve a fabrica dentro de un cambio del TOML (`nil`: no se puede).
    public var restablecer: ((inout AjustesMac, AjustesMac) -> Void)?
    /// Lo mismo para lo que no es del TOML de `valores` (tema, PDF).
    public var restablecerOtro: (@MainActor (ModeloAjustes) -> Void)?

    public var restablecible: Bool { restablecer != nil || restablecerOtro != nil }
}

/// Los proveedores de la nube (`Proveedor::TODOS` de `pixpin-ia`).
public enum ProveedorNube: String, CaseIterable, Sendable {
    case claude, deepseek

    public var nombre: String {
        switch self {
        case .claude: "Claude"
        case .deepseek: "DeepSeek"
        }
    }

    /// Donde se saca la clave.
    public var consola: String {
        switch self {
        case .claude: "console.anthropic.com"
        case .deepseek: "platform.deepseek.com"
        }
    }
}

@MainActor
public enum FilasAjustes {
    /// Una fila de un valor del TOML: lee, escribe, sabe si cambio y vuelve.
    static func toml<V: Equatable>(_ s: SeccionAjustes, _ grupo: String, _ id: String,
                                   _ titulo: String, _ ayuda: String,
                                   _ kp: WritableKeyPath<AjustesMac, V>,
                                   control: (_ get: @escaping @MainActor (ModeloAjustes) -> V,
                                             _ set: @escaping @MainActor (ModeloAjustes, V) -> Void) -> ControlAjuste) -> FilaAjuste {
        let get: @MainActor (ModeloAjustes) -> V = { $0.valores[keyPath: kp] }
        let set: @MainActor (ModeloAjustes, V) -> Void = { m, v in m.cambiar { $0[keyPath: kp] = v } }
        var f = FilaAjuste(id: id, seccion: s, grupo: grupo, titulo: titulo, ayuda: ayuda, control: control(get, set))
        f.cambiada = { $0.valores[keyPath: kp] != $0.fabrica[keyPath: kp] }
        f.restablecer = { a, fabrica in a[keyPath: kp] = fabrica[keyPath: kp] }
        return f
    }

    static func interruptor(_ s: SeccionAjustes, _ grupo: String, _ id: String, _ titulo: String,
                            _ ayuda: String, _ kp: WritableKeyPath<AjustesMac, Bool>) -> FilaAjuste {
        toml(s, grupo, id, titulo, ayuda, kp) { get, set in .interruptor(get: get, set: set) }
    }

    /// Opciones con su valor en el TOML; lo que no este en la lista cae en la
    /// primera (como `unwrap_or(0)` de Windows).
    static func opcion<V: Equatable>(_ s: SeccionAjustes, _ grupo: String, _ id: String, _ titulo: String,
                                     _ ayuda: String, _ kp: WritableKeyPath<AjustesMac, V>,
                                     _ opciones: [(String, V)]) -> FilaAjuste {
        toml(s, grupo, id, titulo, ayuda, kp) { get, set in
            .opcion(opciones.map(\.0),
                    get: { m in opciones.firstIndex { $0.1 == get(m) } ?? 0 },
                    set: { m, i in set(m, opciones[i].1) })
        }
    }

    static func numero(_ s: SeccionAjustes, _ grupo: String, _ id: String, _ titulo: String, _ ayuda: String,
                       _ kp: WritableKeyPath<AjustesMac, UInt32>, _ rango: ClosedRange<Int>, paso: Int,
                       texto: @escaping (Int) -> String) -> FilaAjuste {
        toml(s, grupo, id, titulo, ayuda, kp) { get, set in
            .numero(rango, paso: paso, texto: texto,
                    get: { Int(get($0)) },
                    set: { m, n in set(m, UInt32(min(max(n, rango.lowerBound), rango.upperBound))) })
        }
    }

    nonisolated static func segundos(_ n: Int) -> String { Lengua.t("ajustes2-u-s", ["n": n]) }
    nonisolated static func pixeles(_ n: Int) -> String {
        Lengua.t("ajustes2-u-px", ["n": n.formatted(.number.grouping(.automatic).locale(Lengua.locale))])
    }
    nonisolated static func dias(_ n: Int) -> String {
        n == 0 ? Lengua.t("ajustes2-nunca") : Lengua.t("ajustes2-u-dias", ["n": n])
    }

    /// Todas las filas de una seccion.
    public static func de(_ s: SeccionAjustes) -> [FilaAjuste] {
        switch s {
        case .general: return general
        case .captura: return captura
        case .voz: return voz
        case .asistente: return asistente
        case .atajos: return atajos
        case .sincro: return sincro
        case .apariencia: return apariencia
        case .avanzado: return avanzado
        }
    }

    public static var todas: [FilaAjuste] { SeccionAjustes.allCases.flatMap(de) }

    // MARK: General

    static var general: [FilaAjuste] {
        let g = Lengua.t("ajustes2-g-arranque")
        var arranque = FilaAjuste(
            id: "arranque", seccion: .general, grupo: g, titulo: "Abrir al iniciar sesión",
            ayuda: "Se queda en la barra de menús sin abrir ninguna ventana. Se puede quitar también en Ajustes del Sistema › General › Elementos de inicio.",
            control: .vista { AnyView(ControlArranque(modelo: $0)) })
        // De fabrica en Windows arranca con el sistema.
        arranque.cambiada = { !$0.abrirAlIniciar }
        return [
            arranque,
            filaIdioma(g),
            filaPdfAligerar(), filaPdfNivel(), filaEscala(),
        ]
    }

    /// **El idioma** (Windows: «−» y «+» recorren los catorce; aqui, un
    /// menu): el del Mac y los catorce, cada uno con su nombre en su lengua,
    /// y el mismo codigo en `idioma` de `pixpinmax.toml` (`sistema`, `es`,
    /// `zh-CN`…), para que sincronice con Windows.
    static func filaIdioma(_ g: String) -> FilaAjuste {
        toml(.general, g, "idioma", Lengua.t("ajustes-idioma"), Lengua.t("ajustes2-ayuda-idioma"), \.idioma) { get, set in
            .vista { m in AnyView(SelectorDeIdioma(modelo: m, get: get, set: set)) }
        }
    }

    /// **La escala de la interfaz** (Windows c687285: sale del menu ⋮ del
    /// chat a Ajustes → General → Ventanas). La del chat de ⌘+ / ⌘− / ⌘0
    /// (`EscalaChat`): es de esta pantalla, no va en el archivo de ajustes,
    /// y se pone al momento en el chat abierto. Los grupos de ventanas, que
    /// van al lado en Windows, aun no estan en el Mac.
    static func filaEscala() -> FilaAjuste {
        var f = FilaAjuste(
            id: "escala", seccion: .general, grupo: Lengua.t("ajustes2-g-ventanas"), titulo: Lengua.t("ajustes2-escala"),
            ayuda: "El tamaño de todo en el chat. Se aplica al momento; en el chat también con ⌘ + «+», «−» y «0».",
            control: .vista { _ in AnyView(ControlEscalaInterfaz()) })
        f.cambiada = { _ in
            EscalaChat.valida(UserDefaults.standard.object(forKey: EscalaChat.clave) as? Int ?? EscalaChat.porDefecto)
                != EscalaChat.porDefecto
        }
        f.restablecerOtro = { _ in UserDefaults.standard.set(EscalaChat.porDefecto, forKey: EscalaChat.clave) }
        return f
    }

    static func filaPdfAligerar() -> FilaAjuste {
        var f = FilaAjuste(
            id: "pdf-aligerar", seccion: .general, grupo: Lengua.t("ajustes2-g-pdf"),
            titulo: "Aligerar los PDF al meterlos en un chat",
            ayuda: Lengua.t("ajustes2-ayuda-pdf-aligerar"),
            control: .interruptor(get: { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).aligerarAlEntrar },
                                  set: { m, v in m.cambiarPdf { $0.aligerarAlEntrar = v } }))
        f.cambiada = { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).aligerarAlEntrar != ModeloAjustes.pdfDeFabrica.aligerarAlEntrar }
        f.restablecerOtro = { m in m.cambiarPdf { $0.aligerarAlEntrar = ModeloAjustes.pdfDeFabrica.aligerarAlEntrar } }
        return f
    }

    static func filaPdfNivel() -> FilaAjuste {
        let niveles: [(String, NivelAligerar)] = [(Lengua.t("ajustes-pdf-nivel-sin-perdida"), .sinPerdida), (Lengua.t("ajustes-pdf-nivel-equilibrado"), .equilibrado),
                                                   (Lengua.t("ajustes-pdf-nivel-pequeno"), .pequeno), (Lengua.t("ajustes-pdf-nivel-extremo"), .extremo)]
        var f = FilaAjuste(
            id: "pdf-nivel", seccion: .general, grupo: Lengua.t("ajustes2-g-pdf"), titulo: Lengua.t("ajustes2-pdf-nivel"),
            ayuda: Lengua.t("ajustes2-ayuda-pdf-nivel"),
            control: .opcion(niveles.map(\.0),
                             get: { m in niveles.firstIndex { $0.1 == (m.pdf ?? ModeloAjustes.pdfDeFabrica).nivel } ?? 1 },
                             set: { m, i in m.cambiarPdf { $0.nivel = niveles[i].1 } }))
        f.cambiada = { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).nivel != ModeloAjustes.pdfDeFabrica.nivel }
        f.restablecerOtro = { m in m.cambiarPdf { $0.nivel = ModeloAjustes.pdfDeFabrica.nivel } }
        return f
    }

    // MARK: Captura

    static var captura: [FilaAjuste] {
        let al = Lengua.t("ajustes2-g-al-capturar"), gif = Lengua.t("ajustes2-g-gif"), guardar = Lengua.t("ajustes2-g-guardar")
        return [
            numero(.captura, al, "retardo", Lengua.t("ajustes2-retardo"),
                   Lengua.t("ajustes2-ayuda-retardo"),
                   \.retardoCapturaS, 0 ... 30, paso: 1, texto: segundos),
            opcion(.captura, al, "color", Lengua.t("ajustes2-color"), Lengua.t("ajustes2-ayuda-color"),
                   \.formatoColor, [("HEX", "hex"), ("RGB", "rgb"), ("HSL", "hsl")]),
            numero(.captura, al, "scroll", Lengua.t("ajustes2-scroll"),
                   Lengua.t("ajustes2-ayuda-scroll"),
                   \.limiteScrollPx, 2_000 ... 100_000, paso: 2_000, texto: pixeles),
            numero(.captura, gif, "gif-ritmo", Lengua.t("ajustes2-gif-ritmo"),
                   Lengua.t("ajustes2-ayuda-gif-ritmo"),
                   \.gifPorSegundo, 5 ... 30, paso: 5, texto: { "\($0)" }),
            numero(.captura, gif, "gif-retardo", Lengua.t("ajustes2-gif-retardo"),
                   Lengua.t("ajustes2-ayuda-gif-retardo"),
                   \.gifRetardoS, 0 ... 10, paso: 1, texto: segundos),
            FilaAjuste(id: "carpeta", seccion: .captura, grupo: guardar, titulo: Lengua.t("ajustes2-carpeta"),
                       ayuda: "La carpeta «capturas» de la carpeta de datos: ahí van las de la galería.",
                       control: .boton(Lengua.t("ajustes2-abrir")) { $0.mostrarCarpetaCapturas() }),
            numero(.captura, guardar, "caducidad", Lengua.t("ajustes2-caducidad"),
                   "Pasado el plazo se van a la Papelera, salvo las conservadas.",
                   \.diasCaducidad, 0 ... 90, paso: 1, texto: dias),
            // La de la pila y los gestos, tal cual (`GestosAlt.swift`): sin
            // titulo, ocupa la tarjeta entera.
            FilaAjuste(id: "pila", seccion: .captura, grupo: "La pila de capturas y los gestos",
                       titulo: "", ayuda: "Apilar las capturas que se copian seguidas; gestos con Option en cualquier sitio.",
                       control: .vista { _ in AnyView(SeccionGestosYPila()) }),
            FilaAjuste(id: "ignorados", seccion: .captura, grupo: "Programas ignorados y regiones",
                       titulo: "Programas ignorados y regiones guardadas",
                       ayuda: "En el Mac están con los atajos: las apps delante de las cuales no actúan y las zonas con su atajo.",
                       control: .boton("Ir a Atajos") { _ in NotificationCenter.default.post(name: .pixpinIrASeccionAjustes, object: SeccionAjustes.atajos.rawValue) }),
        ]
    }

    // MARK: Voz

    static var voz: [FilaAjuste] {
        let g = Lengua.t("ajustes2-g-voz")
        return [
            opcion(.voz, g, "voz-segundo", Lengua.t("ajustes-voz-segundo"),
                   "Whisper entiende también este idioma dentro de la misma nota (en Windows; el dictado del Mac usa uno solo).",
                   \.vozSegundoIdioma, [(Lengua.t("ajustes-voz-ninguno"), ""), (Lengua.t("ajustes-voz-ingles"), "en"), (Lengua.t("ajustes-voz-espanol"), "es"), (Lengua.t("ajustes-voz-portugues"), "pt")]),
            opcion(.voz, g, "voz-modo", Lengua.t("ajustes-voz-modo"), Lengua.t("ajustes2-ayuda-voz-modo"),
                   \.vozModoDeIdiomas, [(Lengua.t("ajustes-voz-modo-cada-uno"), "cada_uno"), (Lengua.t("ajustes-voz-modo-todo-en-uno"), "todo_en_uno")]),
        ]
    }

    // MARK: Asistente

    static var asistente: [FilaAjuste] {
        let g = Lengua.t("ajustes2-g-asistente"), v = Lengua.t("ajustes2-g-asistente-voz"), c = Lengua.t("ajustes2-g-claves")
        var filas = [
            // Sin modelo local desde el 27-oct-2026 (Windows `f86732c`): lo
            // vacio o el `local` de antes salen como Claude. Sin ninguna clave
            // contesta Apple Intelligence, si este Mac la tiene.
            opcion(.asistente, g, "asistente-motor", Lengua.t("ajustes2-asistente-motor"),
                   "Contesta por internet con tu clave: Claude Haiku o DeepSeek. Sin clave, Apple Intelligence (si este Mac la tiene).",
                   \.asistenteMotor, [("Claude", "claude"), ("DeepSeek", "deepseek")]),
            opcion(.asistente, g, "asistente-pensar", Lengua.t("ajustes-asistente-pensar"),
                   "Antes de actuar, el asistente piensa y escribe lo que entendió. Pensar tarda: en automático solo piensa en las tareas complejas o si se lo pides («piénsalo», «paso a paso»).",
                   \.asistentePensar, [(Lengua.t("ajustes-nivel-auto"), nil), (Lengua.t("ajustes2-siempre"), true), (Lengua.t("ajustes2-nunca"), false)]),
            opcion(.asistente, g, "asistente-docs", Lengua.t("ajustes2-asistente-docs-nube"),
                   Lengua.t("ajustes2-ayuda-asistente-docs-nube"),
                   \.asistenteDocumentosALaNube, [(Lengua.t("ajustes2-docs-nube-preguntar"), ""), (Lengua.t("ajustes2-docs-nube-si"), "si"), (Lengua.t("ajustes2-docs-nube-no"), "no")]),
            interruptor(.asistente, v, "asistente-revisar", Lengua.t("ajustes2-asistente-revisar-voz"),
                        Lengua.t("ajustes2-ayuda-asistente-revisar-voz"),
                        \.asistenteRevisarLoDicho),
        ]
        // Lo que quedo bajado del asistente local, mientras siga ahi
        // (`ajustes2-asistente-borrar-locales` de Windows).
        if let b = iaModelosViejosOcupan(carpeta: carpetaDeModelosViejos().path) {
            filas.append(FilaAjuste(
                id: "asistente-borrar-locales", seccion: .asistente, grupo: g, titulo: Lengua.t("ajustes2-asistente-borrar-locales"),
                ayuda: "Lo que se bajó para el asistente local, que ya no se usa: \(ModelosViejos.tamano(b)) en ~/Library/Application Support/PinDesk/modelos.",
                control: .vista { _ in AnyView(FilaModelosViejos()) }))
        }
        for p in ProveedorNube.allCases {
            filas.append(FilaAjuste(
                id: "clave-\(p.rawValue)", seccion: .asistente, grupo: c, titulo: Lengua.t("ajustes2-clave-de", ["proveedor": p.nombre]),
                ayuda: "Se guarda en el Llavero de este Mac, nunca en claro. Sácala en \(p.consola).",
                control: .vista { _ in AnyView(ClaveNube(proveedor: p)) }))
        }
        // Jev de TypeSafe (Windows 24fdfa9): su clave y un interruptor por
        // cada funcion que el Mac tiene (`[jev]`, que no viaja).
        let tj = JevTextos.actuales
        filas.append(FilaAjuste(
            id: "clave-typesafe", seccion: .asistente, grupo: tj.grupo, titulo: tj.clave,
            ayuda: "Se guarda en el Llavero de este Mac, nunca en claro. Sácala en console.typesafe.ai. Sin clave, todo sigue como siempre.",
            control: .vista { _ in AnyView(ClaveJev()) }))
        filas.append(filaJev("reunion", tj.reunion, \.reunion))
        filas.append(filaJev("anki", tj.anki, \.anki))
        filas.append(filaJev("urgencia", tj.urgencia, \.urgencia))
        filas.append(filaJev("modelo", tj.modelo, \.modelo))
        // Las conexiones (Windows, 17-oct): Google Drive para el asistente
        // de la nube, con el ID de cliente del usuario y OAuth.
        for c in iaConexiones() {
            filas.append(FilaAjuste(
                id: "conexion-\(c.id)", seccion: .asistente, grupo: c.nombre, titulo: "Conectar \(c.nombre)",
                ayuda: "El asistente de la nube podrá buscar, leer y bajar tus archivos (y subir, preguntando). Crea el ID de cliente en \(c.consola).",
                control: .vista { _ in AnyView(FilaConexion(id: c.id)) }))
        }
        return filas
    }

    /// Un interruptor de `[jev]`, con su punto azul y su «Restablecer».
    static func filaJev(_ id: String, _ t: TextoInterruptorJev,
                        _ kp: WritableKeyPath<AjustesJev, Bool>) -> FilaAjuste {
        let fabrica = ModeloAjustes.jevDeFabrica
        var f = FilaAjuste(
            id: "jev-\(id)", seccion: .asistente, grupo: JevTextos.actuales.grupo, titulo: t.titulo, ayuda: t.ayuda,
            control: .interruptor(get: { ($0.jev ?? fabrica)[keyPath: kp] },
                                  set: { m, v in m.cambiarJev { $0[keyPath: kp] = v } }))
        f.cambiada = { ($0.jev ?? fabrica)[keyPath: kp] != fabrica[keyPath: kp] }
        f.restablecerOtro = { m in m.cambiarJev { $0[keyPath: kp] = fabrica[keyPath: kp] } }
        return f
    }

    // MARK: Atajos, Sincro, Apariencia, Avanzado

    /// La seccion «Atajos» es `SeccionAtajos` entera; esta fila es para que
    /// el buscador la encuentre.
    static var atajos: [FilaAjuste] {
        [FilaAjuste(id: "atajos", seccion: .atajos, grupo: Lengua.t("ajustes2-g-atajos"), titulo: "Atajos de teclado",
                    ayuda: "Todos los comandos, las regiones guardadas, silenciar los atajos y las apps ignoradas.",
                    control: .boton("Abrir") { _ in NotificationCenter.default.post(name: .pixpinIrASeccionAjustes, object: SeccionAjustes.atajos.rawValue) })]
    }

    static var sincro: [FilaAjuste] {
        let g = Lengua.t("ajustes2-g-sincro")
        return [
            interruptor(.sincro, g, "presencia", Lengua.t("ajustes2-presencia"),
                        "El móvil ve este Mac en cuanto abre Sincronizar. Apagado no se abre ninguna puerta en la red.",
                        \.sincroPresencia),
            interruptor(.sincro, g, "automatica", "Sincronizar sola con los aparatos del grupo",
                        "Al aparecer un aparato del grupo en la Wi‑Fi, 30 s después de un cambio y cada 10 min. Se pausa en modo de bajo consumo.",
                        \.sincroAutomatica),
            interruptor(.sincro, g, "lo-mio", Lengua.t("ajustes2-lo-mio"),
                        "Al sincronizar, lo de este Mac se impone: del otro lado solo llega lo que aquí no existe. Es como empieza el interruptor de «¿Qué sincronizar?».",
                        \.sincroLoMioManda),
        ]
    }

    static var apariencia: [FilaAjuste] {
        var tema = FilaAjuste(
            id: "tema", seccion: .apariencia, grupo: Lengua.t("ajustes2-g-tema"), titulo: "Aspecto",
            ayuda: "Claro, oscuro o como el Mac. Es de este Mac: no va en el archivo de ajustes.",
            control: .opcion(Tema.allCases.map(\.nombre),
                             get: { Tema.allCases.firstIndex(of: $0.tema) ?? 0 },
                             set: { m, i in m.tema = Tema.allCases[i] }))
        tema.cambiada = { $0.tema != .sistema }
        tema.restablecerOtro = { $0.tema = .sistema }
        return [tema]
    }

    static var avanzado: [FilaAjuste] {
        let g = Lengua.t("ajustes2-g-fichero")
        return [
            FilaAjuste(id: "fichero", seccion: .avanzado, grupo: g, titulo: Lengua.t("ajustes2-fichero"),
                       ayuda: "pindesk.toml, el mismo que PinDesk para Windows. Lo que no está aquí sigue ahí, con sus comentarios. Lo cambiado a mano vale al reiniciar.",
                       control: .boton(Lengua.t("ajustes2-abrir-fichero")) { m in Task { await m.abrirFicheroAjustes() } }),
            FilaAjuste(id: "datos", seccion: .avanzado, grupo: g, titulo: "Carpeta de datos",
                       ayuda: "Proyectos, capturas, sincronización y el archivo de ajustes.",
                       control: .boton("Mostrar en Finder") { $0.mostrarCarpetaEnFinder() }),
        ]
    }

    // MARK: Buscar y restablecer

    /// Sin tildes ni mayusculas, para buscar.
    nonisolated static func plano(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    /// Si la fila habla de `busqueda` (todas las palabras, en el titulo, la
    /// explicacion, el grupo o la seccion).
    public static func coincide(_ f: FilaAjuste, _ busqueda: String) -> Bool {
        let texto = plano([f.titulo, f.ayuda, f.grupo, f.seccion.titulo].joined(separator: " "))
        let palabras = plano(busqueda).split(whereSeparator: \.isWhitespace)
        return !palabras.isEmpty && palabras.allSatisfy { texto.contains($0) }
    }

    /// Las que coinciden de TODAS las secciones, en su orden.
    public static func buscar(_ busqueda: String) -> [FilaAjuste] {
        todas.filter { coincide($0, busqueda) }
    }

    /// Si algo de la seccion no esta como de fabrica.
    public static func hayCambios(en s: SeccionAjustes, _ m: ModeloAjustes) -> Bool {
        de(s).contains { $0.restablecible && $0.cambiada(m) }
    }

    /// «Restablecer <seccion>»: lo del TOML en un solo paso de «Deshacer».
    public static func restablecer(_ s: SeccionAjustes, _ m: ModeloAjustes) {
        let filas = de(s)
        let fabrica = m.fabrica
        m.cambiar { a in
            for f in filas { f.restablecer?(&a, fabrica) }
        }
        for f in filas where f.cambiada(m) { f.restablecerOtro?(m) }
    }

    /// Vuelve una fila a fabrica.
    public static func restablecer(_ f: FilaAjuste, _ m: ModeloAjustes) {
        if let r = f.restablecer {
            let fabrica = m.fabrica
            m.cambiar { r(&$0, fabrica) }
        }
        f.restablecerOtro?(m)
    }
}

/// El menu del idioma: «el del Mac» y los catorce, con su nombre en su
/// lengua («日本語», «العربية»), para que lo encuentre quien no lee el actual.
struct SelectorDeIdioma: View {
    @ObservedObject var modelo: ModeloAjustes
    let get: @MainActor (ModeloAjustes) -> String
    let set: @MainActor (ModeloAjustes, String) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { get(modelo) }, set: { set(modelo, $0) })) {
            ForEach(Lengua.opciones, id: \.valor) { o in
                Text(verbatim: o.nombre).tag(o.valor)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

public extension Notification.Name {
    /// Pide a la ventana de Ajustes ir a una seccion (`object`: su `rawValue`).
    static let pixpinIrASeccionAjustes = Notification.Name("pixpinIrASeccionAjustes")
}
