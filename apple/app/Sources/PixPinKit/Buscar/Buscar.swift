// **Buscar en PixPin** (D8, `buscar_todo.rs` de Windows): una ventana que
// busca en todo —chats, mensajes y notas, ficheros por su nombre y por lo
// que pone dentro (PDF, Word, PowerPoint...), tareas, lecciones, capturas
// por su nombre, su fecha y su texto, y los momentos del timeline— y hace
// con lo elegido lo de Windows.
//
// Con la caja vacia ensena las busquedas recientes, lo abierto hace poco y
// las letras rapidas (t, n, l, g, c, u, a). Con algo escrito, pestanas con
// su cuenta, el mejor resultado arriba y el resto por grupos, la fila
// elegida con sus botones y la vista previa. Todo se hace con el teclado:
// ↑↓, RePag/AvPag, Tab (o ⇧Tab, ⌘1…7) entre pestanas, ↩, ⌘↩ (ver en el
// chat), ⌥↩ (abrir con), → (mas acciones), ⌘C, Supr o ⌘⌫ (borrar una
// captura, con ⌘Z) y Esc por capas. La logica esta en `EstadoBuscar.swift`;
// lo que hace cada cosa, en `AccionesBuscar.swift`; la vista previa, en
// `VistaPreviaBuscar.swift`.
//
// Rendimiento (§4bis del plan):
// - se espera a que se deje de escribir (200 ms) antes de buscar, y cada
//   letra nueva CANCELA la busqueda anterior: la `Task` de Swift y, en Rust,
//   el `Busqueda` que mira en cada linea si tiene que parar;
// - cada clase llega hasta un tope (`tamPagina`); al llegar al final de la
//   lista se pide con el doble (`cargarMas`);
// - el texto de los documentos y de las capturas se lee en segundo plano
//   (`LectorTextoDocumentos`, `LectorTextoGaleria`) y se vuelve a buscar
//   cuando llega algo nuevo.

import AppKit
import Foundation
import PixPinCore
import SwiftUI

/// Que la ventana de Proyectos abra un chat (lo pide Buscar). Es un valor y
/// no un aviso suelto: si la ventana aun no estaba abierta, lo lee al
/// aparecer.
@MainActor
public final class PeticionDeChat: ObservableObject {
    public static let compartida = PeticionDeChat()
    @Published public var chat: String?
    /// El mensaje al que saltar dentro del chat (lo toma la vista del chat al
    /// aparecer; ver `Chat/SaltoAMensaje.swift`). Se pone ANTES que `chat`.
    @Published public var salto: SaltoAMensaje?
}

/// Que el timeline abra un momento en su detalle (lo pide Buscar): lo
/// busca por `consulta` y abre el de `id`. Como `PeticionDeChat`, un valor
/// que la ventana lee al aparecer.
@MainActor
public final class PeticionDeMomento: ObservableObject {
    public static let compartida = PeticionDeMomento()
    public struct Pedido: Equatable {
        public var id: String
        public var consulta: String
    }
    @Published public var pedido: Pedido?
}

@MainActor
public final class ModeloBuscar: ObservableObject {
    /// El tope de cada clase en la primera vuelta.
    public nonisolated static let tamPagina: UInt32 = 50
    /// Lo que se espera desde la ultima letra antes de buscar.
    public nonisolated static let espera: Duration = .milliseconds(200)

    @Published public var estado = EstadoBuscar()
    @Published public private(set) var busquedas: [String] = []
    @Published public private(set) var buscando = false
    @Published public private(set) var error: String?
    /// Las clases que se cortaron en el tope.
    @Published public private(set) var recortadas: Set<ClaseDeResultado> = []
    /// El aviso de abajo («Copiado», «Captura borrada»).
    @Published public var aviso: String?

