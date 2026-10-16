// **El fondo fijo del lienzo**: la imagen de un pin o una foto, o una pagina
// de un PDF (`fondo_lienzo.rs` de Windows, D132-D143).
//
// No es un elemento de la escena: no se elige, no se mueve ni se borra. Vive
// en el mundo en (0, 0)-(ancho, alto), las coordenadas en las que ya estan
// las anotaciones:
//
// - una imagen mide lo que sus pixeles;
// - una pagina de PDF mide 1400 de ancho (`ANCHO_PAPEL_PDF`, el
//   `PdfDoc.PAGE_WIDTH` del movil, que la pone en (0, 0)): con otro numero lo
//   dibujado en el movil caeria corrido aqui y al reves.
//
// Lo que el Mac hace distinto: la pagina se pinta vectorial con
// `CGContext.drawPDFPage` cada vez y no en teselas desde otro hilo
// (`MosaicoDePdf`): CoreGraphics la rasteriza a la densidad del zoom, asi
// que nunca se ve borrosa al acercarse.

import AppKit
import ImageIO
import PixPinCore

/// De donde sale el fondo (`Fuente` de Windows).
public enum FuenteFondoLienzo: Equatable {
    /// Una imagen en un fichero: la de un pin o una foto.
    case imagen(URL)
    /// La pagina `pagina` (desde 0) de un PDF.
    case paginaPDF(URL, pagina: Int)
    /// Una imagen que ya esta en memoria y no tiene fichero (el recorte de
    /// la captura que se anota).
    case enMemoria
}

/// El fondo ya leido.
@MainActor
public final class FondoLienzo {
    /// Lo que mide una pagina de PDF de ancho en el lienzo.
    public static let anchoPapelPDF: CGFloat = 1400

    public let fuente: FuenteFondoLienzo
    public let tamano: CGSize
    private let imagen: CGImage?
    private let pagina: CGPDFPage?

    /// Lee el fondo. `nil` si el fichero no se puede leer.
    public init?(_ fuente: FuenteFondoLienzo) {
        self.fuente = fuente
        switch fuente {
        case let .imagen(url):
            guard let origen = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(origen, 0, nil) else { return nil }
            imagen = img
            pagina = nil
            tamano = CGSize(width: img.width, height: img.height)
        case let .paginaPDF(url, n):
            guard let doc = CGPDFDocument(url as CFURL), let p = doc.page(at: n + 1) else { return nil }
            let natural = FondoLienzo.tamanoNatural(p)
            guard natural.width > 0, natural.height > 0 else { return nil }
            imagen = nil
            pagina = p
            tamano = CGSize(width: FondoLienzo.anchoPapelPDF,
                            height: FondoLienzo.anchoPapelPDF * natural.height / natural.width)
        case .enMemoria:
            // No hay fichero que leer: se crea con `init(imagen:tamano:)`.
            return nil
        }
    }

    /// Lo que mide la pagina en puntos, con su giro (girada, el ancho es su
    /// alto).
    static func tamanoNatural(_ p: CGPDFPage) -> CGSize {
        let caja = p.getBoxRect(.cropBox)
        return abs(p.rotationAngle) % 180 == 90 ? CGSize(width: caja.height, height: caja.width) : caja.size
    }

    /// **Una imagen en memoria** estirada a `tamano` (en unidades del
    /// mundo): el anotador de la captura la pone a su tamano en PUNTOS, con
    /// los pixeles de la pantalla (los grosores salen como en pantalla y al
    /// exportar a la escala de la foto no se pierde un pixel).
    public init(imagen: CGImage, tamano: CGSize) {
        fuente = .enMemoria
        self.imagen = imagen
        pagina = nil
        self.tamano = tamano
    }

    /// La caja que ocupa en el mundo.
    public var caja: CGRect { CGRect(origin: .zero, size: tamano) }

    /// **Lo pinta** en `ctx`, que ya tiene la transformada del mundo (Y
    /// hacia abajo).
    public func pintar(en ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: caja)
        if let imagen {
            ctx.translateBy(x: 0, y: tamano.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(imagen, in: CGRect(origin: .zero, size: tamano))
        } else if let pagina {
            // El PDF tiene la Y hacia arriba: se le da la vuelta y se encaja
            // la pagina (con su giro) en la caja.
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(caja)
            ctx.translateBy(x: 0, y: tamano.height)
            ctx.scaleBy(x: 1, y: -1)
            // `getDrawingTransform` solo encoge: se le da la pagina a su
            // tamano (con su giro) y se agranda aparte.
            let natural = FondoLienzo.tamanoNatural(pagina)
            ctx.scaleBy(x: tamano.width / natural.width, y: tamano.height / natural.height)
            ctx.concatenate(pagina.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: natural),
                                                       rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(pagina)
        }
        ctx.restoreGState()
    }

    /// Su PNG, para que vaya dentro del SVG exportado (como mucho 4096 de
    /// lado).
    func png() -> Data? {
        let k = min(1, 4096 / max(tamano.width, tamano.height))
        let w = max(1, Int(tamano.width * k)), h = max(1, Int(tamano.height * k))
        guard let ctx = PintorDeTapados.mapa(w, h) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: k, y: -k)
        pintar(en: ctx)
        return ctx.makeImage().flatMap(PintorDeHojas.png)
    }

    /// Donde se mira al abrir (`encuadre_inicial` de Windows): el fondo
    /// entero con 48 de aire.
    static let margenEncuadre: CGFloat = 48
}
