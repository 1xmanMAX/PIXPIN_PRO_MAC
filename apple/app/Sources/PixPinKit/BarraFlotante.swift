// **La barra que flota fuera de la ventana**, como la de los lectores de
// Windows (`lector_pin.rs`): va encima de la ventana y pegada a su lado
// izquierdo (o dentro, arriba, si fuera no cabe: pegada al borde de la
// pantalla o a pantalla completa), aparece con el raton encima de la
// ventana y se va un poco despues de salir (600 ms, como alla).
//
// Es un panel hijo de la ventana (`addChildWindow`): mientras se ve, se
// mueve con ella. No se activa al pulsarlo (la ventana sigue con el
// teclado) y su asa lleva la ventana, no el panel.
//
// Para saber si el raton esta encima se mira cada 100 ms donde esta y que
// ventana hay debajo (`windowNumber(at:)`): asi una ventana que tape al
// lector no la hace salir, y no hacen falta zonas de seguimiento en dos
// ventanas a la vez. Solo mientras la ventana esta abierta.

import AppKit
import SwiftUI

@MainActor
public final class BarraFlotante {
    /// Lo que espera despues de salir el raton antes de irse.
    static let espera: TimeInterval = 0.6
    /// Lo que se separa de la ventana.
    nonisolated static let separacion: CGFloat = 6

    private let panel: NSPanel
    private let anfitrion: NSView
    private weak var ventana: NSWindow?
    private var reloj: Timer?
    private var fueraDesde: Date?
    /// Mientras sea `true`, la barra no se va (un aviso, un menu abierto).
    public var fija: () -> Bool = { false }

    public init<V: View>(ventana: NSWindow, @ViewBuilder contenido: () -> V) {
        self.ventana = ventana
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        let raiz = contenido()
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 6)
            .frame(height: 48)
            .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.97),
                        in: RoundedRectangle(cornerRadius: 14))
            .environment(\.ventanaDeLaBarra, RefVentana(ventana))
        let h = NSHostingView(rootView: raiz)
        h.safeAreaRegions = []
        anfitrion = h
        panel.contentView = h
    }

    /// Empieza a mirar el raton (llamar al abrir la ventana).
    public func empezar() {
        guard reloj == nil else { return }
        let r = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirar() }
        }
        RunLoop.main.add(r, forMode: .common)
        reloj = r
    }

    /// Deja de mirar y quita la barra (al cerrar la ventana).
    public func terminar() {
        reloj?.invalidate()
        reloj = nil
        ocultar()
    }

    private func mirar() {
        guard let ventana, ventana.isVisible, !ventana.isMiniaturized else {
            ocultar()
            return
        }
        let raton = NSEvent.mouseLocation
        let debajo = NSWindow.windowNumber(at: raton, belowWindowWithWindowNumber: 0)
        let encima = (debajo == ventana.windowNumber && ventana.frame.contains(raton))
            || (panel.isVisible && (debajo == panel.windowNumber || panel.frame.insetBy(dx: -4, dy: -4).contains(raton)))
        if encima || fija() || NSEvent.pressedMouseButtons != 0 && panel.isVisible {
            fueraDesde = nil
            mostrar(en: ventana)
        } else if panel.isVisible {
            if let t = fueraDesde {
                if Date().timeIntervalSince(t) > Self.espera { ocultar() }
            } else {
                fueraDesde = Date()
            }
        }
    }

    private func mostrar(en ventana: NSWindow) {
        let tam = anfitrion.fittingSize
        let marco = Self.marco(tam: tam, ventana: ventana.frame,
                               pantalla: (ventana.screen ?? NSScreen.main)?.visibleFrame,
                               completa: ventana.styleMask.contains(.fullScreen))
        if panel.frame != marco { panel.setFrame(marco, display: true) }
        panel.level = ventana.level
        if !panel.isVisible || panel.parent !== ventana {
            ventana.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    private func ocultar() {
        fueraDesde = nil
        guard panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Donde va: encima de la ventana y pegada a su izquierda; si no cabe
    /// arriba (o a pantalla completa), dentro, arriba a la izquierda.
    nonisolated static func marco(tam: CGSize, ventana: CGRect, pantalla: CGRect?, completa: Bool) -> CGRect {
        let fuera = CGRect(x: ventana.minX, y: ventana.maxY + separacion, width: tam.width, height: tam.height)
        if !completa, let pantalla, fuera.maxY <= pantalla.maxY {
            return fuera
        }
        return CGRect(x: ventana.minX + 8, y: ventana.maxY - tam.height - 8, width: tam.width, height: tam.height)
    }
}

private struct ClaveVentanaDeLaBarra: EnvironmentKey {
    static let defaultValue: RefVentana? = nil
}

extension EnvironmentValues {
    /// La ventana que lleva la barra flotante (la mueve su asa).
    var ventanaDeLaBarra: RefVentana? {
        get { self[ClaveVentanaDeLaBarra.self] }
        set { self[ClaveVentanaDeLaBarra.self] = newValue }
    }
}

/// **El asa** de la barra: arrastrarla lleva la ventana (no el panel de la
/// barra, que va detras como hijo suyo).
public struct AsaBarra: View {
    @Environment(\.ventanaDeLaBarra) private var ref
    @State private var inicio: (raton: CGPoint, origen: CGPoint)?

    public init() {}

    public var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13))
            .foregroundStyle(Color(white: 0.78))
            .frame(width: 22, height: 40)
            .contentShape(Rectangle())
            .help("Mover")
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    guard let v = ref?.ventana else { return }
                    let raton = NSEvent.mouseLocation
                    if inicio == nil { inicio = (raton, v.frame.origin) }
                    guard let i = inicio else { return }
                    v.setFrameOrigin(CGPoint(x: i.origen.x + raton.x - i.raton.x,
                                             y: i.origen.y + raton.y - i.raton.y))
                }
                .onEnded { _ in inicio = nil })
            .onHover { dentro in
                if dentro { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
    }
}

/// Un boton de la barra flotante: 40 x 40, icono claro, fondo blanco al
/// 12 % con el raton encima; encendido, azul (el pin fijado).
public struct BotonFlotante: View {
    let simbolo: String
    let ayuda: String
    var encendido = false
    let accion: () -> Void
    @State private var encima = false

    public init(simbolo: String, ayuda: String, encendido: Bool = false, accion: @escaping () -> Void) {
        self.simbolo = simbolo
        self.ayuda = ayuda
        self.encendido = encendido
        self.accion = accion
    }

    public var body: some View {
        Button(action: accion) {
            Label(ayuda, systemImage: simbolo)
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(encendido ? Color(red: 0, green: 0.376, blue: 0.875)
                              : encima ? Color.white.opacity(0.12) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
    }
}
