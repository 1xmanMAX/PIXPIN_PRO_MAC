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
