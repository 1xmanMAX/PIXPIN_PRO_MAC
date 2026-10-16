// **El visor de HTML de PixPin** (tanda D9): `visor_html.rs` de Windows (y
// `VisorHtmlActivity.kt` de Android) con `WKWebView`.
//
// Un `.html` del chat se abre DENTRO de PixPin, del tamano de la pantalla y
// sin cromo (ni direcciones, ni pestanas): lisa, como los lectores, con su
// barra flotante (el asa y el nombre, exportar, el pin, pantalla completa y
// la ✕). ⎋ cierra, tambien escribiendo dentro de la pagina; ⌘E exporta.
//
// Lo que resuelve, como alla: estos HTML los genera PixPin y traen su
// propio boton de guardar. En un navegador ese boton DESCARGA una copia; aqui
// se guarda **encima del mismo fichero**, por los dos caminos de Windows:
//
// 1. el puente `PixPinVisor.guardar(nombre, base64)` (el nombre de Android:
//    las paginas ya lo llaman asi), y
// 2. para las que no lo conocen, la descarga de un `.html` (un `<a
//    download>` o un `Blob`) se desvia al fichero. Lo demas (un CSV de una
//    tabla) es una descarga de verdad y va a Descargas.
//
// Los dos pasan por el mismo filtro (`pareceHtmlCompleto`) antes de tocar
// nada: mas vale dejar pasar un guardado que quedarse sin el original.
//
// El modo oscuro de los visores (luna/sol del lector) se sigue: la pagina lo
// ve como `prefers-color-scheme`.

import AppKit
import PixPinCore
import SwiftUI
import WebKit

public extension Notification.Name {
    /// El visor guardo una pagina encima de su fichero: `object` es su ruta.
    static let pixpinHtmlGuardado = Notification.Name("PixPinHtmlGuardado")
}

@MainActor
public final class VisorHtml {
    public static let compartido = VisorHtml()
    private var abiertos: [String: ControladorVisorHtml] = [:]

    /// Si este fichero se abre con el visor propio.
    public nonisolated static func seAbre(_ url: URL) -> Bool {
        ["html", "htm"].contains(url.pathExtension.lowercased())
    }

    /// Tamano por debajo del cual no se acepta nada (el de Android).
    public nonisolated static let minimoBytes = 200

    /// **Si estos bytes parecen el HTML entero** que la pagina queria
    /// guardar: mas de 200 bytes y su `</html>` (en mayusculas o no).
    public nonisolated static func pareceHtmlCompleto(_ datos: Data) -> Bool {
        guard datos.count > minimoBytes else { return false }
        return String(decoding: datos, as: UTF8.self).lowercased().contains("</html>")
    }

    /// Si una descarga es la propia pagina (su boton de guardar baja un
    /// `.html`) y no otra cosa.
    public nonisolated static func esLaPagina(nombreSugerido: String) -> Bool {
        seAbre(URL(fileURLWithPath: nombreSugerido))
    }

    /// Escribe `datos` sobre `url` sin dejarla a medias: a un temporal al
    /// lado y luego de un tiron.
    public nonisolated static func escribirEncima(_ url: URL, _ datos: Data) throws {
        let temporal = url.deletingPathExtension().appendingPathExtension("pixpin-tmp")
        try datos.write(to: temporal)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporal)
    }

    /// Abre `url` en el visor (o trae el que ya estaba).
    public func abrir(_ url: URL, nucleo: Nucleo?) {
        let clave = url.standardizedFileURL.path
        if let c = abiertos[clave] {
            c.ventana.makeKeyAndOrderFront(nil)
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        let c = ControladorVisorHtml(url: url, nucleo: nucleo)
        c.alCerrar = { [weak self] in self?.abiertos[clave] = nil }
        abiertos[clave] = c
        c.mostrar()
    }
}

