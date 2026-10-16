// Las barras de la zona elegida (la maqueta `Captura2-despues` de
// Windows): ENCIMA de la zona la barra de herramientas del lienzo (la misma
// que en el lienzo, con su desplegable) y a su lado el panel de estilo;
// DEBAJO la de acciones: «Copiar» primero (Intro), Pinear, Al chat, Texto,
// Guardar y Descartar, cada una con su tecla en una pastilla.
//
// Todo va en una sola `NSHostingView` del tamano de la pantalla, encima de
// la captura, para que el desplegable de un grupo pueda salir por fuera de
// la barra. Solo se queda el raton donde hay algo (las islas que cada vista
// apunta en `ZonasDeBarrasCaptura`): el resto pasa a la captura de debajo.

import AppKit
import SwiftUI

/// Lo que ensenan las barras; lo cambia la vista de la captura.
@MainActor
final class EstadoBarrasCaptura: ObservableObject {
    /// El lienzo de la zona (`nil` mientras no hay zona).
    @Published var modelo: ModeloEditorLienzo?
    @Published var visibles = false
    /// Donde va cada cosa, en puntos de la vista con el origen ARRIBA (el
    /// de SwiftUI).
    @Published var acciones: CGRect = .zero
    @Published var herramientas: CGRect = .zero
    @Published var panel: CGPoint = .zero
    /// La accion de Intro (copiar, o grabar si se abrio para grabar).
    @Published var intro: AccionCaptura = .copiar
    /// Las que tienen a alguien detras.
    @Published var disponibles: Set<AccionCaptura> = Set(AccionCaptura.allCases)
    /// Lo que hace un boton de accion.
    var alPulsar: (AccionCaptura) -> Void = { _ in }
    /// Las islas que se ven ahora (donde se queda el raton).
    var zonas: [CGRect] = []
}

/// Donde caen las islas, para saber donde se queda el raton.
struct ZonasDeBarrasCaptura: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Apunta el marco de esta vista en las zonas que se quedan el raton.
    fileprivate func zonaDeRaton() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: ZonasDeBarrasCaptura.self, value: [g.frame(in: .named("barras"))])
        })
    }
}

/// Las tres islas sobre la pantalla entera.
struct BarrasCapturaVista: View {
    @ObservedObject var estado: EstadoBarrasCaptura

    var body: some View {
        ZStack(alignment: .topLeading) {
            if estado.visibles {
                BarraAccionesCaptura(estado: estado)
                    .zonaDeRaton()
                    .offset(x: estado.acciones.minX, y: estado.acciones.minY)
                if let modelo = estado.modelo {
                    HerramientasDeCaptura(modelo: modelo, estado: estado)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "barras")
        .onPreferenceChange(ZonasDeBarrasCaptura.self) { zonas in
            MainActor.assumeIsolated { estado.zonas = zonas }
        }
    }
}

/// La barra del lienzo, su desplegable y el panel de estilo.
private struct HerramientasDeCaptura: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    @ObservedObject var estado: EstadoBarrasCaptura

    var body: some View {
        let botones = BotonBarraLienzo.barraDeCaptura
        ZStack(alignment: .topLeading) {
            if modelo.desplegado != nil {
                // Un clic fuera del desplegable lo cierra.
                Color.black.opacity(0.001)
                    .onTapGesture { modelo.desplegado = nil }
            }
            BarraHerramientasLienzo(modelo: modelo, botones: botones, corte: botones.count)
                .zonaDeRaton()
                .offset(x: estado.herramientas.minX, y: estado.herramientas.minY)
            if modelo.hayElegidos || !HerramientaLienzo.sinEstilo.contains(modelo.herramienta) {
                PanelEstiloLienzo(modelo: modelo)
                    .zonaDeRaton()
                    .offset(x: estado.panel.x, y: estado.panel.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlayPreferenceValue(AnclasGruposLienzo.self) { anclas in
            MenuGrupoLienzo(modelo: modelo, anclas: anclas)
        }
    }
}

/// **La barra de acciones** (la de Windows): un boton por accion con su
/// icono, su nombre y su tecla; la de Intro, en azul.
struct BarraAccionesCaptura: View {
    @ObservedObject var estado: EstadoBarrasCaptura

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AccionCaptura.enBarra.filter { $0 != .cerrar }, id: \.self) { a in
                BotonAccionCaptura(accion: a, principal: a == estado.intro,
                                   disponible: estado.disponibles.contains(a)) { estado.alPulsar(a) }
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 24)
            BotonAccionCaptura(accion: .cerrar, principal: false, disponible: true, plano: true) {
                estado.alPulsar(.cerrar)
            }
        }
        .padding(6)
        .background(Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15, opacity: 0.97),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    /// Lo que mide (para colocarla antes de ensenarla).
    static func tamano() -> CGSize {
        let estado = EstadoBarrasCaptura()
        return NSHostingView(rootView: BarraAccionesCaptura(estado: estado)).fittingSize
    }
}

/// Un boton de la barra de acciones.
private struct BotonAccionCaptura: View {
    let accion: AccionCaptura
    let principal: Bool
    let disponible: Bool
    var plano = false
    let hacer: () -> Void

    @State private var encima = false

    var body: some View {
        Button(action: hacer) {
            HStack(spacing: 7) {
                if !plano { Image(systemName: accion.simbolo).font(.system(size: 13, weight: .medium)) }
                Text(accion.titulo).font(.system(size: 13, weight: .medium))
                Text(accion.tecla)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(principal ? 0.22 : 0.10), in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.18)))
            }
            .foregroundStyle(plano ? Color.white.opacity(0.65) : Color.white)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(fondo, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!disponible)
        .opacity(disponible ? 1 : 0.4)
        .onHover { encima = $0 }
        .help("\(accion.titulo) (\(accion.atajo))")
        .accessibilityLabel(accion.titulo)
    }

    private var fondo: Color {
        if principal { return Color(.sRGB, red: 0.0, green: 0.40, blue: 0.85, opacity: encima ? 1 : 0.92) }
        if plano { return encima ? Color.white.opacity(0.08) : .clear }
        return Color.white.opacity(encima ? 0.16 : 0.08)
    }
}

/// La vista que hospeda las barras: solo se queda el raton dentro de las
/// islas; fuera, la captura de debajo.
final class HospedajeBarrasCaptura: NSHostingView<BarrasCapturaVista> {
    let estado: EstadoBarrasCaptura

    init(estado: EstadoBarrasCaptura) {
        self.estado = estado
        super.init(rootView: BarrasCapturaVista(estado: estado))
    }

    @available(*, unavailable)
    required init(rootView: BarrasCapturaVista) { fatalError("se crea con init(estado:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("no se crea desde un nib") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard estado.visibles else { return nil }
        // `point` viene en las coordenadas de la vista de arriba.
        let local = convert(point, from: superview)
        let p = isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
        let dentro = estado.zonas.contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
            || (estado.modelo?.desplegado != nil)
        return dentro ? super.hitTest(point) : nil
    }
}
