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

/// **Un marcador de un plano con su vista** (Windows, `Marcador2d` de
/// `pixpin-cad/marcadores.rs`): el centro y lo que se ve, en coordenadas
/// del dibujo (Y arriba). Van numerados (1, 2, 3…), sin emoticono.
struct MarcadorDeVista: Equatable, Identifiable {
    var id: String
    var nombre: String
    var x: Double, y: Double, ancho: Double, alto: Double
}

/// Los marcadores de un plano en el `.vistas.json` de Windows
/// (`{"version":1,"plano":[…],"modelo":[…]}`): en `anot-<uid>.vistas.json`
/// si el plano es un adjunto (viaja), si no junto a el. Lo de `modelo` (3D)
/// se conserva tal cual.
@MainActor
final class MarcadoresDeVista: ObservableObject {
    @Published private(set) var lista: [MarcadorDeVista] = []
    private let fichero: URL
    private var resto: [String: Any] = ["version": 1]

    init(documento: URL, nucleo: Nucleo?) {
        if let n = nucleo, let r = n.rutaAnotadaDelAdjunto(documento: documento.path, terminacion: ".vistas.json") {
            fichero = URL(fileURLWithPath: r)
        } else {
            fichero = documento.appendingPathExtension("pixpin-vistas")
        }
        guard let d = try? Data(contentsOf: fichero),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        resto = o
        lista = (o["plano"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            func n(_ k: String) -> Double { (m[k] as? NSNumber)?.doubleValue ?? 0 }
            return MarcadorDeVista(id: id, nombre: m["nombre"] as? String ?? "", x: n("x"), y: n("y"), ancho: n("ancho"), alto: n("alto"))
        }
    }

    func poner(x: Double, y: Double, ancho: Double, alto: Double) {
        let id = "m" + String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36)
        lista.append(MarcadorDeVista(id: id, nombre: "", x: x, y: y, ancho: ancho, alto: alto))
        guardar()
    }

    func quitar(_ m: MarcadorDeVista) { lista.removeAll { $0.id == m.id }; guardar() }

    // MARK: Modelos 3D (`Marcador3d` con su `Estado3d`)

    /// Los de un modelo: id y su `Estado3d` tal cual.
    var del3d: [(id: String, estado: [String: Any])] {
        (resto["modelo"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = m["id"] as? String, let e = m["estado"] as? [String: Any] else { return nil }
            return (id, e)
        }
    }

    func poner3d(estado: [String: Any]) {
        let id = "m" + String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36)
        var l = resto["modelo"] as? [[String: Any]] ?? []
        l.append(["id": id, "nombre": "", "estado": estado])
        resto["modelo"] = l
        objectWillChange.send()
        guardar()
    }

    func quitar3d(_ id: String) {
        resto["modelo"] = (resto["modelo"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != id }
        objectWillChange.send()
        guardar()
    }

    /// Vaciar escribe la lista vacia: un fichero borrado volveria al sincronizar.
    private func guardar() {
        var o = resto
        o["version"] = 1
        o["plano"] = lista.map { ["id": $0.id, "nombre": $0.nombre, "x": $0.x, "y": $0.y, "ancho": $0.ancho, "alto": $0.alto] }
        if o["modelo"] == nil { o["modelo"] = [Any]() }
        resto = o
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: fichero, options: .atomic)
        }
    }
}

/// **El riel en SwiftUI** (planos y modelos): la isla de siempre y, debajo,
/// un punto por marcador que crece al pasar el raton y lleva a su vista.
struct RielDeVistas: View {
    @ObservedObject var modelo: ModeloLector
    @ObservedObject var marcadores: MarcadoresDeVista
    var lapiz: (() -> Void)?
    let marcar: () -> Void
    let marco: () -> Void
    let ir: (MarcadorDeVista) -> Void
    @State private var encima: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            IslaRiel(modelo: modelo, marcar: marcar, lapiz: lapiz, imprimir: marco)
            ForEach(Array(marcadores.lista.enumerated()), id: \.element.id) { i, m in
                Button { ir(m) } label: {
                    Text("\(i + 1)")
                        .font(.system(size: encima == m.id ? 14 : 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: encima == m.id ? 36 : 22, height: encima == m.id ? 36 : 22)
                        .background(Circle().fill(Color(white: 0.12, opacity: encima == m.id ? 0.85 : 0.55)))
                        .offset(x: encima == m.id ? -8 : 0)
                }
                .buttonStyle(.plain)
                .help("Marcador \(i + 1)")
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
