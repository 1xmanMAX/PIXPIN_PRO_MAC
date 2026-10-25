// **Grabar una clase o una reunion** (Windows edd0ffa,
// `ventana_chat/grabar_clase.rs`): una ventanita siempre encima, como el
// microfono flotante.
//
// 1. **Preparar**: que se oye —el microfono, el sonido del Mac (lo que suena
//    en Meet o Zoom) o los dos— y en que proyecto se guarda (un clic pasa al
//    siguiente). Un boton grande para empezar; ↩ empieza y ⎋ cierra.
// 2. **Grabando**: una barra arriba en el centro con el tiempo, el nivel,
//    **Captura**, cambiar la zona, pausa, **Terminar** y tirar (✕ dos veces).
//    La primera captura pide la zona con la captura de siempre
//    (`Capturador.elegirZonaDeLaClase`); las siguientes repiten la misma
//    zona con un clic. La barra no sale en ninguna foto (las fotos no llevan
//    las ventanas de PixPin, y `sharingType = .none` la quita tambien de lo
//    que se comparte en la reunion) y pulsarla no le quita el teclado a la
//    reunion (el panel no se hace principal mientras graba).
// 3. **Guardar**: `Nucleo.guardarClase` deja en el chat lo mismo que
//    Windows: la nota de voz `Clase 24-10 18h05.m4a`, detras el video (si
//    se grabo) y cada captura con su minuto, enlazados (`capturas`, `video`
//    y `enGrabacion`). Las fotos que aun se estaban haciendo al terminar se
//    esperan; si la nota no se cerro, lo demas entra igual, suelto.
// 4. **Pasar a texto** en el aparato, como «Pasar a texto» del chat
//    (`Almacen.transcribir`). Sin reconocedor se guarda igual y se dice
//    donde pedirlo luego.
//
// **Con video** (Windows 20162e9, 25-oct-2026): el interruptor «Vídeo de
// esta pantalla» (apagado de salida: ocupa mucho y casi siempre basta la
// nota con sus capturas) graba ademas la pantalla donde esta la ventanita a
// un MP4 con el mismo sonido (`VideoDeClase`). En la barra se ve siempre
// «Grabando vídeo»; si se corta, se dice una vez y la nota sigue.
//
// Las fotos no paran la barra: se hacen fuera del hilo principal (el
// «fotografo» de Windows) y cuentan en «Captura · N» desde el clic.
//
// El sonido lo graba `AudioDeClase` (microfono + ScreenCaptureKit). Los
// textos son los de Windows (`clase-*` de `main.ftl`).

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class GrabarClase: ObservableObject {
    public static let compartida = GrabarClase()

    /// Lo que dura un aviso en la linea de abajo de la barra.
    static let avisoDura: TimeInterval = 2.6
    /// Lo que espera el segundo clic en ✕ para tirar la grabacion.
    static let tirarEspera: TimeInterval = 4
    /// Lo que se espera a que se elija la zona antes de darla por perdida.
    static let zonaEspera: TimeInterval = 180
    /// Lo que se queda «Guardada» en pantalla antes de irse sola.
    static let listaDura: TimeInterval = 12
    static let falloDura: TimeInterval = 6

    enum Fase: Equatable {
        case preparar
        case abriendo
        case grabando
        case guardando
        /// Pasando a texto la nota ya guardada.
        case texto
        case lista(texto: String, sub: String)
        case fallo(String)

        /// El tamano de la ventanita (`tamano` de Windows).
        var tam: NSSize {
            switch self {
            case .preparar: NSSize(width: 340, height: 370)
            // Lo que piden los botones de la barra: 146 de tiempo y nivel,
            // 392 de botones y el margen.
            case .abriendo, .grabando: NSSize(width: 556, height: 92)
            default: NSSize(width: 360, height: 170)
            }
        }

        var esBarra: Bool { self == .abriendo || self == .grabando }
    }

    @Published private(set) var fase: Fase = .preparar
    @Published var microfono = true
    @Published var equipo = true
    /// Grabar tambien el video de la pantalla.
    @Published var video = false
    /// Se esta grabando el video (para «Grabando vídeo» en la barra).
    @Published private(set) var conVideo = false
    /// El video se corto (se dice una vez; la nota sigue).
    @Published private(set) var videoRoto = false
    /// Las fotos que aun se estan haciendo: cuentan ya (el clic se vio).
    @Published private(set) var pendientes = 0
    /// Donde se puede guardar, el ultimo usado primero.
    @Published private(set) var proyectos: [FichaChat] = []
    @Published private(set) var proyecto = 0
    @Published private(set) var aviso: String?
    @Published private(set) var tirando = false
    @Published private(set) var destello = false
    @Published private(set) var enPausa = false
    /// Las capturas hechas: su minuto y el PNG en un temporal.
    @Published private(set) var capturas: [(ms: Int64, url: URL)] = []

    /// Lo pone la app al arrancar.
    public weak var almacen: Almacen?

    private var panel: PanelClase?
    private var audio: AudioDeClase?
    private var grabador: VideoDeClase?
    /// Si el video entro en el chat, para el «Guardada» del final.
    private var videoGuardado = false
    /// La zona de las capturas (global, de AppKit), una vez elegida.
    private var zona: CGRect?
    /// Esperando la zona: desde cuando y el minuto en que se pidio (la
    /// primera foto es de cuando se pulso, no de cuando se termino de elegir).
    private var pidiendoZona: (desde: Date, ms: Int64)?
    private var turnoAviso = 0
    private var turnoTirar = 0
    private var cierre: DispatchWorkItem?
    private var tareaTexto: Task<Bool, Never>?
    private var guardadas = 0

    public init() {}

    var nombreDelProyecto: String { proyectos.indices.contains(proyecto) ? proyectos[proyecto].nombre : "" }

    // MARK: Abrir y cerrar

    /// **Abre «Grabar clase»**. Si ya hay una abierta, la trae delante.
    public func abrir() {
        if let panel, panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        guard let almacen else { return NSSound.beep() }
        fase = .preparar
        aviso = nil
        tirando = false
        enPausa = false
        capturas = []
        zona = nil
        pidiendoZona = nil
        guardadas = 0
        conVideo = false
        videoRoto = false
        videoGuardado = false
        pendientes = 0
        Task {
            await almacen.cargarChats()
            var lista = almacen.chats.filter { !$0.esAsistente }
            if lista.isEmpty {
                // Sin proyectos, en «Mensajes guardados».
                let nucleo = almacen.nucleo
                if let g = await Task.detached(priority: .userInitiated, operation: { try? nucleo.chatGuardados() }).value {
                    lista = [g]
                }
            }
            let ultimo = UserDefaults.standard.string(forKey: ListaDeProyectos.clave)
            proyectos = ListaDeProyectos.ordenar(lista, id: \.id, ultimo: ultimo)
            proyecto = 0
            guard !proyectos.isEmpty else { return NSSound.beep() }
            mostrar()
        }
    }

    private func mostrar() {
        let p = panel ?? crear()
        panel = p
        recolocar()
        p.tomaTeclado = true
        // Preparar toma el teclado (↩ empieza, ⎋ cierra); grabando ya no.
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
    }

    private func crear() -> PanelClase {
        let vista = NSHostingView(rootView: VistaGrabarClase(g: self))
        let p = PanelClase(contentRect: NSRect(origin: .zero, size: fase.tam),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        // Que no salga en lo que se comparte ni en ninguna foto.
        p.sharingType = .none
        p.contentView = vista
        p.alTeclear = { [weak self] e in self?.tecla(e) ?? false }
        return p
    }

    /// Preparar, en el centro de la pantalla del raton; la barra, arriba en
    /// el centro (a la vista y lejos de lo que se suele mirar); lo demas,
    /// donde quedo la barra.
    private func recolocar(antes: NSRect? = nil) {
        guard let panel else { return }
        let tam = fase.tam
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let v = pantalla?.visibleFrame else { return }
        var origen: NSPoint
        switch (fase, antes) {
        case (.preparar, _):
            origen = NSPoint(x: v.midX - tam.width / 2, y: v.midY - tam.height / 2)
        case (.abriendo, _), (_, nil):
            origen = NSPoint(x: v.midX - tam.width / 2, y: v.maxY - 16 - tam.height)
        case let (_, a?):
            origen = NSPoint(x: a.midX - tam.width / 2, y: a.maxY - tam.height)
        }
        origen.x = min(max(origen.x, v.minX), v.maxX - tam.width)
        origen.y = min(max(origen.y, v.minY), v.maxY - tam.height)
        panel.setFrame(NSRect(origin: origen, size: tam), display: true)
    }

    private func cambiar(_ nueva: Fase) {
        let antes = panel?.frame
        let otroTam = nueva.tam != fase.tam
        fase = nueva
        if otroTam { recolocar(antes: antes) }
        cierre?.cancel()
        switch nueva {
        case .lista: irseEn(GrabarClase.listaDura)
        case .fallo: irseEn(GrabarClase.falloDura)
        default: break
        }
    }

    private func irseEn(_ s: TimeInterval) {
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.cerrar() } }
        cierre = t
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: t)
    }

    /// Cierra la ventanita. A mitad de grabar no tira nada: lo grabado se
    /// guarda (tirar es ✕ dos veces).
    func cerrar() {
        cierre?.cancel()
        if fase == .grabando {
            terminar()
            return
        }
        // Abriendo el audio: quien lo abre ve que ya no toca y lo suelta.
        if fase == .abriendo { fase = .preparar }
        Capturador.principal?.soltarZonaDeLaClase()
        panel?.orderOut(nil)
        borrarCapturas()
    }

    private func borrarCapturas() {
        let viejas = capturas.map { $0.url }
        capturas = []
        for u in viejas { try? FileManager.default.removeItem(at: u) }
    }

    /// ↩ y ⎋, como en Windows.
    func tecla(_ e: NSEvent) -> Bool {
        let esc = e.keyCode == 53
        let intro = e.keyCode == 36 || e.keyCode == 76
        switch fase {
        case .preparar:
            if esc { cerrar(); return true }
            if intro { empezar(); return true }
        case .lista, .fallo:
            if esc || intro { cerrar(); return true }
        default:
            break
        }
        return false
    }

    // MARK: Avisos

    func avisar(_ texto: String?) {
        aviso = texto
        turnoAviso += 1
        let turno = turnoAviso
        guard texto != nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(GrabarClase.avisoDura * 1e9))
            // Mientras se elige la zona, «Elige la zona…» se queda.
            if turno == turnoAviso, pidiendoZona == nil { aviso = nil }
        }
    }

    // MARK: Preparar

    func otroProyecto() {
        guard !proyectos.isEmpty else { return }
        proyecto = (proyecto + 1) % proyectos.count
    }

    func empezar() {
        guard fase == .preparar else { return }
        let fuentes = FuentesClase(microfono: microfono, equipo: equipo)
        guard fuentes.alguna else { return avisar("Elige el micrófono, el sonido del equipo o los dos") }
        let quiereVideo = video
        if fuentes.equipo || quiereVideo, !PermisoCaptura.asegurar() { return }
        // La pantalla del video: la de la ventanita al pulsar «Empezar»; la
        // barra no sale en el.
        let pantalla = panel?.screen ?? NSScreen.main
        let ventana = panel.map { CGWindowID($0.windowNumber) }
        cambiar(.abriendo)
        panel?.tomaTeclado = false
        Task {
            if fuentes.microfono, !(await GrabadoraVoz.permisoMicrofono()) {
                return fallo("No hay micrófono, o PixPin no tiene permiso para usarlo. Mira en Ajustes del Sistema › Privacidad › Micrófono.")
            }
            ReproductorVoz.compartido.parar()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pixpin-clase-\(UUID().uuidString).\(FormatoVoz.extensionFichero)")
            var v: VideoDeClase?
            do {
                let a = try AudioDeClase(url: url, fuentes: fuentes)
                // Con video, la nota le manda una copia de lo que escribe
                // desde el primer bloque: el video empieza con ella.
                var sinVideo = false
                if quiereVideo {
                    v = GrabarClase.prepararVideo(junto: url, en: pantalla)
                    if let hecho = v {
                        a.copia = { [weak hecho] m in hecho?.sonido(m) }
                        hecho.alRomperse = { [weak self] in
                            DispatchQueue.main.async { MainActor.assumeIsolated { self?.videoSeCorto() } }
                        }
                    } else {
                        sinVideo = true
                    }
                }
                try await a.empezar()
                // Cerrada mientras se abria: no se graba.
                guard fase == .abriendo else {
                    await v?.tirar()
                    return await a.cancelar()
                }
                audio = a
                grabador = v
                self.conVideo = v != nil
                cambiar(.grabando)
                if sinVideo { videoSeCorto() }
                // Si la pantalla no se deja mirar, el video queda roto (lo
                // dice `alRomperse`) y la nota sigue.
                if let v { try? await v.empezar(sin: ventana) }
            } catch {
                await v?.tirar()
                try? FileManager.default.removeItem(at: url)
                fallo(GrabarClase.explicar(error))
            }
        }
    }

    /// El video de la clase, al lado del temporal de la nota y con su mismo
    /// nombre (`temporal_del_video`), para la pantalla `pantalla`. `nil` si
    /// no se puede abrir el MP4.
    static func prepararVideo(junto nota: URL, en pantalla: NSScreen?) -> VideoDeClase? {
        guard let pantalla else { return nil }
        let escala = pantalla.backingScaleFactor
        let pixeles = (ancho: Int(pantalla.frame.width * escala), alto: Int(pantalla.frame.height * escala))
        let url = nota.deletingLastPathComponent()
            .appendingPathComponent(nota.lastPathComponent + ".video.mp4")
        return try? VideoDeClase(url: url, pantalla: pantalla.numeroDePantalla ?? CGMainDisplayID(),
                                 pixeles: pixeles, muestreo: Int(AudioDeClase.muestreo))
    }

    /// El video se corto: se dice una vez; la nota sigue.
    private func videoSeCorto() {
        guard !videoRoto else { return }
        videoRoto = true
        if fase == .grabando { avisar("El vídeo se cortó; el audio sigue grabándose") }
    }

    nonisolated static func explicar(_ error: Error) -> String {
        switch error as? ErrorAudioClase {
        case .sinSonidoDelEquipo?: "No se oye nada del equipo: no hay altavoces ni cascos activos"
        case .sinMicrofono?: "No hay micrófono, o PixPin no tiene permiso para usarlo. Mira en Ajustes del Sistema › Privacidad › Micrófono."
        default: "No se pudo grabar la nota de voz."
        }
    }

    private func fallo(_ texto: String) {
        panel?.tomaTeclado = true
        cambiar(.fallo(texto))
    }

    // MARK: Grabando

    /// Lo que lleva la nota.
    var llevadoMs: Int64 { audio?.llevadoMs ?? 0 }
    var nivel: Float { audio?.nivel ?? 0 }
    /// Las capturas de la barra: las hechas y las que aun se estan haciendo.
    var hechas: Int { capturas.count + pendientes }

    /// **Captura**: la zona de antes con un clic, o elegirla la primera vez.
    func capturar() {
        guard fase == .grabando, let audio else { return }
        tirando = false
        let ms = audio.llevadoMs
        // Sin zona, o eligiendola todavia: `pedirZona` sabe que no hay que
        // pedirla dos veces.
        guard let zona, pidiendoZona == nil else { return pedirZona(ms) }
        // La foto se hace fuera y la barra sigue; cuenta ya.
        pendientes += 1
        Task {
            defer { pendientes = max(pendientes - 1, 0) }
            guard let fotos = try? await Instantanea.fotografiarTodas(),
                  let (imagen, escala) = Capturador.recortar(zona, de: fotos),
                  let url = await GrabarClase.escribirPng(imagen, escala: escala) else {
                return avisar("No se pudo capturar la zona")
            }
            anotar(ms: ms, url: url)
        }
    }

    /// Cambiar la zona: la pide otra vez (y esa foto cuenta).
    func cambiarZona() {
        guard fase == .grabando, let audio else { return }
        tirando = false
        pedirZona(audio.llevadoMs)
    }

    private func pedirZona(_ ms: Int64) {
        // Ya se esta eligiendo: no se pide otra vez (se perderia el minuto
        // en que se pulso la primera).
        if pidiendoZona != nil { return avisar("Elige la zona en la pantalla…") }
        guard let capturador = Capturador.principal, !capturador.abierta else {
            return avisar("No se pudo capturar la zona")
        }
        pidiendoZona = (Date(), ms)
        avisar("Elige la zona en la pantalla…")
        capturador.elegirZonaDeLaClase { [weak self] elegida in
            guard let self, let pedido = self.pidiendoZona else { return }
            self.pidiendoZona = nil
            guard let elegida else { return self.avisar(nil) }
            self.zona = elegida.zona
            let escala = NSScreen.screens.first { $0.frame.intersects(elegida.zona) }?.backingScaleFactor ?? 2
            self.pendientes += 1
            Task {
                defer { self.pendientes = max(self.pendientes - 1, 0) }
                guard let url = await GrabarClase.escribirPng(elegida.foto, escala: escala) else {
                    return self.avisar("Zona cambiada")
                }
                self.anotar(ms: pedido.ms, url: url)
            }
        }
        // Sin elegir en tres minutos, se da por perdida.
        let desde = pidiendoZona?.desde
        DispatchQueue.main.asyncAfter(deadline: .now() + GrabarClase.zonaEspera) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let p = self.pidiendoZona, p.desde == desde else { return }
                self.pidiendoZona = nil
                Capturador.principal?.soltarZonaDeLaClase()
                self.avisar("No se eligió ninguna zona: pulsa «Captura» otra vez")
            }
        }
    }

    private func anotar(ms: Int64, url: URL) {
        // Guardando: es una de las que se estaban haciendo al terminar.
        guard fase == .grabando || fase == .guardando else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        capturas.append((ms: ms, url: url))
        destello = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            destello = false
        }
        avisar("Captura guardada en el \(FormatoVoz.marca(ms: ms))")
    }

    /// El PNG de una captura en un temporal, fuera del hilo principal.
    nonisolated static func escribirPng(_ imagen: CGImage, escala: CGFloat) async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            guard let datos = Capturador.codificar(imagen, tipo: .png, escala: escala) else { return nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-clase-\(UUID().uuidString).png")
            return (try? datos.write(to: url)) != nil ? url : nil
        }.value
    }

    func alternarPausa() {
        guard fase == .grabando, let audio else { return }
        tirando = false
        enPausa.toggle()
        audio.pausar(enPausa)
    }

    /// ✕: la primera vez avisa; la segunda, en 4 s, tira la grabacion.
    func tirar() {
        switch fase {
        case .grabando:
            if tirando {
                tirando = false
                let a = audio
                let v = grabador
                audio = nil
                grabador = nil
                conVideo = false
                Capturador.principal?.soltarZonaDeLaClase()
                Task {
                    await a?.cancelar()
                    await v?.tirar()
                }
                panel?.orderOut(nil)
                borrarCapturas()
                fase = .preparar
            } else {
                tirando = true
                turnoTirar += 1
                let turno = turnoTirar
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(GrabarClase.tirarEspera * 1e9))
                    if turno == turnoTirar { tirando = false }
                }
            }
        case .texto:
            // Mientras se pasa a texto, ✕ lo deja: la nota ya esta guardada.
            tareaTexto?.cancel()
            tareaTexto = nil
            almacen?.ponerError(nil)
            cambiar(lista(conTexto: false))
        default:
            break
        }
    }

    // MARK: Terminar y guardar

    /// **Terminar**: guarda todo lo que haya. Las fotos que aun se estaban
    /// haciendo se esperan (5 s como mucho); el video se cierra cuando se
    /// cierra la nota. Si la nota no vale (un resbalon en el boton), el
    /// video se tira, pero las capturas se guardan igual: una reunion sin su
    /// nota sigue valiendo por sus imagenes.
    func terminar() {
        guard fase == .grabando || fase == .abriendo, let audio, let almacen,
              proyectos.indices.contains(proyecto) else { return }
        tirando = false
        self.audio = nil
        let video = grabador
        grabador = nil
        Capturador.principal?.soltarZonaDeLaClase()
        pidiendoZona = nil
        let chat = proyectos[proyecto].id
        panel?.tomaTeclado = true
        cambiar(.guardando)
        Task {
            let limite = Date().addingTimeInterval(5)
            while pendientes > 0, Date() < limite {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let hechas = capturas
            let nota = await audio.terminar()
            // Con el sonido parado, el video escribe lo que le quede y cierra.
            let mp4 = await video?.terminar()
            conVideo = false
            defer { try? FileManager.default.removeItem(at: nota.url) }
            let corta = nota.duracionMs < FormatoVoz.minimoMs
            if corta, let mp4 { try? FileManager.default.removeItem(at: mp4) }
            guard !corta || !hechas.isEmpty else {
                borrarCapturas()
                return fallo("Demasiado corta: mantén pulsado un poco más.")
            }
            let rutaAudio = corta ? nil : nota.url.path
            let rutaVideo = corta ? nil : mp4?.path
            let nucleo = almacen.nucleo
            let desfase = Int64(TimeZone.current.secondsFromGMT()) * 1000
            let lista = hechas.map { CapturaClase(ms: $0.ms, rutaPng: $0.url.path) }
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<ClaseGuardada, Error> in
                Result {
                    try nucleo.guardarClase(chat: chat, rutaAudio: rutaAudio, duracionMs: nota.duracionMs,
                                            picos: nota.picos, rutaVideo: rutaVideo, capturas: lista,
                                            desfaseMs: desfase)
                }
            }.value
            borrarCapturas()
            // El video que no entro no se borra: el nucleo lo deja en la
            // carpeta del proyecto (es la reunion entera).
            switch hecho {
            case let .success(clase):
                UserDefaults.standard.set(chat, forKey: ListaDeProyectos.clave)
                guardadas = clase.capturas.count
                videoGuardado = clase.video != nil
                let nuevos = [clase.voz, clase.video].compactMap { $0 } + clase.capturas
                if almacen.mensajes[chat] != nil { almacen.anadir(nuevos, en: chat) }
                await almacen.cargarChats()
                if let voz = clase.voz {
                    ClaseEnElChat.olvidar(chat: chat, mensaje: voz.id)
                    pasarATexto(voz, chat: chat, almacen: almacen)
                } else {
                    // Lo que si entro se dice: que nadie crea que lo perdio todo.
                    var texto = "Demasiado corta: mantén pulsado un poco más."
                    if guardadas > 0 || videoGuardado { texto += " · Lo demás se guardó: \(guardadas) capturas" }
                    fallo(texto)
                }
            case .failure:
                fallo("No se pudo grabar la nota de voz.")
            }
        }
    }

    /// Empieza a pasar a texto la nota recien guardada, si se puede.
    private func pasarATexto(_ voz: MensajeChat, chat: String, almacen: Almacen) {
        guard TranscriptorVoz.reconocedorLocal() != nil else { return cambiar(lista(conTexto: false)) }
        cambiar(.texto)
        let t = Task { await almacen.transcribir(voz, en: chat) }
        tareaTexto = t
        Task {
            let bien = await t.value
            guard fase == .texto, tareaTexto == t else { return }
            tareaTexto = nil
            cambiar(lista(conTexto: bien))
        }
    }

    private func lista(conTexto: Bool) -> Fase {
        let n = guardadas
        let sub = conTexto
            ? "Con \(n) capturas y la transcripción. Ábrela en el chat para verla junto a las imágenes."
            : "Con \(n) capturas. Para el texto, pulsa «Pasar a texto» en la nota del chat."
        return .lista(texto: "Guardada en «\(nombreDelProyecto)»",
                      sub: videoGuardado ? "Con el vídeo de la pantalla. \(sub)" : sub)
    }
}

