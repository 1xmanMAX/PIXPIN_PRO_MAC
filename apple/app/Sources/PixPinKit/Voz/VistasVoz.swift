// Las vistas de las notas de voz: la burbuja `VOZ` (reproducir, la onda con
// su avance, la duracion y lo que se dijo), el boton del microfono de la
// caja de escribir y la barra de lo que suena (D3), que es la del movil
// (`BarraDelReproductor.kt`) y la de Windows: atras 10, play o pausa,
// adelante 10, la velocidad en ciclo, el titulo con el tiempo, el aspa y la
// linea de avance, que se pincha o se arrastra para ir a un punto.

import AppKit
import PixPinCore
import SwiftUI

struct BurbujaVoz: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @ObservedObject private var reproductor = ReproductorVoz.compartido
    @State private var url: URL?
    @State private var transcribiendo = false

    private var esLaActual: Bool { reproductor.actual == mensaje.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: alternar) {
                    Image(systemName: esLaActual && reproductor.sonando ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .disabled(url == nil)
                .help(esLaActual && reproductor.sonando ? "Pausa" : "Escuchar")

                Group {
                    if esLaActual && reproductor.sonando {
                        // Solo la que suena se repinta mientras suena.
                        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { _ in
                            onda(avance: reproductor.fraccion)
                        }
                    } else {
                        onda(avance: esLaActual ? reproductor.fraccion : 0)
                    }
                }
                .frame(width: 180, height: 28)

                Text(FormatoVoz.marca(ms: mensaje.duracionMs))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                // Pasar a texto, a la vista (como Windows y el movil): sin
                // texto todavia, o para volver a pasarlo.
                if url != nil {
                    Button(action: transcribir) {
                        if transcribiendo {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "captions.bubble").font(.system(size: 15))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(transcribiendo)
                    .help(mensaje.transcripcion?.isEmpty == false ? "Volver a pasar a texto (T)" : "Pasar a texto (T)")
                }
            }
            texto
        }
        .frame(maxWidth: 360, alignment: .leading)
        .contextMenu {
            // Con texto es VOLVER a pasarlo, como en Windows; T con el menu
            // abierto.
            EntradasDeMensaje {
                if url != nil {
                    Button(action: transcribir) {
                        Label(mensaje.transcripcion?.isEmpty == false ? "Volver a pasar a texto" : "Pasar a texto",
                              systemImage: "captions.bubble")
                    }
                    .keyboardShortcut("t", modifiers: [])
                    .disabled(transcribiendo)
                }
                if let url {
                    Button {
                        ReproductorFlotante.compartido.abrir([Pista(id: mensaje.id, url: url,
                                                                    titulo: BibliotecaAudio.titulo(de: mensaje))])
                    } label: {
                        Label("Escuchar en flotante", systemImage: "pip")
                    }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Label("Mostrar en el Finder", systemImage: "folder")
                    }
                }
            }
        }
        .task(id: mensaje.id) {
            guard let ruta = mensaje.ruta else { return }
            if let u = await almacen.url(deRuta: ruta, en: chat), FileManager.default.fileExists(atPath: u.path) {
                url = u
            }
        }
    }

    /// Lo que se dijo, en parrafos y sin los `[m:ss]` dentro del texto.
    @ViewBuilder private var texto: some View {
        let trozos = FormatoVoz.trozos(mensaje.transcripcion ?? "")
        if !trozos.isEmpty {
            Text(trozos.map { $0.texto }.joined(separator: "\n\n"))
                .textSelection(.enabled)
        } else if transcribiendo {
            ProgressView().controlSize(.small)
        } else if !mensaje.texto.isEmpty {
            Text(mensaje.texto).textSelection(.enabled)
        }
    }

    /// La onda de los picos (normalizada contra el maximo de la nota, como
    /// `barras_de_onda` de Windows) con lo ya escuchado en color.
    private func onda(avance: Double) -> some View {
        let picos = mensaje.picos
        return Canvas { ctx, tam in
            let barras = max(min(picos.count, Int(tam.width / 3)), 1)
            let maximo = max(Double(picos.max() ?? 0), 1)
            let ancho = tam.width / CGFloat(barras)
            for i in 0..<barras {
                let valor: Double
                if picos.isEmpty {
                    valor = 0.15
                } else {
                    // Cada barra, el maximo de su tramo de picos.
                    let a = i * picos.count / barras
                    let b = max((i + 1) * picos.count / barras, a + 1)
                    valor = Double(picos[a..<min(b, picos.count)].max() ?? 0) / maximo
                }
                let alto = max(CGFloat(valor) * tam.height, 2)
                let rect = CGRect(x: CGFloat(i) * ancho, y: (tam.height - alto) / 2,
                                  width: max(ancho - 1, 1), height: alto)
                let hecho = (Double(i) + 0.5) / Double(barras) <= avance
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                         with: .color(hecho ? Color.accentColor : Color.secondary.opacity(0.5)))
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { toque in
            guard esLaActual else { return }
            reproductor.saltar(mensaje.id, a: Double(toque.location.x / 180))
        })
    }

    private func alternar() {
        guard let url else { return NSSound.beep() }
        reproductor.alternar(mensaje.id, url: url, titulo: BibliotecaAudio.titulo(de: mensaje))
    }

    private func transcribir() {
        guard !transcribiendo else { return }
        transcribiendo = true
        Task {
            await almacen.transcribir(mensaje, en: chat)
            transcribiendo = false
        }
    }
}

