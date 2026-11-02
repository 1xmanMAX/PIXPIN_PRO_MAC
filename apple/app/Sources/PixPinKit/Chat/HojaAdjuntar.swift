// **La hoja del clip de la caja**, como la «Adjuntar» del iPhone (Windows
// f87468aa, `ventana_chat/hoja_adjuntar.rs`): arriba «Cerrar» en una
// pastilla y el titulo; lo de todos los dias en una cuadricula de cuatro
// (el cuadrado de color con su icono blanco y el nombre debajo: foto,
// archivo, lienzo, nota, lista de tareas, tabla y captura); una raya, «Más»
// y lo demas en dos columnas de pastillas grises con su icono; otra raya y
// «Pegar» (apagado si no hay nada copiado). Sin buscador: son pocas.
//
// Teclado, como alli: las flechas recorren (`moverEnLaHojaAdjuntar` del
// nucleo), Intro hace lo elegido, 1–7 las baldosas y Esc cierra. Cada
// entrada hace lo mismo que su `Accion` de Windows.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Lo que hace cada entrada de la hoja.
enum AccionAdjuntar: Hashable, Sendable {
    case foto, archivo, lienzo, nota, tabla, conversacion, captura
    case pagina, proyecto, telepronter, pronunciar, delMovil
    /// Una figura de la biblioteca, elegida en la ventana de las figuras, a
    /// un lienzo del chat (en el del asistente, para que la mejore), y
    /// pedirle una nueva al asistente (`para_el_asistente`).
    case figura, pedirFigura
    /// Una carpeta de paginas (26-oct-2026): un cuaderno con nombre.
    case carpeta
    /// Una mini-app (`tareas`, `cronometro`...), por su nombre en el nucleo.
    case mini(String)
    /// «Pegar lo copiado»: ficheros o una imagen al chat; un texto, a la caja.
    case pegar

    /// Si el Mac ya la hace. Las que no, salen apagadas.
    var enElMac: Bool {
        switch self {
        default: true
        }
    }
}

/// Una entrada de la hoja.
struct OpcionAdjuntar: Identifiable, Hashable, Sendable {
    let rotulo: String
    /// El rotulo y sus sinonimos, ya normalizados: donde mira el buscador.
    let buscable: String
    let accion: AccionAdjuntar
    /// El color de su cuadrado (solo las baldosas) y su simbolo.
    let color: UInt32
    let simbolo: String
    /// Del 1 al 8 en las baldosas; `nil` en los chips.
    var numero: Int?

    var id: String { rotulo }
    var esBaldosa: Bool { numero != nil }

    init(_ rotulo: String, _ palabras: String, _ accion: AccionAdjuntar,
         color: UInt32 = 0, simbolo: String = "", numero: Int? = nil) {
        self.rotulo = rotulo
        buscable = HojaAdjuntar.normalizar("\(rotulo) \(palabras)")
        self.accion = accion
        self.color = color
        self.simbolo = simbolo
        self.numero = numero
    }
}

enum HojaAdjuntar {
    /// Las columnas de baldosas y de «Más» (las de Windows, del nucleo).
    static let columnas = Int(columnasDeLaHoja().baldosas)
    static let columnasChips = Int(columnasDeLaHoja().chips)

