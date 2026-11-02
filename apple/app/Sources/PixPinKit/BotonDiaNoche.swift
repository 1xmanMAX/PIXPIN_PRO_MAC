// **El boton ☀/☾ redondo** (Windows bbc1a9bd, `boton_dia_noche.rs`): un
// circulo con filete que dice el modo PUESTO (el sol de dia, la luna de
// noche, como el del movil). Al cambiar, el icono viejo gira y se apaga
// mientras el nuevo entra girando. Las cuentas (lado, duracion, giro, alfa y
// tamano de cada icono) son las del nucleo (`dia_noche.rs`); aqui solo se
// mide el tiempo y se pinta. Lo usan la cabecera de las figuras y la barra
// de los visores.

import PixPinCore
import SwiftUI

struct BotonDiaNoche: View {
    /// El modo puesto.
    let noche: Bool
    /// Sobre un fondo claro (el icono y el filete, oscuros).
    var claro = false
    var ayuda = ""
    let accion: () -> Void

    @State private var desde = Date.distantPast
    @State private var animando = false
    @State private var encima = false

    private static let medidas = medidasDiaNoche()

    private var tinta: Color {
        claro ? Color(red: 0.12, green: 0.14, blue: 0.17) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    var body: some View {
        let m = Self.medidas
        let dura = max(Double(m.duraMs) / 1000, 0.001)
        Button(action: accion) {
            TimelineView(.animation(minimumInterval: nil, paused: !animando)) { t in
                let progreso = Float(min(1, max(0, t.date.timeIntervalSince(desde) / dura)))
                let paso = pasoDiaNoche(noche: noche, progreso: progreso)
                ZStack {
                    Circle().fill(encima ? tinta.opacity(0.12) : Color.clear)
                    Circle().strokeBorder(tinta.opacity(0.35), lineWidth: 1)
                    if let sale = paso.sale { icono(sale, lado: CGFloat(m.icono)) }
                    icono(paso.entra, lado: CGFloat(m.icono))
                }
                .frame(width: CGFloat(m.lado), height: CGFloat(m.lado))
                .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
        .onChange(of: noche) {
            desde = Date()
            animando = true
            DispatchQueue.main.asyncAfter(deadline: .now() + dura + 0.05) { animando = false }
        }
    }

    private func icono(_ i: IconoDiaNoche, lado: CGFloat) -> some View {
        Simbolo(nombre: i.luna ? "moon" : "sun.max", lado: lado)
            .foregroundStyle(tinta)
            .scaleEffect(CGFloat(i.tam))
            .rotationEffect(.radians(Double(i.giro)))
            .opacity(Double(i.alfa))
    }
}
