// Musica con letra en el chat (Windows fc1101e y 058ae2b,
// `ventana_chat/musica.rs`): una cancion es una nota `VOZ` con
// `estadoDelTexto = letra` y la letra en `transcripcion` (`[m:ss] linea`).
// La burbuja es una tarjeta con la portada que trae el fichero (o un
// degradado con la nota), el titulo y el artista de sus etiquetas y la
// pastilla que abre el karaoke; pulsarla la toca. El karaoke va sin la tira
// de arriba: la portada con el titulo y el artista, A-, A+ y la ✕; la linea
// que suena grande y en color a un tercio de la altura, las cantadas
// apagadas, y un clic en una linea lleva la cancion ahi.

import AppKit
import AVFoundation
import PixPinCore
import SwiftUI

/// Lo que se ensena de una cancion: sus etiquetas (ID3, MP4, FLAC por
/// AVFoundation) y su portada. Sin etiquetas, nada: nunca el nombre del
/// fichero en el karaoke.
struct TarjetaMusica: Equatable {
    var titulo: String?
    var artista: String?
    var album: String?
    var portada: NSImage?

    static func == (a: TarjetaMusica, b: TarjetaMusica) -> Bool {
        a.titulo == b.titulo && a.artista == b.artista && a.album == b.album && a.portada === b.portada
    }
}

@MainActor
enum MusicaChat {
    private static var tarjetas: [URL: TarjetaMusica] = [:]
    private static var idsPorChat: [String: (cuando: Date, ids: Set<String>)] = [:]

    /// Si la nota es una cancion: su id en las lineas `letra` del cuaderno
    /// del chat (el puente no trae `estadoDelTexto`). Se relee si el
    /// cuaderno cambio.
    static func esMusica(_ m: MensajeChat, chat: String, nucleo: Nucleo) -> Bool {
        // El puente ya trae lo que es (`opciones_del_mensaje`): sin leer el
        // cuaderno entero.
        if let tipo = m.tipo { return tipo == .musica }
        guard m.clase == "VOZ",
              let ruta = try? nucleo.rutaAbsoluta(chat: chat, rutaRelativa: "guardados.jsonl") else { return false }
        let url = URL(fileURLWithPath: ruta)
        let cambio = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let ya = idsPorChat[chat], ya.cuando == cambio { return ya.ids.contains(m.id) }
        let ids = BibliotecaAudio.idsDeMusica(cuaderno: url)
        idsPorChat[chat] = (cambio, ids)
        return ids.contains(m.id)
    }

    /// Las etiquetas de un audio, leidas una vez.
    static func tarjeta(_ url: URL) async -> TarjetaMusica {
        if let ya = tarjetas[url] { return ya }
        let t = await Task.detached(priority: .utility) { await leer(url) }.value
        tarjetas[url] = t
        return t
    }

