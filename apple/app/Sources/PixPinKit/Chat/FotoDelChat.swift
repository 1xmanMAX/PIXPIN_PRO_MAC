// **La foto del chat** (Windows 22bf4dc, bc71b4f y 838a37f, 25-oct-2026, el
// usuario: «permitir poner un fondo en las esferas de los chats para que
// parezca mas una app de chat: dame la opcion de poner emojis como su
// perfil, o poner una imagen yo»).
//
// - `CirculoDelChat`: lo que se pinta en todos los sitios del avatar (la
//   fila de la lista, la cabecera del chat, la isla, sus filas de
//   Proyectos y la seccion «Mensajes» del buscador), como `logo::pintar`
//   de Windows: la imagen recortada al circulo; el emoji grande (52 %) sobre
//   el degradado; o las iniciales en blanco sobre el degradado o el color de
//   siempre. Una imagen que aun no ha llegado se pinta como siempre.
// - `HojaFotoDelChat`: la hoja para elegirla (`ventana_chat/foto_del_chat.rs`
//   de Windows, 360 de ancho): el circulo grande (132) donde la imagen se
//   arrastra y la rueda (o el pellizco) acerca hacia el raton; Elegir
//   imagen…, Pegar imagen (⌘V) y Como siempre; los doce fondos; la rejilla
//   de emojis (8 columnas, 4 filas de 40) con su buscador; Cancelar (Esc) y
//   Guardar (Intro). Guardar sin tocar nada no escribe nada.
//
// Lo que se guarda lo escribe el nucleo (`foto_del_chat.rs`): el campo
// `avatar` de la ficha y la imagen `<proyecto>/avatar-<ms>.png`, PNG cuadrado
// de 256 px como mucho, igual que Windows, y viaja con el proyecto. Se abre
// desde el menu de la fila («Cambiar foto del chat…») y pulsando el avatar
// de la isla, con `PeticionDeFoto`.

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

enum TextosFoto {
    static let actuales = textosDeLaFoto(locale: Locale.preferredLanguages.first ?? "es")
}

/// Que chat cambia de foto: la ventana de los chats ensena la hoja mientras
/// haya uno.
@MainActor
final class PeticionDeFoto: ObservableObject {
    static let compartida = PeticionDeFoto()
    @Published var chat: String?
}

/// Las imagenes de las fotos ya leidas, por su ruta (una foto nueva es un
/// fichero nuevo, asi que la ruta basta). Una que aun no esta no se apunta:
/// se vuelve a mirar al repintar.
@MainActor
enum ImagenesDeFoto {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    static func imagen(_ ruta: String) -> NSImage? {
        if let i = cache.object(forKey: ruta as NSString) { return i }
        guard let i = NSImage(contentsOfFile: ruta) else { return nil }
        cache.setObject(i, forKey: ruta as NSString)
        return i
    }
}

/// **El circulo de un chat** con su foto (o como siempre).
struct CirculoDelChat: View {
    let id: String
    let nombre: String
    let lado: CGFloat
    var foto: FotoDelChat?
    /// El tamano de las iniciales (por omision, el 40 % del lado).
    var letra: CGFloat?

