// **El editor de la grabacion** (D7, `editor.rs` y `reproductor.rs` de
// Windows): al parar de grabar no se guarda a lo bruto. Se abre esto, que
// ensena lo grabado dando vueltas, deja recorrerlo con la linea de tiempo y
// solo entonces pregunta que hacer con ello. Media grabacion sale mal a la
// primera, y guardarlas sin mirar llena la carpeta de ficheros que hay que
// borrar despues.
//
// Como en Windows: se abre andando y en bucle; Espacio reproduce y para,
// ← → van fotograma a fotograma, la velocidad (¼× a 4×) y el formato
// (MP4 o GIF) se cambian con su boton; a la derecha, pegados al borde, los
// de decidir: «Guardar…» (pregunta donde), «Guardar» (↩, a `capturas/`
// sin preguntar), «Copiar» (guarda y deja el FICHERO en el portapapeles,
// que se pega entero y sigue moviendose) y «Descartar» (Esc o cerrar la
// ventana).
//
// Lo del Mac, que graba video y no fotogramas: recortar el principio (I) y
// el final (O) arrastrando sus asas, dividir (S) y quitar el tramo bajo el
// cabezal (⌫; otra vez lo devuelve), el zoom (Z; un clic en el video elige
// donde mirar) y ⌘Z deshace. La velocidad y el zoom se guardan tal cual se
// ven. Las cuentas son puras (`EdicionGrabacion`); aqui solo AVFoundation y
// la ventana.
//
// Sin cambios y con una sola pista de sonido, «Guardar» MUEVE el MP4 (sin
// recodificar); si no, se monta una composicion con los tramos (y las dos
// pistas de sonido, que la exportacion mezcla) y se exporta en H.264.

import AppKit
import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorGrabacion: NSObject, NSWindowDelegate {
    /// Los abiertos (cada uno se suelta al cerrar).
    private static var abiertos: [EditorGrabacion] = []

    let modelo: ModeloEditor
    private let ventana: NSWindow
    private var teclado: Any?

    /// Abre el editor con el MP4 recien grabado (temporal: el editor lo
    /// mueve o lo borra). `fecha` da el nombre de Windows al guardarlo en
    /// `carpeta`.
    static func abrir(video: URL, fecha: Date, carpeta: URL, alGuardar: @escaping (URL) -> Void) {
        let editor = EditorGrabacion(video: video, fecha: fecha, carpeta: carpeta, alGuardar: alGuardar)
        abiertos.append(editor)
        editor.mostrar()
    }

    private init(video: URL, fecha: Date, carpeta: URL, alGuardar: @escaping (URL) -> Void) {
        modelo = ModeloEditor(video: video, fecha: fecha, carpeta: carpeta)
        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        super.init()
        modelo.alGuardar = alGuardar
        modelo.alTerminar = { [weak self] in self?.terminar() }
        ventana.title = "Revisar la grabación"
        ventana.isReleasedWhenClosed = false
        ventana.minSize = NSSize(width: 640, height: 420)
        ventana.delegate = self
        ventana.contentView = NSHostingView(rootView: VistaEditorGrabacion(modelo: modelo))
    }

    private func mostrar() {
        // En la pantalla del raton, centrada.
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let v = pantalla?.visibleFrame {
            let tam = NSSize(width: min(960, v.width * 0.8), height: min(700, v.height * 0.85))
            ventana.setFrame(NSRect(x: v.midX - tam.width / 2, y: v.midY - tam.height / 2,
                                    width: tam.width, height: tam.height), display: false)
        }
        teclado = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.ventana else { return e }
            return self.modelo.tecla(e) ? nil : e
        }
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate()
        modelo.cargar()
    }

    /// Cerrar la ventana es descartar (como Windows).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !modelo.ocupado else { return false }
        modelo.decidir(.descartar)
        return false
    }

    private func terminar() {
        if let teclado { NSEvent.removeMonitor(teclado) }
        teclado = nil
        modelo.soltar()
        ventana.orderOut(nil)
        ventana.close()
        EditorGrabacion.abiertos.removeAll { $0 === self }
    }
}

// MARK: - El modelo

@MainActor
final class ModeloEditor: ObservableObject {
    let video: URL
    let fecha: Date
    let carpeta: URL
    var alGuardar: ((URL) -> Void)?
    var alTerminar: (() -> Void)?

