// **La ficha del chat** (`ventana_chat/ficha_del_chat.rs` de Windows,
// 25-oct-2026, el usuario: «Mira Telegram: una isla flotante que muestra el
// chat, fotos, videos, archivos, enlaces… y hacer click dentro no debe salir
// de esa zona»): la isla que sale al pulsar el nombre del chat en su
// cabecera.
//
// - **Arriba**, el avatar del chat, su nombre y cuantas cosas tiene (con su
//   codigo unico), la lupa y el aspa.
// - **Las pestanas**, un selector con la cuenta de cada una. Solo salen las
//   que tienen algo: un chat sin videos no ensena «Vídeos 0».
// - **El contenido**: lo que se mira (fotos, videos, dibujos, hojas) en una
//   rejilla de miniaturas cuadradas que pone mas columnas cuanto mas sitio
//   hay; lo que se lee (archivos, enlaces, voz) en filas.
// - **Lo que se pulsa se ve DENTRO**: la previa en grande, con las flechas
//   de la anterior y la siguiente (y ← →), «Abrir» y «Ver en el chat». La
//   flecha de arriba (o Esc) vuelve a la rejilla. Un enlace se abre en el
//   navegador y la isla se queda.
//
// Solo el aspa, Esc (desde la rejilla) o un clic FUERA la cierran. Que
// pestanas salen, que cuenta cada una y que hay en ella es de Rust
// (`ficha_del_chat.rs`: `Nucleo.fichaDelChat`, `Nucleo.cosasDeLaFicha`).

import AppKit
import PixPinCore
import SwiftUI

/// Las medidas de la isla (`pixpin_ui::info`, las `ISLA_*`), al 100 %.
enum MedidasFicha {
    static let anchoMinimo: CGFloat = 360
    static let anchoMaximo: CGFloat = 720
    /// Lo que ocupa de la ventana, en tanto por uno.
    static let fraccion: CGFloat = 0.58
    static let altoMaximo: CGFloat = 860
    static let margenX: CGFloat = 32
    static let margenY: CGFloat = 28
    static let radio: CGFloat = 16
    static let cabecera: CGFloat = 68
    static let avatar: CGFloat = 42
    static let boton: CGFloat = 40
    static let tira: CGFloat = 48
    static let celdaMinima: CGFloat = 112
    static let hueco: CGFloat = 4
    static let margen: CGFloat = 12
    static let fila: CGFloat = 62
    static let miniaturaFila: CGFloat = 44
    static let flecha: CGFloat = 40
    static let pie: CGFloat = 64
    static let botonPie: CGFloat = 40
    static let anchoBotonPie: CGFloat = 150

    /// **Lo que mide la isla** en un hueco (`isla_en`): el 58 % del ancho,
    /// entre 360 y 720, con su margen; tan alta como deja el hueco (hasta
    /// 860). Si no cabe ni la minima, el hueco entero (`completa`).
    static func isla(en hueco: CGSize) -> (tamano: CGSize, completa: Bool) {
        if hueco.width < anchoMinimo + 2 * margenX { return (hueco, true) }
        let ancho = min(min(max(hueco.width * fraccion, anchoMinimo), anchoMaximo), hueco.width - 2 * margenX)
        let alto = max(min(hueco.height - 2 * margenY, altoMaximo), 1)
        return (CGSize(width: ancho, height: alto), false)
    }
}

/// Los textos de la ficha (`info-*` de `main.ftl`).
enum TextosFicha {
    static func rotulo(_ s: SeccionFicha) -> String {
        switch s {
        case .galeria: "Galería"
        case .todo: "Todo"
        case .fotos: "Fotos"
        case .videos: "Vídeos"
        case .archivos: "Archivos"
        case .enlaces: "Enlaces"
        case .voz: "Voz"
        case .dibujos: "Dibujos"
        case .fijados: "Fijados"
        case .buzon: "Buzón"
        }
    }

