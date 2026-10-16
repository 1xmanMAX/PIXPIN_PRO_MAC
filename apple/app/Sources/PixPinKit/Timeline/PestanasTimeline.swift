// Las pestanas «Momentos» y «Calendario», el detalle de un momento y el
// menu de exportar del timeline, como `archivo.rs`, `estado_mes.rs` e
// `historia.rs` de Windows (copiadas de «Mis publicaciones» de WeChat).

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Momentos

/// El archivo: cada dia, su numero grande con el mes y el dia de la semana,
/// y en fila lo que paso (la foto, o el titulo en una tarjeta de color).
/// Clic en una abre su detalle; en el numero, el dia entero.
struct ArchivoTimeline: View {
    @ObservedObject var modelo: ModeloTimeline
    let abrir: (MomentoTimeline, Int) -> Void

    private let columnas = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(modelo.archivo.enumerated()), id: \.element.dia.iso) { i, d in
                    if i == 0 || modelo.archivo[i - 1].dia.anio != d.dia.anio {
                        Text(String(d.dia.anio)).font(.system(size: 26, weight: .bold)).foregroundStyle(Paleta.v2.texto)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Button {
                            Task { await modelo.elegir(.dia(d.dia.iso)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(d.dia.dia)).font(.system(size: 28, weight: .bold))
                                Text("\(d.nombreMes) · \(d.diaCorto)").font(.system(size: 11))
                                    .foregroundStyle(Paleta.v2.gris)
                            }
                            .foregroundStyle(Paleta.v2.texto)
                            .frame(width: 84, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Abrir el día entero")
                        LazyVGrid(columns: columnas, alignment: .leading, spacing: 8) {
                            ForEach(d.momentos, id: \.id) { m in
                                MiniMomento(momento: m)
                                    .onTapGesture { abrir(m, 0) }
                                    .contextMenu { MenuMomento(momento: m, modelo: modelo, abrir: abrir) }
                            }
                        }
                    }
                }
                if modelo.quedaArchivo {
                    ProgressView().frame(maxWidth: .infinity).task { await modelo.cargarMasArchivo() }
                }
            }
            .padding(20)
        }
        .overlay {
            if modelo.archivo.isEmpty {
                Text("Aquí van los momentos que elijas. En «Hoy», pasa el ratón por una tarjeta y pulsa el marcador para mandarla aquí.")
                    .multilineTextAlignment(.center).foregroundStyle(Paleta.v2.gris).frame(maxWidth: 380)
            }
        }
        .task { await modelo.cargarArchivo() }
    }
}

/// Un momento en pequeno: su primera foto, o su titulo sobre un color que
/// sale de su id (siempre el mismo).
struct MiniMomento: View {
    let momento: MomentoTimeline

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let f = momento.fotos.first {
                MiniaturaVista(url: URL(fileURLWithPath: f), lado: 160)
                    .frame(width: 120, height: 120).clipped()
            } else {
                Paleta.avatar(momento.id).opacity(0.55)
                Text(momento.titulo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(4).padding(8)
            }
            if momento.audio != nil {
                Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(.white)
                    .padding(5).background(.black.opacity(0.5), in: Circle()).padding(5)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .help(momento.titulo)
    }
}

// MARK: - Calendario

/// Una tarjeta por mes: el numero del mes en grande, su nombre y lo que
/// mas se repitio; a la derecha sus dias, del mas reciente al 1, con el
/// circulo de cada dia con algo. Clic abre el dia; ⌘clic lo elige para
/// exportar varios juntos.
struct EstadoTimeline: View {
    @ObservedObject var modelo: ModeloTimeline

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(modelo.meses, id: \.nombreCompleto) { mes in
                    TarjetaMes(mes: mes, modelo: modelo)
                }
            }
            .padding(20)
            .padding(.bottom, modelo.elegidos.isEmpty ? 0 : 60)
        }
        .overlay(alignment: .bottom) {
            if !modelo.elegidos.isEmpty {
                HStack(spacing: 12) {
                    Text(modelo.elegidos.count == 1 ? "1 día elegido" : "\(modelo.elegidos.count) días elegidos")
                        .foregroundStyle(Paleta.v2.texto)
                    MenuExportarTimeline(modelo: modelo)
                    BotonCabecera(icono: "xmark", ayuda: "Quitar la elección", tenue: true) { modelo.elegidos = [] }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Paleta.v2.tarjetaEncima, in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 16)
            }
        }
        .task { await modelo.cargarEstado() }
    }
}

