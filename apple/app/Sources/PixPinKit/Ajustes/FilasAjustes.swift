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
        case .general: "General"
        case .captura: "Captura"
        case .voz: "Voz y transcripción"
        case .asistente: "Asistente"
        case .atajos: "Atajos"
        case .sincro: "Sincronizar"
        case .apariencia: "Apariencia"
        case .avanzado: "Avanzado"
        }
    }

    public var subtitulo: String {
        switch self {
        case .general: "Cómo arranca PixPin y qué hace con los PDF del chat."
        case .captura: "Cómo se hace una captura y qué pasa con ella después."
        case .voz: "Pasar a texto las notas de voz con dos idiomas."
        case .asistente: "Quién contesta en el chat «Asistente»: el modelo de este Mac, Claude o DeepSeek."
        case .atajos: "Pulsa «Cambiar» y luego la combinación. ⌫ la deja sin atajo; Esc cancela."
        case .sincro: "Cómo se encuentra este Mac con el móvil y los demás equipos."
        case .apariencia: "El aspecto de PixPin."
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

    nonisolated static func segundos(_ n: Int) -> String { "\(n) s" }
    nonisolated static func pixeles(_ n: Int) -> String {
        "\(n.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))) px"
    }
    nonisolated static func dias(_ n: Int) -> String { n == 0 ? "Nunca" : n == 1 ? "1 día" : "\(n) días" }

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
        let g = "Al arrancar"
        var arranque = FilaAjuste(
            id: "arranque", seccion: .general, grupo: g, titulo: "Abrir al iniciar sesión",
            ayuda: "Se queda en la barra de menús sin abrir ninguna ventana. Se puede quitar también en Ajustes del Sistema › General › Elementos de inicio.",
            control: .vista { AnyView(ControlArranque(modelo: $0)) })
        // De fabrica en Windows arranca con el sistema.
        arranque.cambiada = { !$0.abrirAlIniciar }
        return [
            arranque,
            opcion(.general, g, "idioma", "Idioma", "Vale desde el próximo arranque. Lo comparte con PixPin para Windows.",
                   \.idioma, [("El del Mac", "sistema"), ("Español", "es"), ("English", "en")]),
            filaPdfAligerar(), filaPdfNivel(),
        ]
    }

    static func filaPdfAligerar() -> FilaAjuste {
        var f = FilaAjuste(
            id: "pdf-aligerar", seccion: .general, grupo: "Documentos PDF",
            titulo: "Aligerar los PDF al meterlos en un chat",
            ayuda: "Después de meterlo al chat, en segundo plano.",
            control: .interruptor(get: { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).aligerarAlEntrar },
                                  set: { m, v in m.cambiarPdf { $0.aligerarAlEntrar = v } }))
        f.cambiada = { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).aligerarAlEntrar != ModeloAjustes.pdfDeFabrica.aligerarAlEntrar }
        f.restablecerOtro = { m in m.cambiarPdf { $0.aligerarAlEntrar = ModeloAjustes.pdfDeFabrica.aligerarAlEntrar } }
        return f
    }

    static func filaPdfNivel() -> FilaAjuste {
        let niveles: [(String, NivelAligerar)] = [("Exacto", .sinPerdida), ("Medio", .equilibrado),
                                                   ("Chico", .pequeno), ("Máx.", .extremo)]
        var f = FilaAjuste(
            id: "pdf-nivel", seccion: .general, grupo: "Documentos PDF", titulo: "Cuánto se aligera",
            ayuda: "Al entrar solo se usan Exacto y Medio; Chico y Máx. quedan para «Aligerar el PDF» a mano.",
            control: .opcion(niveles.map(\.0),
                             get: { m in niveles.firstIndex { $0.1 == (m.pdf ?? ModeloAjustes.pdfDeFabrica).nivel } ?? 1 },
                             set: { m, i in m.cambiarPdf { $0.nivel = niveles[i].1 } }))
        f.cambiada = { ($0.pdf ?? ModeloAjustes.pdfDeFabrica).nivel != ModeloAjustes.pdfDeFabrica.nivel }
        f.restablecerOtro = { m in m.cambiarPdf { $0.nivel = ModeloAjustes.pdfDeFabrica.nivel } }
        return f
    }

    // MARK: Captura

    static var captura: [FilaAjuste] {
        let al = "Al capturar", gif = "Grabar GIF", guardar = "Guardar y limpiar"
        return [
            numero(.captura, al, "retardo", "Captura con retardo",
                   "Cuenta atrás para abrir un menú o un tooltip antes de capturar.",
                   \.retardoCapturaS, 0 ... 30, paso: 1, texto: segundos),
            opcion(.captura, al, "color", "Formato del color", "Cómo se copia el color con el cuentagotas.",
                   \.formatoColor, [("HEX", "hex"), ("RGB", "rgb"), ("HSL", "hsl")]),
            numero(.captura, al, "scroll", "Alto máximo con scroll",
                   "Tope de la captura larga, para que una página infinita no agote la memoria.",
                   \.limiteScrollPx, 2_000 ... 100_000, paso: 2_000, texto: pixeles),
            numero(.captura, gif, "gif-ritmo", "Fotogramas por segundo",
                   "Menos = archivo más ligero. Para tutoriales basta con 10 o 15.",
                   \.gifPorSegundo, 5 ... 30, paso: 5, texto: { "\($0)" }),
            numero(.captura, gif, "gif-retardo", "Cortesía antes de grabar",
                   "Segundos entre pulsar «Grabar» y el primer fotograma.",
                   \.gifRetardoS, 0 ... 10, paso: 1, texto: segundos),
            FilaAjuste(id: "carpeta", seccion: .captura, grupo: guardar, titulo: "Carpeta de las capturas",
                       ayuda: "La carpeta «capturas» de la carpeta de datos: ahí van las de la galería.",
                       control: .boton("Abrir") { $0.mostrarCarpetaCapturas() }),
            numero(.captura, guardar, "caducidad", "Días hasta borrar",
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
        let g = "Notas de voz"
        return [
            opcion(.voz, g, "voz-segundo", "Segundo idioma de las notas de voz",
                   "Whisper entiende también este idioma dentro de la misma nota (en Windows; el dictado del Mac usa uno solo).",
                   \.vozSegundoIdioma, [("Ninguno", ""), ("Inglés", "en"), ("Español", "es"), ("Portugués", "pt")]),
            opcion(.voz, g, "voz-modo", "Con dos idiomas", "Qué hacer con lo dicho en el segundo idioma.",
                   \.vozModoDeIdiomas, [("Cada trozo como se dijo", "cada_uno"), ("Todo en el primero", "todo_en_uno")]),
        ]
    }

    // MARK: Asistente

    static var asistente: [FilaAjuste] {
        let g = "Motor del asistente", v = "Voz del asistente", c = "Claves de API"
        var filas = [
            opcion(.asistente, g, "asistente-motor", "Motor", "Local: gratis y sin red. Nube: con tu clave.",
                   \.asistenteMotor, [("Local (este Mac)", ""), ("Claude", "claude"), ("DeepSeek", "deepseek")]),
            opcion(.asistente, g, "asistente-modelo", "Modelo del asistente",
                   "Con motor Local. El 2B dibuja y ve mejor; el 0.8B gasta menos.",
                   \.asistenteModelo, [("Qwen3.5 2B (recomendado)", ""), ("Qwen3.5 0.8B (ligero)", "qwen3.5-0.8b")]),
            opcion(.asistente, g, "asistente-pensar", "Pensar antes de contestar",
                   "Antes de actuar, el asistente piensa y escribe lo que entendió. Pensar tarda: en automático solo piensa en las tareas complejas o si se lo pides («piénsalo», «paso a paso»).",
                   \.asistentePensar, [("Automático", nil), ("Siempre", true), ("Nunca", false)]),
            interruptor(.asistente, g, "asistente-respaldo", "Si la nube falla, seguir con el local",
                        "Sin red, con la clave mal o sin saldo, contesta el modelo local (si está bajado) y te avisa en la respuesta.",
                        \.asistenteRespaldoLocal),
            interruptor(.asistente, g, "asistente-vista", "Mejor vista con fotos (Gemma 4 E2B)",
                        "Opcional: para describir una foto o leer lo que pone usa Gemma 4 E2B, que ve mejor. Se baja aparte desde el chat «Asistente».",
                        \.asistenteMejorVista),
            opcion(.asistente, g, "asistente-docs", "Tus documentos y la nube",
                   "Con Claude o DeepSeek, lo que el asistente encuentre en tus PDF, notas y chats sale por internet para contestarte. Con el modelo local nunca sale del Mac.",
                   \.asistenteDocumentosALaNube, [("Preguntar", ""), ("Permitir", "si"), ("No permitir", "no")]),
            interruptor(.asistente, v, "asistente-revisar", "Ver lo dicho antes de enviarlo",
                        "Con el micrófono del chat «Asistente»: lo que dices queda escrito en la caja para corregirlo y lo envías tú. Apagado, se envía solo.",
                        \.asistenteRevisarLoDicho),
            interruptor(.asistente, v, "asistente-leer", "Leer siempre las respuestas",
                        "Cada respuesta se lee en voz alta al acabar. Sin esto, pulsa el altavoz de la burbuja.",
                        \.asistenteLeerRespuestas),
        ]
        for p in ProveedorNube.allCases {
            filas.append(FilaAjuste(
                id: "clave-\(p.rawValue)", seccion: .asistente, grupo: c, titulo: "Clave de \(p.nombre)",
                ayuda: "Se guarda en el Llavero de este Mac, nunca en claro. Sácala en \(p.consola).",
                control: .vista { _ in AnyView(ClaveNube(proveedor: p)) }))
        }
        return filas
    }

    // MARK: Atajos, Sincro, Apariencia, Avanzado

    /// La seccion «Atajos» es `SeccionAtajos` entera; esta fila es para que
    /// el buscador la encuentre.
    static var atajos: [FilaAjuste] {
        [FilaAjuste(id: "atajos", seccion: .atajos, grupo: "Atajos generales", titulo: "Atajos de teclado",
                    ayuda: "Todos los comandos, las regiones guardadas, silenciar los atajos y las apps ignoradas.",
                    control: .boton("Abrir") { _ in NotificationCenter.default.post(name: .pixpinIrASeccionAjustes, object: SeccionAjustes.atajos.rawValue) })]
    }

    static var sincro: [FilaAjuste] {
        let g = "En la red local"
        return [
            interruptor(.sincro, g, "presencia", "Dejarse encontrar",
                        "El móvil ve este Mac en cuanto abre Sincronizar. Apagado no se abre ninguna puerta en la red.",
                        \.sincroPresencia),
            interruptor(.sincro, g, "automatica", "Sincronizar sola con los aparatos del grupo",
                        "Al aparecer un aparato del grupo en la Wi‑Fi, 30 s después de un cambio y cada 10 min. Se pausa en modo de bajo consumo.",
                        \.sincroAutomatica),
            interruptor(.sincro, g, "lo-mio", "Lo mío manda",
                        "Al sincronizar, lo de este Mac se impone: del otro lado solo llega lo que aquí no existe. Es como empieza el interruptor de «¿Qué sincronizar?».",
                        \.sincroLoMioManda),
        ]
    }

    static var apariencia: [FilaAjuste] {
        var tema = FilaAjuste(
            id: "tema", seccion: .apariencia, grupo: "Tema", titulo: "Aspecto",
            ayuda: "Claro, oscuro o como el Mac. Es de este Mac: no va en el archivo de ajustes.",
            control: .opcion(Tema.allCases.map(\.nombre),
                             get: { Tema.allCases.firstIndex(of: $0.tema) ?? 0 },
                             set: { m, i in m.tema = Tema.allCases[i] }))
        tema.cambiada = { $0.tema != .sistema }
        tema.restablecerOtro = { $0.tema = .sistema }
        return [tema]
    }

    static var avanzado: [FilaAjuste] {
        let g = "El archivo de ajustes"
        return [
            FilaAjuste(id: "fichero", seccion: .avanzado, grupo: g, titulo: "Archivo de ajustes",
                       ayuda: "pixpinmax.toml, el mismo que PixPin para Windows. Lo que no está aquí sigue ahí, con sus comentarios. Lo cambiado a mano vale al reiniciar.",
                       control: .boton("Abrir el archivo") { m in Task { await m.abrirFicheroAjustes() } }),
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

public extension Notification.Name {
    /// Pide a la ventana de Ajustes ir a una seccion (`object`: su `rawValue`).
    static let pixpinIrASeccionAjustes = Notification.Name("pixpinIrASeccionAjustes")
}
