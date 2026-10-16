// **La hoja de compartir comun** (D1, `compartir/ventana.rs` de Windows y
// `HojaDeCompartir.kt` del movil): una sola para toda la app. El chat (un
// mensaje, lo elegido), la lista de proyectos, los pines y los lectores la
// abren con lo que comparten (`CosaCompartida`), y de aqui en adelante todo
// va igual.
//
// Tres partes, de arriba abajo, como en Windows:
// - **los formatos**, en redondeles (HTML, PDF, PNG, JPG, SVG y lo que va
//   entero: Original, Editable, .pixpin, Texto);
// - **que paginas**, cuando hay para elegir (ver `EstadoHoja`);
// - **el peso y las salidas**: el fichero de lo elegido se hace en cuanto
//   se elige, para decir cuanto pesa de verdad, y es ese el que se manda.
//
// Las salidas: **Compartir** (el principal) deja el fichero en la Salida
// para arrastrarlo o copiarlo, como Windows desde el 8-oct-2026; **Más…**
// es la hoja del Mac (AirDrop, Mail, Mensajes...), lo que en Windows es el
// panel Compartir; **Guardar como…** y **Copiar**.
//
// Teclado: ← → cambian de formato, ↩ comparte, ⌘S guarda, ⌘C copia, ⎋
// cierra.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HojaCompartir {
    /// Las abiertas, para que no se suelten mientras se ven.
    private static var abiertas: [ObjectIdentifier: NSPanel] = [:]

    /// **Abre la hoja** para `cosa`. `almacen` hace falta para leer los
    /// mensajes y los proyectos.
    static func abrir(_ cosa: CosaCompartida, almacen: Almacen?) {
        let modelo = ModeloHojaCompartir()
        let panel = PanelHoja(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.modelo = modelo
        panel.appearance = NSAppearance(named: .darkAqua)
        modelo.cerrar = { [weak panel] in panel?.close() }
        let vista = NSHostingView(rootView: VistaHojaCompartir(modelo: modelo))
        vista.sizingOptions = [.preferredContentSize]
        panel.contentView = vista
        let id = ObjectIdentifier(panel)
        abiertas[id] = panel
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated {
                abiertas[id] = nil
                modelo.limpiar()
            }
        }
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        Task { await modelo.preparar(cosa, almacen: almacen) }
    }

    /// **Imprimir** lo que se comparte: todas sus paginas marcadas, cada una
    /// encajada en su hoja de papel (el «Imprimir…» del mensaje de un
    /// lienzo, `Accion::Imprimir` de Windows).
    static func imprimir(_ cosa: CosaCompartida, almacen: Almacen?) {
        Task {
            let p = await PrepararCompartir.preparar(cosa, almacen: almacen)
            let marcadas = p.compartible().marcadas
            let piezas = p.piezas.filter { marcadas?.contains($0.pagina.clave) ?? true }
            guard !piezas.isEmpty else { return NSSound.beep() }
            ImpresionCompartida.imprimir(piezas, titulo: p.titulo)
        }
    }
}

/// El panel de la hoja: ⎋ cierra y las teclas de la hoja.
final class PanelHoja: NSPanel {
    var modelo: ModeloHojaCompartir?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with evento: NSEvent) {
        guard let modelo else { return super.keyDown(with: evento) }
        let mando = evento.modifierFlags.contains(.command)
        MainActor.assumeIsolated {
            switch (evento.keyCode, mando, evento.charactersIgnoringModifiers) {
            case (123, _, _): modelo.moverFormato(-1)
            case (124, _, _): modelo.moverFormato(1)
            case (36, _, _), (76, _, _): modelo.salir(.compartir)
            case (_, true, "s"): modelo.salir(.guardar)
            case (_, true, "c"): modelo.salir(.copiar)
            default: super.keyDown(with: evento)
            }
        }
    }
}

// MARK: - El modelo

/// Las salidas del pie.
enum SalidaHoja {
    /// A la Salida, para arrastrarlo o copiarlo.
    case compartir
    /// La hoja del Mac (AirDrop, Mail...).
    case mas
    case guardar
    case copiar
}

