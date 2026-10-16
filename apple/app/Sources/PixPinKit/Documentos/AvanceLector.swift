// **La pagina que sube sola** (D, «Desplazar sola»; `LectorPdfActivity` del
// movil v0.92 y `lector_pdf.rs` de Windows). La velocidad va en **palabras
// por minuto**, que es como se mide leer: no cambia al acercar (el
// documento se alarga, pero las palabras son las mismas) y «Terminas en…»
// sale directo. Las cuentas son las de `pixpin_docs::auto_desplazar`, por
// el nucleo; la velocidad se recuerda en este equipo, como alla.
//
// La barra va abajo en medio, de cristal oscuro: −, la velocidad, +, pausa
// y cerrar, y debajo lo que queda. Anotando no corre; al llegar al final se
// para sola (la barra sigue, con el play).
//
// Aqui va tambien la tira de los marcadores (M: se elige el emoticono con
// su cifra, como en Windows) y el riel de la derecha con los marcadores
// puestos (⌘1…9 para ir a ellos).

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class AvanceLector: ObservableObject {
    /// La barra puesta.
    @Published var activo = false
    @Published var enMarcha = true
    @Published var ppm: UInt32 = 230
    /// «Terminas en 12 min · a las 18:40».
    @Published var quedan = "Contando las palabras…"
    /// Las palabras del documento (`nil` mientras se cuentan).
    var palabras: Int?
    /// Lo que no llego a un pixel, para la vuelta siguiente (`sobra`).
    var sobra: CGFloat = 0
    var antes: CFTimeInterval?

    /// Una vuelta: cuanto bajar, en puntos, a `porSegundo` (lo que pasa de
    /// una decima entre dos vueltas cuenta como una decima, como alla).
    func paso(ahora: CFTimeInterval, porSegundo: CGFloat, quieta: Bool, pixel: CGFloat) -> CGFloat {
        guard activo, enMarcha, !quieta, porSegundo > 0 else {
            antes = nil
            sobra = 0
            return 0
        }
        guard let a = antes else {
            antes = ahora
            return 0
        }
        antes = ahora
        sobra += porSegundo * CGFloat(min(max(ahora - a, 0), 0.1))
        let n = (sobra / pixel).rounded(.down) * pixel
        sobra -= n
        return n
    }

    func alternar() {
        enMarcha.toggle()
        antes = nil
        sobra = 0
    }

    func alFinal() {
        enMarcha = false
        antes = nil
        sobra = 0
    }
}

/// **La barra de la pagina que sube sola**.
struct BarraAvance: View {
    @ObservedObject var avance: AvanceLector
    let cambiar: (Int32) -> Void
    let cerrar: () -> Void

    var body: some View {
        if avance.activo {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    boton("minus", "Más despacio") { cambiar(-1) }
                    Text("\(avance.ppm) palabras/min")
                        .font(.system(size: 13).monospacedDigit())
                        .padding(.horizontal, 8)
                        .fixedSize()
                    boton("plus", "Más deprisa") { cambiar(1) }
                    boton(avance.enMarcha ? "pause.fill" : "play.fill",
                          avance.enMarcha ? "Pausa" : "Seguir") { avance.alternar() }
                    boton("xmark", "Dejar de desplazar (D)") { cerrar() }
                }
                Text(avance.quedan)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.78))
                    .fixedSize()
            }
            .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.95),
                        in: RoundedRectangle(cornerRadius: 20))
            .environment(\.colorScheme, .dark)
        }
    }

    private func boton(_ simbolo: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 15)).frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }
}

/// **La tira de los marcadores** (M): cada emoticono con su cifra; se elige
/// pulsandolo o con la cifra (1…9 y 0, `emoji_de_cifra`). ⎋ o M la quitan.
struct TiraMarcas: View {
    @ObservedObject var modelo: ModeloLector
    let elegir: (String) -> Void

