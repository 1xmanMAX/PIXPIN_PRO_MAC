// **La barrita de marcar texto** de los lectores (Windows a5b3c24 y a4fd8c8,
// 1-nov-2026): leyendo (no con el lapiz), al elegir texto sale encima de lo
// elegido la barra de los pines: copiar, los cinco colores, resaltar,
// ondulada, subrayar, tachar, tapar y quitar.
//
// Donde va y que botones lleva lo dice el nucleo
// (`disponerBarritaDeMarcar`, `pindesk_ui::barra_marcar`); los colores son
// los de `marcas_texto` (`coloresDeMarcar`). Aqui solo se pinta: el cristal
// oscuro de las barras del lector (siempre oscuro, como en Windows, asi que
// se lee igual de dia y de noche) y los dibujitos de `barra_marcas.rs`: una
// «A» con la marca puesta, del color elegido. El nombre de cada boton sale
// como globo del Mac (`help`), con los textos de `main.ftl`.
//
// Lo usan el lector de PDF y Office (`LectorDocumento.swift`) y el visor de
// Word, libros y paginas (`VisorReflujo.swift`).

import AppKit
import PixPinCore
import SwiftUI

/// Lo de marcar de un lector: el color elegido y la barrita de ahora.
@MainActor
final class ModeloMarcar: ObservableObject {
    /// El color elegido (`coloresDeMarcar`), el amarillo al empezar.
    @Published var color: UInt8 = colorInicialDeMarcar()
    /// La barrita dispuesta (en puntos desde arriba a la izquierda de la
    /// vista que la lleva), o nada si no se ve.
    @Published var barrita: BarritaDeMarcar?
    /// La marca elegida con un clic encima (su grupo `marca-texto-<ms>`):
    /// otra marca la cambia y el circulo tachado la quita.
    var deMarca: String?
    /// Lo que hace cada boton (`que` del nucleo: `copiar`, `color`, `quitar`
    /// o el nombre de la marca).
    var pulsar: ((BotonDeMarcar) -> Void)?

    /// **Pone la barrita** junto a `zona` (lo elegido que se ve, en puntos de
    /// `vista` desde arriba a la izquierda) en la vista `anfitrion`, que se
    /// coloca encima. Sin zona, se esconde.
    func poner(zona: CGRect?, en vista: NSView, anfitrion: NSView) {
        guard let z = zona, !z.isNull, z.width > 0 || z.height > 0 else { return quitar(anfitrion) }
        let b = vista.bounds
        let r = disponerBarritaDeMarcar(
            eleccion: CajaDeMarca(x0: Float(z.minX), y0: Float(z.minY), x1: Float(z.maxX), y1: Float(z.maxY)),
            ancho: Float(b.width), alto: Float(b.height), escala: 1)
        barrita = r
        let y = vista.isFlipped ? CGFloat(r.y) : b.height - CGFloat(r.y) - CGFloat(r.alto)
        anfitrion.frame = NSRect(x: CGFloat(r.x), y: y, width: CGFloat(r.ancho), height: CGFloat(r.alto))
        anfitrion.isHidden = false
    }

    func quitar(_ anfitrion: NSView) {
        if barrita != nil { barrita = nil }
        anfitrion.isHidden = true
    }

    /// Lo de una zona en puntos de `vista` llevado a «desde arriba» (lo que
    /// pide el nucleo), recortado a lo que se ve.
    static func desdeArriba(_ r: CGRect, en vista: NSView) -> CGRect? {
        let b = vista.bounds
        let dentro = r.intersection(b)
        guard !dentro.isNull, dentro.width > 0 || dentro.height > 0 else { return nil }
        if vista.isFlipped { return dentro }
        return CGRect(x: dentro.minX, y: b.height - dentro.maxY, width: dentro.width, height: dentro.height)
    }
}

/// Los cinco colores de las marcas, ya hechos (los de `marcas_texto`).
enum ColoresDeMarcar {
    static let todos: [Color] = coloresDeMarcar().map { hex in
        Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0xF5C218)
    }

    static func color(_ k: UInt8) -> Color {
        todos[min(Int(k), todos.count - 1)]
    }
}

/// La vista de la barrita: un `NSHostingView` del tamano de la barrita.
struct BarritaMarcarVista: View {
    @ObservedObject var modelo: ModeloMarcar
    @State private var encima: Int?