/// **Un `.html` abierto en el visor.**
@MainActor
final class ControladorVisorHtml: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate,
    WKUIDelegate, WKDownloadDelegate {
    let url: URL
    let ventana: NSWindow
    let web: WKWebView
    private let modelo = ModeloVisorHtml()
    private var barra: BarraFlotante?
    private var teclas: Any?
    private var vigias: [NSObjectProtocol] = []
    /// Las descargas que son la pagina: a que temporal van.
    private var desviadas: [ObjectIdentifier: URL] = [:]
    var alCerrar: (() -> Void)?

    /// Lo que la pagina ve como `window.PixPinVisor` (antes de su `<head>`).
    nonisolated static let puente = """
    window.PixPinVisor = { guardar: function(nombre, base64) { \
    window.webkit.messageHandlers.pixpinVisor.postMessage({tipo: "guardar", nombre: String(nombre), datos: String(base64)}); } };
    """

    init(url: URL, nucleo: Nucleo?) {
        self.url = url
        let conf = WKWebViewConfiguration()
        conf.userContentController.addUserScript(WKUserScript(source: ControladorVisorHtml.puente,
                                                              injectionTime: .atDocumentStart, forMainFrameOnly: false))
        web = WKWebView(frame: .zero, configuration: conf)
        // El area de trabajo, como Windows: sin marco propio, la barra de
        // menus y el Dock siguen ahi para cambiar de ventana.
        let marco = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        ventana = NSWindow(contentRect: marco, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        conf.userContentController.add(Debil(self), name: "pixpinVisor")
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        ventana.title = url.lastPathComponent
        VentanaLisa.vestirEntera(ventana)
        ventana.isReleasedWhenClosed = false
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.delegate = self
        ventana.contentView = web
        ventana.setFrame(marco, display: false)
        modelo.nombre = url.lastPathComponent
        modelo.controlador = self
        let modelo = self.modelo
        barra = BarraFlotante(ventana: ventana) { BarraVisorHtml(modelo: modelo) }
        // El modo oscuro de los visores: nunca tocado, el del Mac.
        if let nucleo {
            Task { [weak self] in
                let oscuro = await Task.detached { nucleo.lectoresOscuros() }.value
                if let oscuro { self?.ponerOscuro(oscuro) }
            }
        }
        vigias.append(NotificationCenter.default.addObserver(forName: .pixpinLectoresOscuros, object: nil, queue: .main) { [weak self] n in
            let oscuro = n.object as? Bool
            MainActor.assumeIsolated { if let oscuro { self?.ponerOscuro(oscuro) } }
        })
    }

    func mostrar() {
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        ventana.makeKeyAndOrderFront(nil)
        barra?.empezar()
        NSApp.activate()
        // ⎋ y ⌘E tambien con el foco DENTRO de la pagina: el teclado es de
        // WebKit y la ventana no lo veria.
        teclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let (n, k, f, c) = (e.windowNumber, e.keyCode, e.modifierFlags, e.charactersIgnoringModifiers ?? "")
            let suya = MainActor.assumeIsolated { () -> Bool in
                guard let self, n == self.ventana.windowNumber else { return false }
                return self.tecla(k, f, c)
            }
            return suya ? nil : e
        }
    }

    private func tecla(_ k: UInt16, _ f: NSEvent.ModifierFlags, _ letras: String) -> Bool {
        let m = f.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let c = letras.lowercased()
        if k == 53, m.isEmpty {
            // A pantalla completa, primero vuelve; si no, se cierra.
            if ventana.styleMask.contains(.fullScreen) { ventana.toggleFullScreen(nil) } else { cerrar() }
            return true
        }
        if m == .command, c == "e" { exportar(); return true }
        if m == .command, c == "w" { cerrar(); return true }
        if m == [.control, .command], c == "f" { ventana.toggleFullScreen(nil); return true }
        if k == 103, m.isEmpty { ventana.toggleFullScreen(nil); return true } // F11
        return false
    }

    func cerrar() {
        VentanaLisa.cerrar(ventana)
    }

    func pantallaCompleta() {
        ventana.toggleFullScreen(nil)
    }

    private func ponerOscuro(_ oscuro: Bool) {
        web.appearance = NSAppearance(named: oscuro ? .darkAqua : .aqua)
    }

    /// **Exportar la pagina** con la hoja comun (la pagina, el original, su
    /// PDF...).
    func exportar() {
        HojaCompartir.abrir(.ficheros(titulo: url.deletingPathExtension().lastPathComponent, [url]), almacen: nil)
    }

    // MARK: Guardar encima

    /// Lo que la pagina manda guardar, al fichero del chat.
    private func guardar(_ datos: Data) {
        guard VisorHtml.pareceHtmlCompleto(datos) else {
            modelo.avisar("No se guardó: no parece la página entera")
            return
        }
        do {
            try VisorHtml.escribirEncima(url, datos)
            modelo.avisar("Guardado")
            NotificationCenter.default.post(name: .pixpinHtmlGuardado, object: url.path)
        } catch {
            modelo.avisar("No se pudo guardar")
        }
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], d["tipo"] as? String == "guardar",
              let b64 = d["datos"] as? String,
              let datos = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return }
        guardar(datos)
    }

    // MARK: Descargas

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.shouldPerformDownload { return (.download, preferences) }
        // Un enlace de fuera, al navegador: el visor es para esta pagina.
        if navigationAction.navigationType == .linkActivated, let u = navigationAction.request.url,
           ["http", "https", "mailto"].contains(u.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(u)
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let gestor = FileManager.default
        if VisorHtml.esLaPagina(nombreSugerido: suggestedFilename) {
            // La pagina: a un temporal nuestro, y al acabar, encima.
            let t = gestor.temporaryDirectory.appendingPathComponent("pixpin-visor-\(UUID().uuidString).html")
            desviadas[ObjectIdentifier(download)] = t
            return t
        }
        // Una descarga de verdad: a Descargas, sin pisar lo que haya.
        let carpeta = gestor.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? gestor.temporaryDirectory
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var destino = carpeta.appendingPathComponent(suggestedFilename)
        var n = 2
        while gestor.fileExists(atPath: destino.path) {
            destino = carpeta.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        modelo.avisar("Descargado en Descargas: \(destino.lastPathComponent)")
        return destino
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let t = desviadas.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if let datos = try? Data(contentsOf: t) { guardar(datos) }
        try? FileManager.default.removeItem(at: t)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let t = desviadas.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: t)
        }
    }

    /// `target="_blank"` y `window.open`: al navegador.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
        return nil
    }

    // MARK: Cerrar

    func windowWillClose(_ notification: Notification) {
        if let teclas { NSEvent.removeMonitor(teclas) }
        teclas = nil
        vigias.forEach(NotificationCenter.default.removeObserver)
        vigias = []
        barra?.terminar()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "pixpinVisor")
        web.stopLoading()
        alCerrar?()
    }
}

