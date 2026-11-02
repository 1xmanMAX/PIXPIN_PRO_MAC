// **La tinta de una hoja de calculo en su celda** y **marcar celdas
// enteras** (Windows 100857f2, `visor_hoja/{marcar,capa}.rs`).
//
// La tinta de la hoja de un libro (`anot-<uid>-h<i>`) va en las unidades de
// su capa: pixeles de Excel al 100 % con la rejilla del propio libro
// (`rejillaDelLibro`, `anotar_inteligente::rejilla_de_la_capa` de Windows),
// la misma en todos los aparatos. Cada visor lleva cada punto a la misma
// fraccion de la misma celda de su rejilla: aqui, la del `NSTableView`
// (otra columna de numeros, otros anchos, otro alto de fila). Asi lo
// anotado en Windows o en el movil cae en su celda en el Mac, y al reves.
//
// Las marcas de celdas son dibujo normal de esa capa (el grupo
// `marca-texto-<ms>`); sus cajas las da el nucleo
// (`cajasDeCeldasMarcadas`): resaltar y tapar cubren el rango, las rayas
// van fila a fila.

import AppKit
import CoreGraphics
import PixPinCore

/// **Una correspondencia por tramos** entre dos rejillas de bordes
/// crecientes (`a` y `b`, con lo que mide cada tramo mas alla de los
/// medidos): el punto que esta a una fraccion de su tramo en una cae a la
/// misma fraccion del mismo tramo en la otra.
struct TramosDeRejilla {
    var a: [CGFloat]
    var defectoA: CGFloat
    var b: [CGFloat]
    var defectoB: CGFloat

    /// El borde `i` (antes del primero y mas alla del ultimo, a `defecto`).
    static func borde(_ v: [CGFloat], _ defecto: CGFloat, _ i: Int) -> CGFloat {
        guard let primero = v.first, let ultimo = v.last else { return CGFloat(i) * defecto }
        if i < 0 { return primero + CGFloat(i) * defecto }
        if i < v.count { return v[i] }
        return ultimo + CGFloat(i - (v.count - 1)) * defecto
    }

    /// El tramo de `x`: el `i` con `borde(i) <= x < borde(i + 1)` (en uno
    /// vacio, el de despues).
    static func tramo(_ v: [CGFloat], _ defecto: CGFloat, _ x: CGFloat) -> Int {
        guard let primero = v.first, let ultimo = v.last else {
            return defecto > 0 ? Int((x / defecto).rounded(.down)) : 0
        }
        if x < primero {
            return defecto > 0 ? -1 - Int(((primero - x) / defecto).rounded(.down)) : -1
        }
        if x >= ultimo {
            return v.count - 1 + (defecto > 0 ? Int(((x - ultimo) / defecto).rounded(.down)) : 0)
        }
        var bajo = 0, alto = v.count - 1
        while bajo < alto {
            let m = (bajo + alto + 1) / 2
            if v[m] <= x { bajo = m } else { alto = m - 1 }
        }
        return bajo
    }

    private static func llevar(_ x: CGFloat, _ de: [CGFloat], _ dd: CGFloat, _ a: [CGFloat], _ ad: CGFloat) -> CGFloat {
        let i = tramo(de, dd, x)
        let x0 = borde(de, dd, i), x1 = borde(de, dd, i + 1)
        let f = x1 > x0 ? (x - x0) / (x1 - x0) : 0
        let y0 = borde(a, ad, i), y1 = borde(a, ad, i + 1)
        return y0 + f * (y1 - y0)
    }

    /// De `a` a `b`.
    func ir(_ x: CGFloat) -> CGFloat { TramosDeRejilla.llevar(x, a, defectoA, b, defectoB) }

    /// De `b` a `a`.
    func volver(_ x: CGFloat) -> CGFloat { TramosDeRejilla.llevar(x, b, defectoB, a, defectoA) }
}