    let almacen: Almacen
    /// La busqueda en curso (la espera y la llamada a Rust).
    private(set) var tarea: Task<Void, Never>?
    private var enRust: Busqueda?
    private var tope = ModeloBuscar.tamPagina
    /// Las capturas borradas, para ⌘Z.
    var borradas: [CapturaBorrada] = []
    private var finAviso: Task<Void, Never>?

    public init(almacen: Almacen) {
        self.almacen = almacen
    }

    // Lo de siempre, para quien ya lo usaba (y sus pruebas).
    public var consulta: String { estado.consulta }
    public var resultados: [ResultadoBusqueda] { estado.resultados }
    public var hayMas: Bool { !recortadas.isEmpty }

    /// Lo escrito cambio: cancela lo anterior y busca tras la espera.
    public func cambiar(_ texto: String) {
        estado.consulta = texto
        estado.menu = nil
        tope = ModeloBuscar.tamPagina
        cancelar()
        buscando = true
        tarea = Task { [weak self] in
            try? await Task.sleep(for: ModeloBuscar.espera)
            guard !Task.isCancelled else { return }
            await self?.buscarAhora(texto)
        }
    }

    /// Cambia de pestana (con la caja vacia, cada una pregunta lo suyo).
    public func ir(a p: PestanaBuscar) {
        if estado.ir(a: p) == .buscar {
            refrescar()
        }
    }

    /// Vuelve a buscar lo de ahora, ya.
    public func refrescar(mantener: Bool = false) {
        cancelar()
        let texto = estado.consulta
        tarea = Task { [weak self] in await self?.buscarAhora(texto, mantener: mantener) }
    }

    /// Para lo que este en marcha (tambien la busqueda en Rust).
    public func cancelar() {
        tarea?.cancel()
        tarea = nil
        enRust?.cancelar()
        enRust = nil
    }

    /// Busca ya, sin esperar.
    public func buscarAhora(_ texto: String, mantener: Bool = false) async {
        estado.consulta = texto
        let b = Busqueda.nueva()
        enRust = b
        buscando = true
        let pedido = pedidoDe(texto)
        let hecho = await pedir(pedido, busqueda: b)
        // Si mientras tanto se escribio otra cosa, esto ya no vale.
        guard enRust === b, !Task.isCancelled else { return }
        buscando = false
        enRust = nil
        guard let hecho, !hecho.cancelada else { return }
        recortadas = Set(hecho.recortadas)
        estado.poner(hecho.resultados, mantener: mantener)
    }

    /// Al llegar al final de la lista: lo mismo con el doble de tope.
    public func cargarMas() async {
        guard hayMas, enRust == nil, tope < 1000 else { return }
        tope = min(tope * 2, 1000)
        await buscarAhora(estado.consulta, mantener: true)
    }

    /// Que se le pide al nucleo para `texto` en la pestana de ahora.
    enum Pedido {
        /// La caja vacia en «Todo»: lo abierto hace poco.
        case inicio
        /// Nada (una letra que no busca: «t pan» solo apunta).
        case nada
        case buscar(OpcionesBusqueda)
    }

    func pedidoDe(_ texto: String) -> Pedido {
        let limpio = texto.trimmingCharacters(in: .whitespaces)
        let dias = Int64(AjusteCaducidad.dias)
        func opciones(_ q: String, _ clases: [ClaseDeResultado]) -> Pedido {
            .buscar(OpcionesBusqueda(consulta: q, clases: clases, tope: tope,
                                     diasCaducidad: dias, desfaseMs: desfaseLocalMs()))
        }
        if let (letra, resto) = LetrasRapidas.analizar(texto) {
            // «g muro» busca en las capturas; las demas letras no buscan.
            return letra == "g" ? opciones(resto, [.captura]) : .nada
        }
        if limpio.isEmpty {
            switch estado.pestana {
            case .todo: return .inicio
            case .acciones: return .nada
            case let p: return opciones("", p.clases)
            }
        }
        // Con algo escrito se busca en todo: las pestanas solo filtran (y
        // asi ensenan su cuenta).
        return opciones(limpio, [])
    }

