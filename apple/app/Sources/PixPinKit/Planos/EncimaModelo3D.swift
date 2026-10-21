// **Lo de encima del modelo 3D** (como `ventana3d.rs` de Windows):
// - el punto de giro, mientras se gira arrastrando;
// - la caja de seccion: sus aristas y un asa por cara (un punto con sus
//   flechas) que se arrastra para mover esa cara;
// - la tinta de cada marcador (`anot-<uid>-m<id>`, §3.4 del manual de
//   Windows): en la pantalla desde el centro, en milesimas de su alto, y
//   solo con la vista de su marcador.

import AppKit
import PixPinCore

extension VistaModeloMetal {
    /// Un punto del modelo en la vista (puntos, y hacia arriba); `nil` si
    /// queda detras del ojo.
    func aPantalla(_ p: Punto3d) -> CGPoint? {
        let m = camaraMatriz(camara: camara, ancho: ancho, alto: alto, radio: radio)
        guard m.count == 16 else { return nil }
        let v = [p.x, p.y, p.z, 1.0]
        var c = [0.0, 0.0, 0.0, 0.0]
        for i in 0 ..< 4 { for j in 0 ..< 4 { c[i] += Double(m[j * 4 + i]) * v[j] } }
        guard c[3] > 1e-9 else { return nil }
        return CGPoint(x: (c[0] / c[3] + 1) / 2 * bounds.width, y: (c[1] / c[3] + 1) / 2 * bounds.height)
    }

    /// Las seis caras de la caja de seccion: su centro, su eje y si es la
    /// de abajo de ese eje.
    func carasDelCorte() -> [(centro: Punto3d, eje: Int, minimo: Bool)] {
        guard let k = visor.cajaDeCorte else { return [] }
        let cx = Double(k.x0 + k.x1) / 2, cy = Double(k.y0 + k.y1) / 2, cz = Double(k.z0 + k.z1) / 2
        return [
            (Punto3d(x: Double(k.x0), y: cy, z: cz), 0, true), (Punto3d(x: cx, y: Double(k.y0), z: cz), 1, true),
            (Punto3d(x: cx, y: cy, z: Double(k.z0)), 2, true), (Punto3d(x: Double(k.x1), y: cy, z: cz), 0, false),
            (Punto3d(x: cx, y: Double(k.y1), z: cz), 1, false), (Punto3d(x: cx, y: cy, z: Double(k.z1)), 2, false),
        ]
    }

    /// Lo que mide la caja del modelo en el eje `e`.
    private func largo(_ e: Int) -> Double {
        guard let c = visor.datos?.resumen.caja else { return 1 }
        return max([Double(c.x1 - c.x0), Double(c.y1 - c.y0), Double(c.z1 - c.z0)][e], 1e-6)
    }

    /// La flecha de una cara en la pantalla: hacia donde crece su eje
    /// (puntos por unidad del modelo).
    func flecha(_ cara: (centro: Punto3d, eje: Int, minimo: Bool)) -> CGVector? {
        let l = largo(cara.eje) * 0.1
        var q = cara.centro
        switch cara.eje { case 0: q.x += l; case 1: q.y += l; default: q.z += l }
        guard let a = aPantalla(cara.centro), let b = aPantalla(q) else { return nil }
        return CGVector(dx: (b.x - a.x) / l, dy: (b.y - a.y) / l)
    }

    /// El asa bajo `p` (su numero de cara), si la caja esta puesta.
    func asaBajo(_ p: CGPoint) -> Int? {
        for (i, c) in carasDelCorte().enumerated() {
            if let q = aPantalla(c.centro), hypot(q.x - p.x, q.y - p.y) < 11 { return i }
        }
        return nil
    }

    /// Arrastrando un asa: su cara sigue al raton a lo largo de su eje.
    func moverAsa(_ a: (cara: Int, p: CGPoint, corte: [Double]), hasta p: CGPoint) {
        let caras = carasDelCorte()
        guard a.cara < caras.count, let f = flecha(caras[a.cara]) else { return }
        let n2 = f.dx * f.dx + f.dy * f.dy
        guard n2 > 1e-12 else { return }
        let unidades = (Double(p.x - a.p.x) * f.dx + Double(p.y - a.p.y) * f.dy) / n2
        let e = caras[a.cara].eje
        let delta = unidades / largo(e)
        var c = a.corte
        let (lo, hi) = (min(c[e], c[e + 3]), max(c[e], c[e + 3]))
        if caras[a.cara].minimo {
            c[e] = min(max(lo + delta, 0), hi - 0.01); c[e + 3] = hi
        } else {
            c[e + 3] = max(min(hi + delta, 1), lo + 0.01); c[e] = lo
        }
        visor.corte = c
    }
}

/// Pinta el punto de giro y la caja de seccion con sus asas. No recibe el
/// raton: lo atiende la vista de Metal.
final class CapaEncimaModelo: NSView {
    weak var vista: VistaModeloMetal?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static let azul = NSColor(srgbRed: 0, green: 0x78 / 255.0, blue: 0xD4 / 255.0, alpha: 1)