extension MesEstado {
    var nombreCompleto: String { "\(anio)-\(mes)" }
}

struct TarjetaMes: View {
    let mes: MesEstado
    @ObservedObject var modelo: ModeloTimeline

    private let columnas = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 10)

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(mes.mes)).font(.system(size: 34, weight: .bold)).foregroundStyle(Paleta.v2.texto)
                Text("\(mes.nombre) \(String(mes.anio))").font(.system(size: 12)).foregroundStyle(Paleta.v2.gris)
                if let lo = mes.loMas {
                    Text(mes.loMasVeces > 1 ? "\(lo) ×\(mes.loMasVeces)" : lo)
                        .font(.system(size: 12)).foregroundStyle(Paleta.v2.cuerpo)
                        .padding(.top, 6)
                        .help("Sobre todo")
                }
            }
            .frame(width: 96, alignment: .leading)
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 10) {
                ForEach(mes.dias, id: \.iso) { d in
                    DiaDelCalendario(dia: d, elegido: modelo.elegidos.contains(d.iso))
                        .onTapGesture {
                            guard d.cuantos > 0 else { return }
                            if NSEvent.modifierFlags.contains(.command) {
                                if modelo.elegidos.contains(d.iso) { modelo.elegidos.remove(d.iso) } else {
                                    modelo.elegidos.insert(d.iso)
                                }
                            } else {
                                Task { await modelo.elegir(.dia(d.iso)) }
                            }
                        }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x262628), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Un dia de la tarjeta: su numero y su circulo (emoticonos apilados, la
/// foto, o la inicial), o un puntito si no tiene nada.
struct DiaDelCalendario: View {
    let dia: DiaEstado
    let elegido: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                switch dia.circulo {
                case let .emoticonos(lista):
                    ZStack {
                        ForEach(Array(lista.prefix(3).enumerated().reversed()), id: \.offset) { i, e in
                            Text(e).font(.system(size: 18))
                                .frame(width: 34, height: 34)
                                .background(Paleta.avatar(e).opacity(0.35), in: Circle())
                                .offset(x: CGFloat(i) * 5, y: CGFloat(-i) * 2)
                        }
                    }
                    if lista.count > 3 {
                        Text("+\(lista.count - 3)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(2).background(Paleta.v2.acento, in: Capsule()).offset(x: 16, y: 14)
                    }
                case let .foto(ruta):
                    MiniaturaVista(url: URL(fileURLWithPath: ruta), lado: 44)
                        .frame(width: 36, height: 36).clipShape(Circle())
                case let .inicial(letra):
                    Text(letra).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Paleta.avatar(dia.iso).opacity(0.6), in: Circle())
                case nil:
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 5, height: 5)
                }
            }
            .frame(width: 40, height: dia.circulo == nil ? 14 : 40)
            .overlay {
                if elegido { Circle().strokeBorder(Paleta.v2.acento, lineWidth: 2.5).frame(width: 42, height: 42) }
            }
            Text(String(dia.dia)).font(.system(size: 11)).foregroundStyle(dia.cuantos > 0 ? Paleta.v2.cuerpo : Paleta.v2.gris)
        }
        .contentShape(Rectangle())
        .help(dia.cuantos == 1 ? "1 momento" : dia.cuantos > 0 ? "\(dia.cuantos) momentos" : "")
    }
}

// MARK: - El detalle

/// El detalle abierto: la lista desde la que se abrio (sus ids, para que
/// ↑/↓ sigan su orden), el momento y su foto.
struct DetalleTimeline: Equatable {
    var lista: [String]
    var id: String
    var foto: Int
}

/// El detalle de un momento (`historia.rs`): la foto entera sobre negro, la
/// fecha arriba, el texto abajo; ←/→ pasan de foto, ↑/↓ de momento, Esc
/// cierra. Los botones de arriba pinean la foto, la anotan en un lienzo y
/// oyen su voz.
struct DetalleMomento: View {
    @ObservedObject var modelo: ModeloTimeline
    let almacen: Almacen
    @Binding var detalle: DetalleTimeline
    let cerrar: () -> Void
    @FocusState private var foco: Bool