    let jugador = AVPlayer()
    private let asset: AVURLAsset
    @Published private(set) var historial = HistorialEdicion(EdicionGrabacion(duracion: 0))
    /// El cabezal, en segundos del original.
    @Published var tiempo: Double = 0
    @Published private(set) var reproduciendo = false
    @Published var formato: FormatoGrabacion = .mp4
    @Published private(set) var ocupado = false
    @Published private(set) var cargado = false
    @Published var aviso: String?
    /// Pixeles del video.
    private(set) var tam = CGSize(width: 16, height: 9)
    private var pistasDeSonido = 0
    private var observador: Any?
    private var alAcabar: NSObjectProtocol?

    var edicion: EdicionGrabacion { historial.actual }

    init(video: URL, fecha: Date, carpeta: URL) {
        self.video = video
        self.fecha = fecha
        self.carpeta = carpeta
        asset = AVURLAsset(url: video)
    }

    func cargar() {
        Task {
            do {
                let duracion = try await asset.load(.duration).seconds
                if let pista = try await asset.loadTracks(withMediaType: .video).first {
                    let natural = try await pista.load(.naturalSize)
                    if natural.width > 0, natural.height > 0 { tam = natural }
                }
                pistasDeSonido = try await asset.loadTracks(withMediaType: .audio).count
                historial = HistorialEdicion(EdicionGrabacion(duracion: duracion.isFinite ? duracion : 0))
                let item = AVPlayerItem(asset: asset)
                item.audioTimePitchAlgorithm = .spectral
                jugador.replaceCurrentItem(with: item)
                jugador.actionAtItemEnd = .pause
                observar(item)
                cargado = true
                // Se abre andando: lo primero es ver si salio bien.
                reproducir(true)
            } catch {
                aviso = "No se pudo abrir la grabación: \(error.localizedDescription)"
            }
        }
    }