    override func draw(_ sucio: NSRect) {
        guard let v = vista, let ctx = NSGraphicsContext.current?.cgContext else { return }
        if v.visor.conCorte, let k = v.visor.cajaDeCorte { caja(v, k, ctx) }
        if let p = v.pivoteVisible, let q = v.aPantalla(p) {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12))
            ctx.setFillColor(NSColor.systemOrange.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8))
        }
    }

    private func caja(_ v: VistaModeloMetal, _ k: Caja3d, _ ctx: CGContext) {
        let xs = [Double(k.x0), Double(k.x1)], ys = [Double(k.y0), Double(k.y1)], zs = [Double(k.z0), Double(k.z1)]
        func p(_ i: Int, _ j: Int, _ l: Int) -> CGPoint? { v.aPantalla(Punto3d(x: xs[i], y: ys[j], z: zs[l])) }
        var aristas: [(CGPoint?, CGPoint?)] = []
        for a in 0 ..< 2 { for b in 0 ..< 2 {
            aristas.append((p(0, a, b), p(1, a, b)))
            aristas.append((p(a, 0, b), p(a, 1, b)))
            aristas.append((p(a, b, 0), p(a, b, 1)))
        } }
        ctx.setStrokeColor(CapaEncimaModelo.azul.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.2)
        for case let (a?, b?) in aristas { ctx.move(to: a); ctx.addLine(to: b) }
        ctx.strokePath()
        // Un asa por cara: el punto y sus dos flechas a lo largo del eje.
        for c in v.carasDelCorte() {
            guard let q = v.aPantalla(c.centro), let f = v.flecha(c) else { continue }
            let n = max(hypot(f.dx, f.dy), 1e-9)
            let d = CGVector(dx: f.dx / n, dy: f.dy / n)
            ctx.setStrokeColor(CapaEncimaModelo.azul.cgColor)
            ctx.setLineWidth(1.5)
            for s in [-1.0, 1.0] {
                let punta = CGPoint(x: q.x + d.dx * 18 * s, y: q.y + d.dy * 18 * s)
                ctx.move(to: CGPoint(x: q.x + d.dx * 8 * s, y: q.y + d.dy * 8 * s)); ctx.addLine(to: punta)
                let ax = -d.dy, ay = d.dx
                ctx.move(to: punta)
                ctx.addLine(to: CGPoint(x: punta.x - d.dx * 5 * s + ax * 4, y: punta.y - d.dy * 5 * s + ay * 4))
                ctx.move(to: punta)
                ctx.addLine(to: CGPoint(x: punta.x - d.dx * 5 * s - ax * 4, y: punta.y - d.dy * 5 * s - ay * 4))
            }
            ctx.strokePath()
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12))
            ctx.setFillColor(CapaEncimaModelo.azul.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - 4.5, y: q.y - 4.5, width: 9, height: 9))
        }
    }
}

/// **La tinta de un marcador 3D**: sus coordenadas son las de Windows (desde
/// el centro, milesimas del alto, y hacia abajo), asi que los limites de la
/// vista se ponen a esa medida al cambiar de tamano.
final class CapaTintaMarcador3D: CapaTintaDoc {
    /// El marcador cuya tinta se ve.
    var marcador: String?

    override func setFrameSize(_ n: NSSize) {
        super.setFrameSize(n)
        let h = max(n.height, 1)
        bounds = NSRect(x: -500 * n.width / h, y: -500, width: 1000 * n.width / h, height: 1000)
    }
}

extension VisorModelo3D {
    /// El marcador que es la vista de ahora, si lo hay.
    func marcadorDeAhora() -> String? {
        guard let c = vista?.camara else { return nil }
        for m in marcadores.del3d {
            guard let o = (m.estado["objetivo"] as? [NSNumber])?.map(\.doubleValue), o.count == 3 else { continue }
            func n(_ k: String) -> Double { (m.estado[k] as? NSNumber)?.doubleValue ?? 0 }
            let cm = Camara3d(objetivo: Punto3d(x: o[0], y: o[1], z: o[2]), rumbo: n("rumbo"), altura: n("altura"), dist: n("dist"))
            if Marcos3D.coincide(c, cm) { return m.id }
        }
        return nil
    }

    /// Tras mover la camara: la tinta del marcador de ahora (o ninguna);
    /// saliendo de su vista se deja de anotar.
    func alMoverLaCamara() {
        guard let v = vista else { return }
        let m = marcadorDeAhora()
        if m != v.tinta.marcador {
            v.tinta.marcador = m
            v.tinta.editor = nil
            if let m, let nucleo = nucleoDeMarcadores {
                let r = nucleo.rutaDeTintaDeMarcador3d(modelo: ruta, id: m)
                let hay = FileManager.default.fileExists(atPath: r) || FileManager.default.fileExists(atPath: r + ".gz")
                if hay || riel.anotando { v.tinta.editor = try? EditorLienzo.deFichero(ruta: r, crear: true) }
            }
            if m == nil, riel.anotando { riel.herramienta = "leer"; v.tinta.anotando = false }
        }
        v.tinta.isHidden = m == nil
        v.tinta.needsDisplay = true
    }

    /// El lapiz del riel (A): anota sobre la vista de ahora. Si no es la de
    /// un marcador, se pone uno (lo anotado va siempre con su vista).
    func alternarAnotar() {
        guard nucleoDeMarcadores != nil, let v = vista else { return NSSound.beep() }
        if riel.anotando {
            riel.herramienta = "leer"
            v.tinta.anotando = false
            v.tinta.guardarLuego()
            return
        }
        if marcadosDeAhoraFalta() { ponerMarcador() }
        riel.herramienta = "lapiz"
        v.tinta.marcador = nil // que se vuelva a abrir, ya para escribir
        alMoverLaCamara()
        v.tinta.anotando = v.tinta.editor != nil
    }

    private func marcadosDeAhoraFalta() -> Bool { marcadorDeAhora() == nil }
}
