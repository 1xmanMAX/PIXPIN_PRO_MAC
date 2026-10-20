import AppKit
import SwiftUI

/// **El riel de los visores** (Windows, 19-oct, `riel_marcas.rs`): una isla
/// arriba a la derecha con poner un marcador, el lapiz (pulsado = azul,
/// anotando) y el marco para imprimir. Debajo van los puntos de los
/// marcadores (`RielMarcasNS`). Igual en todos los visores.
struct IslaRiel: View {
    @ObservedObject var modelo: ModeloLector
    let marcar: () -> Void
    let lapiz: () -> Void
    let imprimir: () -> Void

    /// Lo que ocupa a lo alto (para poner los puntos debajo).
    static let alto: CGFloat = 3 * 34 + 2 * 2 + 2 * 4

    var body: some View {
        VStack(spacing: 2) {
            BotonRiel(simbolo: "bookmark", ayuda: "Poner un marcador (M)", encendido: modelo.poniendoMarca, accion: marcar)
            BotonRiel(simbolo: "pencil", ayuda: modelo.anotando ? "Dejar de anotar" : "Anotar (lápiz)",
                      encendido: modelo.anotando, accion: lapiz)
            BotonRiel(simbolo: "printer", ayuda: "Marco para imprimir (⌘P)", accion: imprimir)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        .fixedSize()
    }
}

/// Un boton de la isla: 34 x 34, pulsado en azul como en Windows.
struct BotonRiel: View {
    let simbolo: String
    let ayuda: String
    var encendido = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 14))
                .foregroundStyle(encendido ? Color.white : Color.primary)
                .frame(width: 34, height: 34)
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
