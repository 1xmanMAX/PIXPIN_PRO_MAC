// **El editor de notas de Windows, en el Mac** (`notas_md/lector_web.rs`):
// la misma pagina (CodeMirror con el Markdown vivo, la barra flotante, el
// menu `/`, tablas, formulas, casillas, fotos bajo su renglon, comentarios
// al margen, letra y tamano) dentro de un `WKWebView`. La pagina y lo que
// hay que hacer con cada mensaje suyo son de Rust (`SesionNota`, N/notas/
// web.rs); aqui solo lo del Mac: la ventana, los paneles de abrir y guardar,
// la hoja de compartir y el esquema `pixpin-nota://` de las fotos.
//
// Guardar: la pagina pide guardar a los 0,8 s de dejar de escribir; Rust
// escribe en el cuaderno (o en el `.md`) en una cola aparte, en orden. Lo
// que llega de otro aparato se mira cada 2 s y entra solo si aqui no hay
// nada sin guardar. Al cerrar, la pagina guarda lo ultimo antes (3 s como
// mucho, como Windows).
//
// Teclas (las de Windows con ⌘): ⌘B/I/E/K, ⇧⌘X, ⌘M formula, ⌥⌘M
// comentario, ⌘1/2/3, ⇧⌘8/7/9, ⌘↩, ⇧⌘. /C/T/D, ⌘S, ⇧⌘S, ⌘F, ⌘+/−,
// ⌘-clic en un enlace (el puente de N/notas/web.rs).

import AppKit
import PixPinCore
import UniformTypeIdentifiers
import SwiftUI
import WebKit

/// La vista web de la nota: recuerda el ultimo clic para mover la ventana
/// desde la cabecera de la pagina. Las teclas con ⌘ ya van a la pagina antes
/// que a los menus del Mac (WebKit se las da primero; si la pagina no las
/// quiere, siguen a los menus).
final class VistaWebNota: WKWebView {
    private(set) var ultimoClic: NSEvent?

    override func mouseDown(with event: NSEvent) {
        ultimoClic = event
        super.mouseDown(with: event)
    }
}

/// Las fotos, audios y videos que pide la pagina (`pixpin-nota://nota/
/// archivo?r=…`), leidos fuera del hilo principal.
final class EsquemaNota: NSObject, WKURLSchemeHandler {
    let sesion: SesionNota
    private var parados = Set<ObjectIdentifier>()
    private let cola = DispatchQueue(label: "pixpin.nota.fotos", qos: .userInitiated, attributes: .concurrent)

    init(sesion: SesionNota) {
        self.sesion = sesion
    }

    func webView(_ webView: WKWebView, start tarea: WKURLSchemeTask) {
        let id = ObjectIdentifier(tarea)
        let url = tarea.request.url
        let sesion = self.sesion
        cola.async { [weak self] in
            let r = url.flatMap { sesion.servir(peticion: $0.absoluteString) }
            DispatchQueue.main.async {
                guard let self, !self.parados.contains(id) else { return }
                guard let r, let url else {
                    tarea.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": r.tipo,
                    "Content-Length": "\(r.datos.count)",
                    "Cache-Control": "no-store",
                ])
                tarea.didReceive(resp ?? URLResponse(url: url, mimeType: r.tipo, expectedContentLength: r.datos.count, textEncodingName: nil))
                tarea.didReceive(r.datos)
                tarea.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop tarea: WKURLSchemeTask) {
        parados.insert(ObjectIdentifier(tarea))
    }
}

/// Los mensajes de la pagina, sin que la vista retenga al controlador.
private final class PuenteDebil: NSObject, WKScriptMessageHandler {
    weak var destino: ControladorNotaWeb?

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let texto = m.body as? String else { return }
        MainActor.assumeIsolated { destino?.recibir(texto) }
    }
}

