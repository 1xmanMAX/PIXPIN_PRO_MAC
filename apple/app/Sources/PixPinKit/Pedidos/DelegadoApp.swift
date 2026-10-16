// **El delegado de la app** (C2): lo que macOS le pide a PixPin desde fuera.
//
// - Los enlaces `pixpinmax://` (`CFBundleURLTypes`) van a `HacerPedidos`.
// - Los ficheros («Abrir con», soltarlos en el icono del Dock) siguen el
//   camino de siempre (`DelegadoAbrirFicheros`) y, si no son de un visor
//   ni de un lector, un pin (imagenes y videos) o el reproductor (audios),
//   como las asociaciones de Windows (`pixpin-shell/asociaciones.rs`).
// - **El menu del Dock** es la Jump List de Windows (`jump_list.rs`):
//   Capturar, Mensajes guardados, Proyectos, Sincronizar y los tres ultimos
//   proyectos tocados; cada entrada es un pedido, como alli.
// - **El icono del Dock** sale mientras hay una ventana de PixPin abierta
//   (en Windows, el boton de la barra de tareas) y se va con la ultima: la
//   app sigue viviendo en la barra de menus (`LSUIElement`).
// - Los Servicios del Finder (`ServiciosFinder`) son el menu del Explorador.

import AppKit
import Foundation

@MainActor
public final class DelegadoApp: NSObject, NSApplicationDelegate {
    private let ficheros = DelegadoAbrirFicheros()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServiciosFinder.compartidos
        NSUpdateDynamicServices()
        IconoDelDock.compartido.vigilar()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ficheros.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        var resto: [URL] = []
        for u in urls {
            if !u.isFileURL, HacerPedidos.compartidos.abrir(enlace: u) { continue }
            if u.isFileURL, DelegadoApp.vaAPinOReproductor(u) {
                HacerPedidos.compartidos.abrir(fichero: u)
                continue
            }
            resto.append(u)
        }
        if !resto.isEmpty { ficheros.application(application, open: resto) }
    }

    /// Imagenes, videos y audios: lo que Windows asocia a PixPin
    /// (`IMAGENES`, `VIDEOS`, `AUDIOS`) y no abre ningun lector.
    nonisolated static func vaAPinOReproductor(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return TiposQueAbre.imagenes.contains(ext) || TiposQueAbre.videos.contains(ext) || TiposQueAbre.audios.contains(ext)
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MenuDelDock.menu()
    }
}

/// Las extensiones que Windows abre con PixPin (`asociaciones.rs`); las
/// mismas estan en `CFBundleDocumentTypes` de los dos Info.plist.
public enum TiposQueAbre {
    public static let imagenes: Set<String> = ["png", "jpg", "jpeg", "jfif", "gif", "bmp", "webp", "tif", "tiff",
                                               "ico", "heic", "heif", "avif", "jxl", "jxr"]
    public static let videos: Set<String> = ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "mpg", "mpeg", "ts"]
    public static let audios: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "wma", "3gp", "amr"]
}

// MARK: - El menu del Dock

/// Una entrada del menu del Dock: lo que se lee y el pedido que hace.
public struct EntradaDock: Equatable, Sendable {
    public var titulo: String
    public var pedido: Pedido
}

@MainActor
public enum MenuDelDock {
    /// Cuantos proyectos recientes (los de Android y Windows).
    public nonisolated static let cuantosProyectos = 3

