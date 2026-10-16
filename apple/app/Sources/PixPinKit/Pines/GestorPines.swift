// El gestor de pines: los crea y los tiene vivos mientras estan abiertos.
// Es la API que usan los demas (la captura, el menu de la barra):
//
//     GestorPines.compartido.pinear(imagen: captura, marco: zonaCapturada)
//     GestorPines.compartido.pinear(fichero: url)
//     GestorPines.compartido.pinearDesdePortapapeles()
//     GestorPines.compartido.pinearEnVivo(zona: zona, pantalla: pantalla)
//     GestorPines.compartido.pinearNota()
//     GestorPines.compartido.pinearMiniapp("tareas")
//     GestorPines.compartido.alternarTodos()          // ⌃2
//     GestorPines.compartido.mostrarPanelAbiertos()
//     GestorPines.compartido.restaurarUltimoCerrado()
//     GestorPines.compartido.alternarPasoDeClics()     // ⌘T de vuelta
//
// **Se guardan y vuelven al arrancar** como en Windows (`AlmacenPines`, el
// mismo `almacen/indice.json`): cada pin nuevo deja su entrada y lo que se
// mueve, gira o filtra se apunta (juntado: una rafaga de flechas es una
// sola escritura). Cerrar lo marca cerrado sin borrar nada, y «Restaurar el
// ultimo cerrado» lo devuelve a su sitio. El pin en vivo no se guarda.
//
// Rendimiento (§4bis del plan): las fotos se leen con ImageIO ya reducidas
// al tamano de la pantalla y fuera del hilo principal; el aviso de memoria
// solo se escucha mientras hay algun pin abierto.

import AppKit
import AVFoundation
import Carbon.HIToolbox
import PDFKit
import PixPinCore
import UniformTypeIdentifiers

@MainActor
public final class GestorPines {
    public static let compartido = GestorPines()

    private var pines: [Pin] = []
    private var vigiaMemoria: DispatchSourceMemoryPressure?
    private var siguienteId = 1
    private let panelAbiertos = PanelPinesAbiertos()
    /// Los que aparto «Cerrar todos», por si se deshace.
    private var apartados: [Pin] = []
    private var olvidarApartados: Task<Void, Never>?
    private var atajoOcultar: AtajoGlobal?

    /// El nucleo de la carpeta de datos: donde viven las mini-apps (en
    /// «Mensajes guardados») y adonde va una nota. Lo pone la app al
    /// arrancar; sin el, las herramientas viven solo en memoria.
    ///
    /// Al ponerlo se abre el almacen de pines de esa carpeta y vuelven los
    /// que estaban abiertos (en la siguiente vuelta del bucle: la app aun
    /// esta arrancando).
    public var nucleo: Nucleo? {
        didSet {
            guard let nucleo, almacen == nil else { return }
            abrirAlmacen(en: URL(fileURLWithPath: nucleo.raiz(), isDirectory: true))
            DispatchQueue.main.async { [weak self] in self?.restaurar() }
        }
    }

    /// Los pines guardados (nil sin carpeta de datos: viven en memoria).
    private var almacen: AlmacenPines?
    /// Los cerrados, con su sitio, para «Restaurar el ultimo cerrado» (el
    /// ultimo, el primero en volver).
    private var reabrir: [(id: UInt64, guardado: PinGuardado)] = []
    /// Lo que «Cerrar todos» marco cerrado, por si se deshace.
    private var guardadosApartados: [Int: PinGuardado] = [:]
    /// Pines con cambios por apuntar (sitio, como) y por reescribir (lo de
    /// dentro), y el temporizador que los junta.
    private var porGuardar: [Int: Pin] = [:]
    private var porReescribir: [Int: Pin] = [:]
    private var tareaGuardar: Task<Void, Never>?

