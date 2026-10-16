// La ventana de la galeria: la barra comun con el buscador, la rejilla por
// dias, la barra de las elegidas abajo y el aviso con «Deshacer».
//
// Las teclas son las de Windows (`tecla` de `galeria_capturas.rs`), con ⌘
// donde alli va Ctrl: flechas mueven el foco, Inicio/Fin, Espacio elige,
// ↩ pinea, ⌫ borra, ⌘C copia, ⌘S conserva, ⌘A elige todas, ⌘Z deshace,
// ⌘Y vista rapida, Esc va por capas (soltar la eleccion, vaciar lo buscado,
// cerrar) y escribir una letra va al buscador.

import AppKit
import PixPinCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

public struct VentanaGaleria: View {
    @StateObject private var modelo: ModeloGaleria
    /// Los proyectos, para «Mandar a un proyecto» (sin observarlo: cada
    /// mensaje nuevo repintaria la rejilla).
    private let proyectos: Almacen
    /// Elegir varias: con el modo puesto, un clic marca.
    @State private var eligiendo = false
    @State private var elegidas: Set<String> = []
    /// La captura con el foco del teclado (solo tras un clic o una flecha).
    @State private var foco: String?
    @State private var vistaRapida: URL?
    @State private var columnas = 4
    @FocusState private var enLaRejilla: Bool

    public init(almacen: Almacen) {
        _modelo = StateObject(wrappedValue: ModeloGaleria(almacen: almacen))
        proyectos = almacen
    }

