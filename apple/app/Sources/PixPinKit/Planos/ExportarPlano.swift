// **Exportar el plano** (⌘E, `plano_cad::exportar` de Windows): la hoja de
// compartir comun con los formatos del plano.
//
// - **HTML**: la pagina de Windows (`Plano.paginaWeb`, `pixpin_cad::web`):
//   se mueve y acerca como el visor, con las capas como se ven ahora, los
//   grosores, las imagenes, las cotas, los marcos y lo anotado.
// - **PDF**: en vectores, una hoja por marco para imprimir (sin marcos, el
//   plano entero), con las cotas y lo anotado encima; la hoja, como la de
//   Windows: el lado largo de un A3 con su margen.
// - **PNG** y **JPG**: el plano pintado como al imprimir, 3200 pixeles por
//   el lado largo, con lo anotado.
// - **DXF** (de un DWG): lo escribe Rust (`opencadcodec`).
// - **Original**: el fichero tal cual.
//
// El PDF y las imagenes salen del pintor de papel (`PapelPlano`), que lee
// los buferes que ya estan en la tarjeta: no se vuelve a leer el plano.

import AppKit
import PixPinCore
import UniformTypeIdentifiers

@MainActor
enum ExportarPlano {
    /// El lado largo de una hoja del PDF: un A3 (puntos), y su margen.
    static let ladoPdf: CGFloat = 1190.55
    static let margenPdf: CGFloat = 28
    /// El lado largo de la imagen, en pixeles, y su margen.
    static let ladoImagen: CGFloat = 3200
    static let margenImagen: CGFloat = 24

    /// **Abre la hoja de compartir** con los formatos del plano.
    static func abrir(_ visor: VisorPlano) {
        guard let p = preparar(visor) else { return NSSound.beep() }
        HojaCompartir.abrir(.preparado(p), almacen: nil)
    }

    /// Lo que ofrece la hoja (`exportable` de Windows).
    static func preparar(_ visor: VisorPlano) -> PreparadoCompartir? {
        guard let d = visor.datos else { return nil }
        let p = PreparadoCompartir(titulo: visor.titulo)
        let base = p.base
        let plano = d.plano
        let anotado = visor.anotado
        let claro = !visor.oscuro
        let encima = visor.encimaParaPapel()
        let visibles = visor.visibles
        let marcos = anotado.marcos
        let util = d.resumen.cajaUtil
        p.extras.append(ExtraCompartir(
            formato: FormatoCompartir(id: IdFormato.web, nombre: "HTML", cuantas: .ninguna, simbolo: "globe"),
            que: .escrito(nombre: base + ".html") {
                let html = try await Task.detached(priority: .userInitiated) {
                    try plano.paginaWeb(anotado: anotado, claro: claro)
                }.value
                return Data(html.utf8)
            }))
        p.extras.append(ExtraCompartir(
            formato: FormatoCompartir(id: IdFormato.pdf, nombre: "PDF", cuantas: .ninguna, simbolo: "doc.richtext"),
            que: .escrito(nombre: base + ".pdf") {
                guard let datos = pdf(d, visibles: visibles, marcos: marcos, util: util, encima: encima) else {
                    throw ErrorCompartir.noSePudo("PDF")
                }
                return datos
            }))
        for (id, nombre, simbolo) in [(IdFormato.png, "PNG", "photo"), (IdFormato.jpg, "JPG", "photo.fill")] {
            p.extras.append(ExtraCompartir(
                formato: FormatoCompartir(id: id, nombre: nombre, cuantas: .ninguna, simbolo: simbolo),
                que: .escrito(nombre: base + "." + id) {
                    guard let img = imagen(d, visibles: visibles, region: util, encima: encima),
                          let datos = PreparadoCompartir.codificar(img, id == IdFormato.jpg ? .jpeg : .png) else {
                        throw ErrorCompartir.noSePudo(nombre)
                    }
                    return datos
                }))
        }
        if plano.esDwg() {
            p.extras.append(ExtraCompartir(
                formato: FormatoCompartir(id: "dxf", nombre: "DXF", cuantas: .ninguna, simbolo: "square.on.square.dashed"),
                que: .lote { carpeta in
                    let salida = carpeta.appendingPathComponent(base + ".dxf")
                    try await Task.detached(priority: .userInitiated) { try plano.exportarDxf(salida: salida.path) }.value
                    return [salida]
                }))
        }
        PrepararCompartir.anadirOriginales(p, [URL(fileURLWithPath: visor.ruta)])
        return p
    }

    /// **El PDF del plano**: una hoja por marco (sin marcos, `util`), cada
    /// una del tamano de su marco con el lado largo de un A3.
    static func pdf(_ d: PlanoEnTarjeta, visibles: Set<UInt32>, marcos: [CajaPlano], util: CajaPlano,
                    encima: EncimaPapel?) -> Data? {
        let hojas = (marcos.isEmpty ? [util] : marcos).filter { $0.x1 > $0.x0 && $0.y1 > $0.y0 }
        guard !hojas.isEmpty else { return nil }
        let datos = NSMutableData()
        guard let consumidor = CGDataConsumer(data: datos as CFMutableData) else { return nil }
        var caja = CGRect(x: 0, y: 0, width: ladoPdf, height: ladoPdf)
        guard let ctx = CGContext(consumer: consumidor, mediaBox: &caja, nil) else { return nil }
        for m in hojas {
            let tam = tamanoDeHoja(m, lado: ladoPdf, margen: margenPdf)
            var media = CGRect(origin: .zero, size: tam)
            ctx.beginPage(mediaBox: &media)
            PapelPlano.pintar(d, visibles: visibles, region: m, encima: encima, en: ctx,
                              destino: media.insetBy(dx: margenPdf, dy: margenPdf))
            ctx.endPage()
        }
        ctx.closePDF()
        return datos as Data
    }

    /// **El plano como imagen**, sobre blanco.
    static func imagen(_ d: PlanoEnTarjeta, visibles: Set<UInt32>, region: CajaPlano, encima: EncimaPapel?) -> CGImage? {
        guard region.x1 > region.x0, region.y1 > region.y0 else { return nil }
        let tam = tamanoDeHoja(region, lado: ladoImagen, margen: margenImagen)
        let w = Int(tam.width.rounded()), h = Int(tam.height.rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        PapelPlano.pintar(d, visibles: visibles, region: region, encima: encima, en: ctx,
                          destino: CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: margenImagen, dy: margenImagen))
        return ctx.makeImage()
    }

    /// El tamano de la hoja de `region` con `lado` de lado largo, margen
    /// incluido (`HojaPdf::de` de Windows).
    static func tamanoDeHoja(_ region: CajaPlano, lado: CGFloat, margen: CGFloat) -> CGSize {
        let mw = max(region.x1 - region.x0, 1e-9), mh = max(region.y1 - region.y0, 1e-9)
        let s = Double(lado - 2 * margen) / max(mw, mh)
        return CGSize(width: mw * s + 2 * Double(margen), height: mh * s + 2 * Double(margen))
    }
}
