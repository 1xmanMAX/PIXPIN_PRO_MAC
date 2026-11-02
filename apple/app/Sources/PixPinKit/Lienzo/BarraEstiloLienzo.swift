// **El panel de estilo del lienzo**: color del trazo, fondo, relleno,
// grosor, linea, trazo a mano y opacidad. Es el panel lateral de Windows
// (`pixpin-ui/src/panel_lateral.rs`, el de Excalidraw): una isla a la
// izquierda, bajo la barra, con sus secciones en el orden de Excalidraw.
// **Compacto** (Windows, 24-oct: «la barra de propiedades ocupa mucha de la
// visualizacion, redisenala y pon un boton para mostrarla y quitarla»): 168
// de ancho en vez de 200, menos relleno y aire, botones de 28, cuatro por
// fila; el boton de quitarlo va solo en el lienzo (`BotonPlegarPanel`). Lo
// que se elige queda para lo proximo que se dibuje y, si hay algo elegido,
// se le aplica en un paso de deshacer (`EditorLienzo.cambiarEstilo`, ver
// `pixpin-nucleo/src/editor_estilo.rs`). Lo que ensena es `EditorLienzo.estilo`:
// el de lo elegido o, sin nada, el «actual».

import AppKit
import PixPinCore
import SwiftUI

/// Una opcion de un mando: su nombre (que hace de id) y su valor.
public struct OpcionEstiloLienzo<Valor>: Identifiable {
    public let nombre: String
    public let valor: Valor
    public var id: String { nombre }

    init(_ nombre: String, _ valor: Valor) {
        self.nombre = nombre
        self.valor = valor
    }
}

/// Las opciones de cada mando. Aparte de la vista para probarlas sin
/// pantalla.
public enum OpcionesEstiloLienzo {
    /// Los colores de trazo de Excalidraw (`COLOR_PALETTE`, el tono de la barra).
    public static let trazos: [OpcionEstiloLienzo<ColorEstilo>] = [
        .init("Negro", hex(0x1e1e1e)), .init("Rojo", hex(0xe03131)), .init("Verde", hex(0x2f9e44)),
        .init("Azul", hex(0x1971c2)), .init("Naranja", hex(0xf08c00)),
    ]

    /// Los fondos de Excalidraw; `nil` es transparente.
    public static let fondos: [OpcionEstiloLienzo<ColorEstilo?>] = [
        .init("Transparente", nil), .init("Rosa", hex(0xffc9c9)), .init("Verde claro", hex(0xb2f2bb)),
        .init("Azul claro", hex(0xa5d8ff)), .init("Amarillo", hex(0xffec99)),
    ]

    public static let grosores: [OpcionEstiloLienzo<GrosorEstilo>] = [
        .init("Fino", .fino), .init("Medio", .medio), .init("Grueso", .grueso),
    ]

    /// 1, 2 y 3: los tres grosores, como las teclas de la pluma de Windows
    /// (`tecla_a_pluma`).
    public static func grosor(tecla: String) -> GrosorEstilo? {
        switch tecla {
        case "1": return .fino
        case "2": return .medio
        case "3": return .grueso
        default: return nil
        }
    }

    /// El trazo a mano de Excalidraw (`roughness`): 0 arquitecto, 1 artista
    /// y 2 caricaturista.
    public static let rugosidades: [OpcionEstiloLienzo<Float>] = [
        .init("Arquitecto", 0), .init("Artista", 1), .init("Caricaturista", 2),
    ]

    // Los iconos de cada opcion: los de Excalidraw, como el panel de Windows
    // (`panel_dibujo.rs`).
    static func icono(_ g: GrosorEstilo) -> IconoLienzo {
        switch g {
        case .fino: return .strokeWidthBase
        case .medio: return .strokeWidthBold
        case .grueso: return .strokeWidthExtraBold
        }
    }

    static func icono(_ l: LineaEstilo) -> IconoLienzo {
        switch l {
        case .continua: return .strokeStyleSolid
        case .discontinua: return .strokeStyleDashed
        case .punteada: return .strokeStyleDotted
        case .rayaPunto: return .strokeStyleDashed
        }
    }