    public var body: some View {
        VStack(spacing: 0) {
            Cabecera("Capturas", subtitulo: subtitulo,
                     buscador: BuscadorCabecera($modelo.consulta, pista: "Buscar, también el texto de las capturas")) {
                BotonCabecera(icono: "checkmark.circle", rotulo: "Seleccionar", activo: eligiendo) {
                    eligiendo.toggle()
                    if !eligiendo { elegidas = [] }
                }
                BotonCabecera(icono: "folder", rotulo: "Abrir carpeta") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: modelo.almacen.nucleo.carpetaCapturas(), isDirectory: true))
                }
            }
            rejilla
        }
        .ventanaConCabecera()
        .frame(minWidth: 600, minHeight: 440)
        .onChange(of: modelo.consulta) { _, _ in modelo.consultaCambiada() }
    }

    /// «25 capturas · duran 7 días», como el subtitulo de Windows.
    private var subtitulo: String {
        let n = modelo.enLaCarpeta
        let cuantas = n == 1 ? "1 captura" : "\(n) capturas"
        let dias = AjusteCaducidad.dias
        return dias > 0 ? "\(cuantas) · duran \(dias) días" : cuantas
    }

    /// Las de la vista en el orden en que se ven.
    private var orden: [CapturaGaleria] { modelo.capturas }

    /// A lo que se aplica una accion: las elegidas o, sin eleccion, la del
    /// foco (`objetivos` de Windows).
    private var objetivos: [String] {
        if !elegidas.isEmpty { return orden.map(\.nombre).filter { elegidas.contains($0) } }
        return foco.map { [$0] } ?? []
    }

    private var rejilla: some View {
        GeometryReader { geo in
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(modelo.grupos) { g in
                            Section {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnas),
                                          spacing: 12) {
                                    ForEach(g.capturas, id: \.nombre) { c in
                                        celda(c).id(c.nombre)
                                    }
                                }
                                .padding(.bottom, 16)
                            } header: {
                                cabeceraDelDia(g)
                            }
                        }
                        if modelo.quedanMas {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                                .task { await modelo.cargarMas() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, elegidas.isEmpty ? 20 : 96)
                }
                .onChange(of: foco) { _, f in
                    if let f { withAnimation(.easeOut(duration: 0.12)) { lector.scrollTo(f) } }
                }
            }
            .onAppear { columnas = ModeloGaleria.columnas(ancho: geo.size.width) }
            .onChange(of: geo.size.width) { _, w in columnas = ModeloGaleria.columnas(ancho: w) }
        }
        .focusable()
        .focused($enLaRejilla)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { tecla($0) }
        .overlay { vacia }
        .overlay(alignment: .bottom) { abajo }
        .quickLookPreview($vistaRapida, in: modelo.capturas.map { modelo.url(de: $0) })
        .background { atajos }
        .task {
            await modelo.recargar()
            modelo.vigilar()
            enLaRejilla = true
        }
        .onDisappear { modelo.dejarDeVigilar() }
    }

    private func celda(_ c: CapturaGaleria) -> some View {
        CeldaCaptura(captura: c, elegida: elegidas.contains(c.nombre), conFoco: foco == c.nombre,
                     eligiendo: eligiendo, menu: { AnyView(menu(para: c)) })
            .onTapGesture(count: 2) { NSWorkspace.shared.open(modelo.url(de: c)) }
            .onTapGesture { clic(c.nombre) }
            .contextMenu { menu(para: c) }
            .onDrag { NSItemProvider(contentsOf: modelo.url(de: c)) ?? NSItemProvider() }
    }

    /// «Hoy · jueves 15 oct · 3 capturas» y «Elegir todo el día».
    private func cabeceraDelDia(_ g: ModeloGaleria.Grupo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ModeloGaleria.rotulo(g.fecha).capitalizedPrimera)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.v2.texto)
            Text(g.capturas.count == 1 ? "1 captura" : "\(g.capturas.count) capturas")
                .font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
            Spacer()
            Button(g.capturas.allSatisfy { elegidas.contains($0.nombre) } ? "Soltar el día" : "Elegir todo el día") {
                elegirDia(g)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Paleta.v2.acento)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Paleta.v2.fondo)
    }

    @ViewBuilder
    private var vacia: some View {
        if modelo.capturas.isEmpty, !modelo.quedanMas {
            VStack(spacing: 10) {
                Image(systemName: modelo.consulta.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass")
                    .font(.system(size: 36)).foregroundStyle(Paleta.v2.gris)
                Text(modelo.consulta.isEmpty
                    ? "Todavía no hay capturas. Las que guardes aparecerán aquí y se borran solas a los \(AjusteCaducidad.dias) días, salvo las que conservas."
                    : "Ninguna captura con «\(modelo.consulta)».")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Paleta.v2.gris)
                    .frame(maxWidth: 380)
            }
        }
    }

    /// Abajo: la barra de las elegidas (o el aviso, encima).
    private var abajo: some View {
        VStack(spacing: 8) {
            if let t = modelo.error ?? modelo.aviso {
                HStack(spacing: 12) {
                    Text(t).font(.system(size: 13)).foregroundStyle(Paleta.v2.texto)
                    if !modelo.ultimoBorrado.isEmpty, modelo.error == nil {
                        Button("Deshacer") { Task { await modelo.deshacer() } }
                            .buttonStyle(.plain).foregroundStyle(Paleta.v2.acento)
                        Chapa(texto: "⌘Z")
                    }
                }
                .padding(.horizontal, 16).frame(height: 40)
                .background(modelo.error != nil ? Paleta.v2.rojo.opacity(0.3) : Paleta.v2.tarjetaEncima, in: Capsule())
            }
            if !elegidas.isEmpty { barraDeElegidas }
        }
        .padding(.bottom, 16)
    }

    /// La barra de las elegidas (`barra_de_elegidas` de Windows).
    private var barraDeElegidas: some View {
        HStack(spacing: 8) {
            Text(elegidas.count == 1 ? "1 elegida" : "\(elegidas.count) elegidas")
                .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Paleta.v2.texto)
                .padding(.horizontal, 8)
            Button("Todas") { elegirTodas() }.buttonStyle(.plain).foregroundStyle(Paleta.v2.acento)
            Divider().frame(height: 24)
            BotonCabecera(icono: "pin", rotulo: "Pinear") { pinear(objetivos) }
            BotonCabecera(icono: "doc.on.doc", rotulo: "Copiar") { copiar(objetivos) }
            BotonCabecera(icono: "square.and.arrow.down", rotulo: "Guardar como") { guardarComo(objetivos) }
            BotonCabecera(icono: "checkmark.seal", rotulo: "Conservar") { conservar(objetivos) }
            BotonCabecera(icono: "trash", rotulo: "Borrar") { borrar(objetivos) }
            BotonCabecera(icono: "xmark", ayuda: "Soltar (Esc)", tenue: true) { soltarEleccion() }
        }
        .padding(8)
        .background(Paleta.v2.tarjetaEncima, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    /// Los atajos con ⌘ (los que el sistema reparte a los botones).
    private var atajos: some View {
        ZStack {
            Button("") { if let n = objetivos.first, let c = modelo.capturas.first(where: { $0.nombre == n }) {
                vistaRapida = modelo.url(de: c)
            } }
            .keyboardShortcut("y")
            Button("") { Task { await modelo.deshacer() } }
                .keyboardShortcut("z")
                .disabled(modelo.ultimoBorrado.isEmpty)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: El menu

    /// El clic derecho (`menu_de_captura`): sobre una elegida, vale para
    /// todas las elegidas.
    @ViewBuilder
    private func menu(para c: CapturaGaleria) -> some View {
        let nombres = elegidas.contains(c.nombre) ? objetivos : [c.nombre]
        let varias = nombres.count > 1
        Button(varias ? "Pinear \(nombres.count)" : "Pinear") { pinear(nombres) }
        Button("Copiar") { copiar(nombres) }
        Button("Compartir…") { CompartirMac.mostrar(urls(nombres)) }
        Button("Guardar como…") { guardarComo(nombres) }
        Menu("Mandar a un proyecto") {
            ForEach(proyectos.chats, id: \.id) { chat in
                Button(chat.nombre) { mandar(nombres, a: chat) }
            }
        }
        if !varias, !c.esVideo {
            Button("Anotar en un lienzo") {
                AnotarEnLienzo.abrir(modelo.url(de: c), titulo: c.nombre, almacen: modelo.almacen)
            }
        }
        Button("Vista rápida") { vistaRapida = modelo.url(de: c) }
        Button("Abrir") { NSWorkspace.shared.open(modelo.url(de: c)) }
        Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls(nombres)) }
        let caducan = modelo.capturas.contains { nombres.contains($0.nombre) && $0.seVa != nil }
        if caducan {
            Divider()
            Button("Conservar") { conservar(nombres) }
            Button("Dar 7 días más") { prorrogar(nombres) }
        }
        Divider()
        Button("Borrar", role: .destructive) { borrar(nombres) }
    }

    // MARK: Elegir

    private func clic(_ nombre: String) {
        enLaRejilla = true
        foco = nombre
        if eligiendo || NSEvent.modifierFlags.contains(.command) {
            marcar(nombre)
        } else if NSEvent.modifierFlags.contains(.shift), let desde = elegidas.first ?? foco {
            elegirTramo(desde: desde, hasta: nombre)
        }
    }

    private func marcar(_ nombre: String) {
        if elegidas.contains(nombre) { elegidas.remove(nombre) } else { elegidas.insert(nombre) }
        eligiendo = true
    }

    private func elegirTramo(desde: String, hasta: String) {
        let nombres = orden.map(\.nombre)
        guard let a = nombres.firstIndex(of: desde), let b = nombres.firstIndex(of: hasta) else { return }
        elegidas.formUnion(nombres[min(a, b)...max(a, b)])
        eligiendo = true
    }

    private func elegirDia(_ g: ModeloGaleria.Grupo) {
        let del = Set(g.capturas.map(\.nombre))
        if del.isSubset(of: elegidas) { elegidas.subtract(del) } else { elegidas.formUnion(del) }
        eligiendo = true
    }

    /// ⌘A: todas las que se ven; si ya estaban, las suelta.
    private func elegirTodas() {
        let todas = Set(orden.map(\.nombre))
        if todas.isSubset(of: elegidas) { elegidas = [] } else { elegidas = todas }
        eligiendo = true
    }

    private func soltarEleccion() {
        elegidas = []
        eligiendo = false
    }

    // MARK: Teclado

    private func tecla(_ k: KeyPress) -> KeyPress.Result {
        let nombres = orden.map(\.nombre)
        let i = foco.flatMap { nombres.firstIndex(of: $0) }
        func ir(_ j: Int) {
            guard !nombres.isEmpty else { return }
            foco = nombres[max(0, min(nombres.count - 1, j))]
        }
        let cmd = k.modifiers.contains(.command)
        switch k.key {
        case .leftArrow: ir((i ?? 1) - 1)
        case .rightArrow: ir(i.map { $0 + 1 } ?? 0)
        case .upArrow: ir(i.map { $0 - columnas } ?? 0)
        case .downArrow: ir(i.map { $0 + columnas } ?? 0)
        case .home: ir(0)
        case .end: ir(nombres.count - 1)
        case .space where !cmd:
            if let f = foco { marcar(f) }
        case .return: pinear(objetivos)
        case .delete, .deleteForward: borrar(objetivos)
        case .escape:
            if eligiendo || !elegidas.isEmpty {
                soltarEleccion()
            } else if !modelo.consulta.isEmpty {
                modelo.consulta = ""
            } else {
                NSApp.keyWindow?.performClose(nil)
            }
        default:
            if cmd {
                switch k.characters {
                case "c": copiar(objetivos)
                case "s": conservar(objetivos)
                case "a": elegirTodas()
                default: return .ignored
                }
                return .handled
            }
            // Una letra con el foco en la rejilla va al buscador.
            guard k.modifiers.subtracting(.shift).isEmpty, let ch = k.characters.first,
                  !ch.isWhitespace, !ch.isNewline, ch.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return .ignored }
            modelo.consulta += k.characters
            return .handled
        }
        return .handled
    }

    // MARK: Acciones

    private func urls(_ nombres: [String]) -> [URL] {
        nombres.compactMap { n in modelo.capturas.first { $0.nombre == n }.map(modelo.url(de:)) }
    }

    private func pinear(_ nombres: [String]) {
        let v = urls(nombres)
        guard !v.isEmpty else { return }
        let hechas = v.filter { GestorPines.compartido.pinear(fichero: $0) }.count
        modelo.avisar(hechas == 0 ? "No se pudo pinear" : hechas == 1 ? "Pineada" : "\(hechas) pineadas en la pantalla")
    }

    /// Una imagen sola, como imagen (se pega en cualquier sitio); varias (o
    /// un video), como ficheros.
    private func copiar(_ nombres: [String]) {
        let v = urls(nombres)
        guard !v.isEmpty else { return }
        let tablero = NSPasteboard.general
        tablero.clearContents()
        var objetos: [NSPasteboardWriting] = v.map { $0 as NSURL }
        if v.count == 1, let c = modelo.capturas.first(where: { $0.nombre == nombres[0] }), !c.esVideo,
           let imagen = NSImage(contentsOf: v[0]) {
            objetos.insert(imagen, at: 0)
        }
        tablero.writeObjects(objetos)
        modelo.avisar(v.count == 1 ? "Copiada al portapapeles" : "\(v.count) copiadas como archivos")
    }

    /// «Guardar como…»: una, con su nombre; varias, a una carpeta.
    private func guardarComo(_ nombres: [String]) {
        let v = urls(nombres)
        guard !v.isEmpty else { return }
        var copiadas = 0
        if v.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = v[0].lastPathComponent
            if let t = UTType(filenameExtension: v[0].pathExtension) { panel.allowedContentTypes = [t] }
            guard panel.runModal() == .OK, let destino = panel.url else { return }
            try? FileManager.default.removeItem(at: destino)
            if (try? FileManager.default.copyItem(at: v[0], to: destino)) != nil { copiadas = 1 }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Guardar aquí"
            guard panel.runModal() == .OK, let carpeta = panel.url else { return }
            for u in v {
                let destino = ModeloGaleria.libre(carpeta.appendingPathComponent(u.lastPathComponent))
                if (try? FileManager.default.copyItem(at: u, to: destino)) != nil { copiadas += 1 }
            }
        }
        modelo.avisar(copiadas == 0 ? "No se pudo guardar" : copiadas == 1 ? "1 guardada" : "\(copiadas) guardadas")
    }

    private func mandar(_ nombres: [String], a chat: FichaChat) {
        let v = urls(nombres)
        Task {
            let m = await proyectos.adjuntar(urls: v, en: chat.id)
            modelo.avisar(m.isEmpty ? "No se pudo mandar" : "Mandada\(m.count == 1 ? "" : "s") a «\(chat.nombre)»")
        }
    }

    private func conservar(_ nombres: [String]) {
        guard !nombres.isEmpty else { return }
        Task { await modelo.conservar(nombres) }
    }

    private func prorrogar(_ nombres: [String]) {
        Task { await modelo.prorrogar(nombres) }
    }

    private func borrar(_ nombres: [String]) {
        guard !nombres.isEmpty else { return }
        // El foco pasa a la de al lado, para seguir borrando con ⌫.
        let todas = orden.map(\.nombre)
        if let f = foco, nombres.contains(f), let i = todas.firstIndex(of: f) {
            foco = todas[(i + 1)...].first { !nombres.contains($0) } ?? todas[..<i].last { !nombres.contains($0) }
        }
        elegidas.subtract(nombres)
        if elegidas.isEmpty { eligiendo = false }
        Task { await modelo.borrar(nombres) }
    }
}