    init() {
        let m = panelAbiertos.modelo
        m.alTraer = { [weak self] id in self?.pin(id)?.resaltar() }
        m.alAlternar = { [weak self] id in
            guard let pin = self?.pin(id) else { return }
            pin.ocultar(!pin.oculto)
        }
        m.alCerrar = { [weak self] id in self?.pin(id)?.cerrar() }
        m.alMostrarTodos = { [weak self] in self?.ocultarTodos(false) }
        m.alOcultarTodos = { [weak self] in self?.ocultarTodos(true) }
        m.alCerrarTodos = { [weak self] in self?.cerrarTodosConDeshacer() }
        m.alDeshacer = { [weak self] in self?.deshacerCerrarTodos() }
        // Al salir, lo pendiente se escribe ya (los pines abiertos se quedan
        // abiertos en el almacen: vuelven al arrancar).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { GestorPines.compartido.guardarPendientes() }
        }
    }

    /// Cuantos pines hay abiertos.
    public var cuantos: Int { pines.count }

    // MARK: Pin en vivo

    /// **Pin en vivo**: la zona `zona` (coordenadas de pantalla de AppKit,
    /// globales) de `pantalla`, vista en directo. Nace al lado de su zona,
    /// a su tamano.
    public func pinearEnVivo(zona: CGRect, pantalla: NSScreen) {
        let zona = zona.standardized.integral
        guard zona.width >= 8, zona.height >= 8, PermisoCaptura.asegurar(),
              let viva = ZonaViva(zona: zona, pantalla: pantalla) else {
            NSSound.beep()
            return
        }
        abrir(.vivo(viva), marco: ReglasVivo.sitioJuntoA(zona, trabajo: pantalla.visibleFrame))
    }

    // MARK: Herramientas

    /// Una nota suelta en Markdown.
    public func pinearNota(texto: String = "") {
        let pantalla = Self.pantallaDelRaton()
        let visible = pantalla?.visibleFrame ?? CGRect(origin: .zero, size: Self.pantallaSupuesta)
        let marco = ReglasPin.marcoInicial(tamano: CGSize(width: 300, height: 260),
                                           centro: NSEvent.mouseLocation, visible: visible)
        abrir(.herramienta(HerramientaPin(.nota(ModeloNota(texto: texto)))), marco: marco,
              almacen: .nota(texto, origen: "nota"))
    }

    /// Una mini-app nueva (`tareas`, `contador`, `ruleta`, `gastos`,
    /// `cronometro`, `temporizador`, `alarma`): se
    /// crea en «Mensajes guardados» (asi se guarda y viaja al movil) y se
    /// pinea. Sin nucleo, vive solo en memoria.
    public func pinearMiniapp(_ miniapp: String, titulo: String = "") {
        let moneda = monedaDelAparato()
        guard let documento = miniDocumentoNuevo(miniapp: miniapp, titulo: titulo, moneda: moneda) else {
            NSSound.beep()
            return
        }
        guard let nucleo else {
            abrirMiniapp(DocumentoMini(miniapp: miniapp, documento: documento, nucleo: nil, chat: nil, mensaje: nil))
            return
        }
        Task { [weak self] in
            let creado = await Task.detached(priority: .userInitiated) { () -> (String, MensajeChat)? in
                guard let chat = try? nucleo.chatGuardados(),
                      let m = try? nucleo.crearMiniapp(chat: chat.id, miniapp: miniapp, titulo: titulo, moneda: moneda)
                else { return nil }
                return (chat.id, m)
            }.value
            guard let self else { return }
            guard let creado else {
                NSSound.beep()
                return
            }
            let (chat, m) = creado
            self.abrirMiniapp(DocumentoMini(miniapp: miniapp, documento: m.texto, nucleo: nucleo,
                                            chat: chat, mensaje: m.id))
        }
    }

    /// Saca a la pantalla una mini-app que ya esta en un chat (su mensaje
    /// `MINIAPP`): lo que se toque en el pin se guarda en ese mensaje.
    public func pinearMiniapp(chat: String, mensaje: String, miniapp: String, documento: String) {
        abrirMiniapp(DocumentoMini(miniapp: miniapp, documento: documento, nucleo: nucleo,
                                   chat: chat, mensaje: mensaje))
    }

    private func abrirMiniapp(_ doc: DocumentoMini) {
        let pantalla = Self.pantallaDelRaton()
        let visible = pantalla?.visibleFrame ?? CGRect(origin: .zero, size: Self.pantallaSupuesta)
        let tam = doc.miniapp == "ruleta" ? CGSize(width: 300, height: 420) : CGSize(width: 300, height: 340)
        abrir(.herramienta(HerramientaPin(.mini(doc))),
              marco: ReglasPin.marcoInicial(tamano: tam, centro: NSEvent.mouseLocation, visible: visible),
              almacen: .nota(doc.documento, origen: AlmacenPines.origenMini(doc.miniapp, chat: doc.chat,
                                                                           mensaje: doc.mensaje)))
    }

    // MARK: Todos

    /// Muestra u oculta todos los pines (⌃2): si hay alguno a la vista, los
    /// oculta; si no, los ensena.
    public func alternarTodos() {
        ocultarTodos(pines.contains { !$0.oculto })
    }

    public func ocultarTodos(_ ocultar: Bool) {
        olvidarApartadosYa()
        for pin in pines { pin.ocultar(ocultar) }
    }

    /// El panel «Pines abiertos».
    public func mostrarPanelAbiertos() {
        refrescarPanel()
        panelAbiertos.mostrar()
    }

    /// Registra ⌃2 en todo el Mac (como el Ctrl 2 de Windows). Si otra app
    /// ya lo tiene, se queda solo en el menu.
    public func activarAtajoOcultar() {
        guard atajoOcultar == nil else { return }
        let combinacion = AtajoGlobal.Combinacion(tecla: UInt32(kVK_ANSI_2), modificadores: UInt32(controlKey))
        atajoOcultar = AtajoGlobal(combinacion) { GestorPines.compartido.alternarTodos() }
    }

    /// Cierra todos de forma que se puede deshacer: se apartan (ocultos, sin
    /// soltar nada) y se cierran de verdad a los 30 s o al hacer otra cosa.
    public func cerrarTodosConDeshacer() {
        olvidarApartadosYa()
        apartados = pines
        guardarPendientes()
        for pin in apartados {
            pin.apartar()
            // Cerrado ya en el almacen (y para «Restaurar el ultimo»): si se
            // sale ahora de PixPin, no vuelven.
            if let g = marcarCerrado(pin) { guardadosApartados[pin.id] = g }
        }
        pines = []
        refrescarPanel()
        olvidarApartados = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.olvidarApartadosYa()
        }
    }

    public func deshacerCerrarTodos() {
        olvidarApartados?.cancel()
        olvidarApartados = nil
        let vuelven = apartados.filter { !$0.estaCerrado }
        apartados = []
        pines += vuelven
        for pin in vuelven {
            pin.ocultar(false)
            if let id = pin.idAlmacen, let g = guardadosApartados[pin.id] {
                try? almacen?.actualizarPin(id, g)
                reabrir.removeAll { $0.id == id }
            }
        }
        guardadosApartados = [:]
        refrescarPanel()
    }

    private func olvidarApartadosYa() {
        olvidarApartados?.cancel()
        olvidarApartados = nil
        let lista = apartados
        apartados = []
        guardadosApartados = [:]
        for pin in lista { pin.cerrar() }
        if !lista.isEmpty { refrescarPanel() }
    }

    /// Los marcos de los pines a la vista menos `pin` (para las guias).
    func marcosVisibles(salvo pin: Pin) -> [CGRect] {
        pines.filter { $0 !== pin && !$0.oculto }.map(\.panel.frame)
    }

    private func pin(_ id: Int) -> Pin? {
        pines.first { $0.id == id }
    }

    private func refrescarPanel() {
        let m = panelAbiertos.modelo
        m.filas = pines.map(\.fila)
        m.puedeDeshacer = !apartados.isEmpty
    }

    /// Pinea una imagen ya en memoria (una captura). Con `marco` (en
    /// coordenadas de pantalla) nace justo ahi, encima de lo capturado; sin
    /// el, a su tamano natural junto al raton. Si es mayor que la pantalla se
    /// guarda reducida.
    public func pinear(imagen: CGImage, marco: CGRect? = nil) {
        let pantalla = Self.pantallaDelRaton()
        let lado = ReglasPin.ladoMiniatura(pantalla: pantalla?.frame.size ?? Self.pantallaSupuesta,
                                           escala: pantalla?.backingScaleFactor ?? 2)
        let reducida = Miniatura.reducir(imagen, ladoMaximo: lado)
        // Al almacen va la captura entera, no la reducida.
        if let marco, marco.width >= 1, marco.height >= 1 {
            abrir(.imagen(reducida, fichero: nil), marco: marco, almacen: .captura(imagen, origen: "recorte"))
        } else {
            abrirImagen(reducida, pixelesNaturales: CGSize(width: imagen.width, height: imagen.height),
                        fichero: nil, pantalla: pantalla, almacen: .captura(imagen, origen: "recorte"))
        }
    }

    /// Pinea un fichero: foto (ImageIO, reducida), PDF (PDFKit) o video y
    /// audio (AVKit). `false` si no es de ningun tipo que se pueda pinear;
    /// si la foto no se puede leer, suena un aviso al terminar de intentarlo.
    @discardableResult
    public func pinear(fichero url: URL) -> Bool {
        guard let tipo = TipoContenido.de(url) else { return false }
        let pantalla = Self.pantallaDelRaton()
        let visible = pantalla?.visibleFrame ?? CGRect(origin: .zero, size: Self.pantallaSupuesta)
        switch tipo {
        case .imagen:
            let lado = ReglasPin.ladoMiniatura(pantalla: pantalla?.frame.size ?? Self.pantallaSupuesta,
                                               escala: pantalla?.backingScaleFactor ?? 2)
            Task { [weak self] in
                let imagen = await Miniatura.fueraDelPrincipal { Miniatura.de(url: url, ladoMaximo: lado) }
                guard let self else { return }
                guard let imagen else {
                    NSSound.beep()
                    return
                }
                self.abrirImagen(imagen, pixelesNaturales: nil, fichero: url, pantalla: pantalla, almacen: .foto(url))
            }

        case .pdf:
            // PDFDocument lee las paginas segun se ven, no el fichero entero.
            guard let documento = PDFDocument(url: url) else { return false }
            var tamano = CGSize(width: 612, height: 792)
            if let pagina = documento.page(at: 0) {
                let caja = pagina.bounds(for: .cropBox).size
                let girada = pagina.rotation % 180 != 0
                tamano = girada ? CGSize(width: caja.height, height: caja.width) : caja
            }
            let tam = ReglasPin.tamanoInicial(pixeles: tamano, escala: 1, visible: visible.size)
            abrir(.pdf(documento, fichero: url),
                  marco: ReglasPin.marcoInicial(tamano: tam, centro: NSEvent.mouseLocation, visible: visible),
                  almacen: .archivo(url))

        case .video, .audio:
            // AVPlayer decodifica por hardware (VideoToolbox).
            let reproductor = AVPlayer(url: url)
            let audio = tipo == .audio
            let tam = audio ? CGSize(width: 360, height: 66) : CGSize(width: 480, height: 270)
            abrir(.video(reproductor, fichero: url, soloAudio: audio),
                  marco: ReglasPin.marcoInicial(tamano: tam, centro: NSEvent.mouseLocation, visible: visible),
                  almacen: .archivo(url))
        }
        return true
    }

    /// Pinea lo que haya en el portapapeles: ficheros copiados en el Finder
    /// (hasta 10) o una imagen. `false` si no habia nada que pinear.
    @discardableResult
    public func pinearDesdePortapapeles() -> Bool {
        let portapapeles = NSPasteboard.general
        if let urls = portapapeles.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            var alguno = false
            for url in urls.prefix(10) {
                if pinear(fichero: url) { alguno = true }
            }
            if alguno { return true }
        }
        let tipos: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(UTType.heic.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        ]
        guard let tipo = portapapeles.availableType(from: tipos),
              let datos = portapapeles.data(forType: tipo) else { return false }
        let pantalla = Self.pantallaDelRaton()
        let lado = ReglasPin.ladoMiniatura(pantalla: pantalla?.frame.size ?? Self.pantallaSupuesta,
                                           escala: pantalla?.backingScaleFactor ?? 2)
        Task { [weak self] in
            let imagen = await Miniatura.fueraDelPrincipal { Miniatura.de(datos: datos, ladoMaximo: lado) }
            guard let self else { return }
            guard let imagen else {
                NSSound.beep()
                return
            }
            self.abrirImagen(imagen, pixelesNaturales: nil, fichero: nil, pantalla: pantalla,
                             almacen: .captura(imagen, origen: "portapapeles"))
        }
        return true
    }

    /// Cierra todos los pines (sin deshacer).
    public func cerrarTodos() {
        olvidarApartadosYa()
        for pin in pines { pin.cerrar() }
    }

    // MARK: Por dentro

    private static let pantallaSupuesta = CGSize(width: 1440, height: 900)

    /// La pantalla donde esta el raton (alli nace el pin).
    private static func pantallaDelRaton() -> NSScreen? {
        let raton = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(raton, $0.frame, false) } ?? NSScreen.main
    }

    private func abrirImagen(_ imagen: CGImage, pixelesNaturales: CGSize?, fichero: URL?, pantalla: NSScreen?,
                             almacen: ParaAlmacen) {
        let visible = pantalla?.visibleFrame ?? CGRect(origin: .zero, size: Self.pantallaSupuesta)
        let pixeles = pixelesNaturales ?? CGSize(width: imagen.width, height: imagen.height)
        let tam = ReglasPin.tamanoInicial(pixeles: pixeles, escala: pantalla?.backingScaleFactor ?? 2,
                                          visible: visible.size)
        abrir(.imagen(imagen, fichero: fichero),
              marco: ReglasPin.marcoInicial(tamano: tam, centro: NSEvent.mouseLocation, visible: visible),
              almacen: almacen)
    }

    @discardableResult
    private func abrir(_ contenido: ContenidoPin, marco: CGRect, almacen para: ParaAlmacen = .nada,
                       guardado: PinGuardado? = nil) -> Pin {
        let pin = Pin(id: siguienteId, contenido: contenido, marco: marco)
        siguienteId += 1
        pin.alCerrar = { [weak self] cerrado in self?.quitar(cerrado) }
        pin.alCambiar = { [weak self] in self?.refrescarPanel() }
        pines.append(pin)
        vigilarMemoria()
        // Uno que vuelve trae su vista (giro, filtros...) y su marco.
        if let guardado {
            pin.restaurado = true
            pin.aplicar(guardado)
        }
        pin.mostrar()
        registrar(pin, para)
        pin.alGuardar = { [weak self] p in self?.programarGuardar(p) }
        pin.alCambiarContenido = { [weak self] p in self?.programarReescribir(p) }
        refrescarPanel()
        return pin
    }

    private func quitar(_ pin: Pin) {
        porGuardar[pin.id] = nil
        if let p = porReescribir.removeValue(forKey: pin.id) { reescribir(p) }
        if !apartados.contains(where: { $0 === pin }) { marcarCerrado(pin) }
        pines.removeAll { $0 === pin }
        apartados.removeAll { $0 === pin }
        refrescarPanel()
        if pines.isEmpty, apartados.isEmpty {
            vigiaMemoria?.cancel()
            vigiaMemoria = nil
        }
    }

    /// Con presion de memoria, cada pin suelta lo que puede rehacer.
    private func vigilarMemoria() {
        guard vigiaMemoria == nil else { return }
        let fuente = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        fuente.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.pines.forEach { $0.aligerar() }
            }
        }
        fuente.resume()
        vigiaMemoria = fuente
    }
}

