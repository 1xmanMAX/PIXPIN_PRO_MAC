// **Las ventanas lisas, como en Windows** (15-oct-2026, el usuario: «todas
// las ventanas tienen la interfaz clasica de macOS, con la barra del titulo y
// los botones de cerrar y minimizar; el PixPin original es plano, mas
// limpio»).
//
// En Windows ninguna ventana de PixPin lleva el marco del sistema
// (`WS_POPUP`): la de Proyectos tiene una franja fina del color del fondo con
// el nombre a la izquierda y −, ☐ y ✕ planos a la derecha; Galeria, Tareas,
// Lecciones y Timeline, su cabecera (`cabecera.rs`) con la ✕ al final; y los
// lectores nacen sin marco, como un pin, con su barra (`lector_pin.rs`).
//
// Aqui se queda el marco de AppKit por dentro (sombra, esquinas, estirar por
// los bordes, ⌘W y ⌘M, pantalla completa) pero no se ve: sin titulo, sin
// semaforo y con la barra del titulo transparente, del color de la ventana.
// En su lugar van los botones planos de Windows a la derecha
// (`BotonesDeVentana`); las ventanas con barra propia (el lector, el pin de
// Office) los llevan dentro de ella.

import AppKit
import SwiftUI

@MainActor
public enum VentanaLisa {
    /// Quita a `ventana` lo que se ve del marco del Mac. `botones`: poner los
    /// planos de Windows (−, ☐, ✕) a la derecha de la barra del titulo; sin
    /// ellos, la ventana los lleva en su propia barra.
    public static func vestir(_ ventana: NSWindow, botones: Bool = true) {
        ventana.titleVisibility = .hidden
        ventana.titlebarAppearsTransparent = true
        ventana.titlebarSeparatorStyle = .none
        for tipo in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            ventana.standardWindowButton(tipo)?.isHidden = true
        }
        if botones, !enteras.contains(ventana),
           !ventana.titlebarAccessoryViewControllers.contains(where: { $0 is AccesorioBotones }) {
            ventana.addTitlebarAccessoryViewController(AccesorioBotones(ventana: ventana))
        }
    }

    /// Las ventanas enteras: `vestir` ya no les pone los botones, aunque
    /// llegue despues (SwiftUI llama a los dos sin orden fijo).
    private static let enteras = NSHashTable<NSWindow>.weakObjects()

    /// Como `vestir`, para una ventana cuyo contenido llega hasta arriba (su
    /// barra hace de titulo): sin franja, el contenido ocupa la ventana. Si
    /// ya tenia los botones de la franja, se le quitan: los lleva su barra.
    public static func vestirEntera(_ ventana: NSWindow) {
        enteras.add(ventana)
        ventana.styleMask.insert(.fullSizeContentView)
        for (i, a) in ventana.titlebarAccessoryViewControllers.enumerated().reversed() where a is AccesorioBotones {
            ventana.removeTitlebarAccessoryViewController(at: i)
        }
        vestir(ventana, botones: false)
    }

    /// **⎋ de los visores**: a pantalla completa, el primero sale de ella; si
    /// no, se cierra (el segundo ⎋ en pantalla completa).
    static func escapar(_ ventana: NSWindow?) {
        guard let ventana else { return }
        if ventana.styleMask.contains(.fullScreen) { ventana.toggleFullScreen(nil) } else { cerrar(ventana) }
    }

    /// Para los visores cuyo contenido no ve el ⎋ (QuickLook, paginas web):
    /// un vigia de la app se lo da a `escapar` mientras la ventana es la activa.
    /// `escape: false`: solo ⌃⌘F (la ventana ya trata su ⎋).
    static func escaparConVigia(_ ventana: NSWindow, escape: Bool = true) {
        conVigia.add(ventana)
        if !escape { soloCompleta.add(ventana) }
        guard vigiaEscape == nil else { return }
        vigiaEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard let v = e.window ?? NSApp.keyWindow, conVigia.contains(v) else { return e }
            if e.keyCode == 53, m.isEmpty, !soloCompleta.contains(v) {
                escapar(v)
                return nil
            }
            // ⌃⌘F: pantalla completa, para luego salir con ⎋.
            if m == [.control, .command], e.keyCode == 3, v.collectionBehavior.contains(.fullScreenPrimary) {
                v.toggleFullScreen(nil)
                return nil
            }
            return e
        }
    }

    private static let conVigia = NSHashTable<NSWindow>.weakObjects()
    private static let soloCompleta = NSHashTable<NSWindow>.weakObjects()
    private static var vigiaEscape: Any?

    /// Cerrar como la ✕ del sistema: preguntando antes al delegado.
    static func cerrar(_ ventana: NSWindow?) {
        guard let ventana else { return }
        if ventana.delegate?.windowShouldClose?(ventana) == false { return }
        ventana.close()
    }
}

