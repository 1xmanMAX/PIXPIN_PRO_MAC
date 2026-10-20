import AppKit
import PDFKit
import PixPinCore

/// **Los marcos numerados de los documentos** (Windows, 19-oct,
/// `marcos_doc.rs`), con la logica de los marcos para imprimir del plano:
/// el boton del marco del riel (o la I) entra y sale del modo; arrastrar
/// deja un marco (su numero es su sitio); Supr quita el ultimo; ⌘P los
/// imprime todos en grupo, una hoja por marco. Se guardan junto al fichero,
/// en `<fichero>.pixpin-marcos` (JSON, el mismo de Windows: `caja`
/// `[x0, y0, x1, y1]`, `parte` = la hoja).
struct MarcoDoc: Codable, Equatable {
    var caja: [Double]
    var parte: UInt32 = 0
    var vista: String?

    var rect: CGRect { CGRect(x: caja[0], y: caja[1], width: caja[2] - caja[0], height: caja[3] - caja[1]) }
}

@MainActor
final class MarcosDoc {
    private(set) var lista: [MarcoDoc] = []
    var activo = false
    private let fichero: URL?
    /// Si viaja (es `anot-<uid>.marcos.json` de un adjunto): vaciar escribe
    /// `[]`, nunca borra (no hay lapidas de ficheros; volveria).
    private let viaja: Bool

    init(documento: URL?, nucleo: Nucleo? = nil) {
        if let d = documento, let n = nucleo, let r = n.rutaAnotadaDelAdjunto(documento: d.path, terminacion: ".marcos.json") {
            fichero = URL(fileURLWithPath: r)
            viaja = true
        } else {
            fichero = documento.map { $0.appendingPathExtension("pixpin-marcos") }
            viaja = false
        }
        if let f = fichero, let d = try? Data(contentsOf: f),
           let l = try? JSONDecoder().decode([MarcoDoc].self, from: d) {
            lista = l.filter { $0.caja.count == 4 }
        }
    }

    func poner(_ r: CGRect, parte: Int) {
        lista.append(MarcoDoc(caja: [r.minX, r.minY, r.maxX, r.maxY], parte: UInt32(parte)))
        guardar()
    }

    @discardableResult
    func quitarUltimo() -> Bool {
        guard lista.popLast() != nil else { return false }
        guardar()
        return true
    }

    func borrar() { lista = []; guardar() }

    private func guardar() {
        guard let f = fichero else { return }
        if lista.isEmpty, !viaja { try? FileManager.default.removeItem(at: f); return }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        try? e.encode(lista).write(to: f, options: .atomic)
    }
}

/// **Las unidades del lector de Windows** (`pixpin_docs::vista::Hojas`):
/// cada hoja 1400 de ancho, una debajo de otra con 18 de hueco, Y hacia
/// abajo. En ellas van los marcos de un PDF, para que viajen con Windows.
struct HojasDelLector {
    static let ancho: CGFloat = 1400
    static let hueco: CGFloat = 18
    let arriba: [CGFloat]
    let altos: [CGFloat]

    init(_ doc: PDFDocument, caja: PDFDisplayBox) {
        var y: CGFloat = 0, a: [CGFloat] = [], h: [CGFloat] = []
        for i in 0..<doc.pageCount {
            let b = doc.page(at: i)?.bounds(for: caja) ?? .zero
            let p = b.width > 0 && b.height > 0 ? min(max(b.height / b.width, 0.05), 20) : 1.414
            a.append(y); h.append(HojasDelLector.ancho * p)
            y += HojasDelLector.ancho * p + HojasDelLector.hueco
        }
        arriba = a; altos = h
    }

    /// De un punto de la hoja `i` (PDF, Y arriba) a unidades.
    func unidades(_ p: CGPoint, hoja i: Int, bounds b: CGRect) -> CGPoint {
        CGPoint(x: (p.x - b.minX) / b.width * HojasDelLector.ancho,
                y: arriba[i] + (b.maxY - p.y) / b.height * altos[i])
    }