extension ModeloGaleria {
    /// Cuantas columnas caben (celdas de 180 como poco, `CELDA_MIN`).
    nonisolated static func columnas(ancho: CGFloat) -> Int {
        max(1, Int((ancho - 40 + 12) / (180 + 12)))
    }

    /// `destino`, o `nombre (2).ext` si ya hay uno: nada se pisa.
    nonisolated static func libre(_ destino: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destino.path) else { return destino }
        let base = destino.deletingPathExtension().lastPathComponent
        let ext = destino.pathExtension
        var n = 2
        while true {
            let otro = destino.deletingLastPathComponent()
                .appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: otro.path) { return otro }
            n += 1
        }
    }
}

/// Una captura en la rejilla: su miniatura, la chapita de los dias que le
/// quedan (gris, naranja, rojo; verde si esta conservada), la marca de
/// elegida, el anillo del foco y el «⋯» al pasar el raton.
struct CeldaCaptura: View {
    let captura: CapturaGaleria
    let elegida: Bool
    var conFoco = false
    var eligiendo = false
    var menu: () -> AnyView = { AnyView(EmptyView()) }
    @State private var encima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MiniaturaCaptura(url: URL(fileURLWithPath: captura.ruta), esVideo: captura.esVideo)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) { InsigniaCaducidad(captura: captura).padding(6) }
                .overlay(alignment: .topLeading) {
                    if eligiendo || elegida || encima {
                        Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(elegida ? Paleta.v2.acento : Color.white.opacity(0.85))
                            .background(Circle().fill(.black.opacity(elegida ? 0 : 0.25)))
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if encima {
                        Menu { menu() } label: {
                            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold))
                                .frame(width: 26, height: 22)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if captura.esVideo {
                        Text("Vídeo").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule()).padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(elegida ? Paleta.v2.acento : conFoco ? Color.white.opacity(0.7) : .clear,
                                      lineWidth: elegida ? 3 : 2)
                }
            Text(fechaDe(ms: captura.cuando), format: .dateTime.hour().minute())
                .font(.system(size: 11.5))
                .foregroundStyle(Paleta.v2.gris)
        }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .help(captura.nombre)
    }
}