/// Los botones planos de Windows a la derecha de la barra del titulo.
final class AccesorioBotones: NSTitlebarAccessoryViewController {
    init(ventana: NSWindow) {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
        let vista = NSHostingView(rootView: BotonesDeVentana(ventana: RefVentana(ventana))
            .padding(.trailing, 4))
        vista.frame.size = vista.fittingSize
        view = vista
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
}

/// La ventana de unos botones, sin retenerla.
@MainActor
public final class RefVentana {
    public weak var ventana: NSWindow?
    public init(_ ventana: NSWindow? = nil) { self.ventana = ventana }
}

/// **−, ☐ y ✕ planos**, como los de Windows: sin fondo hasta pasar el raton
/// (gris; la ✕, roja con la cruz blanca). − solo si la ventana se minimiza,
/// y ☐ si ademas se estira.
public struct BotonesDeVentana: View {
    let ref: RefVentana
    var minimizar = true

    public init(ventana: RefVentana, minimizar: Bool = true) {
        ref = ventana
        self.minimizar = minimizar
    }

    private var mascara: NSWindow.StyleMask {
        ref.ventana?.styleMask ?? [.miniaturizable, .resizable]
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Un panel (pines abiertos) no se minimiza: solo la ✕.
            if minimizar, mascara.contains(.miniaturizable) {
                BotonPlano(simbolo: "minus", ayuda: "Minimizar (⌘M)") { ref.ventana?.miniaturize(nil) }
                if mascara.contains(.resizable) {
                    BotonPlano(simbolo: "square", ayuda: "Maximizar") { ref.ventana?.zoom(nil) }
                }
            }
            BotonPlano(simbolo: "xmark", ayuda: "Cerrar (⌘W)", rojo: true) { VentanaLisa.cerrar(ref.ventana) }
        }
    }
}

/// Un boton de la barra: icono fino, fondo solo con el raton encima.
public struct BotonPlano: View {
    let simbolo: String
    let ayuda: String
    var rojo = false
    var encendido = false
    let accion: () -> Void
    @State private var encima = false

    public init(simbolo: String, ayuda: String, rojo: Bool = false, encendido: Bool = false,
                accion: @escaping () -> Void) {
        self.simbolo = simbolo
        self.ayuda = ayuda
        self.rojo = rojo
        self.encendido = encendido
        self.accion = accion
    }

    public var body: some View {
        Button(action: accion) {
            // Con su nombre para VoiceOver; se ve solo el icono.
            Label(ayuda, systemImage: simbolo)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(encima && rojo ? Color.white : encendido ? Color.white : Color.secondary)
                .frame(width: 38, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(encendido ? Color.accentColor
                              : encima ? (rojo ? Color(red: 0.77, green: 0.17, blue: 0.11) : Color.primary.opacity(0.1))
                              : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
    }
}

public extension View {
    /// La ventana de esta vista, lisa como en Windows (`VentanaLisa`).
    func ventanaLisa() -> some View {
        modifier(ModificadorVentanaLisa())
    }
}

struct ModificadorVentanaLisa: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(removing: .title)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .background(AccesoVentana { VentanaLisa.vestir($0) })
    }
}

/// Da la ventana de la vista en cuanto la tiene (y otra vez despues, por si
/// SwiftUI vuelve a poner lo suyo al montar la barra).
struct AccesoVentana: NSViewRepresentable {
    let alTener: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> VistaAcceso {
        let v = VistaAcceso()
        v.alTener = alTener
        return v
    }

    func updateNSView(_ nsView: VistaAcceso, context: Context) {}
}

final class VistaAcceso: NSView {
    var alTener: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let ventana = window else { return }
        alTener?(ventana)
        DispatchQueue.main.async { [weak self] in
            guard let self, let ventana = self.window else { return }
            self.alTener?(ventana)
        }
    }
}
