// **El menu de un mensaje del chat**, el de Windows (`menu_de_mensaje` de
// `ventana_chat.rs`, la v2 de los menus) con su orden y sus letras:
//
// - encima, la fila de etiquetas (⭐ ✅ ⏳ 💡 💰 📍): pulsar la puesta la
//   quita;
// - lo diario: Responder (R), Copiar (⌘C), Pinear (P), Añadir o editar la
//   descripcion (E), Abrir en el editor de notas (N) y lo propio de cada
//   burbuja (Pasar a texto, T, en una nota de voz; Vista rapida...);
// - mandarlo a otro sitio y acordarse: Reenviar (F), Compartir…,
//   Recordarmelo (o Quitar el recordatorio) y Hacer leccion (L);
// - «Mas»: Cambiar el nombre (F2), Fijar arriba, Abrir con…, Guardar esto
//   (lo del buzon), Ver comentarios y Elegir varios (⌘-clic);
// - Borrar, en rojo y aparte (⌫), en `BorrarMensajes.swift`.
//
// Las letras valen con el menu abierto, como en Windows (alli Ctrl+C, aqui
// ⌘C). Lo que se escribe en el cuaderno pasa por el nucleo
// (`Nucleo.cambiarMensaje`, `reenviarMensajes`, `leccionDeMensaje`): los
// mismos campos que Windows y el movil (`fijado`, `emoji`, `texto`,
// `nombre`, `recuerdaEn`, `enBuzon`, `respondeA`), para que viajen.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Lo que el menu necesita de su chat

/// Lo que el menu de una burbuja puede hacer con su mensaje. Lo pone el
/// chat (`VistaChat`) en el entorno de cada burbuja, para que lo usen
/// tambien los menus propios de las burbujas (fichero, nota, voz), que
/// tapan al de fuera.
struct AccionesDeMensaje {
    var mensaje: MensajeChat
    var marcado: Bool
    var marcar: () -> Void
    var borrar: () -> Void
    var chat: ChatAbierto
}

private struct ClaveAccionesDeMensaje: EnvironmentKey {
    static let defaultValue: AccionesDeMensaje? = nil
}

extension EnvironmentValues {
    var accionesDeMensaje: AccionesDeMensaje? {
        get { self[ClaveAccionesDeMensaje.self] }
        set { self[ClaveAccionesDeMensaje.self] = newValue }
    }
}

/// Lo que se esta escribiendo en la hoja de una linea: la descripcion, el
/// nombre o la hora de avisar (la barra de Windows encima de la caja).
enum Escritura: Identifiable, Equatable {
    case describir(MensajeChat)
    case renombrar(MensajeChat)
    case hora(MensajeChat)

    var id: String {
        switch self {
        case let .describir(m): "d" + m.id
        case let .renombrar(m): "r" + m.id
        case let .hora(m): "h" + m.id
        }
    }

    var mensaje: MensajeChat {
        switch self {
        case let .describir(m), let .renombrar(m), let .hora(m): m
        }
    }
}

/// **El estado del chat abierto que toca el menu**: a quien se responde,
/// la hoja de escribir, el aviso de abajo y las acciones que escriben.
@MainActor
final class ChatAbierto: ObservableObject {
    let chat: String
    let almacen: Almacen
    /// El mensaje al que se contesta (la barra encima de la caja).
    @Published var respondiendo: String?
    @Published var escritura: Escritura?
    /// Lo que se dice un momento abajo («Copiado», «Reenviado»...).
    @Published private(set) var aviso: String?
    private var turnoAviso = 0

    /// Los mensajes elegidos (⌘-clic o «Elegir varios»).
    @Published var eleccion = Eleccion()

    /// Saltar a un mensaje cargado (lo pone `VistaChat`).
    var irA: (String) -> Void = { _ in }

    init(chat: String, almacen: Almacen) {
        self.chat = chat
        self.almacen = almacen
    }

    var cargados: [MensajeChat] { almacen.mensajes[chat] ?? [] }

    /// Los elegidos en el orden del chat.
    func elegidos() -> [String] { eleccion.enOrden(cargados.map(\.id)) }

    func soltarElegidos() { eleccion.vaciar() }