    /// Las de Windows, en su orden, con los colores del iPhone (azul, gris,
    /// naranja, verde, verde, indigo y rojo) y sus simbolos.
    static let opciones: [OpcionAdjuntar] = [
        .init(Lengua.t("adjuntar-imagen"), "", .foto, color: 0x0A84FF, simbolo: "photo", numero: 1),
        .init(Lengua.t("adjuntar-archivo"), "", .archivo, color: 0x8E8E93, simbolo: "doc.text.fill", numero: 2),
        .init(Lengua.t("v2menus-adj-lienzo"), "", .lienzo, color: 0xFF9500, simbolo: "pencil.and.scribble", numero: 3),
        .init(Lengua.t("chat-adj-nota-md"), "", .nota, color: 0x34C759, simbolo: "list.bullet", numero: 4),
        .init(Lengua.t("v2menus-adj-tareas"), "", .mini("tareas"), color: 0x30B350, simbolo: "checklist", numero: 5),
        .init(Lengua.t("v2menus-adj-tabla"), "", .tabla, color: 0x5856D6, simbolo: "tablecells.fill", numero: 6),
        // La «Cámara» del movil: en el Mac, la captura de una zona.
        .init(Lengua.t("v2menus-adj-captura"), "", .captura, color: 0xFF3B30, simbolo: "crop", numero: 7),
        // «Más», de dos en dos en el orden del iPhone.
        .init(Lengua.t("v2menus-adj-proyecto"), "", .proyecto, simbolo: "folder"),
        .init(Lengua.t("v2menus-adj-pagina"), "", .pagina, simbolo: "doc.text"),
        .init(Lengua.t("asistente-adj-figura"), "", .figura, simbolo: "paintpalette"),
        .init(Lengua.t("carpeta-nueva"), "", .carpeta, simbolo: "book"),
        .init(Lengua.t("mini-contador"), "", .mini("contador"), simbolo: "number"),
        .init(Lengua.t("mini-ruleta"), "", .mini("ruleta"), simbolo: "arrow.counterclockwise"),
        .init(Lengua.t("mini-gastos"), "", .mini("gastos"), simbolo: "square.and.pencil"),
        .init(Lengua.t("mini-cronometro"), "", .mini("cronometro"), simbolo: "timer"),
        .init(Lengua.t("mini-temporizador"), "", .mini("temporizador"), simbolo: "gauge.with.dots.needle.67percent"),
        .init(Lengua.t("mini-alarma"), "", .mini("alarma"), simbolo: "alarm"),
        .init(Lengua.t("v2menus-adj-conversacion"), "", .conversacion, simbolo: "bubble.left.and.bubble.right"),
        .init(Lengua.t("chat-adj-telepronter"), "", .telepronter, simbolo: "captions.bubble"),
        .init(Lengua.t("chat-adj-pronunciar"), "", .pronunciar, simbolo: "person.wave.2"),
        .init(Lengua.t("v2menus-adj-movil"), "", .delMovil, simbolo: "wifi"),
    ]

    /// **La hoja del chat del asistente** (`para_el_asistente` de Windows,
    /// 25-oct-2026: «que pueda adjuntar figuras para que las mejore, o
    /// decirle hazme una figura»): primero **Figura** y lo que se le suele
    /// dar a mirar; en «Más», pedir una figura nueva y lo demas que sirve.
    static let delAsistente: [OpcionAdjuntar] = {
        func de(_ a: AccionAdjuntar, _ numero: Int?) -> OpcionAdjuntar? {
            guard var o = HojaAdjuntar.opciones.first(where: { $0.accion == a }) else { return nil }
            o.numero = numero
            return o
        }
        var v = [OpcionAdjuntar(Lengua.t("asistente-adj-figura"), "", .figura,
                                color: 0xAF52DE, simbolo: "paintpalette.fill", numero: 1)]
        for a in [AccionAdjuntar.foto, .archivo, .captura, .lienzo, .nota] {
            if let o = de(a, v.count + 1) { v.append(o) }
        }
        v.append(OpcionAdjuntar(Lengua.t("asistente-adj-pedir-figura"), "", .pedirFigura, simbolo: "sparkles"))
        for a in [AccionAdjuntar.pagina, .proyecto, .tabla, .delMovil] {
            if let o = de(a, nil) { v.append(o) }
        }
        return v
    }()

    /// Minusculas y sin tildes.
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Si hay algo que pegar (ficheros, una imagen o texto).
    @MainActor static var hayCopiado: Bool {
        let pb = NSPasteboard.general
        return !(pb.types ?? []).isEmpty && (pb.pasteboardItems?.isEmpty == false)
    }
}

// MARK: - La vista

/// La hoja, en el globo que sale del clip.
struct VistaHojaAdjuntar: View {
    let elegir: (AccionAdjuntar) -> Void
    let cerrar: () -> Void
    /// Las de siempre, o las del asistente (`HojaAdjuntar.delAsistente`).
    var opciones: [OpcionAdjuntar] = HojaAdjuntar.opciones
    /// Lo elegido con las flechas (indice: baldosas, chips y «Pegar»).
    @State private var elegido: Int?
    @State private var encima: String?
    @State private var hayCopiado = false
    @FocusState private var enfocada: Bool