    /// La hoja de una Y en unidades (la mas cercana).
    func hoja(de y: CGFloat) -> Int {
        var i = 0
        while i + 1 < arriba.count, y >= arriba[i + 1] - HojasDelLector.hueco / 2 { i += 1 }
        return i
    }

    /// De unidades a un punto de su hoja (PDF, Y arriba).
    func punto(_ u: CGPoint, bounds b: CGRect, hoja i: Int) -> CGPoint {
        CGPoint(x: b.minX + u.x / HojasDelLector.ancho * b.width,
                y: b.maxY - (u.y - arriba[i]) / altos[i] * b.height)
    }
}

/// La capa de los marcos sobre las hojas de un PDF (dentro de la vista del
/// documento, se desplaza con ellas). Los marcos van en las unidades del
/// lector de Windows (`HojasDelLector`), en el `anot-<uid>.marcos.json` que
/// viaja si el PDF es un adjunto.
@MainActor
final class CapaMarcosPDF: NSView {
    weak var vistaPDF: PDFView?
    var marcos: MarcosDoc? { didSet { needsDisplay = true } }
    var alCambiar: (() -> Void)?
    private var inicio: NSPoint?
    private var actual: NSPoint?

    static let azul = NSColor(srgbRed: 0, green: 0x78 / 255, blue: 0xD4 / 255, alpha: 1)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { marcos?.activo == true ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if marcos?.activo == true { addCursorRect(visibleRect, cursor: .crosshair) } }

    private var hojas: HojasDelLector? {
        guard let v = vistaPDF, let d = v.document else { return nil }
        return HojasDelLector(d, caja: v.displayBox)
    }

    /// De esta vista a unidades.
    private func aUnidades(_ p: NSPoint, _ h: HojasDelLector) -> CGPoint? {
        guard let v = vistaPDF, let d = v.document else { return nil }
        let enV = v.convert(p, from: self)
        guard let hoja = v.page(for: enV, nearest: true) else { return nil }
        let i = d.index(for: hoja)
        return h.unidades(v.convert(enV, to: hoja), hoja: i, bounds: hoja.bounds(for: v.displayBox))
    }

    /// De unidades a esta vista.
    private func aVista(_ u: CGPoint, _ h: HojasDelLector) -> NSPoint? {
        guard let v = vistaPDF, let d = v.document else { return nil }
        let i = h.hoja(de: u.y)
        guard let hoja = d.page(at: i) else { return nil }
        let p = h.punto(u, bounds: hoja.bounds(for: v.displayBox), hoja: i)
        return convert(v.convert(p, from: hoja), from: v)
    }

