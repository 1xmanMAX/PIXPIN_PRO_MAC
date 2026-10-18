// PixPin para Mac: vive en la barra de menus (como la bandeja de Windows) y
// abre la ventana de Proyectos cuando se pide.

import PixPinKit
import SwiftUI

@main
struct PixPinApp: App {
    @StateObject private var estado = EstadoApp()
    /// Abrir ficheros desde el Finder (planos, documentos, imagenes), los
    /// enlaces `pixpinmax://`, el menu del Dock y los Servicios (C2).
    @NSApplicationDelegateAdaptor(DelegadoApp.self) private var delegado

    var body: some Scene {
        // El icono de la barra de menus (con su panel y su menu del clic
        // derecho) lo pone `IconoBandeja` al arrancar (E4).
        // Al abrir PixPin se ve la ventana de Proyectos (si no, solo estaria
        // el icono de la barra de menus, que tras la muesca ni se ve), y al
        // abrirla otra vez con la app ya abierta, vuelve a salir.
        Window("Proyectos", id: "proyectos") {
            Group {
                if let almacen = estado.almacen {
                    VentanaProyectos(almacen: almacen)
                        .frame(minWidth: 720, minHeight: 480)
                } else {
                    ContentUnavailableView("No se pudo abrir la carpeta de datos",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(estado.error ?? ""))
                }
            }
            .modifier(AlReabrirSaleProyectos())
            .ventanaLisa()
        }
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(.presented)
        Window("Sincronizar", id: "sincronizar") {
            Group {
                if let sincro = estado.sincro {
                    VistaSincro(sincro: sincro)
                } else {
                    ContentUnavailableView("No se pudo abrir la carpeta de datos",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(estado.error ?? ""))
                }
            }
            .ventanaLisa()
        }
        .defaultSize(width: 520, height: 600)
        Window("Lecciones", id: "lecciones") {
            Group {
                if let almacen = estado.almacen {
                    VentanaLecciones(nucleo: almacen.nucleo)
                        .frame(minWidth: 760, minHeight: 480)
                } else {
                    ContentUnavailableView("No se pudo abrir la carpeta de datos",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(estado.error ?? ""))
                }
            }
            .ventanaLisa()
        }
        .defaultSize(width: 960, height: 640)
        Window("Asistente", id: "asistente") {
            VentanaAsistente(almacen: estado.almacen)
                .ventanaLisa()
        }
        .defaultSize(width: 460, height: 640)
        // Ajustes (⌘,): lo que vale en Windows y Mac va a `pixpinmax.toml`.
        Settings {
            Group {
                if let ajustes = estado.ajustes {
                    VistaAjustes(modelo: ajustes, atajos: estado.atajos)
                } else {
                    ContentUnavailableView("No se pudo abrir la carpeta de datos",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(estado.error ?? ""))
                        .frame(width: 420, height: 240)
                }
            }
            .ventanaLisa()
        }
        Window("Galería de capturas", id: IdVentana.galeria) {
            ConAlmacen(estado.almacen, error: estado.error) { VentanaGaleria(almacen: $0) }
                .ventanaLisa()
        }
        .defaultSize(width: 900, height: 640)
        Window("Timeline", id: IdVentana.timeline) {
            ConAlmacen(estado.almacen, error: estado.error) { VentanaTimeline(almacen: $0) }
                .ventanaLisa()
        }
        .defaultSize(width: 860, height: 640)
        Window("Tareas", id: IdVentana.tareas) {
            ConAlmacen(estado.almacen, error: estado.error) { VentanaTareas(almacen: $0) }
                .ventanaLisa()
        }
        .defaultSize(width: 620, height: 640)
        // En un `Group`: un `SceneBuilder` admite diez escenas seguidas.
        Group {
            Window("Buscar en PixPin", id: IdVentana.buscar) {
                ConAlmacen(estado.almacen, error: estado.error) { VentanaBuscar(almacen: $0) }
                    .ventanaLisa()
            }
            .defaultSize(width: 900, height: 600)
            // Enviar y recibir con un codigo de seis cifras, y los chats
            // compartidos con personas (`Sincro/`).
            Window("Enviar y recibir por Wi-Fi", id: "envio") {
                ConAlmacen(estado.almacen, error: estado.error) { VistaEnvio(nucleo: $0.nucleo) }
                    .ventanaLisa()
            }
            .defaultSize(width: 460, height: 560)
            Window("Chats compartidos", id: "compartidos") {
                ConAlmacen(estado.almacen, error: estado.error) {
                    VistaCompartidos(almacen: $0, sincro: estado.sincro)
                }
                .ventanaLisa()
            }
            .defaultSize(width: 520, height: 640)
            // Las automatizaciones del asistente (E6).
            Window("Automatizaciones", id: "automatizaciones") {
                ConAlmacen(estado.almacen, error: estado.error) { VentanaAutomatizaciones(almacen: $0) }
                    .ventanaLisa()
            }
            .defaultSize(width: 720, height: 600)
        }
    }
}

