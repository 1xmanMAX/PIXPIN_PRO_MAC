// Tareas: las listas de tareas de TODOS los chats en una ventana, como la de
// Windows. No hay una segunda copia: cada lista es la mini-app `tareas` de
// un mensaje del chat y marcar reescribe ese mensaje (en el nucleo de Rust,
// con `mini::alternar`), que es lo que viaja al movil al sincronizar.
//
// El formato no tiene fecha de vencimiento: la unica fecha es la de
// creacion (`➕ AAAA-MM-DD`). Por eso lo pendiente se agrupa por lo que
// lleva esperando (hoy, esta semana, este mes, mas, sin fecha), la mas vieja
// arriba como en Windows; lo hecho va aparte y plegado.
//
// Lo que si puede llevar una tarea es **la hora de recordarla** (`⏰`, A4):
// se ve en su fila y se pone o se quita con su menu («Recordarmelo» de
// Windows). Va dentro de su texto, asi que viaja; la hace sonar el vigia
// (`Recordatorios`).

import AppKit
import Foundation
import PixPinCore
import SwiftUI

/// Una tarea con su lista, para ensenarla fuera de ella.
public struct TareaConLista: Identifiable, Hashable {
    public let lista: ListaTareas
    public let tarea: Tarea
    public var id: String { "\(lista.chat)/\(lista.mensaje)/\(tarea.indice)" }
}

/// Las tareas pendientes de un grupo.
public struct GrupoPendiente: Identifiable {
    public let grupo: GrupoDeTareas
    public let tareas: [TareaConLista]
    public var id: GrupoDeTareas { grupo }
}

/// Un grupo de lo pendiente por lo que lleva esperando.
public enum GrupoDeTareas: Int, CaseIterable, Identifiable, Comparable {
    case masDeUnMes, esteMes, estaSemana, hoy, sinFecha

    public var id: Int { rawValue }

    public var titulo: String {
        switch self {
        case .masDeUnMes: "Más de un mes"
        case .esteMes: "Este mes"
        case .estaSemana: "Esta semana"
        case .hoy: "Hoy"
        case .sinFecha: "Sin fecha"
        }
    }

    /// El grupo de una tarea por los dias que lleva.
    public static func de(_ t: Tarea) -> GrupoDeTareas {
        guard let d = t.dias else { return .sinFecha }
        switch d {
        case 0: return .hoy
        case 1...7: return .estaSemana
        case 8...31: return .esteMes
        default: return .masDeUnMes
        }
    }

    public static func < (a: GrupoDeTareas, b: GrupoDeTareas) -> Bool { a.rawValue < b.rawValue }
}

@MainActor
public final class ModeloTareas: ObservableObject {
    @Published public private(set) var listas: [ListaTareas] = []
    @Published public private(set) var error: String?
    @Published public private(set) var cargado = false
    /// Lo ultimo borrado, para «Deshacer» (⌘Z).
    @Published public private(set) var borrada: TareaConLista?
    /// Lo que se busca (texto, `#etiqueta`); vacio: todo.
    @Published public var busqueda = ""

    private let nucleo: Nucleo

    public init(nucleo: Nucleo) {
        self.nucleo = nucleo
    }

    /// Lo pendiente de todas las listas por grupos, la mas vieja arriba (y
    /// a igual fecha, el orden de su lista), como `orden_de_pendiente` de
    /// Windows.
    public var pendientesPorGrupo: [GrupoPendiente] {
        var grupos: [GrupoDeTareas: [TareaConLista]] = [:]
        for l in listas {
            for t in l.tareas where !t.hecha && encaja(t) {
                grupos[GrupoDeTareas.de(t), default: []].append(TareaConLista(lista: l, tarea: t))
            }
        }
        return GrupoDeTareas.allCases.compactMap { g in
            guard let v = grupos[g], !v.isEmpty else { return nil }
            let ordenadas = v.sorted { a, b in
                let fa = a.tarea.creada ?? "", fb = b.tarea.creada ?? ""
                if fa != fb { return fa < fb }
                return a.tarea.indice < b.tarea.indice
            }
            return GrupoPendiente(grupo: g, tareas: ordenadas)
        }
    }