/// Los dias que le quedan: «hoy», «1», «6»…, en gris si queda tiempo, en
/// naranja a uno o dos dias y en rojo el ultimo; o una marca verde si esta
/// conservada. Nada si la caducidad esta apagada.
struct InsigniaCaducidad: View {
    let captura: CapturaGaleria

    var body: some View {
        if captura.conservada {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .padding(5)
                .background(Paleta.v2.verde, in: Circle())
                .foregroundStyle(.white)
                .help("Conservada: está en Mensajes guardados y ya no se borra")
        } else if let d = captura.diasQueQuedan {
            Text(d <= 0 ? "hoy" : "\(d)")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(InsigniaCaducidad.color(dias: d), in: Capsule())
                .foregroundStyle(.white)
                .help(InsigniaCaducidad.pista(dias: d))
        }
    }

    static func color(dias d: Int64) -> Color {
        switch d {
        case ..<1: Paleta.v2.rojo
        case 1...2: Paleta.v2.naranja
        default: Color(hex: 0x636366)
        }
    }

    static func pista(dias d: Int64) -> String {
        switch d {
        case ..<1: return "Se borra hoy. Clic derecho para conservarla o darle 7 días más."
        case 1: return "Se borra mañana. Clic derecho para conservarla o darle 7 días más."
        default: return "Se borra en \(d) días. Clic derecho para conservarla o darle 7 días más."
        }
    }
}

