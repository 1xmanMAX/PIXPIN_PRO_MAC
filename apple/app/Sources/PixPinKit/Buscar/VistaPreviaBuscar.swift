// **La vista previa del buscador** (D8, la columna derecha de la maqueta
// `Buscar2-resultados` de Windows): lo elegido en grande, segun lo que es.
//
// - una captura: la foto, sus medidas y su peso, cuando caduca (o
//   «Conservada») y el boton de conservar;
// - un fichero: su miniatura (Quick Look) o la foto, y el trozo de dentro
//   donde esta lo buscado;
// - un mensaje o una tarea: su pagina del chat alrededor, desplazada hasta
//   el y marcado;
// - una leccion: su ficha (que paso, por que, la proxima vez);
// - un momento: su foto, su texto y su fecha;
// - una accion: lo que hara.
//
// Encima, con → , el menu de mas acciones.

import AppKit
import PixPinCore
import QuickLookThumbnailing
import SwiftUI

struct VistaPreviaBuscar: View {
    @ObservedObject var modelo: ModeloBuscar
    let hacer: (OrdenBuscar) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let f = modelo.estado.filaElegida {
                    contenido(f).id(f.id)
                } else {
                    ContentUnavailableView("Elige un resultado", systemImage: "text.magnifyingglass")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let m = modelo.estado.menu {
                MenuBuscarVista(menu: m, elegir: { i in
                    modelo.estado.menu?.elegida = i
                    if let f = modelo.estado.filaElegida, m.opciones.indices.contains(i) {
                        hacer(.opcion(m.opciones[i], f))
                    }
                }, cerrar: { modelo.estado.menu = nil })
                .padding(14)
            }
        }
        .background(Paleta.v2.fondo)
    }

    @ViewBuilder
    private func contenido(_ f: FilaBuscar) -> some View {
        switch f {
        case let .accion(a):
            PreviaAccion(a: a)
        case let .resultado(r):
            switch r.clase {
            case .captura: PreviaCaptura(r: r, conservar: { hacer(.opcion(.conservar, f)) })
            case .fichero: PreviaFichero(r: r, almacen: modelo.almacen)
            case .leccion: PreviaLeccion(r: r, nucleo: modelo.almacen.nucleo)
            case .momento: PreviaMomento(r: r)
            case .chat: PreviaChat(r: r)
            case .mensaje, .tarea: PreviaEnChat(r: r, almacen: modelo.almacen)
            }
        }
    }
}

// MARK: - El menu de mas acciones

struct MenuBuscarVista: View {
    let menu: MenuBuscar
    let elegir: (Int) -> Void
    let cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(menu.titulo).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.v2.gris).lineLimit(1)
                Spacer()
                Button(action: cerrar) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Paleta.v2.gris).help("Volver (←)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            ForEach(Array(menu.opciones.enumerated()), id: \.offset) { i, o in
                Button { elegir(i) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: o.icono).frame(width: 18)
                        Text(o.titulo).lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(i == menu.elegida ? Color.white : Paleta.v2.texto)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(i == menu.elegida ? Paleta.v2.acento : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: 340)
        .background(Paleta.v2.tarjetaEncima, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }
}

// MARK: - Piezas comunes

/// Una foto del disco, reducida fuera del hilo principal.
struct MiniaturaBuscar: View {
    let ruta: String
    var lado: CGFloat = 480
    var ajustar = false
    @State private var imagen: NSImage?

    var body: some View {
        Group {
            if let imagen {
                Image(nsImage: imagen).resizable()
                    .aspectRatio(contentMode: ajustar ? .fit : .fill)
            } else {
                Color.white.opacity(0.04)
            }
        }
        .task(id: ruta) { imagen = await MiniaturaBuscar.cargar(ruta, lado: lado) }
    }

    /// La miniatura de Quick Look (la de una foto, un PDF, un Word...).
    static func cargar(_ ruta: String, lado: CGFloat) async -> NSImage? {
        let url = URL(fileURLWithPath: ruta)
        let pedido = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: lado, height: lado),
                                                  scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                  representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido).nsImage
    }
}

/// El titulo grande de la previa, con lo de debajo.
private struct CabeceraPrevia: View {
    let r: ResultadoBusqueda

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            textoResaltado(r.titulo.isEmpty ? r.nombreChat : r.titulo, posiciones: r.resaltado,
                           tachado: r.clase == .tarea && r.hecha)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Paleta.v2.texto)
                .lineLimit(3)
                .textSelection(.enabled)
            Text(subtituloDe(r)).font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El trozo donde esta lo buscado, con sus palabras resaltadas.
