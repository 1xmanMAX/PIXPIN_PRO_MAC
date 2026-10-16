// Lo que hacen los comandos con atajo que no abren la captura de siempre
// (los de `ComandoAtajo` de Windows):
//
// - una zona ya decidida (una region guardada o la ultima) se captura y se
//   copia sin superposicion, como `scroll::capturar` + la pila de Windows;
// - el cuentagotas, con el de macOS (`NSColorSampler`: lupa y todo);
// - «ventana encima»: macOS no deja subir la ventana de otra app por
//   encima de todo, asi que se hace un pin en vivo de esa ventana, que si
//   flota encima y se mueve con lo que pase dentro;
// - la cuenta atras de capturar con retardo;
// - pinear lo elegido en el Finder (lo pide por Apple Events).

import AppKit

extension Capturador {
    // MARK: Una zona ya decidida

    /// Captura `zona` (coordenadas globales de AppKit) y la copia (a la
    /// pila, como un ⌘C de la captura). Sin superposicion ni preguntas.
    public func capturarYa(_ zona: CGRect) {
        guard !abierta, zona.width >= 1, zona.height >= 1 else { return NSSound.beep() }
        guard PermisoCaptura.asegurar() else { return }
        Task { @MainActor in
            guard let fotos = try? await Instantanea.fotografiarTodas(),
                  let (recorte, escala) = Capturador.recortar(zona, de: fotos) else {
                return NSSound.beep()
            }
            if let alCopiar { alCopiar(recorte, escala) } else { Capturador.copiar(recorte, escala: escala) }
        }
    }

    /// La ultima zona elegida en la pantalla del raton (o en cualquiera),
    /// en coordenadas globales de AppKit; `nil` si aun no hay ninguna.
    public static func ultimaZonaGlobal(_ ultima: UltimaZona = UltimaZona()) -> CGRect? {
        let raton = NSEvent.mouseLocation
        let pantallas = NSScreen.screens.sorted { a, _ in a.frame.contains(raton) }
        for p in pantallas {
            guard let n = p.numeroDePantalla, let r = ultima.leer(pantalla: n) else { continue }
            return r.offsetBy(dx: p.frame.minX, dy: p.frame.minY)
        }
        return nil
    }

    /// Repite la ultima zona sin abrir la captura (el `R` de la captura,
    /// pero desde un atajo).
    public func capturarUltimaZona() {
        guard let zona = Capturador.ultimaZonaGlobal() else { return NSSound.beep() }
        capturarYa(zona)
    }

    /// El trozo de la foto de la pantalla donde cae mas de la zona.
    static func recortar(_ zona: CGRect, de fotos: [FotoDePantalla]) -> (CGImage, CGFloat)? {
        let candidata = fotos.max { a, b in
            area(a.pantalla.frame.intersection(zona)) < area(b.pantalla.frame.intersection(zona))
        }
        guard let foto = candidata else { return nil }
        let marco = foto.pantalla.frame
        let dentro = marco.intersection(zona)
        guard !dentro.isNull, dentro.width >= 1, dentro.height >= 1 else { return nil }
        let local = dentro.offsetBy(dx: -marco.minX, dy: -marco.minY)
        let px = GeometriaCaptura.rectEnPixeles(local, tamVista: marco.size,
                                                ancho: foto.imagen.width, alto: foto.imagen.height)
        guard !px.isEmpty, let trozo = foto.imagen.cropping(to: px) else { return nil }
        let entera = CGSize(width: foto.imagen.width, height: foto.imagen.height)
        return (suelto(trozo, entera: entera), foto.pantalla.backingScaleFactor)
    }

    private static func area(_ r: CGRect) -> CGFloat {
        r.isNull ? 0 : r.width * r.height
    }

    // MARK: Cuentagotas

    /// El cuentagotas de macOS: el color elegido se copia en HEX (como la
    /// `C` de la captura). Esc lo cancela.
    public static func cuentagotas() {
        NSApp.activate()
        NSColorSampler().show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = MedidasCaptura.hex(UInt8((c.redComponent * 255).rounded()),
                                         UInt8((c.greenComponent * 255).rounded()),
                                         UInt8((c.blueComponent * 255).rounded()))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
        }
    }

    // MARK: Ventana encima

    /// El marco (AppKit) de la ventana de otra app que hay bajo el raton.
    public static func ventanaBajoElRaton() -> CGRect? {
        let raton = NSEvent.mouseLocation
        return Instantanea.ventanasVisibles().first { $0.marco.contains(raton) }?.marco
    }
}

// MARK: - Cuenta atras

/// Los segundos antes de capturar con retardo, grandes en el centro de la
/// pantalla del raton (sin quitar el foco: el menu que se quiere capturar
/// sigue abierto). Como la `cuenta_atras` de Windows, de 3.
@MainActor
public enum CuentaAtras {
    private static var panel: NSPanel?

    public static func empezar(segundos: Int = 3, alAcabar: @escaping @MainActor () -> Void) {
        guard panel == nil else { return }
        let lado: CGFloat = 120
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let pantalla else { return alAcabar() }
        let marco = CGRect(x: pantalla.frame.midX - lado / 2, y: pantalla.frame.midY - lado / 2,
                           width: lado, height: lado)
        let p = NSPanel(contentRect: marco, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let fondo = NSVisualEffectView(frame: CGRect(origin: .zero, size: marco.size))
        fondo.material = .hudWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 24
        let numero = NSTextField(labelWithString: "\(segundos)")
        numero.font = .monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        numero.alignment = .center
        numero.frame = CGRect(x: 0, y: (lado - 80) / 2, width: lado, height: 80)
        fondo.addSubview(numero)
        p.contentView = fondo
        p.orderFrontRegardless()
        panel = p
        Task { @MainActor in
            for s in stride(from: segundos, to: 0, by: -1) {
                numero.stringValue = "\(s)"
                try? await Task.sleep(for: .seconds(1))
            }
            p.orderOut(nil)
            panel = nil
            // Un respiro para que la cuenta no salga en la foto.
            try? await Task.sleep(for: .milliseconds(80))
            alAcabar()
        }
    }
}

// MARK: - Lo elegido en el Finder

public enum SeleccionFinder {
    /// Los ficheros elegidos en el Finder (pide permiso la primera vez).
    /// Vacio si el Finder no tiene nada elegido o no se dio permiso.
    @MainActor
    public static func ficheros() -> [URL] {
        let guion = """
        tell application "Finder"
            set lista to {}
            repeat with f in (get selection)
                set end of lista to POSIX path of (f as alias)
            end repeat
            return lista
        end tell
        """
        var error: NSDictionary?
        guard let resultado = NSAppleScript(source: guion)?.executeAndReturnError(&error) else { return [] }
        var rutas: [URL] = []
        let n = resultado.numberOfItems
        if n == 0, let una = resultado.stringValue, !una.isEmpty {
            return [URL(fileURLWithPath: una)]
        }
        if n > 0 {
            for i in 1 ... n {
                if let r = resultado.atIndex(i)?.stringValue { rutas.append(URL(fileURLWithPath: r)) }
            }
        }
        return rutas
    }
}