    /// El icono de una seccion (para el vacio).
    static func icono(_ s: SeccionFicha) -> String {
        switch s {
        case .fotos, .galeria: "photo.on.rectangle"
        case .videos: "play.fill"
        case .enlaces: "link"
        case .voz: "mic"
        case .dibujos: "scribble.variable"
        case .fijados: "pin"
        default: "doc.text"
        }
    }

    /// «24 cosas  ·  K7Q2» (`info-resumen`).
    static func resumen(cosas: UInt32, codigo: String) -> String {
        let n = cosas == 1 ? "1 cosa" : "\(cosas) cosas"
        return codigo.isEmpty ? n : "\(n)  ·  \(codigo)"
    }

    /// «24 cosas» (`chat-cosas`), debajo del nombre en la cabecera.
    static func cosas(_ n: UInt64) -> String { n == 1 ? "1 cosa" : "\(n) cosas" }

    static let vacia = "Aquí no hay nada todavía"
    static let nada = "Nada con eso"
    static let buscar = "Buscar"
    static let abrir = "Abrir"
    static let abrirEnlace = "Abrir enlace"
    static let reproducir = "Reproducir"
    static let verEnElChat = "Ver en el chat"

    /// «3 de 24» (`info-previa-posicion`).
    static func posicion(_ k: Int, de n: Int) -> String { "\(k) de \(n)" }

    /// De que es una cosa (`chat-clase-*`). Una nota es solo su texto; una
    /// clase que no se conoce se dice con su palabra.
    static func clase(_ c: String) -> String? {
        switch c {
        case "", "NOTA": nil
        case "IMAGEN": "Imagen"
        case "ARCHIVO": "Archivo"
        case "VOZ": "Nota de voz"
        case "DIBUJO": "Dibujo"
        case "PAGINA": "Página"
        case "PROYECTO": "Proyecto"
        case "MINIAPP": "Mini-aplicación"
        default: c
        }
    }

    /// Cuando: la hora si es de hoy; si no, el dia (`etiqueta_hora`).
    static func hora(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func tamano(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// El nombre con el que se ensena una cosa: su texto (la primera linea)
    /// o, sin el, el del fichero.
    static func nombre(_ m: MensajeChat) -> String {
        let r = m.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return m.nombre }
        return r.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? r
    }

    /// La segunda linea de una fila: en un enlace, adonde lleva; si no, de
    /// que es, cuanto pesa y cuando.
    static func segunda(_ c: CosaDeLaFicha) -> String {
        if c.mensaje.ruta == nil, let e = c.enlace {
            return e.deQue.isEmpty ? e.donde : "\(e.donde) / \(e.deQue)"
        }
        var partes: [String] = []
        if let k = clase(c.mensaje.clase) { partes.append(k) }
        if c.mensaje.bytes > 0 { partes.append(tamano(c.mensaje.bytes)) }
        partes.append(hora(c.mensaje.cuando))
        return partes.joined(separator: "  ·  ")
    }
}

// MARK: - El estado

/// **El estado de la ficha** de un chat: abierta o no, la pestana, lo que
/// hay en ella, lo buscado y lo que se ve en grande.
@MainActor
final class ModeloFichaDelChat: ObservableObject {
    let chat: String
    let almacen: Almacen
    @Published private(set) var abierta = false
    @Published private(set) var leida: FichaDelChatLeida?
    @Published private(set) var seccion: SeccionFicha = .todo
    @Published private(set) var cosas: [CosaDeLaFicha] = []
    @Published private(set) var cargando = false
    /// La cosa que se ve en grande (su sitio en `cosas`); `nil`, la rejilla.
    @Published var enPrevia: Int?
    @Published var buscando = false
    @Published var buscado = "" { didSet { if buscado != oldValue { leerCosas() } } }
    /// Sube con cada lectura: lo que llegue de una vieja no pisa lo nuevo.
    private var vuelta = 0

    init(chat: String, almacen: Almacen) {
        self.chat = chat
        self.almacen = almacen
    }

