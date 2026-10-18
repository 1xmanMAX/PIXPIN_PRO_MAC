// **Grupos de ventanas guardados** (`grupos_ventanas.rs` de Windows, H9):
// que ventanas de PixPin habia abiertas y donde estaban, con un nombre, para
// volver a abrirlas de una vez. Por cada una, que es (un lienzo de un
// proyecto, un documento en su lector, una nota) y su marco.
//
// - **Que hay abierto** se mira en las ventanas de la app, por su dueño:
//   las de `VentanasDeLienzo` (con `chat\0referencia` de identificador), las
//   de `ControladorLector` (su fichero) y las de `ControladorNotaWeb` (su
//   mensaje o su fichero). Ni el lienzo ni el lector saben nada de grupos.
// - **Abrir un grupo** abre lo que falte por los pedidos de siempre
//   (`HacerPedidos`: `abrir hoja`, `abrir nota`, un fichero) y devuelve cada
//   ventana a su sitio en cuanto aparece (se espera 20 s, como Windows). NO
//   cierra lo demas: seria perderle trabajo al usuario.
// - **Donde**: `grupos-de-ventanas.json` en la raiz de los datos, NO en
//   `proyectos/`: son de este aparato (un marco no significa nada en otra
//   pantalla), como en el movil y en Windows.
// - **Sin atajo**: se ofrece donde Windows, en un menu (el de la barra de
//   menus y el panel).

import AppKit
import Foundation

/// Que es una ventana, con lo justo para volver a abrirla.
public enum ClaseVentana: Equatable, Hashable, Sendable {
    /// Un dibujo de un proyecto (como lo busca `abrir hoja`).
    case lienzo(proyecto: String, referencia: String)
    /// Un documento en su lector.
    case lector(ruta: String)
    /// Una nota: la de un mensaje, o un `.md` suelto.
    case nota(proyecto: String?, mensaje: String?, ruta: String?)
}

extension ClaseVentana: Codable {
    private enum Claves: String, CodingKey { case clase, proyecto, referencia, ruta, mensaje }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Claves.self)
        switch try c.decode(String.self, forKey: .clase) {
        case "lienzo":
            self = try .lienzo(proyecto: c.decode(String.self, forKey: .proyecto),
                               referencia: c.decode(String.self, forKey: .referencia))
        case "lector":
            self = try .lector(ruta: c.decode(String.self, forKey: .ruta))
        case "nota":
            self = try .nota(proyecto: c.decodeIfPresent(String.self, forKey: .proyecto),
                             mensaje: c.decodeIfPresent(String.self, forKey: .mensaje),
                             ruta: c.decodeIfPresent(String.self, forKey: .ruta))
        case let otra:
            throw DecodingError.dataCorruptedError(forKey: .clase, in: c, debugDescription: "clase «\(otra)»")
        }
    }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: Claves.self)
        switch self {
        case let .lienzo(p, r):
            try c.encode("lienzo", forKey: .clase)
            try c.encode(p, forKey: .proyecto)
            try c.encode(r, forKey: .referencia)
        case let .lector(r):
            try c.encode("lector", forKey: .clase)
            try c.encode(r, forKey: .ruta)
        case let .nota(p, m, r):
            try c.encode("nota", forKey: .clase)
            try c.encodeIfPresent(p, forKey: .proyecto)
            try c.encodeIfPresent(m, forKey: .mensaje)
            try c.encodeIfPresent(r, forKey: .ruta)
        }
    }
}

/// Donde estaba una ventana (coordenadas de pantalla de AppKit).
public struct ColocacionVentana: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var ancho: Double
    public var alto: Double
    public var minimizada = false

    public init(x: Double, y: Double, ancho: Double, alto: Double, minimizada: Bool = false) {
        self.x = x
        self.y = y
        self.ancho = ancho
        self.alto = alto
        self.minimizada = minimizada
    }

    init(_ marco: CGRect, minimizada: Bool) {
        self.init(x: marco.minX, y: marco.minY, ancho: marco.width, alto: marco.height, minimizada: minimizada)
    }

    var marco: CGRect { CGRect(x: x, y: y, width: ancho, height: alto) }
}

/// Una ventana del grupo.
public struct VentanaDeGrupo: Codable, Equatable, Sendable {
    public var clase: ClaseVentana
    public var colocacion: ColocacionVentana