    private func rectEnVista(_ m: MarcoDoc, _ h: HojasDelLector) -> CGRect? {
        guard let a = aVista(CGPoint(x: m.caja[0], y: m.caja[1]), h),
              let b = aVista(CGPoint(x: m.caja[2], y: m.caja[3]), h) else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ sucio: NSRect) {
        guard let m = marcos, let h = hojas else { return }
        let k = escalaDeMarcos
        for (i, marco) in m.lista.enumerated() {
            guard let r = rectEnVista(marco, h), r.insetBy(dx: -20, dy: -20).intersects(sucio) else { continue }
            CapaMarcosPDF.azul.setStroke()
            let camino = NSBezierPath(rect: r)
            camino.lineWidth = 1.2 / k
            camino.stroke()
            let t = "\(i + 1)" as NSString
            let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9 / k, weight: .semibold), .foregroundColor: NSColor.white]
            let s = t.size(withAttributes: atr)
            let caja = NSRect(x: r.minX, y: r.minY, width: max(14 / k, s.width + 6 / k), height: 14 / k)
            CapaMarcosPDF.azul.setFill()
            NSBezierPath(rect: caja).fill()
            t.draw(at: NSPoint(x: caja.midX - s.width / 2, y: caja.midY - s.height / 2), withAttributes: atr)
        }
        if let a = inicio, let b = actual {
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            c.lineWidth = 1 / k
            c.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) { inicio = convert(e.locationInWindow, from: nil); actual = inicio }
    override func mouseDragged(with e: NSEvent) { actual = convert(e.locationInWindow, from: nil); needsDisplay = true }

    override func mouseUp(with e: NSEvent) {
        defer { inicio = nil; actual = nil; needsDisplay = true }
        guard let a = inicio, let m = marcos, let h = hojas else { return }
        let b = convert(e.locationInWindow, from: nil)
        // Menos de 8 px de pantalla de ancho o de alto es un clic.
        let k = escalaDeMarcos
        guard abs(a.x - b.x) * k > 8, abs(a.y - b.y) * k > 8,
              let ua = aUnidades(a, h), let ub = aUnidades(b, h) else { return }
        m.poner(CGRect(x: min(ua.x, ub.x), y: min(ua.y, ub.y), width: abs(ua.x - ub.x), height: abs(ua.y - ub.y)), parte: 0)
        alCambiar?()
    }

    /// **Imprimir los marcos en grupo**: cada marco, dibujado en su propia
    /// hoja de un PDF nuevo (con la tinta si `documento` la lleva quemada).
    static func imprimir(_ marcos: MarcosDoc, documento: PDFDocument, ventana: NSWindow?) {
        let h = HojasDelLector(documento, caja: .mediaBox)
        let datos = NSMutableData()
        guard let consumidor = CGDataConsumer(data: datos as CFMutableData),
              let ctx = CGContext(consumer: consumidor, mediaBox: nil, nil) else { return }
        for m in marcos.lista {
            let i = h.hoja(de: CGFloat(m.caja[1]))
            guard let p = documento.page(at: i) else { continue }
            let b = p.bounds(for: .mediaBox)
            let a = h.punto(CGPoint(x: m.caja[0], y: m.caja[1]), bounds: b, hoja: i)
            let z = h.punto(CGPoint(x: m.caja[2], y: m.caja[3]), bounds: b, hoja: i)
            let r = CGRect(x: min(a.x, z.x), y: min(a.y, z.y), width: abs(a.x - z.x), height: abs(a.y - z.y))
            var caja = CGRect(origin: .zero, size: r.size)
            ctx.beginPage(mediaBox: &caja)
            ctx.translateBy(x: -r.minX, y: -r.minY)
            ctx.clip(to: r)
            p.draw(with: .mediaBox, to: ctx)
            ctx.endPage()
        }
        ctx.closePDF()
        guard let salida = PDFDocument(data: datos as Data), salida.pageCount > 0,
              let op = salida.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        if let ventana { op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }
}

/// La capa de los marcos sobre una vista de documento cualquiera (la pagina
/// del visor reflujado): los marcos van en las coordenadas de esa vista y
/// se imprimen recortandola.
@MainActor
final class CapaMarcosVista: NSView {
    weak var documento: NSView?
    var marcos: MarcosDoc? { didSet { needsDisplay = true } }
    /// La parte que se ve (la hoja de un libro): solo sus marcos.
    var parte = 0 { didSet { needsDisplay = true } }
    private var inicio: NSPoint?
    private var actual: NSPoint?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { marcos?.activo == true ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if marcos?.activo == true { addCursorRect(visibleRect, cursor: .crosshair) } }

