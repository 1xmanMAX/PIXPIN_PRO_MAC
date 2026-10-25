// **Las carpetas de paginas del chat** (`ventana_chat/carpetas.rs` de
// Windows, 26-oct-2026; el usuario: «dentro del chat se puede crear una
// carpeta con nombre, como si fuera un PDF; al abrirla se ven todas sus
// paginas en orden: Dia 1, Dia 2, Dia 3…»).
//
// - **La tarjeta** en el chat: el cuaderno, cuantas paginas lleva y las
//   tres primeras en miniatura, con su numero, y «+N» si hay mas. Un clic
//   la abre.
// - **Su ventana**: arriba el nombre y cuantas lleva, «Nueva página» (la
//   plantilla de la ultima otra vez, vacia, con el titulo siguiente) y
//   «Exportar PDF»; debajo las paginas en orden, con su miniatura, su numero
//   y su titulo. Se abren con un clic, se cambian de sitio arrastrandolas
//   (o con sus flechas, o ⌘← ⌘→), se renombran (lapiz o F2) y se quitan de
//   la carpeta (aspa o ⌫): el lienzo sigue en el chat.
// - **En el chat**: «Carpeta de páginas» en el clip, «Añadir a carpeta…» en
//   el menu de un lienzo, una pagina o una foto (en «Más» en lo demas),
//   «Nueva carpeta con esta página» y «Abrir la carpeta».
//
// Todo se escribe en el cuaderno por el nucleo (`carpetas.rs`, el mismo
// formato que Windows y el movil: un mensaje `MINIAPP` «carpeta» con la
// lista de sus paginas en el texto).

import AppKit
import PixPinCore
import SwiftUI

/// Los textos de las carpetas, los de Windows (`carpeta-*` de `main.ftl`).
enum TextosCarpeta {
    static let nueva = "Carpeta de páginas"
    static let pagina = "Página"
    static func paginas(_ n: Int) -> String { n == 1 ? "1 página" : "\(n) páginas" }
    static let vaciaDetalle = "Vacía"
    static let anadirA = "Añadir a carpeta…"
    static let nuevaCon = "Nueva carpeta con esta página"
    static func anadida(_ carpeta: String, como titulo: String) -> String { "Añadida a «\(carpeta)» como «\(titulo)»" }
    static func yaEstaba(_ carpeta: String) -> String { "Ya está en «\(carpeta)»" }
    static let abrir = "Abrir la carpeta"
    static let nuevaPagina = "Nueva página"
    static let exportarPdf = "Exportar PDF"
    static let exportando = "Exportando el PDF…"
    static let noSeExporto = "No se pudo exportar: no hay ninguna página con algo dentro"
    static let vacia = "Esta carpeta está vacía. Pulsa «Nueva página», o en el chat elige «Añadir a carpeta…» en el menú de un lienzo o de una imagen."
    static let antes = "Antes"
    static let despues = "Después"
    static let renombrar = "Renombrar"
    static let quitar = "Quitar de la carpeta"
    static let noEsta = "Esa carpeta ya no está en el chat"
    static let pista = "Arrastra una página para cambiarla de sitio · F2 cambia su título · ⌫ la quita (el lienzo sigue en el chat)"
    static let escribeTitulo = "Escribe el título y pulsa Intro"
    static let noSePudo = "No se pudo: mira el registro de PixPin"
}

// MARK: - Lo comun

@MainActor
enum CarpetasDelChat {
    /// Cuantas paginas se ven en la tarjeta, una al lado de otra.
    static let enLaTarjeta = 3

    /// Si el mensaje es una carpeta de paginas.
    nonisolated static func esCarpeta(_ m: MensajeChat) -> Bool {
        m.clase == "MINIAPP" && m.miniapp == "carpeta"
    }

    /// Si se ofrece «Añadir a carpeta…» (`carpeta_de_paginas::puede_ir`):
    /// todo lo que puede ser una pagina, menos otra carpeta y lo de sistema.
    nonisolated static func seOfrece(_ m: MensajeChat) -> Bool {
        !esCarpeta(m) && !m.id.isEmpty && !m.id.hasPrefix("auto-")
    }