    private var baldosas: [OpcionAdjuntar] { opciones.filter(\.esBaldosa) }
    private var chips: [OpcionAdjuntar] { opciones.filter { !$0.esBaldosa } }

    var body: some View {
        let baldosas = self.baldosas, chips = self.chips
        VStack(alignment: .leading, spacing: 12) {
            cabecera
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: HojaAdjuntar.columnas),
                      spacing: 4) {
                ForEach(Array(baldosas.enumerated()), id: \.element.id) { i, o in
                    baldosa(o, elegida: elegido == i)
                }
            }
            if !chips.isEmpty {
                raya
                Text(Lengua.t("v2menus-adj-mas"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.proyectos.apagado)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                         count: HojaAdjuntar.columnasChips), spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { i, o in
                        chip(o, elegido: elegido == baldosas.count + i)
                    }
                }
            }
            raya
            HStack {
                Spacer()
                Button { elegir(.pegar) } label: {
                    Label(Lengua.t("lienzo-pegar-menu"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(hayCopiado ? Color(hex: 0x0A84FF) : Paleta.proyectos.apagado)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Color(hex: 0x0A84FF).opacity(hayCopiado ? (elegido == indicePegar ? 0.30 : 0.15) : 0.06),
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!hayCopiado)
            }
        }
        .padding(16)
        .frame(width: 480)
        .background(Paleta.chat.cabecera)
        .focusable()
        .focusEffectDisabled()
        .focused($enfocada)
        .onAppear {
            hayCopiado = HojaAdjuntar.hayCopiado
            enfocada = true
        }
        .onKeyPress(phases: .down) { tecla($0) }
    }

    private var indicePegar: Int { baldosas.count + chips.count }

    private var cabecera: some View {
        ZStack {
            Text(Lengua.t("chat-adjuntar"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.proyectos.texto)
            HStack {
                Button(action: cerrar) {
                    Text(Lengua.t("pin-cerrar"))
                        .font(.system(size: 13))
                        .foregroundStyle(Paleta.proyectos.texto)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Paleta.proyectos.texto.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .frame(height: 34)
    }

    private var raya: some View {
        Paleta.proyectos.separador.frame(height: 1)
    }

    /// Las teclas de la hoja: flechas, Intro, 1–7 y Esc.
    private func tecla(_ k: KeyPress) -> KeyPress.Result {
        let flecha: FlechaDeLaHoja?
        switch k.key {
        case .upArrow: flecha = .arriba
        case .downArrow: flecha = .abajo
        case .leftArrow: flecha = .izquierda
        case .rightArrow: flecha = .derecha
        case .return:
            if let n = elegido { hacer(n) }
            return .handled
        case .escape:
            cerrar()
            return .handled
        default:
            flecha = nil
        }
        if let flecha {
            elegido = moverEnLaHojaAdjuntar(actual: elegido.map { UInt32($0) }, flecha: flecha,
                                            baldosas: UInt32(baldosas.count), chips: UInt32(chips.count),
                                            pegar: hayCopiado).map { Int($0) }
            return .handled
        }
        if let d = k.characters.first?.wholeNumberValue, let o = baldosas.first(where: { $0.numero == d }) {
            elegir(o.accion)
            return .handled
        }
        return .ignored
    }

    private func hacer(_ n: Int) {
        if n < baldosas.count { elegir(baldosas[n].accion) }
        else if n < indicePegar { elegir(chips[n - baldosas.count].accion) }
        else if hayCopiado { elegir(.pegar) }
    }

    private func baldosa(_ o: OpcionAdjuntar, elegida: Bool) -> some View {
        Button { elegir(o.accion) } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: o.color))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: o.simbolo)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(o.rotulo)
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(fondo(o, elegida: elegida), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 ? o.id : (encima == o.id ? nil : encima) }
        .help("\(o.rotulo) (\(o.numero ?? 0))")
    }

    private func chip(_ o: OpcionAdjuntar, elegido: Bool) -> some View {
        Button { elegir(o.accion) } label: {
            HStack(spacing: 8) {
                Image(systemName: o.simbolo)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(o.rotulo)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(elegido ? .white : Paleta.proyectos.texto)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(elegido ? Paleta.chat.azulElegido
                                : Paleta.proyectos.texto.opacity(encima == o.id ? 0.16 : 0.08),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 ? o.id : (encima == o.id ? nil : encima) }
        .help(o.rotulo)
    }

    private func fondo(_ o: OpcionAdjuntar, elegida: Bool) -> Color {
        if elegida { return Paleta.chat.azulElegido.opacity(0.35) }
        return encima == o.id ? Paleta.proyectos.texto.opacity(0.08) : .clear
    }
}

/// Los chips en filas: los que caben en una, y el resto debajo.
struct FilasDeChips: Layout {
    var espacio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let filas = colocar(ancho: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? filas.ancho, height: filas.alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let filas = colocar(ancho: bounds.width, subviews)
        for (i, p) in filas.sitios.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func colocar(ancho: CGFloat, _ subviews: Subviews) -> (sitios: [CGPoint], ancho: CGFloat, alto: CGFloat) {
        var sitios: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, altoFila: CGFloat = 0, mayor: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho {
                x = 0
                y += altoFila + espacio
                altoFila = 0
            }
            sitios.append(CGPoint(x: x, y: y))
            x += t.width + espacio
            mayor = max(mayor, x - espacio)
            altoFila = max(altoFila, t.height)
        }
        return (sitios, mayor, y + altoFila)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Lo que hace cada entrada

/// Hace una entrada de la hoja en un chat. Cada una hace lo mismo que su
/// `Accion` de Windows con lo que el Mac ya tiene.
@MainActor
enum AdjuntarEnChat {
    static func hacer(_ accion: AccionAdjuntar, chat: String, almacen: Almacen,
                      avisar: @escaping (String) -> Void, abrirVentana: @escaping (String) -> Void) {
        switch accion {
        case .foto:
            elegirFicheros(tipos: [.image, .movie], chat: chat, almacen: almacen)
        case .archivo:
            elegirFicheros(tipos: [], chat: chat, almacen: almacen)
        case .lienzo:
            Task {
                guard let m = await almacen.crearLienzo(en: chat), let referencia = m.referencia else { return }
                VentanasDeLienzo.compartidas.abrir(referencia: referencia, en: chat,
                                                   titulo: Lengua.t("adjuntar-lienzo"), almacen: almacen)
            }
        case .nota:
            // Windows abre el editor con una nota por nacer; aqui la nota
            // nace ya, con su titulo, y se abre en el editor de notas.
            Task {
                guard let m = await almacen.escribir(nota: "# Nota nueva", en: chat) else { return }
                EditoresDeNotas.compartidos.abrir(m, en: chat, almacen: almacen)
            }
        case let .mini(cual):
            crearMini(cual, chat: chat, almacen: almacen)
        case .tabla:
            crearTabla(chat: chat, almacen: almacen)
        case .captura:
            // Como Windows: la captura de siempre (un poco despues, para que
            // el globo ya no salga en la foto). Su «Al chat» propone este
            // proyecto el primero.
            guard let capturador = Capturador.principal else { return NSSound.beep() }
            UserDefaults.standard.set(chat, forKey: ListaDeProyectos.clave)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { capturador.capturar() }
        case .delMovil:
            abrirVentana("envio")
        case .conversacion:
            VozEnElChat.conversacion(chat: chat, almacen: almacen, avisar: avisar)
        case .telepronter:
            VozEnElChat.telepronter(chat: chat, almacen: almacen, avisar: avisar)
        case .pronunciar:
            VozEnElChat.pronunciar(chat: chat, almacen: almacen, avisar: avisar)
        case .proyecto:
            elegirProyecto(chat: chat, almacen: almacen, avisar: avisar)
        case .pagina:
            elegirPagina(chat: chat, almacen: almacen, avisar: avisar)
        case .figura, .pedirFigura, .pegar:
            // Las hace el chat: tocan la caja de escribir (`FigurasDelChat.swift`,
            // `ChatView.adjuntar`).
            break
        case .carpeta:
            // El chat la crea con el nombre listo para escribirlo
            // (`ChatAbierto.crearCarpeta`); sin chat, sin mas.
            let nucleo = almacen.nucleo
            Task {
                guard let m = try? await Task.detached(operation: {
                    try nucleo.crearCarpetaDePaginas(chat: chat, primera: nil)
                }).value else { return avisar(TextosCarpeta.noSePudo) }
                await almacen.alFinal(m, en: chat)
            }
        }
    }

    /// «Proyecto entero» (Windows): un menu con los otros chats; el elegido
    /// entra como su puerta (no se copia).
    private static func elegirProyecto(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        let otros = almacen.chats.filter { $0.id != chat && !$0.esAsistente }
        guard !otros.isEmpty else { return avisar("No hay otros proyectos") }
        let menu = NSMenu()
        for f in otros {
            menu.addItem(ItemConAccion.nuevo(f.nombre) {
                let nucleo = almacen.nucleo
                Task {
                    guard let m = try? await Task.detached(operation: {
                        try nucleo.adjuntarProyecto(chat: chat, proyecto: f.id)
                    }).value else { return avisar("No se pudo adjuntar «\(f.nombre)»") }
                    almacen.anadir([m], en: chat)
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// «Página de un proyecto» (Windows): el proyecto y luego su hoja. Una
    /// pagina del PDF de otro proyecto se pinta aqui con PDFKit.
    private static func elegirPagina(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        let nucleo = almacen.nucleo
        let menu = NSMenu()
        for f in almacen.chats where !f.esAsistente {
            let hojas = nucleo.paginasDeProyecto(proyecto: f.id)
            guard !hojas.isEmpty else { continue }
            let item = NSMenuItem(title: f.nombre, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for h in hojas {
                sub.addItem(ItemConAccion.nuevo("\(h.esLienzo ? "✏️" : "📄") Página \(h.numero)") {
                    Task {
                        var png: Data?
                        if let p = nucleo.paginaPorPintar(hacia: chat, desde: f.id, hoja: h.hoja) {
                            png = ManosDelAsistente.pintar(URL(fileURLWithPath: p.pdf), pagina: Int(p.pagina), ancho: 1400)
                            if png == nil { return avisar("No se pudo pintar esa página") }
                        }
                        let png2 = png
                        guard let m = try? await Task.detached(operation: {
                            try nucleo.adjuntarPagina(hacia: chat, desde: f.id, hoja: h.hoja, png: png2)
                        }).value else { return avisar("No se pudo adjuntar esa página") }
                        almacen.anadir([m], en: chat)
                        NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                    }
                })
            }
            item.submenu = sub
            menu.addItem(item)
        }
        guard !menu.items.isEmpty else { return avisar("Ningún proyecto tiene páginas") }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// El panel de abrir del sistema; lo elegido se copia al chat.
    private static func elegirFicheros(tipos: [UTType], chat: String, almacen: Almacen) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if !tipos.isEmpty { panel.allowedContentTypes = tipos }
        panel.begin { respuesta in
            guard respuesta == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await almacen.adjuntar(urls: urls, en: chat) }
        }
    }

    /// El nombre con el que nace una mini-app (el de su entrada, como
    /// `clave_del_nombre` de Windows).
    static func nombre(deMini cual: String) -> String {
        HojaAdjuntar.opciones.first { $0.accion == .mini(cual) }?.rotulo ?? ""
    }

    private static func crearMini(_ cual: String, chat: String, almacen: Almacen) {
        let nucleo = almacen.nucleo
        let titulo = nombre(deMini: cual)
        let moneda = monedaDelAparato()
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.crearMiniapp(chat: chat, miniapp: cual, titulo: titulo, moneda: moneda) }
            }.value
            switch r {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                GestorPines.compartido.pinearMiniapp(chat: chat, mensaje: m.id, miniapp: cual, documento: m.texto)
            case let .failure(e):
                almacen.ponerError("\(e)")
            }
        }
    }

    private static func crearTabla(chat: String, almacen: Almacen) {
        let nucleo = almacen.nucleo
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.crearTabla(chat: chat, nombre: Lengua.t("chat-tabla")) }
            }.value
            switch r {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                HojasDeCalculo.compartidas.abrir(m, en: chat, almacen: almacen)
            case let .failure(e):
                almacen.ponerError("\(e)")
            }
        }
    }
}

extension Almacen {
    /// Un mensaje recien creado, al final de lo cargado (o, si se veia una
    /// pagina del medio, el chat otra vez desde el final).
    func alFinal(_ m: MensajeChat, en chat: String) async {
        if quedanPosteriores(chat: chat) {
            await abrir(chat: chat)
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        } else {
            anadir([m], en: chat)
        }
    }
}