    override func draw(_ sucio: NSRect) {
        guard let m = marcos else { return }
        for (i, marco) in m.lista.enumerated() where Int(marco.parte) == parte && marco.rect.intersects(sucio) {
            let r = marco.rect
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: r)
            c.lineWidth = 1.2 / escalaDeMarcos
            c.stroke()
            let t = "\(i + 1)" as NSString
            let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9 / escalaDeMarcos, weight: .semibold), .foregroundColor: NSColor.white]
            let s = t.size(withAttributes: atr)
            let caja = NSRect(x: r.minX, y: r.minY, width: max(14 / escalaDeMarcos, s.width + 6 / escalaDeMarcos), height: 14 / escalaDeMarcos)
            CapaMarcosPDF.azul.setFill()
            NSBezierPath(rect: caja).fill()
            t.draw(at: NSPoint(x: caja.midX - s.width / 2, y: caja.midY - s.height / 2), withAttributes: atr)
        }
        if let a = inicio, let b = actual {
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            c.lineWidth = 1 / escalaDeMarcos
            c.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) { inicio = convert(e.locationInWindow, from: nil); actual = inicio }
    override func mouseDragged(with e: NSEvent) { actual = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        defer { inicio = nil; actual = nil; needsDisplay = true }
        guard let a = inicio, let m = marcos else { return }
        let b = convert(e.locationInWindow, from: nil)
        guard abs(a.x - b.x) > 8, abs(a.y - b.y) > 8 else { return }
        m.poner(NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)), parte: parte)
    }

    /// Los marcos en grupo: cada uno, el trozo de la pagina, una hoja.
    func imprimir(ventana: NSWindow?) {
        guard let m = marcos, let doc = documento else { return }
        let salida = PDFDocument()
        // Lo impreso va sin la raya ni el numero.
        isHidden = true
        defer { isHidden = false }
        for marco in m.lista where Int(marco.parte) == parte {
            let r = convert(marco.rect, to: doc)
            if let p = PDFDocument(data: doc.dataWithPDF(inside: r))?.page(at: 0) { salida.insert(p, at: salida.pageCount) }
        }
        guard salida.pageCount > 0,
              let op = salida.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        if let ventana { op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }
}

extension NSView {
    /// Cuantos puntos de pantalla mide una unidad de esta vista (con el
    /// zoom de la vista que la desplaza): para que rayas y numeros midan
    /// siempre lo mismo en pantalla.
    var escalaDeMarcos: CGFloat {
        let u = convert(NSSize(width: 1, height: 1), to: nil).width
        return u > 0.0001 ? abs(u) : 1
    }
}

/// **Las vistas de los marcadores de un documento** (Windows, 20-oct,
/// `anot-<uid>.vistas.json`): id del marcador → `"zoom x y"` (el zoom en
/// pixeles por unidad y la esquina de arriba a la izquierda, en unidades
/// del documento). Un marcador sin vista vuelve solo a su sitio.
@MainActor
final class VistasDoc {
    private(set) var vistas: [String: String] = [:]
    private let fichero: URL?

    init(documento: URL?, nucleo: Nucleo?) {
        if let d = documento, let n = nucleo, let r = n.rutaAnotadaDelAdjunto(documento: d.path, terminacion: ".vistas.json") {
            fichero = URL(fileURLWithPath: r)
        } else {
            fichero = documento.map { $0.appendingPathExtension("pixpin-vistas") }
        }
        if let f = fichero, let d = try? Data(contentsOf: f),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] { vistas = o }
    }

    func vista(_ id: Int64) -> (zoom: CGFloat, x: CGFloat, y: CGFloat)? {
        let p = (vistas[String(id)] ?? "").split(separator: " ").compactMap { Double($0) }
        guard p.count == 3, p[0] > 0 else { return nil }
        return (CGFloat(p[0]), CGFloat(p[1]), CGFloat(p[2]))
    }

    func poner(_ id: Int64, zoom: CGFloat, x: CGFloat, y: CGFloat) {
        vistas[String(id)] = "\(zoom) \(x) \(y)"
        guardar()
    }

    /// Solo los de `vivos` (los marcadores que quedan). Vaciar escribe `{}`.
    func quedarse(con vivos: Set<String>) {
        let antes = vistas.count
        vistas = vistas.filter { vivos.contains($0.key) }
        if vistas.count != antes { guardar() }
    }

    private func guardar() {
        guard let f = fichero, let d = try? JSONSerialization.data(withJSONObject: vistas, options: [.sortedKeys]) else { return }
        try? d.write(to: f, options: .atomic)
    }
}