/// **De la capa de la hoja a la rejilla que se ve** y al reves.
struct MapaCeldasHoja {
    let columnas: TramosDeRejilla
    let filas: TramosDeRejilla

    /// `capa`: la rejilla de la tinta (la del libro); `xsVista`: el borde
    /// izquierdo de cada columna de datos en la vista y el derecho de la
    /// ultima; `altoFila`: el de cada fila de la vista (la primera en 0).
    init(capa: RejillaTinta, xsVista: [CGFloat], altoFila: CGFloat) {
        let ancho = xsVista.count > 1 ? (xsVista[xsVista.count - 1] - xsVista[xsVista.count - 2]) : 90
        columnas = TramosDeRejilla(a: capa.xs.map { CGFloat($0) }, defectoA: CGFloat(capa.anchoDefecto),
                                   b: xsVista, defectoB: max(ancho, 1))
        filas = TramosDeRejilla(a: capa.ys.map { CGFloat($0) }, defectoA: CGFloat(capa.altoDefecto),
                                b: [0], defectoB: max(altoFila, 1))
    }

    func aVista(_ p: CGPoint) -> CGPoint { CGPoint(x: columnas.ir(p.x), y: filas.ir(p.y)) }
    func aCapa(_ p: CGPoint) -> CGPoint { CGPoint(x: columnas.volver(p.x), y: filas.volver(p.y)) }

    /// Un trazado con cada punto llevado por `f`.
    static func camino(_ c: CGPath, _ f: @escaping (CGPoint) -> CGPoint) -> CGPath {
        let m = CGMutablePath()
        c.applyWithBlock { e in
            let p = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: m.move(to: f(p[0]))
            case .addLineToPoint: m.addLine(to: f(p[0]))
            case .addQuadCurveToPoint: m.addQuadCurve(to: f(p[1]), control: f(p[0]))
            case .addCurveToPoint: m.addCurve(to: f(p[2]), control1: f(p[0]), control2: f(p[1]))
            case .closeSubpath: m.closeSubpath()
            @unknown default: break
            }
        }
        return m
    }

    private static func caja(_ r: CGRect, _ f: @escaping (CGPoint) -> CGPoint) -> CGRect {
        let a = f(CGPoint(x: r.minX, y: r.minY)), b = f(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// **El lienzo de la capa en la vista**: cada figura con sus puntos en su
    /// celda (los textos y las imagenes, por su esquina).
    func enVista(_ l: LienzoLeido) -> LienzoLeido {
        let f: (CGPoint) -> CGPoint = { [self] p in aVista(p) }
        var v = l
        v.caja = l.caja.map { MapaCeldasHoja.caja($0, f) }
        v.figuras = l.figuras.map { figura -> FiguraLienzo in
            switch figura {
            case let .relleno(c, color): return .relleno(MapaCeldasHoja.camino(c, f), color)
            case let .tinta(c, color): return .tinta(MapaCeldasHoja.camino(c, f), color)
            case let .linea(c, color, grosor, estilo):
                return .linea(MapaCeldasHoja.camino(c, f), color, grosor: grosor, estilo: estilo)
            case let .velo(hueco, color): return .velo(hueco: MapaCeldasHoja.camino(hueco, f), color)
            case let .texto(t, origen, tam, anchoMax, familia, negrita, cursiva, color):
                return .texto(t, origen: f(origen), tam: tam, anchoMax: anchoMax, familia: familia,
                              negrita: negrita, cursiva: cursiva, color)
            case let .rotulo(t, origen, tam, familia, color, halo, grosorHalo, centro, angulo):
                return .rotulo(t, origen: f(origen), tam: tam, familia: familia, color, halo: halo,
                               grosorHalo: grosorHalo, centro: f(centro), angulo: angulo)
            case let .imagen(id, caja, opacidad, angulo, recorte, natural):
                return .imagen(id: id, caja: MapaCeldasHoja.caja(caja, f), opacidad: opacidad, angulo: angulo,
                               recorte: recorte, natural: natural)
            }
        }
        return v
    }
}
