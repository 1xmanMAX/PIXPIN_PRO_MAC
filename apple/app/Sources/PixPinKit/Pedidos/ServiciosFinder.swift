// **Los Servicios del Finder** (C2): el menu del Explorador de Windows
// (`herramientas/integraciones.ps1`, «PixPin ▸ Al chat, Pinear, Copiar
// texto (OCR), Enviar al movil, Preguntar al asistente»). En el Mac son
// `NSServices` del Info.plist: clic derecho en el Finder → Servicios (o
// Acciones rapidas). Cada uno es el verbo de la linea de ordenes con los
// ficheros elegidos (`Verbos.deArgumentos`), todos en una sola llamada (lo
// que en Windows hace `--juntar`).

import AppKit
import Foundation

@MainActor
public final class ServiciosFinder: NSObject {
    public static let compartidos = ServiciosFinder()

    /// Los servicios: el `NSMessage` del Info.plist y su verbo.
    public static let servicios: [(mensaje: String, verbo: String)] = [
        ("alChat", "chat"),
        ("pinear", "pinear"),
        ("copiarTexto", "copiar-texto"),
        ("alMovil", "al-movil"),
        ("preguntarAlAsistente", "asistente"),
    ]

    /// La orden de un servicio con sus ficheros.
    public nonisolated static func orden(verbo: String, rutas: [String]) -> Result<LlamadaOrden, FalloOrden>? {
        Verbos.deArgumentos([verbo, "--"] + rutas, esFichero: { FileManager.default.fileExists(atPath: $0) })
    }

    private func hacer(_ verbo: String, _ pboard: NSPasteboard,
                       _ error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "PixPin: no hay ficheros" as NSString
            return
        }
        switch ServiciosFinder.orden(verbo: verbo, rutas: urls.map(\.path)) {
        case let .success(l)?: HacerPedidos.compartidos.hacer(l)
        case let .failure(f)?: HacerPedidos.aviso(f.motivo)
        case nil: NSSound.beep()
        }
    }

    @objc func alChat(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        hacer("chat", pboard, error)
    }

    @objc func pinear(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        hacer("pinear", pboard, error)
    }

    @objc func copiarTexto(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        hacer("copiar-texto", pboard, error)
    }

    @objc func alMovil(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        hacer("al-movil", pboard, error)
    }

    @objc func preguntarAlAsistente(_ pboard: NSPasteboard, userData: String?,
                                    error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        hacer("asistente", pboard, error)
    }
}
