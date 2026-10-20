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
        anotando ? super.hitTest(point) : nil
    }

    override func draw(_ sucio: NSRect) {
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

    override func mouseDown(with e: NSEvent) { puntero(.pulsar, e) }
    override func mouseDragged(with e: NSEvent) { puntero(.mover, e) }
    override func mouseUp(with e: NSEvent) { puntero(.soltar, e) }
    override func rightMouseDown(with e: NSEvent) {
        if editor?.deshacer() == true { needsDisplay = true; alSoltar?() }
    }
    /// La rueda sigue moviendo la pagina con el lapiz pulsado.
    override func scrollWheel(with e: NSEvent) { web?.scrollWheel(with: e) }
    override func resetCursorRects() { if anotando { addCursorRect(bounds, cursor: .crosshair) } }

    /// El guion que avisa del desplazamiento de la pagina.
    static let guion = """
    (function(){var t=0;function a(){t=0;window.webkit.messageHandlers.pixpinScroll.postMessage([scrollX,scrollY]);}
    addEventListener('scroll',function(){if(!t){t=requestAnimationFrame(a);}},{passive:true});
    addEventListener('load',a);addEventListener('resize',a);})();
    """
}

