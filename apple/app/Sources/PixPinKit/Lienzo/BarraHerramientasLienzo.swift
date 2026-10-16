// **La barra de herramientas del lienzo**, con el aspecto de la de Windows
// (`apps/pixpin/src/caja_dibujo.rs`, que copia la de Excalidraw): una isla
// blanca flotando arriba en el centro, botones cuadrados de 36 con el icono
// oscuro, fondo lila en la herramienta puesta y al pasar el raton,
// separadores entre secciones y la letra del atajo en la esquina. Cada
// grupo ensena su cara y un piquito; al pulsarlo coge la cara y despliega
// sus hermanas debajo, en otra isla con su nombre y su tecla. Si la ventana
// es estrecha, la barra se parte en dos filas por un separador, como en
// Windows (`CajaHerramientas::barra_superior`).

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Las medidas de Windows (`caja_herramientas.rs` y `panel_lateral.rs`), en
/// puntos.
enum MedidasBarraLienzo {
    static let lado: CGFloat = 36
    static let hueco: CGFloat = 4
    static let relleno: CGFloat = 4
    static let distanciaBorde: CGFloat = 16
    static let separador: CGFloat = 1
    static let margenSeparador: CGFloat = 4
    static let altoSeparador: CGFloat = 24
    static let radio: CGFloat = 8
    static let icono: CGFloat = 16
    /// El desplegable de un grupo: 212 de ancho, filas de 32.
    static let anchoMenu: CGFloat = 212
    static let filaMenu: CGFloat = 32
    static let rellenoMenu: CGFloat = 6
    static let bajoLaBarra: CGFloat = 6
    /// El panel de estilo, debajo de la barra (16 + 36 + 24).
    static let yPanel: CGFloat = 76
}

/// Los colores de la barra, del tema claro u oscuro de Excalidraw
/// (`TemaBarra` de Windows).
struct TemaBarraLienzo {
    let isla: Color
    let icono: Color
    let hover: Color
    let activoFondo: Color
    let activoIcono: Color
    let tecla: Color
    let separador: Color
    let menuElegida: Color
    let menuIconoElegido: Color

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255, opacity: 1)
    }

    static let claro = TemaBarraLienzo(
        isla: hex(0xffffff), icono: hex(0x1b1b1f), hover: hex(0xf1f0ff), activoFondo: hex(0xe0dfff),
        activoIcono: hex(0x030064), tecla: hex(0xb8b8b8), separador: hex(0xf1f0ff),
        menuElegida: hex(0xe3e2fe), menuIconoElegido: hex(0x5b57d1))

    static let oscuro = TemaBarraLienzo(
        isla: hex(0x232329), icono: hex(0xe3e3e8), hover: hex(0x2e2d39), activoFondo: hex(0x403e6a),
        activoIcono: hex(0xe0dfff), tecla: hex(0x7a7a7a), separador: hex(0x2e2d39),
        menuElegida: hex(0x4f4d6f), menuIconoElegido: hex(0xb2aeff))

    static func de(_ modelo: ModeloEditorLienzo) -> TemaBarraLienzo {
        modelo.papelOscuro ? oscuro : claro
    }
}

/// La isla de Excalidraw: fondo, esquinas de 8 y su sombra suave.
struct IslaLienzo: ViewModifier {
    let tema: TemaBarraLienzo

    func body(content: Content) -> some View {
        content
            .background(tema.isla, in: RoundedRectangle(cornerRadius: MedidasBarraLienzo.radio))
            .shadow(color: .black.opacity(0.17), radius: 0.5)
            .shadow(color: .black.opacity(0.08), radius: 1.5)
            .shadow(color: .black.opacity(0.05), radius: 7, y: 7)
    }
}

/// Donde cae cada grupo en la barra, para colgarle su desplegable.
struct AnclasGruposLienzo: PreferenceKey {
    static let defaultValue: [GrupoHerramientaLienzo: Anchor<CGRect>] = [:]

