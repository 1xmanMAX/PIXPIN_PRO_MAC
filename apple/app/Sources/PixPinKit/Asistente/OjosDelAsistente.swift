// **Los ojos del asistente** (E1, `asistente/ojos.rs` de Windows): el
// lienzo pintado para que el modelo lo vea. Rust copia la zona y la
// empaqueta como el `LienzoPlano` de siempre, con la rejilla y las
// etiquetas `#id` ya colocadas (`asistente/ojos.rs` del nucleo); aqui se
// pinta con **el mismo pintor del lienzo** (`PintorLienzo`, lo que ve el
// usuario) en un bitmap sin ventana y sale en PNG.
//
// Lo llama el hilo del turno (nunca el principal): un `CGContext` de mapa
// de bits no necesita ventana ni el hilo principal.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PixPinCore
import UniformTypeIdentifiers

extension ManosDelAsistente {
    func pintarVista(vista: VistaParaPintar) -> Data? {
        OjosDelAsistente.pintar(vista)
    }
}

enum OjosDelAsistente {
    /// Pinta la vista y la devuelve en PNG (`nil` si no se pudo).
    static func pintar(_ v: VistaParaPintar) -> Data? {
        let w = Int(v.ancho), h = Int(v.alto)
        guard w > 0, h > 0, w <= 8192, h <= 8192,
              let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // El eje Y hacia abajo, como el mundo del lienzo.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let leido = try? leerLienzo(v.plano)
        // Un papel transparente se ve blanco, como en el editor.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let fondo = leido?.fondo.cg, fondo.alpha > 0.01 {
            ctx.setFillColor(fondo)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        if let leido {
            var fotos: [UInt64: CGImage] = [:]
            for i in v.imagenes {
                if let f = foto(i.ruta) { fotos[i.idObjeto] = f }
            }
            let s = CGFloat(v.escala)
            let zona = CGRect(x: CGFloat(v.x0), y: CGFloat(v.y0), width: CGFloat(v.x1 - v.x0), height: CGFloat(v.y1 - v.y0))
            ctx.saveGState()
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -zona.minX, y: -zona.minY)
            PintorLienzo(lienzo: leido, imagen: { fotos[$0] }).pintar(en: ctx, limites: zona)
            ctx.restoreGState()
        }
        pintarMarcas(v, en: ctx)
        guard let imagen = ctx.makeImage() else { return nil }
        let datos = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(datos, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destino, imagen, nil)
        return CGImageDestinationFinalize(destino) ? datos as Data : nil
    }

    /// La rejilla (gris claro) con sus numeros y las etiquetas `#id` (sobre
    /// amarillo), en pixeles de la imagen (`pintar_marcas` de Windows).
    private static func pintarMarcas(_ v: VistaParaPintar, en ctx: CGContext) {
        ctx.setStrokeColor(CGColor(red: 0.45, green: 0.5, blue: 0.58, alpha: 0.28))
        ctx.setLineWidth(1)
        for r in v.rayas {
            ctx.move(to: CGPoint(x: CGFloat(r.x0), y: CGFloat(r.y0)))
            ctx.addLine(to: CGPoint(x: CGFloat(r.x1), y: CGFloat(r.y1)))
        }
        ctx.strokePath()
        guard !v.rotulos.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let letra = NSFont.systemFont(ofSize: 11)
        for r in v.rotulos {
            let color = r.etiqueta ? NSColor(white: 0.08, alpha: 1) : NSColor(red: 0.25, green: 0.28, blue: 0.33, alpha: 1)
            let fondo = r.etiqueta ? NSColor(red: 1, green: 0.86, blue: 0.25, alpha: 0.92) : NSColor(white: 1, alpha: 0.75)
            let texto = NSAttributedString(string: r.texto, attributes: [.font: letra, .foregroundColor: color])
            let tam = texto.size()
            let caja = CGRect(x: CGFloat(r.x) - 2, y: CGFloat(r.y) - 1, width: tam.width + 4, height: tam.height + 2)
            ctx.setFillColor(fondo.cgColor)
            ctx.fill(caja)
            texto.draw(at: CGPoint(x: CGFloat(r.x), y: CGFloat(r.y)))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Una foto del lienzo, reducida a lo que hace falta para la vista.
    private static func foto(_ ruta: String) -> CGImage? {
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opciones as CFDictionary)
    }
}