/// El boton del microfono de la caja de escribir: un toque graba, otro para
/// y la nota va a este chat. Mientras graba, rojo y con el tiempo.
struct BotonVoz: View {
    let chat: String
    let almacen: Almacen
    @ObservedObject private var grabadora = GrabadoraVoz.compartida

    var body: some View {
        HStack(spacing: 4) {
            if case let .grabando(c, desde) = grabadora.estado, c == chat {
                TimelineView(.periodic(from: desde, by: 1)) { contexto in
                    Text(FormatoVoz.marca(ms: Int64(contexto.date.timeIntervalSince(desde) * 1000)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.red)
                }
            } else if grabadora.estado == .guardando || grabadora.estado == .transcribiendo {
                ProgressView().controlSize(.small)
            }
            Button {
                grabadora.alternar(en: chat, almacen: almacen)
            } label: {
                Image(systemName: grabadora.grabando(en: chat) ? "stop.circle.fill" : "mic")
                    .foregroundStyle(grabadora.grabando(en: chat) ? Color.red : Color.primary)
            }
            .buttonStyle(.borderless)
            .help(grabadora.grabando(en: chat) ? "Parar y mandar la nota de voz" : "Grabar una nota de voz")
            .disabled(ocupadaEnOtro)
            .contextMenu {
                Button("Grabar en flotante") {
                    let nombre = almacen.chats.first { $0.id == chat }?.nombre ?? ""
                    MicrofonoFlotante.compartido.alternar(en: chat, nombre: nombre, almacen: almacen)
                }
                .disabled(grabadora.estado != .quieta)
            }
        }
    }

    /// Grabando en otro chat, o guardando: este boton espera.
    private var ocupadaEnOtro: Bool {
        switch grabadora.estado {
        case .quieta: false
        case let .grabando(c, _): c != chat
        case .guardando, .transcribiendo: true
        }
    }
}

/// **La barra de lo que suena**: sale solo si hay algo cargado. Va encima de
/// la caja de escribir del chat, abajo en la biblioteca y en el reproductor
/// flotante.
struct BarraReproductor: View {
    @ObservedObject private var r = ReproductorVoz.compartido
    /// Sin el aspa (el flotante tiene la suya).
    var conCerrar = true

    var body: some View {
        if r.hayAlgo {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    boton("gobackward.10", "Atrás 10 s") { r.atras() }
                    boton(r.sonando ? "pause.fill" : "play.fill", r.sonando ? "Pausa" : "Escuchar") {
                        if r.sonando { r.pausar() } else { r.seguir() }
                    }
                    boton("goforward.10", "Adelante 10 s") { r.adelante() }
                    // La velocidad se escribe: «1,5×» dice mas que un icono.
                    Button { r.otraVelocidad() } label: {
                        Text(VozAlta.rotulo(r.velocidad))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 40, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Velocidad")
                    Text(r.titulo)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                    TiempoReproductor()
                    if !r.cola.isEmpty {
                        Text("+\(r.cola.count)").font(.caption2).foregroundStyle(.secondary)
                            .help("En la fila")
                    }
                    if conCerrar { boton("xmark", "Cerrar") { r.parar() } }
                }
                PistaAvance()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func boton(_ simbolo: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 14)).frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }
}

/// «0:07 / 1:24», al dia mientras suena.
struct TiempoReproductor: View {
    @ObservedObject private var r = ReproductorVoz.compartido

    var body: some View {
        Group {
            if r.sonando {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in Text(texto) }
            } else {
                Text(texto)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var texto: String { "\(FormatoVoz.marca(ms: r.posicionMs)) / \(FormatoVoz.marca(ms: r.duracionMs))" }
}

/// La linea de avance con su bolita: pinchar o arrastrar va a ese punto.
struct PistaAvance: View {
    @ObservedObject private var r = ReproductorVoz.compartido

    var body: some View {
        GeometryReader { g in
            Group {
                if r.sonando {
                    TimelineView(.animation(minimumInterval: 0.1, paused: false)) { _ in linea(g.size.width) }
                } else {
                    linea(g.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                r.irA(fraccion: Double(v.location.x / max(g.size.width, 1)))
            })
        }
        .frame(height: 10)
        .help("Ir a un punto")
    }

    private func linea(_ ancho: CGFloat) -> some View {
        let f = CGFloat(r.fraccion)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(height: 3)
            Capsule().fill(Color.accentColor).frame(width: max(ancho * f, 0), height: 3)
            Circle().fill(Color.accentColor).frame(width: 9, height: 9).offset(x: max(ancho * f - 4.5, 0))
        }
        .frame(height: 10)
    }
}
