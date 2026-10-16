// **La Salida** (D1, `salida.rs` de Windows): una ventanita flotante con lo
// que se acaba de exportar o compartir, lista para ARRASTRARLA a otro sitio.
//
// El usuario: «si comparto algun documento o archivo, que primero aparezca
// en pantalla para que pueda facilmente jalarlo a otro lugar; y si exporto,
// aparezca como una ventana para compartir y tambien aparezca el archivo y
// pueda jalarlo».
//
// - Siempre encima y abajo a la derecha de la pantalla del raton, y **sin
//   robar el foco** al aparecer (un `NSPanel` que no activa la app): el
//   usuario estaba haciendo algo y lo sigue haciendo. Al pulsarla si lo
//   toma, que es lo que hace falta para que ⎋ la cierre.
// - Una tarjeta por fichero (miniatura, nombre, tipo y peso). **Arrastrar
//   una tarjeta** la lleva a otra app o a una carpeta; con mas de uno, una
//   franja los lleva todos juntos.
// - Abajo, sobre la tarjeta elegida: Copiar (el principal, en azul), Abrir,
//   Mostrar en la carpeta y Pinear; con el boton derecho, «Abrir con…».
// - **Una sola a la vez**: lo que llega mientras esta abierta se suma
//   arriba. Soltar con exito NO la cierra: se puede querer soltar el mismo
//   fichero en otro sitio.
//
// Teclado: ⎋ cierra, ⌘C copia, ↩ abre, ↑ ↓ cambian de tarjeta.

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Salida {
    static let compartida = Salida()

    /// Los titulos de Windows (`salida-titulo`, `-exportado`, `-guardado`).
    static let listo = "Listo para compartir"
    static let exportado = "Exportado"
    static let guardado = "Guardado"

    let modelo = ModeloSalida()
    private var panel: PanelSalida?

    var abierta: Bool { panel?.isVisible == true }

    /// **Ensena** `ficheros` con `titulo`. Si ya estaba abierta, se suman
    /// arriba.
    func mostrar(_ ficheros: [URL], titulo: String? = nil) {
        let hay = ficheros.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !hay.isEmpty else { return }
        modelo.recibir(hay, titulo: titulo ?? Salida.listo)
        let panel = self.panel ?? crearPanel()
        self.panel = panel
        if !panel.isVisible { colocar(panel) }
        panel.orderFrontRegardless()
    }

    func cerrar() {
        panel?.orderOut(nil)
        modelo.vaciar()
    }

    private func crearPanel() -> PanelSalida {
        let panel = PanelSalida(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.salida = self
        let vista = NSHostingView(rootView: VistaSalida(modelo: modelo, cerrar: { [weak self] in self?.cerrar() }))
        vista.sizingOptions = [.preferredContentSize]
        panel.contentView = vista
        return panel
    }

    /// Abajo a la derecha de la pantalla del raton.
    private func colocar(_ panel: NSPanel) {
        let raton = NSEvent.mouseLocation
        let pantalla = NSScreen.screens.first { $0.frame.contains(raton) } ?? NSScreen.main
        guard let zona = pantalla?.visibleFrame else { return }
        panel.layoutIfNeeded()
        let tamano = panel.contentView?.fittingSize ?? panel.frame.size
        panel.setFrame(NSRect(x: zona.maxX - tamano.width - 16, y: zona.minY + 16,
                              width: tamano.width, height: tamano.height), display: true)
    }
}

/// El panel: puede tomar el foco al pulsarlo (para ⎋) sin activar la app
/// al aparecer.
final class PanelSalida: NSPanel {
    weak var salida: Salida?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with evento: NSEvent) {
        let m = MainActor.assumeIsolated { salida?.modelo }
        guard let m else { return super.keyDown(with: evento) }
        let mando = evento.modifierFlags.contains(.command)
        MainActor.assumeIsolated {
            switch (evento.keyCode, mando, evento.charactersIgnoringModifiers) {
            case (53, _, _): salida?.cerrar()
            case (36, _, _), (76, _, _): m.abrir()
            case (126, _, _): m.mover(-1)
            case (125, _, _): m.mover(1)
            case (_, true, "c"): m.copiar()
            default: super.keyDown(with: evento)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { salida?.cerrar() }
    }
}

// MARK: - El modelo

@MainActor
final class ModeloSalida: ObservableObject {
    @Published private(set) var titulo = Salida.listo
    /// Lo ultimo, arriba.
    @Published private(set) var ficheros: [URL] = []
    @Published var elegido = 0
    @Published private(set) var aviso: String?
    private var turno = 0

    /// Suma `nuevos` arriba (sin repetir) y elige el primero.
    func recibir(_ nuevos: [URL], titulo: String) {
        self.titulo = titulo
        ficheros = ModeloSalida.juntar(nuevos, ficheros)
        elegido = 0
    }

    /// Los nuevos arriba y los de antes detras, sin repetir.
    nonisolated static func juntar(_ nuevos: [URL], _ antes: [URL]) -> [URL] {
        var vistos = Set<String>()
        return (nuevos + antes).filter { vistos.insert($0.standardizedFileURL.path).inserted }
    }

    func vaciar() {
        ficheros = []
        elegido = 0
        aviso = nil
    }

    var actual: URL? { ficheros.indices.contains(elegido) ? ficheros[elegido] : nil }

    func mover(_ paso: Int) {
        guard !ficheros.isEmpty else { return }
        elegido = min(max(0, elegido + paso), ficheros.count - 1)
    }

    func avisar(_ texto: String) {
        aviso = texto
        turno += 1
        let t = turno
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if t == turno { aviso = nil }
        }
    }

    /// Al portapapeles: el fichero (se pega en el Finder o en un correo) y,
    /// si es una imagen, tambien la imagen (se pega en cualquier sitio).
    func copiar() {
        guard let url = actual else { return }
        Portapapeles.copiar([url])
        avisar("Copiado al portapapeles")
    }

    func abrir() {
        guard let url = actual else { return }
        if let aviso = AbrirCon.aviso(url) { return avisar(aviso) }
        NSWorkspace.shared.open(url)
    }

    func mostrarEnCarpeta() {
        guard let url = actual else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func pinear() {
        guard let url = actual else { return }
        avisar(GestorPines.compartido.pinear(fichero: url) ? "Pineado" : "No se pudo hacer")
    }
}

/// Copiar ficheros al portapapeles como lo hace Windows
/// (`copiar_imagen_y_ficheros`): los ficheros y, si hay una sola imagen,
/// tambien sus pixeles.
@MainActor
enum Portapapeles {
    static func copiar(_ urls: [URL]) {
        let tablero = NSPasteboard.general
        tablero.clearContents()
        var objetos: [NSPasteboardWriting] = urls.map { $0 as NSURL }
        if urls.count == 1, let url = urls.first, PiezasCompartir.esImagen(url), let img = NSImage(contentsOf: url) {
            objetos.append(img)
        }
        tablero.writeObjects(objetos)
    }
}

// MARK: - La vista

private enum ColoresSalida {
    static let fondo = Color(red: 0x1c / 255, green: 0x1d / 255, blue: 0x22 / 255)
    static let tarjeta = Color(red: 0x2a / 255, green: 0x2b / 255, blue: 0x31 / 255)
    static let encima = Color(red: 0x34 / 255, green: 0x35 / 255, blue: 0x3c / 255)
    static let texto = Color(red: 0xe8 / 255, green: 0xe8 / 255, blue: 0xec / 255)
    static let apagado = Color(red: 0x9a / 255, green: 0x9a / 255, blue: 0xa2 / 255)
    static let azul = Color(red: 0x1e / 255, green: 0x88 / 255, blue: 0xe5 / 255)
}

struct VistaSalida: View {
    @ObservedObject var modelo: ModeloSalida
    let cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ColoresSalida.azul)
                Text(modelo.aviso ?? modelo.titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ColoresSalida.texto)
                    .lineLimit(1)
                Spacer()
                Button(action: cerrar) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ColoresSalida.apagado)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cerrar (⎋)")
            }
            Text("Arrastra un archivo a otra app o a una carpeta")
                .font(.system(size: 11)).foregroundStyle(ColoresSalida.apagado)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(modelo.ficheros.enumerated()), id: \.element) { i, url in
                        TarjetaSalida(url: url, elegida: i == modelo.elegido, modelo: modelo)
                            .overlay(Arrastre(urls: [url], alPulsar: { modelo.elegido = i },
                                              alSoltar: { modelo.avisar("Soltado · puedes soltarlo en otro sitio") }))
                            .contextMenu {
                                MenuAbrirCon(url: url, avisar: modelo.avisar)
                            }
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(modelo.ficheros.count) * 66, 4 * 66))
            if modelo.ficheros.count > 1 {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Arrastrar los \(modelo.ficheros.count) juntos").font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(ColoresSalida.texto)
                .padding(.horizontal, 10).frame(height: 32)
                .background(ColoresSalida.encima, in: RoundedRectangle(cornerRadius: 8))
                .overlay(Arrastre(urls: modelo.ficheros, alPulsar: {},
                                  alSoltar: { modelo.avisar("Soltado · puedes soltarlo en otro sitio") }))
                .help("Mantén pulsado y arrastra para llevarlos todos")
            }
            HStack(spacing: 6) {
                Button { modelo.copiar() } label: { Label("Copiar", systemImage: "doc.on.doc") }
                    .buttonStyle(BotonSalida(principal: true))
                Button { modelo.abrir() } label: { Label("Abrir", systemImage: "arrow.up.forward.square") }
                    .buttonStyle(BotonSalida())
                Button { modelo.mostrarEnCarpeta() } label: { Label("Carpeta", systemImage: "folder") }
                    .buttonStyle(BotonSalida())
                    .help("Mostrar en la carpeta")
                Button { modelo.pinear() } label: { Label("Pinear", systemImage: "pin") }
                    .buttonStyle(BotonSalida())
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(ColoresSalida.fondo, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }
}

