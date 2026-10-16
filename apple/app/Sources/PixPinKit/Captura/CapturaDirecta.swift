// Lo que hacen los comandos con atajo que no abren la captura de siempre
// (los de `ComandoAtajo` de Windows):
//
// - una zona ya decidida (una region guardada o la ultima) se captura y se
//   copia sin superposicion, como `scroll::capturar` + la pila de Windows;
// - el cuentagotas: la captura con `.cuentagotas` (la lupa y nada mas);
// - «ventana encima»: macOS no deja subir la ventana de otra app por
//   encima de todo, asi que se hace un pin en vivo de esa ventana, que si
//   flota encima y se mueve con lo que pase dentro;
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

    // El cuentagotas suelto es la captura abierta como `.cuentagotas`: la
    // misma lupa, y clic, Intro o `C` copian en el formato de los ajustes.

    // MARK: Ventana encima

    /// El marco (AppKit) de la ventana de otra app que hay bajo el raton.
    public static func ventanaBajoElRaton() -> CGRect? {
        let raton = NSEvent.mouseLocation
        return Instantanea.ventanasVisibles().first { $0.marco.contains(raton) }?.marco
    }
}

// La cuenta atras de capturar con retardo: `CuentaAtras.swift`.

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