    public init(clase: ClaseVentana, colocacion: ColocacionVentana) {
        self.clase = clase
        self.colocacion = colocacion
    }
}

/// Un grupo guardado: lo abierto en un momento, con nombre.
public struct GrupoVentanas: Codable, Equatable, Sendable {
    public var id: String
    public var nombre: String
    public var ventanas: [VentanaDeGrupo]
    /// Milisegundos desde 1970.
    public var guardado: Int64
}

// MARK: - Lo puro

public enum ReglasGruposVentanas {
    /// Cuantos se guardan; pasados estos, el mas viejo se va.
    public static let tope = 12
    public static let sinNombre = "Grupo"

    /// Guarda `ventanas` como grupo: uno con el mismo nombre (sin mirar
    /// mayusculas) se sustituye y el nuevo va primero. Un nombre en blanco
    /// se llama «Grupo N». Es `con_grupo` de Windows tal cual.
    public static func conGrupo(_ grupos: [GrupoVentanas], nombre: String, ventanas: [VentanaDeGrupo],
                                ahora: Int64) -> [GrupoVentanas] {
        var limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.isEmpty { limpio = "\(sinNombre) \(grupos.count + 1)" }
        let nuevo = GrupoVentanas(id: "g-\(ahora)", nombre: limpio, ventanas: sinRepetir(ventanas), guardado: ahora)
        let resto = grupos.filter { $0.nombre.lowercased() != limpio.lowercased() }
        return Array(([nuevo] + resto).prefix(tope))
    }

    /// La misma cosa abierta dos veces se guarda una.
    static func sinRepetir(_ ventanas: [VentanaDeGrupo]) -> [VentanaDeGrupo] {
        var v: [VentanaDeGrupo] = []
        for w in ventanas where !v.contains(where: { $0.clase == w.clase }) { v.append(w) }
        return v
    }

    public static func sinGrupo(_ grupos: [GrupoVentanas], id: String) -> [GrupoVentanas] {
        grupos.filter { $0.id != id }
    }

    /// Las entradas del menu: guardar lo abierto (o decir que no hay nada),
    /// abrir cada grupo y borrar cada grupo.
    public static func entradas(abiertas: Int, grupos: [GrupoVentanas]) -> [EntradaGrupos] {
        var v: [EntradaGrupos] = []
        if abiertas == 0 {
            v.append(EntradaGrupos(titulo: "No hay lienzos, documentos ni notas abiertos que guardar", que: .nada))
        } else {
            let t = abiertas == 1 ? "Guardar la ventana abierta como grupo…"
                : "Guardar las \(abiertas) ventanas abiertas como grupo…"
            v.append(EntradaGrupos(titulo: t, que: .guardar))
        }
        for g in grupos {
            v.append(EntradaGrupos(titulo: "Abrir «\(g.nombre)» · \(g.ventanas.count)", que: .abrir(g.id)))
        }
        for g in grupos {
            v.append(EntradaGrupos(titulo: "Borrar «\(g.nombre)»", que: .borrar(g.id)))
        }
        return v
    }

    // MARK: El fichero

    static func fichero(_ raiz: URL) -> URL {
        raiz.appendingPathComponent("grupos-de-ventanas.json")
    }

    public static func leer(_ raiz: URL) -> [GrupoVentanas] {
        guard let datos = try? Data(contentsOf: fichero(raiz)) else { return [] }
        return (try? JSONDecoder().decode([GrupoVentanas].self, from: datos)) ?? []
    }

    /// A un temporal y luego se cambia el nombre: un corte a medias deja los
    /// grupos de antes enteros.
    public static func escribir(_ raiz: URL, _ grupos: [GrupoVentanas]) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try e.encode(grupos).write(to: fichero(raiz), options: .atomic)
    }
}

/// Una entrada del menu de los grupos.
public struct EntradaGrupos: Equatable, Sendable {
    public enum Que: Equatable, Sendable {
        case nada, guardar
        case abrir(String)
        case borrar(String)
    }

    public var titulo: String
    public var que: Que
}

// MARK: - Las ventanas de verdad

@MainActor
public final class GruposVentanas {
    public static let compartidos = GruposVentanas()

    /// La raiz de los datos (la pone la bandeja al arrancar).
    var raiz: URL?

