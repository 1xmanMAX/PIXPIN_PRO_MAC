// Capturar una zona de la pantalla: la foto congelada, elegir la zona y lo
// que se hace con ella (copiar, pinear, al chat, texto, guardar), anotada
// encima si se quiere (1-5). Modos `Z V P S G L T`, medidas tecleadas,
// proporciones, `R` repetir la ultima zona, `C` copiar el color (⇧ sola
// cambia HEX/RGB), ⌘A la pantalla entera, flechas (⇧ ×10) para mover la
// zona, Espacio para ver la pantalla en vivo y ⇧⌘S guardar como.
//
// Lo que no es de la captura lo hacen otros por los ganchos `alPinear`,
// `alMandarAlChat` y `alSacarTexto`: si un gancho no esta puesto, su boton
// sale apagado.
//
// Rendimiento (§4bis del plan):
// - una foto por pantalla al abrir, y se suelta al cerrar (las vistas
//   sueltan sus capas y los paneles se cierran y se olvidan);
// - el recorte es `CGImage.cropping(to:)`: sin copiar ni recodificar. Si lo
//   recortado va a vivir mas que la captura (pin, chat, OCR) y es pequeno
//   frente a la pantalla, se copia aparte para no retener la foto entera;
// - codificar el PNG/TIFF y escribir el fichero van fuera del hilo
//   principal, con prioridad baja.

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Para que se abre la captura (los comandos con atajo de Windows): elegir
/// la zona y luego la barra, o hacer ya algo al elegirla.
public enum IntencionCaptura: Sendable {
    /// La de siempre: elegir y luego la barra de acciones.
    case normal
    /// Al elegir, copiar (sin barra).
    case copiar
    /// Al elegir, pinear.
    case pinear
    /// Al elegir, el lapiz en la mano.
    case anotar
    /// Modo `T`: al elegir, sacar el texto.
    case texto
    /// Modo `S`: captura con scroll.
    case scroll
    /// Modo `G`: grabar un GIF.
    case gif
    /// Modo `L`: pin en vivo.
    case enVivo
    /// El cuentagotas suelto: la lupa sin zona; clic, Intro o `C` copian
    /// el color y cierran, Esc cierra.
    case cuentagotas
}

@MainActor
public final class Capturador {
    /// Hace un pin con la imagen recortada.
    public var alPinear: ((CGImage) -> Void)?
    /// Manda la imagen a un proyecto (el que elija el usuario).
    public var alMandarAlChat: ((CGImage) -> Void)?
    /// Saca el texto de la imagen (OCR con Vision).
    public var alSacarTexto: ((CGImage) -> Void)?
    /// Graba en video la zona elegida (`Grabar/GrabadorPantalla`).
    public var alGrabar: ((ZonaDeGrabacion) -> Void)?
    /// Avisa de que se guardo una captura (por si la galeria esta abierta).
    public var alGuardar: ((URL) -> Void)?
    /// Copia la imagen (la pila de capturas). Sin el, se copia suelta.
    public var alCopiar: ((CGImage, CGFloat) -> Void)?
    /// La captura con scroll de la zona elegida (modo `S`).
    public var alScroll: ((ZonaDeGrabacion) -> Void)?
    /// Grabar la zona elegida en GIF (modo `G`).
    public var alGif: ((ZonaDeGrabacion) -> Void)?
    /// Pin en vivo de la zona elegida (modo `L`), en coordenadas globales
    /// de AppKit. Lo pone quien hace los pines en vivo.
    public var alPinEnVivo: ((CGRect) -> Void)?

    /// Donde se guardan las capturas: `capturas/` de los datos, la misma
    /// carpeta que la galeria de Windows (`galeria_capturas::carpeta_en`),
    /// que es la que viaja entre aparatos.
    public var carpetaDeCapturas: URL