    func avisar(_ texto: String) {
        aviso = texto
        turnoAviso += 1
        let turno = turnoAviso
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if turno == turnoAviso { aviso = nil }
        }
    }

    /// Los ids sobre los que actua una entrada: si el mensaje esta entre
    /// los elegidos, todos los elegidos (lo que se espera al pulsar sobre
    /// uno de un grupo marcado, como en Windows); si no, el.
    func sobre(_ m: MensajeChat) -> [String] {
        let todos = elegidos()
        return todos.contains(m.id) ? todos : [m.id]
    }

    /// El fichero del mensaje en este Mac, si ya se resolvio y esta.
    func fichero(_ m: MensajeChat) -> URL? {
        guard let ruta = m.ruta, !ruta.isEmpty,
              let url = almacen.urlResuelta(deRuta: ruta, en: chat),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: Lo diario

    func responder(_ m: MensajeChat) {
        respondiendo = m.id
    }

    /// Copia el texto (sin espacios de los lados), como `Accion::Copiar`.
    func copiar(_ ids: [String]) {
        let texto = ChatAbierto.textoParaCopiar(cargados.filter { ids.contains($0.id) })
        guard !texto.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        avisar("Copiado")
        if ids.count > 1 { soltarElegidos() }
    }

    /// El texto de unos mensajes para el portapapeles: el de cada uno sin
    /// espacios a los lados, sin las mini-apps (su texto es un JSON) y
    /// separados por una linea en blanco (`copiar_marcados` de Windows).
    nonisolated static func textoParaCopiar(_ mensajes: [MensajeChat]) -> String {
        mensajes
            .filter { $0.clase != "MINIAPP" }
            .map { $0.texto.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Si «Copiar» sale para este mensaje.
    nonisolated static func sePuedeCopiar(_ m: MensajeChat) -> Bool {
        m.clase != "MINIAPP" && !m.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Una lista de tareas: no tiene fichero, pero se pinea viva.
    nonisolated static func esListaDeTareas(_ m: MensajeChat) -> Bool {
        m.clase == "MINIAPP" && m.miniapp == "tareas"
    }

    /// Sacarlo a la pantalla: el fichero en un pin; una lista de tareas, la
    /// lista viva (lo que se tache alli se guarda en el mensaje).
    func pinear(_ m: MensajeChat) {
        if ChatAbierto.esListaDeTareas(m) {
            GestorPines.compartido.pinearMiniapp(chat: chat, mensaje: m.id, miniapp: "tareas", documento: m.texto)
            avisar("Pineado")
            return
        }
        guard let url = fichero(m) else {
            avisar("Este mensaje no tiene un archivo en este equipo")
            return
        }
        if GestorPines.compartido.pinear(fichero: url) {
            avisar("Pineado")
        } else {
            avisar("No se pudo pinear este archivo")
        }
    }

    func editarNota(_ m: MensajeChat) {
        EditoresDeNotas.compartidos.abrir(m, en: chat, almacen: almacen)
    }

    // MARK: Lo que cambia el mensaje

    func cambiar(_ ids: [String], _ cambio: CambioMensaje, aviso: String? = nil) {
        let almacen = self.almacen
        let chat = self.chat
        Task {
            var bien = true
            for id in ids where await almacen.cambiar(mensaje: id, en: chat, cambio) == nil {
                bien = false
            }
            if let aviso, bien { avisar(aviso) }
        }
    }

    /// Una etiqueta de la fila: la que ya estaba puesta, otra vez, se quita.
    func etiquetar(_ m: MensajeChat, _ emoji: String) {
        cambiar([m.id], .etiqueta(emoji: m.emoji == emoji ? nil : emoji))
    }

    /// Fija lo elegido; si ya estaba todo fijado, lo suelta (`fijar_marcados`).
    func fijar(_ ids: [String]) {
        let mensajes = cargados.filter { ids.contains($0.id) }
        let fijar = mensajes.contains { !$0.fijado }
        let cambiar = mensajes.filter { $0.fijado != fijar }.map(\.id)
        self.cambiar(cambiar, .fijar(fijado: fijar))
        if ids.count > 1 { soltarElegidos() }
    }

    func recordar(_ m: MensajeChat, en cuando: Date) {
        let ms = Int64((cuando.timeIntervalSince1970 * 1000).rounded())
        let texto = HorasDeRecordar.resumen(de: m)
        let almacen = self.almacen
        let chat = self.chat
        Task {
            guard await almacen.cambiar(mensaje: m.id, en: chat, .recordar(cuando: ms)) != nil else { return }
            RecordatoriosDeMensajes.programar(chat: chat, id: m.id, texto: texto, cuando: cuando)
            avisar("Te aviso a las \(HorasDeRecordar.legible(cuando, ahora: Date()))")
        }
    }

    func olvidar(_ m: MensajeChat) {
        let almacen = self.almacen
        let chat = self.chat
        Task {
            guard await almacen.cambiar(mensaje: m.id, en: chat, .recordar(cuando: nil)) != nil else { return }
            RecordatoriosDeMensajes.cancelar(chat: chat, id: m.id)
            avisar("Recordatorio quitado")
        }
    }

    /// Lo escrito en la hoja: descripcion, nombre u hora.
    func guardar(_ e: Escritura, _ texto: String) {
        switch e {
        case let .describir(m):
            cambiar([m.id], .descripcion(texto: texto))
        case let .renombrar(m):
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty else { return }
            // Un audio se escribe sin su «.m4a» y el nucleo se la vuelve a
            // poner (`con_su_extension`).
            cambiar([m.id], .nombre(nombre: limpio))
        case let .hora(m):
            if let cuando = HorasDeRecordar.horaEscrita(texto, ahora: Date()) {
                recordar(m, en: cuando)
            }
        }
    }

    /// Lo que la hoja de cambiar el nombre trae escrito: el nombre, sin el
    /// «.m4a» de un audio; un lienzo sin nombre, «Lienzo».
    nonisolated static func nombreParaEscribir(_ m: MensajeChat) -> String {
        let n = m.nombre.trimmingCharacters(in: .whitespaces)
        if m.clase != "DIBUJO", !n.isEmpty {
            return n.hasSuffix(".m4a") ? String(n.dropLast(4)) : n
        }
        return n.isEmpty ? (m.clase == "DIBUJO" ? "Lienzo" : m.resumen) : n
    }

    // MARK: Mandarlo a otro sitio

    /// Los demas proyectos: todos menos este («Mensajes guardados» tambien).
    var otrosChats: [FichaChat] { almacen.chats.filter { $0.id != chat } }

    /// «Reenviar»: el menu de los demas proyectos donde esta el raton, como
    /// el de Windows (`menu_de_proyectos`).
    func reenviar(_ ids: [String]) {
        let otros = otrosChats
        guard !otros.isEmpty else {
            avisar("No hay otro proyecto al que mandarlo")
            return
        }
        MenuEmergente.mostrar(otros.map { f in
            MenuEmergente.Entrada(titulo: f.nombre, icono: f.esGuardados ? "bookmark" : "folder") { [weak self] in
                self?.reenviar(ids, a: f.id)
            }
        })
    }

    func reenviar(_ ids: [String], a destino: String) {
        let almacen = self.almacen
        let chat = self.chat
        Task {
            let n = await almacen.reenviar(mensajes: ids, de: chat, a: destino)
            if n > 0 {
                soltarElegidos()
                avisar("Reenviado")
            }
        }
    }

    /// «Compartir…»: los servicios del sistema (Mail, Mensajes, AirDrop...)
    /// con los ficheros, o con el texto si no hay ficheros.
    func compartir(_ ids: [String]) {
        let mensajes = cargados.filter { ids.contains($0.id) }
        var cosas: [Any] = mensajes.compactMap { fichero($0) }
        if cosas.isEmpty {
            let texto = ChatAbierto.textoParaCopiar(mensajes)
            guard !texto.isEmpty else {
                avisar("Este mensaje no tiene un archivo en este equipo")
                return
            }
            cosas = [texto]
        }
        // Donde esta el raton, tras cerrarse el menu del mensaje.
        DispatchQueue.main.async {
            guard let ventana = NSApp.keyWindow, let vista = ventana.contentView else { return }
            let p = vista.convert(ventana.mouseLocationOutsideOfEventStream, from: nil)
            NSSharingServicePicker(items: cosas)
                .show(relativeTo: NSRect(origin: p, size: CGSize(width: 1, height: 1)), of: vista, preferredEdge: .maxY)
        }
    }

    /// «Abrir con»: las apps que saben abrir el fichero.
    func abrir(_ url: URL, con app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// «Otra app…»: se elige en el disco.
    func abrirConOtra(_ url: URL) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Abrir"
        if panel.runModal() == .OK, let app = panel.url { abrir(url, con: app) }
    }

    // MARK: Acordarse

    /// «Hacer lección»: la ficha nueva con lo que dice el mensaje ya
    /// repartido, enlazada a el (`deMensaje`) y en este chat.
    func hacerLeccion(_ m: MensajeChat) {
        let nucleo = almacen.nucleo
        let chat = self.chat
        let id = m.id
        Task {
            let hecho = await Task.detached(priority: .userInitiated) {
                Result { try nucleo.leccionDeMensaje(chat: chat, id: id) }
            }.value
            var b = BorradorLeccion()
            b.chat = chat
            b.deMensaje = id
            if case let .success(l?) = hecho {
                b.titulo = l.titulo
                b.quePaso = l.quePaso
                b.porQue = l.porQue
                b.proxima = l.proxima
                b.etiquetas = l.etiquetas
            }
            VentanasDeLeccion.compartidas.nueva(b, nucleo: nucleo)
        }
    }

    /// «Ver comentarios»: los que le responden, en un menu; uno lleva a el.
    func verHilo(_ m: MensajeChat) {
        let respuestas = cargados.filter { $0.respondeA == m.id }
        MenuEmergente.mostrar(respuestas.map { r in
            MenuEmergente.Entrada(titulo: String(r.resumen.prefix(80)), icono: "arrowshape.turn.up.left") { [weak self] in
                self?.irA(r.id)
            }
        })
    }
}

// MARK: - Las entradas

/// Las entradas del menu de un mensaje. `propias` son las de la burbuja
/// (Vista rapida, Pasar a texto...): van con lo diario. Fuera de un chat
/// (sin acciones en el entorno), solo esas.
struct EntradasDeMensaje<Propias: View>: View {
    @Environment(\.accionesDeMensaje) private var acciones
    private let propias: Propias

    init(@ViewBuilder propias: () -> Propias) {
        self.propias = propias()
    }

    var body: some View {
        if let acciones {
            MenuDeMensaje(a: acciones, propias: propias)
        } else {
            propias
        }
    }
}

extension EntradasDeMensaje where Propias == EmptyView {
    init() { propias = EmptyView() }
}

/// F2 (Cambiar el nombre), como en Windows.
let teclaF2 = KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!))

private struct MenuDeMensaje<Propias: View>: View {
    let a: AccionesDeMensaje
    let propias: Propias

    private var m: MensajeChat { a.mensaje }
    private var c: ChatAbierto { a.chat }

    var body: some View {
        // ── La fila de etiquetas ──
        ControlGroup {
            ForEach(MenuMensaje.etiquetas, id: \.self) { e in
                Button { c.etiquetar(m, e) } label: {
                    Text(m.emoji == e ? "\(e)✓" : e)
                }
                .help(m.emoji == e ? "Quitar la etiqueta" : "Etiquetar")
            }
        }
        .controlGroupStyle(.compactMenu)
        Divider()

        // ── Lo diario ──
        Button { c.responder(m) } label: { Label("Responder", systemImage: "arrowshape.turn.up.left") }
            .keyboardShortcut("r", modifiers: [])
        if ChatAbierto.sePuedeCopiar(m) {
            Button { c.copiar([m.id]) } label: { Label("Copiar", systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: .command)
        }
        if m.ruta?.isEmpty == false || ChatAbierto.esListaDeTareas(m) {
            Button { c.pinear(m) } label: { Label("Pinear", systemImage: "pin") }
                .keyboardShortcut("p", modifiers: [])
        }
        if m.sePuedeDescribir {
            Button { c.escritura = .describir(m) } label: {
                Label(m.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Añadir descripción" : "Editar descripción", systemImage: "captions.bubble")
            }
            .keyboardShortcut("e", modifiers: [])
        }
        if m.clase == "NOTA" {
            Button { c.editarNota(m) } label: { Label("Abrir en el editor de notas", systemImage: "square.and.pencil") }
                .keyboardShortcut("n", modifiers: [])
        }
        propias

        // ── Mandarlo a otro sitio y acordarse ──
        Divider()
        Button { c.reenviar(c.sobre(m)) } label: { Label("Reenviar", systemImage: "arrowshape.turn.up.right") }
            .keyboardShortcut("f", modifiers: [])
        Button { c.compartir(c.sobre(m)) } label: { Label("Compartir…", systemImage: "square.and.arrow.up") }
        if m.recuerdaEn != nil {
            Button { c.olvidar(m) } label: { Label("Quitar el recordatorio", systemImage: "alarm") }
        } else {
            Menu {
                ForEach(HorasDeRecordar.atajos(ahora: Date()), id: \.titulo) { h in
                    Button { c.recordar(m, en: h.cuando) } label: { Label(h.titulo, systemImage: "alarm") }
                }
                Button { c.escritura = .hora(m) } label: { Label("Elegir la hora…", systemImage: "pencil") }
            } label: {
                Label("Recordármelo", systemImage: "alarm")
            }
        }
        if !m.esLeccion, m.clase != "ARCHIVO" {
            Button { c.hacerLeccion(m) } label: { Label("Hacer lección", systemImage: "lightbulb") }
                .keyboardShortcut("l", modifiers: [])
        }

        // ── «Más»: lo que se usa poco ──
        Divider()
        Menu {
            if m.sePuedeRenombrar {
                Button { c.escritura = .renombrar(m) } label: { Label("Cambiar el nombre", systemImage: "pencil") }
                    .keyboardShortcut(teclaF2, modifiers: [])
            }
            Button { c.fijar([m.id]) } label: {
                Label(m.fijado ? "Quitar de arriba" : "Fijar arriba", systemImage: m.fijado ? "flag.slash" : "flag")
            }
            if let url = c.fichero(m) {
                Menu {
                    let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
                    ForEach(apps, id: \.self) { app in
                        Button { c.abrir(url, con: app) } label: {
                            Label {
                                Text(FileManager.default.displayName(atPath: app.path))
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            }
                        }
                    }
                    if !apps.isEmpty { Divider() }
                    Button("Otra app…") { c.abrirConOtra(url) }
                } label: {
                    Label("Abrir con…", systemImage: "arrow.up.forward.app")
                }
            }
            if m.enBuzon {
                Button { c.cambiar([m.id], .rescatar) } label: { Label("Guardar esto", systemImage: "bookmark") }
            }
            if c.cargados.contains(where: { $0.respondeA == m.id }) {
                Button { c.verHilo(m) } label: { Label("Ver comentarios", systemImage: "bubble.left.and.bubble.right") }
            }
            Divider()
            Button(action: a.marcar) {
                Label(a.marcado ? "Quitar de los elegidos" : "Elegir varios (⌘-clic)", systemImage: "checkmark.square")
            }
        } label: {
            Label("Más", systemImage: "ellipsis.circle")
        }

        // ── Borrar, en rojo y aparte ──
        Divider()
        Button(role: .destructive, action: a.borrar) { Label("Borrar", systemImage: "trash") }
            .keyboardShortcut(.delete, modifiers: [])
    }
}

/// Lo comun del menu que no es una vista.
enum MenuMensaje {
    /// Las etiquetas del movil y de Windows, en su orden
    /// (`chats::ETIQUETAS` del nucleo).
    static let etiquetas = ["\u{2B50}", "\u{2705}", "\u{23F3}", "\u{1F4A1}", "\u{1F4B0}", "\u{1F4CD}"]
}

// MARK: - Un menu donde esta el raton

/// Un menu que sale donde esta el raton tras cerrarse el del mensaje (los
/// proyectos de «Reenviar», los servicios de «Compartir», el hilo): lo que
/// en Windows es otro menu en el mismo sitio (`Efecto::Menu`).
@MainActor
enum MenuEmergente {
    struct Entrada {
        var titulo: String
        var icono: String?
        var imagen: NSImage?
        var hacer: () -> Void

        init(titulo: String, icono: String? = nil, imagen: NSImage? = nil, hacer: @escaping () -> Void) {
            self.titulo = titulo
            self.icono = icono
            self.imagen = imagen
            self.hacer = hacer
        }
    }

    private final class Destino: NSObject {
        let hacer: () -> Void
        init(_ hacer: @escaping () -> Void) { self.hacer = hacer }
        @objc func pulsar(_: Any?) { hacer() }
    }

    static func mostrar(_ entradas: [Entrada]) {
        guard !entradas.isEmpty else { return }
        // Una vuelta despues: que el menu del mensaje ya se haya cerrado.
        DispatchQueue.main.async {
            let menu = NSMenu()
            var destinos: [Destino] = []
            for e in entradas {
                let d = Destino(e.hacer)
                destinos.append(d)
                let item = NSMenuItem(title: e.titulo, action: #selector(Destino.pulsar(_:)), keyEquivalent: "")
                item.target = d
                if let imagen = e.imagen {
                    item.image = imagen
                } else if let icono = e.icono {
                    item.image = NSImage(systemSymbolName: icono, accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
            // `popUp` no vuelve hasta que se cierra: los destinos viven hasta entonces.
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            withExtendedLifetime(destinos) {}
        }
    }
}

// MARK: - Las horas de recordar

/// Las horas que se ofrecen al poner un recordatorio, las de Windows
/// (`recordatorios::atajos`, las del movil y «dentro de 10 minutos»), y la
/// hora escrita a mano (`hora_escrita`). En hora local.
enum HorasDeRecordar {
    struct Atajo {
        var titulo: String
        var cuando: Date
    }

    static func atajos(ahora: Date, calendario: Calendar = .current) -> [Atajo] {
        [
            Atajo(titulo: "Dentro de 10 minutos", cuando: ahora.addingTimeInterval(10 * 60)),
            Atajo(titulo: "Dentro de 1 hora", cuando: ahora.addingTimeInterval(60 * 60)),
            Atajo(titulo: "Dentro de 3 horas", cuando: ahora.addingTimeInterval(3 * 60 * 60)),
            Atajo(titulo: "Esta tarde (18:00)", cuando: aLas(18, 0, dias: 0, ahora: ahora, calendario: calendario)),
            Atajo(titulo: "Mañana (9:00)", cuando: aLas(9, 0, dias: 1, ahora: ahora, calendario: calendario)),
        ]
    }

    /// La proxima vez que el reloj marque `hora:minuto`, `dias` despues de
    /// hoy. Si ya paso, la de manana: «esta tarde» a las ocho de la noche
    /// no puede ser una hora que ya fue.
    static func aLas(_ hora: Int, _ minuto: Int, dias: Int, ahora: Date, calendario: Calendar = .current) -> Date {
        let hoy = calendario.startOfDay(for: ahora)
        var cuando = calendario.date(byAdding: DateComponents(day: dias, hour: hora, minute: minuto), to: hoy) ?? ahora
        if cuando <= ahora {
            cuando = calendario.date(byAdding: .day, value: 1, to: cuando) ?? cuando
        }
        return cuando
    }

    /// «Elegir la hora…»: `18:30`, `18.30`, `18h30`, `1830`, `930` (las
    /// 9:30), `9` y `18` (en punto), como la proxima vez que el reloj la
    /// marque. `nil` si no es una hora (`25:00`, `9:75`, letras).
    static func horaEscrita(_ escrito: String, ahora: Date, calendario: Calendar = .current) -> Date? {
        let limpio = escrito.trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty, limpio.allSatisfy(\.isASCII) else { return nil }
        let h: Substring
        let m: Substring
        if let corte = limpio.firstIndex(where: { ":. h".contains($0) }) {
            h = limpio[..<corte]
            m = limpio[limpio.index(after: corte)...]
        } else if limpio.count >= 3 {
            h = limpio.dropLast(2)
            m = limpio.suffix(2)
        } else {
            h = Substring(limpio)
            m = "00"
        }
        func cifras(_ t: Substring) -> Int? {
            let t = t.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 2, t.allSatisfy(\.isNumber) else { return nil }
            return Int(t)
        }
        guard let hora = cifras(h) else { return nil }
        let mt = m.trimmingCharacters(in: .whitespaces)
        // `18:` a medio escribir es las 18 en punto.
        guard let minuto = mt.isEmpty ? 0 : cifras(Substring(mt)) else { return nil }
        guard hora <= 23, minuto <= 59 else { return nil }
        return aLas(hora, minuto, dias: 0, ahora: ahora, calendario: calendario)
    }

    /// Para leerla: «18:00» si es de hoy y «21/09 09:00» si no.
    static func legible(_ cuando: Date, ahora: Date, calendario: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendario
        f.timeZone = calendario.timeZone
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = calendario.isDate(cuando, inSameDayAs: ahora) ? "HH:mm" : "dd/MM HH:mm"
        return f.string(from: cuando)
    }

    /// Lo que se ensena al vencer (`Mensaje::resumen`).
    static func resumen(de m: MensajeChat) -> String {
        let r = m.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? (m.nombre.isEmpty ? "Recordatorio" : m.nombre) : r
    }
}

/// El aviso del sistema de un recordatorio puesto desde este Mac. El vigia
/// que vuelve a ponerlos al arrancar y tras sincronizar es la tanda A4.
@MainActor
enum RecordatoriosDeMensajes {
    static func identificador(chat: String, id: String) -> String { "recuerdaEn:\(chat):\(id)" }

    /// Solo dentro de una `.app` (sin paquete se cae, como en `AvisosMini`).
    private static var centro: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            ? UNUserNotificationCenter.current() : nil
    }

    static func programar(chat: String, id: String, texto: String, cuando: Date) {
        guard let centro, cuando > Date() else { return }
        centro.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let contenido = UNMutableNotificationContent()
        contenido.title = "Recordatorio"
        contenido.body = texto
        contenido.sound = .default
        let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: cuando)
        let peticion = UNNotificationRequest(identifier: identificador(chat: chat, id: id), content: contenido,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: partes, repeats: false))
        centro.add(peticion) { _ in }
    }

    static func cancelar(chat: String, id: String) {
        centro?.removePendingNotificationRequests(withIdentifiers: [identificador(chat: chat, id: id)])
    }
}

// MARK: - La hoja de escribir una linea

/// Escribir la descripcion, el nombre o la hora: una linea, Intro guarda y
/// Esc lo deja como estaba (la barra de Windows).
struct HojaEscritura: View {
    let escritura: Escritura
    let guardar: (String) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""
    @FocusState private var enfocado: Bool

    private var titulo: String {
        switch escritura {
        case let .describir(m):
            m.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Añadir descripción" : "Editar descripción"
        case .renombrar: "Cambiar el nombre"
        case .hora: "Avisar a las"
        }
    }

    private var etiqueta: String {
        switch escritura {
        case .describir: "Descripción:"
        case .renombrar: "Nombre:"
        case .hora: "Hora:"
        }
    }

    private var pie: String {
        switch escritura {
        case .hora:
            if texto.isEmpty { return "Escribe la hora · Intro la pone · Esc la deja" }
            if let c = HorasDeRecordar.horaEscrita(texto, ahora: Date()) {
                return "Intro: \(HorasDeRecordar.legible(c, ahora: Date()))"
            }
            return "Eso no es una hora: escríbela como 18:30"
        case .renombrar: return "Intro guarda · Esc deja el de antes"
        case .describir: return "Intro guarda · Esc lo deja como estaba"
        }
    }

    private var vale: Bool {
        switch escritura {
        case .hora: HorasDeRecordar.horaEscrita(texto, ahora: Date()) != nil
        case .renombrar: !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .describir: true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).font(.headline)
            HStack {
                Text(etiqueta).foregroundStyle(.secondary)
                TextField(etiqueta, text: $texto, prompt: escritura.esHora ? Text("18:30") : nil)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($enfocado)
                    .onSubmit(hecho)
            }
            Text(pie).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { cerrar() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar", action: hecho)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vale)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            switch escritura {
            case let .describir(m): texto = m.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            case let .renombrar(m): texto = ChatAbierto.nombreParaEscribir(m)
            case .hora: texto = ""
            }
            enfocado = true
        }
    }

    private func hecho() {
        guard vale else { return }
        guardar(texto)
        cerrar()
    }
}

private extension Escritura {
    var esHora: Bool {
        if case .hora = self { return true }
        return false
    }
}

// MARK: - Las piezas de la burbuja y del chat

/// A quien responde un mensaje, encima de su burbuja (la cita de Windows):
/// una raya de color y su resumen. Un clic lleva a el.
struct CitaDeMensaje: View {
    let citado: MensajeChat?
    let irA: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 3)
            Text(citado.map { $0.resumen.isEmpty ? $0.nombre : $0.resumen } ?? "Mensaje que ya no está")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: 320, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if citado != nil { irA() } }
        .help("Ir al mensaje")
    }
}