    var pestanas: [PestanaFicha] { leida?.pestanas ?? [] }

    /// La pestana puesta va en rejilla.
    var cuadricula: Bool { pestanas.first { $0.seccion == seccion }?.cuadricula ?? false }

    var previa: CosaDeLaFicha? { enPrevia.flatMap { cosas[safe: $0] } }

    /// **Abre la ficha** en la primera pestana que tenga algo.
    func abrir() {
        enPrevia = nil
        buscando = false
        buscado = ""
        abierta = true
        releer(primera: true)
    }

    func cerrar() {
        abierta = false
        enPrevia = nil
        buscando = false
    }

    func elegir(_ s: SeccionFicha) {
        enPrevia = nil
        guard s != seccion else { return }
        seccion = s
        cosas = []
        leerCosas()
    }

    /// Vuelve a leer las pestanas y lo de la puesta (al abrirla y cuando el
    /// chat cambia con la ficha abierta).
    func releer(primera: Bool = false) {
        guard abierta else { return }
        let nucleo = almacen.nucleo
        let chat = self.chat
        let actual: SeccionFicha? = primera ? nil : seccion
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> FichaDelChatLeida? in
                try? nucleo.fichaDelChat(chat: chat, actual: actual)
            }.value
            guard let r, abierta else { return }
            leida = r
            if primera { seccion = r.primera }
            leerCosas()
        }
    }

    private func leerCosas() {
        vuelta += 1
        let mia = vuelta
        let nucleo = almacen.nucleo
        let (chat, seccion, buscado) = (self.chat, self.seccion, self.buscado)
        cargando = true
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> [CosaDeLaFicha] in
                (try? nucleo.cosasDeLaFicha(chat: chat, seccion: seccion, buscado: buscado)) ?? []
            }.value
            guard mia == vuelta else { return }
            cargando = false
            // La que se veia en grande sigue, si sigue estando.
            let vista = previa?.mensaje.id
            cosas = r
            if let vista { enPrevia = r.firstIndex { $0.mensaje.id == vista } }
        }
    }

    /// Esc: de la previa a la rejilla; con la lupa, la apaga; si no, cierra.
    func escape() {
        if enPrevia != nil {
            enPrevia = nil
        } else if buscando {
            buscando = false
            buscado = ""
        } else {
            cerrar()
        }
    }

    /// La anterior (`-1`) o la siguiente (`+1`) en la previa.
    func mover(_ paso: Int) {
        guard let i = enPrevia, cosas.indices.contains(i + paso) else { return }
        enPrevia = i + paso
    }

    func hayVecina(_ paso: Int) -> Bool {
        guard let i = enPrevia else { return false }
        return cosas.indices.contains(i + paso)
    }

    /// Un clic en una cosa: un enlace se abre en el navegador (y la isla se
    /// queda); lo demas, en grande dentro de la isla.
    func pulsar(_ i: Int) {
        guard let c = cosas[safe: i] else { return }
        if c.mensaje.ruta == nil, let e = c.enlace, let url = URL(string: e.url) {
            NSWorkspace.shared.open(url)
            return
        }
        enPrevia = i
    }
}

/// **«Abrir»** de la previa: cada cosa con lo suyo, como su burbuja.
@MainActor
enum AbrirDeLaFicha {
    /// El rotulo del boton.
    static func rotulo(_ c: CosaDeLaFicha) -> String {
        if c.mensaje.ruta == nil, c.enlace != nil { return TextosFicha.abrirEnlace }
        if c.mensaje.clase == "VOZ" || c.esVideo { return TextosFicha.reproducir }
        return TextosFicha.abrir
    }