// MARK: - El almacen: guardar y restaurar

extension GestorPines {
    /// Como va al almacen un pin nuevo.
    enum ParaAlmacen {
        /// Una captura: un PNG propio («recorte» o «portapapeles»).
        case captura(CGImage, origen: String)
        /// Una foto abierta: se copia tal cual.
        case foto(URL)
        /// Una nota o una mini-app (`origen` `mini:…`).
        case nota(String, origen: String)
        /// Un PDF o un video: por referencia.
        case archivo(URL)
        /// Ya tiene entrada (vuelve del almacen).
        case entrada(UInt64)
        /// No se guarda (el pin en vivo).
        case nada
    }

    /// El `maxY` de la pantalla principal: el «arriba» del almacen.
    private var techo: CGFloat { NSScreen.screens.first?.frame.maxY ?? 900 }

    func abrirAlmacen(en raiz: URL) {
        almacen = try? AlmacenPines(raiz: raiz)
    }

    /// Le da su entrada al pin nuevo.
    fileprivate func registrar(_ pin: Pin, _ para: ParaAlmacen) {
        if case let .entrada(id) = para {
            pin.idAlmacen = id
            return
        }
        guard let almacen else { return }
        switch para {
        case let .captura(imagen, origen):
            // El PNG se hace fuera del hilo principal; si el pin se cierra
            // entretanto, queda guardado y cerrado.
            Task { [weak self] in
                let png = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                    DispatchQueue.global(qos: .utility).async { c.resume(returning: AlmacenPines.png(imagen)) }
                }
                guard let self, let png else { return }
                let abierto = pin.estaCerrado ? nil : pin.guardado(techo: self.techo)
                pin.idAlmacen = try? almacen.guardarImagen(png: png, origen: origen, pin: abierto)
                if !pin.estaCerrado { self.programarGuardar(pin) }
            }
        case let .foto(url):
            pin.idAlmacen = try? almacen.guardarImagen(deFichero: url, origen: AlmacenPines.origenFoto,
                                                       pin: pin.guardado(techo: techo))
        case let .nota(texto, origen):
            pin.idAlmacen = try? almacen.guardarNota(texto, origen: origen, pin: pin.guardado(techo: techo))
        case let .archivo(url):
            pin.idAlmacen = try? almacen.guardarArchivo(url, pin: pin.guardado(techo: techo))
        case .entrada, .nada:
            break
        }
    }

    /// Lo marca cerrado en el almacen y lo apunta para «Restaurar el ultimo
    /// cerrado». Devuelve donde estaba.
    @discardableResult
    fileprivate func marcarCerrado(_ pin: Pin) -> PinGuardado? {
        guard let almacen, let id = pin.idAlmacen, let g = almacen.entrada(id)?.pin else { return nil }
        reabrir.append((id, g))
        if reabrir.count > 50 { reabrir.removeFirst(reabrir.count - 50) }
        try? almacen.actualizarPin(id, nil)
        return g
    }

    /// Junta los cambios de medio segundo en una escritura.
    fileprivate func programarGuardar(_ pin: Pin) {
        porGuardar[pin.id] = pin
        programarEscritura()
    }

    fileprivate func programarReescribir(_ pin: Pin) {
        porReescribir[pin.id] = pin
        programarEscritura()
    }

    private func programarEscritura() {
        guard tareaGuardar == nil else { return }
        tareaGuardar = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.guardarPendientes()
        }
    }

    /// Escribe ya lo pendiente (tambien al salir de PixPin).
    func guardarPendientes() {
        tareaGuardar?.cancel()
        tareaGuardar = nil
        let guardar = porGuardar.values
        let reescribir = porReescribir.values
        porGuardar = [:]
        porReescribir = [:]
        guard let almacen else { return }
        for pin in guardar where !pin.estaCerrado && !apartados.contains(where: { $0 === pin }) {
            guard let id = pin.idAlmacen else { continue }
            try? almacen.actualizarPin(id, pin.guardado(techo: techo))
            _ = try? almacen.ponerGrupo(id, color: pin.grupo.flatMap(ColorGrupo.porIndice))
        }
        for pin in reescribir { self.reescribir(pin) }
    }

    /// Lo de dentro al almacen: el texto de la nota o mini-app, o la foto
    /// recien anotada.
    fileprivate func reescribir(_ pin: Pin) {
        guard let almacen, let id = pin.idAlmacen else { return }
        if let texto = pin.textoHerramienta {
            try? almacen.reescribirNota(id, texto: texto)
        } else if let foto = pin.imagenOriginal, let png = AlmacenPines.png(foto) {
            try? almacen.reemplazarImagen(id, png: png)
        }
    }

    /// Devuelve a la pantalla lo que el almacen da por abierto y no esta ya
    /// (al arrancar). Lo que no se puede leer se queda en el almacen.
    public func restaurar() {
        guard let almacen else { return }
        let yaAbiertos = Set(pines.compactMap(\.idAlmacen))
        for e in almacen.abiertas where !yaAbiertos.contains(e.id) {
            restaurar(e)
        }
    }

    /// Devuelve el ultimo pin cerrado a donde estaba. `false` si no queda
    /// ninguno.
    @discardableResult
    public func restaurarUltimoCerrado() -> Bool {
        guard let almacen else { return false }
        while let (id, g) = reabrir.popLast() {
            // Si ya se borro, o ya volvio, el siguiente.
            guard let e = almacen.entrada(id), e.pin == nil else { continue }
            try? almacen.actualizarPin(id, g)
            guard let vuelta = almacen.entrada(id) else { continue }
            restaurar(vuelta)
            return true
        }
        return false
    }

    /// Que todos los pines dejen pasar el clic, o que lo recojan: es la
    /// vuelta de ⌘T (un pin pasante no recibe su clic derecho). Manda la
    /// mayoria, como en Windows. Devuelve si quedaron pasantes y cuantos
    /// cambiaron.
    @discardableResult
    public func alternarPasoDeClics() -> (pasantes: Bool, cambiados: Int) {
        let pasantes = pines.filter(\.pasante).count
        let hacia = pasantes * 2 <= pines.count
        var cambiados = 0
        for pin in pines where pin.pasante != hacia {
            pin.ponerPasante(hacia)
            cambiados += 1
        }
        return (hacia, cambiados)
    }

    /// Cuantos pines dejan pasar el clic (para el menu).
    public var cuantosPasantes: Int { pines.filter(\.pasante).count }

    /// Un pin del almacen, a su sitio. Si su pantalla ya no esta, entra en
    /// la principal.
    private func restaurar(_ e: EntradaAlmacen) {
        guard let almacen, let g = e.pin else { return }
        let pantallas = NSScreen.screens.map { (marco: $0.frame, visible: $0.visibleFrame) }
        var marco = ReglasAlmacen.deAlmacen(g, techo: techo)
        if let area = ReglasAlmacen.areaDeVuelta(marco, pantallas: pantallas) {
            marco = ReglasAlmacen.recolocar(marco, en: area)
        }
        let grupo = almacen.colorDe(e.id)?.indice
        let poner: (ContenidoPin) -> Void = { [weak self] contenido in
            guard let self else { return }
            let pin = self.abrir(contenido, marco: marco, almacen: .entrada(e.id), guardado: g)
            if let grupo { pin.grupo = grupo }
        }
        switch e.tipo {
        case .imagen:
            let url = almacen.rutaObjeto(e)
            leerFoto(url) { imagen in
                poner(.imagen(imagen, fichero: e.origen == AlmacenPines.origenFoto ? url : nil))
            }
        case .nota:
            guard let texto = try? String(contentsOf: almacen.rutaObjeto(e), encoding: .utf8) else { return }
            guard let mini = AlmacenPines.miniDeOrigen(e.origen) else {
                poner(.herramienta(HerramientaPin(.nota(ModeloNota(texto: texto)))))
                return
            }
            // Una mini-app del chat vuelve con lo que diga el chat ahora (pudo
            // cambiar en otro aparato); si no, con lo guardado.
            if let chat = mini.chat, let mensaje = mini.mensaje, let nucleo {
                let actual = (try? nucleo.documentoMiniapp(chat: chat, mensaje: mensaje)) ?? texto
                poner(.herramienta(HerramientaPin(.mini(DocumentoMini(miniapp: mini.cual, documento: actual,
                                                                      nucleo: nucleo, chat: chat,
                                                                      mensaje: mensaje)))))
            } else {
                poner(.herramienta(HerramientaPin(.mini(DocumentoMini(miniapp: mini.cual, documento: texto,
                                                                      nucleo: nil, chat: nil, mensaje: nil)))))
            }
        case .archivo:
            // Una referencia rota se queda en el almacen: si el fichero
            // vuelve, el pin tambien.
            guard let ruta = e.ruta, FileManager.default.fileExists(atPath: ruta) else { return }
            let url = URL(fileURLWithPath: ruta)
            switch TipoContenido.de(url) {
            case .pdf:
                guard let documento = PDFDocument(url: url) else { return }
                poner(.pdf(documento, fichero: url))
            case .video, .audio:
                // Los que vuelven al arrancar, callados.
                let reproductor = AVPlayer(url: url)
                reproductor.isMuted = true
                poner(.video(reproductor, fichero: url, soloAudio: TipoContenido.de(url) == .audio))
            case .imagen:
                leerFoto(url) { poner(.imagen($0, fichero: url)) }
            case nil:
                return
            }
        }
    }

    /// Lee una foto reducida a la pantalla, fuera del hilo principal.
    private func leerFoto(_ url: URL, _ listo: @escaping (CGImage) -> Void) {
        let pantalla = NSScreen.main
        let lado = ReglasPin.ladoMiniatura(pantalla: pantalla?.frame.size ?? CGSize(width: 1440, height: 900),
                                           escala: pantalla?.backingScaleFactor ?? 2)
        Task {
            guard let imagen = await Miniatura.fueraDelPrincipal({ Miniatura.de(url: url, ladoMaximo: lado) })
            else { return }
            listo(imagen)
        }
    }
}
