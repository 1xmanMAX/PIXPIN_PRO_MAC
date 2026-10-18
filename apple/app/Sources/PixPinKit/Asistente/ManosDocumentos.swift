// Las manos del asistente para las herramientas de documentos (E1,
// `asistente/documentos_acciones.rs`): lo que solo sabe hacer el Mac desde
// Swift. PDFKit mide y pinta las hojas de un PDF; Vision lee las palabras
// de una imagen con su sitio (para la tabla de una foto y para buscar y
// anotar en un PDF escaneado); exportar va por la hoja de compartir comun.
// Todo se llama desde el hilo del turno (nunca el principal).

import AppKit
import Foundation
import PDFKit
import PixPinCore
import Vision

extension ManosDelAsistente {
    func paginasDePdf(ruta: String) -> [MedidaPagina] {
        ManosDelAsistente.medidas(URL(fileURLWithPath: ruta))
    }

    func pintarPagina(ruta: String, pagina: UInt32, ancho: UInt32) -> Data? {
        ManosDelAsistente.pintar(URL(fileURLWithPath: ruta), pagina: Int(pagina), ancho: Int(ancho))
    }

    func palabrasDeImagen(imagen: Data) -> [PalabraLeida] {
        guard let img = NSImage(data: imagen)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return ManosDelAsistente.palabras(img)
    }

    func exportar(ruta: String, formato: String, carpeta: String) throws -> [String] {
        let url = URL(fileURLWithPath: ruta)
        guard FileManager.default.fileExists(atPath: ruta) else {
            throw ErrorNucleo.NoExiste(que: url.lastPathComponent)
        }
        let r: Result<[String], Error>? = esperarEnPrincipal(tope: 120) { responder in
            Task { @MainActor in
                let p = PrepararCompartir.deFicheros(titulo: url.deletingPathExtension().lastPathComponent, [url])
                do {
                    let hechos = try await p.generar(formato.lowercased(), claves: p.piezas.map(\.pagina.clave),
                                                     en: URL(fileURLWithPath: carpeta))
                    responder(.success(hechos.map(\.path)))
                } catch {
                    responder(.failure(error))
                }
            }
        }
        switch r {
        case let .success(v): return v
        case let .failure(e): throw ErrorNucleo.Argumento(detalle: "\(e)")
        case .none: throw ErrorNucleo.Argumento(detalle: "exportar tardó demasiado")
        }
    }

    /// Espera en este hilo a lo que haga `trabajo` en el principal.
    private func esperarEnPrincipal<T: Sendable>(tope: TimeInterval,
                                                 _ trabajo: @escaping @MainActor (@escaping @Sendable (T) -> Void) -> Void) -> T? {
        let caja = CajaDeEspera<T>()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                trabajo { v in
                    caja.valor = v
                    caja.s.signal()
                }
            }
        }
        let limite = Date().addingTimeInterval(tope)
        while caja.s.wait(timeout: .now() + 0.1) == .timedOut {
            if corte.cortado() || Date() > limite { return nil }
        }
        return caja.valor
    }

    // MARK: Lo puro (y probado)

    /// Lo que mide cada hoja: la caja que se ve, ya girada (como el lector).
    static func medidas(_ url: URL) -> [MedidaPagina] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0 ..< doc.pageCount).compactMap { i in
            guard let p = doc.page(at: i) else { return nil }
            let c = p.bounds(for: .cropBox)
            let girada = abs(p.rotation) % 180 == 90
            return MedidaPagina(ancho: Float(girada ? c.height : c.width), alto: Float(girada ? c.width : c.height))
        }
    }

    /// La hoja `pagina` pintada a `ancho` pixeles, en PNG, sobre blanco.
    static func pintar(_ url: URL, pagina: Int, ancho: Int) -> Data? {
        guard let doc = PDFDocument(url: url), let p = doc.page(at: pagina) else { return nil }
        let c = p.bounds(for: .cropBox)
        let girada = abs(p.rotation) % 180 == 90
        let (w, h) = girada ? (c.height, c.width) : (c.width, c.height)
        guard w > 0, h > 0 else { return nil }
        let escala = CGFloat(ancho) / w
        let img = p.thumbnail(of: CGSize(width: w * escala, height: h * escala), for: .cropBox)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// **Las palabras de una imagen** con su caja en pixeles (y abajo), en
    /// orden de lectura; cada renglon de Vision, su numero.
    static func palabras(_ img: CGImage) -> [PalabraLeida] {
        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = .accurate
        peticion.recognitionLanguages = ["es-ES", "en-US"]
        peticion.usesLanguageCorrection = true
        let manejador = VNImageRequestHandler(cgImage: img, options: [:])
        guard (try? manejador.perform([peticion])) != nil else { return [] }
        let (w, h) = (CGFloat(img.width), CGFloat(img.height))
        var v: [PalabraLeida] = []
        let lineas = (peticion.results ?? []).sorted {
            // De arriba abajo (Vision mide desde abajo), y de izquierda a derecha.
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        for (n, linea) in lineas.enumerated() {
            guard let c = linea.topCandidates(1).first else { continue }
            let s = c.string
            var i = s.startIndex
            while i < s.endIndex {
                guard let inicio = s[i...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let fin = s[inicio...].firstIndex(where: \.isWhitespace) ?? s.endIndex
                let caja = (try? c.boundingBox(for: inicio ..< fin))?.boundingBox ?? linea.boundingBox
                v.append(PalabraLeida(texto: String(s[inicio ..< fin]),
                                      x: Float(caja.minX * w), y: Float((1 - caja.maxY) * h),
                                      ancho: Float(caja.width * w), alto: Float(caja.height * h),
                                      renglon: UInt32(n)))
                i = fin
            }
        }
        return v
    }
}