    /// Abre `c`; `false` si no tiene con que abrirse aparte (una mini-app, un
    /// acceso a otro proyecto): entonces se ve en el chat.
    static func abrir(_ c: CosaDeLaFicha, chat: String, almacen: Almacen) -> Bool {
        let m = c.mensaje
        if m.ruta == nil, let e = c.enlace, let url = URL(string: e.url) {
            NSWorkspace.shared.open(url)
            return true
        }
        switch m.clase {
        case "DIBUJO":
            guard let r = m.referencia, !r.isEmpty else { return false }
            VentanasDeLienzo.compartidas.abrir(referencia: r, en: chat,
                                               titulo: m.nombre.isEmpty ? "Dibujo" : m.nombre, almacen: almacen)
            return true
        case "NOTA":
            EditoresDeNotas.compartidos.abrir(m, en: chat, almacen: almacen)
            return true
        case "IMAGEN" where !c.esVideo:
            // En su lienzo, como la burbuja.
            anotarFoto(m, chat: chat, almacen: almacen)
            return true
        default:
            break
        }
        guard let ruta = m.ruta, !ruta.isEmpty else { return false }
        Task {
            guard let url = await almacen.url(deRuta: ruta, en: chat),
                  FileManager.default.fileExists(atPath: url.path) else { return NSSound.beep() }
            if m.clase == "VOZ" {
                ReproductorVoz.compartido.alternar(m.id, url: url, titulo: BibliotecaAudio.titulo(de: m))
                return
            }
            if c.esVideo {
                NSWorkspace.shared.open(url)
                return
            }
            if VentanasDePlano.compartidas.abrirSiEsSuyo(url, titulo: m.nombre) { return }
            if AbrirDocumento.abrir(url, nucleo: almacen.nucleo, titulo: m.nombre.isEmpty ? nil : m.nombre) { return }
            NSWorkspace.shared.open(url)
        }
        return true
    }
}

// MARK: - La cabecera del chat

/// **La cabecera del chat**: el avatar y el nombre (que abren la ficha) con
/// cuantas cosas guarda debajo, y la lupa (⌘F).
struct CabeceraDelChat: View {
    @ObservedObject var almacen: Almacen
    let chat: String
    @ObservedObject var ficha: ModeloFichaDelChat
    @ObservedObject var buscador: BuscadorDelChat
    @State private var encima = false

    private var datos: FichaChat? { almacen.chats.first { $0.id == chat } }

    var body: some View {
        HStack(spacing: 8) {
            Button { ficha.abrir() } label: {
                HStack(spacing: 10) {
                    AvatarDelChat(id: chat, nombre: datos?.nombre ?? "", lado: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(datos?.nombre ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Paleta.proyectos.texto)
                        if let n = almacen.totales[chat] {
                            Text(TextosFicha.cosas(n))
                                .font(.system(size: 12))
                                .foregroundStyle(Paleta.proyectos.apagado)
                        }
                    }
                    .lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(encima ? Paleta.proyectos.filaEncima : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { encima = $0 }
            .help("Fotos, vídeos, archivos y enlaces del chat")
            Spacer(minLength: 0)
            Button {
                if buscador.abierto { buscador.cerrar() } else { buscador.abrir() }
            } label: {
                Image(systemName: buscador.abierto ? "xmark" : "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Buscar en el chat (⌘F)")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Paleta.chat.cabecera)
    }
}

/// El avatar de un chat: el circulo de su color con sus iniciales.
struct AvatarDelChat: View {
    let id: String
    let nombre: String
    let lado: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Paleta.avatar(id))
            Text(Paleta.iniciales(nombre))
                .font(.system(size: lado * 0.4))
                .foregroundStyle(.white)
        }
        .frame(width: lado, height: lado)
    }
}

// MARK: - La isla

/// **La isla**, encima del chat con el velo detras.
struct IslaFichaDelChat: View {
    @ObservedObject var ficha: ModeloFichaDelChat
    /// «Ver en el chat»: cierra la isla y salta al mensaje.
    let verEnElChat: (CosaDeLaFicha) -> Void
    @FocusState private var enBuscar: Bool

    private var nombreDelChat: String {
        ficha.almacen.chats.first { $0.id == ficha.chat }?.nombre ?? ""
    }