@MainActor
final class ModeloHojaCompartir: ObservableObject {
    @Published private(set) var preparado: PreparadoCompartir?
    @Published private(set) var compartible: Compartible?
    @Published var estado: EstadoHoja?
    /// El fichero de lo elegido, hecho; `nil` mientras se hace.
    @Published private(set) var hecho: [URL]?
    @Published private(set) var fallo: String?
    @Published private(set) var aviso: String?
    /// Una salida pulsada antes de que estuviera hecho: se hace en cuanto
    /// este.
    private var pendiente: SalidaHoja?
    private var turno = 0
    private var turnoAviso = 0
    /// La carpeta de lo hecho, que se borra al cerrar (lo que se lleva a la
    /// Salida se queda: se borra solo al dia siguiente).
    private let carpetaBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("pixpin-compartir", isDirectory: true)
    var cerrar: () -> Void = {}
    /// La vista desde la que sale la hoja del Mac (la pone la vista).
    weak var anclaje: NSView?

    func preparar(_ cosa: CosaCompartida, almacen: Almacen?) async {
        Self.limpiarViejos(carpetaBase)
        usar(await PrepararCompartir.preparar(cosa, almacen: almacen))
    }

    /// Lo ya preparado, en la hoja.
    func usar(_ p: PreparadoCompartir) {
        let c = p.compartible()
        preparado = p
        compartible = c
        guard !c.formatos.isEmpty else {
            fallo = ErrorCompartir.nada.localizedDescription
            return
        }
        estado = EstadoHoja(c)
        rehacer()
    }

    func cambiar(_ hacer: (inout EstadoHoja, Compartible) -> Void) {
        guard var e = estado, let c = compartible else { return }
        hacer(&e, c)
        guard e != estado else { return }
        estado = e
        rehacer()
    }

    func moverFormato(_ paso: Int) { cambiar { e, c in e.moverFormato(c, paso) } }

    /// **Hace el fichero de lo elegido**, para decir cuanto pesa: el que se
    /// manda despues es este mismo.
    private func rehacer() {
        guard let p = preparado, let c = compartible, let e = estado, let f = e.formato(c) else { return }
        turno += 1
        let t = turno
        hecho = nil
        fallo = nil
        guard e.hayQuePreparar(c) else {
            fallo = ErrorCompartir.sinPaginas.localizedDescription
            return
        }
        let carpeta = carpetaBase.appendingPathComponent(UUID().uuidString, isDirectory: true)
        Task {
            // Un respiro: que tocar varias paginas seguidas no haga cinco PDF.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard t == turno else { return }
            do {
                let urls = try await p.generar(f.id, claves: e.elegidas(c), en: carpeta)
                guard t == turno else { return }
                hecho = urls
                if let s = pendiente {
                    pendiente = nil
                    salir(s)
                }
            } catch {
                guard t == turno else { return }
                fallo = error.localizedDescription
            }
        }
    }

    /// «1,2 MB · 3 archivos», «Preparando…», «Marca alguna página».
    var pie: String {
        if let fallo { return fallo }
        guard let hecho else { return "Preparando…" }
        let bytes = hecho.reduce(Int64(0)) { s, u in
            s + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return TextosCompartir.peso(bytes, ficheros: hecho.count)
    }

    func avisar(_ texto: String) {
        aviso = texto
        turnoAviso += 1
        let t = turnoAviso
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if t == turnoAviso { aviso = nil }
        }
    }

    /// **Una salida pulsada.**
    func salir(_ s: SalidaHoja) {
        if let fallo { return avisar(fallo) }
        guard let hecho else {
            pendiente = s
            return avisar("En cuanto esté preparado")
        }
        switch s {
        case .compartir:
            Salida.compartida.mostrar(hecho, titulo: Salida.listo)
            cerrar()
        case .mas:
            guard let anclaje else { return }
            NSSharingServicePicker(items: hecho)
                .show(relativeTo: anclaje.bounds, of: anclaje, preferredEdge: .minY)
        case .guardar:
            guardar(hecho)
        case .copiar:
            Portapapeles.copiar(hecho)
            avisar("Copiado al portapapeles")
        }
    }

