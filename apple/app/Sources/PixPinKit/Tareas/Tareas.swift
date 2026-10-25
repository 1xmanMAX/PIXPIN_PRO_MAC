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
//
// **Tres vistas** (Windows 5139e5d, 25-oct-2026): Tarjetas (cada lista con
// sus cuadrados y la foto de fondo), Kanban (una columna por lista) y
// Horario (el calendario semanal de las clases, `VentanaHorario`, con las
// tareas con hora como chapitas). La Lista se quito; quien la tenia abre
// en las tarjetas. Lo puro de las vistas (su palabra, su atajo, el ancho,
// donde va cada cosa del horario) es del nucleo (`vista_tareas.rs`).

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

    /// Lo pendiente con hora (`⏰`) de todas las listas, para las chapitas
    /// de la semana del Horario (sin lo buscado: la semana es entera).
    public var conHora: [TareaConLista] {
        listas.flatMap { l in
            l.tareas.filter { !$0.hecha && $0.recuerda != nil }.map { TareaConLista(lista: l, tarea: $0) }
        }
    }

    /// La lista de tareas de una asignatura del horario, si ya tiene.
    public func listaDeAsignatura(_ nombre: String) -> ListaTareas? {
        nucleo.listaDeAsignatura(listas: listas, asignatura: nombre)
    }

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

/// Lo que el Mac ensena de cada vista en la barra (la palabra que se
/// guarda y el atajo los da el nucleo, `pixpin_ui::vista_tareas`).
public extension VistaTareas {
    /// En el orden del conmutador.
    static let todas: [VistaTareas] = [.tarjetas, .kanban, .horario]

    var rotulo: String {
        switch self {
        case .tarjetas: "Tarjetas"
        case .kanban: "Kanban"
        case .horario: "Horario"
        }
    }

    /// La letra del atajo, que en el Mac va con ⌃⌘ (⌘H oculta la app y
    /// ⌥⌘H las demas; en Windows es Ctrl+T, Ctrl+K y Ctrl+H).
    var letraAtajo: Character { Character(vistaTareasAtajo(vista: self).lowercased()) }

    /// «Tarjetas · ⌃⌘T», la pista del conmutador (`tareas5-vista-*`).
    var pista: String {
        let nombre = self == .kanban ? "Tablero Kanban" : rotulo
        return "\(nombre) · ⌃⌘\(vistaTareasAtajo(vista: self))"
    }
}

public struct VentanaTareas: View {
    @StateObject private var modelo: ModeloTareas
    /// El horario semanal de la vista Horario.
    @StateObject private var semana: ModeloSemana
    /// La vista elegida, con la palabra de Windows (`tareas-vista.txt`):
    /// lo que el Mac guardaba antes («Por fecha», «Por lista») abre en las
    /// tarjetas.
    @AppStorage("PixPinTareasVista") private var vistaGuardada = "tarjetas"
    /// En el Horario, si se ve el domingo (el boton de la barra).
    @AppStorage("PixPinHorarioDomingo") private var conDomingo = false
    @State private var nueva = ""
    /// Las imagenes que iran con la tarea que se apunta.
    @State private var imagenes: [URL] = []
    /// Donde se apunta: vacio el Inbox, o una asignatura (Windows, 18-oct).
    @State private var destino = ""
    /// La tarea que se ensena en las tarjetas (una chapita del Horario).
    @State private var resaltada: String?

    /// La lista que pidio el chat antes de que la ventana existiera.
    static var listaPedida: String?
    // La vista pedida desde fuera (el mosaico Horario de Funciones,
    // «Horario de clases…») es `VentanaTareas.vistaPedida` y
    // `VentanaTareas.abrir(vista:)`, en `FuncionesDeLaLista.swift`.

    private var vista: VistaTareas { vistaTareasDeTexto(texto: vistaGuardada) }

    private func cambiarVista(_ v: VistaTareas) {
        if v == .horario, vista != .horario { semana.abrir() }
        vistaGuardada = vistaTareasComoTexto(vista: v)
    }

    private var eleccion: Binding<VistaTareas> {
        Binding(get: { vista }, set: { cambiarVista($0) })
    }

    private func irALista(_ nombre: String?) {
        guard let nombre else { return }
        VentanaTareas.listaPedida = nil
        modelo.busqueda = nombre
        cambiarVista(.tarjetas)
    }

    private func irAVista(_ texto: String?) {
        guard let texto else { return }
        VentanaTareas.vistaPedida = nil
        cambiarVista(vistaTareasDeTexto(texto: texto))
    }

    public init(almacen: Almacen) {
        _modelo = StateObject(wrappedValue: ModeloTareas(nucleo: almacen.nucleo))
        _semana = StateObject(wrappedValue: ModeloSemana(nucleo: almacen.nucleo))
    }