    /// Un lienzo, una pagina o una foto lo llevan a la vista; lo demas, en
    /// «Más».
    nonisolated static func aLaVista(_ m: MensajeChat) -> Bool {
        ["DIBUJO", "PAGINA", "IMAGEN"].contains(m.clase)
    }

    /// Lo que pone debajo del nombre: cuantas lleva (`fila_de` de Windows).
    nonisolated static func detalle(_ m: MensajeChat) -> String {
        let n = paginasDeCarpeta(texto: m.texto).count
        return n == 0 ? TextosCarpeta.vaciaDetalle : TextosCarpeta.paginas(n)
    }

    /// El icono de una pagina sin miniatura (`icono_de` de Windows).
    nonisolated static func icono(_ clase: String) -> String {
        switch clase {
        case "DIBUJO": "scribble.variable"
        case "PAGINA": "book"
        case "IMAGEN": "photo"
        case "VOZ": "play.fill"
        case "NOTA", "": "square.and.pencil"
        default: "doc.text"
        }
    }

    static func abrir(_ m: MensajeChat, chat: String, almacen: Almacen) {
        VentanasDeCarpeta.compartidas.abrir(id: m.id, chat: chat, titulo: m.nombre, almacen: almacen)
    }

    /// **Abre una pagina**: un lienzo en el lienzo, una pagina del PDF en el
    /// lienzo con su hoja de fondo, una foto en su lienzo; lo demas, en el
    /// chat, en su sitio.
    static func abrirPagina(_ m: MensajeChat, titulo: String, chat: String, almacen: Almacen) {
        switch m.clase {
        case "DIBUJO" where m.referencia?.isEmpty == false:
            VentanasDeLienzo.compartidas.abrir(referencia: m.referencia ?? "", en: chat, titulo: titulo, almacen: almacen)
        case "PAGINA":
            let (nucleo, id) = (almacen.nucleo, m.id)
            Task {
                let (dibujo, hoja) = await Task.detached(priority: .userInitiated) { () -> (String?, HojaDePagina?) in
                    let d = (try? nucleo.estrenarDibujoDePagina(chat: chat, id: id)) ?? nil
                    let h = (try? nucleo.hojaDePagina(chat: chat, id: id)) ?? nil
                    return (d, h)
                }.value
                if let dibujo {
                    let fuente = hoja.flatMap { PaginaLeida(hoja: $0, dibujo: nil).fuente }
                    VentanasDeLienzo.compartidas.abrir(referencia: dibujo, en: chat, titulo: titulo,
                                                       almacen: almacen, fondo: fuente)
                } else if let pdf = hoja?.pdf {
                    AbrirDocumento.abrir(URL(fileURLWithPath: pdf), nucleo: nucleo, titulo: titulo)
                } else {
                    Recordatorios.abrir(chat: chat, mensaje: id, nucleo: nucleo)
                }
            }
        case "IMAGEN":
            anotarFoto(m, chat: chat, almacen: almacen)
        default:
            Recordatorios.abrir(chat: chat, mensaje: m.id, nucleo: almacen.nucleo)
        }
    }

    /// La carpeta con sus paginas, leida fuera del hilo principal.
    static func leer(_ id: String, chat: String, almacen: Almacen) async -> CarpetaDePaginas? {
        let nucleo = almacen.nucleo
        return await Task.detached(priority: .userInitiated) {
            (try? nucleo.carpetaDePaginas(chat: chat, id: id)) ?? nil
        }.value
    }
}

// MARK: - Lo que hace el chat

