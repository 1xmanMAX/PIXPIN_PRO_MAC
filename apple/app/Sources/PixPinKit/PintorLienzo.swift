// Pinta un `LienzoLeido` en un `CGContext` con el eje Y hacia abajo (el del
// mundo de Excalidraw y de una `NSView` con `isFlipped`).
//
// No guarda estado ni crea trazados: los `CGPath` ya vienen hechos del
// lector. Las imagenes se piden a `imagen(id)`, que la vista cachea.

import AppKit
import CoreGraphics
import PixPinCore

/// **Los mapas de grafito ya hechos imagen** (`grafito_plano.rs`): su id
/// lleva el bit alto y cambia cuando cambia el mapa, asi que se piden una
/// vez al nucleo.
enum GrafitosPintados {
    static let bit: UInt64 = 1 << 61
    nonisolated(unsafe) private static let cache: NSCache<NSNumber, CGImage> = {
        let c = NSCache<NSNumber, CGImage>()
        c.totalCostLimit = 128 << 20
        return c
    }()

    static func imagen(_ id: UInt64) -> CGImage? {
        guard id & bit != 0, id >> 62 == 0 else { return nil }
        let k = NSNumber(value: id)
        if let img = cache.object(forKey: k) { return img }
        guard let m = mapaDeGrafito(id: id), m.ancho > 0, m.alto > 0,
              m.rgba.count >= Int(m.ancho) * Int(m.alto) * 4,
              let prov = CGDataProvider(data: m.rgba as CFData),
              let img = CGImage(width: Int(m.ancho), height: Int(m.alto), bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: Int(m.ancho) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        cache.setObject(img, forKey: k, cost: m.rgba.count)
        return img
    }
}

public struct PintorLienzo {
    public var lienzo: LienzoLeido
    /// El bitmap de una imagen del lienzo, ya decodificado (o `nil`).
    public var imagen: (UInt64) -> CGImage?

    public init(lienzo: LienzoLeido, imagen: @escaping (UInt64) -> CGImage? = { _ in nil }) {
        self.lienzo = lienzo
        self.imagen = imagen
    }

    /// Pinta todo. `limites`: lo visible, en unidades del mundo (para el
    /// velo, que oscurece «todo lo demas»).
    public func pintar(en ctx: CGContext, limites: CGRect) {
        for figura in lienzo.figuras {
            switch figura {
            case let .relleno(path, color):
                ctx.addPath(path)
                ctx.setFillColor(color.cg)
                ctx.fillPath(using: .evenOdd)
            case let .tinta(path, color):
                ctx.addPath(path)
                ctx.setFillColor(color.cg)
                ctx.fillPath(using: .winding)
            case let .linea(path, color, grosor, estilo):
                ctx.saveGState()
                ctx.addPath(path)
                ctx.setStrokeColor(color.cg)
                ctx.setLineWidth(grosor)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                switch estilo {
                case 1: ctx.setLineDash(phase: 0, lengths: [grosor * 4, grosor * 3])
                case 2: ctx.setLineDash(phase: 0, lengths: [0.01, grosor * 2.5])
                case 3:
                    let hueco = grosor * 2 + 2
                    ctx.setLineDash(phase: 0, lengths: [grosor * 5 + 4, hueco, 0.01, hueco])
                default: break
                }
                ctx.strokePath()
                ctx.restoreGState()
            case let .velo(hueco, color):
                ctx.addRect(limites.insetBy(dx: -1, dy: -1))
                ctx.addPath(hueco)
                ctx.setFillColor(color.cg)
                ctx.fillPath(using: .evenOdd)
            case let .texto(texto, origen, tam, anchoMax, familia, negrita, cursiva, color):
                let atributos = PintorLienzo.atributos(tam: tam, familia: familia, negrita: negrita,
                                                       cursiva: cursiva, color: color)
                let ancho = anchoMax > 0 && anchoMax < 1e6 ? anchoMax : .greatestFiniteMagnitude
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                (texto as NSString).draw(
                    with: CGRect(x: origen.x, y: origen.y, width: ancho, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: atributos)
                NSGraphicsContext.restoreGraphicsState()
            case let .rotulo(texto, origen, tam, familia, color, halo, grosorHalo, centro, angulo):
                ctx.saveGState()
                ctx.translateBy(x: centro.x, y: centro.y)
                ctx.rotate(by: angulo)
                ctx.translateBy(x: -centro.x, y: -centro.y)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                var conHalo = PintorLienzo.atributos(tam: tam, familia: familia, negrita: false,
                                                    cursiva: false, color: halo)
                conHalo[.strokeColor] = NSColor(cgColor: halo.cg)
                conHalo[.strokeWidth] = grosorHalo / max(tam, 1) * 100
                (texto as NSString).draw(at: origen, withAttributes: conHalo)
                (texto as NSString).draw(at: origen, withAttributes: PintorLienzo.atributos(
                    tam: tam, familia: familia, negrita: false, cursiva: false, color: color))
                NSGraphicsContext.restoreGraphicsState()
                ctx.restoreGState()
            case let .imagen(id, caja, opacidad, angulo, recorte, natural):
                ctx.saveGState()
                ctx.setAlpha(opacidad)
                ctx.translateBy(x: caja.midX, y: caja.midY)
                ctx.rotate(by: angulo)
                var local = CGRect(x: -caja.width / 2, y: -caja.height / 2,
                                   width: caja.width, height: caja.height)
                // Lo de dentro de un mosaico o una lupa (`TapadoLienzo.swift`)
                // un pelo mas grande: el borde suavizado dejaba asomar la
                // banda maciza de debajo como un filo gris.
                if PintorDeTapados.esTapado(id) { local = local.insetBy(dx: -0.75, dy: -0.75) }
                if var bitmap = imagen(id) ?? GrafitosPintados.imagen(id) {
                    if let r = recorte, let nat = natural, nat.width > 0, nat.height > 0 {
                        // El recorte viene en las medidas naturales de la foto.
                        let sx = CGFloat(bitmap.width) / nat.width
                        let sy = CGFloat(bitmap.height) / nat.height
                        let px = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
                        bitmap = bitmap.cropping(to: px.integral) ?? bitmap
                    }
                    // En un contexto con Y hacia abajo, la foto se voltea.
                    ctx.translateBy(x: 0, y: local.maxY + local.minY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.interpolationQuality = .high
                    ctx.draw(bitmap, in: local)
                } else {
                    ctx.setFillColor(gray: 0.5, alpha: 0.15)
                    ctx.fill(local)
                }
                ctx.restoreGState()
            }
        }
    }

    static func atributos(tam: CGFloat, familia: String, negrita: Bool, cursiva: Bool,
                          color: ColorLienzo) -> [NSAttributedString.Key: Any] {
        var fuente = NSFont(name: familia, size: tam) ?? NSFont.systemFont(ofSize: tam)
        var rasgos: NSFontDescriptor.SymbolicTraits = []
        if negrita { rasgos.insert(.bold) }
        if cursiva { rasgos.insert(.italic) }
        if !rasgos.isEmpty,
           let conRasgos = NSFont(descriptor: fuente.fontDescriptor.withSymbolicTraits(rasgos), size: tam) {
            fuente = conRasgos
        }
        return [.font: fuente, .foregroundColor: NSColor(cgColor: color.cg) ?? .labelColor]
    }
}
