// La ventana del asistente, como el chat «Asistente» de Windows: las
// conversaciones a la izquierda (se vuelve a una y se sigue), las burbujas
// con lo que pensó (plegable), lo que hizo y lo que dibujó (abrirlo en el
// lienzo o guardarlo en «Mensajes guardados»), la pregunta de «¿seguro?»
// con «Sí» y «No», el altavoz de cada respuesta, y la caja con el clip
// (PDF, fotos: también arrastrarlos o pegarlos), el micrófono y enviar o
// parar. Arriba, quién contesta (Claude o DeepSeek; sin su clave, Apple
// Intelligence si está); sin clave, la tarjeta para ponerla, y una vez, la
// de liberar los modelos locales que quedaron bajados.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

public struct VentanaAsistente: View {
    @StateObject private var modelo: ModeloAsistente
    @ObservedObject private var viejos = ModelosViejos.compartidos
    @StateObject private var dictado = DictadoAsistente()
    @State private var texto = ""
    @State private var guardado: UUID?
    @State private var lateral = true
    @State private var encima = false

    public init(almacen: Almacen?) {
        _modelo = StateObject(wrappedValue: ModeloAsistente(almacen: almacen, historial: HistorialAsistente()))
    }

    public var body: some View {
        HStack(spacing: 0) {
            if lateral {
                ListaConversaciones(modelo: modelo)
                    .frame(width: 210)
                Divider()
            }
            VStack(spacing: 0) {
                cabecera
                Divider()
                conversacion
                Divider()
                caja
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .task {
            await modelo.comprobarMotor()
            modelo.prepararDocumentos()
            await viejos.mirar()
        }
        .onDrop(of: [.fileURL], isTargeted: $encima) { proveedores in
            soltar(proveedores)
            return true
        }
        .overlay {
            if encima {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Cabecera

    private var cabecera: some View {
        HStack(spacing: 8) {
            Button { withAnimation { lateral.toggle() } } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help(lateral ? "Ocultar las conversaciones" : "Ver las conversaciones")
            Image(systemName: icono)
                .foregroundStyle(sinClave ? Color.orange : Color.accentColor)
            Text(modelo.motor?.nombre ?? "Buscando motor…")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                Task { await modelo.comprobarMotor() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Volver a mirar quién contesta (tras cambiar los ajustes)")
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Ajustes → Asistente: motor, pensar, claves")
                .simultaneousGesture(TapGesture().onEnded { VentanaAsistente.irAAjustes() })
            Button("Nueva") { modelo.nuevaConversacion() }
                .disabled(modelo.burbujas.isEmpty || modelo.ocupado)
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(8)
        // La ventana va sin franja: sus −, ☐ y ✕ flotan a la derecha.
        .padding(.trailing, BotonesDeVentana.anchoFlotante - 8)
    }

    private var icono: String {
        switch modelo.motor {
        case .nube: return sinClave ? "exclamationmark.triangle" : "cloud"
        case .apple: return "apple.logo"
        default: return "sparkles"
        }
    }

    /// La nube elegida sin su clave (y sin Apple Intelligence que conteste).
    private var sinClave: Bool {
        if case let .nube(_, conClave)? = modelo.motor { return !conClave }
        return false
    }

    /// Tras abrirse la ventana de Ajustes, a su seccion «Asistente».
    static func irAAjustes() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .pixpinIrASeccionAjustes, object: SeccionAjustes.asistente.rawValue)
        }
    }

    // MARK: Burbujas

    private var conversacion: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if modelo.burbujas.isEmpty {
                        vacia
                    }
                    ForEach(modelo.burbujas) { b in
                        BurbujaAsistente(
                            burbuja: b,
                            guardada: guardado == b.id,
                            pregunta: b.id == modelo.burbujas.last?.id ? modelo.pregunta : nil,
                            alGuardar: { abrir in
                                Task { if await modelo.guardarDibujo(b, abrir: abrir) { guardado = b.id } }
                            },
                            alLeer: { modelo.leerEnVoz(b) },
                            alResponder: { modelo.responder($0) },
                            alCitar: { modelo.abrir($0) })
                            .id(b.id)
                    }
                    if modelo.ocupado {
                        HStack {
                            ProgressView().controlSize(.small)
                            if modelo.sePuedeParar {
                                Button("Parar") { modelo.parar() }
                                    .controlSize(.small)
                                    .keyboardShortcut(".", modifiers: .command)
                            }
                        }
                        .padding(.leading, 8).id("pensando")
                    }
                }
                .padding(12)
            }
            .onChange(of: modelo.burbujas.count) { _, _ in
                if let ultima = modelo.burbujas.last?.id {
                    withAnimation { lector.scrollTo(ultima, anchor: .bottom) }
                }
            }
            // La respuesta en vivo crece: se sigue su final (sin animar).
            .onChange(of: modelo.burbujas.last?.texto.count) { _, _ in
                if modelo.ocupado, let ultima = modelo.burbujas.last?.id {
                    lector.scrollTo(ultima, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var vacia: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pregunta algo, pide un dibujo («dibuja una casa con un árbol»), apunta una tarea («recuérdame comprar pan mañana a las 10») o adjunta un PDF y pregunta qué dice.")
                .foregroundStyle(.secondary)
            if case let .nube(nombre, conClave)? = modelo.motor, !conClave {
                TarjetaFaltaClave(nombre: nombre)
            } else if modelo.motor == .apple {
                Text("Contesta Apple Intelligence, en este Mac. Con la clave de Claude o DeepSeek (Ajustes → Asistente) contesta la nube.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TarjetaModelosViejos(viejos: viejos)
        }
        .padding()
    }

    // MARK: La caja

    private var caja: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !modelo.pendientes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(modelo.pendientes) { a in
                            FichaAdjunto(adjunto: a) { modelo.pendientes.removeAll { $0.id == a.id } }
                        }
                    }
                }
            }
            if let aviso = dictado.aviso {
                Text(aviso).font(.caption).foregroundStyle(.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: elegirFicheros) { Image(systemName: "paperclip") }
                    .buttonStyle(.borderless)
                    .help("Adjuntar un PDF o una foto (también se pueden arrastrar o pegar)")
                TextField(dictado.escuchando ? "Te escucho…" : "Escribe al asistente…", text: $texto, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 6)
                    .onSubmit(enviar)
                    .onPasteCommand(of: [.image, .fileURL]) { pegar($0) }
                Button(action: microfono) {
                    Image(systemName: dictado.escuchando ? "mic.fill" : "mic")
                        .foregroundStyle(dictado.escuchando ? Color.red : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(dictado.escuchando ? "Dejar de escuchar" : "Dictar")
                if modelo.sePuedeParar {
                    Button { modelo.parar() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .buttonStyle(.borderless)
                        .help("Parar (⌘.)")
                } else {
                    Button(action: enviar) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.borderless)
                        .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelo.ocupado)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(10)
    }

    private func enviar() {
        let t = texto
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !modelo.ocupado else { return }
        texto = ""
        Task { await modelo.enviar(t) }
    }

    private func microfono() {
        if dictado.escuchando {
            dictado.parar()
            return
        }
        let revisar = modelo.revisarLoDicho
        Task {
            await dictado.empezar(caja: texto, alTexto: { texto = $0 }, alAcabar: { final in
                texto = final
                if !revisar { enviar() }
            })
        }
    }

    private func elegirFicheros() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .plainText]
        panel.message = "El asistente puede leer un PDF o una foto, o calcar un dibujo."
        if panel.runModal() == .OK { modelo.adjuntar(panel.urls) }
    }

    private func soltar(_ proveedores: [NSItemProvider]) {
        for p in proveedores {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { modelo.adjuntar([url]) } }
            }
        }
    }