/// **Una nota abierta en el editor web.**
@MainActor
final class ControladorNotaWeb: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let sesion: SesionNota
    let chat: String?
    let mensaje: MensajeChat?
    let almacen: Almacen?
    let ventana: NSWindow
    let web: VistaWebNota
    private let puente = PuenteDebil()
    private let esquema: EsquemaNota
    private let cola = DispatchQueue(label: "pixpin.nota.web", qos: .userInitiated)
    private var mirar: Timer?
    /// La barra comun de los visores, fuera de la ventana (Windows, 17-oct:
    /// el lector de notas como pin): siempre encima, pantalla completa.
    private var barra: BarraFlotante?
    private let estadoBarra = EstadoBarraNota()
    private var cerrarYa = false
    private var cerrando = false
    var alCerrar: (@MainActor (ControladorNotaWeb) -> Void)?
    /// Pidio el editor de antes: quien lo abrio lo abre con la misma nota.
    var alPedirAnterior: (@MainActor (ControladorNotaWeb) -> Void)?

    init(sesion: SesionNota, chat: String?, mensaje: MensajeChat?, almacen: Almacen?) {
        self.sesion = sesion
        self.chat = chat
        self.mensaje = mensaje
        self.almacen = almacen
        esquema = EsquemaNota(sesion: sesion)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(esquema, forURLScheme: "pixpin-nota")
        config.userContentController.add(puente, name: "pixpin")
        config.preferences.isElementFullscreenEnabled = false
        web = VistaWebNota(frame: NSRect(x: 0, y: 0, width: 760, height: 820), configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        puente.destino = self
        web.navigationDelegate = self
        web.uiDelegate = self
        ventana.contentView = web
        ventana.isReleasedWhenClosed = false
        ventana.delegate = self
        ventana.title = sesion.titulo()
        ventana.backgroundColor = NSColor(srgbRed: 0x13 / 255, green: 0x14 / 255, blue: 0x15 / 255, alpha: 1)
        ventana.minSize = NSSize(width: 420, height: 320)
        // La pagina lleva su cabecera (titulo, compartir, −, ☐, ✕): la ventana
        // va entera, sin franja del Mac.
        VentanaLisa.vestirEntera(ventana)
        VentanaLisa.escaparConVigia(ventana)
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.center()
        _ = ventana.setFrameAutosaveName("PixPinNotaWeb")
        web.loadHTMLString(notaPagina(), baseURL: URL(string: "pixpin-nota://nota/"))
        estadoBarra.nombre = sesion.titulo()
        let estado = estadoBarra
        let v = ventana
        barra = BarraFlotante(ventana: ventana) {
            BarraNotaPin(estado: estado, ventana: RefVentana(v), orden: { [weak self] que in
                self?.mandar(#"{"tipo":"orden","que":"\#(que)"}"#)
            }, escuchar: { [weak self] in self?.escuchar() })
        }
        mirar = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirarFuera() }
        }
    }

    func mostrar() {
        ventana.makeKeyAndOrderFront(nil)
        barra?.empezar()
        ventana.makeFirstResponder(web)
        NSApp.activate()
    }

    // MARK: La pagina

    /// Un mensaje de la pagina: Rust decide (en su cola, en orden: guardar es
    /// bloqueante) y aqui se hace lo que diga.
    func recibir(_ texto: String) {
        let sesion = self.sesion
        cola.async { [weak self] in
            let ordenes = sesion.recibir(mensaje: texto)
            guard !ordenes.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.hacer(ordenes) }
            }
        }
    }

    /// Manda un JSON a la pagina (`window.__pixpin`).
    func mandar(_ json: String) {
        web.evaluateJavaScript("window.__pixpin(\(json))", completionHandler: nil)
    }

    private func hacer(_ ordenes: [OrdenNota]) {
        for o in ordenes {
            switch o {
            case let .mandar(json):
                mandar(json)
            case let .guardada(m):
                if let m, let chat { almacen?.sustituir(m, en: chat) }
            case let .elegir(imagenes):
                elegir(imagenes: imagenes)
            case let .guardarComo(nombre, ext, datos):
                guardarComo(nombre: nombre, extension: ext, datos: datos)
            case let .ventana(accion):
                ventanaHace(accion)
            case let .titulo(texto):
                let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                ventana.title = t.isEmpty ? sesion.titulo() : t
                estadoBarra.nombre = ventana.title
            case let .estadoBarra(leyendo, comentarios):
                estadoBarra.leyendo = leyendo
                estadoBarra.comentarios = comentarios
            case let .abrirEnlace(url):
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            case let .abrirFichero(ruta):
                abrir(fichero: URL(fileURLWithPath: ruta))
            case .abrirMensaje:
                // Falta saltar al mensaje en su chat (la ventana del chat no
                // tiene aun por donde pedirlo desde fuera).
                NSSound.beep()
            case let .compartir(titulo, texto):
                compartir(titulo: titulo, texto: texto)
            case .cerrar:
                cerrarYa = true
                ventana.close()
            case .editorAnterior:
                cerrarYa = true
                ventana.close()
                alPedirAnterior?(self)
            }
        }
    }

    /// **Leer la nota en voz alta** (la voz de la app, como el lector);
    /// otra vez, se calla.
    private func escuchar() {
        let voz = LeerEnVoz.compartida
        guard let ruta = sesion.fichero() else { return NSSound.beep() }
        if voz.suena(ruta) { return voz.soltar() }
        guard let texto = try? String(contentsOfFile: ruta, encoding: .utf8),
              VozDeLaNota.escuchar(texto: texto, desde: 0, clave: ruta, titulo: sesion.titulo()) else {
            return NSSound.beep()
        }
    }

    private func mirarFuera() {
        let sesion = self.sesion
        cola.async { [weak self] in
            guard let json = sesion.mirarFuera() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.mandar(json) }
            }
        }
    }

    // MARK: Lo del Mac

    private func elegir(imagenes: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if imagenes { panel.allowedContentTypes = [.image] }
        panel.beginSheetModal(for: ventana) { [weak self] r in
            guard r == .OK, let self else { return }
            let rutas = panel.urls.map(\.path)
            let sesion = self.sesion
            self.cola.async { [weak self] in
                guard let json = sesion.adjuntarFicheros(rutas: rutas) else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.mandar(json) }
                }
            }
        }
    }

    private func guardarComo(nombre: String, extension ext: String, datos: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = nombre + "." + ext
        if let t = UTType(filenameExtension: ext) { panel.allowedContentTypes = [t] }
        panel.beginSheetModal(for: ventana) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            do {
                try datos.write(to: url, options: .atomic)
            } catch {
                let a = NSAlert(error: error)
                if let v = self?.ventana { a.beginSheetModal(for: v) } else { a.runModal() }
            }
        }
    }

    private func ventanaHace(_ accion: String) {
        switch accion {
        case "arrastrar":
            if let e = web.ultimoClic { ventana.performDrag(with: e) }
        case "minimizar":
            ventana.miniaturize(nil)
        case "maximizar":
            ventana.zoom(nil)
        case "pantalla":
            ventana.toggleFullScreen(nil)
        default:
            break
        }
    }

    /// Una foto de la nota se ve como pin (como en Windows); lo demas, con su
    /// programa.
    private func abrir(fichero url: URL) {
        let foto = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        if foto, GestorPines.compartido.pinear(fichero: url) { return }
        NSWorkspace.shared.open(url)
    }

    /// La hoja de compartir del Mac con la nota como `.md` (y su texto).
    private func compartir(titulo: String, texto: String) {
        let limpio = titulo.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "_")
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-notas", isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appendingPathComponent((limpio.isEmpty ? "Nota" : limpio) + ".md")
        var cosas: [Any] = [texto]
        if (try? texto.write(to: url, atomically: true, encoding: .utf8)) != nil { cosas = [url] }
        let picker = NSSharingServicePicker(items: cosas)
        let ancla = NSRect(x: web.bounds.maxX - 220, y: web.bounds.maxY - 44, width: 1, height: 1)
        picker.show(relativeTo: ancla, of: web, preferredEdge: .minY)
    }

    // MARK: Delegados

    func webView(_ webView: WKWebView, decidePolicyFor accion: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // Solo la propia pagina; un enlace que se escape va al navegador.
        if accion.navigationType == .linkActivated, let url = accion.request.url {
            let s = url.scheme?.lowercased() ?? ""
            if ["http", "https", "mailto"].contains(s) { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith c: WKWebViewConfiguration,
                 for accion: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = accion.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Se cayo la pagina: se vuelve a cargar con lo guardado.
        webView.loadHTMLString(notaPagina(), baseURL: URL(string: "pixpin-nota://nota/"))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if cerrarYa { return true }
        if !cerrando {
            cerrando = true
            mandar(#"{"tipo":"cerrando"}"#)
            // Si la pagina no contesta (colgada), se cierra igual: lo ultimo
            // se guardo hace como mucho 0,8 s.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.cerrarYa else { return }
                    self.cerrarYa = true
                    self.ventana.close()
                }
            }
        }
        return false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        mandar(#"{"tipo":"pantalla","si":true}"#)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        mandar(#"{"tipo":"pantalla","si":false}"#)
    }

    func windowWillClose(_ notification: Notification) {
        mirar?.invalidate()
        mirar = nil
        barra?.terminar()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "pixpin")
        alCerrar?(self)
    }
}