private struct BotonSalida: ButtonStyle {
    var principal = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: principal ? .semibold : .regular))
            .foregroundStyle(ColoresSalida.texto)
            .padding(.horizontal, 10).frame(height: 28)
            .background(principal ? ColoresSalida.azul : ColoresSalida.encima, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Una tarjeta: miniatura, nombre, tipo y peso.
private struct TarjetaSalida: View {
    let url: URL
    let elegida: Bool
    @ObservedObject var modelo: ModeloSalida
    @State private var miniatura: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: miniatura ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ColoresSalida.texto)
                    .lineLimit(1).truncationMode(.middle)
                Text(Self.detalle(url)).font(.system(size: 11)).foregroundStyle(ColoresSalida.apagado)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(height: 60)
        .background(ColoresSalida.tarjeta, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(elegida ? ColoresSalida.azul : .clear, lineWidth: 2))
        .task(id: url) {
            let pedido = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 48, height: 48),
                                                      scale: 2, representationTypes: .thumbnail)
            if let m = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido) {
                miniatura = m.nsImage
            }
        }
    }

    /// «Documento PDF · 1,2 MB».
    static func detalle(_ url: URL) -> String {
        let tipo = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? url.pathExtension.uppercased()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "\(tipo) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }
}

// MARK: - Arrastrar