    private func observar(_ item: AVPlayerItem) {
        observador = jugador.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.latido(t.seconds) }
        }
        // Al llegar al final del fichero, vuelta al principio de lo que se
        // guarda.
        alAcabar = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                          object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reproduciendo else { return }
                self.ir(a: self.edicion.salto(desde: self.edicion.duracion) ?? 0, seguir: true)
            }
        }
    }

    /// Cada fotograma: el cabezal y, andando, saltar lo que no se guarda
    /// (lo quitado, lo recortado) y dar la vuelta.
    private func latido(_ t: Double) {
        guard t.isFinite else { return }
        tiempo = t
        guard reproduciendo, let destino = edicion.salto(desde: t) else { return }
        ir(a: destino, seguir: true)
    }

    func soltar() {
        jugador.pause()
        if let observador { jugador.removeTimeObserver(observador) }
        observador = nil
        if let alAcabar { NotificationCenter.default.removeObserver(alAcabar) }
        alAcabar = nil
        jugador.replaceCurrentItem(with: nil)
    }

    // MARK: Reproducir

    func reproducir(_ si: Bool) {
        reproduciendo = si
        if si {
            if let s = edicion.salto(desde: tiempo) { ir(a: s, seguir: true) }
            jugador.rate = Float(edicion.velocidad)
        } else {
            jugador.pause()
        }
    }

    /// Al cabezal en `t`. `seguir`: si se estaba reproduciendo, sigue.
    func ir(a t: Double, seguir: Bool = false) {
        let t = min(max(t, 0), edicion.duracion)
        tiempo = t
        if !seguir, reproduciendo { reproducir(false) }
        jugador.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reproduciendo else { return }
                self.jugador.rate = Float(self.edicion.velocidad)
            }
        }
    }

    func paso(_ adelante: Bool, segundo: Bool = false) {
        reproducir(false)
        if segundo {
            ir(a: tiempo + (adelante ? 1 : -1))
        } else {
            ir(a: edicion.paso(desde: tiempo, adelante: adelante))
        }
    }

    // MARK: Editar

    /// `seguido`: parte de un arrastre ya empezado (no es otro paso de
    /// deshacer).
    func cambiar(seguido: Bool = false, _ cambio: (inout EdicionGrabacion) -> Void) {
        let zoomAntes = (edicion.zoom, edicion.centro)
        if seguido { historial.retocar(cambio) } else { historial.cambiar(cambio) }
        if reproduciendo { jugador.rate = Float(edicion.velocidad) }
        if zoomAntes != (edicion.zoom, edicion.centro) { aplicarZoom() }
    }

    func deshacer() {
        let zoomAntes = (edicion.zoom, edicion.centro)
        historial.deshacer()
        if reproduciendo { jugador.rate = Float(edicion.velocidad) }
        if zoomAntes != (edicion.zoom, edicion.centro) { aplicarZoom() }
    }

    /// ⌫: quita el tramo bajo el cabezal o, si ya estaba quitado, lo
    /// devuelve.
    func quitarORestaurar() {
        let t = tiempo
        if edicion.quitado(t) {
            cambiar { _ = $0.restaurar(en: t) }
        } else {
            var prueba = edicion
            if !prueba.quitarSegmento(en: t) {
                NSSound.beep()
                return
            }
            cambiar { _ = $0.quitarSegmento(en: t) }
        }
    }

    /// La vista previa con el mismo zoom que se guardara.
    private func aplicarZoom() {
        guard let item = jugador.currentItem else { return }
        Task {
            item.videoComposition = try? await ExportadorGrabacion.zoom(asset, edicion: edicion, tam: tam,
                                                                        duracion: asset.load(.duration))
        }
    }

    func clicEnVideo(_ p: CGPoint, vista: CGSize) {
        guard edicion.zoom > 1, let f = EdicionGrabacion.fraccion(de: p, vista: vista, video: tam) else { return }
        let tam = self.tam
        cambiar { $0.centrar(enVista: f, tam: tam) }
    }

    // MARK: Teclado

    /// Las teclas del editor (`EventoOverlay::Tecla` de Windows y las del
    /// Mac). Devuelve si la uso.
    func tecla(_ e: NSEvent) -> Bool {
        guard !ocupado else { return true }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let letra = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods.contains(.command) {
            switch letra {
            case "z": deshacer()
            case "s": decidir(.guardar)
            case "c": decidir(.copiar)
            default: return false
            }
            return true
        }
        switch e.keyCode {
        case 49: reproducir(!reproduciendo) // Espacio
        case 123: paso(false, segundo: mods.contains(.shift)) // ←
        case 124: paso(true, segundo: mods.contains(.shift)) // →
        case 36, 76: decidir(.guardadoRapido) // ↩
        case 53: decidir(.descartar) // Esc
        case 51, 117: quitarORestaurar() // ⌫ y Supr
        default:
            let t = tiempo
            switch letra {
            case "i": cambiar { $0.ponerInicio(t) }
            case "o": cambiar { $0.ponerFin(t) }
            case "s": cambiar { _ = $0.dividir(en: t) }
            case "z": cambiar { $0.siguienteZoom() }
            case "v": cambiar { $0.siguienteVelocidad() }
            case "f": formato = formato.siguiente
            default: return false
            }
        }
        return true
    }

    // MARK: Decidir

    func decidir(_ d: DecisionEditor) {
        guard !ocupado else { return }
        if d == .descartar {
            try? FileManager.default.removeItem(at: video)
            alTerminar?()
            return
        }
        let destino: URL
        if d == .guardar {
            // La ruta se pide ANTES de exportar: si se cancela, no se
            // exporta nada y se sigue en el editor.
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "grabacion.\(formato.ext)"
            panel.allowedContentTypes = [formato == .gif ? .gif : .mpeg4Movie]
            panel.directoryURL = carpeta
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destino = url
        } else {
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            destino = GeometriaGrabacion.rutaNueva(en: carpeta, fecha: fecha)
                .deletingPathExtension().appendingPathExtension(formato.ext)
        }
        reproducir(false)
        ocupado = true
        aviso = formato == .gif ? "Haciendo el GIF…" : "Guardando…"
        let edicion = edicion, formato = formato, tam = tam, asset = asset, video = video
        let mover = formato == .mp4 && edicion.sinCambios && pistasDeSonido <= 1
        Task {
            do {
                try? FileManager.default.removeItem(at: destino)
                if mover {
                    try FileManager.default.moveItem(at: video, to: destino)
                } else {
                    switch formato {
                    case .mp4: try await ExportadorGrabacion.mp4(asset, edicion: edicion, tam: tam, a: destino)
                    case .gif: try await ExportadorGrabacion.gif(asset, edicion: edicion, tam: tam, a: destino)
                    }
                    try? FileManager.default.removeItem(at: video)
                }
                if d == .copiar {
                    let tablero = NSPasteboard.general
                    tablero.clearContents()
                    tablero.writeObjects([destino as NSURL])
                }
                ocupado = false
                alGuardar?(destino)
                alTerminar?()
            } catch {
                ocupado = false
                aviso = "No se pudo guardar: \(error.localizedDescription)"
                NSSound.beep()
            }
        }
    }
}