    private func pedir(_ p: Pedido, busqueda: Busqueda) async -> ResultadosEnTodo? {
        let nucleo = almacen.nucleo
        switch p {
        case .nada:
            return ResultadosEnTodo(resultados: [], recortadas: [], cancelada: false)
        case .inicio:
            let dias = Int64(AjusteCaducidad.dias)
            let desfase = desfaseLocalMs()
            let (inicio, recientes) = await Task.detached(priority: .userInitiated) {
                (nucleo.buscarInicio(diasCaducidad: dias, desfaseMs: desfase), nucleo.buscarRecientes())
            }.value
            busquedas = recientes.busquedas
            return ResultadosEnTodo(resultados: inicio, recortadas: [], cancelada: false)
        case let .buscar(o):
            let hecho = await withTaskCancellationHandler {
                await Task.detached(priority: .userInitiated) { () -> Result<ResultadosEnTodo, Error> in
                    Result(catching: { try nucleo.buscarEnTodo(opciones: o, busqueda: busqueda) })
                }.value
            } onCancel: {
                busqueda.cancelar()
            }
            switch hecho {
            case let .success(r):
                error = nil
                return r
            case let .failure(e):
                error = "\(e)"
                return nil
            }
        }
    }

    // MARK: Recientes

    /// Apunta lo elegido: la busqueda en las recientes y el resultado en
    /// «Abierto hace poco».
    func recordar(_ f: FilaBuscar) {
        let nucleo = almacen.nucleo
        let consulta = estado.consulta
        let abierto = f.resultado
        Task.detached(priority: .utility) {
            try? nucleo.buscarApuntar(consulta: consulta, abierto: abierto)
        }
    }

    func quitarBusqueda(_ i: Int) {
        try? almacen.nucleo.buscarQuitarBusqueda(indice: UInt32(i))
        busquedas = almacen.nucleo.buscarRecientes().busquedas
    }

    func borrarBusquedas() {
        try? almacen.nucleo.buscarBorrarBusquedas()
        busquedas = []
    }

    // MARK: Avisos

    /// Un aviso abajo; con algo que deshacer dura mas (como Windows: 6 s).
    func avisar(_ texto: String) {
        aviso = texto
        finAviso?.cancel()
        let largo: Duration = estado.seDeshace ? .seconds(6) : .seconds(2)
        finAviso = Task { [weak self] in
            try? await Task.sleep(for: largo)
            guard !Task.isCancelled, let self else { return }
            self.aviso = nil
            self.estado.seDeshace = false
            self.borradas = []
        }
    }
}

// MARK: - La ventana

public struct VentanaBuscar: View {
    @StateObject private var modelo: ModeloBuscar
    @State private var texto = ""
    @State private var vistaRapida: URL?
    @State private var monitor: Any?
    @State private var lectorDocumentos: LectorTextoDocumentos?
    @State private var lectorCapturas: LectorTextoGaleria?
    @Environment(\.openWindow) private var abrirVentana
    /// La ventana (para las teclas y para cerrarla).
    @State private var ventana = RefVentana()