/// **Lo que se arrastra**: una capa encima de la tarjeta que, al arrastrar,
/// lleva sus ficheros a otra app (como `pixpin_pin::arrastrar` de Windows),
/// y al pulsar sin arrastrar la elige.
private struct Arrastre: NSViewRepresentable {
    let urls: [URL]
    let alPulsar: () -> Void
    let alSoltar: () -> Void

    func makeNSView(context: Context) -> VistaArrastre { VistaArrastre() }

    func updateNSView(_ v: VistaArrastre, context: Context) {
        v.urls = urls
        v.alPulsar = alPulsar
        v.alSoltar = alSoltar
    }
}

final class VistaArrastre: NSView, NSDraggingSource {
    var urls: [URL] = []
    var alPulsar: () -> Void = {}
    var alSoltar: () -> Void = {}
    private var inicio: NSPoint?

    override func mouseDown(with evento: NSEvent) {
        inicio = evento.locationInWindow
        alPulsar()
    }

    override func mouseDragged(with evento: NSEvent) {
        guard let inicio, hypot(evento.locationInWindow.x - inicio.x, evento.locationInWindow.y - inicio.y) > 3,
              !urls.isEmpty else { return }
        self.inicio = nil
        let local = convert(evento.locationInWindow, from: nil)
        let cosas = urls.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icono = NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(NSRect(x: local.x - 24 + CGFloat(i) * 6, y: local.y - 24 - CGFloat(i) * 6,
                                         width: 48, height: 48), contents: icono)
            return item
        }
        beginDraggingSession(with: cosas, event: evento, source: self)
    }

    override func mouseUp(with evento: NSEvent) { inicio = nil }

    override func rightMouseDown(with evento: NSEvent) {
        // El menu de la tarjeta («Abrir con…») lo pone SwiftUI debajo.
        alPulsar()
        super.rightMouseDown(with: evento)
    }

    nonisolated func draggingSession(_ s: NSDraggingSession,
                                     sourceOperationMaskFor contexto: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic]
    }

    nonisolated func draggingSession(_ s: NSDraggingSession, endedAt punto: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        MainActor.assumeIsolated { alSoltar() }
    }
}