    private static let cristal = Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.97)
    private static let tinta = Color(red: 0.96, green: 0.96, blue: 0.97)

    var body: some View {
        if let b = modelo.barrita {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(BarritaMarcarVista.cristal)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                // La raya entre copiar y los colores.
                Rectangle()
                    .fill(BarritaMarcarVista.tinta.opacity(0.25))
                    .frame(width: 1, height: CGFloat(b.alto) * 0.5)
                    .offset(x: CGFloat(b.raya - b.x), y: CGFloat(b.alto) * 0.25)
                ForEach(Array(b.botones.enumerated()), id: \.offset) { i, boton in
                    botonVista(boton, i: i)
                        .frame(width: CGFloat(boton.ancho), height: CGFloat(boton.alto))
                        .offset(x: CGFloat(boton.x - b.x), y: CGFloat(boton.y - b.y))
                }
            }
            .frame(width: CGFloat(b.ancho), height: CGFloat(b.alto), alignment: .topLeading)
            .environment(\.colorScheme, .dark)
        }
    }

    @ViewBuilder
    private func botonVista(_ boton: BotonDeMarcar, i: Int) -> some View {
        let fondo = encima == i && boton.que != "color"
        Button {
            modelo.pulsar?(boton)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(fondo ? BarritaMarcarVista.tinta.opacity(0.12) : Color.clear)
                IconoDeMarcar(que: boton.que, color: boton.color, elegido: modelo.color,
                              tinta: BarritaMarcarVista.tinta, fondo: BarritaMarcarVista.cristal)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { dentro in
            if dentro { encima = i } else if encima == i { encima = nil }
        }
        .help(boton.clave.isEmpty ? "" : Lengua.t(boton.clave))
    }
}

/// **El dibujito de un boton** (`pindesk_pin::barra_marcas::pintar_icono`).
struct IconoDeMarcar: View {
    let que: String
    let color: UInt8
    let elegido: UInt8
    let tinta: Color
    let fondo: Color

    var body: some View {
        switch que {
        case "copiar":
            Image(systemName: "doc.on.doc")
                .font(.system(size: 15))
                .foregroundStyle(tinta)
        case "color":
            ZStack {
                if color == elegido {
                    Circle().fill(tinta).frame(width: 17, height: 17)
                    Circle().fill(fondo).frame(width: 14, height: 14)
                }
                Circle().fill(ColoresDeMarcar.color(color)).frame(width: 11, height: 11)
            }
        default:
            Canvas { ctx, tam in
                pintar(&ctx, tam)
            }
        }
    }

    private func pintar(_ ctx: inout GraphicsContext, _ tam: CGSize) {
        let c = ColoresDeMarcar.color(elegido)
        let cx = tam.width / 2, cy = tam.height / 2
        let (x0, x1) = (cx - 9, cx + 9)
        let abajo = cy + 10
        func letra(_ ctx: inout GraphicsContext) {
            ctx.draw(Text("A").font(.system(size: 16)).foregroundStyle(tinta), at: CGPoint(x: cx, y: cy - 1))
        }
        func raya(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ grosor: CGFloat) {
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: grosor, lineCap: .round))
        }
        switch que {
        case "resaltar":
            ctx.fill(Path(roundedRect: CGRect(x: x0 - 1, y: cy - 10, width: x1 - x0 + 2, height: 20), cornerRadius: 3),
                     with: .color(c.opacity(0.55)))
            letra(&ctx)
        case "ondulada":
            letra(&ctx)
            // Una ola cada cuatro pasos, como `marcas_texto::onda`.
            var p = Path()
            let paso: CGFloat = 1.2, amplitud: CGFloat = 1.6
            var x = x0
            var k = 0
            p.move(to: CGPoint(x: x0, y: abajo))
            while x < x1 {
                k += 1
                x = min(x0 + CGFloat(k) * paso, x1)
                p.addLine(to: CGPoint(x: x, y: abajo + amplitud * sin(CGFloat(k) / 4 * 2 * .pi)))
            }
            ctx.stroke(p, with: .color(c), lineWidth: 1.6)
        case "subrayar":
            letra(&ctx)
            raya(&ctx, CGPoint(x: x0, y: abajo), CGPoint(x: x1, y: abajo), 1.8)
        case "tachar":
            letra(&ctx)
            raya(&ctx, CGPoint(x: x0, y: cy + 1), CGPoint(x: x1, y: cy + 1), 2)
        case "tapar":
            letra(&ctx)
            ctx.fill(Path(roundedRect: CGRect(x: x0, y: cy, width: x1 - x0, height: 9), cornerRadius: 2), with: .color(c))
        default:
            // Quitar la marca: un circulo tachado.
            let radio: CGFloat = 8
            ctx.fill(Path(ellipseIn: CGRect(x: cx - radio, y: cy - radio, width: 2 * radio, height: 2 * radio)),
                     with: .color(tinta.opacity(0.35)))
            let k = radio * 0.55
            var p = Path()
            p.move(to: CGPoint(x: cx - k, y: cy + k))
            p.addLine(to: CGPoint(x: cx + k, y: cy - k))
            ctx.stroke(p, with: .color(tinta), lineWidth: 1.8)
        }
    }
}

/// El anfitrion de la barrita: se lleva los clics aunque la ventana no sea
/// la principal, y nada mas (no se queda con el teclado).
final class AnfitrionBarritaNS: NSHostingView<BarritaMarcarVista> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    static func nuevo(_ modelo: ModeloMarcar) -> AnfitrionBarritaNS {
        let h = AnfitrionBarritaNS(rootView: BarritaMarcarVista(modelo: modelo))
        h.translatesAutoresizingMaskIntoConstraints = true
        // El tamano lo pone `ModeloMarcar.poner` (el de la barrita).
        h.sizingOptions = []
        h.safeAreaRegions = []
        h.isHidden = true
        return h
    }
}