// MARK: - Exportar

enum ExportadorGrabacion {
    /// El zoom como composicion de video (la vista previa y el MP4). `nil`
    /// sin zoom.
    static func zoom(_ asset: AVAsset, edicion: EdicionGrabacion, tam: CGSize,
                     duracion: CMTime) async throws -> AVVideoComposition? {
        guard edicion.zoom > 1, let pista = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        return composicionZoom(pista: pista, edicion: edicion, tam: tam, duracion: duracion)
    }

    private static func composicionZoom(pista: AVAssetTrack, edicion: EdicionGrabacion, tam: CGSize,
                                        duracion: CMTime) -> AVVideoComposition {
        let capa = AVMutableVideoCompositionLayerInstruction(assetTrack: pista)
        capa.setTransform(edicion.transformacion(en: tam), at: .zero)
        let instruccion = AVMutableVideoCompositionInstruction()
        instruccion.timeRange = CMTimeRange(start: .zero, duration: duracion)
        instruccion.layerInstructions = [capa]
        let c = AVMutableVideoComposition()
        c.renderSize = tam
        c.frameDuration = CMTime(value: 1, timescale: GeometriaGrabacion.porSegundo)
        c.instructions = [instruccion]
        return c
    }

    /// Los tramos que se guardan, uno tras otro, a la velocidad elegida y
    /// con todas las pistas de sonido (la exportacion las mezcla).
    static func composicion(_ asset: AVAsset, edicion: EdicionGrabacion) async throws -> AVMutableComposition {
        let c = AVMutableComposition()
        let videos = try await asset.loadTracks(withMediaType: .video)
        let sonidos = try await asset.loadTracks(withMediaType: .audio)
        var pares: [(AVAssetTrack, AVMutableCompositionTrack)] = []
        for p in videos + sonidos {
            guard let destino = c.addMutableTrack(withMediaType: p.mediaType,
                                                  preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            pares.append((p, destino))
        }
        var cursor = CMTime.zero
        for t in edicion.tramos {
            let rango = CMTimeRange(start: CMTime(seconds: t.lowerBound, preferredTimescale: 600),
                                    end: CMTime(seconds: t.upperBound, preferredTimescale: 600))
            for (origen, destino) in pares {
                let suyo = try await origen.load(.timeRange)
                let dentro = rango.intersection(suyo)
                guard !dentro.isEmpty else { continue }
                try destino.insertTimeRange(dentro, of: origen,
                                            at: CMTimeAdd(cursor, CMTimeSubtract(dentro.start, rango.start)))
            }
            cursor = CMTimeAdd(cursor, rango.duration)
        }
        if edicion.velocidad != 1 {
            let todo = CMTimeRange(start: .zero, duration: c.duration)
            c.scaleTimeRange(todo, toDuration: CMTimeMultiplyByFloat64(c.duration, multiplier: 1 / edicion.velocidad))
        }
        return c
    }

    /// El MP4 (H.264) con todo aplicado.
    static func mp4(_ asset: AVAsset, edicion: EdicionGrabacion, tam: CGSize, a destino: URL) async throws {
        let c = try await composicion(asset, edicion: edicion)
        guard let sesion = AVAssetExportSession(asset: c, presetName: AVAssetExportPresetHighestQuality) else {
            throw ErrorGrabacion.escritor("no se puede exportar el vídeo")
        }
        sesion.audioTimePitchAlgorithm = .spectral
        sesion.shouldOptimizeForNetworkUse = true
        if edicion.zoom > 1, let pista = c.tracks(withMediaType: .video).first {
            sesion.videoComposition = composicionZoom(pista: pista, edicion: edicion, tam: tam, duracion: c.duration)
        }
        let temporal = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-exportar-\(UUID().uuidString).mp4")
        try await sesion.export(to: temporal, as: .mp4)
        try FileManager.default.moveItem(at: temporal, to: destino)
    }

    /// El GIF: los fotogramas de lo guardado a `gifPorSegundo`, con el zoom
    /// recortado y el lado mayor a 960 como mucho (lo del GIF grabado).
    static func gif(_ asset: AVAsset, edicion: EdicionGrabacion, tam: CGSize, a destino: URL) async throws {
        let momentos = edicion.momentosGif()
        guard !momentos.isEmpty else { throw ErrorGrabacion.zonaVacia }
        let visible = edicion.zonaVisible(en: tam)
        let sale = DeduplicadorGif.tamSalida(puntos: visible.size)
        let f = CGFloat(sale.ancho) / max(visible.width, 1)
        let generador = AVAssetImageGenerator(asset: asset)
        generador.appliesPreferredTrackTransform = true
        generador.requestedTimeToleranceBefore = .zero
        generador.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generador.maximumSize = CGSize(width: (tam.width * f).rounded(.up), height: (tam.height * f).rounded(.up))
        let recorte = CGRect(x: visible.minX * f, y: visible.minY * f,
                             width: CGFloat(sale.ancho), height: CGFloat(sale.alto)).integral

        let temporal = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-exportar-\(UUID().uuidString).gif")
        guard let gif = CGImageDestinationCreateWithURL(temporal as CFURL, UTType.gif.identifier as CFString,
                                                        momentos.count, nil) else {
            throw ErrorGrabacion.escritor("no se puede escribir el GIF")
        }
        CGImageDestinationSetProperties(gif, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0,
                                            kCGImagePropertyGIFHasGlobalColorMap: false],
        ] as CFDictionary)
        let retraso = 1 / Double(EdicionGrabacion.gifPorSegundo)
        let propiedades = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: retraso,
                                            kCGImagePropertyGIFUnclampedDelayTime: retraso],
        ] as CFDictionary
        let tiempos = momentos.map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await resultado in generador.images(for: tiempos) {
            guard let imagen = try? resultado.image else { continue }
            let r = recorte.intersection(CGRect(x: 0, y: 0, width: imagen.width, height: imagen.height))
            CGImageDestinationAddImage(gif, imagen.cropping(to: r) ?? imagen, propiedades)
        }
        guard CGImageDestinationFinalize(gif) else {
            try? FileManager.default.removeItem(at: temporal)
            throw ErrorGrabacion.escritor("no se pudo escribir el GIF")
        }
        try FileManager.default.moveItem(at: temporal, to: destino)
    }
}