    nonisolated private static func leer(_ url: URL) async -> TarjetaMusica {
        let asset = AVURLAsset(url: url)
        var t = TarjetaMusica()
        var todos: [AVMetadataItem] = (try? await asset.load(.commonMetadata)) ?? []
        for formato in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            todos += (try? await asset.loadMetadata(for: formato)) ?? []
        }
        func texto(_ clave: AVMetadataKey) async -> String? {
            for item in AVMetadataItem.metadataItems(from: todos, withKey: clave, keySpace: .common) {
                if let s = try? await item.load(.stringValue), !s.trimmingCharacters(in: .whitespaces).isEmpty {
                    return s.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
        t.titulo = await texto(.commonKeyTitle)
        t.artista = await texto(.commonKeyArtist)
        t.album = await texto(.commonKeyAlbumName)
        for item in AVMetadataItem.metadataItems(from: todos, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common) {
            if let d = try? await item.load(.dataValue), let img = NSImage(data: d) {
                t.portada = img
                break
            }
        }
        return t
    }

    /// Los dos colores del degradado de una cancion sin portada: siempre los
    /// mismos para la misma cancion (`degradado_de`, los mismos pares).
    nonisolated static func degradado(_ semilla: String) -> (Color, Color) {
        let pares: [(UInt32, UInt32)] = [
            (0x8e44b8, 0x0a6cd6), (0xc93c35, 0xc77700), (0x1e7a4a, 0x0a6cd6),
            (0x4b49c8, 0x9a3fc4), (0xc77700, 0x8e44b8),
        ]
        let n = semilla.utf8.reduce(UInt32(0)) { $0 &* 31 &+ UInt32($1) }
        let (a, b) = pares[Int(n % UInt32(pares.count))]
        return (hex(a), hex(b))
    }

    nonisolated private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    /// El renglon de debajo: el artista y lo que dura (`detalle`).
    nonisolated static func detalle(artista: String?, tiempo: String) -> String {
        switch (artista, tiempo.isEmpty) {
        case let (a?, true): return a
        case let (a?, false): return "\(a) · \(tiempo)"
        case (nil, _): return tiempo
        }
    }

    /// La linea que suena: la ultima con minuto que ya empezo
    /// (`por_donde_va`).
    nonisolated static func porDondeVa(_ trozos: [(ms: Int64?, texto: String)], ms: Int64) -> Int? {
        var donde: Int?
        for (n, t) in trozos.enumerated() {
            guard let m = t.ms else { continue }
            if m <= ms { donde = n } else { break }
        }
        return donde
    }
}

/// La portada en su caja con las esquinas redondeadas: la imagen recortada
/// al centro o un degradado con la nota encima.
struct PortadaMusica: View {
    let tarjeta: TarjetaMusica
    let semilla: String
    let lado: CGFloat
    let radio: CGFloat

    var body: some View {
        Group {
            if let img = tarjeta.portada {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                let (a, b) = MusicaChat.degradado(semilla)
                LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: lado * 0.45, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}

/// **La tarjeta** de la burbuja de una cancion: la portada de 44, el titulo
/// y el artista con lo que dura, y la pastilla de la letra. Pulsarla la toca.
struct TarjetaCancion: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    let url: URL?
    @ObservedObject private var reproductor = ReproductorVoz.compartido
    @State private var tarjeta = TarjetaMusica()

    private var suena: Bool { reproductor.actual == mensaje.id && reproductor.sonando }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                PortadaMusica(tarjeta: tarjeta, semilla: mensaje.id, lado: 44, radio: 10)
                if suena {
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35)).frame(width: 44, height: 44)
                    Image(systemName: "pause.fill").foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tarjeta.titulo ?? BibliotecaAudio.titulo(de: mensaje))
                    .font(.body.weight(.medium)).lineLimit(1)
                let tiempo = mensaje.duracionMs > 0 ? FormatoVoz.marca(ms: mensaje.duracionMs) : ""
                let abajo = MusicaChat.detalle(artista: tarjeta.artista, tiempo: tiempo)
                if !abajo.isEmpty {
                    Text(abajo).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                if reproductor.actual == mensaje.id {
                    TimelineView(.animation(minimumInterval: 0.25, paused: !suena)) { _ in
                        ProgressView(value: reproductor.fraccion).progressViewStyle(.linear).controlSize(.mini)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                KaraokeVentana.abrir(mensaje: mensaje, chat: chat, url: url, tarjeta: tarjeta, almacen: almacen)
            } label: {
                Image(systemName: "music.note.list").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Letra")
        }
        .frame(width: 300, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let url else { return NSSound.beep() }
            reproductor.alternar(mensaje.id, url: url, titulo: tarjeta.titulo ?? BibliotecaAudio.titulo(de: mensaje))
        }
        .task(id: url) {
            if let url { tarjeta = await MusicaChat.tarjeta(url) }
        }
    }
}

// MARK: - El karaoke

@MainActor
enum KaraokeVentana {
    private static var ventana: NSWindow?

    static func abrir(mensaje: MensajeChat, chat: String, url: URL?, tarjeta: TarjetaMusica, almacen: Almacen) {
        let vista = VistaKaraoke(mensaje: mensaje, url: url, tarjeta: tarjeta, cerrar: { ventana?.close() })
        if let ventana {
            ventana.contentView = NSHostingView(rootView: vista)
            // La vista nueva tampoco se aparta de la barra del titulo.
            VentanaLisa.quitarFranja(ventana)
            ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = tarjeta.titulo ?? "Letra"
        w.contentView = NSHostingView(rootView: vista)
        w.isReleasedWhenClosed = false
        VentanaLisa.vestirEntera(w)
        w.center()
        ventana = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct VistaKaraoke: View {
    let mensaje: MensajeChat
    let url: URL?
    let tarjeta: TarjetaMusica
    let cerrar: () -> Void
    @ObservedObject private var reproductor = ReproductorVoz.compartido
    @AppStorage("musica.tamLetra") private var tam: Double = 22
    /// Hasta cuando manda la mano: mover la letra para 6 s el seguirla.
    @State private var aMano: Date = .distantPast

    private var trozos: [(ms: Int64?, texto: String)] { FormatoVoz.trozos(mensaje.transcripcion ?? "") }
    private var esLaActual: Bool { reproductor.actual == mensaje.id }

    var body: some View {
        VStack(spacing: 0) {
            cabecera
            Divider().opacity(0.4)
            letra
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onExitCommand(perform: cerrar)
    }

    private var cabecera: some View {
        HStack(spacing: 14) {
            PortadaMusica(tarjeta: tarjeta, semilla: mensaje.id, lado: 64, radio: 12)
            VStack(alignment: .leading, spacing: 2) {
                if let t = tarjeta.titulo { Text(t).font(.system(size: 17, weight: .semibold)).lineLimit(1) }
                let abajo = [tarjeta.artista, tarjeta.album].compactMap { $0 }.joined(separator: " · ")
                if !abajo.isEmpty { Text(abajo).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button { tam = max(14, tam - 2) } label: { Text("A").font(.system(size: 12)) }.help("Letra menor")
            Button { tam = min(44, tam + 2) } label: { Text("A").font(.system(size: 18)) }.help("Letra mayor")
            Button(action: alternar) {
                Image(systemName: esLaActual && reproductor.sonando ? "pause.fill" : "play.fill")
            }.disabled(url == nil).help("Escuchar")
            Button(action: cerrar) { Image(systemName: "xmark") }.help("Volver (Esc)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 16))
        .padding(.horizontal, 20)
        .frame(height: 88)
        .padding(.top, 24)
    }

    @ViewBuilder private var letra: some View {
        let trozos = self.trozos
        if trozos.isEmpty {
            VStack(spacing: 8) {
                Text("Esta canción aún no tiene letra")
                Text("Pégala con el lápiz de la letra en el móvil o en Windows").foregroundStyle(.secondary)
            }
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.animation(minimumInterval: 0.2, paused: !(esLaActual && reproductor.sonando))) { _ in
                lineas(trozos)
            }
        }
    }

    private func lineas(_ trozos: [(ms: Int64?, texto: String)]) -> some View {
        let conTiempos = trozos.contains { $0.ms != nil }
        let actual = esLaActual ? MusicaChat.porDondeVa(trozos, ms: reproductor.posicionMs) : nil
        return GeometryReader { geo in
            ScrollViewReader { lector in
                ScrollView {
                    VStack(spacing: 14) {
                        Color.clear.frame(height: geo.size.height / 3)
                        ForEach(trozos.indices, id: \.self) { n in
                            let t = trozos[n]
                            let activa = actual == n
                            Text(t.texto.isEmpty && t.ms != nil ? "♪" : t.texto)
                                .font(.system(size: activa ? tam * 1.15 : tam, weight: activa ? .semibold : .regular))
                                .foregroundStyle(color(n, actual: actual, conTiempos: conTiempos))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 560)
                                .id(n)
                                .contentShape(Rectangle())
                                .onTapGesture { ir(a: t.ms) }
                        }
                        Color.clear.frame(height: geo.size.height * 2 / 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .simultaneousGesture(DragGesture().onChanged { _ in aMano = Date().addingTimeInterval(6) })
                .onScrollPhaseChange { _, fase in
                    if fase == .interacting || fase == .decelerating { aMano = Date().addingTimeInterval(6) }
                }
                .onChange(of: actual) { _, nueva in
                    guard conTiempos, Date() >= aMano else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        lector.scrollTo(nueva ?? 0, anchor: UnitPoint(x: 0.5, y: 1.0 / 3))
                    }
                }
            }
        }
    }

    private func color(_ n: Int, actual: Int?, conTiempos: Bool) -> Color {
        guard conTiempos, let donde = actual else { return .primary }
        if n == donde { return .accentColor }
        return n < donde ? Color.primary.opacity(0.40) : Color.primary.opacity(0.75)
    }

    private func alternar() {
        guard let url else { return NSSound.beep() }
        reproductor.alternar(mensaje.id, url: url, titulo: tarjeta.titulo ?? BibliotecaAudio.titulo(de: mensaje))
    }

    /// Un clic en una linea lleva la cancion ahi (y la arranca).
    private func ir(a ms: Int64?) {
        guard let ms, let url else { return }
        aMano = .distantPast
        if !esLaActual { reproductor.alternar(mensaje.id, url: url, titulo: tarjeta.titulo ?? "") }
        else if !reproductor.sonando { reproductor.seguir() }
        reproductor.saltar(ms: ms - reproductor.posicionMs)
    }
}