    /// Lo que espera a su ventana para colocarla, con la hora del pedido.
    private var pendientes: [(clase: ClaseVentana, colocacion: ColocacionVentana, desde: Date)] = []
    private var vigia: Timer?
    /// Cuanto se espera a que nazca una ventana del grupo.
    static let espera: TimeInterval = 20

    // MARK: Lo abierto ahora

    /// Que es `w`, si es de las que se guardan.
    static func clase(de w: NSWindow) -> ClaseVentana? {
        if w.delegate === VentanasDeLienzo.compartidas, let id = w.identifier?.rawValue {
            let partes = id.split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
            guard partes.count == 2 else { return nil }
            return .lienzo(proyecto: String(partes[0]), referencia: String(partes[1]))
        }
        if let lector = w.delegate as? ControladorLector {
            return .lector(ruta: lector.url.standardizedFileURL.path)
        }
        if let nota = w.delegate as? ControladorNotaWeb {
            if let chat = nota.chat, let m = nota.mensaje {
                return .nota(proyecto: chat, mensaje: m.id, ruta: nil)
            }
            if let ruta = nota.sesion.fichero() { return .nota(proyecto: nil, mensaje: nil, ruta: ruta) }
        }
        return nil
    }

    /// Lo abierto y que se ve (o esta en el Dock), con su ventana.
    func abiertas() -> [(clase: ClaseVentana, ventana: NSWindow)] {
        NSApp.windows.compactMap { w in
            guard w.isVisible || w.isMiniaturized, let c = Self.clase(de: w) else { return nil }
            return (c, w)
        }
    }

    /// Lo abierto ahora, cada cosa con su sitio.
    public func fotografiar() -> [VentanaDeGrupo] {
        abiertas().map { VentanaDeGrupo(clase: $0.clase, colocacion: ColocacionVentana($0.ventana.frame,
                                                                                      minimizada: $0.ventana.isMiniaturized)) }
    }

    // MARK: Abrir

    /// Abre un grupo: lo que no estaba se abre, y todo vuelve a su sitio.
    /// Devuelve cuantas se abrieron o colocaron.
    @discardableResult
    public func abrir(_ g: GrupoVentanas) -> Int {
        let hay = abiertas()
        var hechas = 0
        for v in g.ventanas {
            if hay.contains(where: { $0.clase == v.clase }) || lanzar(v.clase) {
                pendientes.append((v.clase, v.colocacion, Date()))
                hechas += 1
            }
        }
        vigilar()
        return hechas
    }

    /// Por los pedidos de siempre: lo mismo que pide un enlace `pixpinmax://`.
    private func lanzar(_ clase: ClaseVentana) -> Bool {
        let pedidos = HacerPedidos.compartidos
        switch clase {
        case let .lienzo(proyecto, referencia):
            pedidos.hacer(Pedido("abrir", ["que": .objeto(["tipo": .texto("hoja"), "proyecto": .texto(proyecto),
                                                           "referencia": .texto(referencia)])]))
            return true
        case let .lector(ruta):
            guard FileManager.default.fileExists(atPath: ruta) else { return false }
            return pedidos.abrir(fichero: URL(fileURLWithPath: ruta))
        case let .nota(proyecto, mensaje, ruta):
            if let proyecto, let mensaje {
                pedidos.hacer(Pedido("abrir", ["que": .objeto(["tipo": .texto("nota"), "proyecto": .texto(proyecto),
                                                               "codigo": .texto(mensaje)])]))
                return true
            }
            guard let ruta, FileManager.default.fileExists(atPath: ruta) else { return false }
            return pedidos.abrir(fichero: URL(fileURLWithPath: ruta))
        }
    }

