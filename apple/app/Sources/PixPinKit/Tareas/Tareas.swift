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
    /// Ya hay una relectura esperando a Jev (`releerTrasJev`).
    private var esperandoAJev = false
    @Published public private(set) var error: String?
    @Published public private(set) var cargado = false
    /// Lo ultimo borrado, para «Deshacer» (⌘Z).
    @Published public private(set) var borrada: TareaConLista?
    /// Lo que se busca (texto, `#etiqueta`, «hoy»); vacio: todo. Busca en
    /// la tarea, su lista y su chat, como Windows (`grupos`).
    @Published public var busqueda = "" {
        didSet { if busqueda != oldValue { reagrupar() } }
    }
    /// **Lo que se ve en Tarjetas y Kanban** (`tarjetas::agrupar` de
    /// Windows, en el nucleo): cada lista con algo que sale, su pendiente
    /// ordenado, sus hechas y su color.
    @Published public private(set) var grupos: [GrupoTareas] = []

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

    private func reagrupar() {
        grupos = gruposDeTareas(listas: listas, busqueda: busqueda, desfaseMs: desfaseLocalMs())
    }

    /// La lista de un grupo.
    public func lista(de g: GrupoTareas) -> ListaTareas? {
        let i = Int(g.lista)
        return listas.indices.contains(i) ? listas[i] : nil
    }

    /// Las tareas de un grupo por sus numeros (los `indice` del documento).
    public func tareas(_ indices: [UInt32], de l: ListaTareas) -> [Tarea] {
        indices.compactMap { i in l.tareas.first { $0.indice == i } }
    }

    /// La lista de una clave (`chat/mensaje`, `Lista::clave` de Windows).
    public func lista(clave: String) -> ListaTareas? {
        listas.first { "\($0.chat)/\($0.mensaje)" == clave }
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
            // Con la prioridad de Jev (sin clave, como siempre).
            listas = try await Task.detached(priority: .userInitiated) {
                try nucleo.tareasConJev(desfaseMs: desfase)
            }.value
            reagrupar()
            error = nil
        } catch {
            self.error = "\(error)"
        }
        cargado = true
        releerTrasJev()
    }

    /// Mientras Jev mira la prioridad de las tareas (en el nucleo, en su
    /// hilo), se relee cada poco para ensenar lo que llega.
    private func releerTrasJev() {
        guard jevPreguntandoTareas(), !esperandoAJev else { return }
        esperandoAJev = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            self.esperandoAJev = false
            await self.cargar()
        }
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
    public func apuntar(_ texto: String, imagenes: [URL] = [], asignatura: String = "",
                        en destino: ListaTareas? = nil) async {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty || !imagenes.isEmpty else { return }
        let rutas = imagenes.map(\.path)
        let nucleo = self.nucleo
        let desfase = desfaseLocalMs()
        do {
            let (chat, mensaje) = (destino?.chat, destino?.mensaje)
            let lista = try await Task.detached(priority: .userInitiated) {
                if let chat, let mensaje {
                    // La lista abierta desde el chat (Windows `apuntar_en`).
                    return try nucleo.apuntarTareaConImagenesEn(chat: chat, mensaje: mensaje, texto: limpio,
                                                                imagenes: rutas, desfaseMs: desfase)
                }
                if asignatura.isEmpty {
                    return try nucleo.apuntarTareaConImagenes(texto: limpio, imagenes: rutas, desfaseMs: desfase)
                }
                return try nucleo.apuntarEnAsignatura(asignatura: asignatura, texto: limpio, imagenes: rutas,
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
    /// La lista abierta desde el chat: lo apuntado va a ella (Windows
    /// `apuntar_en`), hasta que se elija otro destino.
    @State private var apuntarEn: ListaTareas?
    /// La lista pedida que aun no se ha leido (la ventana recien abierta).
    @State private var pedida: String?
    /// La lista a cuyo encabezado se desplaza la vista (su clave).
    @State private var irAEncabezado: String?

    /// La lista que pidio el chat antes de que la ventana existiera: su
    /// clave (`chat/mensaje`, `Lista::clave` de Windows).
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

    /// **Abre una lista pedida** (pulsada en el chat), como Windows: NO se
    /// busca (antes se buscaba por su nombre, y como buscar solo miraba el
    /// texto de cada tarea, la lista salia vacia); se ensenan todas, se
    /// desplaza hasta su encabezado y lo apuntado va a ella. Desde el
    /// Horario pasa a las tarjetas; en Kanban se queda en Kanban.
    private func irALista(_ clave: String?) {
        guard let clave, !clave.isEmpty else { return }
        VentanaTareas.listaPedida = nil
        if vista == .horario { cambiarVista(.tarjetas) }
        if modelo.cargado {
            resolverPedida(clave)
        } else {
            pedida = clave
        }
    }

    /// La pedida, si ya esta leida (si no, se espera a `cargar`).
    private func resolverPedida(_ pedidaAhora: String? = nil) {
        guard let clave = pedidaAhora ?? pedida, modelo.cargado else { return }
        pedida = nil
        // La clave, o (de antes) solo el mensaje o el titulo.
        let mensaje: String = clave.split(separator: "/").last.map(String.init) ?? clave
        let l: ListaTareas? = modelo.lista(clave: clave)
            ?? modelo.listas.first(where: { $0.mensaje == mensaje })
            ?? modelo.listas.first(where: { $0.titulo == clave })
        guard let l else { return }
        modelo.busqueda = ""
        destino = ""
        apuntarEn = l
        irAEncabezado = "\(l.chat)/\(l.mensaje)"
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
                                   apuntarEn = nil
                                   modelo.busqueda = nombre
                                   cambiarVista(.tarjetas)
                               })
                    .padding(.horizontal, 0)
            } else {
                apuntarYBuscar
                Divider()
                Group {
                    switch vista {
                    case .kanban: TableroKanban(modelo: modelo, irAEncabezado: $irAEncabezado)
                    default: RejillaTarjetas(modelo: modelo, resaltada: $resaltada, irAEncabezado: $irAEncabezado)
                    }
                }
                .overlay {
                    if modelo.cargado, modelo.listas.allSatisfy({ $0.tareas.isEmpty }) {
                        // `tareas-vacia` de Windows.
                        ContentUnavailableView("Sin tareas", systemImage: "checklist",
                                               description: Text("Aún no hay tareas. Escribe arriba y pulsa Intro: irá al Inbox y desde ahí la pasas a su grupo."))
                    } else if modelo.cargado, modelo.grupos.isEmpty, !modelo.busqueda.isEmpty {
                        ContentUnavailableView.search(text: modelo.busqueda)
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
        // Oscura siempre, como en Windows: `ventanaConCabecera` pone tambien
        // el `colorScheme` oscuro (sin el, el texto salia negro).
        .ventanaConCabecera()
        .task {
            await modelo.cargar()
            resolverPedida()
        }
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
        // Buscando, cuantas salen (`tareas3-encontradas`); si no, cuantas
        // listas hay (`tareas5-subtitulo`).
        let encontradas: Int = modelo.grupos.reduce(0) { $0 + $1.arriba.count + $1.hechas.count }
        let subtitulo: String
        if vista == .horario {
            subtitulo = semana.subtitulo
        } else if !modelo.busqueda.trimmingCharacters(in: .whitespaces).isEmpty {
            subtitulo = encontradas == 1 ? "1 tarea encontrada" : "\(encontradas) tareas encontradas"
        } else {
            subtitulo = modelo.listas.count == 1 ? "1 lista" : "\(modelo.listas.count) listas"
        }
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
            TextField(apuntarEn.map { "Nueva tarea en «\($0.titulo.isEmpty ? "Tareas" : $0.titulo)»…" }
                      ?? (destino.isEmpty ? "Apuntar en el Inbox (urgente, #etiqueta, recordar a las 5)"
                                          : "Nueva tarea de \(destino)…"), text: $nueva)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apuntar)
            if !imagenes.isEmpty {
                Label("\(imagenes.count)", systemImage: "photo")
                    .help(imagenes.map(\.lastPathComponent).joined(separator: "\n"))
                    .onTapGesture { imagenes = [] }
            }
            let asignaturas = modelo.asignaturas
            if !asignaturas.isEmpty {
                Picker("", selection: Binding(get: { destino }, set: { destino = $0; apuntarEn = nil })) {
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
            if let l = apuntarEn {
                // Volver al Inbox (en Windows, Esc en la caja vacia).
                Button { apuntarEn = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Paleta.v2.gris)
                    .help("Apuntar en el Inbox y no en «\(l.titulo)»")
            }
            TextField("Buscar tareas…", text: $modelo.busqueda)
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
        let lista = apuntarEn
        Task { await modelo.apuntar(texto, imagenes: fotos, asignatura: donde, en: lista) }
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

/// Los colores de un grupo (`DEGRADADOS` de Windows, del nucleo).
extension GrupoTareas {
    var colorDesde: Color { Color(hex: desde) }
    var colorHasta: Color { Color(hex: hasta) }
    /// La marca de su encabezado: su color, un cuarto hacia el blanco.
    var colorMarca: Color {
        func c(_ x: UInt32) -> UInt32 { x + (255 - x) / 4 }
        let r = c((desde >> 16) & 0xFF), g = c((desde >> 8) & 0xFF), b = c(desde & 0xFF)
        return Color(hex: (r << 16) | (g << 8) | b)
    }
    /// El id del encabezado, para desplazarse hasta el (la lista pedida).
    var idEncabezado: String { "lista:\(clave)" }
}

/// **Las tarjetas** (tareas-v4 de Windows): cada lista con su encabezado y
/// lo pendiente en cuadrados (una foto de la tarea, de fondo; sin foto, el
/// degradado de SU lista; con varias, los bordes de las de detras), y lo
/// hecho plegado en filas: un cuadrado entero para algo ya tachado pesaba
/// tanto como lo pendiente. Lo que sale, en que orden y su color lo da el
/// nucleo (`modelo.grupos`).
struct RejillaTarjetas: View {
    @ObservedObject var modelo: ModeloTareas
    @Binding var resaltada: String?
    @Binding var irAEncabezado: String?
    /// Las listas con lo hecho abierto.
    @State private var abiertas: Set<String> = []

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(modelo.grupos, id: \.clave) { g in
                        // El id en el grupo entero (hijo directo de la pila
                        // perezosa): asi `scrollTo` lo alcanza aunque aun no
                        // se haya pintado.
                        if let l = modelo.lista(de: g) { grupo(g, l).id(g.idEncabezado) }
                    }
                }
                .padding(12)
            }
            .onChange(of: resaltada) { _, id in
                guard let id else { return }
                withAnimation { lector.scrollTo(id, anchor: .center) }
            }
            .onChange(of: irAEncabezado) { _, k in irA(k, lector) }
            .onAppear {
                if let id = resaltada {
                    DispatchQueue.main.async { lector.scrollTo(id, anchor: .center) }
                }
                irA(irAEncabezado, lector)
            }
        }
    }

    /// Su encabezado arriba del todo (Windows, `ir_a_lista`).
    private func irA(_ clave: String?, _ lector: ScrollViewProxy) {
        guard let clave, let g = modelo.grupos.first(where: { $0.clave == clave }) else { return }
        DispatchQueue.main.async {
            withAnimation { lector.scrollTo(g.idEncabezado, anchor: .top) }
            irAEncabezado = nil
        }
    }

    private func grupo(_ g: GrupoTareas, _ l: ListaTareas) -> some View {
        let hechas = modelo.tareas(g.hechas, de: l)
        let buscando = !modelo.busqueda.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            CabeceraLista(l: l, g: g)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(modelo.tareas(g.arriba, de: l), id: \.indice) { t in
                    let x = TareaConLista(lista: l, tarea: t)
                    TarjetaTarea(t: x, g: g, modelo: modelo, resaltada: resaltada == x.id)
                        .id(x.id)
                }
            }
            if !hechas.isEmpty {
                PliegueHechas(n: hechas.count, buscando: buscando, abierta: Binding(
                    get: { abiertas.contains(g.clave) || buscando },
                    set: { if $0 { abiertas.insert(g.clave) } else { abiertas.remove(g.clave) } }))
                if abiertas.contains(g.clave) || buscando {
                    ForEach(hechas, id: \.indice) { t in
                        let x = TareaConLista(lista: l, tarea: t)
                        FilaHecha(t: x, modelo: modelo)
                            .id(x.id)
                    }
                }
            }
        }
    }
}