extension ChatAbierto {
    /// **Una carpeta nueva al final del chat** (el clip, o «Nueva carpeta
    /// con esta página» con `primera` dentro), con el nombre listo para
    /// escribirlo: «Cuaderno» no dice nada.
    func crearCarpeta(primera: MensajeChat?) {
        let (nucleo, chat, almacen) = (self.almacen.nucleo, self.chat, self.almacen)
        let primera = primera?.id
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.crearCarpetaDePaginas(chat: chat, primera: primera) }
            }.value
            switch hecho {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                escritura = .renombrar(m)
            case .failure:
                avisar(TextosCarpeta.noSePudo)
            }
        }
    }

    /// **«Añadir a carpeta…»**: las carpetas del chat (en la que ya esta,
    /// marcada) y una nueva con esta pagina, en un menu donde esta el raton.
    func anadirACarpeta(_ m: MensajeChat) {
        let (nucleo, chat) = (almacen.nucleo, self.chat)
        let id = m.id
        Task {
            let carpetas = await Task.detached(priority: .userInitiated) {
                (try? nucleo.carpetasDelChat(chat: chat, pagina: id)) ?? []
            }.value
            var entradas = carpetas.map { c in
                MenuEmergente.Entrada(titulo: c.nombre, icono: c.laLleva ? "checkmark.square" : "book") { [weak self] in
                    self?.anadir(m, a: c.id)
                }
            }
            entradas.append(MenuEmergente.Entrada(titulo: TextosCarpeta.nuevaCon, icono: "plus") { [weak self] in
                self?.crearCarpeta(primera: m)
            })
            MenuEmergente.mostrar(entradas)
        }
    }

    /// Mete `m` en la carpeta `carpeta`, al final y con el titulo que le
    /// toca, y dice como entro (o que ya estaba).
    func anadir(_ m: MensajeChat, a carpeta: String) {
        let (nucleo, chat, almacen) = (self.almacen.nucleo, self.chat, self.almacen)
        let id = m.id
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<AnadidaACarpeta?, Error> in
                Result { try nucleo.anadirACarpeta(chat: chat, carpeta: carpeta, pagina: id) }
            }.value
            switch hecho {
            case let .success(a?):
                // La tarjeta de la carpeta, al dia sin releer todo el chat.
                almacen.sustituir(a.carpeta, en: chat)
                avisar(a.yaEstaba ? TextosCarpeta.yaEstaba(a.nombre) : TextosCarpeta.anadida(a.nombre, como: a.titulo))
            case .success(nil):
                avisar(TextosCarpeta.noEsta)
            case .failure:
                avisar(TextosCarpeta.noSePudo)
            }
        }
    }
}

// MARK: - La miniatura de una pagina

