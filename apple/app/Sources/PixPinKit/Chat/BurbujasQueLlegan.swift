// Lo que llega al chat desde Windows o el movil y el Mac no sabia ensenar
// (tanda B9). Cada cosa con su burbuja, como en Windows, y abriendose en el
// visor del Mac que le toca:
//
// - la hoja-pagina (`PAGINA`): la pagina del PDF del proyecto con lo
//   dibujado encima; se abre en el lienzo con la pagina de fondo;
// - el proyecto entero (`PROYECTO`): la puerta a ese proyecto;
// - el croquis 3D del movil (`CROQUIS`): se abre en el visor 3D;
// - la foto anotada en el movil: su lienzo propio, encima de la foto (lo
//   usa `BurbujaImagen`);
// - el punto de proyecto (verde o rojo), de quien llego, de donde viene y
//   el lienzo del asistente, debajo de la burbuja.
//
// Lo que se lee del disco se lee fuera del hilo principal y una vez por
// burbuja (`.task`), como el resto de burbujas con fichero.

import AppKit
import PixPinCore
import SwiftUI

// MARK: - Hoja-pagina

/// Una hoja-pagina leida: su fondo y, si lo tiene, su dibujo.
struct PaginaLeida {
    let hoja: HojaDePagina
    let dibujo: DibujoDelChat?
    /// Lo alto de la hoja por cada punto de ancho.
    var proporcion: CGFloat = 1.41

    /// De donde sale el fondo: la imagen vieja o la pagina del PDF.
    var fuente: FuenteFondoLienzo? {
        if let i = hoja.imagen { return .imagen(URL(fileURLWithPath: i)) }
        if let p = hoja.pdf { return .paginaPDF(URL(fileURLWithPath: p), pagina: Int(hoja.pagina)) }
        return nil
    }
}

