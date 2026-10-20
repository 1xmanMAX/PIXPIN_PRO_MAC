import AppKit
import PixPinCore
import WebKit

/// **La tinta de una pagina web** (visor de HTML; Windows, 19-oct): la
/// capa del documento (`anotarReflujo`, la misma que viaja), en pixeles CSS
/// del documento. Va encima de la pagina y sigue a su desplazamiento y a su
/// zoom: lo anotado se queda donde se puso. Con el lapiz suelto deja pasar
/// los clics a la pagina.
@MainActor
final class CapaTintaWeb: NSView {
    weak var web: WKWebView?
    var editor: EditorLienzo? { didSet { leido = nil; needsDisplay = true } }
    var anotando = false { didSet { window?.invalidateCursorRects(for: self) } }
    var alSoltar: (() -> Void)?
    /// Los marcos numerados, en px CSS del documento (como la tinta).
    var marcos: MarcosDoc? { didSet { needsDisplay = true } }
    private var marcoInicio: NSPoint?
    private var marcoActual: NSPoint?
    /// Desplazamiento de la pagina (px CSS) y su zoom.
    var desplazado = CGPoint.zero { didSet { needsDisplay = true } }
    private var leido: (version: UInt64, lienzo: LienzoLeido)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var zoom: CGFloat { (web?.pageZoom ?? 1) * (web?.magnification ?? 1) }

    /// De la vista al documento.
    private func aDocumento(_ p: NSPoint) -> NSPoint {
        NSPoint(x: p.x / zoom + desplazado.x, y: p.y / zoom + desplazado.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        anotando || marcos?.activo == true ? super.hitTest(point) : nil
    }

    /// Del documento a la vista.
    func aVista(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - desplazado.x) * zoom, y: (r.minY - desplazado.y) * zoom, width: r.width * zoom, height: r.height * zoom)
    }

    private func pintarMarcos() {
        guard let m = marcos else { return }
        for (i, marco) in m.lista.enumerated() {
            let r = aVista(marco.rect)
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: r)
            c.lineWidth = 2
            c.stroke()
            let t = "\(i + 1)" as NSString
            let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white]
            let s = t.size(withAttributes: atr)
            let caja = NSRect(x: r.minX, y: r.minY, width: max(20, s.width + 10), height: 20)
            CapaMarcosPDF.azul.setFill()
            NSBezierPath(rect: caja).fill()
            t.draw(at: NSPoint(x: caja.midX - s.width / 2, y: caja.midY - s.height / 2), withAttributes: atr)
        }
        if let a = marcoInicio, let b = marcoActual {
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            c.lineWidth = 1.5
            c.stroke()
        }
    }

    override func draw(_ sucio: NSRect) {
        if !ocultarMarcos { pintarMarcos() }
        guard let ed = editor, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let v = ed.version()
        if leido?.version != v, let l = try? leerLienzo(ed.plano()) { leido = (v, l) }
        guard let l = leido?.lienzo, !l.figuras.isEmpty else { return }
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -desplazado.x, y: -desplazado.y)
        let visible = NSRect(x: desplazado.x, y: desplazado.y, width: bounds.width / zoom, height: bounds.height / zoom)
        PintorLienzo(lienzo: l).pintar(en: ctx, limites: visible)
        ctx.restoreGState()
    }

    private func puntero(_ fase: FasePuntero, _ e: NSEvent) {
        guard let ed = editor else { return }
        let p = aDocumento(convert(e.locationInWindow, from: nil))
        let presion: Float? = e.subtype == .tabletPoint ? Float(e.pressure) : nil
        var mods: UInt32 = 0
        if e.modifierFlags.contains(.shift) { mods |= 1 }
        if e.modifierFlags.contains(.option) { mods |= 2 }
        _ = ed.puntero(fase: fase, x: Float(p.x), y: Float(p.y), presion: presion, modificadores: mods, zoom: Float(zoom))
        needsDisplay = true
        if fase == .soltar { alSoltar?() }
    }

    var ocultarMarcos = false

    override func mouseDown(with e: NSEvent) {
        if marcos?.activo == true { marcoInicio = convert(e.locationInWindow, from: nil); marcoActual = marcoInicio; return }
        puntero(.pulsar, e)
    }
    override func mouseDragged(with e: NSEvent) {
        if marcoInicio != nil { marcoActual = convert(e.locationInWindow, from: nil); needsDisplay = true; return }
        puntero(.mover, e)
    }
    override func mouseUp(with e: NSEvent) {
        if let a = marcoInicio {
            let b = convert(e.locationInWindow, from: nil)
            marcoInicio = nil; marcoActual = nil
            if abs(a.x - b.x) > 8, abs(a.y - b.y) > 8, let m = marcos {
                let p = aDocumento(NSPoint(x: min(a.x, b.x), y: min(a.y, b.y)))
                let q = aDocumento(NSPoint(x: max(a.x, b.x), y: max(a.y, b.y)))
                m.poner(CGRect(x: p.x, y: p.y, width: q.x - p.x, height: q.y - p.y), parte: 0)
            }
            needsDisplay = true
            return
        }
        puntero(.soltar, e)
    }
    override func rightMouseDown(with e: NSEvent) {
        if editor?.deshacer() == true { needsDisplay = true; alSoltar?() }
    }
    /// La rueda sigue moviendo la pagina con el lapiz pulsado.
    override func scrollWheel(with e: NSEvent) { web?.scrollWheel(with: e) }
    override func resetCursorRects() { if anotando || marcos?.activo == true { addCursorRect(bounds, cursor: .crosshair) } }

    /// El guion que avisa del desplazamiento de la pagina.
    static let guion = """
    (function(){var t=0;function a(){t=0;window.webkit.messageHandlers.pixpinScroll.postMessage([scrollX,scrollY]);}
    addEventListener('scroll',function(){if(!t){t=requestAnimationFrame(a);}},{passive:true});
    addEventListener('load',a);addEventListener('resize',a);})();
    """
}