/// El almacen se abre una vez al arrancar; si falla, se dice en la ventana.
@MainActor
final class EstadoApp: ObservableObject {
    let almacen: Almacen?
    let error: String?
    /// Sincronizar con los demas aparatos del grupo (escucha, anuncio y
    /// busqueda viven lo que la app, como la presencia de Windows).
    let sincro: Sincronizador?
    /// Capturar una zona (Ctrl+Option+X en todo el Mac).
    let capturador: Capturador
    /// Los atajos globales de todos los comandos (se cambian en Ajustes).
    let atajos = GestorAtajos()
    /// Lo de Ajustes (`pixpinmax.toml`, tema, abrir al iniciar sesion).
    let ajustes: ModeloAjustes?
    /// Lleva las capturas caducadas a la Papelera.
    private var barrendero: BarrenderoCapturas?

    init() {
        let capturador = Capturador()
        self.capturador = capturador
        do {
            almacen = try Almacen()
            error = nil
        } catch {
            almacen = nil
            self.error = "\(error)"
        }
        // «Abrir con PixPin» desde el Finder: PDF al lector, Office a un pin.
        if let almacen { AbrirDesdeFinder.compartido.instalar(nucleo: almacen.nucleo) }
        let sincro = almacen.map { Sincronizador(nucleo: $0.nucleo) }
        VentanasDePlano.compartidas.nucleo = almacen?.nucleo
        self.sincro = sincro
        ajustes = almacen.map { ModeloAjustes(nucleo: $0.nucleo, sincro: sincro) }
        if let almacen, let sincro {
            sincro.alTraerCambios = { [weak almacen, weak sincro] in
                Task { await almacen?.cargarChats() }
                // Un temporizador o una alarma puestos en otro aparato
                // tambien suenan aqui.
                AvisosMini.compartido.reprogramar()
                // Y un recordatorio puesto en el movil (A4).
                Recordatorios.compartido.releer()
                // Las automatizaciones «al sincronizar» (E6) y las que
                // llegaron de otro aparato.
                MotorAutomatizaciones.compartido.alSincronizar(sincro?.ultimoResultado ?? "")
            }
            sincro.arrancar()
        }
        // Lo que se hace con la zona elegida: pinearla o sacar su texto.
        capturador.alPinear = { GestorPines.compartido.pinear(imagen: $0) }
        // Pines: en vivo (tecla L al capturar), las mini-apps en «Mensajes
        // guardados» y ⌃2 para mostrar u ocultar todos.
        // Pin en vivo de una zona (modo `L` de la captura y Option + boton
        // central): la pantalla es la que contiene la zona.
        let pinEnVivo: (CGRect) -> Void = { zona in
            let pantalla = NSScreen.screens.first { $0.frame.intersects(zona) } ?? NSScreen.main
            guard let pantalla else { NSSound.beep(); return }
            GestorPines.compartido.pinearEnVivo(zona: zona, pantalla: pantalla)
        }
        capturador.alPinEnVivo = pinEnVivo
        GestorPines.compartido.nucleo = almacen?.nucleo
        // Los temporizadores y alarmas de las mini-apps avisan a su hora,
        // con su pin abierto o no (`AvisosMini`).
        if let nucleo = almacen?.nucleo { AvisosMini.compartido.vigilar(nucleo: nucleo) }
        // Los recordatorios de los mensajes y las tareas (A4), con las
        // notificaciones comunes (C4).
        CentroAvisos.compartido.preparar()
        if let nucleo = almacen?.nucleo { Recordatorios.compartido.vigilar(nucleo: nucleo) }
        // Las automatizaciones (E6): la hora, las capturas nuevas y la
        // sincronizacion las hacen saltar.
        if let nucleo = almacen?.nucleo { MotorAutomatizaciones.compartido.arrancar(nucleo: nucleo, almacen: almacen) }
        capturador.alSacarTexto = { imagen in
            Task {
                guard let texto = try? await sacarTexto(de: imagen), !texto.isEmpty else {
                    NSSound.beep()
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(texto, forType: .string)
            }
        }
        // Al chat: el proyecto se elige en un paso (buscador y teclas 1-6).
        if let almacen {
            let selector = SelectorProyecto()
            capturador.alMandarAlChat = { selector.elegir(para: $0, almacen: almacen) }
        }
        // Copiar apila (⌘V pega la tanda); scroll y GIF de la zona elegida.
        let pila = PilaCapturas.compartida
        capturador.alCopiar = { pila.copiar($0, escala: $1) }
        let scroll = CapturaConScroll.compartida
        scroll.alTerminar = { imagen, escala in
            Capturador.copiar(imagen, escala: escala)
            GestorPines.compartido.pinear(imagen: imagen)
        }
        capturador.alScroll = { zona in Task { await scroll.empezar(zona) } }
        let gif = GrabadorGif.compartido
        gif.alGuardar = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        capturador.alGif = { zona in Task { await gif.empezar(zona) } }
        // Los gestos con Option en todo el Mac (apagados de fabrica).
        let gestos = GestosAlt.compartido
        gestos.alCopiar = { pila.copiar($0, escala: $1) }
        gestos.alPinear = { GestorPines.compartido.pinear(imagen: $0, marco: $1) }
        gestos.alAnotarPantalla = { capturador.anotarPantalla() }
        // El anotador de pantalla guarda en «Mensajes guardados» y copia a la pila.
        AnotadorPantalla.compartido.almacen = almacen
        AnotadorPantalla.compartido.alCopiar = { pila.copiar($0, escala: $1) }
        gestos.alPinEnVivo = pinEnVivo
        gestos.arrancarSiToca()
        // Grabar la pantalla: elegir la zona con la misma captura (Intro o
        // ⌘G graba) y parar desde la barra de menus o con el mismo atajo.
        let grabador = GrabadorPantalla.compartido
        capturador.alGrabar = { zona in Task { await grabador.empezar(zona) } }
        grabador.alGuardar = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        // Los atajos globales: cada comando del catalogo con quien lo hace
        // (⌃⌥X capturar, ⌃2 los pines, ⌃⌥R grabar y los que ate el usuario).
        ComandosApp.atar(atajos, capturador: capturador, pinEnVivo: pinEnVivo,
                         grabarOParar: { EstadoApp.grabarOParar(capturador) })
        if let ajustes {
            // El tema y la sincronizacion sola, como se dejaron.
            ajustes.tema.aplicar()
            Task { await ajustes.cargar() }
        }
        // Las capturas caducadas, a la Papelera (al arrancar y cada hora).
        barrendero = almacen.map { BarrenderoCapturas(nucleo: $0.nucleo) }
        barrendero?.arrancar()
        // Las claves del asistente, en el Llavero del Mac.
        LlaveroDelSistema.instalar()
        // Lo que piden Atajos, Siri y Spotlight (App Intents).
        AccionesApp.compartidas.registrar(almacen: almacen, sincro: sincro,
                                          capturar: { capturador.capturar() })
        // Lo que piden los enlaces `pixpinmax://`, el Dock y los Servicios
        // del Finder (C2); lo que llego al abrir la app se hace ahora.
        HacerPedidos.compartidos.registrar(almacen: almacen, sincro: sincro)
        // El icono de la barra de menus: clic, el panel; clic derecho, el
        // menu (E4). En la siguiente vuelta: la app aun esta arrancando.
        let atajos = self.atajos
        let nucleo = almacen?.nucleo
        DispatchQueue.main.async {
            IconoBandeja.compartido.instalar(atajos: atajos, nucleo: nucleo, sincro: sincro)
        }
    }

    /// Empieza a elegir que grabar o, si ya graba, para.
    static func grabarOParar(_ capturador: Capturador) {
        let grabador = GrabadorPantalla.compartido
        if GrabadorGif.compartido.grabando {
            Task { await GrabadorGif.compartido.parar() }
        } else if grabador.grabando {
            Task { await grabador.parar() }
        } else {
            capturador.capturar(paraGrabar: true)
        }
    }
}

/// Guarda como abrir la ventana de Proyectos para cuando se abre PixPin
/// otra vez (`DelegadoAbrirFicheros.alReabrir`) y la trae al frente.
struct AlReabrirSaleProyectos: ViewModifier {
    @Environment(\.openWindow) private var abrirVentana
    @Environment(\.openSettings) private var abrirAjustes

    func body(content: Content) -> some View {
        content.onAppear {
            let abrir = abrirVentana
            // Los atajos que abren ventanas (Proyectos, Buscar, Ajustes...).
            ComandosApp.abrirVentana = { abrir(id: $0) }
            let ajustes = abrirAjustes
            ComandosApp.abrirAjustes = { ajustes() }
            DelegadoAbrirFicheros.alReabrir = {
                abrir(id: "proyectos")
                NSApp.activate()
            }
            NSApp.activate()
        }
    }
}