/// Las marcas de la burbuja junto a la hora: fijado, recordatorio y su
/// etiqueta.
struct MarcasDeMensaje: View {
    let mensaje: MensajeChat

    var body: some View {
        HStack(spacing: 4) {
            if mensaje.fijado {
                Image(systemName: "flag.fill").help("Fijado arriba")
            }
            if let ms = mensaje.recuerdaEn {
                let cuando = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
                Label(HorasDeRecordar.legible(cuando, ahora: Date()), systemImage: "alarm")
                    .help("Recordatorio")
            }
            if let e = mensaje.emoji, !e.isEmpty {
                Text(e)
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}

/// La barra de encima de la caja mientras se responde: a quien, y su aspa
/// (Esc tambien la quita).
struct BarraDeRespuesta: View {
    let citado: MensajeChat
    let cancelar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.tint)
            RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Respondiendo").font(.caption.weight(.medium)).foregroundStyle(.tint)
                Text(citado.resumen.isEmpty ? citado.nombre : citado.resumen)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: cancelar) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dejar de responder (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// «Mensaje fijado», arriba del chat: el ultimo fijado de lo cargado. Un
/// clic lleva a el.
struct BarraDeFijado: View {
    let fijado: MensajeChat
    let irA: () -> Void

    var body: some View {
        Button(action: irA) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mensaje fijado").font(.caption.weight(.medium)).foregroundStyle(.tint)
                    Text(fijado.resumen.isEmpty ? fijado.nombre : fijado.resumen)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// El aviso de un momento abajo del chat.
struct AvisoDelChat: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 2)
            .padding(.bottom, 8)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

// MARK: - La ficha de una leccion nueva

/// La ficha «Nueva lección» en su ventana, ya escrita desde un mensaje.
@MainActor
final class VentanasDeLeccion {
    static let compartidas = VentanasDeLeccion()
    private var abiertas: [NSWindow] = []

    func nueva(_ b: BorradorLeccion, nucleo: Nucleo) {
        let modelo = ModeloLecciones(nucleo: nucleo)
        let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
        ventana.title = "Nueva lección"
        ventana.isReleasedWhenClosed = false
        let cerrar: (FichaLeccion?) -> Void = { [weak ventana] _ in ventana?.close() }
        ventana.contentView = NSHostingView(rootView: FichaLeccionVista(modelo: modelo, ficha: nil, inicial: b, alAcabar: cerrar))
        ventana.center()
        abiertas.append(ventana)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: ventana, queue: .main) { [weak self] aviso in
            MainActor.assumeIsolated {
                self?.abiertas.removeAll { $0 === aviso.object as? NSWindow }
            }
        }
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - En el almacen

extension Almacen {
    /// Escribe una nota que contesta a `respondeA` (Responder, R) y la anade
    /// al final de lo cargado, como `escribir(nota:en:)`.
    @discardableResult
    func escribir(nota: String, en chat: String, respondeA: String?) async -> MensajeChat? {
        guard let respondeA, !respondeA.isEmpty else { return await escribir(nota: nota, en: chat) }
        let texto = nota.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return nil }
        let nucleo = self.nucleo
        do {
            let m = try await Task.detached(priority: .userInitiated) {
                try nucleo.escribirNota(chat: chat, texto: texto, respondeA: respondeA)
            }.value
            if quedanPosteriores(chat: chat) {
                await abrir(chat: chat)
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            } else {
                anadir([m], en: chat)
            }
            return m
        } catch {
            ponerError("\(error)")
            return nil
        }
    }

    /// Cambia un mensaje desde su menu (`Nucleo.cambiarMensaje`) y lo pone
    /// al dia en lo cargado. `nil` si no salio o ya no esta.
    @discardableResult
    func cambiar(mensaje id: String, en chat: String, _ cambio: CambioMensaje) async -> MensajeChat? {
        let nucleo = self.nucleo
        let hecho = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat?, Error> in
            Result { try nucleo.cambiarMensaje(chat: chat, id: id, cambio: cambio) }
        }.value
        switch hecho {
        case let .success(m?):
            sustituir(m, en: chat)
            return m
        case .success(nil):
            return nil
        case let .failure(e):
            ponerError("No se pudo: \(e)")
            return nil
        }
    }

    /// Reenvia mensajes a otro chat (`Nucleo.reenviarMensajes`): cuantos.
    func reenviar(mensajes ids: [String], de chat: String, a destino: String) async -> UInt32 {
        let nucleo = self.nucleo
        let hecho = await Task.detached(priority: .userInitiated) { () -> Result<UInt32, Error> in
            Result { try nucleo.reenviarMensajes(chat: chat, ids: ids, destino: destino) }
        }.value
        switch hecho {
        case let .success(n):
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            await cargarChats()
            return n
        case let .failure(e):
            ponerError("No se pudo reenviar: \(e)")
            return 0
        }
    }
}