    /// Lo hecho, en el orden de sus listas.
    public var hechas: [TareaConLista] {
        listas.flatMap { l in l.tareas.filter(\.hecha).filter(encaja).map { TareaConLista(lista: l, tarea: $0) } }
    }

    /// Si una tarea encaja con lo buscado: todas las palabras, sin tildes
    /// ni mayusculas, en su texto o en su lista.
    public func encaja(_ t: Tarea) -> Bool {
        ModeloTareas.encaja(t.crudo, busqueda)
    }

    nonisolated static func encaja(_ texto: String, _ busqueda: String) -> Bool {
        let opciones: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return busqueda.split(separator: " ").allSatisfy { texto.range(of: $0, options: opciones) != nil }
    }

    /// Las listas que se ven (las de lo buscado), con sus tareas filtradas.
    public var listasFiltradas: [ListaTareas] {
        guard !busqueda.trimmingCharacters(in: .whitespaces).isEmpty else { return listas }
        return listas.compactMap { l in
            var x = l
            x.tareas = l.tareas.filter(encaja)
            return x.tareas.isEmpty ? nil : x
        }
    }

    /// Hace un cambio en el nucleo y relee; si la lista cambio fuera, lo
    /// dice.
    private func cambiar(chat: String, _ hacer: @escaping @Sendable (Nucleo) throws -> Bool) async -> Bool {
        let nucleo = self.nucleo
        var aviso: String?
        var hecho = false
        do {
            hecho = try await Task.detached(priority: .userInitiated) { try hacer(nucleo) }.value
            if hecho {
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: chat)
            } else {
                aviso = "La lista cambió: se ha vuelto a leer"
            }
        } catch {
            aviso = "\(error)"
        }
        await cargar()
        if let aviso { error = aviso }
        return hecho
    }

    /// **Corrige el texto** de una tarea (F2), entendido como al apuntarla.
    public func editar(_ t: TareaConLista, a nuevo: String) async {
        let limpio = nuevo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, limpio != t.tarea.texto else { return }
        let (chat, lista, i, crudo, d) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo, desfaseLocalMs())
        _ = await cambiar(chat: chat) {
            try $0.editarTarea(chat: chat, lista: lista, indice: i, crudo: crudo, nuevo: limpio, desfaseMs: d)
        }
    }

    /// **Borra** una tarea; se puede deshacer hasta el siguiente borrado.
    public func borrar(_ t: TareaConLista) async {
        let (chat, lista, i, crudo) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo)
        if await cambiar(chat: chat, { try $0.borrarTarea(chat: chat, lista: lista, indice: i, crudo: crudo) }) {
            borrada = t
        }
    }

    /// Vuelve a poner lo ultimo borrado en su sitio.
    public func deshacer() async {
        guard let t = borrada else { return }
        borrada = nil
        let (chat, lista, i, crudo, hecha) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo, t.tarea.hecha)
        _ = await cambiar(chat: chat) {
            try $0.devolverTarea(chat: chat, lista: lista, indice: i, crudo: crudo, hecha: hecha)
            return true
        }
    }

    /// **Pasa una tarea a otra lista** («Mover a…», o soltarla en otra
    /// columna del Kanban).
    public func mover(_ t: TareaConLista, a destino: ListaTareas) async {
        guard destino.mensaje != t.lista.mensaje || destino.chat != t.lista.chat else { return }
        let (chat, lista, i, crudo) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo)
        let (aChat, aLista) = (destino.chat, destino.mensaje)
        if await cambiar(chat: chat, {
            try $0.moverTarea(chat: chat, lista: lista, indice: i, crudo: crudo, aChat: aChat, aLista: aLista)
        }) {
            NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: aChat)
        }
    }

    /// Las asignaturas del horario (donde tambien se puede apuntar).
    public var asignaturas: [String] { nucleo.nombresDeAsignaturas(desfaseMs: desfaseLocalMs()) }

    /// Fija la tarea en la pantalla (su pin, con la nota).
    public func pinear(_ t: TareaConLista) {
        let titulo = marcasDeTarea(texto: t.tarea.crudo, desfaseMs: desfaseLocalMs()).titulo
        PinesDeTareas.compartidos.abrir(chat: t.lista.chat, lista: t.lista.mensaje, titulo: titulo, nucleo: nucleo)
    }

    /// La tarea de un id (`chat/lista/indice`), para soltarla en el Kanban.
    public func tarea(id: String) -> TareaConLista? {
        for l in listas {
            for t in l.tareas where TareaConLista(lista: l, tarea: t).id == id {
                return TareaConLista(lista: l, tarea: t)
            }
        }
        return nil
    }

    public func cargar() async {
        let nucleo = self.nucleo
        let desfase = desfaseLocalMs()
        do {
            listas = try await Task.detached(priority: .userInitiated) {
                try nucleo.tareas(desfaseMs: desfase)
            }.value
            error = nil
        } catch {
            self.error = "\(error)"
        }
        cargado = true
    }

    /// Pone una tarea como hecha o pendiente en su mensaje. Si la lista
    /// cambio fuera (el numero ya es otra tarea), no se toca y se relee.
    public func marcar(_ t: TareaConLista, hecha: Bool) async {
        let nucleo = self.nucleo
        let (chat, mensaje, indice, crudo) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo)
        // El aviso se pone DESPUES de releer: `cargar` limpia el error al
        // leer bien, y el usuario tiene que saber que su clic no se aplico.
        var aviso: String?
        do {
            let hecho = try await Task.detached(priority: .userInitiated) {
                try nucleo.marcarTarea(chat: chat, mensaje: mensaje, indice: indice, crudo: crudo, hecha: hecha)
            }.value
            if hecho {
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                // Las tareas, al instante a los otros aparatos.
                NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: chat)
            } else {
                aviso = "La lista cambió: se ha vuelto a leer"
            }
        } catch {
            aviso = "\(error)"
        }
        await cargar()
        if let aviso { error = aviso }
    }

    /// **Pone o quita la hora de recordar** una tarea (`nil` la quita).
    /// Como al marcar, si la lista cambio fuera no se toca y se relee.
    public func recordar(_ t: TareaConLista, en cuando: Date?) async {
        let nucleo = self.nucleo
        let (chat, mensaje, indice, crudo) = (t.lista.chat, t.lista.mensaje, t.tarea.indice, t.tarea.crudo)
        let local = cuando.map(milisegundosLocales)
        var aviso: String?
        do {
            let hecho = try await Task.detached(priority: .userInitiated) {
                try nucleo.ponerHoraTarea(chat: chat, lista: mensaje, indice: indice, crudo: crudo,
                                          cuandoLocalMs: local)
            }.value
            if hecho {
                // Al vigia (que relee al oirlo) y a los otros aparatos.
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: chat)
            } else {
                aviso = "La lista cambió: se ha vuelto a leer"
            }
        } catch {
            aviso = "\(error)"
        }
        await cargar()
        if let aviso { error = aviso }
    }

    /// Apunta una tarea en el Inbox de «Mensajes guardados», con sus
    /// imagenes (pegadas o soltadas en la caja) si las hay.
    public func apuntar(_ texto: String, imagenes: [URL] = [], asignatura: String = "") async {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty || !imagenes.isEmpty else { return }
        let rutas = imagenes.map(\.path)
        let nucleo = self.nucleo
        let desfase = desfaseLocalMs()
        do {
            let lista = try await Task.detached(priority: .userInitiated) {
                asignatura.isEmpty
                    ? try nucleo.apuntarTareaConImagenes(texto: limpio, imagenes: rutas, desfaseMs: desfase)
                    : try nucleo.apuntarEnAsignatura(asignatura: asignatura, texto: limpio, imagenes: rutas,
                                                     desfaseMs: desfase)
            }.value
            error = nil
            // Con hora: directamente su pin en la pantalla (Windows).
            let m = marcasDeTarea(texto: tareaEntendida(texto: limpio, desfaseMs: desfase), desfaseMs: desfase)
            if m.horaMs != nil, !m.titulo.isEmpty {
                PinesDeTareas.compartidos.abrir(chat: lista.chat, lista: lista.mensaje, titulo: m.titulo, nucleo: nucleo)
            }
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: lista.chat)
        } catch {
            self.error = "\(error)"
        }
        await cargar()
    }
}

