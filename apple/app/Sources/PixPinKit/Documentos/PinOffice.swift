// **Word, Excel y PowerPoint al instante, como un pin**: el visor del propio
// sistema (Vista Rapida, `QLPreviewView`) dentro de un panel flotante. Es lo
// mas rapido que hay en Mac para un `.docx`, `.xlsx` o `.pptx` (y ODT, RTF,
// CSV, EPUB...): lo pinta el renderizador de Apple, sin cargar nada nuestro.
//
// Perezoso (§4bis): la vista nace al abrir el pin y se cierra con el
// (`QLPreviewView.close()` suelta el proceso de vista previa). Para anotar
// un Word o un PowerPoint, el boton «Leer y anotar» lo abre en el lector
// paginado (`LectoresDeDocumentos`).

import AppKit
import PixPinCore
import Quartz
import SwiftUI

@MainActor
public final class PinesDeOffice: NSObject, NSWindowDelegate {
    public static let compartidos = PinesDeOffice()

    private struct Abierto {
        let panel: NSPanel
        let vista: QLPreviewView
    }

    private var abiertos: [String: Abierto] = [:]

    /// Abre `url` en un pin con Vista Rapida. `nucleo`: si se da, el pin de
    /// un Word o un PowerPoint ofrece abrirlo en el lector para anotar.
    public func abrir(_ url: URL, nucleo: Nucleo? = nil) {
        let clave = url.standardizedFileURL.path
        if let a = abiertos[clave] {
            a.panel.makeKeyAndOrderFront(nil)
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        let marco = PinesDeOffice.marcoInicial()
        // Lisa, como el lector de Windows (`lector_pin.rs`): sin el marco del
        // Mac, con su barra arriba (asa, nombre, «Leer y anotar», el pin y
        // la ✕) y el documento debajo.
        let panel = NSPanel(contentRect: marco,
                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = url.lastPathComponent
        VentanaLisa.vestirEntera(panel)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier(clave)
        guard let vista = QLPreviewView(frame: CGRect(origin: .zero, size: marco.size), style: .normal) else {
            NSSound.beep()
            return
        }
        vista.shouldCloseWithWindow = true
        vista.autostarts = true
        vista.previewItem = url as NSURL
        var leer: (() -> Void)?
        if let nucleo, TiposDeDocumento.clase(de: url) == .officePaginado {
            // «Leer y anotar»: el lector paginado como Office, con tinta.
            leer = { [weak panel] in
                LectoresDeDocumentos.compartidos.abrir(url, nucleo: nucleo)
                panel?.close()
            }
        }
        let barra = NSHostingView(rootView: BarraPinOffice(nombre: url.lastPathComponent,
                                                           ventana: RefVentana(panel), leer: leer))
        // Hasta arriba del todo: la barra del titulo no se ve, no aparta nada.
        barra.safeAreaRegions = []
        let contenedor = NSView(frame: CGRect(origin: .zero, size: marco.size))
        for v in [barra, vista] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        NSLayoutConstraint.activate([
            barra.topAnchor.constraint(equalTo: contenedor.topAnchor),
            barra.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            barra.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            vista.topAnchor.constraint(equalTo: barra.bottomAnchor),
            vista.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            vista.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            vista.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
        ])
        panel.contentView = contenedor
        abiertos[clave] = Abierto(panel: panel, vista: vista)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Un tercio de la pantalla a la derecha, de alto casi entero.
    private static func marcoInicial() -> CGRect {
        let pantalla = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let ancho = min(max(pantalla.width / 3, 480), 900)
        let alto = pantalla.height * 0.85
        return CGRect(x: pantalla.maxX - ancho - 24, y: pantalla.minY + (pantalla.height - alto) / 2,
                      width: ancho, height: alto)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let clave = panel.identifier?.rawValue,
              let a = abiertos.removeValue(forKey: clave) else { return }
        a.vista.close()
    }
}

/// **La barra del pin de Office**, como la de los lectores de Windows: el
/// asa y el nombre a la izquierda (se arrastra desde cualquier hueco), y a
/// la derecha «Leer y anotar», el pin (siempre encima o no) y la ✕.
struct BarraPinOffice: View {
    let nombre: String
    let ventana: RefVentana
    let leer: (() -> Void)?
    @State private var encima = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(nombre)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let leer {
                Button("Leer y anotar", action: leer)
                    .controlSize(.small)
                    .help("Abrirlo en el lector, para anotar encima")
            }
            BotonPlano(simbolo: encima ? "pin.fill" : "pin", ayuda: "Siempre encima, como un pin",
                       encendido: encima) {
                encima.toggle()
                ventana.ventana?.level = encima ? .floating : .normal
            }
            BotonesDeVentana(ventana: ventana)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        // Los huecos de la barra (y el nombre) llevan la ventana, como el asa
        // de Windows; los botones van antes.
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
