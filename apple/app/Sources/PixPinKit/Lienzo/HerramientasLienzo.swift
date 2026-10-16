// **Las herramientas del lienzo y como se agrupan en la barra**, copiadas de
// Windows: el catalogo y los grupos de `pixpin-ui/src/caja_herramientas.rs`
// (`BOTONES_EDITOR`, `GrupoBarra`, `BARRA_AGRUPADA`), la regla del clic y la
// memoria de la ultima usada de `apps/pixpin/src/dibujo/grupos.rs`, y las
// letras de `dibujo/teclas.rs`.
//
// Aqui solo hay datos y reglas, sin vistas: se prueban sin pantalla. La
// barra que los pinta es `BarraHerramientasLienzo.swift`.

import Foundation

/// **Los grupos de la barra** (`GrupoBarra` de Windows, que copia los
/// `GRUPOS_DE_FABRICA` del movil): lo que hace lo mismo, junto. La barra
/// ensena UN boton por grupo —la herramienta del grupo que este puesta, o la
/// ultima que se uso— y las demas salen en un desplegable al pulsarlo.
public enum GrupoHerramientaLienzo: String, CaseIterable {
    /// Elegir de otras formas: el lazo.
    case elegir
    /// Lo que pinta a mano ademas del lapiz: el grafito, el resaltador y el
    /// bote.
    case trazar
    case formas
    case flechas
    /// Lo que arregla una raya ya trazada.
    case arreglar
    /// Lo que nombra cosas del dibujo: el texto, el numerito y el punto.
    case nombrar
    case medir

    public var titulo: String {
        switch self {
        case .elegir: return "Elegir"
        case .trazar: return "Trazar"
        case .formas: return "Formas"
        case .flechas: return "Flechas"
        case .arreglar: return "Arreglar"
        case .nombrar: return "Nombrar"
        case .medir: return "Medir"
        }
    }

    /// Lo que hay dentro, en el orden del desplegable (el de Windows). La
    /// primera es la cara del grupo mientras no se haya usado otra.
    public var miembros: [HerramientaLienzo] {
        HerramientaLienzo.todas.filter { $0.grupo == self }
    }
}

/// Una herramienta de la barra: nombre del motor, titulo, icono y letra.
public struct HerramientaLienzo: Identifiable, Equatable {
    public let id: String
    public let titulo: String
    let icono: IconoLienzo
    /// La tecla que la elige (sin modificadores, fuera de un texto). Las de
    /// Windows y, donde Windows no tiene, la de Excalidraw si no choca.
    public let tecla: Character?
    /// Su grupo; `nil` es que va suelta (la mano, el lapiz y la goma: las de
    /// uso constante).
    public let grupo: GrupoHerramientaLienzo?

    init(_ id: String, _ titulo: String, _ icono: IconoLienzo, tecla: Character? = nil,
         grupo: GrupoHerramientaLienzo? = nil) {
        self.id = id
        self.titulo = titulo
        self.icono = icono
        self.tecla = tecla
        self.grupo = grupo
    }

    public static func == (a: HerramientaLienzo, b: HerramientaLienzo) -> Bool { a.id == b.id }

    /// El catalogo, en el orden de los desplegables de Windows. Las letras
    /// M L R T B A E G P son las de Windows (`tecla_a_herramienta`); S O D X
    /// W N, las de Excalidraw que alli no se usan.
    public static let todas: [HerramientaLienzo] = [
        .init("seleccion", "Seleccionar", .selection, tecla: "m"),
        .init("lazo", "Lazo", .lasso, tecla: "s", grupo: .elegir),
        .init("lapiz", "Lápiz", .freedraw, tecla: "l"),
        .init("grafito", "Grafito", .grafito, tecla: "p", grupo: .trazar),
        .init("resaltador", "Resaltador", .penMode, tecla: "r", grupo: .trazar),
        .init("relleno", "Bote de relleno", .bucketFill, grupo: .trazar),
        .init("rectangulo", "Rectángulo", .rectangle, grupo: .formas),
        .init("elipse", "Elipse", .ellipse, tecla: "o", grupo: .formas),
        .init("rombo", "Rombo", .diamond, tecla: "d", grupo: .formas),
        .init("arco", "Arco", .angle, grupo: .formas),
        .init("flecha", "Flecha", .arrow, grupo: .flechas),
        .init("flecha_libre", "Flecha a pulso", .roundArrow, grupo: .flechas),
        .init("linea", "Línea", .line, grupo: .flechas),
        .init("flecha_codos", "Flecha de codos", .elbowArrow, grupo: .flechas),
        .init("recortar", "Recortar", .cut, tecla: "x", grupo: .arreglar),
        .init("extender", "Extender", .arrowRight, tecla: "w", grupo: .arreglar),
        .init("texto", "Texto", .text, tecla: "t", grupo: .nombrar),
        .init("serie", "Numerito", .abacus, grupo: .nombrar),
        .init("punto", "Punto", .dots, tecla: "n", grupo: .nombrar),
        .init("cota", "Cota", .lineEditor, tecla: "a", grupo: .medir),
        .init("escalar", "Calibrar escala", .resize, tecla: "e", grupo: .medir),
        .init("escala_grafica", "Escala gráfica", .grid, tecla: "g", grupo: .medir),
        .init("borrador", "Goma", .eraser, tecla: "b"),
    ]