// MARK: - La ventana

public struct VentanaTareas: View {
    public enum Vista: String, CaseIterable, Identifiable {
        case porFecha = "Por fecha"
        case porLista = "Por lista"
        /// Cada lista una columna; arrastrar una tarjeta la pasa a otra
        /// lista (Windows, 17-oct).
        case kanban = "Kanban"
        public var id: String { rawValue }
    }

    @StateObject private var modelo: ModeloTareas
    @AppStorage("PixPinTareasVista") private var vista: Vista = .porFecha
    @State private var nueva = ""
    @State private var verHechas = false
    /// Las imagenes que iran con la tarea que se apunta.
    @State private var imagenes: [URL] = []
    /// Donde se apunta: vacio el Inbox, o una asignatura (Windows, 18-oct).
    @State private var destino = ""

    public init(almacen: Almacen) {
        _modelo = StateObject(wrappedValue: ModeloTareas(nucleo: almacen.nucleo))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // La barra comun de Windows (`Cabecera`): las vistas y releer.
            Cabecera("Tareas", subtitulo: modelo.listas.count == 1 ? "1 lista" : "\(modelo.listas.count) listas") {
                SegmentosCabecera(Vista.allCases.map { ($0, $0.rawValue) }, eleccion: $vista)
                BotonCabecera(icono: "arrow.clockwise", ayuda: "Releer (⌘R)") { Task { await modelo.cargar() } }
                    .keyboardShortcut("r")
            }
            HStack {
                TextField("Apuntar en el Inbox (urgente, #etiqueta, recordar a las 5)", text: $nueva)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(apuntar)
                if !imagenes.isEmpty {
                    Label("\(imagenes.count)", systemImage: "photo")
                        .help(imagenes.map(\.lastPathComponent).joined(separator: "\n"))
                        .onTapGesture { imagenes = [] }
                }
                let asignaturas = modelo.asignaturas
                if !asignaturas.isEmpty {
                    Picker("", selection: $destino) {
                        Text("Inbox").tag("")
                        ForEach(asignaturas, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    .help("Apuntar en el Inbox o en la lista de una asignatura")
                }
                Button { pegarImagen() } label: { Image(systemName: "photo.badge.plus") }
                    .help("Pegar una imagen del portapapeles (o suelta imágenes en la caja)")
                Button("Apuntar", action: apuntar)
                    .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty && imagenes.isEmpty)
                TextField("Buscar", text: $modelo.busqueda)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            .padding(10)
            .dropDestination(for: URL.self) { urls, _ in
                let fotos = urls.filter { ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains($0.pathExtension.lowercased()) }
                imagenes += fotos
                return !fotos.isEmpty
            }
            Divider()
            Group {
                switch vista {
                case .porFecha: List { porFecha }
                case .porLista: List { porLista }
                case .kanban: TableroKanban(modelo: modelo)
                }
            }
            .overlay {
                if modelo.cargado, modelo.listas.allSatisfy({ $0.tareas.isEmpty }) {
                    ContentUnavailableView("Sin tareas", systemImage: "checklist",
                                           description: Text("Las listas de tareas de tus chats aparecen aquí."))
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                if let t = modelo.borrada {
                    HStack {
                        Text("Borrada: \(t.tarea.texto)").lineLimit(1)
                        Button("Deshacer (⌘Z)") { Task { await modelo.deshacer() } }
                            .keyboardShortcut("z")
                    }
                    .font(.callout)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                if let e = modelo.error {
                    Text(e).font(.caption).padding(6)
                        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
        }
        .ventanaConCabecera()
        .task { await modelo.cargar() }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func fila(_ t: TareaConLista, conLista: Bool) -> FilaTarea {
        FilaTarea(t: t, conLista: conLista, listas: modelo.listas, acciones: acciones(t))
    }

    private func acciones(_ t: TareaConLista) -> AccionesTarea {
        AccionesTarea(
            marcar: { h in Task { await modelo.marcar(t, hecha: h) } },
            recordar: { c in Task { await modelo.recordar(t, en: c) } },
            editar: { n in Task { await modelo.editar(t, a: n) } },
            borrar: { Task { await modelo.borrar(t) } },
            mover: { l in Task { await modelo.mover(t, a: l) } },
            pinear: { modelo.pinear(t) }
        )
    }

    @ViewBuilder
    private var porFecha: some View {
        ForEach(modelo.pendientesPorGrupo) { g in
            Section(g.grupo.titulo) {
                ForEach(g.tareas) { t in fila(t, conLista: true) }
            }
        }
        let hechas = modelo.hechas
        if !hechas.isEmpty {
            Section {
                DisclosureGroup("Hechas (\(hechas.count))", isExpanded: $verHechas) {
                    ForEach(hechas) { t in fila(t, conLista: true) }
                }
            }
        }
    }

    @ViewBuilder
    private var porLista: some View {
        ForEach(modelo.listasFiltradas, id: \.mensaje) { l in
            Section {
                ForEach(l.tareas, id: \.indice) { t in fila(TareaConLista(lista: l, tarea: t), conLista: false) }
            } header: {
                CabeceraLista(l: l)
            }
        }
    }

    private func apuntar() {
        let texto = nueva
        let fotos = imagenes
        nueva = ""
        imagenes = []
        let donde = destino
        Task { await modelo.apuntar(texto, imagenes: fotos, asignatura: donde) }
    }

    /// La imagen del portapapeles, a un PNG temporal para la tarea.
    private func pegarImagen() {
        guard let img = NSImage(pasteboard: .general), let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return NSSound.beep()
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pegada-\(UUID().uuidString).png")
        if (try? png.write(to: url)) != nil { imagenes.append(url) }
    }
}

/// El titulo de una lista, su chat y cuantas van hechas.
struct CabeceraLista: View {
    let l: ListaTareas

    var body: some View {
        HStack {
            Text(l.titulo.isEmpty ? "Tareas" : l.titulo).bold()
            Text(l.guardados ? "Mensajes guardados" : l.nombreChat).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("\(l.tareas.count - Int(l.pendientes)) de \(l.tareas.count)").monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Lo que se puede hacer con una tarea desde su fila o su tarjeta.
struct AccionesTarea {
    var marcar: (Bool) -> Void = { _ in }
    /// Poner la hora de recordarla (`nil` la quita).
    var recordar: (Date?) -> Void = { _ in }
    var editar: (String) -> Void = { _ in }
    var borrar: () -> Void = {}
    var mover: (ListaTareas) -> Void = { _ in }
    var pinear: () -> Void = {}
}

/// Una tarea: su casilla, el texto con sus #etiquetas y sus chapitas
/// (prioridad primero), su hora de recordar, cuantos dias lleva y, si se
/// pide, su lista y su chat. Doble clic o F2 la corrige; su menu la
/// recuerda, la mueve o la borra.
struct FilaTarea: View {
    let t: TareaConLista
    let conLista: Bool
    var listas: [ListaTareas] = []
    var acciones = AccionesTarea()
    @State private var editando = false
    @State private var texto = ""
    @FocusState private var foco: Bool

    private var marcas: MarcasTarea { marcasDeTarea(texto: t.tarea.texto, desfaseMs: desfaseLocalMs()) }

    var body: some View {
        let m = marcas
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(get: { t.tarea.hecha }, set: { acciones.marcar($0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                if editando {
                    TextField("Tarea", text: $texto)
                        .textFieldStyle(.roundedBorder)
                        .focused($foco)
                        .onSubmit {
                            editando = false
                            acciones.editar(texto)
                        }
                        .onExitCommand { editando = false }
                } else {
                    HStack(spacing: 4) {
                        ForEach(m.chapitas, id: \.self) { Text($0) }
                        Text(m.vista.isEmpty ? "(sin texto)" : m.vista)
                            .strikethrough(t.tarea.hecha)
                            .foregroundStyle(t.tarea.hecha ? Color.secondary : Color.primary)
                        // La urgencia y las #etiquetas, en chapitas aparte
                        // (Windows, 18-oct).
                        if let u = m.urgencia {
                            ChapitaTarea(texto: (m.marcaUrgencia ?? "") + (u == "muy_urgente" ? " muy urgente" : " urgente"),
                                    color: u == "muy_urgente" ? .red : .orange)
                        }
                        ForEach(m.etiquetas, id: \.self) { ChapitaTarea(texto: "#\($0)", color: .accentColor) }
                    }
                    .onTapGesture(count: 2) { empezar() }
                }
                if conLista {
                    Text("\(t.lista.titulo) · \(t.lista.guardados ? "Mensajes guardados" : t.lista.nombreChat)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !t.tarea.imagenes.isEmpty {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .help("\(t.tarea.imagenes.count) imágenes")
            }
            if let d = t.tarea.dias, !t.tarea.hecha {
                Text(d == 0 ? "hoy" : "\(d) d")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(d > 7 ? Color.orange : Color.secondary)
                    .help("Creada el \(t.tarea.creada ?? "")")
            }
        }
        .contentShape(Rectangle())
        .onKeyPress(.init("\u{F70F}")) { // F2
            empezar()
            return .handled
        }
        .contextMenu {
            Button("Corregir (F2)") { empezar() }
            if !t.tarea.hecha { Button("Pinear en la pantalla") { acciones.pinear() } }
            if !t.tarea.hecha {
                Menu("Recordármelo") {
                    ForEach(AtajosDeHora.atajos(ahora: Date()), id: \.titulo) { a in
                        Button(a.titulo) { acciones.recordar(a.cuando) }
                    }
                }
            }
            if t.tarea.recuerda != nil {
                Button("Quitar el recordatorio") { acciones.recordar(nil) }
            }
            let otras = listas.filter { $0.mensaje != t.lista.mensaje || $0.chat != t.lista.chat }
            if !otras.isEmpty {
                Menu("Mover a…") {
                    ForEach(otras, id: \.mensaje) { l in
                        Button("\(l.titulo.isEmpty ? "Tareas" : l.titulo) · \(l.guardados ? "Mensajes guardados" : l.nombreChat)") {
                            acciones.mover(l)
                        }
                    }
                }
            }
            Divider()
            Button("Borrar", role: .destructive) { acciones.borrar() }
        }
    }

    private func empezar() {
        texto = t.tarea.texto
        editando = true
        foco = true
    }
}

// MARK: - Kanban

/// **El tablero Kanban** (Windows, 17-oct): cada lista una columna con lo
/// pendiente arriba y lo hecho plegado al pie. Arrastrar una tarjeta a otra
/// columna la pasa a esa lista. Lo que no cabe a lo ancho baja a otra
/// banda: nunca hay que desplazarse de lado.
struct TableroKanban: View {
    @ObservedObject var modelo: ModeloTareas

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(modelo.listasFiltradas, id: \.mensaje) { l in
                    ColumnaKanban(l: l, modelo: modelo)
                }
            }
            .padding(12)
        }
    }
}

struct ColumnaKanban: View {
    let l: ListaTareas
    @ObservedObject var modelo: ModeloTareas
    @State private var encima = false
    @State private var verHechas = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CabeceraLista(l: l).font(.callout)
            ForEach(l.tareas.filter { !$0.hecha }, id: \.indice) { t in tarjeta(t) }
            let hechas = l.tareas.filter(\.hecha)
            if !hechas.isEmpty {
                DisclosureGroup("Hechas (\(hechas.count))", isExpanded: $verHechas) {
                    ForEach(hechas, id: \.indice) { t in tarjeta(t) }
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color.secondary.opacity(encima ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids {
                if let t = modelo.tarea(id: id) { Task { await modelo.mover(t, a: l) } }
            }
            return true
        } isTargeted: { encima = $0 }
    }

    private func tarjeta(_ t: Tarea) -> some View {
        let x = TareaConLista(lista: l, tarea: t)
        return FilaTarea(t: x, conLista: false, listas: modelo.listas, acciones: AccionesTarea(
            marcar: { h in Task { await modelo.marcar(x, hecha: h) } },
            recordar: { c in Task { await modelo.recordar(x, en: c) } },
            editar: { n in Task { await modelo.editar(x, a: n) } },
            borrar: { Task { await modelo.borrar(x) } },
            mover: { d in Task { await modelo.mover(x, a: d) } },
            pinear: { modelo.pinear(x) }
        ))
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .draggable(x.id)
    }
}


/// Una chapita de una tarea (su urgencia o una etiqueta).
struct ChapitaTarea: View {
    let texto: String
    let color: Color

    var body: some View {
        Text(texto)
            .font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