private struct TrozoPrevia: View {
    let texto: String
    let consulta: String

    var body: some View {
        if !texto.isEmpty {
            Text(resaltarPalabras(texto, consulta))
                .font(.system(size: 13))
                .foregroundStyle(Paleta.v2.cuerpo)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// `texto` con cada palabra de `consulta` resaltada (sin tildes ni
/// mayusculas).
func resaltarPalabras(_ texto: String, _ consulta: String) -> AttributedString {
    var a = AttributedString(texto)
    for p in consulta.split(whereSeparator: \.isWhitespace) where p.count >= 2 {
        var desde = texto.startIndex
        while let r = texto.range(of: p, options: [.caseInsensitive, .diacriticInsensitive], range: desde ..< texto.endIndex) {
            if let i = AttributedString.Index(r.lowerBound, within: a),
               let j = AttributedString.Index(r.upperBound, within: a) {
                a[i ..< j].foregroundColor = Paleta.v2.acento
                a[i ..< j].inlinePresentationIntent = .stronglyEmphasized
            }
            desde = r.upperBound
        }
    }
    return a
}

/// «412 KB», «1,2 MB» (`peso_legible` de Windows).
func pesoLegible(_ bytes: UInt64) -> String {
    if bytes >= 1024 * 1024 {
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)).replacingOccurrences(of: ".", with: ",")
    }
    return "\((bytes + 1023) / 1024) KB"
}

// MARK: - Cada clase

private struct PreviaCaptura: View {
    let r: ResultadoBusqueda
    let conservar: () -> Void
    @State private var medidas: CGSize?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let ruta = r.ruta {
                    MiniaturaBuscar(ruta: ruta, lado: 900, ajustar: true)
                        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 340)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                CabeceraPrevia(r: r)
                HStack(spacing: 8) {
                    Text(lineaMedidas).foregroundStyle(Paleta.v2.cuerpo)
                    Spacer()
                }
                .font(.system(size: 12.5))
                HStack(spacing: 10) {
                    Text(caducidad)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(r.conservada ? Paleta.v2.verde : Paleta.v2.naranja)
                    Spacer()
                    if !r.conservada {
                        BotonCabecera(icono: "square.and.arrow.down", rotulo: "Conservar",
                                      ayuda: "Conservar: no caduca", accion: conservar)
                    }
                }
                if r.dentro {
                    Titulillo("En su texto")
                    TrozoPrevia(texto: r.fragmento, consulta: "")
                }
            }
            .padding(16)
        }
        .task(id: r.ruta) {
            guard let ruta = r.ruta, let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil),
                  let p = CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any],
                  let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return }
            medidas = CGSize(width: w, height: h)
        }
    }

    private var lineaMedidas: String {
        var v = [r.tipo == "VIDEO" ? "Vídeo" : "Captura"]
        if let m = medidas { v.append("\(Int(m.width)) × \(Int(m.height))") }
        v.append(pesoLegible(r.bytes))
        return v.joined(separator: " · ")
    }

    private var caducidad: String {
        if r.conservada { return "Conservada: no caduca" }
        guard let d = r.diasQueQuedan else { return "No caduca" }
        return d <= 0 ? "Caduca hoy" : "Caduca en \(d) \(d == 1 ? "día" : "días")"
    }
}

private struct PreviaFichero: View {
    let r: ResultadoBusqueda
    let almacen: Almacen