/// **La miniatura de una pagina**: un lienzo con lo dibujado, una pagina
/// del PDF con lo anotado, una foto. Lo demas (una nota, un archivo), su
/// icono.
struct MiniaturaDePagina: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    /// El lado mayor en pantalla (para pedir las fotos a su tamano).
    var lado: CGFloat
    /// Sube cuando se guarda un lienzo: se vuelve a leer.
    var version = 0
    @State private var dibujo: DibujoDelChat?
    @State private var pagina: PaginaLeida?
    @State private var foto: URL?
    @State private var leida = false
    @State private var fotosListas = 0

    private var pixeles: Int { Int(lado * 2) }

    var body: some View {
        ZStack {
            if let pagina, let fuente = pagina.fuente {
                VistaHojaPagina(fuente: fuente, dibujo: pagina.dibujo, version: version + fotosListas)
            } else if let dibujo {
                let fotos = dibujo.fotos
                let pixeles = self.pixeles
                VistaLienzo(lienzo: dibujo.lienzo, version: version + fotosListas) { id in
                    fotos[id].flatMap { Miniaturas.compartidas.enCache($0, lado: pixeles) }
                }
            } else if let foto {
                MiniaturaVista(url: foto, lado: lado)
            } else if leida {
                Image(systemName: CarpetasDelChat.icono(mensaje.clase))
                    .font(.system(size: max(14, lado * 0.16)))
                    .foregroundStyle(Color(white: 0.45))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        // Los clics y el arrastre son de quien la ensena, no del lienzo.
        .allowsHitTesting(false)
        .task(id: "\(mensaje.id)#\(version)") { await leer() }
    }

    private func leer() async {
        let (nucleo, chat, id) = (almacen.nucleo, self.chat, mensaje.id)
        switch mensaje.clase {
        case "PAGINA":
            let hoja = await Task.detached(priority: .utility) {
                (try? nucleo.hojaDePagina(chat: chat, id: id)) ?? nil
            }.value
            if let hoja {
                var d: DibujoDelChat?
                if let r = hoja.dibujo { d = await almacen.dibujo(r, en: chat) }
                await cargarFotos(d)
                pagina = PaginaLeida(hoja: hoja, dibujo: d)
            }
        case "DIBUJO":
            if let r = mensaje.referencia, !r.isEmpty, let d = await almacen.dibujo(r, en: chat) {
                dibujo = d
                await cargarFotos(d)
            }
        case "IMAGEN":
            if let ruta = mensaje.ruta, !ruta.isEmpty, let u = await almacen.url(deRuta: ruta, en: chat),
               FileManager.default.fileExists(atPath: u.path) {
                foto = u
            }
        default:
            break
        }
        leida = true
    }

    /// Las fotos de dentro, por la cache del chat; al tenerlas se repinta.
    private func cargarFotos(_ d: DibujoDelChat?) async {
        guard let d else { return }
        var alguna = false
        for url in Set(d.fotos.values) {
            if await Miniaturas.compartidas.cargar(url, lado: pixeles) != nil { alguna = true }
        }
        if alguna { fotosListas += 1 }
    }
}

/// El numero de la pagina, en su esquina (`chapa` de Windows).
struct ChapaDeNumero: View {
    let texto: String
    var tam: CGFloat = 11

    var body: some View {
        Text(texto)
            .font(.system(size: tam, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, tam * 0.55)
            .padding(.vertical, tam * 0.2)
            .frame(minWidth: tam * 1.7)
            .background(Color.black.opacity(0.6), in: Capsule())
    }
}

// MARK: - La tarjeta del chat

/// **La tarjeta de una carpeta** (`pintar_ojeada_carpeta` de Windows): sus
/// primeras paginas en fila, como hojas de un cuaderno, y cuantas mas lleva.
/// Vacia, el cuaderno. Un clic la abre.
struct BurbujaCarpeta: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @State private var paginas: [PaginaDeCarpeta] = []
    @State private var recargas = 0
    @Environment(\.escalaChat) private var escala

    private var nombre: String {
        let n = mensaje.nombre.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Cuaderno" : n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 18 * escala))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nombre).lineLimit(2)
                    Text(CarpetasDelChat.detalle(mensaje)).font(.caption).foregroundStyle(.secondary)
                }
            }
            hojas
                .frame(width: ladoDeBurbuja * escala, height: ladoDeBurbuja * 0.62 * escala)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .contentShape(Rectangle())
        .onTapGesture { CarpetasDelChat.abrir(mensaje, chat: chat, almacen: almacen) }
        .help(TextosCarpeta.abrir)
        .onReceive(NotificationCenter.default.publisher(for: .pixpinLienzoGuardado)) { aviso in
            guard let r = aviso.object as? String,
                  paginas.contains(where: { $0.mensaje.referencia == r }) else { return }
            recargas += 1
        }
        .task(id: "\(mensaje.texto)#\(recargas)") {
            paginas = await CarpetasDelChat.leer(mensaje.id, chat: chat, almacen: almacen)?.paginas ?? []
        }
    }

    private var hojas: some View {
        GeometryReader { geo in
            let aire: CGFloat = 8 * escala
            let n = min(paginas.count, CarpetasDelChat.enLaTarjeta)
            let ancho = (geo.size.width - aire * CGFloat(CarpetasDelChat.enLaTarjeta + 1)) / CGFloat(CarpetasDelChat.enLaTarjeta)
            let alto = geo.size.height - 2 * aire
            ZStack {
                Color.white.opacity(0.55)
                if n == 0 {
                    Image(systemName: "book")
                        .font(.system(size: 40 * escala))
                        .foregroundStyle(Color(white: 0.45))
                } else {
                    // Centradas: con una o dos no se quedan a la izquierda.
                    HStack(spacing: aire) {
                        ForEach(Array(paginas.prefix(n).enumerated()), id: \.element.mensaje.id) { k, p in
                            MiniaturaDePagina(mensaje: p.mensaje, chat: chat, almacen: almacen, lado: max(ancho, alto),
                                              version: recargas)
                                .frame(width: ancho, height: alto)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .topLeading) {
                                    ChapaDeNumero(texto: "\(k + 1)", tam: 10 * escala).padding(4 * escala)
                                }
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if paginas.count > n {
                    ChapaDeNumero(texto: "+\(paginas.count - n)", tam: 12 * escala)
                        .padding(.trailing, 14 * escala).padding(.bottom, 14 * escala)
                }
            }
        }
    }
}

// MARK: - La ventana

/// Las ventanas de las carpetas abiertas: una por carpeta.
@MainActor
final class VentanasDeCarpeta: NSObject, NSWindowDelegate {
    static let compartidas = VentanasDeCarpeta()
    private var abiertas: [String: (ventana: NSWindow, modelo: ModeloCarpeta)] = [:]

    /// **Abre la ventana de una carpeta**, o trae delante la que ya estaba.
    func abrir(id: String, chat: String, titulo: String, almacen: Almacen) {
        let clave = chat + "\u{0}" + id
        if let a = abiertas[clave] {
            a.ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let modelo = ModeloCarpeta(id: id, chat: chat, almacen: almacen)
        let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        ventana.title = titulo.isEmpty ? "Cuaderno" : titulo
        ventana.contentViewController = NSHostingController(rootView: VistaCarpeta(modelo: modelo))
        ventana.setContentSize(NSSize(width: 900, height: 700))
        ventana.minSize = NSSize(width: 480, height: 360)
        // Lisa, como en Windows: sin titulo ni semaforo, −, ☐ y ✕ planos.
        VentanaLisa.vestir(ventana)
        ventana.isReleasedWhenClosed = false
        ventana.center()
        VentanaLisa.recordar(ventana, clave: "carpeta")
        ventana.identifier = NSUserInterfaceItemIdentifier(clave)
        ventana.delegate = self
        modelo.ventana = ventana
        abiertas[clave] = (ventana, modelo)
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let v = notification.object as? NSWindow, let clave = v.identifier?.rawValue else { return }
        abiertas[clave] = nil
    }

    /// Al volver a la ventana, se relee: lo que cambio por fuera (un lienzo
    /// guardado, una pagina anadida desde el chat) se ve.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let v = notification.object as? NSWindow, let clave = v.identifier?.rawValue else { return }
        abiertas[clave]?.modelo.recargar()
    }
}

/// **El estado de la ventana de una carpeta.**
@MainActor
final class ModeloCarpeta: ObservableObject {
    let id: String
    let chat: String
    let almacen: Almacen
    weak var ventana: NSWindow?
    @Published private(set) var carpeta: CarpetaDePaginas?
    /// El mensaje de la carpeta ya no esta (se borro en el chat).
    @Published private(set) var perdida = false
    @Published var elegida: String?
    /// La pagina cuyo titulo se esta escribiendo, y lo escrito.
    @Published var renombrando: String?
    @Published var escrito = ""
    @Published private(set) var aviso: String?
    @Published private(set) var exportando = false
    /// Sube cuando se guarda un lienzo de la carpeta: las miniaturas se
    /// vuelven a leer.
    @Published private(set) var version = 0
    private var turnoAviso = 0

    init(id: String, chat: String, almacen: Almacen) {
        self.id = id
        self.chat = chat
        self.almacen = almacen
    }

    var paginas: [PaginaDeCarpeta] { carpeta?.paginas ?? [] }

    func posicion(_ pagina: String?) -> Int? { paginas.firstIndex { $0.mensaje.id == pagina } }

    /// **Lee la carpeta y sus paginas.**
    func recargar() {
        Task {
            let leida = await CarpetasDelChat.leer(id, chat: chat, almacen: almacen)
            carpeta = leida
            perdida = leida == nil
            if let n = leida?.nombre { ventana?.title = n }
            if posicion(elegida) == nil { elegida = paginas.first?.mensaje.id }
        }
    }

    func lienzoGuardado(_ referencia: String) {
        guard paginas.contains(where: { $0.mensaje.referencia == referencia }) else { return }
        version += 1
    }

    func avisar(_ texto: String) {
        aviso = texto
        turnoAviso += 1
        let turno = turnoAviso
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if turno == turnoAviso { aviso = nil }
        }
    }

    /// **Cambia la carpeta en el disco**, la pone al dia en el chat y relee.
    func cambiar(_ cambio: CambioCarpeta) {
        let (nucleo, chat, id, almacen) = (self.almacen.nucleo, self.chat, self.id, self.almacen)
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat?, Error> in
                Result { try nucleo.cambiarCarpeta(chat: chat, carpeta: id, cambio: cambio) }
            }.value
            switch hecho {
            case let .success(m?): almacen.sustituir(m, en: chat)
            case .success(nil): break
            case .failure: avisar(TextosCarpeta.noSePudo)
            }
            recargar()
        }
    }

    /// Lleva la pagina `desde` al sitio `hasta`.
    func mover(_ desde: Int, _ hasta: Int) {
        guard desde != hasta, paginas.indices.contains(desde), paginas.indices.contains(hasta) else { return }
        elegida = paginas[desde].mensaje.id
        cambiar(.mover(desde: UInt32(desde), hasta: UInt32(hasta)))
    }

    func quitar(_ pagina: String) {
        if renombrando == pagina { renombrando = nil }
        cambiar(.quitar(pagina: pagina))
    }

    func empezarARenombrar(_ pagina: String) {
        guard let p = paginas.first(where: { $0.mensaje.id == pagina }) else { return }
        escrito = p.titulo
        renombrando = pagina
        elegida = pagina
    }

    /// Lo escrito se guarda (Intro, o pulsar fuera); Esc lo deja.
    func terminarDeRenombrar(guardar: Bool) {
        guard let pagina = renombrando else { return }
        renombrando = nil
        let titulo = escrito.trimmingCharacters(in: .whitespacesAndNewlines)
        guard guardar, !titulo.isEmpty else { return }
        cambiar(.renombrar(pagina: pagina, titulo: titulo))
    }

    func abrir(_ p: PaginaDeCarpeta) {
        elegida = p.mensaje.id
        CarpetasDelChat.abrirPagina(p.mensaje, titulo: p.titulo, chat: chat, almacen: almacen)
    }

    /// **«Nueva página»**: un lienzo nuevo con la plantilla de la ultima
    /// pagina, vacia, y el titulo siguiente. Se abre enseguida, que es lo
    /// que se quiere: llenarla.
    func nuevaPagina() {
        let (nucleo, chat, id, almacen) = (self.almacen.nucleo, self.chat, self.id, self.almacen)
        Task {
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<PaginaNuevaDeCarpeta, Error> in
                Result { try nucleo.paginaSiguienteDeCarpeta(chat: chat, carpeta: id) }
            }.value
            guard case let .success(n) = hecho else {
                avisar(TextosCarpeta.noSePudo)
                return
            }
            await almacen.alFinal(n.lienzo, en: chat)
            almacen.sustituir(n.carpeta, en: chat)
            elegida = n.lienzo.id
            recargar()
            if let r = n.lienzo.referencia {
                VentanasDeLienzo.compartidas.abrir(referencia: r, en: chat, titulo: n.titulo, almacen: almacen)
            }
        }
    }

    /// **«Exportar PDF»**: una pagina por cada una, con el dialogo de guardar.
    func exportar() {
        guard !exportando, let carpeta else { return }
        exportando = true
        Task {
            let aviso = await PdfDeCarpeta.exportar(carpeta, chat: chat, almacen: almacen, ventana: ventana)
            exportando = false
            if let aviso { avisar(aviso) }
        }
    }
}