    /// Coloca lo que va apareciendo y se para cuando no queda nada.
    private func vigilar() {
        guard vigia == nil else { return }
        vigia = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { GruposVentanas.compartidos.colocarLoQueHay() }
        }
    }

    private func colocarLoQueHay() {
        let ahora = Date()
        pendientes.removeAll { ahora.timeIntervalSince($0.desde) > Self.espera }
        let hay = abiertas()
        pendientes.removeAll { p in
            guard let w = hay.first(where: { $0.clase == p.clase })?.ventana else { return false }
            Self.colocar(w, p.colocacion)
            return true
        }
        if pendientes.isEmpty {
            vigia?.invalidate()
            vigia = nil
        }
    }

    /// A su sitio, si cae en alguna pantalla de las de ahora (si no, se deja
    /// donde nacio: la pantalla de entonces ya no esta).
    static func colocar(_ w: NSWindow, _ c: ColocacionVentana) {
        let marco = c.marco
        if marco.width >= 50, marco.height >= 50,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(marco) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.setFrame(marco, display: true)
        }
        if c.minimizada { w.miniaturize(nil) }
    }

    // MARK: El menu

    /// El menu de los grupos (para el de la barra de menus y el panel). Se
    /// arma al pedirlo: lo abierto y lo guardado de ahora.
    public func menu() -> NSMenu {
        let menu = NSMenu(title: "Grupos de ventanas")
        menu.autoenablesItems = false
        let grupos = raiz.map(ReglasGruposVentanas.leer) ?? []
        let hay = fotografiar()
        let entradas = ReglasGruposVentanas.entradas(abiertas: hay.count, grupos: grupos)
        var anterior: EntradaGrupos.Que?
        for e in entradas {
            // Una raya entre guardar, abrir y borrar.
            if let a = anterior, Self.tramo(a) != Self.tramo(e.que) { menu.addItem(.separator()) }
            anterior = e.que
            let item = ItemConAccion.nuevo(e.titulo) { [weak self] in self?.hacer(e.que, hay: hay) }
            item.isEnabled = e.que != .nada
            menu.addItem(item)
        }
        return menu
    }

    private static func tramo(_ q: EntradaGrupos.Que) -> Int {
        switch q {
        case .nada, .guardar: 0
        case .abrir: 1
        case .borrar: 2
        }
    }

    private func hacer(_ que: EntradaGrupos.Que, hay: [VentanaDeGrupo]) {
        guard let raiz else { return NSSound.beep() }
        let grupos = ReglasGruposVentanas.leer(raiz)
        switch que {
        case .nada:
            return
        case .guardar:
            // Lo abierto se fotografio al abrir el menu, que es cuando se pidio.
            guard let nombre = pedirNombre(propuesto: "\(ReglasGruposVentanas.sinNombre) \(grupos.count + 1)") else { return }
            let ahora = Int64(Date().timeIntervalSince1970 * 1000)
            // Se relee: mientras se escribia el nombre pudo guardarse otro.
            let nuevos = ReglasGruposVentanas.conGrupo(ReglasGruposVentanas.leer(raiz), nombre: nombre,
                                                       ventanas: hay, ahora: ahora)
            do { try ReglasGruposVentanas.escribir(raiz, nuevos) } catch { NSSound.beep() }
        case let .abrir(id):
            guard let g = grupos.first(where: { $0.id == id }) else { return }
            if abrir(g) < g.ventanas.count {
                CentroAvisos.compartido.avisar(Aviso(id: "pixpin.grupos-ventanas", categoria: .mini, titulo: "PixPin",
                                                     texto: "Alguna ventana del grupo ya no se puede abrir"))
            }
        case let .borrar(id):
            do { try ReglasGruposVentanas.escribir(raiz, ReglasGruposVentanas.sinGrupo(grupos, id: id)) } catch { NSSound.beep() }
        }
    }

    /// El nombre, en una caja con «Guardar» y «Cancelar».
    private func pedirNombre(propuesto: String) -> String? {
        let alerta = NSAlert()
        alerta.messageText = "Nombre del grupo de ventanas"
        alerta.addButton(withTitle: "Guardar")
        alerta.addButton(withTitle: "Cancelar")
        let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        campo.stringValue = propuesto
        alerta.accessoryView = campo
        alerta.window.initialFirstResponder = campo
        NSApp.activate()
        guard alerta.runModal() == .alertFirstButtonReturn else { return nil }
        return campo.stringValue.components(separatedBy: .newlines).first ?? ""
    }
}

// MARK: - Un elemento de menu con su accion

/// Un `NSMenuItem` que hace un cierre (los menus de la bandeja se arman en
/// AppKit, sin selectores sueltos).
final class ItemConAccion: NSMenuItem {
    private var hacer: (@MainActor () -> Void)?

    static func nuevo(_ titulo: String, tecla: String = "", _ hacer: @escaping @MainActor () -> Void) -> ItemConAccion {
        let i = ItemConAccion(title: titulo, action: #selector(pulsado(_:)), keyEquivalent: tecla)
        i.target = i
        i.hacer = hacer
        return i
    }

    @objc private func pulsado(_ sender: Any?) {
        MainActor.assumeIsolated { hacer?() }
    }
}