    /// «Guardar como…»: el dialogo de guardar con el tipo ya puesto, o el
    /// de elegir carpeta si son varios ficheros.
    private func guardar(_ urls: [URL]) {
        if urls.count == 1, let url = urls.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            if let tipo = UTType(filenameExtension: url.pathExtension) { panel.allowedContentTypes = [tipo] }
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destino = panel.url else { return }
            copiar([url], a: { _ in destino })
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Guardar aquí"
            guard panel.runModal() == .OK, let carpeta = panel.url else { return }
            copiar(urls, a: { carpeta.appendingPathComponent($0.lastPathComponent) })
        }
    }

    private func copiar(_ urls: [URL], a destino: (URL) -> URL) {
        do {
            var escritos: [URL] = []
            for u in urls {
                let d = destino(u)
                if FileManager.default.fileExists(atPath: d.path) { try FileManager.default.removeItem(at: d) }
                try FileManager.default.copyItem(at: u, to: d)
                escritos.append(d)
            }
            avisar(escritos.count == 1 ? "Guardado: \(escritos[0].lastPathComponent)" : "Guardado")
            Salida.compartida.mostrar(escritos, titulo: Salida.guardado)
        } catch {
            avisar("No se pudo guardar: \(error.localizedDescription)")
        }
    }

    func limpiar() { turno += 1 }

    /// Borra lo compartido de hace mas de un dia (`limpiar_viejos`).
    nonisolated static func limpiarViejos(_ base: URL, edad: TimeInterval = 24 * 3600) {
        let fm = FileManager.default
        guard let hijas = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for h in hijas {
            let fecha = (try? h.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(fecha) > edad { try? fm.removeItem(at: h) }
        }
    }
}

// MARK: - La vista

private enum ColoresHoja {
    static let fondo = Color(red: 0x1c / 255, green: 0x1d / 255, blue: 0x22 / 255)
    static let redondel = Color(red: 0x2a / 255, green: 0x2b / 255, blue: 0x31 / 255)
    static let encima = Color(red: 0x34 / 255, green: 0x35 / 255, blue: 0x3c / 255)
    static let texto = Color(red: 0xe8 / 255, green: 0xe8 / 255, blue: 0xec / 255)
    static let apagado = Color(red: 0x9a / 255, green: 0x9a / 255, blue: 0xa2 / 255)
    static let encendido = Color(red: 0x1e / 255, green: 0x88 / 255, blue: 0xe5 / 255)
}