// MARK: - La ventana

struct VistaEditorGrabacion: View {
    @ObservedObject var modelo: ModeloEditor

    var body: some View {
        VStack(spacing: 10) {
            VideoEditor(jugador: modelo.jugador)
                .overlay {
                    GeometryReader { g in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { p in
                                modelo.clicEnVideo(p, vista: g.size)
                            }
                    }
                }
                .overlay(alignment: .center) {
                    if let aviso = modelo.aviso {
                        Text(aviso)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { if !modelo.ocupado { modelo.aviso = nil } }
                    }
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            LineaTiempoGrabacion(modelo: modelo)
                .frame(height: 34)
            mandos
        }
        .padding(12)
        .disabled(modelo.ocupado)
    }

    private var e: EdicionGrabacion { modelo.edicion }

    private var mandos: some View {
        HStack(spacing: 6) {
            // Los de mirar, a la izquierda.
            Button { modelo.paso(false) } label: { Image(systemName: "backward.frame.fill") }
                .help("Fotograma anterior (←; ⇧← un segundo)")
            Button { modelo.reproducir(!modelo.reproduciendo) } label: {
                Image(systemName: modelo.reproduciendo ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .help("Reproducir o parar (Espacio)")
            Button { modelo.paso(true) } label: { Image(systemName: "forward.frame.fill") }
                .help("Fotograma siguiente (→; ⇧→ un segundo)")
            Button(ModeloEditorTexto.velocidad(e.velocidad)) { modelo.cambiar { $0.siguienteVelocidad() } }
                .help("Velocidad (V): así se ve y así se guarda")
            Button(ModeloEditorTexto.zoom(e.zoom)) { modelo.cambiar { $0.siguienteZoom() } }
                .help("Zoom (Z): con zoom, un clic en el vídeo elige dónde mirar")
            Button(modelo.formato.rotulo) { modelo.formato = modelo.formato.siguiente }
                .help("Formato al guardar (F)")
            Divider().frame(height: 18)
            Button { modelo.cambiar { $0.ponerInicio(modelo.tiempo) } } label: { Image(systemName: "arrow.right.to.line") }
                .help("Empezar aquí (I)")
            Button { modelo.cambiar { $0.ponerFin(modelo.tiempo) } } label: { Image(systemName: "arrow.left.to.line") }
                .help("Acabar aquí (O)")
            Button { modelo.cambiar { _ = $0.dividir(en: modelo.tiempo) } } label: { Image(systemName: "scissors") }
                .help("Dividir aquí (S)")
            Button { modelo.quitarORestaurar() } label: {
                Image(systemName: e.quitado(modelo.tiempo) ? "arrow.uturn.backward" : "minus.circle")
            }
            .help(e.quitado(modelo.tiempo) ? "Devolver este tramo (⌫)" : "Quitar el tramo bajo el cabezal (⌫)")
            Button { modelo.deshacer() } label: { Image(systemName: "arrow.uturn.backward.circle") }
                .help("Deshacer (⌘Z)")
                .disabled(!modelo.historial.puedeDeshacer)
            Spacer(minLength: 8)
            // Los de decidir, a la derecha y pegados al borde.
            Button("Descartar", role: .destructive) { modelo.decidir(.descartar) }
                .help("Tirar la grabación (Esc)")
            Button("Copiar") { modelo.decidir(.copiar) }
                .help("Guardar y copiar el fichero para pegarlo (⌘C)")
            Button("Guardar…") { modelo.decidir(.guardar) }
                .help("Elegir dónde guardarla (⌘S)")
            Button("Guardar") { modelo.decidir(.guardadoRapido) }
                .buttonStyle(.borderedProminent)
                .help("A la carpeta de capturas (↩)")
        }
        .controlSize(.regular)
        .disabled(!modelo.cargado)
    }
}

enum ModeloEditorTexto {
    static func velocidad(_ v: Double) -> String {
        switch v {
        case 0.25: "¼×"
        case 0.5: "½×"
        default: "\(Int(v))×"
        }
    }

    static func zoom(_ z: Double) -> String {
        z == 1 ? "Zoom" : (z == 1.5 ? "1,5×" : "\(Int(z))×")
    }
}

/// El video sin mandos (los pone la ventana).
struct VideoEditor: NSViewRepresentable {
    let jugador: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.player = jugador
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== jugador { v.player = jugador }
    }
}

/// La linea de tiempo: lo que se guarda en azul, lo recortado y lo quitado
/// apagado, las divisiones, las asas de principio y fin (se arrastran) y el
/// cabezal (pinchar o arrastrar lleva ahi y para, como en Windows).
struct LineaTiempoGrabacion: View {
    @ObservedObject var modelo: ModeloEditor
    @State private var agarrado: Agarre?

    private enum Agarre { case inicio, fin, cabezal }

    var body: some View {
        let e = modelo.edicion
        HStack(spacing: 10) {
            Text(MarcoAjustable.reloj(modelo.tiempo))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            GeometryReader { g in
                let ancho = g.size.width
                let x = { (t: Double) -> CGFloat in e.duracion > 0 ? CGFloat(t / e.duracion) * ancho : 0 }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12))
                    ForEach(Array(e.tramos.enumerated()), id: \.offset) { _, t in
                        Rectangle().fill(Color.accentColor.opacity(0.55))
                            .frame(width: max(x(t.upperBound) - x(t.lowerBound), 1))
                            .offset(x: x(t.lowerBound))
                    }
                    ForEach(Array(e.divisiones.enumerated()), id: \.offset) { _, d in
                        Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1).offset(x: x(d))
                    }
                    asa.offset(x: x(e.inicio) - 3)
                    asa.offset(x: x(e.fin) - 3)
                    Rectangle().fill(Color.white).frame(width: 2)
                        .shadow(radius: 1)
                        .offset(x: x(modelo.tiempo) - 1)
                }
                .frame(height: g.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    guard e.duracion > 0, ancho > 0 else { return }
                    let t = Double(min(max(v.location.x / ancho, 0), 1)) * e.duracion
                    let seguido = agarrado != nil
                    if agarrado == nil {
                        // Lo que este a menos de 8 puntos del sitio pinchado.
                        let px = v.startLocation.x
                        if abs(px - x(e.inicio)) < 8 { agarrado = .inicio }
                        else if abs(px - x(e.fin)) < 8 { agarrado = .fin }
                        else { agarrado = .cabezal }
                    }
                    switch agarrado {
                    case .inicio:
                        modelo.cambiar(seguido: seguido) { $0.ponerInicio(t) }
                        modelo.ir(a: modelo.edicion.inicio)
                    case .fin:
                        modelo.cambiar(seguido: seguido) { $0.ponerFin(t) }
                        modelo.ir(a: modelo.edicion.fin)
                    default: modelo.ir(a: t)
                    }
                }.onEnded { _ in agarrado = nil })
            }
            Text(MarcoAjustable.reloj(e.duracionFinal))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Lo que dura lo que se guarda")
        }
    }

    private var asa: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.yellow).frame(width: 6)
    }
}