    var body: some View {
        GeometryReader { g in
            let (tam, completa) = MedidasFicha.isla(en: g.size)
            let radio = completa ? 0 : MedidasFicha.radio
            ZStack {
                // El velo: lo de debajo espera, y un clic en el cierra.
                Color.black.opacity(0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { ficha.cerrar() }
                VStack(spacing: 0) {
                    cabecera
                    Paleta.proyectos.separador.frame(height: 1)
                    if let c = ficha.previa {
                        PreviaDeLaFicha(ficha: ficha, cosa: c, verEnElChat: verEnElChat)
                    } else {
                        pestanas
                        contenido
                    }
                }
                .frame(width: tam.width, height: tam.height)
                .background(Paleta.proyectos.lista, in: RoundedRectangle(cornerRadius: radio))
                .overlay {
                    if !completa {
                        RoundedRectangle(cornerRadius: radio).strokeBorder(Paleta.chat.islaBorde, lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radio))
                .shadow(color: .black.opacity(completa ? 0 : 0.22), radius: 12, y: 10)
                // Un clic dentro, donde no hay nada, no cierra.
                .contentShape(Rectangle())
                .onTapGesture {}
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    // La cabecera: avatar, nombre y cuantas cosas, lupa y aspa; en la previa,
    // la flecha de volver, el nombre de la cosa y «3 de 24 · cuando · peso».
    private var cabecera: some View {
        HStack(spacing: 12) {
            if let c = ficha.previa {
                botonRedondo("arrow.left", ayuda: "Volver (Esc)") { ficha.enPrevia = nil }
                titulo(TextosFicha.nombre(c.mensaje), subtitulo: subtituloDePrevia(c))
            } else {
                AvatarDelChat(id: ficha.chat, nombre: nombreDelChat, lado: MedidasFicha.avatar)
                if ficha.buscando {
                    TextField("", text: $ficha.buscado,
                              prompt: Text(TextosFicha.buscar).foregroundStyle(Paleta.proyectos.apagado))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Paleta.proyectos.texto)
                        .focused($enBuscar)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Paleta.proyectos.buscador, in: Capsule())
                        .onAppear { enBuscar = true }
                } else {
                    titulo(nombreDelChat,
                           subtitulo: ficha.leida.map { TextosFicha.resumen(cosas: $0.cosas, codigo: $0.codigo) } ?? "")
                }
                botonRedondo("magnifyingglass", ayuda: TextosFicha.buscar, activo: ficha.buscando) {
                    if ficha.buscando {
                        ficha.buscando = false
                        ficha.buscado = ""
                    } else {
                        ficha.buscando = true
                    }
                }
            }
            botonRedondo("xmark", ayuda: "Cerrar") { ficha.cerrar() }
        }
        .padding(.horizontal, 16)
        .frame(height: MedidasFicha.cabecera)
    }

    private func subtituloDePrevia(_ c: CosaDeLaFicha) -> String {
        var v = [TextosFicha.posicion((ficha.enPrevia ?? 0) + 1, de: ficha.cosas.count),
                 TextosFicha.hora(c.mensaje.cuando)]
        if c.mensaje.bytes > 0 { v.append(TextosFicha.tamano(c.mensaje.bytes)) }
        return v.joined(separator: "  ·  ")
    }

    private func titulo(_ t: String, subtitulo: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.proyectos.texto)
            Text(subtitulo)
                .font(.system(size: 12.5))
                .foregroundStyle(Paleta.proyectos.apagado)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func botonRedondo(_ simbolo: String, ayuda: String, activo: Bool = false,
                              accion: @escaping () -> Void) -> some View {
        BotonRedondoFicha(simbolo: simbolo, ayuda: ayuda, activo: activo, accion: accion)
    }

    // Las pestanas: el nombre y, mas apagada, la cuenta; la puesta, llena.
    private var pestanas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ficha.pestanas, id: \.seccion) { p in
                    PestanaDeLaFicha(pestana: p, activa: p.seccion == ficha.seccion) { ficha.elegir(p.seccion) }
                }
            }
            .padding(4)
            .background(Paleta.proyectos.buscador, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: MedidasFicha.tira)
    }