/// Lo que ensena la barra de una nota.
@MainActor
final class EstadoBarraNota: ObservableObject {
    @Published var nombre = ""
    @Published var encima = false
    /// Viendo la nota sin escribir (el «ojo»), y los comentarios abiertos.
    @Published var leyendo = false
    @Published var comentarios = false
}

/// **La barra de la nota como pin**: el asa, el nombre con su recuadro
/// «MD», siempre encima, pantalla completa y cerrar (lo de la nota en si
/// va en la cabecera de la pagina).
struct BarraNotaPin: View {
    @ObservedObject var estado: EstadoBarraNota
    let ventana: RefVentana
    /// Una orden para la pagina (`leer`, `editar`, `deshacer`, `rehacer`,
    /// `buscar`, `comentarios`, `compartir`, `mas`, `titulo`).
    let orden: (String) -> Void
    /// Leer la nota en voz alta.
    var escuchar: () -> Void = {}
    @ObservedObject var voz = LeerEnVoz.compartida

    var body: some View {
        BarraVisor(nombre: estado.nombre, ext: "md", renombrar: { orden("titulo") },
                   fijar: { si in
                       estado.encima = si
                       ventana.ventana?.level = si ? .floating : .normal
                   }) {
            // Los de Windows (`notas_md::lector_web::botones`): leyendo, el
            // lapiz; escribiendo, el ojo, deshacer y rehacer; y siempre
            // buscar, los comentarios, compartir y el ⋯. Y escuchar.
            BotonVerEditar(editando: !estado.leyendo) { orden(estado.leyendo ? "editar" : "leer") }
            if !estado.leyendo {
                BotonFlotante(simbolo: "arrow.uturn.backward", ayuda: "Deshacer (⌘Z)") { orden("deshacer") }
                BotonFlotante(simbolo: "arrow.uturn.forward", ayuda: "Rehacer (⇧⌘Z)") { orden("rehacer") }
            }
            BotonFlotante(simbolo: "speaker.wave.2", ayuda: "Leer en voz alta", encendido: voz.vivo,
                          accion: escuchar)
            BotonFlotante(simbolo: "magnifyingglass", ayuda: "Buscar (⌘F)") { orden("buscar") }
            BotonFlotante(simbolo: "text.bubble", ayuda: "Comentarios", encendido: estado.comentarios) {
                orden("comentarios")
            }
            BotonFlotante(simbolo: "square.and.arrow.up", ayuda: "Compartir") { orden("compartir") }
            BotonFlotante(simbolo: "ellipsis", ayuda: "Más") { orden("mas") }
        }
    }
}
