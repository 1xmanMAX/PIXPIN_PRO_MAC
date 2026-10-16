// **La barra de arriba comun** de Galeria, Tareas, Lecciones y Timeline,
// como `cabecera.rs` de Windows (el usuario alli: «en estos 4 apartados
// quiero que uniformices la UI de forma que todos en la parte superior se
// mantenga la barra de busqueda y las funciones unicas de cada parte»).
//
// Las medidas son las de Windows: 64 de alto en #1C1C1E con una linea
// blanca al 7 % debajo; el titulo (17, negrita) y su subtitulo (12, gris) en
// una columna fija de 200 a la izquierda, para que el buscador no salte; el
// buscador justo despues (hasta 520); los botones propios de cada ventana a
// la derecha (40 de alto, radio 10, #2C2C2E) y la ✕ del todo. Una sola vista
// para las cuatro: si una cambia, cambian todas.
//
// La barra hace de titulo: se lleva la ventana desde sus huecos y el doble
// clic la agranda, como la del sistema. La ventana va lisa y entera
// (`ventanaConCabecera()`), sin la franja de AppKit encima.

import AppKit
import SwiftUI

/// El buscador de la barra: el texto lo lleva cada ventana.
public struct BuscadorCabecera {
    let texto: Binding<String>
    let pista: String
    /// Con el foco nada mas abrir la ventana («Buscar en PixPin»: se abre
    /// para escribir).
    let enfocar: Bool

    public init(_ texto: Binding<String>, pista: String, enfocar: Bool = false) {
        self.texto = texto
        self.pista = pista
        self.enfocar = enfocar
    }
}

public struct Cabecera<Botones: View>: View {
    public static var alto: CGFloat { 64 }
    /// La columna del titulo, fija (`ANCHO_TITULO`).
    static var anchoTitulo: CGFloat { 200 }

    let titulo: String
    let subtitulo: String
    let buscador: BuscadorCabecera?
    let botones: Botones
    @Environment(\.ventanaDeLaVista) private var ventana

    public init(_ titulo: String, subtitulo: String = "", buscador: BuscadorCabecera? = nil,
                @ViewBuilder botones: () -> Botones) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.buscador = buscador
        self.botones = botones()
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Paleta.v2.texto)
                if !subtitulo.isEmpty {
                    Text(subtitulo)
                        .font(.system(size: 12))
                        .foregroundStyle(Paleta.v2.gris)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.anchoTitulo, alignment: .leading)
            .padding(.leading, 20)
            if let buscador {
                CajaBuscador(buscador: buscador)
                    .frame(minWidth: 120, maxWidth: 520)
                    .padding(.leading, 24)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                botones
                BotonCabecera(icono: "xmark", ayuda: "Cerrar (⌘W)", tenue: true) {
                    VentanaLisa.cerrar(ventana?.ventana)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: Self.alto)
        .frame(maxWidth: .infinity)
        .background {
            // Los huecos llevan la ventana y el doble clic la agranda.
            Paleta.v2.fondo
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { ventana?.ventana?.zoom(nil) })
        }
        .overlay(alignment: .bottom) {
            Paleta.v2.linea.frame(height: 1)
        }
        .environment(\.colorScheme, .dark)
    }
}

public extension Cabecera where Botones == EmptyView {
    init(_ titulo: String, subtitulo: String = "", buscador: BuscadorCabecera? = nil) {
        self.init(titulo, subtitulo: subtitulo, buscador: buscador) { EmptyView() }
    }
}