/// **La ventana de una carpeta**: la barra, la pista y las paginas en orden.
struct VistaCarpeta: View {
    @ObservedObject var modelo: ModeloCarpeta
    @FocusState private var enLaRejilla: Bool
    @FocusState private var enElTitulo: Bool
    /// A donde caeria lo que se arrastra.
    @State private var destino: String?
    @State private var columnas = 1

    private static let ancho: CGFloat = 196
    private static let altoDibujo: CGFloat = 252
    private static let hueco: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            barra
            pista
            Divider()
            rejilla
        }
        .background(Paleta.proyectos.lista)
        .onReceive(NotificationCenter.default.publisher(for: .pixpinLienzoGuardado)) { aviso in
            if let r = aviso.object as? String { modelo.lienzoGuardado(r) }
        }
        .onAppear { modelo.recargar() }
    }

    // MARK: Arriba

    private var barra: some View {
        HStack(spacing: 10) {
            Image(systemName: "book").font(.system(size: 20)).foregroundStyle(Paleta.proyectos.texto)
            VStack(alignment: .leading, spacing: 1) {
                Text(modelo.perdida ? TextosCarpeta.noEsta : (modelo.carpeta?.nombre ?? ""))
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(Paleta.proyectos.texto)
                Text(TextosCarpeta.paginas(modelo.paginas.count))
                    .font(.system(size: 12)).foregroundStyle(Paleta.proyectos.apagado)
            }
            Spacer(minLength: 12)
            if !modelo.perdida {
                Button { modelo.nuevaPagina() } label: {
                    Label(TextosCarpeta.nuevaPagina, systemImage: "plus").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { modelo.exportar() } label: {
                    Label(modelo.exportando ? TextosCarpeta.exportando : TextosCarpeta.exportarPdf,
                          systemImage: "square.and.arrow.up").frame(minWidth: 120)
                }
                .controlSize(.large)
                .disabled(modelo.exportando)
            }
        }
        .padding(.horizontal, 24)
        // La franja del titulo (que no se ve) lleva los botones de la ventana.
        .padding(.top, 30)
        .padding(.bottom, 10)
        .background(Paleta.proyectos.barra)
    }

    /// La pista, o lo que se esta escribiendo, o el aviso.
    private var pista: some View {
        var texto = TextosCarpeta.pista
        var apagado = true
        if let a = modelo.aviso {
            texto = a
            apagado = false
        } else if modelo.renombrando != nil {
            texto = TextosCarpeta.escribeTitulo
        }
        return Text(texto)
            .font(.system(size: 12.5))
            .foregroundStyle(apagado ? Paleta.proyectos.apagado : Paleta.proyectos.texto)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 24)
    }

    // MARK: Las paginas

    private var rejilla: some View {
        GeometryReader { geo in
            ScrollViewReader { lector in
                ScrollView {
                    if modelo.paginas.isEmpty {
                        Text(modelo.perdida ? TextosCarpeta.noEsta : TextosCarpeta.vacia)
                            .font(.system(size: 15))
                            .foregroundStyle(Paleta.proyectos.apagado)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.ancho, maximum: Self.ancho),
                                                     spacing: Self.hueco)],
                                  spacing: Self.hueco) {
                            ForEach(Array(modelo.paginas.enumerated()), id: \.element.mensaje.id) { k, p in
                                celda(p, k)
                                    .id(p.mensaje.id)
                            }
                        }
                        .padding(24)
                    }
                }
                .onChange(of: modelo.elegida) { _, e in
                    if let e { withAnimation(.easeOut(duration: 0.12)) { lector.scrollTo(e) } }
                }
            }
            .onAppear { columnas = Self.columnas(geo.size.width) }
            .onChange(of: geo.size.width) { _, w in columnas = Self.columnas(w) }
        }
        .focusable()
        .focused($enLaRejilla)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { tecla($0) }
        .onAppear { enLaRejilla = true }
    }

    /// Cuantas caben a lo ancho (para ↑ ↓).
    private static func columnas(_ ancho: CGFloat) -> Int {
        max(1, Int((ancho - 48 + hueco) / (Self.ancho + hueco)))
    }

    private func celda(_ p: PaginaDeCarpeta, _ k: Int) -> some View {
        let id = p.mensaje.id
        let elegida = modelo.elegida == id
        let ultima = k + 1 == modelo.paginas.count
        return VStack(alignment: .leading, spacing: 6) {
            MiniaturaDePagina(mensaje: p.mensaje, chat: modelo.chat, almacen: modelo.almacen,
                              lado: Self.altoDibujo, version: modelo.version)
                .padding(8)
                .frame(width: Self.ancho, height: Self.altoDibujo)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) { ChapaDeNumero(texto: "\(k + 1)", tam: 12).padding(8) }
                .contentShape(Rectangle())
                .onTapGesture {
                    modelo.terminarDeRenombrar(guardar: true)
                    modelo.abrir(p)
                }
                .draggable(id)
            if modelo.renombrando == id {
                TextField("", text: $modelo.escrito)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13.5))
                    .focused($enElTitulo)
                    .onSubmit {
                        modelo.terminarDeRenombrar(guardar: true)
                        enLaRejilla = true
                    }
                    .onExitCommand {
                        modelo.terminarDeRenombrar(guardar: false)
                        enLaRejilla = true
                    }
                    // Pulsar fuera del titulo que se escribe lo guarda.
                    .onChange(of: enElTitulo) { _, dentro in
                        if !dentro, modelo.renombrando == id { modelo.terminarDeRenombrar(guardar: true) }
                    }
                    .onAppear { enElTitulo = true }
            } else {
                Text(p.titulo)
                    .font(.system(size: 13.5))
                    .foregroundStyle(elegida ? .white : Paleta.proyectos.texto)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { modelo.empezarARenombrar(id) }
                    .onTapGesture { modelo.elegida = id }
            }
            HStack(spacing: 6) {
                boton("chevron.left", TextosCarpeta.antes, activo: k > 0, elegida: elegida) { modelo.mover(k, k - 1) }
                boton("chevron.right", TextosCarpeta.despues, activo: !ultima, elegida: elegida) { modelo.mover(k, k + 1) }
                boton("pencil", TextosCarpeta.renombrar, activo: true, elegida: elegida) { modelo.empezarARenombrar(id) }
                boton("xmark", TextosCarpeta.quitar, activo: true, elegida: elegida) { modelo.quitar(id) }
            }
        }
        .padding(6)
        .background(fondo(elegida: elegida, destino: destino == id), in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { ids, _ in
            guard let movida = ids.first, let desde = modelo.posicion(movida), desde != k else { return false }
            modelo.mover(desde, k)
            return true
        } isTargeted: { encima in
            if encima { destino = id } else if destino == id { destino = nil }
        }
        .contextMenu {
            Button { modelo.abrir(p) } label: { Label("Abrir", systemImage: "arrow.up.right.square") }
            Button { modelo.empezarARenombrar(id) } label: { Label(TextosCarpeta.renombrar, systemImage: "pencil") }
            Button { modelo.mover(k, k - 1) } label: { Label(TextosCarpeta.antes, systemImage: "chevron.left") }
                .disabled(k == 0)
            Button { modelo.mover(k, k + 1) } label: { Label(TextosCarpeta.despues, systemImage: "chevron.right") }
                .disabled(ultima)
            Divider()
            Button(role: .destructive) { modelo.quitar(id) } label: { Label(TextosCarpeta.quitar, systemImage: "xmark") }
        }
    }

    private func fondo(elegida: Bool, destino: Bool) -> Color {
        elegida || destino ? Paleta.proyectos.filaElegida : .clear
    }

    private func boton(_ simbolo: String, _ ayuda: String, activo: Bool, elegida: Bool,
                       hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: simbolo)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(elegida ? Color.white : Paleta.proyectos.apagado)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!activo)
        .opacity(activo ? 1 : 0.35)
        .help(ayuda)
    }

    // MARK: Teclado

    private func tecla(_ k: KeyPress) -> KeyPress.Result {
        guard modelo.renombrando == nil else { return .ignored }
        let n = modelo.paginas.count
        guard n > 0 else { return .ignored }
        let i = modelo.posicion(modelo.elegida) ?? 0
        let mando = k.modifiers.contains(.command)
        func ir(_ j: Int) { modelo.elegida = modelo.paginas[max(0, min(n - 1, j))].mensaje.id }
        switch k.key {
        // ⌘← ⌘→ la cambian de sitio (Ctrl+flechas en Windows).
        case .leftArrow where mando: modelo.mover(i, i - 1)
        case .rightArrow where mando: modelo.mover(i, i + 1)
        case .leftArrow: ir(i - 1)
        case .rightArrow: ir(i + 1)
        case .upArrow: ir(i - columnas)
        case .downArrow: ir(i + columnas)
        case .return: modelo.abrir(modelo.paginas[i])
        case .delete, .deleteForward: modelo.quitar(modelo.paginas[i].mensaje.id)
        case teclaF2: modelo.empezarARenombrar(modelo.paginas[i].mensaje.id)
        case .escape: VentanaLisa.cerrar(modelo.ventana)
        default: return .ignored
        }
        return .handled
    }
}