    static func icono(_ r: RellenoEstilo) -> IconoLienzo {
        switch r {
        case .solido: return .fillSolid
        case .rayado: return .fillHachure
        case .cruzado: return .fillCrossHatch
        case .zigzag: return .fillZigZag
        case .lineas: return .fillLineas
        }
    }

    static func icono(rugosidad r: Float) -> IconoLienzo {
        r < 0.5 ? .sloppinessArchitect : (r < 1.5 ? .sloppinessArtist : .sloppinessCartoonist)
    }

    public static let lineas: [OpcionEstiloLienzo<LineaEstilo>] = [
        .init("Continua", .continua), .init("Discontinua", .discontinua), .init("Punteada", .punteada),
        .init("Raya y punto", .rayaPunto),
    ]

    /// En el orden de Excalidraw: rayado, cruzado y solido; y despues los
    /// dos que Excalidraw no tiene.
    public static let rellenos: [OpcionEstiloLienzo<RellenoEstilo>] = [
        .init("Rayado", .rayado), .init("Cruzado", .cruzado), .init("Sólido", .solido),
        .init("Zigzag", .zigzag), .init("Líneas", .lineas),
    ]

    public static func hex(_ v: UInt32) -> ColorEstilo {
        ColorEstilo(r: Float((v >> 16) & 0xff) / 255, g: Float((v >> 8) & 0xff) / 255,
                    b: Float(v & 0xff) / 255, a: 1)
    }

    public static func color(_ c: ColorEstilo) -> Color {
        Color(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
    }

    /// De un color del selector del sistema al del motor (sRGB).
    public static func estilo(de color: Color) -> ColorEstilo? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return ColorEstilo(r: Float(c.redComponent), g: Float(c.greenComponent),
                           b: Float(c.blueComponent), a: Float(c.alphaComponent))
    }

    /// Si dos colores son el mismo a la vista (un canal de 8 bits).
    public static func igual(_ a: ColorEstilo?, _ b: ColorEstilo?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?):
            return abs(x.r - y.r) < 0.004 && abs(x.g - y.g) < 0.004 && abs(x.b - y.b) < 0.004
                && abs(x.a - y.a) < 0.004
        default: return false
        }
    }

    static func nombre(_ g: GrosorEstilo) -> String {
        grosores.first { mismo($0.valor, g) }?.nombre ?? ""
    }

    static func nombre(_ l: LineaEstilo) -> String {
        lineas.first { mismo($0.valor, l) }?.nombre ?? ""
    }

    static func nombre(_ r: RellenoEstilo) -> String {
        rellenos.first { mismo($0.valor, r) }?.nombre ?? ""
    }

    // Comparar sin depender de que los enlaces generen `Equatable`.
    static func mismo(_ a: GrosorEstilo, _ b: GrosorEstilo) -> Bool { "\(a)" == "\(b)" }
    static func mismo(_ a: LineaEstilo, _ b: LineaEstilo) -> Bool { "\(a)" == "\(b)" }
    static func mismo(_ a: RellenoEstilo, _ b: RellenoEstilo) -> Bool { "\(a)" == "\(b)" }
}

extension IconoLienzo {
    /// El relleno de lineas, que Excalidraw no tiene: su cuadro con tres
    /// rayas tumbadas, del mismo trazo que los otros rellenos.
    static let fillLineas = IconoLienzo(vista: CGRect(x: 0, y: 0, width: 20, height: 20), trazos: [
        .init(d: "M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z",
              relleno: .nada, trazo: .actual, grosor: 1.25, redondo: true, opacidad: 1, parImpar: false,
              matriz: nil, mascara: nil),
        .init(d: "M2.6 7.2h14.8M2.6 10h14.8M2.6 12.8h14.8", relleno: .nada, trazo: .actual, grosor: 1.25,
              redondo: true, opacidad: 1, parImpar: false, matriz: nil,
              mascara: "M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z"),
    ])
}