struct VistaHojaCompartir: View {
    @ObservedObject var modelo: ModeloHojaCompartir

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(modelo.compartible?.titulo ?? "Compartir")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ColoresHoja.texto)
                .lineLimit(1)
                .padding(.top, 8)
            if let c = modelo.compartible, let e = modelo.estado {
                formatos(c, e)
                paginas(c, e)
            } else if let fallo = modelo.fallo {
                Text(fallo).foregroundStyle(ColoresHoja.apagado)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Preparando…") }
                    .foregroundStyle(ColoresHoja.apagado)
            }
            Spacer(minLength: 0)
            pieDeHoja
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 300)
        .background(ColoresHoja.fondo)
    }

    private func formatos(_ c: Compartible, _ e: EstadoHoja) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(e.visibles(c), id: \.self) { i in
                    let f = c.formatos[i]
                    Button { modelo.cambiar { e, c in e.elegirFormato(c, i) } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: f.simbolo)
                                .font(.system(size: 20))
                                .frame(width: 56, height: 56)
                                .background(i == e.formato ? ColoresHoja.encendido : ColoresHoja.redondel, in: Circle())
                            Text(f.nombre).font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(ColoresHoja.texto)
                        .frame(width: 78)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func paginas(_ c: Compartible, _ e: EstadoHoja) -> some View {
        if let f = e.formato(c), !c.paginas.isEmpty {
            if f.cuantas == .ninguna {
                Text("Va entero, tal cual").font(.system(size: 12)).foregroundStyle(ColoresHoja.apagado)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(f.cuantas == .una ? "Qué página"
                            : TextosCompartir.queIncluir(e.elegidas(c).count, de: c.paginas.count))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(ColoresHoja.apagado)
                        Spacer()
                        if f.cuantas == .varias, c.paginas.count > 1 {
                            Button("Todas") { modelo.cambiar { e, c in e.todas(c) } }
                            Button("Ninguna") { modelo.cambiar { e, _ in e.ninguna() } }
                        }
                    }
                    .buttonStyle(.link)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(c.paginas) { p in
                                fila(p, marcada: e.marcadas.contains(p.clave), una: f.cuantas == .una)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(c.paginas.count) * 40, 7 * 40))
                }
            }
        }
    }

    private func fila(_ p: PaginaCompartir, marcada: Bool, una: Bool) -> some View {
        Button { modelo.cambiar { e, c in e.tocarPagina(c, p.clave) } } label: {
            HStack(spacing: 10) {
                Image(systemName: una ? (marcada ? "largecircle.fill.circle" : "circle")
                    : (marcada ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(marcada ? ColoresHoja.encendido : ColoresHoja.apagado)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.nombre).font(.system(size: 12)).foregroundStyle(ColoresHoja.texto).lineLimit(1)
                    if !p.detalle.isEmpty {
                        Text(p.detalle).font(.system(size: 10)).foregroundStyle(ColoresHoja.apagado).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.leading, CGFloat(p.nivel) * 22)
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pieDeHoja: some View {
        HStack(spacing: 8) {
            Text(modelo.aviso ?? modelo.pie)
                .font(.system(size: 12)).foregroundStyle(ColoresHoja.apagado)
                .lineLimit(1)
            Spacer()
            Button("Copiar") { modelo.salir(.copiar) }
                .help("Copiar al portapapeles (⌘C)")
            Button("Guardar como…") { modelo.salir(.guardar) }
                .help("⌘S")
            Button("Más…") { modelo.salir(.mas) }
                .help("AirDrop, Mail, Mensajes…")
                .background(Anclaje { modelo.anclaje = $0 })
            Button("Compartir") { modelo.salir(.compartir) }
                .keyboardShortcut(.defaultAction)
                .help("Dejarlo en la Salida para arrastrarlo o copiarlo (↩)")
        }
        .controlSize(.large)
    }
}

/// La `NSView` de un sitio de SwiftUI (para colgar de ella la hoja del Mac).
private struct Anclaje: NSViewRepresentable {
    let poner: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { poner(v) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - Imprimir

/// **El papel que se imprime**: una pagina por pieza, encajada y centrada
/// en la hoja de papel con su margen (`encaje` de Windows), como el lienzo
/// (`VistaImpresionLienzo`).
final class ImpresionCompartida: NSView {
    private let piezas: [PiezaCompartir]

    init(_ piezas: [PiezaCompartir]) {
        self.piezas = piezas
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    @MainActor
    static func imprimir(_ piezas: [PiezaCompartir], titulo: String) {
        let papel = ImpresionCompartida(piezas)
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        if let p = piezas.first, p.tamano.width > p.tamano.height { info.orientation = .landscape }
        let op = NSPrintOperation(view: papel, printInfo: info)
        op.jobTitle = titulo
        op.printPanel.options.insert([.showsPreview, .showsOrientation, .showsPaperSize])
        NSApp.activate()
        op.run()
    }

    override var isFlipped: Bool { true }

    private var pagina: NSSize {
        let info = NSPrintOperation.current?.printInfo ?? NSPrintInfo.shared
        return NSSize(width: info.paperSize.width - info.leftMargin - info.rightMargin,
                      height: info.paperSize.height - info.topMargin - info.bottomMargin)
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let p = pagina
        setFrameSize(NSSize(width: p.width, height: p.height * CGFloat(max(1, piezas.count))))
        range.pointee = NSRange(location: 1, length: max(1, piezas.count))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let p = pagina
        return NSRect(x: 0, y: CGFloat(page - 1) * p.height, width: p.width, height: p.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let p = pagina
        MainActor.assumeIsolated {
            for (i, pieza) in piezas.enumerated() {
                let sitio = NSRect(x: 0, y: CGFloat(i) * p.height, width: p.width, height: p.height)
                guard sitio.intersects(dirtyRect), pieza.tamano.width > 0, pieza.tamano.height > 0 else { continue }
                // Encajada y centrada, sin agrandar lo pequeno mas del doble.
                let k = min(p.width / pieza.tamano.width, p.height / pieza.tamano.height, 2)
                let w = pieza.tamano.width * k, alto = pieza.tamano.height * k
                pieza.pintar(ctx, NSRect(x: sitio.midX - w / 2, y: sitio.midY - alto / 2, width: w, height: alto))
            }
        }
    }
}
