// **El icono de PixPin en la barra de menus** (la bandeja de Windows,
// `centro_bandeja.rs` y `pixpin-shell/bandeja.rs`):
//
// - **Clic** (el izquierdo de Windows): el panel rico (`VistaBandeja`), o lo
//   cierra si ya estaba. Se cierra solo al hacer clic fuera.
// - **Clic derecho** (o ⌃clic): el menu de siempre, de respaldo, con todos
//   los comandos, «Grupos de ventanas» y, si los hay, «Grupos ocultos» de
//   los pines (la unica via de vuelta de unos pines que ya no se ven).
// - Mientras se graba la pantalla, un punto rojo en vez del pin.
//
// El panel no hace las cosas: cada boton es un comando del catalogo
// (`GestorAtajos.ejecutar`, atado en `ComandosApp`), el mismo que su atajo y
// su entrada del menu. Lo que mira la pantalla (capturar, anotar) espera a
// que el panel se haya ido, o saldria en la foto.

import AppKit
import Combine
import PixPinCore
import SwiftUI

@MainActor
public final class IconoBandeja: NSObject, NSMenuDelegate {
    public static let compartido = IconoBandeja()

    private var item: NSStatusItem?
    private var panel: PanelBandejaNS?
    private var modelo: ModeloBandeja?
    private var atajos: GestorAtajos?
    private var sincro: Sincronizador?
    private var nucleo: Nucleo?
    private var vigias: Set<AnyCancellable> = []
    private var vigiaRaton: Any?
    private var vigiaFoco: Any?
    /// Cuando se cerro por perder el foco: el clic en el icono que lo cerro
    /// llega despues, y sin esto lo volveria a abrir (`GRACIA_MS`).
    private var cerradoEn = Date.distantPast
    static let gracia: TimeInterval = 0.4