/// Un cuadradito de color (o el damero de «transparente»), de 20 como el
/// panel compacto de Windows; el elegido lleva el anillo del color de la
/// barra.
private struct Muestra: View {
    let color: ColorEstilo?
    let elegida: Bool
    let tema: TemaBarraLienzo

    var body: some View {
        ZStack {
            if let color {
                RoundedRectangle(cornerRadius: 4).fill(OpcionesEstiloLienzo.color(color))
            } else {
                Damero().clipShape(RoundedRectangle(cornerRadius: 4))
            }
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
        }
        .frame(width: 18, height: 18)
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(elegida ? tema.menuIconoElegido : Color.clear, lineWidth: 1.5)
        )
    }
}

/// El damero de lo transparente.
private struct Damero: View {
    var body: some View {
        Canvas { ctx, tam in
            ctx.fill(Path(CGRect(origin: .zero, size: tam)), with: .color(.white))
            let lado: CGFloat = 5
            var y: CGFloat = 0, fila = 0
            while y < tam.height {
                var x: CGFloat = fila % 2 == 0 ? 0 : lado
                while x < tam.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: lado, height: lado)), with: .color(Color(white: 0.85)))
                    x += lado * 2
                }
                y += lado
                fila += 1
            }
        }
    }
}

/// Un boton de opcion de 28 (relleno, grosor, linea, trazo a mano).
private struct BotonOpcion: View {
    let icono: IconoLienzo
    let elegida: Bool
    let tema: TemaBarraLienzo
    let ayuda: String
    let accion: () -> Void

    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            IconoLienzoVista(icono: icono, lado: 15, color: elegida ? tema.activoIcono : tema.icono)
                .frame(width: 28, height: 28)
                .background(elegida ? tema.activoFondo : (encima ? tema.hover : tema.separador.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(elegida ? tema.menuIconoElegido : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

/// El selector de colores del sistema, para «otro color» del trazo o del
/// fondo: el panel avisa aqui y aqui se manda al modelo.
@MainActor
final class SelectorColorLienzo: NSObject {
    static let compartido = SelectorColorLienzo()
    private var alCambiar: ((ColorEstilo) -> Void)?

    func abrir(_ actual: ColorEstilo?, alCambiar: @escaping (ColorEstilo) -> Void) {
        self.alCambiar = nil
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if let actual {
            panel.color = NSColor(srgbRed: CGFloat(actual.r), green: CGFloat(actual.g),
                                  blue: CGFloat(actual.b), alpha: CGFloat(actual.a))
        }
        self.alCambiar = alCambiar
        panel.setTarget(self)
        panel.setAction(#selector(cambio(_:)))
        panel.orderFront(nil)
    }

    @objc private func cambio(_ panel: NSColorPanel) {
        guard let c = panel.color.usingColorSpace(.sRGB) else { return }
        alCambiar?(ColorEstilo(r: Float(c.redComponent), g: Float(c.greenComponent),
                               b: Float(c.blueComponent), a: 1))
    }
}

/// **El panel de estilo**, en su isla de 168 a la izquierda.
struct PanelEstiloLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo

    private var estilo: EstiloLienzo { modelo.estilo }

    var body: some View {
        let tema = TemaBarraLienzo.de(modelo)
        VStack(alignment: .leading, spacing: 8) {
            seccion("Trazo", tema) {
                HStack(spacing: 3) {
                    ForEach(OpcionesEstiloLienzo.trazos) { o in
                        Button { modelo.cambiarEstilo(.trazo(color: o.valor)) } label: {
                            Muestra(color: o.valor, elegida: OpcionesEstiloLienzo.igual(estilo.trazo, o.valor),
                                    tema: tema)
                        }
                        .buttonStyle(.plain)
                        .help("Trazo: \(o.nombre)")
                    }
                    otroColor(estilo.trazo, tema: tema, ayuda: Lengua.t("lienzo-panel-personalizado")) {
                        .trazo(color: $0)
                    }
                }
            }
            seccion("Fondo", tema) {
                HStack(spacing: 3) {
                    ForEach(OpcionesEstiloLienzo.fondos) { o in
                        Button { modelo.cambiarEstilo(.fondo(color: o.valor)) } label: {
                            Muestra(color: o.valor, elegida: OpcionesEstiloLienzo.igual(estilo.fondo, o.valor),
                                    tema: tema)
                        }
                        .buttonStyle(.plain)
                        .help("Fondo: \(o.nombre)")
                    }
                    otroColor(estilo.fondo, tema: tema, ayuda: Lengua.t("lienzo-panel-personalizado")) {
                        .fondo(color: $0)
                    }
                }
            }
            // Sin fondo no hay nada que rayar (`con_fondo` de Windows).
            if estilo.fondo != nil {
                seccion("Relleno", tema) {
                    opciones(OpcionesEstiloLienzo.rellenos, tema: tema,
                             elegida: { OpcionesEstiloLienzo.mismo(estilo.relleno, $0) },
                             icono: OpcionesEstiloLienzo.icono) { modelo.cambiarEstilo(.relleno(relleno: $0)) }
                }
            }
            seccion("Grosor del trazo", tema) {
                opciones(OpcionesEstiloLienzo.grosores, tema: tema,
                         elegida: { OpcionesEstiloLienzo.mismo(estilo.grosor, $0) },
                         icono: OpcionesEstiloLienzo.icono) { modelo.cambiarEstilo(.grosor(grosor: $0)) }
            }
            seccion("Estilo del trazo", tema) {
                opciones(OpcionesEstiloLienzo.lineas, tema: tema,
                         elegida: { OpcionesEstiloLienzo.mismo(estilo.linea, $0) },
                         icono: OpcionesEstiloLienzo.icono) { modelo.cambiarEstilo(.linea(linea: $0)) }
            }
            seccion("Trazo a mano", tema) {
                opciones(OpcionesEstiloLienzo.rugosidades, tema: tema,
                         elegida: { abs(estilo.rugosidad - $0) < 0.5 },
                         icono: { OpcionesEstiloLienzo.icono(rugosidad: $0) }) {
                    modelo.cambiarEstilo(.rugosidad(valor: $0))
                }
            }
            seccion("Opacidad", tema) {
                Slider(value: Binding(get: { Double(estilo.opacidad) * 100 },
                                      set: { modelo.cambiarEstilo(.opacidad(valor: Float($0 / 100))) }),
                       in: 0...100, step: 10)
                    .controlSize(.small)
                    .tint(tema.menuIconoElegido)
            }
            // Lo elegido, a la biblioteca de figuras (la fila «Acciones» del
            // panel de Windows: «Guardar en figuras»).
            if modelo.hayElegidos, modelo.nucleo != nil {
                seccion("Acciones", tema) {
                    Button { modelo.guardarComoFigura() } label: {
                        Label("Guardar en figuras", systemImage: "rectangle.stack.badge.plus")
                            .font(.system(size: 12))
                            .foregroundStyle(tema.icono)
                    }
                    .buttonStyle(.plain)
                    .help("Guardar lo elegido en tus figuras")
                }
            }
        }
        .padding(8)
        .frame(width: MedidasBarraLienzo.anchoPanel, alignment: .leading)
        .modifier(IslaLienzo(tema: tema))
    }

    private func seccion(_ titulo: String, _ tema: TemaBarraLienzo,
                         @ViewBuilder _ contenido: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.system(size: 11)).foregroundStyle(tema.icono.opacity(0.75))
            contenido()
        }
    }

    private func opciones<V>(_ lista: [OpcionEstiloLienzo<V>], tema: TemaBarraLienzo,
                             elegida: @escaping (V) -> Bool, icono: @escaping (V) -> IconoLienzo,
                             accion: @escaping (V) -> Void) -> some View {
        // Cuatro por fila (los rellenos son cinco: el quinto baja).
        let filas = stride(from: 0, to: lista.count, by: 4).map { Array(lista[$0..<min($0 + 4, lista.count)]) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(filas.indices, id: \.self) { f in
                HStack(spacing: 6) {
                    ForEach(filas[f]) { o in
                        BotonOpcion(icono: icono(o.valor), elegida: elegida(o.valor), tema: tema, ayuda: o.nombre) {
                            accion(o.valor)
                        }
                    }
                }
            }
        }
    }

    /// La muestra del color de ahora tras una raya: abre el color avanzado
    /// (Windows f7599df9) en su globo.
    private func otroColor(_ actual: ColorEstilo?, tema: TemaBarraLienzo, ayuda: String,
                           mando: @escaping (ColorEstilo) -> CambioDeEstilo) -> some View {
        OtroColorLienzo(modelo: modelo, actual: actual, tema: tema, ayuda: ayuda, mando: mando)
    }
}

/// **El color avanzado** del panel del lienzo (Windows 6fd2732a, f7599df9,
/// 19f0c8c9): el cuadro de saturacion y brillo, la tira de tonos, la
/// opacidad, el codigo (#RGB, #RRGGBB o #RRGGBBAA), el cuentagotas y los
/// colores recientes. Las cuentas son las del nucleo (`selector_color.rs`);
/// cada arrastre es un solo paso de deshacer
/// (`empezar/arrastrar/terminarArrastreDeEstilo`).
struct SelectorColorAvanzado: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    let actual: ColorEstilo?
    let tema: TemaBarraLienzo
    /// El mando que cambia: el trazo o el fondo.
    let mando: (ColorEstilo) -> CambioDeEstilo

    @State private var hsv = ColorHsv(h: 0, s: 0, v: 0)
    @State private var codigo = ""
    @State private var recientes: [ColorEstilo] = []
    @State private var arrastrando = false

    private let ancho: CGFloat = 188

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cuadro
            tira(alto: 12) {
                LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
                    Color(hue: $0, saturation: 1, brightness: 1)
                }, startPoint: .leading, endPoint: .trailing)
            } marca: { CGFloat(hsv.h) / 360 } mover: { x in
                hsv = ColorHsv(h: tonoDeLaTira(x: x), s: hsv.s, v: hsv.v)
                aplicar(colorDeHsv(valor: hsv))
            }
            tira(alto: 12) {
                ZStack {
                    DameroColor()
                    LinearGradient(colors: [OpcionesEstiloLienzo.color(colorDeHsv(valor: hsv)).opacity(0),
                                            OpcionesEstiloLienzo.color(colorDeHsv(valor: hsv))],
                                   startPoint: .leading, endPoint: .trailing)
                }
            } marca: { CGFloat(modelo.estilo.opacidad) } mover: { x in
                modelo.arrastrarEstilo(.opacidad(valor: opacidadEnPasos(x: x)))
            }
            HStack(spacing: 6) {
                TextField("#RRGGBB", text: $codigo)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 112)
                    .onSubmit(aplicarCodigo)
                Button(action: cuentagotas) {
                    Image(systemName: "eyedropper").foregroundStyle(tema.icono)
                }
                .buttonStyle(.plain)
                .help(Lengua.t("comando-cuentagotas"))
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpcionesEstiloLienzo.color(colorDeHsv(valor: hsv)))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.2)))
            }
            if !recientes.isEmpty {
                Text(Lengua.t("lienzo-panel-recientes"))
                    .font(.system(size: 11)).foregroundStyle(tema.icono.opacity(0.75))
                HStack(spacing: 3) {
                    ForEach(Array(recientes.enumerated()), id: \.offset) { _, c in
                        Button { elegir(c) } label: {
                            Muestra(color: c, elegida: OpcionesEstiloLienzo.igual(actual, c), tema: tema)
                        }
                        .buttonStyle(.plain)
                        .help(escribirCodigoDeColor(color: c, opacidad: 1))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: ancho + 20)
        .onAppear {
            hsv = hsvDeColor(color: actual, tonoRecordado: nil)
            codigo = actual.map { escribirCodigoDeColor(color: $0, opacidad: 1) } ?? ""
            recientes = modelo.nucleo?.lienzoColoresRecientes() ?? []
        }
    }

    /// El cuadro: de izquierda a derecha la saturacion, de arriba abajo el
    /// brillo, del tono de la tira.
    private var cuadro: some View {
        let alto = ancho * 0.66
        return ZStack {
            Color(hue: Double(hsv.h) / 360, saturation: 1, brightness: 1)
            LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            Circle()
                .strokeBorder(marcaClaraSobre(fondo: colorDeHsv(valor: hsv)) ? Color.white : Color.black,
                              lineWidth: 2)
                .frame(width: 12, height: 12)
                .position(x: CGFloat(hsv.s) * ancho, y: (1 - CGFloat(hsv.v)) * alto)
        }
        .frame(width: ancho, height: alto)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                empezar()
                let x = Float(min(max(g.location.x / ancho, 0), 1))
                let y = Float(min(max(g.location.y / alto, 0), 1))
                hsv = hsvDelCuadro(h: hsv.h, x: x, y: y)
                aplicar(colorDeHsv(valor: hsv))
            }
            .onEnded { _ in terminar() })
    }

    /// Una tira con su marca, que se arrastra.
    private func tira(alto: CGFloat, @ViewBuilder fondo: () -> some View,
                      marca: @escaping () -> CGFloat, mover: @escaping (Float) -> Void) -> some View {
        ZStack(alignment: .leading) {
            fondo()
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.white, lineWidth: 2)
                .shadow(radius: 1)
                .frame(width: 6, height: alto + 4)
                .offset(x: min(max(marca(), 0), 1) * (ancho - 6))
        }
        .frame(width: ancho, height: alto)
        .clipShape(RoundedRectangle(cornerRadius: alto / 2))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                empezar()
                mover(Float(min(max(g.location.x / ancho, 0), 1)))
            }
            .onEnded { _ in terminar() })
    }

    private func empezar() {
        guard !arrastrando else { return }
        arrastrando = true
        modelo.empezarArrastreDeEstilo()
    }

    private func terminar() {
        guard arrastrando else { return }
        arrastrando = false
        modelo.terminarArrastreDeEstilo()
        apuntar(colorDeHsv(valor: hsv))
    }

    private func aplicar(_ c: ColorEstilo) {
        codigo = escribirCodigoDeColor(color: c, opacidad: 1)
        modelo.arrastrarEstilo(mando(c))
    }

    /// Un color de una vez (un reciente, el codigo, el cuentagotas): su paso.
    private func elegir(_ c: ColorEstilo) {
        hsv = hsvDeColor(color: c, tonoRecordado: hsv.h)
        codigo = escribirCodigoDeColor(color: c, opacidad: 1)
        modelo.cambiarEstilo(mando(c))
        apuntar(c)
    }

    private func apuntar(_ c: ColorEstilo) {
        if let r = modelo.nucleo?.apuntarColorReciente(color: c) { recientes = r }
    }

    private func aplicarCodigo() {
        guard let leido = leerCodigoDeColor(escrito: codigo) else {
            codigo = limpiarCodigoDeColor(escrito: codigo)
            return
        }
        elegir(leido.color)
        if let o = leido.opacidad { modelo.cambiarEstilo(.opacidad(valor: o)) }
    }

    private func cuentagotas() {
        NSColorSampler().show { elegido in
            guard let c = elegido?.usingColorSpace(.sRGB) else { return }
            let color = ColorEstilo(r: Float(c.redComponent), g: Float(c.greenComponent),
                                    b: Float(c.blueComponent), a: 1)
            MainActor.assumeIsolated { elegir(color) }
        }
    }
}

/// El damero de lo transparente bajo la tira de la opacidad.
private struct DameroColor: View {
    var body: some View { Damero() }
}

/// La muestra del color de ahora que abre el color avanzado.
private struct OtroColorLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    let actual: ColorEstilo?
    let tema: TemaBarraLienzo
    let ayuda: String
    let mando: (ColorEstilo) -> CambioDeEstilo
    @State private var abierto = false

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(tema.separador).frame(width: 1, height: 20)
            Button { abierto.toggle() } label: {
                Muestra(color: actual, elegida: abierto, tema: tema)
            }
            .buttonStyle(.plain)
            .help(ayuda)
            .popover(isPresented: $abierto, arrowEdge: .trailing) {
                SelectorColorAvanzado(modelo: modelo, actual: actual, tema: tema, mando: mando)
            }
        }
    }
}
