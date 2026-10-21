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

    /// Mientras se arrastra un trazo o un marco: entonces lo pinta esta capa;
    /// si no, va DENTRO de la pagina (un SVG en px CSS) y se desplaza con
    /// ella sin ningun retraso.
    private var pulsando = false
    private var enviado: String?
    private var envioPendiente = false

    override var needsDisplay: Bool {
        didSet { if needsDisplay { programarPagina() } }
    }

    /// Manda a la pagina lo anotado y los marcos (una vez por cambio).
    private func programarPagina() {
        guard !envioPendiente else { return }
        envioPendiente = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.envioPendiente = false
            self.enviarALaPagina()
        }
    }

    func enviarALaPagina(forzar: Bool = false) {
        guard let web else { return }
        var l: LienzoLeido?
        if let ed = editor {
            let v = ed.version()
            if leido?.version != v, let x = try? leerLienzo(ed.plano()) { leido = (v, x) }
            l = leido?.lienzo
        }
        let svg = SvgDeTinta.svg(l, marcos: ocultarMarcos ? [] : (marcos?.lista.map(\.rect) ?? []))
        guard forzar || svg != enviado else { return }
        enviado = svg
        let js = "(function(s){var d=document.getElementById('pixpin-tinta');if(!d){d=document.createElement('div');d.id='pixpin-tinta';"
            + "d.style.cssText='position:absolute;left:0;top:0;width:0;height:0;overflow:visible;pointer-events:none;z-index:2147483647';"
            + "document.documentElement.appendChild(d);}d.innerHTML=s;})(" + SvgDeTinta.cadenaJS(svg) + ")"
        web.evaluateJavaScript(js, completionHandler: nil)
    }

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
        if let a = marcoInicio, let b = marcoActual {
            CapaMarcosPDF.azul.setStroke()
            let c = NSBezierPath(rect: NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            c.lineWidth = 1 / escalaDeMarcos
            c.stroke()
        }
    }

    override func draw(_ sucio: NSRect) {
        // Quieto, todo esta en la pagina; aqui solo lo que se arrastra.
        guard pulsando || marcoInicio != nil else { return }
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
        pulsando = true
        if marcos?.activo == true { marcoInicio = convert(e.locationInWindow, from: nil); marcoActual = marcoInicio; return }
        puntero(.pulsar, e)
    }
    override func mouseDragged(with e: NSEvent) {
        if marcoInicio != nil { marcoActual = convert(e.locationInWindow, from: nil); needsDisplay = true; return }
        puntero(.mover, e)
    }
    override func mouseUp(with e: NSEvent) {
        defer {
            // Lo hecho pasa a la pagina y esta capa se vacia en el mismo
            // momento (sin parpadeo: primero la pagina).
            enviarALaPagina()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pulsando = false
                self?.needsDisplay = true
            }
        }
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


/// **La tinta como SVG** en px CSS del documento, para ponerla dentro de la
/// pagina: se desplaza y se acerca con ella, sin retraso.
@MainActor
enum SvgDeTinta {
    static func svg(_ l: LienzoLeido?, marcos: [CGRect]) -> String {
        var o = "<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1' style='position:absolute;left:0;top:0;overflow:visible'>"
        for f in l?.figuras ?? [] {
            switch f {
            case let .relleno(p, c):
                o += "<path d='\(d(p))' fill='\(color(c))' fill-opacity='\(c.a)' fill-rule='evenodd'/>"
            case let .tinta(p, c):
                o += "<path d='\(d(p))' fill='\(color(c))' fill-opacity='\(c.a)'/>"
            case let .linea(p, c, grosor, estilo):
                let g = Double(grosor)
                let raya = estilo == 1 ? " stroke-dasharray='\(g * 4) \(g * 3)'" : estilo == 2 ? " stroke-dasharray='0.01 \(g * 2.5)'"
                    : estilo == 3 ? " stroke-dasharray='\(g * 6) \(g * 2.5) 0.01 \(g * 2.5)'" : ""
                o += "<path d='\(d(p))' fill='none' stroke='\(color(c))' stroke-opacity='\(c.a)' stroke-width='\(g)' stroke-linecap='round' stroke-linejoin='round'\(raya)/>"
            case let .texto(t, origen, tam, _, familia, negrita, cursiva, c):
                o += "<text x='\(origen.x)' y='\(origen.y + tam)' font-size='\(tam)' font-family='\(xml(familia))' fill='\(color(c))'"
                    + (negrita ? " font-weight='bold'" : "") + (cursiva ? " font-style='italic'" : "") + ">\(xml(t))</text>"
            case let .rotulo(t, origen, tam, familia, c, _, _, centro, angulo):
                o += "<text x='\(origen.x)' y='\(origen.y + tam)' font-size='\(tam)' font-family='\(xml(familia))' fill='\(color(c))'"
                    + " transform='rotate(\(angulo * 180 / .pi) \(centro.x) \(centro.y))'>\(xml(t))</text>"
            case let .imagen(id, caja, opacidad, angulo, _, _):
                guard let img = GrafitosPintados.imagen(id), let png = PintorDeHojas.png(img) else { continue }
                o += "<image href='data:image/png;base64,\(png.base64EncodedString())' x='\(caja.minX)' y='\(caja.minY)' width='\(caja.width)' height='\(caja.height)' opacity='\(opacidad)'"
                    + " transform='rotate(\(angulo * 180 / .pi) \(caja.midX) \(caja.midY))' preserveAspectRatio='none'/>"
            case .velo:
                continue
            }
        }
        for (i, r) in marcos.enumerated() {
            o += "<rect x='\(r.minX)' y='\(r.minY)' width='\(r.width)' height='\(r.height)' fill='none' stroke='#0078D4' stroke-width='1.2' vector-effect='non-scaling-stroke'/>"
            o += "<rect x='\(r.minX)' y='\(r.minY)' width='16' height='16' fill='#0078D4'/>"
            o += "<text x='\(r.minX + 8)' y='\(r.minY + 12)' font-size='10' font-weight='600' font-family='-apple-system,sans-serif' fill='#fff' text-anchor='middle'>\(i + 1)</text>"
        }
        return o + "</svg>"
    }

    /// El trazado de un `CGPath` como `d` de SVG.
    static func d(_ p: CGPath) -> String {
        var s = ""
        func n(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }
        p.applyWithBlock { e in
            let q = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: s += "M\(n(q[0].x)) \(n(q[0].y))"
            case .addLineToPoint: s += "L\(n(q[0].x)) \(n(q[0].y))"
            case .addQuadCurveToPoint: s += "Q\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y))"
            case .addCurveToPoint: s += "C\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y)) \(n(q[2].x)) \(n(q[2].y))"
            case .closeSubpath: s += "Z"
            @unknown default: break
            }
        }
        return s
    }

    static func color(_ c: ColorLienzo) -> String {
        func h(_ v: CGFloat) -> String { String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    static func xml(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Una cadena de JavaScript con el texto dentro, sin romperse.
    static func cadenaJS(_ t: String) -> String {
        let datos = (try? JSONSerialization.data(withJSONObject: [t])) ?? Data("[\"\"]".utf8)
        let s = String(decoding: datos, as: UTF8.self)
        return String(s.dropFirst().dropLast())
    }
}