    /// El modo que manda en todas las pantallas (`Z` `V` `P` `S` `G` `L` `T`).
    private(set) var modo: ModoCaptura = .zona
    /// La proporcion a la que se ata la zona (16:9, 4:3, 1:1 o libre).
    private(set) var proporcion: ProporcionCaptura = .libre
    /// Abrir con la pantalla entera elegida y el lapiz en la mano (el
    /// anotador de pantalla).
    private var paraAnotar = false
    /// Lo que se hace al elegir la zona (los comandos con atajo).
    private var intencion: IntencionCaptura = .normal
    private var paneles: [PanelCaptura] = []
    /// La vista de la pantalla donde esta el raton o donde se empezo.
    private weak var activa: VistaCaptura?
    private var abriendo = false
    /// Lo que hace Intro: copiar, o grabar si se abrio para grabar.
    private var intro: AccionCaptura = .copiar
    var accionIntro: AccionCaptura { intro }
    /// El formato del color de la lupa (el de los ajustes al abrir; ⇧
    /// sola lo cambia mientras dura la captura).
    private(set) var formatoColor: FormatoColorLupa = .hex
    /// Espacio: la pantalla en vivo (sin la foto congelada). Al volver, o
    /// al hacer algo con la zona, se hace otra foto.
    private(set) var enVivo = false
    private var refotografiando = false
    /// Abierta como cuentagotas (sin zona ni barras).
    var esCuentagotas: Bool { intencion == .cuentagotas }

    /// Donde viven los `.excalidraw` del anotador mientras dura la captura
    /// (se borra al cerrarla: lo anotado sale como imagen).
    private(set) var carpetaDeAnotar = Capturador.carpetaNuevaDeAnotar()