/// La miniatura de una captura (ImageIO, reducida al leer, en la cache de
/// toda la app). Un video lleva un icono: no se decodifica.
struct MiniaturaCaptura: View {
    let url: URL
    let esVideo: Bool
    /// Lado mayor en pixeles: la celda mide hasta ~260 puntos a 2x.
    static let lado = 400
    @State private var imagen: CGImage?
    @State private var falta = false

    var body: some View {
        // La imagen va encima de un rectangulo que toma el tamano que le
        // den: asi `scaledToFill` no se sale de la celda.
        Rectangle().fill(Paleta.v2.tarjeta)
            .overlay {
                if let imagen {
                    Image(decorative: imagen, scale: 2)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                }
            }
            .overlay { marca }
            .clipped()
            .task(id: url) {
                guard !esVideo else { return }
                if let hecha = Miniaturas.compartidas.enCache(url, lado: MiniaturaCaptura.lado) {
                    imagen = hecha
                    return
                }
                let leida = await Miniaturas.compartidas.cargar(url, lado: MiniaturaCaptura.lado)
                imagen = leida
                falta = leida == nil
            }
    }

    /// Mientras no hay imagen: el icono del video, el de que falta o la
    /// ruedita.
    @ViewBuilder
    private var marca: some View {
        if imagen == nil {
            if esVideo {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(Paleta.v2.gris)
            } else if falta {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Paleta.v2.gris)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}
