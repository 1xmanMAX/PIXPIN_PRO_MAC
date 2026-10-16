// **«Abrir con…» en toda la app** (D1, `abrir_con.rs` de Windows): el menu
// del mensaje del chat, el del pin y las tarjetas de la Salida llaman aqui.
// Ofrece las apps que saben abrir el formato (las del sistema, con su
// icono) y «Otra app…» para elegirla en el disco; y si no sale, lo dice con
// palabras («No se encuentra el archivo X») en vez de no hacer nada.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum AbrirCon {
    /// El aviso para el usuario si `url` no se puede abrir; `nil` si si.
    nonisolated static func aviso(_ url: URL) -> String? {
        FileManager.default.fileExists(atPath: url.path)
            ? nil
            : "No se encuentra el archivo «\(url.lastPathComponent)»: puede que se haya movido o borrado."
    }

    /// Las apps que saben abrir `url`, la predeterminada primero.
    static func apps(_ url: URL) -> [URL] {
        var v = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if let porDefecto = NSWorkspace.shared.urlForApplication(toOpen: url),
           let i = v.firstIndex(of: porDefecto), i > 0 {
            v.remove(at: i)
            v.insert(porDefecto, at: 0)
        }
        return v
    }

    static func nombre(_ app: URL) -> String { FileManager.default.displayName(atPath: app.path) }

    static func icono(_ app: URL) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: app.path)
        i.size = NSSize(width: 16, height: 16)
        return i
    }

    /// Abre `url` con `app`. Si no sale, `avisar` lo dice.
    static func abrir(_ url: URL, con app: URL, avisar: @escaping @MainActor (String) -> Void = avisarConCuadro) {
        if let aviso = aviso(url) { return avisar(aviso) }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in avisar("No se pudo abrir con \(nombre(app)): \(error.localizedDescription)") }
        }
    }

    /// «Otra app…»: se elige en el disco.
    static func elegirOtra(_ url: URL, avisar: @escaping @MainActor (String) -> Void = avisarConCuadro) {
        if let aviso = aviso(url) { return avisar(aviso) }
        let panel = NSOpenPanel()
        panel.title = "Abrir con…"
        panel.message = "Elige la app con la que abrir «\(url.lastPathComponent)»"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Abrir"
        NSApp.activate()
        if panel.runModal() == .OK, let app = panel.url { abrir(url, con: app, avisar: avisar) }
    }

    /// Para quien no tiene donde ensenar un aviso: un cuadro con el motivo.
    static func avisarConCuadro(_ texto: String) {
        let a = NSAlert()
        a.messageText = "Abrir con…"
        a.informativeText = texto
        a.runModal()
    }

    /// **El submenu de AppKit** (el pin, la Salida): las apps y «Otra
    /// app…».
    static func menu(_ url: URL, avisar: @escaping @MainActor (String) -> Void = avisarConCuadro) -> NSMenuItem {
        let item = NSMenuItem(title: "Abrir con…", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let apps = apps(url)
        for app in apps {
            let e = ElementoDeMenu(nombre(app)) { abrir(url, con: app, avisar: avisar) }
            e.image = icono(app)
            sub.addItem(e)
        }
        if !apps.isEmpty { sub.addItem(.separator()) }
        sub.addItem(ElementoDeMenu("Otra app…") { elegirOtra(url, avisar: avisar) })
        item.submenu = sub
        return item
    }
}

/// **El submenu de SwiftUI** (el menu del mensaje): las apps con su icono y
/// «Otra app…».
struct MenuAbrirCon: View {
    let url: URL
    var avisar: @MainActor (String) -> Void = AbrirCon.avisarConCuadro

    var body: some View {
        Menu {
            let apps = AbrirCon.apps(url)
            ForEach(apps, id: \.self) { app in
                Button { AbrirCon.abrir(url, con: app, avisar: avisar) } label: {
                    Label { Text(AbrirCon.nombre(app)) } icon: { Image(nsImage: AbrirCon.icono(app)) }
                }
            }
            if !apps.isEmpty { Divider() }
            Button("Otra app…") { AbrirCon.elegirOtra(url, avisar: avisar) }
        } label: {
            Label("Abrir con…", systemImage: "arrow.up.forward.app")
        }
    }
}

/// Un elemento de menu de AppKit que hace lo que se le dice (se guarda a
/// si mismo como destino).
final class ElementoDeMenu: NSMenuItem {
    private let hacer: @MainActor () -> Void

    init(_ titulo: String, tecla: String = "", hacer: @escaping @MainActor () -> Void) {
        self.hacer = hacer
        super.init(title: titulo, action: #selector(pulsar(_:)), keyEquivalent: tecla)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    @objc private func pulsar(_: Any?) { MainActor.assumeIsolated { hacer() } }
}
