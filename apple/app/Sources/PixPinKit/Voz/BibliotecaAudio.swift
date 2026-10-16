// **La biblioteca de audio**: toda la musica y todas las notas de voz de
// todos los proyectos, juntas (tanda D3). Es `biblioteca_audio.rs` de
// Windows (`BibliotecaDeAudioActivity.kt` del movil), y como alli **no es un
// almacen**: no guarda nada suyo. Es una vista sobre los chats: los mensajes
// `VOZ` con fichero y fuera del buzon, partidos en dos grupos, la musica
// primero (una voz cuyo texto es la letra de una cancion,
// `estadoDelTexto = letra`) y las notas de voz despues; en cada grupo, lo
// mas nuevo arriba.
//
// Un clic (o ↩) suena en el reproductor de la app, con su barra abajo; ⌥↩ o
// «Escuchar en flotante» la manda al reproductor flotante. El titulo va en
// color si ya tiene letra o transcripcion, y apagado si el fichero no esta
// en este Mac (no va a sonar).
//
// Se abre desde el menu de «Mensajes guardados», como en Windows.

import AppKit
import PixPinCore
import SwiftUI

/// Una fila de la biblioteca (`Fila` de Windows).
public struct FilaAudio: Identifiable, Equatable, Sendable {
    public enum Grupo: Equatable, Sendable { case musica, notas }

    /// El `id` del mensaje.
    public var id: String
    public var chat: String
    /// La ruta del mensaje (relativa a la carpeta de su chat).
    public var ruta: String
    public var titulo: String
    public var duracionMs: Int64
    public var grupo: Grupo
    /// Si ya tiene letra o transcripcion.
    public var tieneLetra: Bool
    public var cuando: Int64
    /// El fichero en este Mac; `nil` si no esta (la fila se ve, no suena).
    public var url: URL?

    /// El id en el reproductor: el mensaje en su chat.
    public var clave: String { id }
}

public enum BibliotecaAudio {
    /// El valor de `estadoDelTexto` que marca «esto es musica, y lo escrito
    /// es su letra» (`TEXTO_LETRA`).
    public static let textoLetra = "letra"

    /// **El rotulo de un audio** (`titulo_de_audio`): el nombre del fichero
    /// sin su extension y, si no hay nombre, «Voz» con la fecha.
    public static func titulo(nombre: String, cuando: Int64) -> String {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        if let punto = n.lastIndex(of: "."), punto != n.startIndex {
            return String(n[..<punto])
        }
        if !n.isEmpty { return n }
        let fecha = Date(timeIntervalSince1970: TimeInterval(cuando) / 1000)
        return "Voz · " + fecha.formatted(date: .abbreviated, time: .shortened)
    }

    /// El titulo de un mensaje de voz.
    public static func titulo(de m: MensajeChat) -> String { titulo(nombre: m.nombre, cuando: m.cuando) }