    var body: some View {
        if modelo.poniendoMarca {
            VStack(spacing: 4) {
                Text("Elige un marcador (su cifra) · ⎋ para no poner ninguno")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.78))
                HStack(spacing: 2) {
                    ForEach(Array(emojisDeMarcas().enumerated()), id: \.offset) { i, e in
                        Button { elegir(e) } label: {
                            VStack(spacing: 0) {
                                Text(e).font(.system(size: 20))
                                Text(i < 10 ? "\((i + 1) % 10)" : " ").font(.system(size: 9))
                                    .foregroundStyle(Color(white: 0.7))
                            }
                            .frame(width: 34, height: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.95),
                        in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
        }
    }
}

/// **Un aviso que se va solo** («Ahora se llama…»), arriba en medio.
struct NotaLector: View {
    @ObservedObject var modelo: ModeloLector

    var body: some View {
        if let n = modelo.nota {
            Text(n)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.95),
                            in: RoundedRectangle(cornerRadius: 12))
                .fixedSize()
        }
    }
}

/// **La caja del nombre** (F2): se escribe el nuevo sin la extension;
/// ↩ lo guarda y ⎋ deja el de antes.
struct CajaNombre: View {
    @ObservedObject var modelo: ModeloLector
    let confirmar: (String) -> Void
    let cancelar: () -> Void
    @FocusState private var enfocada: Bool

    var body: some View {
        if modelo.renombrando != nil {
            HStack(spacing: 8) {
                Text("Nombre:").foregroundStyle(Color(white: 0.78))
                TextField("", text: Binding(get: { modelo.renombrando ?? "" },
                                            set: { modelo.renombrando = String($0.prefix(80)) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .frame(width: 280)
                    .focused($enfocada)
                    .onSubmit { confirmar(modelo.renombrando ?? "") }
                    .onExitCommand { cancelar() }
                Text("↩ guarda · ⎋ deja el de antes")
                    .font(.caption).foregroundStyle(Color(white: 0.6)).fixedSize()
            }
            .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.97),
                        in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, .dark)
            .onAppear { enfocada = true }
        }
    }
}

/// **El riel de los marcadores**, en el canto derecho: cada marcador a la
/// altura de su sitio en el documento; un clic lleva a el (⌘1…9, en el
/// orden del riel).
final class RielMarcasNS: NSView {
    var marcas: [MarcaDocumento] = [] { didSet { rehacer() } }
    var paginas = 0 { didSet { rehacer() } }
    var ir: ((MarcaDocumento) -> Void)?
    private var zonas: [(NSRect, MarcaDocumento)] = []
    static let lado: CGFloat = 22

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return zonas.contains { $0.0.contains(p) } ? self : nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rehacer()
    }

    /// Donde cae cada marcador: su fraccion del documento a lo alto.
    static func zonas(marcas: [MarcaDocumento], paginas: Int, alto: CGFloat) -> [NSRect] {
        guard paginas > 0 else { return [] }
        let util = max(alto - 2 * lado, 1)
        return marcas.map { m in
            let f = min(max(CGFloat(m.y) / CGFloat(paginas), 0), 1)
            return NSRect(x: 0, y: lado / 2 + f * util, width: lado, height: lado)
        }
    }

    private func rehacer() {
        removeAllToolTips()
        let r = RielMarcasNS.zonas(marcas: marcas, paginas: paginas, alto: bounds.height)
        zonas = Array(zip(r, marcas))
        for (i, (z, m)) in zonas.enumerated() {
            addToolTip(z, owner: "\(m.emoji)  pág. \(Int(m.y) + 1)\(i < 9 ? "  (⌘\(i + 1))" : "")" as NSString,
                       userData: nil)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (z, m) in zonas where z.intersects(dirtyRect) {
            NSColor(white: 0.12, alpha: 0.55).setFill()
            NSBezierPath(ovalIn: z.insetBy(dx: -2, dy: -2)).fill()
            (m.emoji as NSString).draw(in: z.offsetBy(dx: 2, dy: 1),
                                       withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let m = zonas.first(where: { $0.0.contains(p) })?.1 { ir?(m) }
    }
}