/// El puente sin retener al visor (`WKUserContentController` retiene a quien
/// recibe los mensajes).
private final class Debil: NSObject, WKScriptMessageHandler {
    weak var destino: WKScriptMessageHandler?
    init(_ d: WKScriptMessageHandler) { destino = d }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        destino?.userContentController(uc, didReceive: message)
    }
}

/// Lo que ve la barra del visor.
@MainActor
final class ModeloVisorHtml: ObservableObject {
    @Published var nombre = ""
    @Published var encima = false
    @Published var nota: String?
    weak var controlador: ControladorVisorHtml?
    private var tarea: DispatchWorkItem?

    /// Un aviso en la barra que se va solo.
    func avisar(_ t: String) {
        nota = t
        tarea?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.nota = nil } }
        tarea = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }
}

/// **La barra del visor**, la de los lectores: el asa y el nombre, exportar,
/// el pin (siempre encima), pantalla completa y la ✕.
struct BarraVisorHtml: View {
    @ObservedObject var modelo: ModeloVisorHtml

    var body: some View {
        HStack(spacing: 8) {
            AsaBarra()
            Text(modelo.nota ?? modelo.nombre)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Divider().frame(height: 22)
            BotonFlotante(simbolo: "square.and.arrow.up", ayuda: "Exportar (⌘E)") {
                modelo.controlador?.exportar()
            }
            BotonFlotante(simbolo: modelo.encima ? "pin.fill" : "pin", ayuda: "Siempre encima, como un pin",
                          encendido: modelo.encima) {
                modelo.encima.toggle()
                modelo.controlador?.ventana.level = modelo.encima ? .floating : .normal
            }
            BotonFlotante(simbolo: "arrow.up.left.and.arrow.down.right", ayuda: "Pantalla completa (F11)") {
                modelo.controlador?.pantallaCompleta()
            }
            BotonFlotante(simbolo: "xmark", ayuda: "Cerrar (⎋)") { modelo.controlador?.cerrar() }
        }
        .fixedSize()
    }
}
