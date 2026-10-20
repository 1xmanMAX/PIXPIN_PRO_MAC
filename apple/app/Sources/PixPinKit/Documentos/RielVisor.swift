import AppKit
import PixPinCore
import SwiftUI

/// **El riel de los visores** (Windows, 19-oct, `riel_marcas.rs`): una isla
/// arriba a la derecha con el lapiz, poner un marcador (pulsado = azul,
/// anotando) y el marco para imprimir. Debajo van los puntos de los
/// marcadores (`RielMarcasNS`). Igual en todos los visores.
struct IslaRiel: View {
    @ObservedObject var modelo: ModeloLector
    let marcar: () -> Void
    /// Sin el (un visor sin tinta todavia), no sale el lapiz.
    var lapiz: (() -> Void)?
    let imprimir: () -> Void

    /// Lo que ocupa a lo alto (para poner los puntos debajo).
    static let alto: CGFloat = 3 * 28 + 2 * 2 + 2 * 3

    var body: some View {
        VStack(spacing: 2) {
            if let lapiz {
                BotonRiel(simbolo: "pencil", ayuda: modelo.anotando ? "Dejar de anotar" : "Anotar (A)",
                          encendido: modelo.anotando, accion: lapiz)
            }
            BotonRiel(simbolo: "bookmark", ayuda: "Poner un marcador (⌘M)", encendido: modelo.poniendoMarca, accion: marcar)
            BotonRiel(simbolo: "printer", ayuda: "Marcos para imprimir (I) · ⌘P los imprime", encendido: modelo.enmarcando, accion: imprimir)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        .fixedSize()
    }
}

/// Un boton de la isla: 28 x 28 (como los de la barra), pulsado en azul como en Windows.
struct BotonRiel: View {
    let simbolo: String
    let ayuda: String
    var encendido = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Simbolo(nombre: simbolo, lado: 15)
                .foregroundStyle(encendido ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(encendido ? Color(red: 0, green: 0.376, blue: 0.875)
                          : encima ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
        .onHover { encima = $0 }
    }
}

/// **El riel montado sobre una vista** (los visores web): la isla, los
/// puntos de los marcadores y la tira de emoticonos para poner uno.
@MainActor
final class RielSobreVista {
    let modelo = ModeloLector()
    let puntos = RielMarcasNS()
    var irA: ((Float) -> Void)?
    var fraccion: ((@escaping (Float) -> Void) -> Void)?
    var alCambiar: (([MarcaDocumento]) -> Void)?
    private var suscripcion: Any?

    func montar(en contenedor: NSView, lapiz: (() -> Void)? = nil, imprimir: @escaping () -> Void) {
        let isla = NSHostingView(rootView: IslaRiel(modelo: modelo,
            marcar: { [weak self] in self?.modelo.poniendoMarca.toggle() },
            lapiz: lapiz, imprimir: imprimir))
        let tira = NSHostingView(rootView: TiraMarcas(modelo: modelo) { [weak self] e in self?.poner(e) }.fixedSize())
        puntos.paginas = 1
        puntos.rotulo = { m in "\(m.emoji)  \(Int((m.y * 100).rounded())) %" }
        puntos.ir = { [weak self] m in self?.irA?(Float(m.y)) }
        let arriba = BarraFlotante.alto + 2 * BarraFlotante.separacion + 8
        for v in [puntos, isla, tira] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contenedor.addSubview(v)
        }
        NSLayoutConstraint.activate([
            isla.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor, constant: -16),
            isla.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: arriba),
            puntos.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor, constant: -18),
            puntos.widthAnchor.constraint(equalToConstant: RielMarcasNS.ancho),
            puntos.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: arriba + IslaRiel.alto + 10),
            puntos.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -40),
            tira.centerXAnchor.constraint(equalTo: contenedor.centerXAnchor),
            tira.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -22),
        ])
        suscripcion = modelo.$marcas.sink { [weak self] m in self?.puntos.marcas = m }
    }

    private func poner(_ emoji: String) {
        modelo.poniendoMarca = false
        fraccion? { [weak self] f in
            guard let self else { return }
            let id = Int64(Date().timeIntervalSince1970 * 1000)
            var v = self.modelo.marcas
            v.append(MarcaDocumento(id: id, x: 0.5, y: Double(f), emoji: emoji))
            v.sort { $0.y < $1.y }
            self.modelo.marcas = v
            self.alCambiar?(v)
        }
    }
}

/// **Un marcador con su vista** (planos y modelos, Windows 19-oct): el
/// emoticono y lo que hace falta para volver justo ahi.
struct MarcadorDeVista: Codable, Equatable, Identifiable {
    var id: Int64
    var emoji: String
    var vista: [Double]
}

/// Los marcadores de vista de un fichero, junto a el (`.pixpin-vistas-mac`).
@MainActor
final class MarcadoresDeVista: ObservableObject {
    @Published private(set) var lista: [MarcadorDeVista] = []
    private let fichero: URL

    init(documento: URL) {
        fichero = documento.appendingPathExtension("pixpin-vistas-mac")
        if let d = try? Data(contentsOf: fichero), let l = try? JSONDecoder().decode([MarcadorDeVista].self, from: d) { lista = l }
    }

    func poner(_ emoji: String, vista: [Double]) {
        lista.append(MarcadorDeVista(id: Int64(Date().timeIntervalSince1970 * 1000), emoji: emoji, vista: vista))
        guardar()
    }

    func quitar(_ m: MarcadorDeVista) { lista.removeAll { $0.id == m.id }; guardar() }

    private func guardar() {
        if lista.isEmpty { try? FileManager.default.removeItem(at: fichero); return }
        try? JSONEncoder().encode(lista).write(to: fichero, options: .atomic)
    }
}

/// **El riel en SwiftUI** (planos y modelos): la isla de siempre y, debajo,
/// un punto por marcador que crece al pasar el raton y lleva a su vista.
struct RielDeVistas: View {
    @ObservedObject var modelo: ModeloLector
    @ObservedObject var marcadores: MarcadoresDeVista
    var lapiz: (() -> Void)?
    let marco: () -> Void
    let ir: (MarcadorDeVista) -> Void
    @State private var encima: Int64?

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            IslaRiel(modelo: modelo, marcar: { modelo.poniendoMarca.toggle() }, lapiz: lapiz, imprimir: marco)
            ForEach(Array(marcadores.lista.enumerated()), id: \.element.id) { i, m in
                Button { ir(m) } label: {
                    Text(m.emoji)
                        .font(.system(size: encima == m.id ? 20 : 13))
                        .frame(width: encima == m.id ? 36 : 22, height: encima == m.id ? 36 : 22)
                        .background(Circle().fill(Color(white: 0.12, opacity: encima == m.id ? 0.85 : 0.55)))
                        .offset(x: encima == m.id ? -8 : 0)
                }
                .buttonStyle(.plain)
                .help("\(m.emoji)\(i < 9 ? "  (⌘\(i + 1))" : "")")
                .onHover { encima = $0 ? m.id : (encima == m.id ? nil : encima) }
                .contextMenu { Button("Quitar", role: .destructive) { marcadores.quitar(m) } }
                .animation(.easeOut(duration: 0.12), value: encima)
            }
        }
        .padding(.top, BarraFlotante.alto + 2 * BarraFlotante.separacion + 8)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