    public var body: some View {
        VStack(spacing: 0) {
            cabecera
            if vista == .horario {
                VentanaHorario(modelo: semana, tareas: modelo, dias: conDomingo ? 7 : 6,
                               alPulsarTarea: { t in
                                   // La chapita: esa tarea en las tarjetas.
                                   modelo.busqueda = ""
                                   resaltada = t.id
                                   cambiarVista(.tarjetas)
                               },
                               abrirEnTareas: { nombre in
                                   // Sus tarjetas, y lo apuntado va a su lista.
                                   destino = nombre
                                   modelo.busqueda = nombre
                                   cambiarVista(.tarjetas)
                               })
                    .padding(.horizontal, 0)
            } else {
                apuntarYBuscar
                Divider()
                Group {
                    switch vista {
                    case .kanban: TableroKanban(modelo: modelo)
                    default: RejillaTarjetas(modelo: modelo, resaltada: $resaltada)
                    }
                }
                .overlay {
                    if modelo.cargado, modelo.listas.allSatisfy({ $0.tareas.isEmpty }) {
                        ContentUnavailableView("Sin tareas", systemImage: "checklist",
                                               description: Text("Las listas de tareas de tus chats aparecen aquí."))
                    }
                }
            }
        }
        .background(AnchoDeTareas(vista: vista))
        .background {
            // ⌃⌘T, ⌃⌘K y ⌃⌘H: las vistas (el Ctrl+T/K/H de Windows).
            ForEach(VistaTareas.todas, id: \.self) { v in
                Button("") { cambiarVista(v) }
                    .keyboardShortcut(KeyEquivalent(v.letraAtajo), modifiers: [.control, .command])
                    .hidden()
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
        .onAppear {
            irAVista(VentanaTareas.vistaPedida?.rawValue)
            irALista(VentanaTareas.listaPedida)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixpinAbrirListaTareas)) { irALista($0.object as? String) }
        .onReceive(NotificationCenter.default.publisher(for: .pixpinAbrirVistaTareas)) { irAVista($0.object as? String) }
        .frame(minWidth: 480, minHeight: 400)
    }

    /// La barra comun de Windows (`Cabecera`): el conmutador de vistas y lo
    /// propio de cada una (releer; en el Horario, «Domingo» y «Como texto»).
    private var cabecera: some View {
        let subtitulo = vista == .horario
            ? semana.subtitulo
            : modelo.listas.count == 1 ? "1 lista" : "\(modelo.listas.count) listas"
        return Cabecera("Tareas", subtitulo: subtitulo) {
            SegmentosCabecera(VistaTareas.todas.map { ($0, $0.rotulo) }, eleccion: eleccion)
                .help(VistaTareas.todas.map(\.pista).joined(separator: "\n"))
            if vista == .horario {
                BotonCabecera(rotulo: "Domingo", ayuda: "Ver el domingo", activo: conDomingo) { conDomingo.toggle() }
                BotonCabecera(icono: "pencil", rotulo: "Como texto", ayuda: "Editar el horario como texto") {
                    HorarioClases.abrirTexto(nucleo: semana.nucleo)
                }
            } else {
                BotonCabecera(icono: "arrow.clockwise", ayuda: "Releer (⌘R)") { Task { await modelo.cargar() } }
                    .keyboardShortcut("r")
            }
        }
    }

    /// La caja de apuntar (con sus imagenes y su asignatura) y el buscador.
    private var apuntarYBuscar: some View {
        HStack {
            TextField(destino.isEmpty ? "Apuntar en el Inbox (urgente, #etiqueta, recordar a las 5)"
                                      : "Nueva tarea de \(destino)…", text: $nueva)
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

/// **El ancho de la ventana para cada vista** (Windows): mas ancha en el
/// Horario (la semana necesita sitio) y la de siempre en las otras, con el
/// mismo centro y sin salirse de la pantalla (`marcoDeVistaTareas`).
struct AnchoDeTareas: View {
    let vista: VistaTareas
    @Environment(\.ventanaDeLaVista) private var ventana

    var body: some View {
        Color.clear
            .onChange(of: vista) { _, v in ajustar(v) }
            .onAppear {
                // La ventana se conoce un poco despues de aparecer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ajustar(vista) }
            }
    }

    private func ajustar(_ v: VistaTareas) {
        guard let w = ventana?.ventana, let pantalla = w.screen?.visibleFrame else { return }
        let f = w.frame
        let m = marcoDeVistaTareas(
            actual: MarcoVentanaTareas(x: Int32(f.minX), y: Int32(f.minY), ancho: UInt32(max(1, f.width)),
                                       alto: UInt32(max(1, f.height))),
            trabajo: MarcoVentanaTareas(x: Int32(pantalla.minX), y: Int32(pantalla.minY),
                                        ancho: UInt32(max(1, pantalla.width)), alto: UInt32(max(1, pantalla.height))),
            vista: v)
        let nuevo = NSRect(x: CGFloat(m.x), y: f.minY, width: CGFloat(m.ancho), height: f.height)
        if abs(nuevo.width - f.width) > 1 || abs(nuevo.minX - f.minX) > 1 {
            w.setFrame(nuevo, display: true, animate: true)
        }
    }
}

// MARK: - Tarjetas

/// **Las tarjetas** (tareas-v4 de Windows): cada lista con su encabezado y
/// lo pendiente en cuadrados (una foto de la tarea, de fondo; con varias,
/// los bordes de las de detras), y lo hecho plegado en filas: un cuadrado
/// entero para algo ya tachado pesaba tanto como lo pendiente.
struct RejillaTarjetas: View {
    @ObservedObject var modelo: ModeloTareas
    @Binding var resaltada: String?
    /// Las listas con lo hecho abierto.
    @State private var abiertas: Set<String> = []

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(modelo.listasFiltradas, id: \.mensaje) { l in grupo(l) }
                }
                .padding(12)
            }
            .onChange(of: resaltada) { _, id in
                guard let id else { return }
                withAnimation { lector.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                if let id = resaltada {
                    DispatchQueue.main.async { lector.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func grupo(_ l: ListaTareas) -> some View {
        let pendientes = l.tareas.filter { !$0.hecha }
        let hechas = l.tareas.filter(\.hecha)
        let clave = "\(l.chat)/\(l.mensaje)"
        return VStack(alignment: .leading, spacing: 10) {
            CabeceraLista(l: l).font(.callout)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(pendientes, id: \.indice) { t in
                    let x = TareaConLista(lista: l, tarea: t)
                    TarjetaTarea(t: x, modelo: modelo, resaltada: resaltada == x.id)
                        .id(x.id)
                }
            }
            if !hechas.isEmpty {
                DisclosureGroup("Hechas (\(hechas.count))", isExpanded: Binding(
                    get: { abiertas.contains(clave) || !modelo.busqueda.isEmpty },
                    set: { if $0 { abiertas.insert(clave) } else { abiertas.remove(clave) } })) {
                    ForEach(hechas, id: \.indice) { t in
                        let x = TareaConLista(lista: l, tarea: t)
                        FilaTarea(t: x, conLista: false, listas: modelo.listas, acciones: AccionesTarea.de(x, modelo))
                            .padding(.vertical, 2)
                            .id(x.id)
                    }
                }
                .font(.caption)
            }
        }
    }
}

extension AccionesTarea {
    /// Lo de una tarea, hecho por el modelo de la ventana.
    @MainActor
    static func de(_ x: TareaConLista, _ modelo: ModeloTareas) -> AccionesTarea {
        AccionesTarea(
            marcar: { h in Task { await modelo.marcar(x, hecha: h) } },
            recordar: { c in Task { await modelo.recordar(x, en: c) } },
            editar: { n in Task { await modelo.editar(x, a: n) } },
            borrar: { Task { await modelo.borrar(x) } },
            mover: { d in Task { await modelo.mover(x, a: d) } },
            pinear: { modelo.pinear(x) }
        )
    }
}

/// **Una tarjeta**: la fila de la tarea en un cuadrado, del alto de lo suyo
/// (entre la mitad del lado y el lado), con su primera foto de fondo.
/// Se arrastra a otra columna del Kanban.
struct TarjetaTarea: View {
    let t: TareaConLista
    @ObservedObject var modelo: ModeloTareas
    var resaltada = false
    /// El lado de la tarjeta (`LADO_CUADRADO` de Windows).
    static let lado: CGFloat = 200

    var body: some View {
        let fotos = t.tarea.imagenes
        VStack(alignment: .leading, spacing: 0) {
            FilaTarea(t: t, conLista: false, listas: modelo.listas, acciones: AccionesTarea.de(t, modelo))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: fotos.isEmpty ? Self.lado / 2 : Self.lado,
               maxHeight: Self.lado, alignment: .topLeading)
        .background {
            if let primera = fotos.first {
                FotoDeTarjeta(ruta: primera)
                    .overlay(LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.25)],
                                            startPoint: .top, endPoint: .bottom))
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(resaltada ? Paleta.v2.acento : Color.white.opacity(0.08), lineWidth: resaltada ? 2 : 1)
        }
        // Con varias fotos, los bordes de detras: uno con dos, dos con mas.
        .background(alignment: .topTrailing) {
            ForEach(0 ..< min(2, max(0, fotos.count - 1)), id: \.self) { k in
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.25 - Double(k) * 0.08), lineWidth: 1)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 12))
                    .offset(x: CGFloat(k + 1) * 4, y: -CGFloat(k + 1) * 4)
            }
        }
        .draggable(t.id)
    }
}

/// La foto de fondo de una tarjeta, leida fuera del hilo principal.
struct FotoDeTarjeta: View {
    let ruta: String
    @State private var imagen: NSImage?

    var body: some View {
        GeometryReader { geo in
            if let imagen {
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .task(id: ruta) {
            let ruta = ruta
            let datos = await Task.detached(priority: .utility) { FileManager.default.contents(atPath: ruta) }.value
            imagen = datos.flatMap(NSImage.init(data:))
        }
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
            // Las mismas tarjetas que la vista Tarjetas (con su foto).
            ForEach(l.tareas.filter { !$0.hecha }, id: \.indice) { t in
                TarjetaTarea(t: TareaConLista(lista: l, tarea: t), modelo: modelo)
            }
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
        return FilaTarea(t: x, conLista: false, listas: modelo.listas, acciones: AccionesTarea.de(x, modelo))
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