/// El panel de la ventanita: toma el teclado solo cuando hace falta
/// (preparar y el final); grabando, los clics no se lo quitan a la reunion.
final class PanelClase: NSPanel {
    var tomaTeclado = true
    var alTeclear: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { tomaTeclado }

    override func keyDown(with event: NSEvent) {
        if alTeclear?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let e = NSApp.currentEvent, alTeclear?(e) == true { return }
    }
}

// MARK: - Las vistas

/// El rojo de grabar del chat (`ROJO_GRABAR`).
private let rojoGrabar = Color(red: 0xE5 / 255, green: 0x53 / 255, blue: 0x4B / 255)
private let verdeClase = Color(red: 0x2E / 255, green: 0xA0 / 255, blue: 0x43 / 255)

struct VistaGrabarClase: View {
    @ObservedObject var g: GrabarClase

    var body: some View {
        Group {
            switch g.fase {
            case .preparar: preparar
            case .abriendo, .grabando: barra
            case .guardando:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Guardando la clase…").font(.system(size: 15))
                }
            case .texto: texto
            case let .lista(t, sub): alFinal(simbolo: "checkmark.circle", color: verdeClase, texto: t, sub: sub)
            case let .fallo(t): alFinal(simbolo: "mic", color: rojoGrabar, texto: t, sub: nil)
            }
        }
        .frame(width: g.fase.tam.width, height: g.fase.tam.height)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Preparar