    public static func con(id: String) -> HerramientaLienzo? {
        todas.first { $0.id == id }
    }

    /// La que elige la letra `c` (da igual mayuscula o minuscula).
    public static func deTecla(_ c: Character) -> HerramientaLienzo? {
        let c = Character(c.lowercased())
        return todas.first { $0.tecla == c }
    }

    /// Las que trazan a mano: solo con ellas hay gesto de pararse.
    static let aMano: Set<String> = ["lapiz", "resaltador", "grafito"]

    /// Las que no dibujan nada nuevo: con ellas puestas y nada elegido, el
    /// panel de estilo sobra (Excalidraw lo esconde igual).
    static let sinEstilo: Set<String> = ["seleccion", "lazo", "borrador", "escalar", "recortar", "extender"]
}

/// Lo que se ve en la barra: herramientas sueltas, grupos y acciones.
public enum BotonBarraLienzo: Hashable {
    case herramienta(String)
    case grupo(GrupoHerramientaLienzo)
    /// Meter una imagen de un fichero (el `Imagen` de Windows).
    case imagen
    case deshacer
    case rehacer
    /// Cerrar el lienzo (el `Salir` de Windows; se guarda solo).
    case salir

    /// **La barra agrupada** (`BARRA_AGRUPADA` de Windows) con lo que el Mac
    /// sabe hacer: elegir, lo que pinta, las formas, las flechas, lo que
    /// arregla, lo que nombra, lo que mide, la imagen y la goma; y al final
    /// las acciones.
    public static let barra: [BotonBarraLienzo] = [
        .herramienta("seleccion"), .grupo(.elegir),
        .herramienta("lapiz"), .grupo(.trazar), .grupo(.formas), .grupo(.flechas), .grupo(.arreglar),
        .grupo(.nombrar),
        .grupo(.medir), .imagen, .herramienta("borrador"),
        .deshacer, .rehacer, .salir,
    ]

    /// **La seccion** (`caja_herramientas::grupo` de Windows): entre dos
    /// secciones va un separador. Elegir; lo que dibuja; lo que mide, mete o
    /// borra; y las acciones.
    public var seccion: Int {
        switch self {
        case .herramienta("seleccion"), .grupo(.elegir): return 0
        case .herramienta("lapiz"), .grupo(.trazar), .grupo(.formas), .grupo(.flechas), .grupo(.arreglar),
             .grupo(.nombrar): return 1
        case .grupo(.medir), .imagen, .herramienta("borrador"): return 2
        case .deshacer, .rehacer, .salir: return 3
        case .herramienta: return 1
        }
    }

    /// Si entre este y el siguiente va un separador.
    static func corte(tras i: Int) -> Bool {
        i + 1 < barra.count && barra[i].seccion != barra[i + 1].seccion
    }
}

/// **La memoria y el clic de los grupos** (`dibujo/grupos.rs` de Windows).
/// La memoria es una para toda la aplicacion y no una por ventana: es una
/// costumbre de quien dibuja («el rombo es mi forma»). Se pierde al cerrar.
@MainActor
public enum GruposBarraLienzo {
    private static var recordadas: [GrupoHerramientaLienzo: String] = [:]

    /// Para las pruebas: olvidarlo todo.
    static func olvidar() { recordadas = [:] }

    /// **La cara del grupo** con la herramienta `activa` puesta: la puesta si
    /// es del grupo (y pasa a ser la recordada); si no, la ultima usada; si
    /// no, la primera.
    public static func cara(_ g: GrupoHerramientaLienzo, activa: String) -> HerramientaLienzo? {
        let miembros = g.miembros
        if let puesta = miembros.first(where: { $0.id == activa }) {
            recordadas[g] = puesta.id
            return puesta
        }
        if let r = recordadas[g], let h = miembros.first(where: { $0.id == r }) { return h }
        return miembros.first
    }

    /// Lo que hace un clic en el boton de un grupo.
    public struct Clic: Equatable {
        /// La herramienta que hay que coger, si hay que cambiar.
        public let elegir: String?
        /// Que grupo queda desplegado despues.
        public let desplegado: GrupoHerramientaLienzo?
    }

    /// **El clic en un grupo**: coge su cara si no estaba puesta Y ensena las
    /// hermanas en el mismo clic. Pulsar el grupo ya abierto lo cierra, y uno
    /// de una sola herramienta no se abre.
    public static func pulsar(_ g: GrupoHerramientaLienzo, activa: String,
                              desplegado: GrupoHerramientaLienzo?) -> Clic {
        var elegir: String?
        if let c = cara(g, activa: activa), c.id != activa { elegir = c.id }
        let abierto: GrupoHerramientaLienzo? = desplegado == g || g.miembros.count <= 1 ? nil : g
        return Clic(elegir: elegir, desplegado: abierto)
    }
}