    static func reduce(value: inout [GrupoHerramientaLienzo: Anchor<CGRect>],
                       nextValue: () -> [GrupoHerramientaLienzo: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension ModeloEditorLienzo {
    /// El clic en el boton de un grupo (`dibujo::grupos::pulsar`).
    func pulsarGrupo(_ g: GrupoHerramientaLienzo) {
        let clic = GruposBarraLienzo.pulsar(g, activa: herramienta, desplegado: desplegado)
        if let h = clic.elegir { elegir(h) }
        desplegado = clic.desplegado
    }

    /// Una hermana elegida en el desplegable: se coge (o se hace, si es una
    /// accion, y queda de cara del grupo) y se cierra.
    func elegirDelDesplegable(_ id: String) {
        desplegado = nil
        guard let h = HerramientaLienzo.con(id: id), h.accion else {
            elegir(id)
            return
        }
        GruposBarraLienzo.usado(id)
        hacer(id)
    }

    /// Las acciones de los grupos.
    func hacer(_ accion: String) {
        switch accion {
        case "imagen": meterImagen()
        case "compartir": compartir()
        case "imprimir": imprimir()
        default: break
        }
    }

    /// El boton de imagen: elegir un fichero y meterlo en el centro.
    func meterImagen() {
        desplegado = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard let ventana = vista?.window else { return }
        panel.beginSheetModal(for: ventana) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.vista?.meterImagen(desde: url) }
        }
    }

    /// El boton de cerrar: como cerrar la ventana (se guarda al cerrarse),
    /// o lo que diga quien lo hospeda (`alCerrar`: la captura lo descarta).
    func cerrarVentana() {
        if let alCerrar { return alCerrar() }
        vista?.window?.performClose(nil)
    }
}

/// La barra entera, en su isla: en una fila o, si no cabe, en dos partida
/// en `corte`.
struct BarraHerramientasLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    /// Los botones (los del lienzo, o `barraDeCaptura` en la captura).
    var botones = BotonBarraLienzo.barra
    var corte = BotonBarraLienzo.barra.count

    var body: some View {
        let tema = TemaBarraLienzo.de(modelo)
        let n = botones.count
        VStack(alignment: .leading, spacing: MedidasBarraLienzo.relleno) {
            fila(0..<min(corte, n), tema: tema)
            if corte < n { fila(corte..<n, tema: tema) }
        }
        .padding(MedidasBarraLienzo.relleno)
        .modifier(IslaLienzo(tema: tema))
        .fixedSize()
    }

    /// Una fila de la barra. Donde se parte no hay separador: ya separa el
    /// cambio de fila.
    private func fila(_ indices: Range<Int>, tema: TemaBarraLienzo) -> some View {
        HStack(spacing: MedidasBarraLienzo.hueco) {
            ForEach(Array(indices), id: \.self) { i in
                boton(botones[i], tema: tema)
                if i + 1 < indices.upperBound, BotonBarraLienzo.corte(tras: i, en: botones) {
                    Rectangle().fill(tema.separador)
                        .frame(width: MedidasBarraLienzo.separador, height: MedidasBarraLienzo.altoSeparador)
                        .padding(.leading, MedidasBarraLienzo.margenSeparador)
                }
            }
        }
    }

    @ViewBuilder
    private func boton(_ b: BotonBarraLienzo, tema: TemaBarraLienzo) -> some View {
        switch b {
        case let .herramienta(id):
            if let h = HerramientaLienzo.con(id: id) {
                BotonIslaLienzo(icono: h.icono, tecla: h.tecla, elegido: modelo.herramienta == id,
                                tema: tema, ayuda: Self.ayuda(h)) {
                    modelo.desplegado = nil
                    modelo.elegir(id)
                }
            }
        case let .grupo(g):
            let cara = GruposBarraLienzo.cara(g, activa: modelo.herramienta)
            BotonIslaLienzo(icono: cara?.icono ?? .dots, tecla: cara?.tecla,
                            elegido: cara?.id == modelo.herramienta || modelo.desplegado == g,
                            piquito: g.miembros.count > 1, tema: tema,
                            ayuda: "\(g.titulo): \(cara.map(Self.ayuda) ?? "")") {
                modelo.pulsarGrupo(g)
            }
            .anchorPreference(key: AnclasGruposLienzo.self, value: .bounds) { [g: $0] }
        case .figuras:
            BotonIslaLienzo(icono: .library, tema: tema, ayuda: "Figuras: gráfica, tabla, plano y las guardadas") {
                modelo.desplegado = nil
                modelo.abrirFiguras()
            }
        case .deshacer:
            BotonIslaLienzo(icono: .undo, tema: tema, apagado: !modelo.puedeDeshacer, ayuda: "Deshacer (⌘Z)") {
                modelo.deshacer()
            }
            .keyboardShortcut("z", modifiers: .command)
        case .rehacer:
            BotonIslaLienzo(icono: .redo, tema: tema, ayuda: "Rehacer (⇧⌘Z)") { modelo.rehacer() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        case .salir:
            BotonIslaLienzo(icono: .close, tema: tema, ayuda: "Cerrar el lienzo") { modelo.cerrarVentana() }
        }
    }

    static func ayuda(_ h: HerramientaLienzo) -> String {
        if let t = h.tecla { return "\(h.titulo) — \(String(t).uppercased())" }
        return h.titulo
    }
}

/// Un boton cuadrado de la isla: el icono centrado, la letra en la esquina
/// y el piquito de los grupos.
struct BotonIslaLienzo: View {
    let icono: IconoLienzo
    var tecla: Character?
    var elegido = false
    var piquito = false
    let tema: TemaBarraLienzo
    var apagado = false
    let ayuda: String
    let accion: () -> Void