    /// **Las filas de un chat** (`biblioteca`): clase `VOZ`, con ruta y fuera
    /// del buzon. `musica`: los ids con `estadoDelTexto = letra`.
    public static func filas(_ mensajes: [MensajeChat], chat: String, musica: Set<String>) -> [FilaAudio] {
        mensajes.compactMap { m in
            guard m.clase == "VOZ", !m.enBuzon,
                  let ruta = m.ruta?.trimmingCharacters(in: .whitespaces), !ruta.isEmpty else { return nil }
            return FilaAudio(id: m.id, chat: chat, ruta: ruta, titulo: titulo(de: m), duracionMs: max(m.duracionMs, 0),
                             grupo: musica.contains(m.id) ? .musica : .notas,
                             tieneLetra: !(m.transcripcion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                             cuando: m.cuando, url: nil)
        }
    }

    /// El orden de la biblioteca: la musica primero y, en cada grupo, lo mas
    /// nuevo arriba. Estable: dos notas del mismo milisegundo no bailan.
    public static func ordenar(_ filas: [FilaAudio]) -> [FilaAudio] {
        filas.enumerated().sorted { a, b in
            let ga = a.element.grupo == .notas ? 1 : 0, gb = b.element.grupo == .notas ? 1 : 0
            if ga != gb { return ga < gb }
            if a.element.cuando != b.element.cuando { return a.element.cuando > b.element.cuando }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// **Los ids de musica de un chat**: las lineas de su cuaderno
    /// (`guardados.jsonl`) con `estadoDelTexto = letra`. El puente no trae
    /// ese campo; se mira aqui, sin entender mas de cada linea.
    public static func idsDeMusica(cuaderno: URL) -> Set<String> {
        guard let datos = try? Data(contentsOf: cuaderno, options: .mappedIfSafe) else { return [] }
        var ids: Set<String> = []
        let aguja = Data("\"letra\"".utf8)
        for linea in datos.split(separator: UInt8(ascii: "\n")) where linea.range(of: aguja) != nil {
            guard let o = try? JSONSerialization.jsonObject(with: Data(linea)) as? [String: Any],
                  (o["estadoDelTexto"] as? String) == textoLetra, let id = o["id"] as? String else { continue }
            if (o["clase"] as? String).map({ $0 == "VOZ" }) ?? true { ids.insert(id) }
        }
        return ids
    }

    /// **Lee la biblioteca entera**: todos los chats, fuera del hilo
    /// principal. Se lee al abrirla y no se guarda nada.
    public static func leer(_ nucleo: Nucleo) async -> [FilaAudio] {
        await Task.detached(priority: .userInitiated) { () -> [FilaAudio] in
            var todas: [FilaAudio] = []
            for ficha in (try? nucleo.chats()) ?? [] {
                guard let primera = try? nucleo.mensajes(chat: ficha.id, desde: 0, cuantos: 1) else { continue }
                let total = UInt32(min(primera.total, UInt64(UInt32.max)))
                guard total > 0, let pagina = try? nucleo.mensajes(chat: ficha.id, desde: 0, cuantos: total)
                else { continue }
                let cuaderno = (try? nucleo.rutaAbsoluta(chat: ficha.id, rutaRelativa: "guardados.jsonl"))
                    .map { URL(fileURLWithPath: $0) }
                let musica = cuaderno.map(idsDeMusica(cuaderno:)) ?? []
                for var f in filas(pagina.mensajes, chat: ficha.id, musica: musica) {
                    if let r = try? nucleo.rutaAbsoluta(chat: ficha.id, rutaRelativa: f.ruta),
                       FileManager.default.fileExists(atPath: r) {
                        f.url = URL(fileURLWithPath: r)
                    }
                    todas.append(f)
                }
            }
            return ordenar(todas)
        }.value
    }

    // MARK: La ventana

    @MainActor private static var ventana: NSWindow?

    /// Abre la biblioteca (o la trae delante).
    @MainActor
    public static func abrir(almacen: Almacen) {
        if let v = ventana {
            v.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let v = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        v.title = "Biblioteca de audio"
        v.isReleasedWhenClosed = false
        v.contentView = NSHostingView(rootView: VistaBibliotecaAudio(almacen: almacen))
        v.center()
        _ = v.setFrameAutosaveName("PixPinBibliotecaAudio")
        ventana = v
        v.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// La lista de la biblioteca, con la barra de lo que suena abajo.
struct VistaBibliotecaAudio: View {
    let almacen: Almacen
    @ObservedObject private var reproductor = ReproductorVoz.compartido
    @State private var filas: [FilaAudio]?
    @State private var elegida: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filas.map { "\($0.count) audios" } ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Una nota nueva va a «Mensajes guardados», como el pedido
                // «grabar» de Windows sin proyecto.
                Button {
                    guard let g = almacen.chats.first(where: \.esGuardados) else { return NSSound.beep() }
                    MicrofonoFlotante.compartido.alternar(en: g.id, nombre: "Mensajes guardados", almacen: almacen)
                } label: {
                    Label("Grabar", systemImage: "mic")
                }
                .help("Grabar una nota de voz (micrófono flotante)")
                Button { Task { filas = await BibliotecaAudio.leer(almacen.nucleo) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Volver a leer")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if let filas {
                if filas.isEmpty {
                    Spacer()
                    Text("Aún no hay audios: graba una nota de voz en cualquier proyecto")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    lista(filas)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
            BarraReproductor().padding(8)
        }
        .frame(minWidth: 340, minHeight: 300)
        .task { filas = await BibliotecaAudio.leer(almacen.nucleo) }
    }

    private func lista(_ filas: [FilaAudio]) -> some View {
        // Los dos rotulos solo salen cuando hay de las dos cosas.
        let musica = filas.filter { $0.grupo == .musica }
        let conGrupos = !musica.isEmpty && musica.count < filas.count
        return List(selection: $elegida) {
            if conGrupos {
                Section("Música") { ForEach(musica) { fila($0) } }
                Section("Notas de voz") { ForEach(filas.filter { $0.grupo == .notas }) { fila($0) } }
            } else {
                ForEach(filas) { fila($0) }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return, phases: .down) { tecla in
            guard let f = filas.first(where: { $0.id == elegida }) else { return .ignored }
            if tecla.modifiers.contains(.option) { flotante(f) } else { tocar(f) }
            return .handled
        }
        .onKeyPress(.space) {
            guard reproductor.hayAlgo else { return .ignored }
            if reproductor.sonando { reproductor.pausar() } else { reproductor.seguir() }
            return .handled
        }
    }

    private func fila(_ f: FilaAudio) -> some View {
        let suena = reproductor.suena(f.clave)
        return HStack(spacing: 8) {
            Image(systemName: suena ? "pause.fill" : "play.fill")
                .foregroundStyle(suena ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(f.titulo)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(f.url == nil ? Color.secondary : f.tieneLetra ? Color.accentColor : Color.primary)
            Spacer()
            Text(FormatoVoz.marca(ms: f.duracionMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(f.id)
        .onTapGesture(count: 1) {
            elegida = f.id
            tocar(f)
        }
        .help(f.url == nil ? "El fichero no está en este Mac" : "Escuchar (↩) · ⌥↩ en flotante")
        .contextMenu {
            Button("Escuchar") { tocar(f) }.disabled(f.url == nil)
            Button("Escuchar en flotante") { flotante(f) }.disabled(f.url == nil)
            if let url = f.url {
                Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private func tocar(_ f: FilaAudio) {
        guard let url = f.url else { return NSSound.beep() }
        reproductor.alternar(f.clave, url: url, titulo: f.titulo)
    }

    private func flotante(_ f: FilaAudio) {
        guard let url = f.url else { return NSSound.beep() }
        ReproductorFlotante.compartido.abrir([Pista(id: f.clave, url: url, titulo: f.titulo)])
    }
}