    public init(almacen: Almacen) {
        _modelo = StateObject(wrappedValue: ModeloBuscar(almacen: almacen))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Cabecera("Buscar en PixPin", subtitulo: subtitulo,
                     buscador: BuscadorCabecera($texto, pista: "Busca archivos, tareas, lecciones, capturas… o una letra",
                                                enfocar: true))
            BarraPestanas(modelo: modelo)
            if modelo.estado.esInicio {
                InicioBuscar(modelo: modelo, poner: { texto = $0 }, hacer: hacer)
            } else {
                HStack(spacing: 0) {
                    ListaBuscar(modelo: modelo, hacer: hacer)
                        .frame(minWidth: 320, idealWidth: 440)
                    Paleta.v2.linea.frame(width: 1)
                    VistaPreviaBuscar(modelo: modelo, hacer: hacer)
                        .frame(minWidth: 280, maxWidth: .infinity)
                }
            }
            PieBuscar(modelo: modelo, deshacer: { hacer(.deshacer) })
        }
        .background(AccesoVentana { ventana.ventana = $0 })
        .ventanaConCabecera()
        .frame(minWidth: 720, minHeight: 460)
        .onChange(of: texto) { _, nuevo in modelo.cambiar(nuevo) }
        .onAppear {
            modelo.refrescar()
            empezarLectores()
            ponerTeclas()
        }
        .onDisappear {
            modelo.cancelar()
            lectorDocumentos?.parar()
            lectorCapturas?.parar()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        .quickLookPreview($vistaRapida)
    }

    private var subtitulo: String {
        if modelo.estado.esInicio { return "Chats, archivos, tareas, lecciones y capturas" }
        if modelo.buscando, modelo.estado.resultados.isEmpty { return "Buscando…" }
        let n = modelo.estado.cuenta(modelo.estado.pestana)
        return n == 1 ? "1 resultado" : "\(n)\(modelo.hayMas ? "+" : "") resultados"
    }

    private func hacer(_ o: OrdenBuscar) {
        let e = EjecutorBuscar(modelo: modelo, abrirVentana: { abrirVentana(id: $0) },
                               cerrar: { VentanaLisa.cerrar(ventana.ventana) },
                               vaciar: { texto = "" },
                               vistaRapida: { vistaRapida = $0 })
        e.hacer(o)
    }

    /// El texto de los documentos (PDF, Word…) y de las capturas se lee en
    /// segundo plano; cuando llega algo, se vuelve a buscar.
    private func empezarLectores() {
        let modelo = self.modelo
        let refrescar = { @MainActor [weak modelo] in
            guard let modelo, !modelo.estado.esInicio else { return }
            modelo.refrescar(mantener: true)
        }
        let d = LectorTextoDocumentos(nucleo: modelo.almacen.nucleo, alLeer: refrescar)
        d.despertar()
        lectorDocumentos = d
        let c = LectorTextoGaleria(nucleo: modelo.almacen.nucleo, alLeer: refrescar)
        c.despertar()
        lectorCapturas = c
    }

    /// Las teclas del buscador, antes que la caja de escribir: las que no
    /// son suyas siguen a la caja.
    private func ponerTeclas() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            guard let mia = ventana.ventana, ev.window === mia else { return ev }
            return atender(ev) ? nil : ev
        }
    }

    /// Una tecla: `true` si era del buscador.
    private func atender(_ ev: NSEvent) -> Bool {
        var m: ModsBuscar = []
        let f = ev.modifierFlags
        if f.contains(.shift) { m.insert(.mayus) }
        if f.contains(.command) { m.insert(.comando) }
        if f.contains(.option) { m.insert(.opcion) }
        if f.contains(.control) { m.insert(.control) }
        // ⌘1…7: a esa pestana.
        let cifras: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6]
        if m == .comando, let i = cifras[ev.keyCode], let p = PestanaBuscar(rawValue: i) {
            modelo.ir(a: p)
            return true
        }
        let t: TeclaBuscar
        switch ev.keyCode {
        case 126: t = .arriba
        case 125: t = .abajo
        case 116: t = .rePag
        case 121: t = .avPag
        case 48: t = .tab
        case 124: t = .derecha
        case 123: t = .izquierda
        case 36, 76: t = .intro
        case 53: t = .escape
        case 117: t = .suprimir
        case 51 where m.contains(.comando): t = .suprimir
        case 8: t = .c
        case 6: t = .z
        default: return false
        }
        // Donde esta la rayita de la caja (la del editor de campo).
        var alFinal = true
        var elegido = false
        if let tv = ev.window?.firstResponder as? NSTextView {
            let r = tv.selectedRange()
            elegido = r.length > 0
            alFinal = !elegido && r.location >= (tv.string as NSString).length
        }
        let o = modelo.estado.tecla(t, m, cajaAlFinal: alFinal, textoElegido: elegido)
        switch o {
        case .noEsMia: return false
        case .nada: return true
        case .buscar:
            modelo.refrescar()
            return true
        default:
            hacer(o)
            return true
        }
    }
}

