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
        let barra: BarraFlotante
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
        // Mac, el documento en todo el panel y su barra (asa, nombre, «Leer
        // y anotar», el pin y la ✕) flotando encima, con el raton.
        let panel = NSPanel(contentRect: marco,
                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = url.lastPathComponent
        VentanaLisa.vestirEntera(panel)
        VentanaLisa.recordar(panel, clave: url.pathExtension)
        VentanaLisa.escaparConVigia(panel)
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
        let nombre = url.lastPathComponent
        // Un PowerPoint se presenta (D9), como el boton del lector.
        let presentar: (() -> Void)? = Diapositivas.sePresenta(url) ? { Diapositivas.presentar(url) } : nil
        let barra = BarraFlotante(ventana: panel) {
            BarraPinOffice(nombre: nombre, ventana: RefVentana(panel), leer: leer, presentar: presentar, url: url)
        }
        panel.contentView = vista
        abiertos[clave] = Abierto(panel: panel, vista: vista, barra: barra)
        barra.empezar()
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
        a.barra.terminar()
        a.vista.close()
    }
}

/// **La barra del pin de Office**, como la de los lectores de Windows: el
/// asa y el nombre a la izquierda, y a la derecha «Leer y anotar», presentar
/// (un PowerPoint), el pin
/// (siempre encima o no) y la ✕. Flota encima del panel (`BarraFlotante`).
struct BarraPinOffice: View {
    let nombre: String
    let ventana: RefVentana
    let leer: (() -> Void)?
    var presentar: (() -> Void)?
    var url: URL?

    var body: some View {
        BarraVisor(nombre: nombre, ext: (nombre as NSString).pathExtension) {
            // Los de Windows (`pin_office`): presentar un PowerPoint y abrir
            // con su programa; aqui ademas el lapiz, que lo pasa al lector
            // para anotarlo.
            if let presentar {
                BotonFlotante(simbolo: "play.fill", ayuda: "Presentar", accion: presentar)
            }
            if let leer {
                BotonVerEditar(editando: false, accion: leer)
            }
            if let url {
                BotonFlotante(simbolo: "arrow.up.forward.app", ayuda: "Abrir con su programa") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
