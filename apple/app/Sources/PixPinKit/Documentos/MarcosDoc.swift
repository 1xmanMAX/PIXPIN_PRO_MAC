import AppKit
import PDFKit

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

    init(documento: URL?) {
        fichero = documento.map { $0.appendingPathExtension("pixpin-marcos") }
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
        if lista.isEmpty { try? FileManager.default.removeItem(at: f); return }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        try? e.encode(lista).write(to: f, options: .atomic)
    }
}

/// La capa de los marcos sobre las hojas de un PDF (dentro de la vista del
/// documento, se desplaza con ellas). Los marcos van en puntos de su hoja.
@MainActor
final class CapaMarcosPDF: NSView {
    weak var vistaPDF: PDFView?
    var marcos: MarcosDoc? { didSet { needsDisplay = true } }
    var alCambiar: (() -> Void)?
    private var inicio: (punto: NSPoint, hoja: PDFPage)?
    private var actual: NSPoint?

    static let azul = NSColor(srgbRed: 0, green: 0x78 / 255, blue: 0xD4 / 255, alpha: 1)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { marcos?.activo == true ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if marcos?.activo == true { addCursorRect(visibleRect, cursor: .crosshair) } }

    /// La caja de un marco de la hoja `p` en esta vista.
    private func enVista(_ r: CGRect, _ p: PDFPage) -> CGRect? {
        guard let v = vistaPDF else { return nil }
        return convert(v.convert(r, from: p), from: v)
    }

    override func draw(_ sucio: NSRect) {
        guard let m = marcos, let v = vistaPDF, let doc = v.document else { return }
        for (i, marco) in m.lista.enumerated() {
            guard let p = doc.page(at: Int(marco.parte)), let r = enVista(marco.rect, p), r.intersects(sucio) else { continue }
            CapaMarcosPDF.azul.setStroke()
            let camino = NSBezierPath(rect: r)
            camino.lineWidth = 1.2 / escalaDeMarcos
            camino.stroke()
            // Su numero blanco en un cuadrito azul, arriba a la izquierda.
            let t = "\(i + 1)" as NSString
            let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9 / escalaDeMarcos, weight: .semibold), .foregroundColor: NSColor.white]
            let s = t.size(withAttributes: atr)
            let caja = NSRect(x: r.minX, y: r.minY, width: max(14 / escalaDeMarcos, s.width + 6 / escalaDeMarcos), height: 14 / escalaDeMarcos)
            CapaMarcosPDF.azul.setFill()
            NSBezierPath(rect: caja).fill()
            t.draw(at: NSPoint(x: caja.midX - s.width / 2, y: caja.midY - s.height / 2), withAttributes: atr)
        }
        if let a = inicio?.punto, let b = actual {
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            c.lineWidth = 1 / escalaDeMarcos
            c.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) {
        guard let v = vistaPDF else { return }
        let p = convert(e.locationInWindow, from: nil)
        guard let hoja = v.page(for: v.convert(p, from: self), nearest: true) else { return }
        inicio = (p, hoja)
        actual = p
    }

    override func mouseDragged(with e: NSEvent) {
        actual = convert(e.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { inicio = nil; actual = nil; needsDisplay = true }
        guard let (a, hoja) = inicio, let v = vistaPDF, let m = marcos, let doc = v.document else { return }
        let b = convert(e.locationInWindow, from: nil)
        // Menos de 8 px de ancho o de alto es un clic: no cuenta.
        guard abs(a.x - b.x) > 8, abs(a.y - b.y) > 8 else { return }
        let ra = v.convert(v.convert(a, from: self), to: hoja), rb = v.convert(v.convert(b, from: self), to: hoja)
        let r = CGRect(x: min(ra.x, rb.x), y: min(ra.y, rb.y), width: abs(ra.x - rb.x), height: abs(ra.y - rb.y))
            .intersection(hoja.bounds(for: v.displayBox))
        guard !r.isNull else { return }
        m.poner(r, parte: doc.index(for: hoja))
        alCambiar?()
    }

    /// **Imprimir los marcos en grupo**: un PDF con una hoja por marco (su
    /// hoja recortada al marco), al dialogo de imprimir del Mac.
    static func imprimir(_ marcos: MarcosDoc, documento: PDFDocument, ventana: NSWindow?) {
        // Cada marco, dibujado en su propia hoja de un PDF nuevo (copiar la
        // hoja y recortarla dejaba la vista previa en blanco).
        let datos = NSMutableData()
        guard let consumidor = CGDataConsumer(data: datos as CFMutableData),
              let ctx = CGContext(consumer: consumidor, mediaBox: nil, nil) else { return }
        for m in marcos.lista {
            guard let p = documento.page(at: Int(m.parte)) else { continue }
            var caja = CGRect(origin: .zero, size: m.rect.size)
            ctx.beginPage(mediaBox: &caja)
            ctx.translateBy(x: -m.rect.minX, y: -m.rect.minY)
            ctx.clip(to: m.rect)
            p.draw(with: .mediaBox, to: ctx)
            ctx.endPage()
        }
        ctx.closePDF()
        guard let salida = PDFDocument(data: datos as Data) else { return }
        guard salida.pageCount > 0,
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
    private var inicio: NSPoint?
    private var actual: NSPoint?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { marcos?.activo == true ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if marcos?.activo == true { addCursorRect(visibleRect, cursor: .crosshair) } }

    override func draw(_ sucio: NSRect) {
        guard let m = marcos else { return }
        for (i, marco) in m.lista.enumerated() where marco.rect.intersects(sucio) {
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
        m.poner(NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)), parte: 0)
    }

    /// Los marcos en grupo: cada uno, el trozo de la pagina, una hoja.
    func imprimir(ventana: NSWindow?) {
        guard let m = marcos, let doc = documento else { return }
        let salida = PDFDocument()
        // Lo impreso va sin la raya ni el numero.
        isHidden = true
        defer { isHidden = false }
        for marco in m.lista {
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
