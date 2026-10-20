import AppKit
import PDFKit
import PixPinCore
import SwiftUI

/// **Los marcos numerados de un modelo 3D** (Windows, `Marco3d` de
/// `pixpin-cad/marcadores.rs`): cada uno, su recuadro en la pantalla
/// (desde el centro de la ventana, en unidades de su alto, Y hacia abajo)
/// y la camara con que se puso. Solo se ve con su vista. En el
/// `anot-<uid>.marcos.json` del adjunto (`{"version":1,"marcos":[…]}`).
@MainActor
final class Marcos3D: ObservableObject {
    struct Marco: Identifiable {
        var id: String
        var caja: [Double]
        var camara: Camara3d
        /// El `Estado3d` entero (corte, ocultos…), tal cual.
        var estado: [String: Any]
    }

    @Published private(set) var lista: [Marco] = []
    @Published var activo = false
    private let fichero: URL
    private var resto: [String: Any] = ["version": 1]

    init(documento: URL, nucleo: Nucleo?) {
        if let n = nucleo, let r = n.rutaAnotadaDelAdjunto(documento: documento.path, terminacion: ".marcos.json") {
            fichero = URL(fileURLWithPath: r)
        } else {
            fichero = documento.appendingPathExtension("pixpin-marcos")
        }
        guard let d = try? Data(contentsOf: fichero), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        resto = o
        lista = (o["marcos"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = m["id"] as? String, let c = (m["caja"] as? [NSNumber])?.map(\.doubleValue), c.count == 4,
                  let e = m["estado"] as? [String: Any], let o = (e["objetivo"] as? [NSNumber])?.map(\.doubleValue), o.count == 3
            else { return nil }
            func n(_ k: String) -> Double { (e[k] as? NSNumber)?.doubleValue ?? 0 }
            return Marco(id: id, caja: c, camara: Camara3d(objetivo: Punto3d(x: o[0], y: o[1], z: o[2]),
                                                          rumbo: n("rumbo"), altura: n("altura"), dist: n("dist")), estado: e)
        }
    }

    func poner(caja: [Double], camara: Camara3d, estado: [String: Any]) {
        lista.append(Marco(id: "m" + String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36), caja: caja, camara: camara, estado: estado))
        guardar()
    }

    @discardableResult
    func quitarUltimo() -> Bool {
        guard lista.popLast() != nil else { return false }
        guardar()
        return true
    }

    func borrar() { lista = []; guardar() }

    /// Si la camara `c` es la del marco (Windows: ~2e-3 relativo).
    static func coincide(_ a: Camara3d, _ b: Camara3d) -> Bool {
        let d = max(abs(a.dist), 1e-9)
        let o = hypot(hypot(a.objetivo.x - b.objetivo.x, a.objetivo.y - b.objetivo.y), a.objetivo.z - b.objetivo.z)
        return o / d < 2e-3 && abs(a.dist - b.dist) / d < 2e-3 && abs(a.rumbo - b.rumbo) < 2e-3 && abs(a.altura - b.altura) < 2e-3
    }

    private func guardar() {
        var o = resto
        o["version"] = 1
        o["marcos"] = lista.map { m -> [String: Any] in
            ["id": m.id, "caja": m.caja, "estado": m.estado]
        }
        resto = o
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: fichero, options: .atomic)
        }
    }
}

/// La capa de los marcos sobre el modelo: arrastrar pone uno (en modo), se
/// ven los de la vista de ahora, y abajo a la izquierda sus fichas.
struct CapaMarcos3D: View {
    @ObservedObject var visor: VisorModelo3D
    @ObservedObject var marcos: Marcos3D
    @State private var arrastre: (CGPoint, CGPoint)?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = max(g.size.height, 1)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let camara = visor.vista?.camara
                ZStack(alignment: .topLeading) {
                    if marcos.activo {
                        Color.black.opacity(0.001)
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { arrastre = ($0.startLocation, $0.location) }
                                .onEnded { v in
                                    arrastre = nil
                                    let a = v.startLocation, b = v.location
                                    guard abs(a.x - b.x) > 8, abs(a.y - b.y) > 8, let c = visor.vista?.camara,
                                          let e = visor.estado3d() else { return }
                                    marcos.poner(caja: [(min(a.x, b.x) - w / 2) / h, (min(a.y, b.y) - h / 2) / h,
                                                        (max(a.x, b.x) - w / 2) / h, (max(a.y, b.y) - h / 2) / h], camara: c, estado: e)
                                })
                    }
                    ForEach(Array(marcos.lista.enumerated()), id: \.element.id) { i, m in
                        if let camara, Marcos3D.coincide(camara, m.camara) {
                            let r = CGRect(x: m.caja[0] * h + w / 2, y: m.caja[1] * h + h / 2,
                                           width: (m.caja[2] - m.caja[0]) * h, height: (m.caja[3] - m.caja[1]) * h)
                            Rectangle().stroke(Color(nsColor: CapaMarcosPDF.azul), lineWidth: 1.2)
                                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                            Text("\(i + 1)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 14, height: 14).background(Color(nsColor: CapaMarcosPDF.azul))
                                .offset(x: r.minX, y: r.minY)
                        }
                    }
                    if let (a, b) = arrastre {
                        Rectangle().stroke(Color(nsColor: CapaMarcosPDF.azul), lineWidth: 1)
                            .frame(width: abs(a.x - b.x), height: abs(a.y - b.y))
                            .offset(x: min(a.x, b.x), y: min(a.y, b.y))
                    }
                }
                .allowsHitTesting(marcos.activo)
            }
            HStack(spacing: 6) {
                ForEach(Array(marcos.lista.enumerated()), id: \.element.id) { i, m in
                    Button { visor.aplicar(estado: m.estado) } label: {
                        Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: CapaMarcosPDF.azul)))
                    }
                    .buttonStyle(.plain)
                    .help("Ir al marco \(i + 1)")
                }
                if marcos.activo {
                    Text("Arrastra: un marco con esta vista · Supr quita el último · ⌘P imprime · I sale")
                        .font(.system(size: 11)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(Color(white: 0.08, opacity: 0.9)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

extension VisorModelo3D {
    /// **Imprimir los marcos**: cada uno con su vista, fotografiado y
    /// recortado a su recuadro; una hoja por marco.
    func imprimirMarcos3D() {
        guard let v = vista, !marcos3d.lista.isEmpty else { return NSSound.beep() }
        let antes = v.camara
        let lista = marcos3d.lista
        let salida = PDFDocument()
        func siguiente(_ i: Int) {
            guard i < lista.count else {
                v.ponerCamara(antes)
                if let op = salida.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) {
                    if let w = v.window { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
                }
                return
            }
            let m = lista[i]
            aplicar(estado: m.estado)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                v.foto { img in
                    if let img {
                        let w = CGFloat(img.width), h = CGFloat(img.height)
                        let r = CGRect(x: m.caja[0] * h + w / 2, y: m.caja[1] * h + h / 2,
                                       width: (m.caja[2] - m.caja[0]) * h, height: (m.caja[3] - m.caja[1]) * h).integral
                        if let c = img.cropping(to: r),
                           let p = PDFPage(image: NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height))) {
                            salida.insert(p, at: salida.pageCount)
                        }
                    }
                    siguiente(i + 1)
                }
            }
        }
        siguiente(0)
    }

    func alternarMarcos3D() {
        marcos3d.activo.toggle()
        riel.enmarcando = marcos3d.activo
    }
}