    var body: some View {
        if r.ruta == nil || r.tipo == "DIBUJO" || r.tipo == "PAGINA" {
            // Sin fichero aqui (de otro aparato, o un lienzo del chat): su
            // sitio en el chat.
            PreviaEnChat(r: r, almacen: almacen)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let ruta = r.ruta {
                        MiniaturaBuscar(ruta: ruta, lado: 700, ajustar: true)
                            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 320)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    CabeceraPrevia(r: r)
                    if r.bytes > 0 {
                        Text(pesoLegible(r.bytes)).font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
                    }
                    if !r.fragmento.isEmpty {
                        Titulillo(r.dentro ? "Dentro del documento" : (r.tipo == "VOZ" ? "Lo dicho" : "Texto"))
                        TrozoPrevia(texto: r.fragmento, consulta: "")
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct PreviaLeccion: View {
    let r: ResultadoBusqueda
    let nucleo: Nucleo
    @State private var ficha: FichaLeccion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(ficha?.icono ?? "💡").font(.system(size: 26))
                    CabeceraPrevia(r: r)
                }
                if let f = ficha {
                    seccion("Qué pasó", f.quePaso)
                    seccion("Por qué", f.porQue)
                    seccion("La próxima vez", f.proxima)
                    let etiquetas = f.etiquetas + f.etiquetasAuto
                    if !etiquetas.isEmpty {
                        Text(etiquetas.map { "#\($0)" }.joined(separator: "  "))
                            .font(.system(size: 12)).foregroundStyle(Paleta.v2.acento)
                    }
                    HStack(spacing: 12) {
                        if f.veces > 1 { Text("Pasó \(f.veces) veces") }
                        if f.tocaRepasar { Text("Toca repasarla").foregroundStyle(Paleta.v2.naranja) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.v2.gris)
                } else {
                    TrozoPrevia(texto: r.fragmento, consulta: "")
                }
            }
            .padding(16)
        }
        .task(id: r.leccion) {
            guard let id = r.leccion else { return }
            let nucleo = self.nucleo
            ficha = try? await Task.detached(priority: .userInitiated) { try nucleo.leccion(id: id) }.value
        }
    }

    @ViewBuilder
    private func seccion(_ titulo: String, _ texto: String) -> some View {
        if !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Titulillo(titulo)
                Text(texto).font(.system(size: 13)).foregroundStyle(Paleta.v2.cuerpo).textSelection(.enabled)
            }
        }
    }
}

private struct PreviaMomento: View {
    let r: ResultadoBusqueda

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let ruta = r.ruta {
                    MiniaturaBuscar(ruta: ruta, lado: 800, ajustar: true)
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                CabeceraPrevia(r: r)
                Text(fechaDe(ms: r.cuando), format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                    .font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
                TrozoPrevia(texto: r.fragmento, consulta: "")
            }
            .padding(16)
        }
    }
}

private struct PreviaChat: View {
    let r: ResultadoBusqueda

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(Paleta.iniciales(r.nombreChat))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Paleta.avatar(r.chat ?? r.nombreChat), in: Circle())
                CabeceraPrevia(r: r)
            }
            TrozoPrevia(texto: r.fragmento, consulta: "")
            Spacer()
        }
        .padding(16)
    }
}

private struct PreviaAccion: View {
    let a: AccionBuscar

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: a.icono)
                .font(.system(size: 34))
                .foregroundStyle(Paleta.v2.acento)
                .frame(width: 72, height: 72)
                .background(Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 18))
            Text(a.titulo).font(.system(size: 16, weight: .semibold)).foregroundStyle(Paleta.v2.texto)
                .multilineTextAlignment(.center)
            Text(a.subtitulo).font(.system(size: 12.5)).foregroundStyle(Paleta.v2.gris)
            HStack(spacing: 6) {
                Chapa(texto: "↩")
                Text(a.rotuloPrincipal).foregroundStyle(Paleta.v2.gris)
            }
            .font(.system(size: 12))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Un mensaje o una tarea con su pagina del chat alrededor (ya desplazada
/// hasta el y marcado).
struct PreviaEnChat: View {
    let r: ResultadoBusqueda
    let almacen: Almacen
    @State private var alrededor: [MensajeChat] = []
    @State private var fallo: String?

    /// Cuantos mensajes se ensenan antes y despues del encontrado.
    static let margen: UInt64 = 25

    var body: some View {
        VStack(spacing: 0) {
            CabeceraPrevia(r: r).padding(14)
            Paleta.v2.linea.frame(height: 1)
            if let fallo {
                ContentUnavailableView("No se pudo leer el chat", systemImage: "exclamationmark.triangle",
                                       description: Text(fallo))
            } else if let chat = r.chat {
                ScrollViewReader { lector in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(alrededor, id: \.id) { m in
                                Burbuja(mensaje: m, chat: chat, almacen: almacen)
                                    .overlay {
                                        if m.id == r.mensaje {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Paleta.v2.acento, lineWidth: 2)
                                        }
                                    }
                                    .id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: alrededor.count) { _, _ in
                        if let id = r.mensaje { lector.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .task { await cargar() }
    }

    /// La pagina del chat alrededor del mensaje (solo esa).
    private func cargar() async {
        guard let chat = r.chat, let posicion = r.posicion else { return }
        let nucleo = almacen.nucleo
        let desde = posicion > PreviaEnChat.margen ? posicion - PreviaEnChat.margen : 0
        let cuantos = UInt32(posicion - desde + PreviaEnChat.margen + 1)
        do {
            let pagina = try await Task.detached(priority: .userInitiated) {
                try nucleo.mensajes(chat: chat, desde: desde, cuantos: cuantos)
            }.value
            alrededor = pagina.mensajes
        } catch {
            fallo = "\(error)"
        }
    }
}