/// La caja de buscar: lupa, el texto o su pista y, con algo escrito, la ✕
/// de vaciarlo. ⌘F le da el foco (el «Ctrl F» de Windows).
struct CajaBuscador: View {
    let buscador: BuscadorCabecera
    @FocusState private var foco: Bool
    @State private var encima = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(foco ? Paleta.v2.acento : Paleta.v2.gris)
            TextField("", text: buscador.texto,
                      prompt: Text(buscador.pista).foregroundStyle(Paleta.v2.gris))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Paleta.v2.texto)
                .focused($foco)
            if buscador.texto.wrappedValue.isEmpty {
                Chapa(texto: "⌘F")
            } else {
                Button { buscador.texto.wrappedValue = "" } label: {
                    Label("Vaciar", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.v2.gris)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Vaciar")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 40)
        .background(Color(hex: 0x2A2A2D), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(foco ? Paleta.v2.acento : Color.white.opacity(encima ? 0.2 : 0.1), lineWidth: 1)
        }
        .onHover { encima = $0 }
        .onAppear { if buscador.enfocar { foco = true } }
        .background {
            // ⌘F: al buscador, como el Ctrl F de la barra de Windows.
            Button("") { foco = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }
}

/// La chapita de un atajo («⌘F»), como `ui::chapa` de Windows.
struct Chapa: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Paleta.v2.cuerpo)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(Color(hex: 0x2E2E31), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Un boton propio de la ventana en la barra: icono y rotulo (o solo
/// icono, cuadrado), 40 de alto, #2C2C2E; encendido, azul lleno. `tenue`:
/// sin fondo hasta pasar el raton, como la ✕.
public struct BotonCabecera: View {
    let icono: String?
    let rotulo: String
    let ayuda: String
    var activo = false
    var tenue = false
    let accion: () -> Void
    @Environment(\.isEnabled) private var habilitado
    @State private var encima = false

    public init(icono: String? = nil, rotulo: String = "", ayuda: String = "", activo: Bool = false,
                tenue: Bool = false, accion: @escaping () -> Void) {
        self.icono = icono
        self.rotulo = rotulo
        self.ayuda = ayuda.isEmpty ? rotulo : ayuda
        self.activo = activo
        self.tenue = tenue
        self.accion = accion
    }

    private var fondo: Color {
        if activo { return encima ? Paleta.v2.acento : Paleta.v2.azulLleno }
        if tenue { return encima ? Paleta.v2.caja : .clear }
        return encima && habilitado ? Color(hex: 0x38383B) : Paleta.v2.caja
    }

    public var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                if let icono {
                    Image(systemName: icono)
                        .font(.system(size: tenue ? 14 : 15, weight: .regular))
                        .frame(width: 20)
                }
                if !rotulo.isEmpty {
                    Text(rotulo).font(.system(size: 13.5, weight: .medium))
                }
            }
            .foregroundStyle(activo ? Color.white : tenue ? Paleta.v2.gris : Paleta.v2.texto)
            .padding(.horizontal, rotulo.isEmpty ? 0 : 14)
            .frame(minWidth: 40, minHeight: 40)
            .background(fondo, in: RoundedRectangle(cornerRadius: 10))
            .opacity(habilitado ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

/// El **control segmentado** de la barra (las pestanas del timeline): un
/// contenedor #2C2C2E con radio 12 y el elegido en una pildora azul.
public struct SegmentosCabecera<Valor: Hashable>: View {
    let opciones: [(Valor, String)]
    @Binding var eleccion: Valor

    public init(_ opciones: [(Valor, String)], eleccion: Binding<Valor>) {
        self.opciones = opciones
        _eleccion = eleccion
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(opciones.indices, id: \.self) { i in
                let (valor, rotulo) = opciones[i]
                SegmentoCabecera(rotulo: rotulo, activo: valor == eleccion) { eleccion = valor }
            }
        }
        .padding(3)
        .frame(height: 40)
        .background(Paleta.v2.caja, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SegmentoCabecera: View {
    let rotulo: String
    let activo: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Text(rotulo)
                .font(.system(size: 13.5))
                .foregroundStyle(activo ? Color.white : Paleta.v2.texto)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background {
                    Capsule().fill(activo ? Paleta.v2.acento : encima ? Color.white.opacity(0.08) : .clear)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}

// MARK: - La ventana con cabecera

public extension View {
    /// **Una ventana de la barra comun**, como en Windows: lisa y entera
    /// (sin la franja de AppKit; la `Cabecera` hace de titulo), sin la
    /// barra de herramientas del sistema y en oscuro, con el fondo #1C1C1E.
    func ventanaConCabecera() -> some View {
        modifier(ModificadorVentanaConCabecera())
    }
}

struct ModificadorVentanaConCabecera: ViewModifier {
    @State private var ref = RefVentana()

    func body(content: Content) -> some View {
        content
            .environment(\.ventanaDeLaVista, ref)
            .background(Paleta.v2.fondo)
            .ignoresSafeArea(.container, edges: .top)
            .toolbar(removing: .title)
            .toolbar(removing: .sidebarToggle)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(.hidden, for: .windowToolbar)
            .background(AccesoVentana { v in
                ref.ventana = v
                VentanaLisa.vestirEntera(v)
                // Sin la barra de herramientas del sistema: la de una vista
                // dividida trae su boton de plegar, que asomaria por detras
                // del titulo.
                v.toolbar = nil
                // Las ventanas de Windows son oscuras siempre, aunque la app
                // vaya en claro.
                v.appearance = NSAppearance(named: .darkAqua)
                v.backgroundColor = NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            })
    }
}

private struct ClaveVentanaDeLaVista: EnvironmentKey {
    static let defaultValue: RefVentana? = nil
}

extension EnvironmentValues {
    /// La ventana en la que esta la vista (para la ✕ de la `Cabecera`).
    var ventanaDeLaVista: RefVentana? {
        get { self[ClaveVentanaDeLaVista.self] }
        set { self[ClaveVentanaDeLaVista.self] = newValue }
    }
}