    var body: some View {
        ZStack {
            if let ruta = foto?.imagen, let img = ImagenesDeFoto.imagen(ruta) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: lado, height: lado)
                    .clipShape(Circle())
            } else {
                Circle().fill(fondo)
                if let emoji = foto?.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: lado * 0.52))
                } else {
                    Text(Paleta.iniciales(nombre))
                        .font(.system(size: letra ?? lado * 0.4))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: lado, height: lado)
    }

    /// El degradado de arriba abajo de la foto, o el color de siempre.
    private var fondo: AnyShapeStyle {
        guard let arriba = foto?.arriba else { return AnyShapeStyle(Paleta.avatar(id)) }
        let abajo = foto?.abajo ?? arriba
        if abajo == arriba { return AnyShapeStyle(Color(hex: arriba)) }
        return AnyShapeStyle(LinearGradient(colors: [Color(hex: arriba), Color(hex: abajo)],
                                            startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - La hoja

/// Lo que quedara en el circulo (`Eleccion` de Windows).
enum EleccionFoto: Equatable {
    /// Una imagen nueva: la preparada (entera, reducida a 2048) y que
    /// cuadrado suyo entra.
    case nueva(FotoPreparada, NSImage, RecorteDeLaFoto)
    /// La que ya tenia, sin tocar.
    case laDeAntes(String)
    case emoji(String)
    case iniciales
}

@MainActor
final class ModeloFotoDelChat: ObservableObject {
    let chat: String
    let nombre: String
    let almacen: Almacen
    @Published var eleccion: EleccionFoto = .iniciales
    /// El degradado elegido; sin el, el color de siempre del chat.
    @Published var fondo: FondoDeLaFoto?
    /// El ultimo emoji elegido: elegir un fondo con una imagen puesta vuelve
    /// a el (o a las iniciales).
    var ultimoEmoji: String?
    @Published var busqueda = "" { didSet { emojis = emojisDeLaFoto(consulta: busqueda) } }
    @Published private(set) var emojis: [String] = emojisDeLaFoto(consulta: "")
    @Published private(set) var aviso: String?
    @Published private(set) var guardando = false
    /// Si hay algo que guardar.
    private(set) var tocado = false
    let fondos = fondosDeLaFoto()

    init(chat: String, almacen: Almacen) {
        self.chat = chat
        self.almacen = almacen
        nombre = almacen.chats.first { $0.id == chat }?.nombre ?? ""
        let foto: FotoDelChat? = (try? almacen.nucleo.fotoDelChat(chat: chat)) ?? nil
        if let f = foto {
            if let arriba = f.arriba { fondo = FondoDeLaFoto(arriba: arriba, abajo: f.abajo ?? arriba) }
            ultimoEmoji = f.emoji
            if f.tipo == "imagen", let ruta = f.imagen {
                eleccion = .laDeAntes(ruta)
            } else if let e = f.emoji {
                eleccion = .emoji(e)
            }
        }
    }

    /// Lo que se ve en el circulo grande (sin la imagen nueva, que se pinta
    /// aparte con su recorte).
    var vistaPrevia: FotoDelChat {
        var emoji: String?
        var imagen: String?
        switch eleccion {
        case let .emoji(e): emoji = e
        case let .laDeAntes(r): imagen = r
        default: break
        }
        return FotoDelChat(tipo: imagen != nil ? "imagen" : emoji != nil ? "emoji" : "iniciales",
                           emoji: emoji, arriba: imagen == nil ? fondo?.arriba : nil,
                           abajo: imagen == nil ? fondo?.abajo : nil, imagen: imagen, cuando: 0)
    }

    func avisar(_ t: String) {
        aviso = t
        Task {
            try? await Task.sleep(for: .milliseconds(2500))
            if aviso == t { aviso = nil }
        }
    }

    /// Pone una imagen elegida: el nucleo la lee derecha y la reduce; si no
    /// la entiende (HEIC, PDF...), se le pasa en PNG.
    func ponerImagen(fichero: URL) {
        let nucleo = almacen.nucleo
        Task {
            let p = await Task.detached(priority: .userInitiated) { () -> FotoPreparada? in
                if let p = try? nucleo.prepararFotoDelChat(origen: fichero.path) { return p }
                guard let img = NSImage(contentsOf: fichero), let png = Self.png(img) else { return nil }
                return Self.preparar(png, nucleo)
            }.value
            poner(p)
        }
    }

    func ponerImagen(_ imagen: NSImage) {
        let nucleo = almacen.nucleo
        guard let png = Self.png(imagen) else { return avisar(TextosFoto.actuales.sinImagen) }
        Task {
            let p = await Task.detached(priority: .userInitiated) { Self.preparar(png, nucleo) }.value
            poner(p)
        }
    }

    /// Pegar: una imagen copiada o el fichero de una imagen copiado en el
    /// Finder.
    func pegar() {
        let tablero = NSPasteboard.general
        if let urls = tablero.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let u = urls.first(where: { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }) {
            return ponerImagen(fichero: u)
        }
        if let img = NSImage(pasteboard: tablero) { return ponerImagen(img) }
        avisar(TextosFoto.actuales.sinImagen)
    }

    private func poner(_ p: FotoPreparada?) {
        guard let p, let img = NSImage(contentsOfFile: p.ruta) else { return avisar(TextosFoto.actuales.error) }
        eleccion = .nueva(p, img, recorteCentrado(ancho: p.ancho, alto: p.alto))
        tocado = true
    }

    nonisolated static func png(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    nonisolated static func preparar(_ png: Data, _ nucleo: Nucleo) -> FotoPreparada? {
        let f = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-foto-pegada-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        guard (try? png.write(to: f)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: f) }
        return try? nucleo.prepararFotoDelChat(origen: f.path)
    }

    /// Mueve o acerca la imagen nueva.
    func cambiarRecorte(_ cambio: (RecorteDeLaFoto, UInt32, UInt32) -> RecorteDeLaFoto) {
        guard case let .nueva(p, img, r) = eleccion else { return }
        eleccion = .nueva(p, img, cambio(r, p.ancho, p.alto))
    }

    func ponerEmoji(_ e: String) {
        if fondo == nil, let n = try? almacen.nucleo.fondoPropuestoDelChat(chat: chat), Int(n) < fondos.count {
            fondo = fondos[Int(n)]
        }
        ultimoEmoji = e
        eleccion = .emoji(e)
        tocado = true
    }

    func ponerFondo(_ f: FondoDeLaFoto) {
        fondo = f
        switch eleccion {
        case .nueva, .laDeAntes: eleccion = ultimoEmoji.map { .emoji($0) } ?? .iniciales
        default: break
        }
        tocado = true
    }

    func comoSiempre() {
        eleccion = .iniciales
        fondo = nil
        tocado = true
    }

    /// **Guarda lo elegido** y relee la lista. `true` si se puede cerrar.
    func guardar() async -> Bool {
        guard tocado else { return true }
        let guardado: Guardado
        switch eleccion {
        case let .nueva(p, _, r): guardado = .imagen(p.ruta, r)
        case let .emoji(e): guardado = .emoji(e)
        case .iniciales: guardado = .iniciales
        case .laDeAntes: return true
        }
        let nucleo = almacen.nucleo
        let id = self.chat
        let elegido = self.fondo
        guardando = true
        defer { guardando = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                switch guardado {
                case let .imagen(ruta, r):
                    try nucleo.ponerFotoImagen(chat: id, preparada: ruta, recorte: r)
                case let .emoji(e):
                    try nucleo.ponerFotoEmoji(chat: id, emoji: e, fondo: elegido)
                case .iniciales:
                    try nucleo.ponerFotoIniciales(chat: id, fondo: elegido)
                }
            }.value
        } catch {
            avisar(TextosFoto.actuales.error)
            return false
        }
        // Viaja con el proyecto: la sincronizacion sola cuenta desde aqui.
        NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        await almacen.cargarChats()
        return true
    }

    /// Lo que se escribe al guardar, sin la `NSImage`.
    private enum Guardado: Sendable {
        case imagen(String, RecorteDeLaFoto)
        case emoji(String)
        case iniciales
    }
}

enum MedidasFoto {
    static let ancho: CGFloat = 360
    static let margen: CGFloat = 14
    static let vista: CGFloat = 132
    static let columnas = 8
    static let filasVisibles = 4
    static let celda: CGFloat = 40
}

/// **La hoja de la foto del chat.**
struct HojaFotoDelChat: View {
    @StateObject private var modelo: ModeloFotoDelChat
    let cerrar: () -> Void
    /// Donde esta el raton sobre el circulo (para acercar hacia el).
    @State private var raton: CGPoint?
    @State private var arrastre: CGSize = .zero
    @State private var pellizco: CGFloat = 1
    @State private var vigiaRueda: Any?
    private let t = TextosFoto.actuales

    init(chat: String, almacen: Almacen, cerrar: @escaping () -> Void) {
        _modelo = StateObject(wrappedValue: ModeloFotoDelChat(chat: chat, almacen: almacen))
        self.cerrar = cerrar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(t.titulo).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: cerrar) {
                    Image(systemName: "xmark").font(.system(size: 12)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(t.cancelar)
            }
            .frame(height: 38)
            vista
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            Text(esNueva ? t.recorte : " ")
                .font(.system(size: 11))
                .foregroundStyle(Paleta.proyectos.apagado)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            HStack(spacing: 8) {
                botonDeHoja(t.imagen, accion: elegirImagen)
                botonDeHoja(t.pegar, accion: modelo.pegar)
                botonDeHoja(t.quitar, accion: modelo.comoSiempre)
            }
            .padding(.top, 10)
            Text(t.fondo)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Paleta.proyectos.apagado)
                .padding(.top, 14)
            HStack(spacing: 0) {
                ForEach(Array(modelo.fondos.enumerated()), id: \.offset) { _, f in
                    let puesto = modelo.fondo == f && !esImagen
                    Button { modelo.ponerFondo(f) } label: {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: f.arriba), Color(hex: f.abajo)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 22)
                            .overlay { if puesto { Circle().strokeBorder(Paleta.chat.enviar, lineWidth: 2).padding(-3) } }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 26)
            .padding(.top, 6)
            TextField("", text: $modelo.busqueda,
                      prompt: Text(t.buscar).foregroundStyle(Paleta.proyectos.apagado))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Paleta.proyectos.buscador, in: Capsule())
                .padding(.top, 14)
            rejilla
                .frame(height: MedidasFoto.celda * CGFloat(MedidasFoto.filasVisibles))
                .padding(.top, 8)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                if let a = modelo.aviso {
                    Text(a).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                Button(t.cancelar, action: cerrar)
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 100)
                Button(t.guardar) {
                    Task { if await modelo.guardar() { cerrar() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(modelo.guardando)
                .frame(width: 100)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, MedidasFoto.margen)
        .padding(.bottom, MedidasFoto.margen)
        .frame(width: MedidasFoto.ancho, height: 600)
        .background(Paleta.proyectos.lista)
        .foregroundStyle(Paleta.proyectos.texto)
        // ⌘V pega una imagen (o el fichero de una), como Ctrl+V en Windows.
        .background {
            Button("") { modelo.pegar() }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .onAppear(perform: vigilarRueda)
        .onDisappear {
            if let v = vigiaRueda { NSEvent.removeMonitor(v) }
            vigiaRueda = nil
        }
    }

    private var esNueva: Bool {
        if case .nueva = modelo.eleccion { return true }
        return false
    }

    private var esImagen: Bool {
        switch modelo.eleccion {
        case .nueva, .laDeAntes: return true
        default: return false
        }
    }

    // El circulo grande: la imagen nueva con su recorte (se arrastra y se
    // acerca) o lo que quedara.
    @ViewBuilder private var vista: some View {
        let lado = MedidasFoto.vista
        if case let .nueva(p, img, r) = modelo.eleccion {
            let d = destinoDelRecorte(recorte: r, ancho: p.ancho, alto: p.alto, lado: Float(lado))
            ZStack(alignment: .topLeading) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: CGFloat(d.ancho), height: CGFloat(d.alto))
                    .offset(x: CGFloat(d.x), y: CGFloat(d.y))
            }
            .frame(width: lado, height: lado, alignment: .topLeading)
            .clipShape(Circle())
            .contentShape(Circle())
            .onContinuousHover { fase in
                if case let .active(p) = fase { raton = p } else { raton = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let (dx, dy) = (g.translation.width - arrastre.width, g.translation.height - arrastre.height)
                    arrastre = g.translation
                    modelo.cambiarRecorte {
                        recorteMovido(recorte: $0, ancho: $1, alto: $2, lado: Float(lado), dx: Float(dx), dy: Float(dy))
                    }
                }
                .onEnded { _ in arrastre = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { g in
                    let factor = g.magnification / pellizco
                    pellizco = g.magnification
                    let punto = g.startAnchor
                    modelo.cambiarRecorte {
                        recorteAcercado(recorte: $0, ancho: $1, alto: $2, factor: Float(factor),
                                        px: Float(punto.x), py: Float(punto.y))
                    }
                }
                .onEnded { _ in pellizco = 1 })
        } else {
            CirculoDelChat(id: modelo.chat, nombre: modelo.nombre, lado: lado, foto: modelo.vistaPrevia)
        }
    }

    // La rejilla de emojis, con su buscador encima.
    @ViewBuilder private var rejilla: some View {
        if modelo.emojis.isEmpty {
            Text(t.sinEmojis)
                .font(.system(size: 12))
                .foregroundStyle(Paleta.proyectos.apagado)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: MedidasFoto.columnas),
                          spacing: 0) {
                    ForEach(modelo.emojis, id: \.self) { e in
                        CeldaEmoji(emoji: e, puesto: modelo.eleccion == .emoji(e)) { modelo.ponerEmoji(e) }
                    }
                }
            }
        }
    }

    private func botonDeHoja(_ titulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Paleta.proyectos.buscador, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func elegirImagen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let u = panel.url else { return }
        modelo.ponerImagen(fichero: u)
    }

    /// La rueda sobre el circulo acerca hacia el raton (un paso de rueda,
    /// 120 en Windows, acerca 1,2 veces).
    private func vigilarRueda() {
        guard vigiaRueda == nil else { return }
        let modelo = self.modelo
        let raton = $raton
        vigiaRueda = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            let tomada = MainActor.assumeIsolated { () -> Bool in
                guard let p = raton.wrappedValue, case .nueva = modelo.eleccion else { return false }
                let unidades = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY * 4 : e.scrollingDeltaY * 120
                let delta = Int32(max(min(unidades, 1200), -1200).rounded())
                guard delta != 0 else { return true }
                let lado = Float(MedidasFoto.vista)
                modelo.cambiarRecorte {
                    recorteConRueda(recorte: $0, ancho: $1, alto: $2, delta: delta,
                                    px: Float(p.x) / lado, py: Float(p.y) / lado)
                }
                return true
            }
            return tomada ? nil : e
        }
    }
}

/// Un emoji de la rejilla; el puesto, con su fondo.
private struct CeldaEmoji: View {
    let emoji: String
    let puesto: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: MedidasFoto.celda, maxHeight: MedidasFoto.celda)
                .background(puesto ? Paleta.chat.enviar.opacity(0.28)
                    : encima ? Paleta.proyectos.filaEncima : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}