    private var preparar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grabar clase o reunión").font(.system(size: 17, weight: .semibold))
                    Text("Graba el audio y pon capturas en su minuto").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { g.cerrar() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Cerrar (⎋)")
            }
            .padding(.bottom, 4)
            interruptor("mic", "Micrófono", $g.microfono)
            interruptor("speaker.wave.2", "Sonido del equipo (Meet, Zoom…)", $g.equipo)
            // Apagado de salida: el video ocupa mucho y casi siempre basta la
            // nota con sus capturas.
            interruptor("video", "Vídeo de esta pantalla", $g.video)
            Button { g.otroProyecto() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(.yellow).frame(width: 20)
                    Text("Guardar en: \(g.nombreDelProyecto)").lineLimit(1).truncationMode(.tail)
                    Spacer()
                    if g.proyectos.count > 1 { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { g.empezar() } label: {
                HStack(spacing: 10) {
                    Circle().fill(.white).frame(width: 12, height: 12)
                    Text("Empezar a grabar").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(rojoGrabar, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Text(g.aviso ?? " ").font(.system(size: 12)).foregroundStyle(rojoGrabar)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
    }

    private func interruptor(_ simbolo: String, _ rotulo: String, _ valor: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: simbolo).frame(width: 20).foregroundStyle(valor.wrappedValue ? .primary : .secondary)
            Text(rotulo).lineLimit(1)
            Spacer()
            Toggle("", isOn: valor).toggleStyle(.switch).labelsHidden().tint(verdeClase)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: La barra

    private var barra: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { contexto in
            let grabando = g.fase == .grabando
            let latido = contexto.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // ● 12:34
                    Circle()
                        .fill(g.enPausa ? Color.secondary : rojoGrabar)
                        .frame(width: 10, height: 10)
                        .opacity(grabando && (g.enPausa || latido < 0.6) ? 1 : 0)
                    Text(FormatoVoz.marca(ms: grabando ? g.llevadoMs : 0))
                        .font(.system(size: 18, weight: .medium).monospacedDigit())
                        .frame(width: 66, alignment: .leading)
                    nivel(grabando ? g.nivel : 0)
                    boton("photo", g.hechas == 0 ? "Captura" : "Captura · \(g.hechas)",
                          fondo: g.destello ? verdeClase : Color.accentColor, tinta: .white, ancho: 128) { g.capturar() }
                        .help("«Captura» guarda una zona de la pantalla en este minuto")
                    boton("crop", "", fondo: Color.white.opacity(0.1), tinta: .primary, ancho: 44) { g.cambiarZona() }
                        .help("Cambiar la zona")
                    boton(g.enPausa ? "play.fill" : "pause.fill", "", fondo: Color.white.opacity(0.1), tinta: .primary,
                          ancho: 44) { g.alternarPausa() }
                        .help(g.enPausa ? "Seguir" : "Pausa")
                    boton("stop.fill", "Terminar", fondo: rojoGrabar, tinta: .white, ancho: 108) { g.terminar() }
                    boton("xmark", "", fondo: g.tirando ? rojoGrabar : Color.white.opacity(0.1),
                          tinta: g.tirando ? .white : .secondary, ancho: 36) { g.tirar() }
                        .help("Tirar la grabación (dos clics)")
                }
                .disabled(!grabando)
                HStack(spacing: 8) {
                    linea
                        .lineLimit(1)
                    if g.conVideo {
                        // Que se esta grabando la pantalla tiene que verse
                        // siempre.
                        Spacer(minLength: 0)
                        Label("Grabando vídeo", systemImage: "video.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(g.videoRoto || g.enPausa ? Color.secondary : rojoGrabar)
                            .fixedSize()
                    }
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    /// La linea de abajo: lo que acaba de pasar, o la pista.
    @ViewBuilder private var linea: some View {
        if g.fase != .grabando {
            Text("Abriendo el audio…").foregroundStyle(.secondary)
        } else if g.tirando {
            Text("Pulsa ✕ otra vez para tirar la grabación").foregroundStyle(rojoGrabar)
        } else if let a = g.aviso {
            Text(a)
        } else if g.enPausa {
            Text("En pausa: no se graba nada").foregroundStyle(.secondary)
        } else if g.hechas == 0 {
            Text("«Captura» guarda una zona de la pantalla en este minuto").foregroundStyle(.secondary)
        } else {
            Text("Capturas: \(g.hechas) · la zona se repite con un clic").foregroundStyle(.secondary)
        }
    }

    /// El nivel: cinco barras que dicen que de verdad entra sonido.
    private func nivel(_ n: Float) -> some View {
        let forma: [CGFloat] = [0.5, 0.8, 1, 0.8, 0.5]
        let raiz = CGFloat(min(max(n, 0), 1)).squareRoot()
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(g.enPausa ? Color.secondary : Color.accentColor)
                    .frame(width: 3, height: max(26 * raiz * forma[i], 2))
            }
        }
        .frame(width: 30, height: 28)
    }

    private func boton(_ simbolo: String, _ rotulo: String, fondo: Color, tinta: Color, ancho: CGFloat,
                       _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Image(systemName: simbolo).font(.system(size: 14, weight: .semibold))
                if !rotulo.isEmpty { Text(rotulo).font(.system(size: 13, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(tinta)
            .frame(width: ancho, height: 44)
            .background(fondo, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pasando a texto y el final

    private var texto: some View {
        VStack(spacing: 10) {
            Image(systemName: "captions.bubble").font(.system(size: 26)).foregroundStyle(Color.accentColor)
            Text("Pasando a texto…").font(.system(size: 15))
            ProgressView().progressViewStyle(.linear).padding(.horizontal, 24)
            Button { g.tirar() } label: {
                Label("Dejarlo sin texto", systemImage: "xmark")
                    .frame(width: 160, height: 34)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func alFinal(simbolo: String, color: Color, texto: String, sub: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: simbolo).font(.system(size: 26)).foregroundStyle(color)
            Text(texto).font(.system(size: 15)).multilineTextAlignment(.center)
            if let sub {
                Text(sub).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Button("Listo") { g.cerrar() }
                .keyboardShortcut(.defaultAction)
                .frame(width: 120)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