// MARK: - Pestanas

/// Las pestanas con su cuenta (`Tab` cambia, ⌘1…7 va a una).
struct BarraPestanas: View {
    @ObservedObject var modelo: ModeloBuscar

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PestanaBuscar.allCases) { p in
                PestanaVista(p: p, n: modelo.estado.esInicio ? nil : modelo.estado.cuenta(p),
                             activa: modelo.estado.pestana == p) { modelo.ir(a: p) }
            }
            Spacer(minLength: 8)
            Text("Tab cambia").font(.system(size: 11.5)).foregroundStyle(Paleta.v2.gris)
            Chapa(texto: "⇥")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Paleta.v2.fondo)
        .overlay(alignment: .bottom) { Paleta.v2.linea.frame(height: 1) }
    }
}

private struct PestanaVista: View {
    let p: PestanaBuscar
    let n: Int?
    let activa: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Text(p.rotulo).font(.system(size: 13, weight: activa ? .semibold : .regular))
                if let n, n > 0 {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(activa ? Color.white : Paleta.v2.gris)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(activa ? Color.white.opacity(0.22) : Paleta.v2.caja, in: Capsule())
                }
            }
            .foregroundStyle(activa ? Color.white : Paleta.v2.texto)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(activa ? Paleta.v2.acento : encima ? Color.white.opacity(0.08) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help("\(p.rotulo) (⌘\(p.rawValue + 1))")
    }
}

// MARK: - La caja vacia

/// Las busquedas recientes, lo abierto hace poco y las letras rapidas.
struct InicioBuscar: View {
    @ObservedObject var modelo: ModeloBuscar
    let poner: (String) -> Void
    let hacer: (OrdenBuscar) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !modelo.busquedas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Titulillo("Búsquedas recientes")
                            Spacer()
                            Button("Borrar todas") { modelo.borrarBusquedas() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(Paleta.v2.acento)
                        }
                        FlujoFichas(busquedas: modelo.busquedas, poner: poner, quitar: modelo.quitarBusqueda)
                    }
                }
                if !modelo.estado.resultados.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Titulillo("Abierto hace poco")
                        let visibles = modelo.estado.visibles()
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { i, f in
                            FilaBuscarVista(fila: f, elegida: i == modelo.estado.elegido, consulta: "",
                                            botones: [], hacer: hacer)
                                .onTapGesture {
                                    if i == modelo.estado.elegido {
                                        hacer(.hacer(f, verEnChat: false))
                                    } else {
                                        modelo.estado.elegido = i
                                    }
                                }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Titulillo("Escribe una letra y espacio")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(LetrasRapidas.todas, id: \.letra) { l in
                            Button { poner("\(l.letra) ") } label: {
                                HStack(spacing: 10) {
                                    Text(String(l.letra))
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Paleta.v2.acento)
                                        .frame(width: 28, height: 28)
                                        .background(Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.titulo).font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Paleta.v2.texto)
                                        Text(l.sub).font(.system(size: 11.5)).foregroundStyle(Paleta.v2.gris)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Paleta.v2.fondo)
    }
}

/// El titulito gris de una seccion.
struct Titulillo: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Paleta.v2.gris)
    }
}

/// Las fichas de las busquedas recientes, con su ✕.
struct FlujoFichas: View {
    let busquedas: [String]
    let poner: (String) -> Void
    let quitar: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(busquedas.enumerated()), id: \.offset) { i, b in
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
                    Text(b).lineLimit(1)
                    Button { quitar(i) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Quitar")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Paleta.v2.texto)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Paleta.v2.caja, in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { poner(b) }
            }
        }
    }
}