    /// Pone el icono (una vez, al arrancar).
    public func instalar(atajos: GestorAtajos, nucleo: Nucleo?, sincro: Sincronizador?) {
        guard item == nil else { return }
        self.atajos = atajos
        self.nucleo = nucleo
        self.sincro = sincro
        GruposVentanas.compartidos.raiz = nucleo.map { URL(fileURLWithPath: $0.raiz(), isDirectory: true) }
        let modelo = ModeloBandeja(atajos: atajos, nucleo: nucleo, sincro: sincro)
        modelo.alPedir = { [weak self] in self?.hacer($0) }
        modelo.alCerrar = { [weak self] in self?.cerrar() }
        self.modelo = modelo

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(pulsado(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "PixPin"
        self.item = item
        ponerIcono(grabando: GrabadorPantalla.compartido.grabando)
        GrabadorPantalla.compartido.$grabando
            .receive(on: DispatchQueue.main)
            .sink { [weak self] g in self?.ponerIcono(grabando: g) }
            .store(in: &vigias)
    }

    private func ponerIcono(grabando: Bool) {
        if grabando {
            item?.button?.image = Self.puntoRojo
        } else {
            let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PixPin")
            pin?.isTemplate = true
            item?.button?.image = pin
        }
    }

    /// En color (no plantilla): la barra de menus pinta las plantillas en
    /// blanco o negro, y el rojo es justo lo que tiene que verse.
    static let puntoRojo: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
        let imagen = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Grabando")?
            .withSymbolConfiguration(config) ?? NSImage()
        imagen.isTemplate = false
        return imagen
    }()

    // MARK: El clic

    @objc private func pulsado(_ sender: Any?) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            cerrar()
            mostrarMenu()
            return
        }
        if panel?.isVisible == true {
            cerrar()
        } else if Date().timeIntervalSince(cerradoEn) > Self.gracia {
            abrir()
        }
    }

    // MARK: El panel

    /// Abre el panel bajo el icono.
    public func abrir() {
        guard let modelo, let boton = item?.button, let ventanaBoton = boton.window else { return }
        let pantalla = ventanaBoton.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = pantalla?.visibleFrame else { return }
        let altoMaximo = visible.height - 12
        modelo.alAbrir()
        let p = panel ?? PanelBandejaNS()
        panel = p
        // Nueva cada vez: el buscador con el foco y arriba del todo.
        let vista = NSHostingView(rootView: VistaBandeja(modelo: modelo, altoMaximo: altoMaximo))
        p.contentView = vista
        let ancho = VistaBandeja.ancho
        let bajoIcono = ventanaBoton.convertToScreen(boton.frame)
        let x = min(max(bajoIcono.midX - ancho / 2, visible.minX + 6), visible.maxX - ancho - 6)
        let alto = min(max(vista.fittingSize.height, 200), altoMaximo)
        p.setFrame(CGRect(x: x, y: visible.maxY - 6 - alto, width: ancho, height: alto), display: false)
        p.makeKeyAndOrderFront(nil)
        // Se ajusta a lo de dentro (cambia al buscar, al llegar las capturas).
        modelo.$altoContenido
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ajustarAlto(maximo: altoMaximo) }
            .store(in: &vigiasPanel)
        modelo.objectWillChange
            .debounce(for: .milliseconds(10), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.ajustarAlto(maximo: altoMaximo) }
            .store(in: &vigiasPanel)
        vigiaFoco = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p,
                                                           queue: .main) { _ in
            MainActor.assumeIsolated { IconoBandeja.compartido.cerrar(porFoco: true) }
        }
        // Un clic en otra app tambien lo cierra (no siempre le quita el foco
        // a un panel que no activa la app).
        vigiaRaton = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { IconoBandeja.compartido.cerrar(porFoco: true) }
        }
    }

    private var vigiasPanel: Set<AnyCancellable> = []

    private func ajustarAlto(maximo: CGFloat) {
        guard let p = panel, p.isVisible, let vista = p.contentView else { return }
        vista.layoutSubtreeIfNeeded()
        let alto = min(max(vista.fittingSize.height, 120), maximo)
        guard abs(alto - p.frame.height) > 0.5 else { return }
        var marco = p.frame
        marco.origin.y = marco.maxY - alto
        marco.size.height = alto
        p.setFrame(marco, display: true)
    }

    public func cerrar(porFoco: Bool = false) {
        guard let p = panel, p.isVisible else { return }
        if porFoco { cerradoEn = Date() }
        vigiasPanel.removeAll()
        if let vigiaFoco { NotificationCenter.default.removeObserver(vigiaFoco) }
        vigiaFoco = nil
        if let vigiaRaton { NSEvent.removeMonitor(vigiaRaton) }
        vigiaRaton = nil
        p.orderOut(nil)
        // Lo de dentro se suelta (las miniaturas): se rehace al abrir.
        p.contentView = nil
    }

    /// Lo que pide un boton del panel.
    func hacer(_ a: AccionBandeja) {
        if a.cierraElPanel { cerrar() }
        // Lo que mira la pantalla, cuando el panel ya se fue de verdad.
        let espera: TimeInterval = a.miraLaPantalla ? 0.25 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in self?.hacerYa(a) }
    }

    private func hacerYa(_ a: AccionBandeja) {
        guard let atajos else { return }
        switch a {
        case .comando(.sincronizar):
            // «Sincronizar ahora»: con todos, ya (el estado sale arriba).
            if let sincro { Task { await sincro.sincronizarAhora() } } else { atajos.ejecutar(.sincronizar) }
        case let .comando(c):
            if atajos.disponible(c) { atajos.ejecutar(c) } else { NSSound.beep() }
        case .lecciones, .nuevaLeccion:
            Self.abrirVentana("lecciones")
        case .galeria:
            Self.abrirVentana(IdVentana.galeria)
        case .tareas:
            Self.abrirVentana(IdVentana.tareas)
        case .abrirDocumento:
            Self.abrirDocumento()
        case .gruposVentanas:
            GruposVentanas.compartidos.menu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    static func abrirVentana(_ id: String) {
        guard let abrir = ComandosApp.abrirVentana else { return NSSound.beep() }
        abrir(id)
        NSApp.activate()
    }

    /// «Abrir documento…»: lo elegido, como «Abrir con PixPin» del Finder.
    static func abrirDocumento() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Abrir"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for u in panel.urls { HacerPedidos.compartidos.abrir(fichero: u) }
    }

    // MARK: El menu del clic derecho

    private func mostrarMenu() {
        guard let item, let atajos else { return }
        let menu = MenuBandeja.armar(atajos: atajos, sincro: sincro)
        menu.delegate = self
        item.menu = menu
        item.button?.performClick(nil)
    }

    public nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated { item?.menu = nil }
    }
}

/// La ventana del panel: sin marco, encima de todo y sin activar la app
/// (como el panel de Windows), pero con el teclado para el buscador.
final class PanelBandejaNS: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: VistaBandeja.ancho, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
