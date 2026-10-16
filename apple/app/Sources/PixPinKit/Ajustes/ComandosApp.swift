// Quien hace cada comando del catalogo (`ComandoAtajo`): lo mismo que el
// `match` del bucle de Windows, pero atado una vez al arrancar. El atajo y
// la entrada del menu llaman a lo mismo (`GestorAtajos.ejecutar`).
//
// «Dejar pasar el clic» en todos los pines (la vuelta del ⌘T de un pin) y
// «restaurar el ultimo pin» los hace `GestorPines` (B1).

import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
public enum ComandosApp {
    /// Abrir una ventana de SwiftUI por su id (lo pone la app desde una
    /// vista, que es quien tiene `openWindow`).
    public static var abrirVentana: ((String) -> Void)?
    /// Abrir Ajustes (lo pone la app desde una vista: `openSettings`).
    public static var abrirAjustes: (() -> Void)?

    /// Ata todos los comandos que el Mac sabe hacer.
    public static func atar(_ atajos: GestorAtajos, capturador: Capturador,
                            pinEnVivo: @escaping @MainActor (CGRect) -> Void,
                            grabarOParar: @escaping @MainActor () -> Void) {
        let pines = GestorPines.compartido
        atajos.poner(.capturarRegion) { capturador.capturar() }
        atajos.poner(.capturarYCopiar) { capturador.capturar(.copiar) }
        atajos.poner(.capturarConScroll) { capturador.capturar(.scroll) }
        atajos.poner(.capturarYAnotar) { capturador.capturar(.anotar) }
        atajos.poner(.grabarGif) {
            // Con la sesion del GIF abierta, el mismo atajo empieza o para.
            if GrabadorGif.compartido.enSesion {
                GrabadorGif.compartido.alternar()
            } else {
                capturador.capturar(.gif)
            }
        }
        atajos.poner(.capturarUltimaRegion) { capturador.capturarUltimaZona() }
        atajos.poner(.cuentagotas) { capturador.capturar(.cuentagotas) }
        atajos.poner(.pinear) { capturador.capturar(.pinear) }
        atajos.poner(.pinearEnVivo) { capturador.capturar(.enVivo) }
        atajos.poner(.pinearPortapapeles) {
            if !pines.pinearDesdePortapapeles() { NSSound.beep() }
        }
        // En el Mac la anotacion de pantalla es siempre sobre la foto
        // congelada; las dos entradas de Windows hacen lo mismo.
        atajos.poner(.anotar) { capturador.anotarPantalla() }
        atajos.poner(.anotarCongelada) { capturador.anotarPantalla() }
        atajos.poner(.pinearSeleccion) {
            let ficheros = SeleccionFinder.ficheros()
            var alguno = false
            for f in ficheros where pines.pinear(fichero: f) { alguno = true }
            if !alguno { NSSound.beep() }
        }
        atajos.poner(.capturarConRetardo) {
            CuentaAtras.empezar { capturador.capturar() }
        }
        atajos.poner(.silenciarAtajos) { [weak atajos] in
            guard let atajos else { return }
            atajos.silenciar(!atajos.silenciados)
        }
        atajos.poner(.alternarPines) { pines.alternarTodos() }
        atajos.poner(.cerrarTodosLosPines) { pines.cerrarTodosConDeshacer() }
        atajos.poner(.alternarPasoDeClics) { _ = pines.alternarPasoDeClics() }
        atajos.poner(.restaurarUltimoPin) {
            if !pines.restaurarUltimoCerrado() { NSSound.beep() }
        }
        atajos.poner(.copiarTexto) { capturador.capturar(.texto) }
        atajos.poner(.ventanaEncima) {
            guard let marco = Capturador.ventanaBajoElRaton() else { return NSSound.beep() }
            pinEnVivo(marco)
        }
        atajos.poner(.abrirChat) { abrir(IdVentana.proyectos) }
        atajos.poner(.abrirAjustes) {
            guard let abrirAjustes else { return NSSound.beep() }
            abrirAjustes()
            NSApp.activate()
        }
        atajos.poner(.recibirDelMovil) { abrir("envio") }
        atajos.poner(.salir) { NSApp.terminate(nil) }
        atajos.poner(.sincronizar) { abrir("sincronizar") }
        atajos.poner(.buscar) { abrir(IdVentana.buscar) }
        atajos.poner(.grabarPantalla) { grabarOParar() }
        // Una region guardada se captura y se copia, sin superposicion.
        atajos.alCapturarRegion = { region in
            let alto = NSScreen.screens.first?.frame.height ?? 0
            capturador.capturarYa(region.rectAppKit(altoPantallaPrincipal: alto))
        }
    }

    private static func abrir(_ id: String) {
        guard let abrirVentana else { return NSSound.beep() }
        abrirVentana(id)
        NSApp.activate()
    }
}

// MARK: - En los menus

public extension AtajoGlobal.Combinacion {
    /// El mismo atajo para ensenarlo en un menu de SwiftUI (`nil` si la
    /// tecla no tiene equivalente).
    var enMenu: KeyboardShortcut? {
        guard let texto = AtajoGlobal.Combinacion.textoDeTecla(tecla) else { return nil }
        let tecla: KeyEquivalent
        if texto.count > 1, texto.hasPrefix("F"), let n = Int(texto.dropFirst()),
           let escalar = UnicodeScalar(NSF1FunctionKey + n - 1) {
            tecla = KeyEquivalent(Character(escalar))
        } else if let c = texto.lowercased().first {
            tecla = KeyEquivalent(c)
        } else {
            return nil
        }
        var m: SwiftUI.EventModifiers = []
        if modificadores & UInt32(controlKey) != 0 { m.insert(.control) }
        if modificadores & UInt32(optionKey) != 0 { m.insert(.option) }
        if modificadores & UInt32(shiftKey) != 0 { m.insert(.shift) }
        if modificadores & UInt32(cmdKey) != 0 { m.insert(.command) }
        return KeyboardShortcut(tecla, modifiers: m)
    }
}

public extension View {
    /// Ensena en el menu el atajo global del comando (si lo tiene y esta
    /// registrado); si no, `siNo` (un atajo solo del menu).
    func atajo(_ c: ComandoAtajo, _ atajos: GestorAtajos, siNo: KeyboardShortcut? = nil) -> some View {
        keyboardShortcut(atajos.atajoActivo(de: c)?.enMenu ?? siNo)
    }
}