    private static func carpetaNuevaDeAnotar() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-anotar-\(UUID().uuidString)",
                                                                     isDirectory: true)
    }

    /// El de la app (el ultimo creado), para quien no lo tiene a mano: la
    /// entrada «Captura» de la hoja del clip del chat.
    public private(set) static weak var principal: Capturador?

    public init(carpetaDeCapturas: URL = carpetaDeDatos().appendingPathComponent("capturas", isDirectory: true)) {
        self.carpetaDeCapturas = carpetaDeCapturas
        Capturador.principal = self
    }

    /// Si la captura esta en pantalla.
    public var abierta: Bool { !paneles.isEmpty || abriendo }

    /// Empieza una captura: comprueba el permiso, hace la foto de cada
    /// pantalla y pone encima la superposicion. Si ya hay una, no hace nada.
    /// Con `paraGrabar`, Intro graba la zona en video en vez de copiarla.
    public func capturar(paraGrabar: Bool = false) {
        abrirCaptura(paraGrabar: paraGrabar, paraAnotar: false)
    }

    /// Abre la captura para algo concreto (un comando con atajo): con su
    /// modo ya puesto, o haciendolo en cuanto se elige la zona.
    public func capturar(_ intencion: IntencionCaptura) {
        guard !abierta else { return }
        abrirCaptura(paraGrabar: false, paraAnotar: false)
        guard abierta else { return }
        self.intencion = intencion
    }

    /// El anotador de pantalla: la captura con la pantalla del raton ya
    /// elegida y el lapiz cogido (Option + doble clic central).
    public func anotarPantalla() {
        abrirCaptura(paraGrabar: false, paraAnotar: true)
    }

    private func abrirCaptura(paraGrabar: Bool, paraAnotar: Bool) {
        guard !abierta else { return }
        guard PermisoCaptura.asegurar() else { return }
        intro = paraGrabar && alGrabar != nil ? .grabar : .copiar
        formatoColor = AjustesCaptura.actuales().formatoColor
        self.paraAnotar = paraAnotar
        abriendo = true
        Task { @MainActor in
            defer { self.abriendo = false }
            do {
                let fotos = try await Instantanea.fotografiarTodas()
                guard !fotos.isEmpty else { return }
                self.abrir(fotos)
            } catch {
                PermisoCaptura.avisarDenegado(detalle: "No se pudo capturar la pantalla: \(error.localizedDescription)")
            }
        }
    }

    /// Cierra la captura sin hacer nada y suelta las fotos.
    public func cerrar() {
        let lista = paneles
        paneles = []
        activa = nil
        modo = .zona
        proporcion = .libre
        intro = .copiar
        paraAnotar = false
        intencion = .normal
        enVivo = false
        refotografiando = false
        for panel in lista {
            vista(de: panel)?.soltar()
            panel.orderOut(nil)
            panel.close()
        }
        let carpeta = carpetaDeAnotar
        carpetaDeAnotar = Capturador.carpetaNuevaDeAnotar()
        if !lista.isEmpty {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: carpeta) }
        }
    }

    private func abrir(_ fotos: [FotoDePantalla]) {
        let ventanas = Instantanea.ventanasVisibles()
        switch intencion {
        case .texto: modo = alSacarTexto != nil ? .texto : .zona
        case .scroll: modo = alScroll != nil ? .scroll : .zona
        case .gif: modo = alGif != nil ? .gif : .zona
        case .enVivo: modo = alPinEnVivo != nil ? .pinEnVivo : .zona
        case .normal, .copiar, .pinear, .anotar, .cuentagotas: modo = .zona
        }
        paneles = fotos.map { PanelCaptura.abrir(foto: $0, ventanas: ventanas, capturador: self) }
        if esCuentagotas { for v in vistas { v.barraModos?.isHidden = true } }
        // La pantalla donde esta el raton es la que recibe el teclado.
        let raton = NSEvent.mouseLocation
        let principal = paneles.first { $0.frame.contains(raton) } ?? paneles.first
        for panel in paneles where panel !== principal { panel.orderFrontRegardless() }
        principal?.makeKeyAndOrderFront(nil)
        if let principal, let vista = vista(de: principal) {
            activa = vista
            vista.seguirRaton(a: vista.convert(principal.convertPoint(fromScreen: raton), from: nil))
            if paraAnotar {
                vista.elegirPantalla()
                vista.tomar(.lapiz)
                paraAnotar = false
            }
        }
    }

    private func vista(de panel: NSPanel) -> VistaCaptura? {
        panel.contentView?.subviews.first as? VistaCaptura
    }

    private var vistas: [VistaCaptura] { paneles.compactMap { vista(de: $0) } }

    // MARK: - Lo que avisan las vistas

    /// Si una accion tiene a alguien detras (si no, su boton sale apagado).
    func disponible(_ accion: AccionCaptura) -> Bool {
        switch accion {
        case .copiar, .guardar, .guardarComo, .cerrar: true
        case .pinear: alPinear != nil
        case .alChat: alMandarAlChat != nil
        case .texto: alSacarTexto != nil
        case .grabar: alGrabar != nil
        }
    }

    /// El raton entro en otra pantalla.
    func activar(_ vista: VistaCaptura) {
        activa = vista
    }

    /// Se empezo una zona en `vista`: las demas pantallas se vacian.
    func empezo(en vista: VistaCaptura) {
        activa = vista
        for otra in vistas where otra !== vista && otra.elegida { otra.reiniciar() }
    }

    /// El teclado, venga de la pantalla que venga. Devuelve si se uso.
    func tecla(_ e: NSEvent) -> Bool {
        guard let vista = activa ?? vistas.first else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let conMando = mods.contains(.command) || mods.contains(.control)
        let letra = (e.charactersIgnoringModifiers ?? "").lowercased()

        // El cuentagotas: solo el color (Intro o C) y salir.
        if esCuentagotas {
            switch e.keyCode {
            case 53: cerrar()
            case 36, 76: copiarColor(de: vista)
            default:
                guard !conMando, letra == "c" else { return false }
                copiarColor(de: vista)
            }
            return true
        }

        switch e.keyCode {
        case 53: // Esc
            cerrar()
            return true
        case 36, 76: // Intro y el Intro del teclado numerico
            if vista.elegida { accion(intro, en: vista) }
            return true
        case 49 where !conMando: // Espacio: en vivo o congelada
            alternarVivo()
            return true
        case 123...126 where !conMando: // flechas: mover la zona
            guard vista.elegida, !vista.anotada else { return vista.elegida }
            let paso: CGFloat = mods.contains(.shift) ? 10 : 1
            let (dx, dy): (CGFloat, CGFloat) = switch e.keyCode {
            case 123: (-paso, 0)
            case 124: (paso, 0)
            case 125: (0, -paso)
            default: (0, paso)
            }
            vista.desplazar(dx: dx, dy: dy)
            return true
        default:
            break
        }

        if conMando {
            // ⌘Z / ⇧⌘Z: deshacer y rehacer lo anotado.
            if letra == "z", vista.elegida {
                let hecho = mods.contains(.shift) ? vista.rehacer() : vista.deshacer()
                if !hecho { NSSound.beep() }
                return true
            }
            // ⌘A: la pantalla entera (la del raton), lista para confirmar.
            if letra == "a", !mods.contains(.shift) {
                guard !vista.anotada else { return true }
                empezo(en: vista)
                vista.elegirPantalla()
                return true
            }
            guard vista.elegida else { return false }
            let accion: AccionCaptura?
            switch letra {
            case "c": accion = .copiar
            case "p": accion = .pinear
            case "m": accion = .alChat
            case "t": accion = .texto
            case "s": accion = mods.contains(.shift) ? .guardarComo : .guardar
            case "g": accion = .grabar
            default: accion = nil
            }
            guard let accion else { return false }
            self.accion(accion, en: vista)
            return true
        }

        guard mods.isDisjoint(with: [.option, .shift]) else { return false }
        // 1-5: las herramientas de anotar (con zona elegida).
        if let h = HerramientaAnotar.deTecla(letra) {
            guard vista.elegida else { return false }
            vista.tomar(h)
            return true
        }
        // Con algo dibujado, la zona ya no cambia de modo (como Windows).
        if vista.anotada { return false }
        switch letra {
        case "z": cambiarModo(.zona, desde: vista)
        case "v": cambiarModo(.ventana, desde: vista)
        case "t": cambiarModo(.texto, desde: vista)
        case "p": cambiarModo(.pantalla, desde: vista)
        case "s": cambiarModo(.scroll, desde: vista)
        case "g": cambiarModo(.gif, desde: vista)
        case "l": cambiarModo(.pinEnVivo, desde: vista)
        case "r":
            if !vista.repetirUltima() { NSSound.beep() }
        case "c":
            // El color bajo la lupa, en el formato de la lupa; y se cierra,
            // como en Windows.
            guard !vista.elegida else { return false }
            copiarColor(de: vista)
        default:
            return false
        }
        return true
    }

    /// Copia el color bajo la lupa de `vista` (en su formato) y cierra.
    func copiarColor(de vista: VistaCaptura) {
        guard let c = vista.colorBajoRaton else { return NSSound.beep() }
        let texto = formatoColor.texto(c.0, c.1, c.2)
        cerrar()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    /// ⇧ sola: HEX ↔ RGB en la lupa de todas las pantallas.
    func cambiarFormatoColor() {
        formatoColor = formatoColor.siguiente
        for v in vistas { v.refrescarLupa() }
    }

    // MARK: - En vivo (Espacio)

    /// Espacio: quita la foto congelada para ver la pantalla en vivo; otra
    /// vez Espacio hace una foto nueva y vuelve a congelar.
    func alternarVivo() {
        guard !refotografiando else { return }
        if enVivo {
            refotografiar {}
        } else {
            enVivo = true
            for v in vistas { v.ponerVivo(true) }
        }
    }

    /// Una foto nueva de cada pantalla (sin la captura, que es de esta app)
    /// para las vistas, y luego `despues`. Si falla, sigue la de antes.
    private func refotografiar(_ despues: @escaping @MainActor () -> Void) {
        refotografiando = true
        Task { @MainActor in
            let fotos = (try? await Instantanea.fotografiarTodas()) ?? []
            guard self.refotografiando else { return }
            self.refotografiando = false
            for v in self.vistas {
                if let n = v.numeroDePantalla, let f = fotos.first(where: { $0.pantalla.numeroDePantalla == n }) {
                    v.cambiarFoto(f.imagen)
                }
                v.ponerVivo(false)
            }
            self.enVivo = false
            despues()
        }
    }

    /// Lo que necesita la foto (hacer algo con la zona, anotar): en vivo,
    /// primero se congela con una foto nueva.
    func conFotoCongelada(_ hacer: @escaping @MainActor () -> Void) {
        if enVivo { refotografiar(hacer) } else if !refotografiando { hacer() }
    }

    /// Si un modo tiene a alguien detras (si no, suena y no se cambia).
    func modoDisponible(_ m: ModoCaptura) -> Bool {
        switch m {
        case .zona, .ventana, .pantalla: true
        case .texto: alSacarTexto != nil
        case .scroll: alScroll != nil
        case .gif: alGif != nil
        case .pinEnVivo: alPinEnVivo != nil
        }
    }

    /// Cambia de modo en todas las pantallas. `P` elige ya la pantalla.
    func cambiarModo(_ nuevo: ModoCaptura, desde vista: VistaCaptura) {
        guard modoDisponible(nuevo) else {
            NSSound.beep()
            for v in vistas { v.actualizarBarraModos() }
            return
        }
        modo = nuevo
        for v in vistas where v.elegida { v.reiniciar() }
        for v in vistas { v.actualizarBarraModos() }
        if nuevo == .pantalla { vista.elegirPantalla() }
    }

    /// Cambia la proporcion; la zona ya elegida se ajusta en el sitio.
    func cambiarProporcion(_ p: ProporcionCaptura, desde vista: VistaCaptura) {
        proporcion = p
        for v in vistas { v.actualizarBarraModos() }
        vista.aplicarProporcion(p)
    }

    /// Se acaba de elegir una zona en `vista`: los modos que actuan al
    /// elegir (texto, scroll, GIF, pin en vivo) lo hacen ya.
    func alElegir(en vista: VistaCaptura) {
        vista.actualizarBarraModos()
        // Los comandos que hacen algo en cuanto se elige.
        switch intencion {
        case .copiar where !modo.actuaAlElegir:
            return accion(.copiar, en: vista)
        case .pinear where !modo.actuaAlElegir && alPinear != nil:
            return accion(.pinear, en: vista)
        case .anotar where !modo.actuaAlElegir:
            vista.tomar(.lapiz)
            return
        default:
            break
        }
        guard modo.actuaAlElegir, !paraAnotar else { return }
        switch modo {
        case .texto:
            accion(.texto, en: vista)
        case .scroll, .gif:
            guard let zona = vista.zonaDeGrabacion() else { return }
            recordar(vista)
            let gancho = modo == .scroll ? alScroll : alGif
            cerrar()
            gancho?(zona)
        case .pinEnVivo:
            guard let r = vista.zonaGlobal() else { return }
            recordar(vista)
            cerrar()
            alPinEnVivo?(r)
        case .zona, .ventana, .pantalla:
            break
        }
    }

    /// La zona elegida queda como «la ultima» de su pantalla (`R`).
    private func recordar(_ vista: VistaCaptura) {
        guard vista.elegida, let n = vista.numeroDePantalla else { return }
        UltimaZona().guardar(vista.seleccion, pantalla: n)
    }

    /// Hace `accion` con la zona elegida en `vista` y cierra la captura.
    func accion(_ accion: AccionCaptura, en vista: VistaCaptura) {
        if accion == .cerrar {
            cerrar()
            return
        }
        guard disponible(accion) else {
            NSSound.beep()
            return
        }
        if enVivo || refotografiando {
            conFotoCongelada { [weak self, weak vista] in
                guard let self, let vista else { return }
                self.accion(accion, en: vista)
            }
            return
        }
        recordar(vista)
        if accion == .grabar {
            guard let zona = vista.zonaDeGrabacion() else { return }
            cerrar()
            alGrabar?(zona)
            return
        }
        guard let recorte = vista.recorte() else { return }
        let escala = vista.escalaFoto
        // Anotado, el recorte ya es un mapa de bits aparte: no se vuelve a
        // copiar (se hace como si fuera la foto entera).
        let entera = vista.anotada ? CGSize(width: recorte.width, height: recorte.height) : vista.tamFoto
        cerrar()

        switch accion {
        case .copiar:
            if let alCopiar { alCopiar(recorte, escala) } else { Capturador.copiar(recorte, escala: escala) }
        case .guardar:
            guardar(recorte, escala: escala)
        case .guardarComo:
            guardarComo(recorte, escala: escala)
        case .pinear:
            alPinear?(Capturador.suelto(recorte, entera: entera))
        case .alChat:
            alMandarAlChat?(Capturador.suelto(recorte, entera: entera))
        case .texto:
            alSacarTexto?(Capturador.suelto(recorte, entera: entera))
        case .grabar, .cerrar:
            break
        }
    }

    // MARK: - Copiar y guardar

    /// Al portapapeles como PNG y TIFF (los dos que piden las apps de Mac).
    /// Se codifica fuera del hilo principal; el recorte retiene la foto
    /// solo hasta entonces.
    public static func copiar(_ imagen: CGImage, escala: CGFloat) {
        Task.detached(priority: .userInitiated) {
            let png = Capturador.codificar(imagen, tipo: .png, escala: escala)
            let tiff = Capturador.codificar(imagen, tipo: .tiff, escala: escala)
            await MainActor.run {
                let tablero = NSPasteboard.general
                var tipos: [NSPasteboard.PasteboardType] = []
                if png != nil { tipos.append(.png) }
                if tiff != nil { tipos.append(.tiff) }
                guard !tipos.isEmpty else { return NSSound.beep() }
                _ = tablero.declareTypes(tipos, owner: nil)
                if let png { _ = tablero.setData(png, forType: .png) }
                if let tiff { _ = tablero.setData(tiff, forType: .tiff) }
            }
        }
    }

    /// Guarda un PNG en `carpetaDeCapturas` con el nombre de la hora.
    private func guardar(_ imagen: CGImage, escala: CGFloat) {
        let carpeta = carpetaDeCapturas
        let fecha = Date()
        Task.detached(priority: .utility) { [weak self] in
            var ruta: URL?
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                let destino = GeometriaCaptura.rutaNueva(en: carpeta, fecha: fecha)
                guard let datos = Capturador.codificar(imagen, tipo: .png, escala: escala) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try datos.write(to: destino, options: .atomic)
                ruta = destino
            } catch {
                ruta = nil
            }
            let guardada = ruta
            await MainActor.run { [weak self] in
                if let guardada { self?.alGuardar?(guardada) } else { NSSound.beep() }
            }
        }
    }

    /// ⇧⌘S: el panel de guardar del Mac, con el nombre de la hora y la
    /// carpeta de capturas de entrada. La captura ya esta cerrada.
    private func guardarComo(_ imagen: CGImage, escala: CGFloat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = GeometriaCaptura.rutaNueva(en: carpetaDeCapturas, fecha: Date()).lastPathComponent
        try? FileManager.default.createDirectory(at: carpetaDeCapturas, withIntermediateDirectories: true)
        panel.directoryURL = carpetaDeCapturas
        panel.level = .modalPanel
        NSApp.activate()
        guard panel.runModal() == .OK, let destino = panel.url else { return }
        let carpeta = carpetaDeCapturas
        Task.detached(priority: .utility) { [weak self] in
            let bien: Bool
            if let datos = Capturador.codificar(imagen, tipo: .png, escala: escala) {
                bien = (try? datos.write(to: destino, options: .atomic)) != nil
            } else {
                bien = false
            }
            await MainActor.run { [weak self] in
                guard bien else { return NSSound.beep() }
                // Si quedo en la carpeta de capturas, la galeria la ve.
                if destino.deletingLastPathComponent().standardizedFileURL == carpeta.standardizedFileURL {
                    self?.alGuardar?(destino)
                }
            }
        }
    }

    /// PNG o TIFF con ImageIO, con los PPP de la pantalla (72 x escala) para
    /// que al pegarla salga a su tamano en puntos y no al doble.
    nonisolated static func codificar(_ imagen: CGImage, tipo: UTType, escala: CGFloat) -> Data? {
        let datos = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(datos as CFMutableData, tipo.identifier as CFString, 1, nil) else {
            return nil
        }
        let ppp = 72 * max(escala, 1)
        let propiedades: [CFString: Any] = [kCGImagePropertyDPIWidth: ppp, kCGImagePropertyDPIHeight: ppp]
        CGImageDestinationAddImage(destino, imagen, propiedades as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return datos as Data
    }

    /// El recorte listo para vivir mas que la captura: si es pequeno frente
    /// a la foto entera, se copian solo sus pixeles (y la foto se puede
    /// soltar); si es casi toda, se queda compartido (sin copiar nada).
    static func suelto(_ recorte: CGImage, entera: CGSize) -> CGImage {
        let tam = CGSize(width: recorte.width, height: recorte.height)
        guard GeometriaCaptura.convieneCopiarAparte(recorte: tam, entera: entera) else { return recorte }
        let espacio = recorte.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let lienzo = CGContext(data: nil, width: recorte.width, height: recorte.height, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: espacio, bitmapInfo: info) else { return recorte }
        lienzo.interpolationQuality = .none
        lienzo.draw(recorte, in: CGRect(origin: .zero, size: tam))
        return lienzo.makeImage() ?? recorte
    }
}