    /// **Las entradas** (`jump_list::armar`): las cuatro fijas y los tres
    /// ultimos proyectos tocados (sin nombre no van; «Mensajes guardados» ya
    /// esta arriba). `chats` viene en el orden de la lista (lo ultimo
    /// tocado, arriba).
    public nonisolated static func entradas(chats: [(id: String, nombre: String, guardados: Bool, archivado: Bool)])
        -> (fijas: [EntradaDock], recientes: [EntradaDock]) {
        let abrirProyecto = { (id: ValorPedido) in
            Pedido("abrir", ["que": .objeto(["tipo": .texto("proyecto"), "proyecto": id])])
        }
        let fijas = [
            EntradaDock(titulo: "Capturar", pedido: Pedido("capturar")),
            EntradaDock(titulo: "Mensajes guardados", pedido: abrirProyecto(.nulo)),
            EntradaDock(titulo: "Proyectos", pedido: Pedido("ventana_principal")),
            EntradaDock(titulo: "Sincronizar", pedido: Pedido("ventana", ["cual": .texto("sincronizar")])),
        ]
        let recientes = chats
            .filter { !$0.guardados && !$0.archivado && !$0.id.isEmpty && !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(cuantosProyectos)
            .map { EntradaDock(titulo: String($0.nombre.trimmingCharacters(in: .whitespaces).prefix(24)),
                               pedido: abrirProyecto(.texto($0.id))) }
        return (fijas, Array(recientes))
    }

    /// El menu, armado al pedirlo (con los proyectos ya al dia).
    static func menu() -> NSMenu {
        let menu = NSMenu()
        let chats = HacerPedidos.compartidos.fichas().map {
            (id: $0.id, nombre: $0.nombre, guardados: $0.esGuardados, archivado: $0.archivado)
        }
        let (fijas, recientes) = entradas(chats: chats)
        for e in fijas { menu.addItem(item(e)) }
        if !recientes.isEmpty {
            menu.addItem(.separator())
            for e in recientes { menu.addItem(item(e)) }
        }
        menu.addItem(.separator())
        // Lo demas del catalogo de comandos, como la bandeja de Windows.
        let mas: [(String, Pedido)] = [
            ("Tareas", Pedido("ventana", ["cual": .texto("tareas")])),
            ("Buscar en PixPin…", Pedido("ventana", ["cual": .texto("buscar")])),
            ("Galería de capturas", Pedido("ventana", ["cual": .texto("galeria")])),
            ("Pinear la última captura", Pedido("pinear_ultima")),
        ]
        for (t, p) in mas { menu.addItem(item(EntradaDock(titulo: t, pedido: p))) }
        return menu
    }

    private static func item(_ e: EntradaDock) -> NSMenuItem {
        let i = NSMenuItem(title: e.titulo, action: #selector(Destino.hacer(_:)), keyEquivalent: "")
        i.target = Destino.compartido
        i.representedObject = CajaPedido(e.pedido)
        return i
    }

    /// Quien recibe el clic de una entrada.
    final class Destino: NSObject {
        static let compartido = Destino()
        @objc func hacer(_ sender: NSMenuItem) {
            guard let caja = sender.representedObject as? CajaPedido else { return }
            MainActor.assumeIsolated { HacerPedidos.compartidos.hacer(caja.pedido) }
        }
    }

    final class CajaPedido: NSObject {
        let pedido: Pedido
        init(_ p: Pedido) { pedido = p }
    }
}

// MARK: - El icono del Dock

/// Ensena el icono en el Dock mientras hay una ventana de PixPin abierta.
@MainActor
public final class IconoDelDock {
    public static let compartido = IconoDelDock()
    private var vigias: [Any] = []
    private var pendiente = false

    /// Mira las ventanas al abrirse, cerrarse o minimizarse.
    func vigilar() {
        guard vigias.isEmpty else { return }
        let centro = NotificationCenter.default
        for n in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification,
                  NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                  NSWindow.didChangeOcclusionStateNotification] {
            vigias.append(centro.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { IconoDelDock.compartido.mirarLuego() }
            })
        }
        mirarLuego()
    }

    /// Tras el cierre (que aun cuenta la ventana que se va).
    private func mirarLuego() {
        guard !pendiente else { return }
        pendiente = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                IconoDelDock.compartido.pendiente = false
                IconoDelDock.compartido.mirar()
            }
        }
    }

    private func mirar() {
        let hay = NSApp.windows.contains(where: IconoDelDock.cuenta)
        let quiero: NSApplication.ActivationPolicy = hay ? .regular : .accessory
        guard NSApp.activationPolicy() != quiero else { return }
        NSApp.setActivationPolicy(quiero)
        if hay { NSApp.activate() }
    }

    /// Una ventana «de verdad»: con titulo, que puede ser la principal y a
    /// nivel normal. Los pines (flotantes), los paneles y los avisos no.
    static func cuenta(_ w: NSWindow) -> Bool {
        (w.isVisible || w.isMiniaturized) && !(w is NSPanel) && w.styleMask.contains(.titled)
            && w.canBecomeMain && w.level == .normal
    }
}
