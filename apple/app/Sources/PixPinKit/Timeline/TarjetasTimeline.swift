// La linea de tiempo y sus tarjetas (Hoy, un dia y lo buscado), y la caja
// de apuntar de abajo, como `pintar_linea` y `pintar_caja` de Windows.
//
// Cada tarjeta, al pasar el raton, ensena sus botones: mandar a
// «Momentos», la bombilla de leccion, corregir, compartir y borrar; el
// clic derecho tiene lo mismo. Clic en una foto abre el detalle.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Los momentos de lo elegido («Hoy» o un dia), como una linea de tiempo
/// vertical. En «Hoy» se queda pegada al final (lo nuevo), como un chat.
struct LineaDeMomentos: View {
    @ObservedObject var modelo: ModeloTimeline
    let abrir: (MomentoTimeline, Int) -> Void

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(modelo.momentos, id: \.id) { m in
                        TarjetaMomento(momento: m, modelo: modelo, abrir: abrir).id(m.id)
                    }
                    if modelo.quedanMomentos {
                        ProgressView().frame(maxWidth: .infinity).padding()
                            .task { await modelo.cargarMasMomentos() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: modelo.momentos.last?.id) { _, ultimo in
                guard modelo.eleccion == .hoy, let ultimo else { return }
                withAnimation { lector.scrollTo(ultimo, anchor: .bottom) }
            }
            .onAppear {
                if modelo.eleccion == .hoy, let u = modelo.momentos.last?.id { lector.scrollTo(u, anchor: .bottom) }
            }
        }
        .overlay {
            if modelo.momentos.isEmpty, !modelo.quedanMomentos {
                Text(modelo.eleccion == .hoy
                    ? "Aún no hay nada en las últimas 24 horas.\nEscribe abajo lo que está pasando, o díctalo con el micrófono."
                    : "Ese día no tiene nada apuntado.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Paleta.v2.gris)
            }
        }
    }
}

/// Lo encontrado en todo el timeline, por dias (lo mas nuevo arriba).
struct ResultadosTimeline: View {
    @ObservedObject var modelo: ModeloTimeline
    let abrir: (MomentoTimeline, Int) -> Void

    private var porDias: [(String, [MomentoTimeline])] {
        var out: [(String, [MomentoTimeline])] = []
        for m in modelo.encontrados {
            let d = ModeloTimeline.iso(de: m.cuando)
            if out.last?.0 == d { out[out.count - 1].1.append(m) } else { out.append((d, [m])) }
        }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(porDias, id: \.0) { dia in
                    Section {
                        ForEach(dia.1, id: \.id) { m in
                            TarjetaMomento(momento: m, modelo: modelo, abrir: abrir)
                        }
                    } header: {
                        Button {
                            modelo.consulta = ""
                            Task { await modelo.elegir(.dia(dia.0)) }
                        } label: {
                            Text(ModeloTimeline.rotulo(iso: dia.0).capitalizedPrimera)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Paleta.v2.gris)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Paleta.v2.fondo)
                        }
                        .buttonStyle(.plain)
                        .help("Abrir el día entero")
                    }
                }
            }
            .padding(16)
        }
        .overlay {
            if modelo.encontrados.isEmpty {
                Text("No hay ningún momento con eso.").foregroundStyle(Paleta.v2.gris)
            }
        }
    }
}