/// «Hechas (N)» con su flecha (`pintar_pliegue` de Windows): abre y cierra
/// lo hecho de la lista. Buscando esta abierto siempre y es solo un rotulo.
struct PliegueHechas: View {
    let n: Int
    let buscando: Bool
    @Binding var abierta: Bool
    @State private var encima = false

    var body: some View {
        HStack(spacing: 6) {
            if !buscando {
                Image(systemName: abierta ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("Hechas (\(n))").font(.system(size: 13.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Paleta.v2.gris)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(encima && !buscando ? Color.white.opacity(0.05) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .onTapGesture { if !buscando { abierta.toggle() } }
    }
}

/// Una tarea hecha: una fila en la tarjeta de su lista (`pintar_fila_hecha`
/// de Windows), tachada y en gris.
struct FilaHecha: View {
    let t: TareaConLista
    @ObservedObject var modelo: ModeloTareas

    var body: some View {
        FilaTarea(t: t, conLista: false, listas: modelo.listas, acciones: AccionesTarea.de(t, modelo))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex: 0x222225), in: RoundedRectangle(cornerRadius: 10))
            .draggable(t.id)
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
            pinear: { modelo.pinear(x) },
            buscar: { q in modelo.busqueda = q }
        )
    }
}

/// **Una tarjeta** (`pintar_cuadrado` de Windows): la tarea en un
/// cuadrado, del alto de lo suyo (entre la mitad del lado y el lado). Sin
/// foto, el degradado de SU lista (las tareas de una lista se reconocen de
/// lejos) con el texto claro arriba; con foto, la primera de fondo con un
/// velo oscuro abajo y el texto en blanco y negrita encima. Se arrastra a
/// otra columna del Kanban.
struct TarjetaTarea: View {
    let t: TareaConLista
    let g: GrupoTareas
    @ObservedObject var modelo: ModeloTareas
    var resaltada = false
    @State private var encima = false
    /// El lado de la tarjeta (`LADO_CUADRADO` de Windows).
    static let lado: CGFloat = 200

    var body: some View {
        let fotos = t.tarea.imagenes
        let conFoto = !fotos.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            if conFoto { Spacer(minLength: 0) }
            FilaTarea(t: t, conLista: false, listas: modelo.listas, acciones: AccionesTarea.de(t, modelo),
                      sobreFoto: conFoto, enTarjeta: true)
            if !conFoto { Spacer(minLength: 0) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: conFoto ? Self.lado : Self.lado / 2,
               maxHeight: Self.lado, alignment: .topLeading)
        .background {
            if let primera = fotos.first {
                FotoDeTarjeta(ruta: primera)
                    .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                                    .init(color: .black.opacity(0.8), location: 1)],
                                            startPoint: .top, endPoint: .bottom))
            } else {
                LinearGradient(colors: [g.colorDesde, g.colorHasta],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay { if encima { Color.white.opacity(0.06).allowsHitTesting(false) } }
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
                    .background(Color(hex: 0x48484E).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .offset(x: CGFloat(k + 1) * 4, y: -CGFloat(k + 1) * 4)
            }
        }
        .onHover { encima = $0 }
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
                Paleta.v2.tarjeta
            }
        }
        .task(id: ruta) {
            let ruta = ruta
            let datos = await Task.detached(priority: .utility) { FileManager.default.contents(atPath: ruta) }.value
            imagen = datos.flatMap(NSImage.init(data:))
        }
    }
}