    @ViewBuilder
    private var contenido: some View {
        if ficha.cosas.isEmpty {
            VStack(spacing: 10) {
                if ficha.cargando {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: TextosFicha.icono(ficha.seccion))
                        .font(.system(size: 40))
                        .foregroundStyle(Paleta.proyectos.apagado.opacity(0.6))
                    Text(ficha.buscado.trimmingCharacters(in: .whitespaces).isEmpty ? TextosFicha.vacia : TextosFicha.nada)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Paleta.proyectos.apagado)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ficha.cuadricula {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: MedidasFicha.celdaMinima), spacing: MedidasFicha.hueco)],
                          spacing: MedidasFicha.hueco) {
                    ForEach(Array(ficha.cosas.enumerated()), id: \.element.mensaje.id) { i, c in
                        CeldaDeLaFicha(cosa: c, chat: ficha.chat, almacen: ficha.almacen)
                            .onTapGesture { ficha.pulsar(i) }
                    }
                }
                .padding(MedidasFicha.margen)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ficha.cosas.enumerated()), id: \.element.mensaje.id) { i, c in
                        FilaDeLaFicha(cosa: c, chat: ficha.chat, almacen: ficha.almacen)
                            .onTapGesture { ficha.pulsar(i) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }
}

/// Un boton redondo de la isla, con su fondo al pasar por encima.
private struct BotonRedondoFicha: View {
    let simbolo: String
    let ayuda: String
    var activo = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 16))
                .foregroundStyle(Paleta.proyectos.texto)
                .frame(width: MedidasFicha.boton, height: MedidasFicha.boton)
                .background(encima || activo ? Paleta.proyectos.filaEncima : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

private struct PestanaDeLaFicha: View {
    let pestana: PestanaFicha
    let activa: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Text(TextosFicha.rotulo(pestana.seccion))
                    .font(.system(size: 13))
                    .foregroundStyle(activa ? Color.white : Paleta.proyectos.texto)
                Text("\(pestana.cuenta)")
                    .font(.system(size: 11))
                    .foregroundStyle(activa ? Color.white.opacity(0.7) : Paleta.proyectos.apagado)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(activa ? Paleta.chat.enviar : encima ? Paleta.proyectos.filaEncima : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}

// MARK: - Las miniaturas

/// Lo que se ve de una cosa: la foto, el dibujo o su tarjeta. Las fotos y
/// los dibujos se leen fuera del hilo principal, por la cache de siempre.
private struct VistaDeLaCosa: View {
    let cosa: CosaDeLaFicha
    let chat: String
    let almacen: Almacen
    /// Los pixeles del lado mayor que se piden de la foto.
    let pixeles: Int
    /// Recortada al cuadrado (la rejilla) o entera (la previa).
    var llenar = true
    @State private var foto: CGImage?
    @State private var dibujo: DibujoDelChat?
    @State private var fotosListas = 0

    private var m: MensajeChat { cosa.mensaje }

    var body: some View {
        Group {
            if let foto {
                if llenar {
                    Color.clear.overlay {
                        Image(decorative: foto, scale: 2).resizable().interpolation(.high).scaledToFill()
                    }
                    .clipped()
                } else {
                    Image(decorative: foto, scale: 2).resizable().interpolation(.high).scaledToFit()
                }
            } else if let dibujo {
                let fotos = dibujo.fotos
                let pixeles = self.pixeles
                VistaLienzo(lienzo: dibujo.lienzo, version: fotosListas) { id in
                    fotos[id].flatMap { Miniaturas.compartidas.enCache($0, lado: pixeles) }
                }
                .allowsHitTesting(false)
            } else {
                TarjetaDeLaCosa(mensaje: m)
            }
        }
        .overlay {
            if cosa.esVideo { InsigniaDeVideo() }
        }
        .task(id: m.id) { await cargar() }
    }

    private func cargar() async {
        if m.clase == "IMAGEN", !cosa.esVideo, let ruta = m.ruta, !ruta.isEmpty,
           let url = await almacen.url(deRuta: ruta, en: chat) {
            foto = await Miniaturas.compartidas.cargar(url, lado: pixeles)
            return
        }
        if m.clase == "DIBUJO", let r = m.referencia, !r.isEmpty, let leido = await almacen.dibujo(r, en: chat) {
            dibujo = leido
            var alguna = false
            for url in Set(leido.fotos.values) {
                if await Miniaturas.compartidas.cargar(url, lado: pixeles) != nil { alguna = true }
            }
            if alguna { fotosListas += 1 }
        }
    }
}

/// La tarjeta de lo que no tiene vista previa: la chapa de color con su
/// extension (`PDF`, `MP4`…) o el icono de su clase.
private struct TarjetaDeLaCosa: View {
    let mensaje: MensajeChat

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            let ext = ((mensaje.nombre.isEmpty ? (mensaje.ruta ?? "") : mensaje.nombre) as NSString).pathExtension
            ZStack {
                Paleta.proyectos.filaEncima
                if !ext.isEmpty {
                    CuadroDeTipo(ext: ext, lado: max(lado * 0.42, 20))
                } else {
                    Image(systemName: Burbuja.icono(mensaje.clase))
                        .font(.system(size: max(lado * 0.3, 14)))
                        .foregroundStyle(Paleta.proyectos.apagado)
                }
            }
        }
    }
}

