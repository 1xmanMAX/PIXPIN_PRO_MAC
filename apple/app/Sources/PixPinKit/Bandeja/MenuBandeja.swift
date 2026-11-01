// **El menu del clic derecho en el icono** (`acciones_de_bandeja` y
// `mostrar_menu` de Windows): el de siempre, de respaldo del panel. Cada
// entrada es su comando del catalogo (`GestorAtajos.ejecutar`) con su atajo
// a la vista; ademas, «Grupos de ventanas» y, si hay pines ocultos por
// grupos, «Grupos ocultos» (se arma al abrirlo: un grupo recien ocultado
// sale ya). «Salir» va aparte, al final y tras una raya.

import AppKit
import SwiftUI

@MainActor
enum MenuBandeja {
    static func armar(atajos: GestorAtajos, sincro: Sincronizador?) -> NSMenu {
        let menu = NSMenu(title: "PixPin")
        menu.autoenablesItems = false
        let grabador = GrabadorPantalla.compartido
        let pines = GestorPines.compartido

        func comando(_ titulo: String, _ c: ComandoAtajo, siNo: KeyboardShortcut? = nil) -> NSMenuItem {
            let i = ItemConAccion.nuevo(titulo) { atajos.ejecutar(c) }
            ponerTecla(i, atajos.atajoActivo(de: c)?.enMenu ?? siNo)
            return i
        }
        func ventana(_ titulo: String, _ id: String) -> NSMenuItem {
            ItemConAccion.nuevo(titulo) { IconoBandeja.abrirVentana(id) }
        }
        func cierre(_ titulo: String, _ hacer: @escaping @MainActor () -> Void) -> NSMenuItem {
            ItemConAccion.nuevo(titulo, hacer)
        }

        // Capturar.
        menu.addItem(comando("Capturar zona", .capturarRegion))
        menu.addItem(comando(Lengua.t("comando-capturar-y-anotar"), .capturarYAnotar))
        menu.addItem(comando("Capturar con retardo (3 s)", .capturarConRetardo))
        menu.addItem(comando(Lengua.t("comando-copiar-texto"), .copiarTexto))
        menu.addItem(comando(Lengua.t("comando-anotar"), .anotar))
        menu.addItem(comando("Anotar la pantalla congelada", .anotarCongelada))
        menu.addItem(comando(Lengua.t("comando-cuentagotas"), .cuentagotas))
        menu.addItem(comando("Grabar un GIF", .grabarGif))
        menu.addItem(comando(grabador.grabando ? "Detener grabación" : "Grabar pantalla", .grabarPantalla))
        let sonido = cierre("Grabar con el sonido del sistema") { grabador.conSonido.toggle() }
        sonido.state = grabador.conSonido ? .on : .off
        sonido.isEnabled = !grabador.grabando
        menu.addItem(sonido)
        // La clase o la reunion (Windows edd0ffa): su ventanita flotante.
        menu.addItem(comando("Grabar clase o reunión…", .grabarClase))
        menu.addItem(.separator())

        // Las ventanas.
        menu.addItem(comando("Proyectos…", .abrirChat, siNo: KeyboardShortcut("p", modifiers: [.command, .option])))
        menu.addItem(comando("Sincronizar…", .sincronizar))
        // Detras de Sincronizar, como la bandeja de Windows (`bandeja-figuras`).
        if let nucleo = IconoBandeja.compartido.nucleo {
            menu.addItem(cierre(Lengua.t("bandeja-figuras")) { VentanaFiguras.abrir(nucleo: nucleo, destino: nil) })
        }
        if let sincro { menu.addItem(enviarA(sincro)) }
        menu.addItem(comando("Enviar y recibir por Wi-Fi…", .recibirDelMovil))
        menu.addItem(ventana("Chats compartidos…", "compartidos"))
        menu.addItem(ventana("Lecciones…", "lecciones"))
        menu.addItem(ventana("Asistente…", "asistente"))
        menu.addItem(ventana("Automatizaciones…", "automatizaciones"))
        menu.addItem(comando("Buscar en PixPin…", .buscar, siNo: KeyboardShortcut("f", modifiers: [.command, .option])))
        menu.addItem(ventana(Lengua.t("bandeja-galeria-capturas"), IdVentana.galeria))
        menu.addItem(ventana("Timeline…", IdVentana.timeline))
        menu.addItem(ventana("Tareas…", IdVentana.tareas))
        if let nucleo = IconoBandeja.compartido.nucleo {
            menu.addItem(cierre("Horario de clases…") { HorarioClases.abrir(nucleo: nucleo) })
            menu.addItem(cierre("Nota de voz para la próxima clase") { HorarioClases.grabarParaLaProxima(nucleo: nucleo) })
        }
        menu.addItem(cierre(Lengua.t("bandeja2-documento")) { IconoBandeja.abrirDocumento() })
        let grupos = NSMenuItem(title: Lengua.t("bandeja2-grupos"), action: nil, keyEquivalent: "")
        grupos.submenu = GruposVentanas.compartidos.menu()
        menu.addItem(grupos)
        menu.addItem(.separator())

        // Los pines.
        menu.addItem(comando("Pinear desde el portapapeles", .pinearPortapapeles))
        menu.addItem(comando("Pin en vivo…", .pinearEnVivo))
        menu.addItem(comando("Pinear lo elegido en el Finder", .pinearSeleccion))
        menu.addItem(comando("Ventana encima (pin en vivo)", .ventanaEncima))
        let nuevo = NSMenuItem(title: "Nuevo pin", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(cierre(Lengua.t("chat-adj-nota-md")) { pines.pinearNota() })
        for (t, mini) in [(Lengua.t("mini-tareas"), "tareas"), (Lengua.t("mini-contador"), "contador"), (Lengua.t("mini-ruleta"), "ruleta"),
                          (Lengua.t("mini-gastos"), "gastos"), (Lengua.t("mini-cronometro"), "cronometro"), (Lengua.t("mini-temporizador"), "temporizador"),
                          (Lengua.t("mini-alarma"), "alarma")] {
            sub.addItem(cierre(t) { pines.pinearMiniapp(mini) })
        }
        nuevo.submenu = sub
        menu.addItem(nuevo)
        menu.addItem(cierre(Lengua.t("pin-v2-pines-abiertos")) { pines.mostrarPanelAbiertos() })
        menu.addItem(comando("Mostrar u ocultar los pines", .alternarPines))
        if atajos.disponible(.restaurarUltimoPin) {
            menu.addItem(comando("Restaurar el último pin", .restaurarUltimoPin))
        }
        if atajos.disponible(.alternarPasoDeClics) {
            menu.addItem(comando("Pines: dejar pasar el clic", .alternarPasoDeClics))
        }
        menu.addItem(comando(Lengua.t("comando-cerrar-todos-los-pines"), .cerrarTodosLosPines))
        let ocultos = pines.gruposOcultos()
        if !ocultos.isEmpty {
            let item = NSMenuItem(title: Lengua.t("grupos-ocultos"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for g in ocultos {
                let i = cierre(g.etiqueta) { if pines.mostrarGrupo(g.id) == 0 { NSSound.beep() } }
                i.image = Pin.muestra(ColoresGrupo.nsColor(g.color))
                sub.addItem(i)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Siempre en el menu: con los atajos soltados, es la unica vuelta.
        let silenciar = cierre(Lengua.t("bandeja2-silenciar")) { atajos.silenciar(!atajos.silenciados) }
        silenciar.state = atajos.silenciados ? .on : .off
        menu.addItem(silenciar)
        let ajustes = cierre("Ajustes…") {
            ComandosApp.abrirAjustes?()
            NSApp.activate()
        }
        ajustes.keyEquivalent = ","
        menu.addItem(ajustes)
        menu.addItem(.separator())
        let salir = cierre(Lengua.t("bandeja2-salir")) { NSApp.terminate(nil) }
        salir.keyEquivalent = "q"
        menu.addItem(salir)
        return menu
    }

    /// «Enviar a…»: los aparatos del grupo (`MenuEnviarA`, en AppKit).
    private static func enviarA(_ sincro: Sincronizador) -> NSMenuItem {
        let item = NSMenuItem(title: "Enviar a…", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        if sincro.filas.isEmpty {
            let nada = NSMenuItem(title: sincro.codigoLegible == nil ? "Sin grupo: únete en Sincronizar"
                : "Ningún aparato del grupo en esta Wi-Fi", action: nil, keyEquivalent: "")
            nada.isEnabled = false
            sub.addItem(nada)
        }
        for fila in sincro.filas {
            var titulo = fila.nombre
            if let e = sincro.envios[fila.id], let linea = e.texto.split(separator: "\n").first {
                titulo += " — \(linea)"
            }
            let id = fila.id
            let i = ItemConAccion.nuevo(titulo) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true
                panel.prompt = Lengua.t("sinc-enviar")
                NSApp.activate()
                guard panel.runModal() == .OK else { return }
                let urls = panel.urls
                Task { await sincro.enviar(urls, a: id) }
            }
            i.isEnabled = !(fila.direccion == nil && (fila.estado == .noContesta || fila.estado == .noEncontrado))
            sub.addItem(i)
        }
        item.submenu = sub
        return item
    }

    /// El atajo de SwiftUI, en un elemento de AppKit (solo se ve).
    static func ponerTecla(_ i: NSMenuItem, _ atajo: KeyboardShortcut?) {
        guard let atajo else { return }
        i.keyEquivalent = String(atajo.key.character)
        var m: NSEvent.ModifierFlags = []
        if atajo.modifiers.contains(.command) { m.insert(.command) }
        if atajo.modifiers.contains(.option) { m.insert(.option) }
        if atajo.modifiers.contains(.shift) { m.insert(.shift) }
        if atajo.modifiers.contains(.control) { m.insert(.control) }
        i.keyEquivalentModifierMask = m
    }
}