/// Un momento: la hora y un punto en la linea, y su tarjeta con el titulo,
/// lo contado, sus fotos, su audio y sus marcas.
struct TarjetaMomento: View {
    let momento: MomentoTimeline
    @ObservedObject var modelo: ModeloTimeline
    let abrir: (MomentoTimeline, Int) -> Void
    @State private var encima = false
    @ObservedObject private var reproductor = ReproductorVoz.compartido

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(momento.hora)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Paleta.v2.gris)
                .frame(width: 48, alignment: .trailing)
                .padding(.top, 14)
            VStack(spacing: 0) {
                Rectangle().fill(Color(hex: 0x3A3A3D)).frame(width: 2, height: 16)
                Circle()
                    .fill(momento.enMomentos ? Paleta.v2.naranja : Paleta.v2.acento)
                    .frame(width: 10, height: 10)
                Rectangle().fill(Color(hex: 0x3A3A3D)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 36)
            tarjeta
                .padding(.bottom, 12)
        }
        .onHover { encima = $0 }
        .contextMenu { MenuMomento(momento: momento, modelo: modelo, abrir: abrir) }
    }

    private var tarjeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(momento.titulo.isEmpty ? "Sin título" : momento.titulo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Paleta.v2.texto)
                    .textSelection(.enabled)
                if momento.leccion != nil {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Paleta.v2.amarillo).help("Lección aprendida")
                }
                if momento.enMomentos {
                    Image(systemName: "bookmark.fill").foregroundStyle(Paleta.v2.naranja).help("En Momentos")
                }
                Spacer(minLength: 0)
            }
            if !momento.descripcion.isEmpty {
                Text(momento.descripcion)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Paleta.v2.cuerpo)
                    .textSelection(.enabled)
            }
            if !momento.fotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(momento.fotos.enumerated()), id: \.offset) { i, ruta in
                            MiniaturaVista(url: URL(fileURLWithPath: ruta), lado: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { abrir(momento, i) }
                                .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: ruta)) ?? NSItemProvider() }
                        }
                    }
                }
            }
            if let audio = momento.audio {
                Button {
                    ReproductorVoz.compartido.alternar(momento.id, url: URL(fileURLWithPath: audio))
                } label: {
                    Label(TarjetaMomento.duracion(momento.duracionMs),
                          systemImage: reproductor.sonando && reproductor.actual == momento.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Paleta.v2.caja, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Paleta.v2.texto)
                .help("Nota de voz")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(encima ? Paleta.v2.tarjetaEncima : Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if modelo.corrigiendo?.id == momento.id {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Paleta.v2.acento, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if encima { botones.padding(8) }
        }
    }

    /// Los botones de la tarjeta, al pasar el raton.
    private var botones: some View {
        HStack(spacing: 2) {
            boton(momento.enMomentos ? "bookmark.fill" : "bookmark",
                  momento.enMomentos ? "Quitar de Momentos" : "Mandar a Momentos") {
                Task { await modelo.alternarMomentos(momento) }
            }
            boton(momento.leccion != nil ? "lightbulb.fill" : "lightbulb", "Lección") {
                Task { await modelo.alternarLeccion(momento) }
            }
            boton("pencil", "Corregir") { Task { await modelo.corregir(momento) } }
            Menu {
                MenuCompartirMomento(momento: momento, modelo: modelo)
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 26)
            .help("Compartir")
            boton("trash", "Borrar") { Task { await modelo.borrar(momento) } }
        }
        .padding(3)
        .background(Paleta.v2.fondo.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
    }

    private func boton(_ icono: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono).font(.system(size: 12))
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Paleta.v2.texto)
        .help(ayuda)
    }

    nonisolated static func duracion(_ ms: Int64) -> String {
        guard ms > 0 else { return "Nota de voz" }
        let s = Int(ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// El clic derecho de un momento: lo mismo que sus botones, y mas.
struct MenuMomento: View {
    let momento: MomentoTimeline
    @ObservedObject var modelo: ModeloTimeline
    let abrir: (MomentoTimeline, Int) -> Void

    var body: some View {
        if !momento.fotos.isEmpty {
            Button("Ver") { abrir(momento, 0) }
        }
        Button(momento.enMomentos ? "Quitar de Momentos" : "Mandar a Momentos") {
            Task { await modelo.alternarMomentos(momento) }
        }
        Button(momento.leccion != nil ? "Quitar la marca de lección" : "Hacer lección 💡") {
            Task { await modelo.alternarLeccion(momento) }
        }
        Button("Corregir") { Task { await modelo.corregir(momento) } }
        Button("Copiar el texto") {
            let t = momento.descripcion.isEmpty ? momento.titulo : "\(momento.titulo)\n\(momento.descripcion)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(t, forType: .string)
        }
        Menu("Compartir") { MenuCompartirMomento(momento: momento, modelo: modelo) }
        Divider()
        Button("Abrir el día") {
            modelo.consulta = ""
            Task { await modelo.elegir(.dia(ModeloTimeline.iso(de: momento.cuando))) }
        }
        Divider()
        Button("Borrar", role: .destructive) { Task { await modelo.borrar(momento) } }
    }
}

/// Compartir un momento como imagen (copiar, guardar, la hoja del Mac) o
/// como pagina web, como el menu de compartir de Windows.
struct MenuCompartirMomento: View {
    let momento: MomentoTimeline
    @ObservedObject var modelo: ModeloTimeline

    var body: some View {
        Button("Copiar como imagen") {
            guard let img = ImagenDeMomento.hacer(momento) else { return modelo.avisar("No se pudo hacer la imagen") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
            modelo.avisar("Copiada como imagen")
        }
        Button("Guardar como imagen…") {
            guard let png = ImagenDeMomento.hacer(momento).flatMap(ImagenDeMomento.png) else {
                return modelo.avisar("No se pudo hacer la imagen")
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "\(momento.id).png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try png.write(to: url); modelo.avisar("Guardado: \(url.lastPathComponent)") } catch {
                modelo.avisar("No se pudo guardar el fichero")
            }
        }
        Button("Compartir como imagen…") {
            guard let png = ImagenDeMomento.hacer(momento).flatMap(ImagenDeMomento.png) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(momento.id).png")
            try? png.write(to: url)
            CompartirMac.mostrar([url])
        }
        Button("Compartir como página web…") {
            Task {
                let nucleo = modelo.nucleo
                let desfase = desfaseLocalMs()
                let iso = ModeloTimeline.iso(de: momento.cuando)
                guard let p = try? await Task.detached(priority: .userInitiated, operation: {
                    try nucleo.timelineExportar(que: .dias(isos: [iso]), desfaseMs: desfase)
                }).value else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(p.nombre).html")
                try? p.html.write(to: url, atomically: true, encoding: .utf8)
                CompartirMac.mostrar([url])
            }
        }
    }
}

/// La hoja de compartir del sistema, junto al raton.
@MainActor
enum CompartirMac {
    static func mostrar(_ urls: [URL]) {
        guard let ventana = NSApp.keyWindow, let vista = ventana.contentView else { return }
        let p = ventana.mouseLocationOutsideOfEventStream
        let r = NSRect(x: p.x, y: p.y, width: 1, height: 1)
        NSSharingServicePicker(items: urls).show(relativeTo: vista.convert(r, from: nil), of: vista, preferredEdge: .minY)
    }
}

/// La tarjeta de un momento hecha imagen (para compartirla): fecha arriba,
/// el titulo, el texto y su primera foto.
@MainActor
enum ImagenDeMomento {
    static func hacer(_ m: MomentoTimeline) -> NSImage? {
        let vista = VStack(alignment: .leading, spacing: 10) {
            Text(fechaDe(ms: m.cuando).formatted(date: .long, time: .shortened))
                .font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
            Text(m.titulo).font(.system(size: 20, weight: .bold)).foregroundStyle(Paleta.v2.texto)
            if !m.descripcion.isEmpty {
                Text(m.descripcion).font(.system(size: 15)).foregroundStyle(Paleta.v2.cuerpo)
            }
            if let f = m.fotos.first, let img = NSImage(contentsOfFile: f) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("PixPin Max · Timeline").font(.system(size: 11)).foregroundStyle(Paleta.v2.gris)
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .background(Paleta.v2.tarjeta)
        let r = ImageRenderer(content: vista)
        r.scale = 2
        return r.nsImage
    }

    static func png(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - La caja de apuntar

/// La caja de «Hoy», como la de un chat: las fotos que esperan, lo que se
/// corrige, el campo y los botones de foto, microfono y apuntar.
struct CajaTimeline: View {
    @ObservedObject var modelo: ModeloTimeline
    @ObservedObject var dictado: DictadoTimeline
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = modelo.corrigiendo {
                HStack {
                    Image(systemName: "pencil").foregroundStyle(Paleta.v2.acento)
                    Text("Corrigiendo el momento de las \(c.hora) · ↩ guarda, Esc cancela")
                        .font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
                    Spacer()
                    Button { modelo.vaciarCaja() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Paleta.v2.gris)
                }
            }
            if let t = dictado.rotulo {
                Text(t).font(.system(size: 12)).foregroundStyle(dictado.grabando ? Paleta.v2.rojo : Paleta.v2.gris)
            }
            if !modelo.pegadas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(modelo.pegadas.enumerated()), id: \.offset) { i, p in
                            MiniaturaVista(url: URL(fileURLWithPath: p.ruta), lado: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button { modelo.quitarPegada(i) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                botonRedondo("photo", "Añadir una foto") { elegirFotos() }
                TextField("", text: $modelo.texto,
                          prompt: Text("¿Qué está pasando? Escribe o dicta…").foregroundStyle(Paleta.v2.gris),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Paleta.v2.texto)
                    .lineLimit(1...6)
                    .focused($foco)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x2A2A2D), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(foco ? Paleta.v2.acento : Color.white.opacity(0.1)))
                    .onKeyPress(keys: [.return]) { k in
                        if k.modifiers.contains(.shift) || k.modifiers.contains(.option) { return .ignored }
                        Task { await modelo.enviar(audio: dictado.tomarPendiente()) }
                        return .handled
                    }
                    .onKeyPress(keys: [.upArrow]) { _ in
                        guard modelo.texto.isEmpty, modelo.corrigiendo == nil else { return .ignored }
                        Task { await modelo.corregirElUltimo() }
                        return .handled
                    }
                    .onKeyPress(keys: [KeyEquivalent("v")]) { k in
                        guard k.modifiers == .command, pegarImagen() else { return .ignored }
                        return .handled
                    }
                botonRedondo(dictado.grabando ? "stop.fill" : "mic", dictado.grabando ? "Terminar (⌘⇧M)" : "Dictar (⌘⇧M)",
                             rojo: dictado.grabando) {
                    Task { await dictado.pulsar(modelo: modelo) }
                }
                if !modelo.texto.isEmpty || !modelo.pegadas.isEmpty {
                    botonRedondo("arrow.up", modelo.corrigiendo == nil ? "Apuntar (↩)" : "Guardar (↩)", lleno: true) {
                        Task { await modelo.enviar(audio: dictado.tomarPendiente()) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Paleta.v2.fondo)
        .overlay(alignment: .top) { Paleta.v2.linea.frame(height: 1) }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { proveedores in
            soltar(proveedores)
            return true
        }
        .onAppear { foco = true }
        .onChange(of: modelo.corrigiendo?.id) { _, _ in foco = true }
    }

    private func botonRedondo(_ icono: String, _ ayuda: String, lleno: Bool = false, rojo: Bool = false,
                              _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono).font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(lleno || rojo ? Color.white : Paleta.v2.texto)
                .background(rojo ? Paleta.v2.rojo : lleno ? Paleta.v2.acento : Paleta.v2.caja, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }

    private func elegirFotos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for u in panel.urls { modelo.anadirFoto(u, temporal: false) }
    }

    /// ⌘V con una imagen (o ficheros de imagen) en el portapapeles: a la
    /// caja como foto. Con texto, lo pega el campo.
    private func pegarImagen() -> Bool {
        let tablero = NSPasteboard.general
        if let urls = tablero.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let imagenes = urls.filter { (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image)) == true }
            if !imagenes.isEmpty {
                for u in imagenes { modelo.anadirFoto(u, temporal: false) }
                return true
            }
        }
        guard tablero.string(forType: .string) == nil,
              let img = NSImage(pasteboard: tablero), let png = ImagenDeMomento.png(img) else { return false }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-timeline-pegada-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else {
            modelo.avisar("Eso no es una imagen ni un texto")
            return true
        }
        modelo.anadirFoto(url, temporal: true)
        return true
    }

    private func soltar(_ proveedores: [NSItemProvider]) {
        for p in proveedores {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) == true else { return }
                Task { @MainActor in modelo.anadirFoto(url, temporal: false) }
            }
        }
    }
}