    @State private var encima = false

    var body: some View {
        let color = elegido ? tema.activoIcono : tema.icono
        Button(action: accion) {
            ZStack {
                RoundedRectangle(cornerRadius: MedidasBarraLienzo.radio)
                    .fill(elegido ? tema.activoFondo : (encima && !apagado ? tema.hover : Color.clear))
                IconoLienzoVista(icono: icono, lado: MedidasBarraLienzo.icono, color: color)
                    .opacity(apagado ? 0.35 : 1)
                if let tecla {
                    Text(String(tecla).uppercased())
                        .font(.system(size: 10))
                        .foregroundStyle(elegido ? tema.activoIcono : tema.tecla)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 4)
                        .padding(.bottom, 1)
                }
                if piquito {
                    // El piquito de los grupos con hermanas: sin el, nada
                    // dice que ese boton esconde mas herramientas.
                    Canvas { ctx, tam in
                        let (cx, y) = (tam.width / 2, tam.height - 6)
                        var p = Path()
                        p.move(to: CGPoint(x: cx - 3, y: y))
                        p.addLine(to: CGPoint(x: cx + 3, y: y))
                        p.addLine(to: CGPoint(x: cx, y: y + 2.5))
                        p.closeSubpath()
                        ctx.fill(p, with: .color(color))
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: MedidasBarraLienzo.lado, height: MedidasBarraLienzo.lado)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(apagado)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

/// **El desplegable del grupo abierto**, colgado bajo su boton: una isla
/// con una fila por hermana (icono, nombre y tecla), la puesta marcada.
struct MenuGrupoLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    let anclas: [GrupoHerramientaLienzo: Anchor<CGRect>]

    var body: some View {
        GeometryReader { geo in
            if let g = modelo.desplegado, let ancla = anclas[g] {
                let r = geo[ancla]
                let tema = TemaBarraLienzo.de(modelo)
                let x = min(max(r.minX, 0), max(0, geo.size.width - MedidasBarraLienzo.anchoMenu))
                VStack(spacing: 1) {
                    ForEach(g.miembros) { h in
                        FilaMenuLienzo(h: h, elegida: h.id == modelo.herramienta, tema: tema) {
                            modelo.elegirDelDesplegable(h.id)
                        }
                    }
                }
                .padding(MedidasBarraLienzo.rellenoMenu)
                .frame(width: MedidasBarraLienzo.anchoMenu)
                .modifier(IslaLienzo(tema: tema))
                .offset(x: x, y: r.maxY + MedidasBarraLienzo.relleno + MedidasBarraLienzo.bajoLaBarra)
            }
        }
    }
}

/// Una fila del desplegable (el `DropdownMenu` de Excalidraw).
struct FilaMenuLienzo: View {
    let h: HerramientaLienzo
    let elegida: Bool
    let tema: TemaBarraLienzo
    let accion: () -> Void

    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                IconoLienzoVista(icono: h.icono, lado: MedidasBarraLienzo.icono,
                                 color: elegida ? tema.menuIconoElegido : tema.icono)
                Text(h.titulo).font(.system(size: 13)).foregroundStyle(tema.icono)
                Spacer(minLength: 4)
                if let t = h.tecla {
                    Text(String(t).uppercased()).font(.system(size: 12)).foregroundStyle(tema.tecla)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: MedidasBarraLienzo.filaMenu)
            .background(elegida ? tema.menuElegida : (encima ? tema.hover : Color.clear),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .accessibilityLabel(h.titulo)
    }
}