/// **Una pagina del PDF del proyecto** en el chat, como `HojaDelProyecto`
/// del movil: la hoja con lo anotado encima (lo que se recuerda de ella es
/// lo que se senalo), no una fila con «documento.pdf · pag. 7».
struct BurbujaPagina: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @State private var leida: PaginaLeida?
    @State private var falta = false
    @State private var recargas = 0
    @Environment(\.escalaChat) private var escala

    private var titulo: String {
        if !mensaje.nombre.isEmpty { return mensaje.nombre }
        return "Página \((mensaje.pagina ?? 0) + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let leida, let fuente = leida.fuente {
                    VistaHojaPagina(fuente: fuente, dibujo: leida.dibujo, version: recargas)
                        .alDobleClic(abrir)
                        .frame(width: ladoDeBurbuja * escala,
                               height: ladoDeBurbuja * escala * leida.proporcion)
                } else if falta || leida != nil {
                    Label(titulo, systemImage: "doc.richtext")
                } else {
                    ProgressView().frame(width: ladoDeBurbuja * escala, height: ladoDeBurbuja * 0.7 * escala)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: abrir)
            .help("Doble clic: dibujar encima, en el lienzo")
            Text(titulo).font(.caption).foregroundStyle(.secondary)
            if !mensaje.texto.isEmpty, mensaje.texto != mensaje.nombre {
                Text(mensaje.texto).textSelection(.enabled)
            }
        }
        .contextMenu {
            EntradasDeMensaje {
                Button { abrir() } label: { Label("Dibujar encima", systemImage: "pencil.tip.crop.circle") }
                if let pdf = leida?.hoja.pdf {
                    Button {
                        AbrirDocumento.abrir(URL(fileURLWithPath: pdf), nucleo: almacen.nucleo)
                    } label: { Label("Abrir el documento", systemImage: "doc.text") }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixpinLienzoGuardado)) { aviso in
            guard let r = aviso.object as? String, r == leida?.hoja.dibujo || r == mensaje.referencia else { return }
            recargas += 1
        }
        .task(id: "\(mensaje.id)#\(recargas)") { await leer() }
    }

    /// Lo alto de la hoja por cada punto de ancho (A4 vertical si no se sabe).
    private static func proporcion(_ f: FuenteFondoLienzo?) -> CGFloat {
        guard let f, let fondo = FondoLienzo(f), fondo.tamano.width > 0 else { return 1.41 }
        return min(max(fondo.tamano.height / fondo.tamano.width, 0.3), 1.6)
    }

    private func leer() async {
        let nucleo = almacen.nucleo
        let (chat, id) = (chat, mensaje.id)
        let hoja = await Task.detached(priority: .utility) {
            try? nucleo.hojaDePagina(chat: chat, id: id)
        }.value
        guard let hoja else {
            falta = true
            return
        }
        var dibujo: DibujoDelChat?
        if let d = hoja.dibujo {
            dibujo = await almacen.dibujo(d, en: chat)
            if let dibujo {
                for url in Set(dibujo.fotos.values) {
                    _ = await Miniaturas.compartidas.cargar(url, lado: Int(ladoDeBurbuja * 2))
                }
            }
        }
        var nueva = PaginaLeida(hoja: hoja, dibujo: dibujo)
        nueva.proporcion = BurbujaPagina.proporcion(nueva.fuente)
        leida = nueva
    }

    /// Como Windows al pulsar la hoja: en el lienzo, con la pagina de fondo,
    /// estrenando su dibujo si no lo tiene (y apuntandolo en el mensaje).
    /// Sin hoja en el proyecto donde guardarlo, el documento en el lector.
    private func abrir() {
        let (nucleo, chat, id, titulo, almacen) = (almacen.nucleo, chat, mensaje.id, titulo, almacen)
        let fuente = leida?.fuente
        let pdf = leida?.hoja.pdf
        Task {
            let dibujo = await Task.detached(priority: .userInitiated) {
                try? nucleo.estrenarDibujoDePagina(chat: chat, id: id)
            }.value ?? nil
            if let dibujo {
                VentanasDeLienzo.compartidas.abrir(referencia: dibujo, en: chat, titulo: titulo,
                                                   almacen: almacen, fondo: fuente)
            } else if let pdf {
                AbrirDocumento.abrir(URL(fileURLWithPath: pdf), nucleo: nucleo, titulo: titulo)
            } else {
                NSSound.beep()
            }
        }
    }
}

/// La hoja de fondo y lo dibujado encima, encajados en la vista (la caja
/// manda la hoja: un trazo que se salga no encoge el plano entero).
final class VistaHojaPaginaNS: NSView {
    var fondo: FondoLienzo? { didSet { needsDisplay = true } }
    var lienzo: LienzoLeido? { didSet { needsDisplay = true } }
    var imagen: (UInt64) -> CGImage? = { _ in nil }
    var alDobleClic: (() -> Void)?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let alDobleClic { alDobleClic() } else { super.mouseDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(bounds)
        guard let caja = fondo?.caja ?? lienzo?.caja, caja.width > 0, caja.height > 0 else { return }
        let escala = min(bounds.width / caja.width, bounds.height / caja.height)
        ctx.saveGState()
        ctx.translateBy(x: (bounds.width - caja.width * escala) / 2 - caja.minX * escala,
                        y: (bounds.height - caja.height * escala) / 2 - caja.minY * escala)
        ctx.scaleBy(x: escala, y: escala)
        fondo?.pintar(en: ctx)
        if let lienzo {
            PintorLienzo(lienzo: lienzo, imagen: imagen).pintar(en: ctx, limites: caja)
        }
        ctx.restoreGState()
    }
}

struct VistaHojaPagina: NSViewRepresentable {
    let fuente: FuenteFondoLienzo
    let dibujo: DibujoDelChat?
    /// Cambiarla vuelve a pintar.
    var version: Int
    var dobleClic: (() -> Void)?

    func alDobleClic(_ hacer: @escaping () -> Void) -> VistaHojaPagina {
        var copia = self
        copia.dobleClic = hacer
        return copia
    }