    private var momento: MomentoTimeline? {
        modelo.visibles.first { $0.id == detalle.id }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            if let m = momento {
                VStack(spacing: 12) {
                    HStack {
                        Text(fechaDe(ms: m.cuando).formatted(date: .long, time: .shortened))
                            .foregroundStyle(Paleta.v2.gris)
                        Spacer()
                        if !m.fotos.isEmpty {
                            BotonCabecera(icono: "pin", ayuda: "Pinear la foto") { pinear(m) }
                            BotonCabecera(icono: "pencil.and.scribble", ayuda: "Anotar en un lienzo") { anotar(m) }
                        }
                        if let a = m.audio {
                            BotonCabecera(icono: "play.fill", ayuda: "Oír") {
                                ReproductorVoz.compartido.alternar(m.id, url: URL(fileURLWithPath: a))
                            }
                        }
                        BotonCabecera(icono: m.leccion != nil ? "lightbulb.fill" : "lightbulb", ayuda: "Lección") {
                            Task { await modelo.alternarLeccion(m) }
                        }
                        BotonCabecera(icono: "xmark", ayuda: "Cerrar (Esc)", tenue: true) { cerrar() }
                    }
                    if m.fotos.indices.contains(detalle.foto) {
                        let url = URL(fileURLWithPath: m.fotos[detalle.foto])
                        if let img = NSImage(contentsOf: url) {
                            Image(nsImage: img).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if m.fotos.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(m.fotos.indices, id: \.self) { i in
                                    Circle().fill(i == detalle.foto ? Color.white : Color.white.opacity(0.3))
                                        .frame(width: 7, height: 7)
                                        .onTapGesture { detalle.foto = i }
                                }
                            }
                        }
                    } else {
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.titulo).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        if !m.descripcion.isEmpty {
                            Text(m.descripcion).foregroundStyle(Paleta.v2.cuerpo)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
        .focusable()
        .focused($foco)
        .focusEffectDisabled()
        .onAppear { foco = true }
        .onKeyPress(.leftArrow) { mover(foto: -1); return .handled }
        .onKeyPress(.rightArrow) { mover(foto: 1); return .handled }
        .onKeyPress(.upArrow) { mover(momento: -1); return .handled }
        .onKeyPress(.downArrow) { mover(momento: 1); return .handled }
        .onKeyPress(.pageUp) { mover(momento: -1); return .handled }
        .onKeyPress(.pageDown) { mover(momento: 1); return .handled }
        .onKeyPress(.escape) { cerrar(); return .handled }
    }


    /// ←/→: la foto de al lado; pasada la ultima, el momento siguiente.
    private func mover(foto paso: Int) {
        guard let m = momento else { return }
        let n = detalle.foto + paso
        if m.fotos.indices.contains(n) {
            detalle.foto = n
        } else {
            mover(momento: paso, alFinal: paso < 0)
        }
    }

    private func mover(momento paso: Int, alFinal: Bool = false) {
        guard let i = detalle.lista.firstIndex(of: detalle.id) else { return }
        let j = i + paso
        guard detalle.lista.indices.contains(j) else { return }
        detalle.id = detalle.lista[j]
        let fotos = modelo.visibles.first { $0.id == detalle.id }?.fotos.count ?? 0
        detalle.foto = alFinal ? max(0, fotos - 1) : 0
    }

    private func pinear(_ m: MomentoTimeline) {
        guard m.fotos.indices.contains(detalle.foto) else { return }
        if GestorPines.compartido.pinear(fichero: URL(fileURLWithPath: m.fotos[detalle.foto])) {
            modelo.avisar("Pineada")
        } else {
            NSSound.beep()
        }
    }

    /// Un lienzo nuevo en «Mensajes guardados» con la foto de fondo.
    private func anotar(_ m: MomentoTimeline) {
        guard m.fotos.indices.contains(detalle.foto) else { return }
        AnotarEnLienzo.abrir(URL(fileURLWithPath: m.fotos[detalle.foto]), titulo: m.titulo, almacen: almacen)
    }
}

/// Anotar una imagen: un lienzo nuevo en «Mensajes guardados» con ella de
/// fondo (`VentanasDeLienzo.abrir(…, fondo:)`), lo de Windows al anotar una
/// foto o un pin.
@MainActor
enum AnotarEnLienzo {
    static func abrir(_ url: URL, titulo: String, almacen: Almacen) {
        Task {
            guard let guardados = try? almacen.nucleo.chatGuardados(),
                  let m = await almacen.crearLienzo(en: guardados.id), let ref = m.referencia else {
                NSSound.beep()
                return
            }
            VentanasDeLienzo.compartidas.abrir(referencia: ref, en: guardados.id, titulo: titulo,
                                               almacen: almacen, fondo: .imagen(url))
        }
    }
}

// MARK: - Exportar

/// «Exportar» de la barra: lo que se ve, como pagina web o PDF (la misma
/// linea de tiempo de Windows, con las fotos y la voz dentro).
struct MenuExportarTimeline: View {
    @ObservedObject var modelo: ModeloTimeline

    var body: some View {
        Menu {
            Button("Página web (HTML)…") { exportar(pdf: false) }
            Button("Documento PDF…") { exportar(pdf: true) }
            Button("Compartir…") { compartir() }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
                .foregroundStyle(Paleta.v2.texto)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 40, height: 40)
        .background(Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 10))
        .help("Exportar lo que se ve")
        .disabled(modelo.pestana == .lecciones && !modelo.buscando)
    }

    private func pagina() async -> PaginaTimeline? {
        do { return try await modelo.paginaParaExportar() } catch {
            modelo.avisar(ModeloTimeline.esArgumento(error) ? "No hay nada que exportar ahí" : "No se pudo exportar")
            return nil
        }
    }

    private func exportar(pdf: Bool) {
        Task {
            guard let p = await pagina() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [pdf ? .pdf : .html]
            panel.nameFieldStringValue = "\(p.nombre).\(pdf ? "pdf" : "html")"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                if pdf {
                    modelo.avisar("Haciendo el PDF…")
                    try await PaginaAPdf.guardar(p.html, en: url)
                } else {
                    try p.html.write(to: url, atomically: true, encoding: .utf8)
                }
                modelo.avisar("Guardado: \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                modelo.avisar(pdf ? "No se pudo hacer el PDF" : "No se pudo guardar el fichero")
            }
        }
    }

    private func compartir() {
        Task {
            guard let p = await pagina() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(p.nombre).html")
            guard (try? p.html.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
            CompartirMac.mostrar([url])
        }
    }
}

/// Una pagina HTML a PDF con WebKit (lo que en Windows hace Edge sin
/// ventana): se carga en una vista fuera de la pantalla y se imprime a
/// fichero en hojas A4.
@MainActor
enum PaginaAPdf {
    static func guardar(_ html: String, en destino: URL) async throws {
        let vista = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 1100))
        let espera = EsperaCarga()
        vista.navigationDelegate = espera
        vista.loadHTMLString(html, baseURL: nil)
        try await espera.esperar()
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 28
        info.bottomMargin = 28
        info.leftMargin = 28
        info.rightMargin = 28
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destino
        let op = vista.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        // La operacion necesita una ventana, aunque no se vea.
        let ventana = NSWindow(contentRect: vista.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        ventana.contentView = vista
        op.view?.frame = vista.bounds
        guard op.run(), FileManager.default.fileExists(atPath: destino.path) else {
            // Si imprimir no sale, el PDF de una sola hoja larga.
            let datos = try await vista.pdf()
            try datos.write(to: destino)
            return
        }
    }

    /// Espera a que la pagina termine de cargar.
    private final class EsperaCarga: NSObject, WKNavigationDelegate {
        private var continuacion: CheckedContinuation<Void, Error>?
        private var hecho = false

        func esperar() async throws {
            if hecho { return }
            try await withCheckedThrowingContinuation { continuacion = $0 }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hecho = true
            continuacion?.resume()
            continuacion = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            hecho = true
            continuacion?.resume(throwing: error)
            continuacion = nil
        }
    }
}