// MARK: - La lista

struct ListaBuscar: View {
    @ObservedObject var modelo: ModeloBuscar
    let hacer: (OrdenBuscar) -> Void

    var body: some View {
        let lineas = modelo.estado.lineas()
        let elegida = modelo.estado.filaElegida
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lineas.enumerated()), id: \.offset) { _, l in
                        switch l {
                        case let .cabecera(g):
                            Titulillo(g.rotulo)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        case let .fila(f):
                            let es = f.id == elegida?.id
                            FilaBuscarVista(fila: f, elegida: es, consulta: modelo.estado.consulta,
                                            botones: es ? botonesDe(f) : [], hacer: { hacer($0) },
                                            boton: { hacer(modelo.estado.boton($0)) })
                                .id(f.id)
                                .onTapGesture { tocar(f) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    hacer(.hacer(f, verEnChat: false))
                                })
                        }
                    }
                    if modelo.hayMas {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(8)
                            .task { await modelo.cargarMas() }
                    }
                }
                .padding(8)
            }
            .onChange(of: elegida?.id) { _, id in
                if let id { lector.scrollTo(id) }
            }
        }
        .overlay { vacio }
        .background(Paleta.v2.fondo)
    }

    /// El primer clic elige; otro sobre la elegida la abre.
    private func tocar(_ f: FilaBuscar) {
        guard let i = modelo.estado.visibles().firstIndex(of: f) else { return }
        if i == modelo.estado.elegido, modelo.estado.menu == nil {
            hacer(.hacer(f, verEnChat: false))
        } else {
            modelo.estado.elegido = i
            modelo.estado.menu = nil
        }
    }

    @ViewBuilder
    private var vacio: some View {
        if modelo.estado.visibles().isEmpty {
            if modelo.buscando {
                ProgressView()
            } else if let e = modelo.error {
                ContentUnavailableView("No se pudo buscar", systemImage: "exclamationmark.triangle",
                                       description: Text(e))
            } else if modelo.estado.consulta.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Aquí no hay nada todavía", systemImage: "tray")
            } else {
                ContentUnavailableView("Nada con «\(modelo.estado.consulta)»", systemImage: "magnifyingglass",
                                       description: Text("Prueba con menos letras, o mira en otra pestaña (Tab)"))
            }
        }
    }
}

/// Una fila: su icono (o la miniatura), el titulo con lo buscado resaltado,
/// lo de debajo y, si es la elegida, sus botones.
struct FilaBuscarVista: View {
    let fila: FilaBuscar
    let elegida: Bool
    let consulta: String
    let botones: [BotonBuscar]
    let hacer: (OrdenBuscar) -> Void
    var boton: (BotonBuscar) -> Void = { _ in }
    @State private var encima = false