    func makeNSView(context: Context) -> VistaHojaPaginaNS {
        let v = VistaHojaPaginaNS()
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: VistaHojaPaginaNS, context: Context) {
        if v.fondo?.fuente != fuente { v.fondo = FondoLienzo(fuente) }
        let fotos = dibujo?.fotos ?? [:]
        v.imagen = { id in fotos[id].flatMap { Miniaturas.compartidas.enCache($0, lado: Int(ladoDeBurbuja * 2)) } }
        v.lienzo = dibujo?.lienzo
        v.alDobleClic = dobleClic
        v.needsDisplay = true
    }
}

// MARK: - Proyecto entero

/// **Un proyecto entero como acceso directo** (`PROYECTO`): no copia nada,
/// es la puerta a ese proyecto. Pulsarlo lo abre, como en Windows.
struct BurbujaProyecto: View {
    let mensaje: MensajeChat
    let almacen: Almacen
    @Environment(\.escalaChat) private var escala

    private var ficha: FichaChat? {
        guard let r = mensaje.referencia, !r.isEmpty else { return nil }
        return almacen.chats.first { $0.id == r }
    }

    var body: some View {
        let ficha = self.ficha
        HStack(spacing: 10 * escala) {
            Image(systemName: "folder.fill")
                .font(.system(size: 26 * escala))
                .foregroundStyle(ficha == nil ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(ficha?.nombre ?? (mensaje.nombre.isEmpty ? "Proyecto" : mensaje.nombre))
                    .font(.system(size: 13 * escala, weight: .semibold))
                Group {
                    if let ficha {
                        Text(ficha.hojas == 1 ? "Proyecto · 1 hoja" : "Proyecto · \(ficha.hojas) hojas")
                    } else {
                        Text("Este proyecto no está en este Mac")
                    }
                }
                .font(.system(size: 11 * escala)).foregroundStyle(.secondary)
                if !mensaje.texto.isEmpty {
                    Text(mensaje.texto).font(.system(size: 12 * escala)).textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { abrir() }
        .help(ficha == nil ? "" : "Abrir el proyecto")
        .contextMenu {
            EntradasDeMensaje {
                Button { abrir() } label: { Label("Abrir el proyecto", systemImage: "folder") }
                    .disabled(ficha == nil)
            }
        }
    }

    private func abrir() {
        guard let ficha else {
            NSSound.beep()
            return
        }
        PeticionDeChat.compartida.chat = ficha.id
    }
}

// MARK: - Croquis 3D

/// **Un croquis 3D del movil** (`CROQUIS`): lo dibujado en el espacio. Se
/// abre en el visor 3D (girar, mover, acercar, caja de seccion).
struct BurbujaCroquis: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @State private var esta: Bool?
    @Environment(\.escalaChat) private var escala

    /// El texto del mensaje (su primera linea) o el codigo, como Windows.
    static func titulo(_ m: MensajeChat) -> String {
        let fuente = m.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? m.nombre : m.texto
        let linea = fuente.split(separator: "\n", omittingEmptySubsequences: true).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return linea.isEmpty ? "Croquis \(m.referencia ?? "")" : linea
    }

    var body: some View {
        HStack(spacing: 10 * escala) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 26 * escala))
                .foregroundStyle(esta == false ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(BurbujaCroquis.titulo(mensaje)).font(.system(size: 13 * escala, weight: .semibold))
                Text(esta == false ? "Croquis 3D · aún no ha llegado a este Mac" : "Croquis 3D · doble clic para verlo")
                    .font(.system(size: 11 * escala)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { abrir() }
        .contextMenu {
            EntradasDeMensaje {
                Button { abrir() } label: { Label("Ver en 3D", systemImage: "cube") }.disabled(esta == false)
            }
        }
        .task(id: mensaje.id) {
            guard let r = mensaje.referencia else {
                esta = false
                return
            }
            let (nucleo, chat) = (almacen.nucleo, chat)
            esta = await Task.detached(priority: .utility) { nucleo.croquisDelChat(chat: chat, referencia: r) != nil }.value
        }
    }

    private func abrir() {
        guard esta != false, let r = mensaje.referencia, !r.isEmpty else {
            NSSound.beep()
            return
        }
        VentanasDePlano.compartidas.abrirCroquis(r, en: chat, titulo: BurbujaCroquis.titulo(mensaje),
                                                 nucleo: almacen.nucleo)
    }
}

// MARK: - Foto anotada en el movil

/// Lo dibujado sobre una foto, leido de su lienzo propio.
struct FotoConDibujo {
    let anotada: FotoAnotada
    let dibujo: DibujoDelChat
}

/// El id del lienzo de una foto, como el movil (`dibujoDeLaFoto`): su
/// `referencia` si la tiene y si no `foto-<id del mensaje>`.
func lienzoDeLaFoto(_ m: MensajeChat) -> String {
    if let r = m.referencia, !r.isEmpty { return r }
    return "foto-\(m.id)"
}

/// La caja que se ensena de una foto anotada: la foto sola (`soloLaFoto`,
/// lo normal) o la foto con todo lo dibujado alrededor.
func cajaDeFotoAnotada(foto: CGRect?, todo: CGRect?, soloLaFoto: Bool) -> CGRect? {
    guard let foto else { return todo }
    guard !soloLaFoto, let todo else { return foto }
    return foto.union(todo)
}

/// **La foto con lo que se le dibujo encima en el movil** (o aqui, en su
/// lienzo): el lienzo propio pintado y recortado a la foto.
struct VistaFotoAnotada: View {
    let leida: FotoConDibujo
    let soloLaFoto: Bool
    var version: Int
    let abrir: () -> Void
    @Environment(\.escalaChat) private var escala

    var body: some View {
        var lienzo = leida.dibujo.lienzo
        let foto = leida.anotada.foto.map {
            CGRect(x: CGFloat($0.x0), y: CGFloat($0.y0), width: CGFloat($0.x1 - $0.x0), height: CGFloat($0.y1 - $0.y0))
        }
        lienzo.caja = cajaDeFotoAnotada(foto: foto, todo: lienzo.caja, soloLaFoto: soloLaFoto)
        let caja = lienzo.caja ?? CGRect(x: 0, y: 0, width: 4, height: 3)
        // Con la forma de la foto, como una imagen normal: ancha, a lo
        // ancho de la burbuja; alta, hasta 1,4 veces y mas estrecha.
        let alto = caja.height / max(caja.width, 1)
        let lado = ladoDeBurbuja * escala
        let (w, h) = alto > 1.4 ? (lado * 1.4 / alto, lado * 1.4) : (lado, lado * alto)
        let fotos = leida.dibujo.fotos
        return VistaLienzo(lienzo: lienzo, version: version) { id in
            fotos[id].flatMap { Miniaturas.compartidas.enCache($0, lado: Int(ladoDeBurbuja * 2)) }
        }
        .sinMargen()
        .alDobleClic(abrir)
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Anotada · doble clic: seguir dibujando")
    }
}

/// Lee el lienzo de una foto si esta anotada (fuera del hilo principal).
@MainActor
func leerFotoAnotada(_ m: MensajeChat, chat: String, almacen: Almacen) async -> FotoConDibujo? {
    let nucleo = almacen.nucleo
    let id = lienzoDeLaFoto(m)
    let anotada = await Task.detached(priority: .utility) {
        try? nucleo.fotoAnotada(chat: chat, lienzo: id)
    }.value ?? nil
    guard let anotada, let dibujo = await almacen.dibujo(anotada.lienzo, en: chat) else { return nil }
    for url in Set(dibujo.fotos.values) {
        _ = await Miniaturas.compartidas.cargar(url, lado: Int(ladoDeBurbuja * 2))
    }
    return FotoConDibujo(anotada: anotada, dibujo: dibujo)
}

/// **Abre la foto en SU lienzo**, como el movil y Windows: el que trajo de
/// alli o uno que se estrena aqui con la foto dentro (`asegurar`).
@MainActor
func anotarFoto(_ m: MensajeChat, chat: String, almacen: Almacen) {
    let (nucleo, id) = (almacen.nucleo, m.id)
    let titulo = m.nombre.isEmpty ? "Foto" : m.nombre
    Task {
        let lienzo = await Task.detached(priority: .userInitiated) {
            try? nucleo.asegurarLienzoDeFoto(chat: chat, id: id)
        }.value
        guard let lienzo else {
            NSSound.beep()
            return
        }
        VentanasDeLienzo.compartidas.abrir(referencia: lienzo, en: chat, titulo: titulo, almacen: almacen)
    }
}

// MARK: - Lo de debajo de la burbuja

/// **El punto de proyecto**: verde si vive tambien en las hojas de un
/// proyecto, rojo si solo en el chat (con un halo blanco, que se lea sobre
/// cualquier fondo).
struct PuntoDeProyecto: View {
    let verde: Bool
    @Environment(\.escalaChat) private var escala

    var body: some View {
        Circle()
            .fill(verde ? Color(red: 0x2E / 255, green: 0x9E / 255, blue: 0x4F / 255)
                : Color(red: 0xD2 / 255, green: 0x4B / 255, blue: 0x3E / 255))
            .padding(1.5 * escala)
            .background(Circle().fill(.white))
            .frame(width: 9 * escala, height: 9 * escala)
            .help(verde ? "También está en un proyecto" : "Solo está en el chat")
            .accessibilityLabel(verde ? "En un proyecto" : "Solo en el chat")
    }
}

/// Lo que el movil o Windows dicen del mensaje y va debajo de su burbuja:
/// de donde viene (la zona de un lienzo, que lleva a el), el lienzo donde
/// dibujo el asistente y de quien llego.
struct PieDelMovil: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @Environment(\.escalaChat) private var escala

    var body: some View {
        if let v = mensaje.vieneDe {
            Button {
                abrirLienzo(mensaje.vieneDeDibujo, titulo: v)
            } label: {
                Label(v, systemImage: "arrow.turn.up.left").font(.system(size: 11 * escala))
            }
            .buttonStyle(.link)
            .disabled(mensaje.vieneDeDibujo == nil)
            .help(mensaje.vieneDeDibujo == nil ? v : "Ir al lienzo de donde salió")
        }
        if let l = mensaje.lienzoIa {
            Button {
                abrirLienzo(l, titulo: "Lienzo del asistente")
            } label: {
                Label("Abrir lienzo", systemImage: "scribble.variable").font(.system(size: 12 * escala))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if let r = mensaje.recibidoDe {
            Label("De \(r)", systemImage: "wifi")
                .font(.system(size: 10 * escala)).foregroundStyle(.secondary)
        }
    }

    private func abrirLienzo(_ id: String?, titulo: String) {
        guard let id, !id.isEmpty else { return }
        VentanasDeLienzo.compartidas.abrir(referencia: id, en: chat, titulo: titulo, almacen: almacen)
    }
}

// MARK: - Lista de tareas (MINIAPP «tareas»)

/// Una lista de tareas del movil o de Windows: una ficha con su nombre y lo
/// hecho («3 de 7»), como `fila_de_fichero` de Windows. Pulsarla abre la
/// ventana de Tareas en esa lista.
struct BurbujaTareas: View {
    let mensaje: MensajeChat
    @Environment(\.escalaChat) private var escala
    @Environment(\.openWindow) private var abrirVentana

    static func esTareas(_ m: MensajeChat) -> Bool { m.miniapp == "tareas" }

    /// Las tareas del texto (`- [ ]` / `- [x]`): hechas y total.
    static func cuenta(_ texto: String) -> (hechas: Int, total: Int) {
        var h = 0, t = 0
        for l in texto.split(separator: "\n") {
            let s = l.trimmingCharacters(in: .whitespaces).lowercased()
            if s.hasPrefix("- [ ]") || s.hasPrefix("* [ ]") { t += 1 }
            else if s.hasPrefix("- [x]") || s.hasPrefix("* [x]") { t += 1; h += 1 }
        }
        return (h, t)
    }

    private var nombre: String {
        if !mensaje.nombre.isEmpty { return mensaje.nombre }
        let primera = mensaje.texto.split(separator: "\n").first.map(String.init) ?? ""
        let limpia = primera.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        return limpia.isEmpty ? "Tareas" : limpia
    }

    var body: some View {
        let c = Self.cuenta(mensaje.texto)
        HStack(spacing: 10 * escala) {
            Image(systemName: "checklist")
                .font(.system(size: 24 * escala))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre).font(.system(size: 13 * escala, weight: .semibold))
                Text(c.total == 0 ? "Lista de tareas · vacía" : "Lista de tareas · \(c.hechas) de \(c.total)")
                    .font(.system(size: 11 * escala)).foregroundStyle(.secondary)
                if c.total > 0 {
                    ProgressView(value: Double(c.hechas), total: Double(c.total))
                        .frame(width: 140 * escala)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { abrir() }
        .help("Abrir la lista en Tareas")
        .contextMenu {
            EntradasDeMensaje {
                Button { abrir() } label: { Label("Abrir en Tareas", systemImage: "checklist") }
            }
        }
    }

    private func abrir() {
        VentanaTareas.listaPedida = nombre
        abrirVentana(id: IdVentana.tareas)
        NotificationCenter.default.post(name: .pixpinAbrirListaTareas, object: nombre)
    }
}

extension Notification.Name {
    /// Abrir la ventana de Tareas en una lista (su nombre en `object`).
    static let pixpinAbrirListaTareas = Notification.Name("PixPinAbrirListaTareas")
}

// MARK: - Hoja nota (transcripcion y notas del proyecto)

/// Una hoja nota del proyecto (una transcripcion de voz, una nota de la
/// galeria): una ficha con su titulo y el principio del texto, sin la
/// sintaxis cruda; pulsarla la abre en el editor de notas, como Windows (H12).
struct BurbujaHojaNota: View {
    let mensaje: MensajeChat
    let chat: String
    let almacen: Almacen
    @Environment(\.escalaChat) private var escala

    static func esHoja(_ m: MensajeChat) -> Bool {
        guard let r = m.referencia, !r.isEmpty else { return false }
        return !m.esDelAsistente
    }

    /// Titulo y cuerpo, sin `# `, sin imagenes ni audios incrustados.
    static func partes(_ m: MensajeChat) -> (titulo: String, cuerpo: String, audio: Bool) {
        var titulo = m.nombre, cuerpo: [String] = [], audio = false
        for l in m.texto.components(separatedBy: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("![") { if t.lowercased().contains("audio") || t.hasSuffix(".m4a)") { audio = true }; continue }
            if t.hasPrefix("#") {
                let h = t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if titulo.isEmpty { titulo = h }
                if h == titulo { continue }
            }
            cuerpo.append(l)
        }
        let c = cuerpo.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (titulo.isEmpty ? "Nota" : titulo, c, audio)
    }

    var body: some View {
        let p = Self.partes(mensaje)
        HStack(alignment: .top, spacing: 10 * escala) {
            Image(systemName: p.audio ? "waveform.and.mic" : "doc.text")
                .font(.system(size: 22 * escala))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28 * escala)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.titulo).font(.system(size: 13 * escala, weight: .semibold))
                if !p.cuerpo.isEmpty {
                    Text(textoConFormato(p.cuerpo))
                        .font(.system(size: 12 * escala))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { abrir() }
        .help("Abrir la nota")
        .contextMenu {
            EntradasDeMensaje {
                Button { abrir() } label: { Label("Abrir la nota", systemImage: "doc.text") }
            }
        }
    }

    private func abrir() { EditoresDeNotas.compartidos.abrir(mensaje, en: chat, almacen: almacen) }
}