/// El circulo oscuro con el triangulo de reproducir de un video.
private struct InsigniaDeVideo: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Color.black.opacity(0.55), in: Circle())
    }
}

/// Una celda de la rejilla, cuadrada; al pasar por encima se aclara y
/// lleva su filete.
private struct CeldaDeLaFicha: View {
    let cosa: CosaDeLaFicha
    let chat: String
    let almacen: Almacen
    @State private var encima = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { VistaDeLaCosa(cosa: cosa, chat: chat, almacen: almacen, pixeles: 400) }
            .clipped()
            .overlay {
                if encima {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle().strokeBorder(Paleta.chat.enviar, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onHover { encima = $0 }
            .help(TextosFicha.nombre(cosa.mensaje))
    }
}

/// Una fila: archivos, enlaces, voz, notas. Su miniatura y dos lineas: el
/// nombre y, debajo, de que es, cuanto pesa y cuando (o adonde lleva).
private struct FilaDeLaFicha: View {
    let cosa: CosaDeLaFicha
    let chat: String
    let almacen: Almacen
    @State private var encima = false

    private var esEnlace: Bool { cosa.mensaje.ruta == nil && cosa.enlace != nil }

    var body: some View {
        HStack(spacing: 12) {
            miniatura
                .frame(width: MedidasFicha.miniaturaFila, height: MedidasFicha.miniaturaFila)
            VStack(alignment: .leading, spacing: 4) {
                Text(TextosFicha.nombre(cosa.mensaje))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Paleta.proyectos.texto)
                Text(TextosFicha.segunda(cosa))
                    .font(.system(size: 12))
                    .foregroundStyle(esEnlace ? Paleta.chat.enviar : Paleta.proyectos.apagado)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: MedidasFicha.fila)
        .background(encima ? Paleta.proyectos.filaEncima : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { encima = $0 }
    }

    @ViewBuilder
    private var miniatura: some View {
        if esEnlace {
            circulo("link", Paleta.chat.enviar)
        } else if cosa.mensaje.clase == "VOZ" {
            circulo("play.fill", Paleta.chat.enviar)
        } else if cosa.mensaje.ruta != nil || !cosa.mensaje.nombre.isEmpty {
            VistaDeLaCosa(cosa: cosa, chat: chat, almacen: almacen, pixeles: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            circulo("doc.text", Paleta.proyectos.apagado)
        }
    }

    private func circulo(_ simbolo: String, _ color: Color) -> some View {
        Circle().fill(color)
            .overlay {
                Image(systemName: simbolo).font(.system(size: 18)).foregroundStyle(.white)
            }
    }
}

// MARK: - La previa

/// **La previa de una cosa**, en grande dentro de la isla: la foto entera,
/// el dibujo, la nota o la tarjeta del archivo; las flechas de los lados si
/// hay a donde ir, y el pie con «Ver en el chat» y «Abrir».
private struct PreviaDeLaFicha: View {
    @ObservedObject var ficha: ModeloFichaDelChat
    let cosa: CosaDeLaFicha
    let verEnElChat: (CosaDeLaFicha) -> Void

    private var m: MensajeChat { cosa.mensaje }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                flecha("chevron.left", -1)
                vista
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                flecha("chevron.right", 1)
            }
            .padding(MedidasFicha.margen)
            HStack(spacing: 12) {
                BotonDelPie(rotulo: TextosFicha.verEnElChat, simbolo: "arrow.right", principal: false) {
                    verEnElChat(cosa)
                }
                BotonDelPie(rotulo: AbrirDeLaFicha.rotulo(cosa), simbolo: "arrow.up.forward.square", principal: true) {
                    if !AbrirDeLaFicha.abrir(cosa, chat: ficha.chat, almacen: ficha.almacen) { verEnElChat(cosa) }
                }
            }
            .frame(height: MedidasFicha.pie)
        }
    }

    @ViewBuilder
    private var vista: some View {
        if (m.clase == "IMAGEN" && !cosa.esVideo) || m.clase == "DIBUJO" {
            VistaDeLaCosa(cosa: cosa, chat: ficha.chat, almacen: ficha.almacen, pixeles: 1600, llenar: false)
                .id(m.id)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if m.clase == "NOTA" || m.clase.isEmpty {
            // Una nota (o un enlace): su texto, en una tarjeta.
            ScrollView {
                Text(m.texto)
                    .font(.system(size: 15))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(Paleta.proyectos.filaEncima, in: RoundedRectangle(cornerRadius: 12))
        } else {
            // Lo demas: su tarjeta en un cuadrado y debajo su nombre entero.
            VStack(spacing: 14) {
                TarjetaDeLaCosa(mensaje: m)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay { if cosa.esVideo { InsigniaDeVideo() } }
                Text(m.nombre.isEmpty ? TextosFicha.nombre(m) : m.nombre)
                    .font(.system(size: 14))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func flecha(_ simbolo: String, _ paso: Int) -> some View {
        if ficha.hayVecina(paso) {
            Button { ficha.mover(paso) } label: {
                Image(systemName: simbolo)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .frame(width: MedidasFicha.flecha, height: MedidasFicha.flecha)
                    .background(Paleta.proyectos.buscador, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(paso < 0 ? "Anterior (←)" : "Siguiente (→)")
        } else {
            Color.clear.frame(width: MedidasFicha.flecha, height: MedidasFicha.flecha)
        }
    }
}

/// Un boton del pie de la previa; el principal, azul.
private struct BotonDelPie: View {
    let rotulo: String
    let simbolo: String
    let principal: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Image(systemName: simbolo).font(.system(size: 14))
                Text(rotulo).font(.system(size: 13.5)).lineLimit(1)
            }
            .foregroundStyle(principal ? Color.white : Paleta.proyectos.texto)
            .frame(width: MedidasFicha.anchoBotonPie, height: MedidasFicha.botonPie)
            .background(fondo, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }

    private var fondo: Color {
        switch (principal, encima) {
        case (true, true): Paleta.chat.enviar
        case (true, false): Paleta.chat.enviar.opacity(0.9)
        case (false, true): Paleta.proyectos.filaEncima
        case (false, false): Paleta.proyectos.buscador
        }
    }
}