    var body: some View {
        HStack(spacing: 10) {
            IconoFila(fila: fila)
            VStack(alignment: .leading, spacing: 2) {
                tituloResaltado
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Paleta.v2.texto)
                    .lineLimit(1)
                Text(subtitulo)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Paleta.v2.gris)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !botones.isEmpty {
                HStack(spacing: 4) {
                    ForEach(botones, id: \.self) { b in
                        BotonFila(b: b, fila: fila) { boton(b) }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(
            elegida ? Paleta.v2.acento.opacity(0.22) : encima ? Color.white.opacity(0.05) : .clear))
        .overlay {
            if elegida {
                RoundedRectangle(cornerRadius: 9).strokeBorder(Paleta.v2.acento.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
    }

    /// El titulo con las letras que coinciden en negrita y azul.
    private var tituloResaltado: Text {
        switch fila {
        case let .accion(a): return Text(a.titulo)
        case let .resultado(r):
            let t = r.titulo.isEmpty ? r.nombreChat : r.titulo
            return textoResaltado(t, posiciones: r.titulo.isEmpty ? [] : r.resaltado,
                                  tachado: r.clase == .tarea && r.hecha)
        }
    }

    private var subtitulo: String {
        switch fila {
        case let .accion(a): return a.subtitulo
        case let .resultado(r): return subtituloDe(r)
        }
    }
}

/// «Captura · hoy 09:12», «Tarea · Obra · Inbox»…
func subtituloDe(_ r: ResultadoBusqueda) -> String {
    var trozos: [String] = []
    switch r.clase {
    case .chat: trozos.append("Chat")
    case .mensaje: trozos.append(r.tipo == "NOTA" ? "Nota" : "Mensaje")
    case .fichero:
        switch r.tipo {
        case "IMAGEN": trozos.append("Foto")
        case "VOZ": trozos.append("Audio")
        case "VIDEO": trozos.append("Vídeo")
        case "DIBUJO": trozos.append("Lienzo")
        case "PAGINA": trozos.append("Hoja")
        default: trozos.append("Archivo")
        }
    case .tarea: trozos.append(r.hecha ? "Tarea hecha" : "Tarea")
    case .leccion: trozos.append("Lección")
    case .captura: trozos.append("Captura")
    case .momento: trozos.append("Momento")
    }
    if !r.nombreChat.isEmpty, r.clase != .chat { trozos.append(r.nombreChat) }
    if r.clase == .tarea, !r.fragmento.isEmpty { trozos.append(r.fragmento) }
    if r.dentro { trozos.append(r.clase == .captura ? "en su texto" : "dentro del documento") }
    if r.cuando > 0 { trozos.append(fechaCorta(r.cuando)) }
    if r.clase == .captura {
        if r.conservada {
            trozos.append("conservada")
        } else if let d = r.diasQueQuedan {
            trozos.append(d <= 0 ? "caduca hoy" : "caduca en \(d) \(d == 1 ? "día" : "días")")
        }
    }
    return trozos.joined(separator: " · ")
}

/// «hoy 09:12», «ayer», «3 sep», «3 sep 2024».
func fechaCorta(_ ms: Int64, ahora: Date = Date()) -> String {
    let f = fechaDe(ms: ms)
    let cal = Calendar.current
    if cal.isDateInToday(f) { return "hoy " + f.formatted(date: .omitted, time: .shortened) }
    if cal.isDateInYesterday(f) { return "ayer" }
    if cal.isDate(f, equalTo: ahora, toGranularity: .year) {
        return f.formatted(.dateTime.day().month(.abbreviated))
    }
    return f.formatted(.dateTime.day().month(.abbreviated).year())
}

/// `texto` con las letras de `posiciones` (en UTF-16) resaltadas.
func textoResaltado(_ texto: String, posiciones: [UInt32], tachado: Bool = false) -> Text {
    var a = AttributedString(texto)
    if tachado { a.strikethroughStyle = .single }
    let ns = texto as NSString
    let marcadas = Set(posiciones.map(Int.init))
    var i = 0
    while i < ns.length {
        guard marcadas.contains(i) else { i += 1; continue }
        var j = i
        while j < ns.length, marcadas.contains(j) { j += 1 }
        if let r = Range(NSRange(location: i, length: j - i), in: texto),
           let desde = AttributedString.Index(r.lowerBound, within: a),
           let hasta = AttributedString.Index(r.upperBound, within: a) {
            a[desde ..< hasta].foregroundColor = Paleta.v2.acento
            a[desde ..< hasta].inlinePresentationIntent = .stronglyEmphasized
        }
        i = j
    }
    return Text(a)
}

/// El icono de una fila (la foto de una captura, en pequeno).
struct IconoFila: View {
    let fila: FilaBuscar

    var body: some View {
        Group {
            if let r = fila.resultado, r.clase == .captura || r.tipo == "IMAGEN", let ruta = r.ruta {
                MiniaturaBuscar(ruta: ruta, lado: 34)
            } else {
                Image(systemName: nombre)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 34, height: 34)
        .background(Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var nombre: String {
        switch fila {
        case let .accion(a): return a.icono
        case let .resultado(r): return iconoDe(r)
        }
    }

    private var color: Color {
        guard let r = fila.resultado else { return Paleta.v2.acento }
        switch r.clase {
        case .tarea: return r.hecha ? Paleta.v2.verde : Paleta.v2.texto
        case .leccion: return Paleta.v2.amarillo
        case .momento: return Paleta.v2.naranja
        default: return Paleta.v2.cuerpo
        }
    }
}

func iconoDe(_ r: ResultadoBusqueda) -> String {
    switch r.clase {
    case .chat: return "bubble.left.and.bubble.right"
    case .tarea: return r.hecha ? "checkmark.square" : "square"
    case .momento: return "clock"
    case .leccion: return "lightbulb"
    case .captura: return "camera.viewfinder"
    case .mensaje: return r.tipo == "NOTA" ? "text.bubble" : Burbuja.icono(r.tipo)
    case .fichero:
        let ext = ((r.ruta ?? r.titulo) as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx", "odt", "rtf", "md", "txt": return "doc.text"
        case "xls", "xlsx", "ods", "csv": return "tablecells"
        case "ppt", "pptx", "odp", "key": return "rectangle.on.rectangle"
        case "epub": return "book"
        default: return Burbuja.icono(r.tipo)
        }
    }
}

/// Un boton de la fila elegida.
private struct BotonFila: View {
    let b: BotonBuscar
    let fila: FilaBuscar
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Group {
                switch b {
                case .principal:
                    Text(rotuloPrincipal(fila)).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                case .verEnChat:
                    Image(systemName: "bubble.left").font(.system(size: 12))
                case .copiar:
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                case .mas:
                    Image(systemName: "ellipsis").font(.system(size: 12))
                }
            }
            .foregroundStyle(b == .principal ? Color.white : Paleta.v2.texto)
            .frame(minWidth: 26, minHeight: 26)
            .background(b == .principal ? Paleta.v2.azulLleno : Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }

    private var ayuda: String {
        switch b {
        case .principal: return "\(rotuloPrincipal(fila)) (↩)"
        case .verEnChat: return "Ver en el chat (⌘↩)"
        case .copiar: return "Copiar (⌘C)"
        case .mas: return "Más acciones (→)"
        }
    }
}

// MARK: - El pie

/// Las teclas de abajo, o el aviso (con «Deshacer» si se puede).
struct PieBuscar: View {
    @ObservedObject var modelo: ModeloBuscar
    let deshacer: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let aviso = modelo.aviso {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Paleta.v2.verde)
                Text(aviso).foregroundStyle(Paleta.v2.texto)
                if modelo.estado.seDeshace {
                    Button("Deshacer (⌘Z)", action: deshacer)
                        .buttonStyle(.plain)
                        .foregroundStyle(Paleta.v2.acento)
                }
                Spacer()
            } else {
                pista("↑↓", "moverse")
                pista("↩", "abrir")
                if modelo.estado.menu != nil {
                    pista("←", "volver")
                } else {
                    pista("→", "más acciones")
                    pista("⌘↩", "ver en el chat")
                }
                if modelo.estado.filaElegida?.resultado?.clase == .captura {
                    pista("⌘⌫", "borrar")
                }
                Spacer()
                pista("esc", "cerrar")
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Paleta.v2.fondo)
        .overlay(alignment: .top) { Paleta.v2.linea.frame(height: 1) }
    }

    private func pista(_ tecla: String, _ que: String) -> some View {
        HStack(spacing: 5) {
            Chapa(texto: tecla)
            Text(que).foregroundStyle(Paleta.v2.gris)
        }
    }
}
