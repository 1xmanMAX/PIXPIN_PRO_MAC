// La cuenta atras de la captura con retardo (`cuenta_atras.rs` de Windows,
// P2.1): sirve para capturar lo que se esconde al perder el foco (un menu
// abierto, un desplegable, un globo de ayuda). Se cuenta hasta cero y en
// ese momento se abre la captura, con el menu todavia desplegado.
//
// Como en Windows:
// - los segundos son `retardo_captura_s` de `pixpinmax.toml` (3 de
//   fabrica; 0 abre ya);
// - el cartel va abajo a la derecha de la pantalla (donde menos suele haber
//   algo que mirar y lejos de los menus), es pasante a los clics y no quita
//   el foco;
// - el numero se redondea hacia ARRIBA (`quedan`): empieza en «3» y acaba
//   en «1»;
// - Esc la para. La app no tiene el foco (es la de debajo la que lo tiene,
//   y debe seguir teniendolo para que el menu no se cierre), asi que Esc se
//   mira como `GetAsyncKeyState` de Windows: el estado de la tecla en la
//   sesion (`CGEventSource.keyState`), cada 16 ms, sin pedir permisos;
// - el cartel se quita ANTES de capturar y se espera a que el servidor de
//   ventanas lo haya quitado: si no, saldria en la captura.

import AppKit
import CoreGraphics

@MainActor
public enum CuentaAtras {
    private static var panel: NSPanel?
    private static var tarea: Task<Void, Never>?
    /// Esc llego como evento (la app tenia el foco).
    private static var escPorEvento = false

    /// Separacion del borde de la pantalla y lado del cartel (los de
    /// Windows, en puntos).
    nonisolated static let margen: CGFloat = 24
    nonisolated static let lado: CGFloat = 108
    /// Cada cuanto se mira Esc: corto para que responda al momento.
    static let latido: Duration = .milliseconds(16)

    /// Si hay una cuenta en marcha.
    public static var contando: Bool { tarea != nil }

    /// Los segundos que quedan para el numero grande: hacia arriba, para que
    /// una cuenta de 3 ensene «3», «2» y «1» (y 0 al llegar).
    nonisolated static func quedan(total: Double, transcurrido: Double) -> Int {
        let resta = total - transcurrido
        guard resta > 0 else { return 0 }
        return Int(resta.rounded(.up))
    }

    /// Donde va el cartel en una pantalla de marco `pantalla` (AppKit):
    /// abajo a la derecha, a `margen` de los bordes.
    nonisolated static func marco(en pantalla: CGRect) -> CGRect {
        CGRect(x: pantalla.maxX - lado - margen, y: pantalla.minY + margen, width: lado, height: lado)
    }

    /// Cuenta `segundos` (por defecto, los de los ajustes) y llama a
    /// `alAcabar`; si se pulsa Esc, se para y no se llama. Si ya hay una
    /// cuenta, no empieza otra.
    public static func empezar(segundos: Int? = nil, alAcabar: @escaping @MainActor () -> Void) {
        guard tarea == nil else { return }
        let total = max(0, segundos ?? AjustesCaptura.actuales().retardoSegundos)
        guard total > 0 else { return alAcabar() }
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let cartel = pantalla.map { hacerCartel(en: $0.visibleFrame) }
        let numero = cartel?.1
        panel = cartel?.0
        panel?.orderFrontRegardless()
        // Si la app SI tiene el foco (se lanzo desde su menu), Esc llega
        // como evento: tambien vale.
        escPorEvento = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53 else { return e }
            MainActor.assumeIsolated { escPorEvento = true }
            return nil
        }
        tarea = Task { @MainActor in
            defer {
                if let monitor { NSEvent.removeMonitor(monitor) }
                tarea = nil
            }
            let inicio = ContinuousClock.now
            var pintado = -1
            var cancelada = false
            while true {
                if escPorEvento || CGEventSource.keyState(.combinedSessionState, key: 53) {
                    cancelada = true
                    break
                }
                let pasado = ContinuousClock.now - inicio
                let t = Double(pasado.components.seconds) + Double(pasado.components.attoseconds) / 1e18
                let n = quedan(total: Double(total), transcurrido: t)
                if n == 0 { break }
                if n != pintado {
                    pintado = n
                    numero?.stringValue = "\(n)"
                }
                try? await Task.sleep(for: latido)
            }
            panel?.orderOut(nil)
            panel = nil
            guard !cancelada else { return }
            // Un respiro para que el servidor de ventanas quite el cartel
            // antes de la foto (`esperar_composicion` de Windows).
            try? await Task.sleep(for: .milliseconds(80))
            alAcabar()
        }
    }

    /// Para la cuenta en marcha sin capturar.
    public static func cancelar() {
        tarea?.cancel()
        tarea = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// El cartel: el numero grande y, debajo, como se para.
    private static func hacerCartel(en pantalla: CGRect) -> (NSPanel, NSTextField) {
        let marco = marco(en: pantalla)
        let p = NSPanel(contentRect: marco, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let fondo = NSView(frame: CGRect(origin: .zero, size: marco.size))
        fondo.wantsLayer = true
        // Los colores del cartel de Windows (FONDO, TINTA y TENUE).
        fondo.layer?.backgroundColor = CGColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 0.90)
        fondo.layer?.cornerRadius = 16
        let numero = NSTextField(labelWithString: "")
        numero.font = .monospacedDigitSystemFont(ofSize: 46, weight: .semibold)
        numero.textColor = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        numero.alignment = .center
        numero.frame = CGRect(x: 0, y: 40, width: lado, height: 56)
        fondo.addSubview(numero)
        let pie = NSTextField(labelWithString: "Esc para parar")
        pie.font = .systemFont(ofSize: 11)
        pie.textColor = NSColor(srgbRed: 0.62, green: 0.63, blue: 0.66, alpha: 1)
        pie.alignment = .center
        pie.frame = CGRect(x: 0, y: 14, width: lado, height: 16)
        fondo.addSubview(pie)
        p.contentView = fondo
        return (p, numero)
    }
}