/// **El encabezado de una lista** (`pintar_encabezado` de Windows): la
/// marca redonda de su color, su nombre en negrita, «· su chat» en gris
/// (no en el Inbox: que es de «Mensajes guardados» ya se sabe) y, al borde
/// derecho, cuantas quedan pendientes.
struct CabeceraLista: View {
    let l: ListaTareas
    let g: GrupoTareas

    private var pendientes: String {
        switch g.pendientes {
        case 0: "nada pendiente"
        case 1: "1 pendiente"
        default: "\(g.pendientes) pendientes"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(g.colorMarca).frame(width: 6, height: 15)
            Text(l.titulo.isEmpty ? "Tareas" : l.titulo)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.v2.texto)
                .lineLimit(1)
                .layoutPriority(1)
            if !l.esInbox {
                Text("·  \(l.guardados ? "Mensajes guardados" : l.nombreChat)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Paleta.v2.gris)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(pendientes).font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Paleta.v2.gris)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 28)
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
    /// Buscar lo de una chapita pulsada (su marca o su `#etiqueta`).
    var buscar: (String) -> Void = { _ in }
}

/// Una tarea: su casilla, el texto con sus #etiquetas y sus chapitas
/// (prioridad primero), su hora de recordar, cuantos dias lleva y, si se
/// pide, su lista y su chat. Doble clic o F2 la corrige; su menu la
/// recuerda, la mueve o la borra.
///
/// Los colores son los de las ventanas oscuras de Windows (`Paleta.v2`):
/// la ventana de Tareas es oscura siempre, y `.primary` salia negro si el
/// Mac iba en claro.
struct FilaTarea: View {
    let t: TareaConLista
    let conLista: Bool
    var listas: [ListaTareas] = []
    var acciones = AccionesTarea()
    /// Encima de una foto: letra blanca en negrita y chapitas oscuras.
    var sobreFoto = false
    /// En una tarjeta: el texto arriba y grande, la casilla y la edad al pie
    /// (`rejilla::partes` de Windows); si no, en una fila.
    var enTarjeta = false
    @State private var editando = false
    @State private var texto = ""
    @FocusState private var foco: Bool

    private var marcas: MarcasTarea { marcasDeTarea(texto: t.tarea.texto, desfaseMs: desfaseLocalMs()) }

    private var colorTexto: Color {
        if t.tarea.hecha { return sobreFoto ? Color.white.opacity(0.6) : Paleta.v2.gris }
        return sobreFoto ? Color.white : Paleta.v2.texto
    }

    /// La edad (`mini-tarea-edad`): «hoy», «hace 1 día», «hace N días».
    private var edad: String? {
        guard let d = t.tarea.dias, !t.tarea.hecha else { return nil }
        switch d {
        case 0: return "hoy"
        case 1: return "hace 1 día"
        default: return "hace \(d) días"
        }
    }

    var body: some View {
        Group {
            if enTarjeta { comoTarjeta } else { comoFila }
        }
        .contentShape(Rectangle())
        .onKeyPress(.init("\u{F70F}")) { // F2
            empezar()
            return .handled
        }
        .contextMenu { menu }
    }

    private var casilla: some View {
        Toggle("", isOn: Binding(get: { t.tarea.hecha }, set: { acciones.marcar($0) }))
            .toggleStyle(.checkbox)
            .labelsHidden()
    }

    private var campo: some View {
        TextField("Texto de la tarea…", text: $texto)
            .textFieldStyle(.roundedBorder)
            .focused($foco)
            .onSubmit {
                editando = false
                acciones.editar(texto)
            }
            .onExitCommand { editando = false }
    }

    private func textoDeLaTarea(_ m: MarcasTarea, tam: CGFloat) -> some View {
        Text(m.vista.isEmpty ? "(sin texto)" : m.vista)
            .font(.system(size: tam, weight: sobreFoto ? .semibold : .regular))
            .strikethrough(t.tarea.hecha)
            .foregroundStyle(colorTexto)
            .shadow(color: sobreFoto ? Color.black.opacity(0.6) : Color.clear, radius: 2)
    }

    /// La urgencia y las #etiquetas, en chapitas aparte (Windows, 18-oct);
    /// pulsar una busca lo suyo.
    @ViewBuilder private func chapitas(_ m: MarcasTarea) -> some View {
        // La prioridad de Jev va la primera, con su chispa, si el usuario
        // no marco la suya (Windows fa4ca12: lo suyo manda).
        if m.urgencia == nil, let j = t.tarea.chapitaDeJev {
            ChapitaTarea(texto: j.texto, clase: j.suave ? .jevSuave(j.color) : .jev(j.color), sobreFoto: sobreFoto)
                .help(t.tarea.pistaDeJev)
        }
        if let u = m.urgencia {
            ChapitaTarea(texto: u == "muy_urgente" ? "Muy urgente" : "Urgente",
                         clase: u == "muy_urgente" ? .muyUrgente : .urgente, sobreFoto: sobreFoto)
                .onTapGesture { acciones.buscar(m.marcaUrgencia ?? "") }
        }
        ForEach(m.etiquetas, id: \.self) { e in
            ChapitaTarea(texto: "#\(e)", clase: .etiqueta, sobreFoto: sobreFoto)
                .onTapGesture { acciones.buscar("#\(e)") }
        }
    }

    private var edadVista: some View {
        Text(edad ?? "")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(sobreFoto ? Color.white.opacity(0.8) : Paleta.v2.gris)
            .help("Creada el \(t.tarea.creada ?? "")")
    }

    /// En su cuadrado: los emoticonos arriba, el texto (hasta cinco
    /// renglones; con foto, tres), sus chapitas y al pie la casilla y la
    /// edad (o «+N» con varias fotos).
    private var comoTarjeta: some View {
        let m = marcas
        return VStack(alignment: .leading, spacing: 8) {
            if !m.chapitas.isEmpty {
                HStack(spacing: 4) {
                    ForEach(m.chapitas, id: \.self) { Text($0).font(.system(size: 18)) }
                }
            }
            if editando {
                campo
            } else {
                textoDeLaTarea(m, tam: sobreFoto ? 15 : 17)
                    .lineLimit(sobreFoto ? 3 : 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) { empezar() }
            }
            if m.urgencia != nil || !m.etiquetas.isEmpty || t.tarea.chapitaDeJev != nil {
                HStack(spacing: 4) { chapitas(m) }
            }
            HStack(spacing: 6) {
                casilla
                Spacer(minLength: 0)
                if t.tarea.imagenes.count > 1 {
                    Text("+\(t.tarea.imagenes.count - 1)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .help("\(t.tarea.imagenes.count) imágenes")
                } else if edad != nil {
                    edadVista
                }
            }
        }
    }

    /// En una fila (lo hecho): la casilla, el texto y la edad.
    private var comoFila: some View {
        let m = marcas
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            casilla
            VStack(alignment: .leading, spacing: 2) {
                if editando {
                    campo
                } else {
                    HStack(spacing: 4) {
                        ForEach(m.chapitas, id: \.self) { Text($0) }
                        textoDeLaTarea(m, tam: 14)
                        chapitas(m)
                    }
                    .onTapGesture(count: 2) { empezar() }
                }
                if conLista {
                    Text("\(t.lista.titulo) · \(t.lista.guardados ? "Mensajes guardados" : t.lista.nombreChat)")
                        .font(.caption).foregroundStyle(Paleta.v2.gris)
                }
            }
            Spacer()
            if !t.tarea.imagenes.isEmpty {
                Image(systemName: "photo").foregroundStyle(Paleta.v2.gris)
                    .help("\(t.tarea.imagenes.count) imágenes")
            }
            if edad != nil { edadVista }
        }
    }

    @ViewBuilder private var menu: some View {
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

    private func empezar() {
        texto = t.tarea.texto
        editando = true
        foco = true
    }
}

// MARK: - Kanban

/// **El tablero Kanban** (Windows `kanban.rs`, 17-oct): cada lista una
/// columna (las mismas listas que las tarjetas: una sin nada que salga no
/// sale) con su encabezado, sus tarjetas pendientes una tras otra (las
/// mismas de la vista Tarjetas) y al pie su pliegue de hechas, en filas.
/// Arrastrar una tarjeta a OTRA columna la pasa a esa lista (`mover`, el
/// «Mover a…»); soltarla en la suya o fuera no hace nada. Las columnas miden
/// de 240 a 340 y lo que no cabe a lo ancho baja a otra banda: nunca hay que
/// desplazarse de lado.
struct TableroKanban: View {
    @ObservedObject var modelo: ModeloTareas
    @Binding var irAEncabezado: String?

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 18) {
                    ForEach(modelo.grupos, id: \.clave) { g in
                        if let l = modelo.lista(de: g) {
                            ColumnaKanban(g: g, l: l, modelo: modelo).id(g.idEncabezado)
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: irAEncabezado) { _, k in irA(k, lector) }
            .onAppear { irA(irAEncabezado, lector) }
        }
    }

    private func irA(_ clave: String?, _ lector: ScrollViewProxy) {
        guard let clave, let g = modelo.grupos.first(where: { $0.clave == clave }) else { return }
        DispatchQueue.main.async {
            withAnimation { lector.scrollTo(g.idEncabezado, anchor: .top) }
            irAEncabezado = nil
        }
    }
}

struct ColumnaKanban: View {
    let g: GrupoTareas
    let l: ListaTareas
    @ObservedObject var modelo: ModeloTareas
    @State private var encima = false
    @State private var verHechas = false

    var body: some View {
        let buscando = !modelo.busqueda.trimmingCharacters(in: .whitespaces).isEmpty
        let hechas = modelo.tareas(g.hechas, de: l)
        VStack(alignment: .leading, spacing: 12) {
            CabeceraLista(l: l, g: g)
            ForEach(modelo.tareas(g.arriba, de: l), id: \.indice) { t in
                TarjetaTarea(t: TareaConLista(lista: l, tarea: t), g: g, modelo: modelo)
            }
            if !hechas.isEmpty {
                PliegueHechas(n: hechas.count, buscando: buscando, abierta: $verHechas)
                if verHechas || buscando {
                    ForEach(hechas, id: \.indice) { t in
                        FilaHecha(t: TareaConLista(lista: l, tarea: t), modelo: modelo)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // El fondo de la columna (blanco al 3,5 %) y, la de destino al
        // arrastrar, el azul de Windows.
        .background(encima ? Paleta.v2.acento.opacity(0.16) : Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 15))
        .dropDestination(for: String.self) { ids, _ in
            var movida = false
            for id in ids {
                // Solo de otra columna (`destino_al_soltar`).
                if let t = modelo.tarea(id: id), t.lista.chat != l.chat || t.lista.mensaje != l.mensaje {
                    Task { await modelo.mover(t, a: l) }
                    movida = true
                }
            }
            return movida
        } isTargeted: { encima = $0 }
    }
}

/// Una chapita de una tarea (su urgencia o una etiqueta), con los colores
/// de `chapitas.rs` de Windows sobre la ventana oscura o sobre una foto.
struct ChapitaTarea: View {
    /// `jev`: la prioridad de Jev con su color (mas suave que las marcas).
    /// `jevSuave`: la «Normal» de Jev, con la mitad de fondo.
    enum Clase { case muyUrgente, urgente, etiqueta, jev(UInt32), jevSuave(UInt32) }

    let texto: String
    let clase: Clase
    var sobreFoto = false

    private var fondo: Color {
        switch (clase, sobreFoto) {
        case (.muyUrgente, _): return Color(hex: 0xE5534B)
        case (.urgente, true): return Color.black.opacity(0.6)
        case (.urgente, false): return Color(hex: 0xE8A33D, alfa: 0.22)
        case (.etiqueta, true): return Color.black.opacity(0.55)
        case (.etiqueta, false): return Color.white.opacity(0.08)
        case (.jev, true): return Color.black.opacity(0.6)
        case let (.jev(c), false): return Color(hex: c, alfa: 0.16)
        case (.jevSuave, true): return Color.black.opacity(0.3)
        case let (.jevSuave(c), false): return Color(hex: c, alfa: 0.08)
        }
    }

    private var letra: Color {
        switch (clase, sobreFoto) {
        case (.muyUrgente, _): return Color.white
        case (.urgente, _): return Color(hex: 0xE8A33D)
        case (.etiqueta, true): return Color.white
        case (.etiqueta, false): return Color(hex: 0x9CC4F0)
        case let (.jev(c), _): return Color(hex: c)
        case let (.jevSuave(c), _): return Color(hex: c)
        }
    }

    var body: some View {
        Text(texto)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(fondo, in: Capsule())
            .foregroundStyle(letra)
    }
}
