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
import PDFKit
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
        conf.userContentController.addUserScript(WKUserScript(source: CapaTintaWeb.guion,
                                                              injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: conf)
        // El area de trabajo, como Windows: sin marco propio, la barra de
        // menus y el Dock siguen ahi para cambiar de ventana.
        let marco = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        ventana = NSWindow(contentRect: marco, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        conf.userContentController.add(Debil(self), name: "pixpinVisor")
        conf.userContentController.add(Debil(self), name: "pixpinScroll")
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        // Zoom: pellizco y ⌘+ / ⌘− / ⌘0 (la tinta y los marcos lo siguen).
        web.allowsMagnification = true
        ventana.title = url.lastPathComponent
        VentanaLisa.vestirEntera(ventana)
        ventana.isReleasedWhenClosed = false
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.delegate = self
        // La pagina entera y, encima, el riel (marcadores e imprimir), como
        // el PDF y el Word (Windows, 19-oct): los marcadores van al
        // `.pixpin-lectura` del fichero, en fraccion del desplazamiento.
        let contenedor = NSView()
        web.translatesAutoresizingMaskIntoConstraints = false
        contenedor.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            web.topAnchor.constraint(equalTo: contenedor.topAnchor),
            web.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
        ])
        capa.translatesAutoresizingMaskIntoConstraints = false
        capa.web = web
        contenedor.addSubview(capa)
        NSLayoutConstraint.activate([
            capa.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor),
            capa.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor),
            capa.topAnchor.constraint(equalTo: contenedor.topAnchor),
            capa.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor),
        ])
        ventana.contentView = contenedor
        ventana.setFrame(marco, display: false)
        VentanaLisa.recordar(ventana, clave: "html")
        modelo.nombre = url.lastPathComponent
        modelo.controlador = self
        montarRiel(en: contenedor, nucleo: nucleo)
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

    private let riel = RielSobreVista()
    private let capa = CapaTintaWeb()
    private lazy var marcos = MarcosDoc(documento: url)

    /// El boton del marco del riel: poner marcos numerados (Windows, 19-oct).
    func alternarMarcos() {
        if riel.modelo.anotando { alternarLapiz() }
        marcos.activo.toggle()
        riel.modelo.enmarcando = marcos.activo
        capa.needsDisplay = true
        ventana.invalidateCursorRects(for: capa)
    }

    /// Los marcos en grupo: la pagina llevada a cada uno y fotografiada.
    private func imprimirMarcos() {
        let lista = marcos.lista
        let antes = capa.desplazado
        let salida = PDFDocument()
        capa.ocultarMarcos = true
        func siguiente(_ i: Int) {
            guard i < lista.count else {
                capa.ocultarMarcos = false
                web.evaluateJavaScript("scrollTo(\(antes.x),\(antes.y))")
                if salida.pageCount > 0,
                   let op = salida.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) {
                    op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil)
                }
                return
            }
            let r = lista[i].rect
            web.evaluateJavaScript("scrollTo(\(r.minX),\(r.minY))") { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let conf = WKSnapshotConfiguration()
                        conf.rect = self.capa.aVista(r)
                        self.web.takeSnapshot(with: conf) { img, _ in
                            MainActor.assumeIsolated {
                                if let img, let p = PDFPage(image: img) { salida.insert(p, at: salida.pageCount) }
                                siguiente(i + 1)
                            }
                        }
                    }
                }
            }
        }
        siguiente(0)
    }
    private let alDia = AlDiaLector()
    private var guardado: DispatchWorkItem?
    private var nucleoTinta: Nucleo?

    /// Lo que se ha anotado, ya (si lo hay), para verlo encima al abrir.
    private func abrirTinta(_ nucleo: Nucleo, crear: Bool) {
        let ruta = url.path
        let ancho = UInt32(max(web.bounds.width, 320))
        Task { [weak self] in
            let ed = await Task.detached(priority: .userInitiated) { () -> EditorLienzo? in
                if !crear, !nucleo.hayTintaDeReflujo(documento: ruta) { return nil }
                // El nucleo pide la columna fijada antes de anotar (la del
                // Word); en una pagina web, su ancho al empezar.
                var l = nucleo.lecturaDeReflujo(documento: ruta)
                if l.columna == 0 {
                    l.columna = ancho
                    try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l)
                }
                do { return try nucleo.anotarReflujo(documento: ruta) } catch {
                    return nil
                }
            }.value
            guard let self, let ed, self.capa.editor == nil else { return }
            self.capa.editor = ed
            if self.riel.modelo.anotando { self.tinta.aplicar(a: ed, herramienta: self.riel.modelo.herramienta, color: self.riel.modelo.color) }
        }
    }

    /// El lapiz del riel: anotar encima con las herramientas del lienzo.
    func alternarLapiz() {
        let m = riel.modelo
        if m.anotando {
            m.herramienta = "leer"
            capa.anotando = false
            tinta.ensenar("leer")
            guardarTinta()
        } else {
            guard let nucleo = nucleoTinta else { return }
            m.poniendoMarca = false
            m.herramienta = tinta.alEmpezar
            capa.anotando = true
            tinta.ensenar(m.herramienta)
            if let ed = capa.editor { tinta.aplicar(a: ed, herramienta: m.herramienta, color: m.color) }
            else { abrirTinta(nucleo, crear: true) }
        }
    }

    private(set) lazy var tinta: HerramientasDeTinta = {
        let t = HerramientasDeTinta(nucleo: nucleoTinta)
        t.editores = { [weak self] in self?.capa.editor.map { [$0] } ?? [] }
        t.elegir = { [weak self] h in
            guard let self else { return }
            if h == "leer" { if self.riel.modelo.anotando { self.alternarLapiz() }; return }
            self.riel.modelo.herramienta = h
            self.tinta.ensenar(h)
            if let ed = self.capa.editor { self.tinta.aplicar(a: ed, herramienta: h, color: self.riel.modelo.color) }
        }
        t.deshacer = { [weak self] in if self?.capa.editor?.deshacer() == true { self?.capa.needsDisplay = true; self?.guardarTinta() } }
        t.rehacer = { [weak self] in if self?.capa.editor?.rehacer() == true { self?.capa.needsDisplay = true; self?.guardarTinta() } }
        t.repintar = { [weak self] in self?.capa.needsDisplay = true }
        return t
    }()

    private func guardarTinta() {
        guardado?.cancel()
        guard let ed = capa.editor else { return }
        let alDia = self.alDia, ruta = url.path
        let w = DispatchWorkItem {
            guard ed.sinGuardar(), let r = try? alDia.guardar(0, ed), r.escrito else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pixpinDocumentoAnotado, object: ruta)
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            }
        }
        guardado = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    private func montarRiel(en contenedor: NSView, nucleo: Nucleo?) {
        nucleoTinta = nucleo
        riel.montar(en: contenedor, lapiz: nucleo == nil ? nil : { [weak self] in self?.alternarLapiz() }) { [weak self] in self?.alternarMarcos() }
        capa.marcos = marcos
        tinta.montar(en: contenedor, modelo: riel.modelo)
        capa.alSoltar = { [weak self] in self?.guardarTinta() }
        if let nucleo { abrirTinta(nucleo, crear: false) }
        riel.irA = { [weak self] f in
            self?.web.evaluateJavaScript("var m=Math.max(0,document.documentElement.scrollHeight-innerHeight);scrollTo({top:\(f)*m,behavior:'instant'})")
        }
        riel.fraccion = { [weak self] listo in
            self?.web.evaluateJavaScript("(function(){var m=Math.max(1,document.documentElement.scrollHeight-innerHeight);return scrollY/m})()") { r, _ in
                MainActor.assumeIsolated { listo(Float((r as? Double) ?? 0)) }
            }
        }
        guard let nucleo else { return }
        let ruta = url.path
        riel.alCambiar = { marcas in
            Task.detached(priority: .utility) {
                var l = nucleo.lecturaDeReflujo(documento: ruta)
                l.marcadores = marcas.filter { $0.id >= 0 }.map {
                    MarcadorReflujo(id: UInt64($0.id), fraccion: Float($0.y), emoji: $0.emoji)
                }
                try? nucleo.guardarLecturaDeReflujo(documento: ruta, lectura: l)
            }
        }
        Task { [weak self] in
            let l = await Task.detached(priority: .utility) { nucleo.lecturaDeReflujo(documento: ruta) }.value
            self?.riel.modelo.marcas = l.marcadores.map {
                MarcaDocumento(id: Int64(bitPattern: $0.id), x: 0.5, y: Double($0.fraccion), emoji: $0.emoji)
            }.sorted { $0.y < $1.y }
        }
    }

    /// El boton de imprimir del riel: la pagina como se ve.
    func imprimir() {
        if !marcos.lista.isEmpty { imprimirMarcos(); return }
        let op = web.printOperation(with: NSPrintInfo.shared)
        op.view?.frame = web.bounds
        op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil)
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
        if m == .command, c == "p", !marcos.lista.isEmpty { imprimirMarcos(); return true }
        if marcos.activo, m.isEmpty, k == 51 || k == 117 {
            if marcos.quitarUltimo() { capa.needsDisplay = true }
            return true
        }
        if m.subtracting(.shift) == .command, c == "+" || c == "=" { web.pageZoom = min(web.pageZoom * 1.15, 5); capa.needsDisplay = true; return true }
        if m == .command, c == "-" { web.pageZoom = max(web.pageZoom / 1.15, 0.3); capa.needsDisplay = true; return true }
        if m == .command, c == "0" { web.pageZoom = 1; web.magnification = 1; capa.needsDisplay = true; return true }
        if m == .command, c == "e" { exportar(); return true }
        if m == .command, c == "r" { recargar(); return true }
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

    /// Vuelve a leer la pagina del disco (Windows, 17-oct).
    func recargar() {
        web.reloadFromOrigin()
    }

    /// La misma pagina en el navegador del Mac.
    func abrirEnElNavegador() {
        NSWorkspace.shared.open(url)
    }

    private func ponerOscuro(_ oscuro: Bool) {
        modelo.oscuro = oscuro
        web.appearance = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        // Como el Word oscuro de Windows: la pagina invertida y las fotos
        // vueltas a su color.
        let css = "html{filter:invert(1) hue-rotate(180deg);background:#fff}img,video,picture,canvas,svg image{filter:invert(1) hue-rotate(180deg)}"
        web.evaluateJavaScript("""
        (function(){var e=document.getElementById('pixpin-oscuro');
        if(\(oscuro)){if(!e){e=document.createElement('style');e.id='pixpin-oscuro';document.documentElement.appendChild(e);}e.textContent='\(css)';}
        else if(e){e.remove();}})();
        """)
    }

    /// La luna o el sol de la barra: el modo noche de TODOS los visores.
    func alternarOscuro() {
        let o = !modelo.oscuro
        ponerOscuro(o)
        if let nucleo = nucleoTinta { DispatchQueue.global(qos: .utility).async { try? nucleo.guardarLectoresOscuros(oscuros: o) } }
        NotificationCenter.default.post(name: .pixpinLectoresOscuros, object: o)
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
        if message.name == "pixpinScroll", let a = message.body as? [Double], a.count == 2 {
            capa.desplazado = CGPoint(x: a[0], y: a[1])
            return
        }
        guard let d = message.body as? [String: Any], d["tipo"] as? String == "guardar",
              let b64 = d["datos"] as? String,
              let datos = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return }
        guardar(datos)
    }

    /// Al cargar (o recargar) la pagina, otra vez su modo noche.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if modelo.oscuro { ponerOscuro(true) }
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
    @Published var oscuro = false
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
        BarraVisor(nombre: modelo.nota ?? modelo.nombre, ext: "html",
                   oscuro: modelo.oscuro, alternarOscuro: { modelo.controlador?.alternarOscuro() },
                   fijar: { si in
                       modelo.encima = si
                       modelo.controlador?.ventana.level = si ? .floating : .normal
                   },
                   cerrar: { modelo.controlador?.cerrar() }) {
            // Los de Windows (`visor_html::botones`): recargar, exportar y
            // el navegador. Sin lapiz: una pagina web no se edita aqui.
            BotonFlotante(simbolo: "arrow.clockwise", ayuda: "Recargar (⌘R)") {
                modelo.controlador?.recargar()
            }
            BotonFlotante(simbolo: "square.and.arrow.up", ayuda: "Exportar (⌘E)") {
                modelo.controlador?.exportar()
            }
            BotonFlotante(simbolo: "globe", ayuda: "Abrir en el navegador") {
                modelo.controlador?.abrirEnElNavegador()
            }
        }
    }
}