    private func pegar(_ proveedores: [NSItemProvider]) {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            modelo.adjuntar(urls)
        } else if let img = NSImage(pasteboard: pb) {
            modelo.adjuntar(imagen: img)
        } else if let t = pb.string(forType: .string) {
            texto += t
        }
        _ = proveedores
    }
}

/// Las conversaciones guardadas.
struct ListaConversaciones: View {
    @ObservedObject var modelo: ModeloAsistente

    var body: some View {
        List {
            Section("Conversaciones") {
                if modelo.guardadas.isEmpty {
                    Text("Aún no hay ninguna.").foregroundStyle(.secondary).font(.caption)
                }
                ForEach(modelo.guardadas) { c in
                    Button {
                        modelo.abrir(c)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.rotulo).lineLimit(2)
                            Text(c.cambiada, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(c.id == modelo.conversacion.id ? Color.accentColor.opacity(0.15) : nil)
                    .contextMenu {
                        Button("Borrar la conversación", role: .destructive) { modelo.borrar(c) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// «Falta la clave de la nube» (Windows, `asistente-nube-titulo`), con
/// «Abrir Ajustes».
struct TarjetaFaltaClave: View {
    let nombre: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Falta la clave de la nube", systemImage: "key")
                .font(.headline)
            Text(ModeloAsistente.explicaLaClave(nombre))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink { Text("Abrir Ajustes") }
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(TapGesture().onEnded { VentanaAsistente.irAAjustes() })
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Un adjunto en la caja o en la burbuja.
struct FichaAdjunto: View {
    let adjunto: ModeloAsistente.Adjunto
    var quitar: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: adjunto.esImagen ? "photo" : "doc.text")
            Text(adjunto.nombre).lineLimit(1).truncationMode(.middle)
            if let quitar {
                Button(action: quitar) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .help(adjunto.ruta)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(fileURLWithPath: adjunto.ruta)) }
    }
}

struct BurbujaAsistente: View {
    let burbuja: ModeloAsistente.Burbuja
    let guardada: Bool
    var pregunta: ModeloAsistente.Pregunta?
    let alGuardar: (_ abrir: Bool) -> Void
    var alLeer: () -> Void = {}
    var alResponder: (Bool) -> Void = { _ in }
    var alCitar: (ModeloAsistente.Cita) -> Void = { _ in }

    var body: some View {
        HStack {
            if burbuja.delUsuario { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !burbuja.adjuntos.isEmpty {
                    HStack { ForEach(burbuja.adjuntos) { FichaAdjunto(adjunto: $0) } }
                }
                if !burbuja.pensamiento.isEmpty {
                    DisclosureGroup {
                        Text(burbuja.pensamiento).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } label: {
                        Text(burbuja.segundosPensando.map { "Pensó \(Int($0.rounded())) s" } ?? "Pensando…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let llamando = burbuja.llamando {
                    Label(llamando, systemImage: "wand.and.stars").font(.caption).foregroundStyle(.secondary)
                }
                Text(burbuja.texto.isEmpty ? "…" : burbuja.texto).textSelection(.enabled)
                ForEach(Array(burbuja.herramientas.enumerated()), id: \.offset) { _, h in
                    Label(h.nombre + ": " + h.resumen, systemImage: h.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundStyle(h.ok ? Color.secondary : Color.orange)
                }
                ForEach(burbuja.citas, id: \.numero) { c in
                    Button { alCitar(c) } label: {
                        Label("[\(c.numero)] \(c.titulo)", systemImage: "doc.text.magnifyingglass")
                            .font(.caption).lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .help("Abrir donde lo dice")
                }
                if let pregunta {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pregunta.texto).font(.callout.weight(.semibold))
                        HStack {
                            Button("Sí") { alResponder(true) }.keyboardShortcut(.defaultAction)
                            Button("No") { alResponder(false) }.keyboardShortcut(.cancelAction)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if burbuja.lienzo != nil {
                    HStack {
                        Button("Abrir en el lienzo") { alGuardar(true) }
                            .controlSize(.small)
                        Button(guardada ? "Guardado en Mensajes guardados" : "Guardar en Mensajes guardados") { alGuardar(false) }
                            .controlSize(.small)
                            .disabled(guardada)
                    }
                }
                if !burbuja.delUsuario, !burbuja.esAviso, !burbuja.texto.isEmpty {
                    HStack(spacing: 6) {
                        Button(action: alLeer) { Image(systemName: "speaker.wave.2") }
                            .buttonStyle(.borderless)
                            .help("Leer en voz alta")
                        if !burbuja.motor.isEmpty {
                            Text(burbuja.motor).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(10)
            .background(fondo, in: RoundedRectangle(cornerRadius: 10))
            if !burbuja.delUsuario { Spacer(minLength: 40) }
        }
    }

    private var fondo: Color {
        if burbuja.esAviso { return Color.orange.opacity(0.15) }
        return burbuja.delUsuario ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)
    }
}
