// **Escuchar un PDF** (o un Word o un PowerPoint paginados) en el propio
// lector: es `lector_pdf/voz.rs` de Windows.
//
// El texto de cada hoja sale de PDFKit (`PDFPage.string`) y cada «parrafo»
// de la voz es un trozo de frases de una hoja (`VozAlta.cortes`, como mucho
// 320 letras): el texto de un PDF llega en renglones sin parrafos, y por
// frases se resalta un trozo que se puede seguir con la vista. Lo que suena
// va en ambar sobre la hoja y la palabra que se dice, mas fuerte; la vista
// lo sigue si se estaba mirando; y el verde (🟢 en los marcadores del
// documento, los que viajan) se mueve con lo que se va oyendo, asi la
// proxima vez se empieza por ahi, aqui, en Windows o en el movil.
//
// Se empieza por el verde y, si no hay, por lo que se esta viendo. La voz es
// de la app (`LeerEnVoz`): cerrar el lector no la calla, y al volver a
// abrirlo se engancha y va al trozo que suena.

import AppKit
import PDFKit
import PixPinCore

@MainActor
final class VozDelLector: LectorEnganchado {
    /// Lo mas largo de cada trozo que se resalta y se dice de una vez.
    nonisolated static let topeDelTrozo = 320
    /// El ambar del trozo que suena (`AMBAR_LEYENDO`) y el de la palabra.
    static let ambar = NSColor(srgbRed: 1, green: 196 / 255, blue: 64 / 255, alpha: 0.30)
    static let ambarPalabra = NSColor(srgbRed: 1, green: 170 / 255, blue: 0, alpha: 0.55)

    /// Un trozo: de que hoja, que letras (UTF-16) de su texto y a que altura
    /// de la hoja empieza (0 arriba, 1 abajo).
    struct Trozo: Equatable {
        var pagina: Int
        var rango: NSRange
        var altura: Float
    }

    weak var lector: ControladorLector?
    private(set) var trozos: [Trozo]?
    private var sacando = false
    private var escucharAlLlegar = false
    private var engancharAlLlegar = false
    /// Esta ventana es la que esta enganchada a la voz.
    private(set) var enganchada = false
    private var trozoVisto: Int?

    init(lector: ControladorLector) {
        self.lector = lector
    }

    private var voz: LeerEnVoz { .compartida }
    private var clave: String { lector?.url.path ?? "" }

    /// Escuchando este documento con la barra puesta.
    var activa: Bool { enganchada && voz.suena(clave) }

    // MARK: Los trozos

    /// **Los trozos de todas las hojas, en orden** (`trozos_de`), con la
    /// altura de cada uno. Hay que llamarlo en el hilo que abrio `doc`.
    nonisolated static func trozos(de doc: PDFDocument) -> [Trozo] {
        var salida: [Trozo] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i), let texto = p.string, !texto.isEmpty else { continue }
            let caja = p.bounds(for: .cropBox)
            for r in VozAlta.cortes(texto, tope: topeDelTrozo) {
                var altura: Float = 0
                if let s = p.selection(for: NSRange(location: r.location, length: min(r.length, 40))) {
                    let b = s.bounds(for: p)
                    if !b.isEmpty, caja.height > 0 {
                        altura = Float(min(max((caja.maxY - b.maxY) / caja.height, 0), 1))
                    }
                }
                salida.append(Trozo(pagina: i, rango: r, altura: altura))
            }
        }
        return salida
    }

    /// Lo que se le da a la voz de cada trozo.
    nonisolated static func parrafos(de doc: PDFDocument, _ trozos: [Trozo]) -> [String] {
        var textos: [Int: NSString] = [:]
        return trozos.map { t in
            let s = textos[t.pagina] ?? ((doc.page(at: t.pagina)?.string ?? "") as NSString)
            textos[t.pagina] = s
            guard NSMaxRange(t.rango) <= s.length else { return "" }
            return s.substring(with: t.rango)
        }
    }

    /// Pide los trozos, si aun no estan: un PDF se abre otra vez fuera del
    /// hilo principal; un Word o un PowerPoint maquetados se leen aqui.
    private func sacarLosTrozos(_ listo: @escaping @MainActor ([Trozo], [String]) -> Void) {
        guard let lector, let doc = lector.vistaPDF.document, !sacando else { return }
        if TiposDeDocumento.clase(de: lector.url) == .officePaginado {
            let t = VozDelLector.trozos(de: doc)
            // Maquetando aun: lo de ahora vale para esta vez, no se guarda.
            if !lector.modelo.maquetando { trozos = t }
            listo(t, VozDelLector.parrafos(de: doc, t))
            return
        }
        sacando = true
        let url = lector.url
        Task {
            let (t, p) = await Task.detached(priority: .userInitiated) { () -> ([Trozo], [String]) in
                guard let d = PDFDocument(url: url) else { return ([], []) }
                let t = VozDelLector.trozos(de: d)
                return (t, VozDelLector.parrafos(de: d, t))
            }.value
            self.sacando = false
            self.trozos = t
            listo(t, p)
        }
    }

    // MARK: Ordenes del lector

    /// **Escuchar** (L o el boton de la barra): con la barra puesta,
    /// play/pausa; si no, se empieza por el verde, o por lo que se ve.
    func escuchar() {
        if activa {
            voz.alternar()
            return
        }
        guard let lector, lector.vistaPDF.document != nil else { return }
        if sacando { return }
        lector.avisar("Sacando el texto para leerlo…")
        sacarLosTrozos { [weak self] trozos, parrafos in
            self?.empezar(trozos, parrafos)
        }
    }

    private func empezar(_ trozos: [Trozo], _ parrafos: [String]) {
        guard let lector else { return }
        guard !trozos.isEmpty else {
            lector.avisar("Este documento no tiene texto que leer")
            return
        }
        let (pagina, dentro): (Int, Float)
        if let v = lector.modelo.marcas.first(where: { $0.emoji == VozAlta.emojiDeVoz }) {
            pagina = Int(v.y.rounded(.down))
            dentro = Float(v.y - v.y.rounded(.down))
        } else {
            let s = lector.sitioDeLaVista()
            pagina = Int(s.rounded(.down))
            dentro = Float(s - s.rounded(.down))
        }
        let donde = trozos.map { (pagina: $0.pagina, altura: $0.altura) }
        let desde = VozAlta.trozoDesde(donde, pagina: pagina, dentro: dentro)
        let muestra = String(parrafos.dropFirst(desde).prefix(40).joined(separator: " ").prefix(4000))
        let idioma = VozAlta.idiomaParaLeer(muestra: muestra, lang: "", delEquipo: VozAlta.idiomaDeLaApp)
        // A la voz se le da el texto de la hoja tal cual (con sus blancos, que
        // `VozAlta.paraDecir` hace espacios): las palabras que avisa caen
        // asi en su sitio de la hoja y se resaltan alli.
        let titulo = (lector.modelo.nombre as NSString).deletingPathExtension
        let doc = LeerEnVoz.Documento(clave: clave, titulo: titulo.isEmpty ? lector.modelo.nombre : titulo,
                                      parrafos: parrafos, idioma: idioma,
                                      apuntar: VozDelLector.apuntarElVerde(ruta: clave, nucleo: lector.nucleo,
                                                                           donde: donde, altos: lector.altos()))
        guard voz.arrancar(doc, lector: self) else {
            lector.avisar("El Mac no tiene voz para «\(VozAlta.partes(idioma).lengua)»: Ajustes del Sistema › Accesibilidad › Contenido leído")
            return
        }
        enganchada = true
        self.trozos = trozos
        trozoVisto = nil
        voz.leer(desde: desde)
        lector.modelo.poniendoMarca = false
    }

    /// **Deja de escuchar** (la ✕ de la barra o ⎋): la voz se calla y olvida
    /// el documento. Cerrar el lector solo la suelta.
    func dejar() {
        if activa { voz.soltar() }
    }

    /// **Volver a abrir un documento que se esta escuchando**: con sus trozos
    /// ya aqui, el lector se engancha a la voz (barra, ambar, verde).
    func alAbrir() {
        guard voz.suena(clave), !enganchada, lector?.modelo.maquetando == false else { return }
        sacarLosTrozos { [weak self] trozos, _ in
            guard let self else { return }
            self.enganchada = self.voz.enganchar(self, clave: self.clave, cuantos: trozos.count)
        }
    }

    /// Se cierra el lector: la voz sigue, y desde ahora el verde lo apunta
    /// ella.
    func alCerrar() {
        voz.desenganchar(self)
        enganchada = false
    }

    // MARK: Lo que avisa la voz

    func vozSuena(_ i: Int, primero: Bool) {
        guard let lector, let t = trozos?[safe: i] else { return }
        resaltar(i, palabra: nil)
        seguir(t, antes: primero ? nil : trozos?[safe: i - 1], primero: primero)
        trozoVisto = i
        // El verde, a este trozo.
        lector.ponerMarcas(VozDelLector.conVerde(lector.modelo.marcas, en: (t.pagina, t.altura)))
    }

    func vozPalabra(_ r: NSRange?) {
        resaltar(voz.actual, palabra: r)
    }

    func vozAcabo() {
        guard let lector else { return }
        lector.vistaPDF.highlightedSelections = nil
        lector.ponerMarcas(VozDelLector.conVerde(lector.modelo.marcas, en: nil))
    }

    func vozFuera() {
        enganchada = false
        lector?.vistaPDF.highlightedSelections = nil
    }

    // MARK: Pintar y seguir

    /// Lo que suena en ambar y, encima, la palabra que se dice.
    private func resaltar(_ i: Int, palabra: NSRange?) {
        guard let lector, let t = trozos?[safe: i], let p = lector.vistaPDF.document?.page(at: t.pagina),
              let trozo = p.selection(for: t.rango) else { return }
        trozo.color = VozDelLector.ambar
        var todas = [trozo]
        if let r = palabra, r.length > 0, NSMaxRange(r) <= t.rango.length,
           let s = p.selection(for: NSRange(location: t.rango.location + r.location, length: r.length)) {
            s.color = VozDelLector.ambarPalabra
            todas.append(s)
        }
        lector.vistaPDF.highlightedSelections = todas
    }

    /// **Suena otro trozo**: la vista lo sigue si el de antes se veia
    /// (anotando no se mueve).
    private func seguir(_ t: Trozo, antes: Trozo?, primero: Bool) {
        guard let lector, !lector.modelo.anotando, let doc = lector.vistaPDF.document,
              let vistaDoc = lector.vistaPDF.documentView, let scroll = vistaDoc.enclosingScrollView else { return }
        let clip = scroll.contentView
        let alto = vistaDoc.bounds.height
        func arriba(_ t: Trozo) -> CGFloat? {
            guard let p = doc.page(at: t.pagina) else { return nil }
            let caja = p.bounds(for: lector.vistaPDF.displayBox)
            let y = caja.maxY - CGFloat(t.altura) * caja.height
            let enVista = lector.vistaPDF.convert(CGRect(x: caja.minX, y: y - 1, width: 1, height: 1), from: p)
            let enDoc = vistaDoc.convert(enVista, from: lector.vistaPDF)
            return vistaDoc.isFlipped ? enDoc.minY : alto - enDoc.maxY
        }
        guard let y = arriba(t) else { return }
        let visible = clip.bounds
        let desdeArriba = vistaDoc.isFlipped ? visible.minY : alto - visible.maxY
        guard let nueva = VozAlta.seguir(y: y, yAntes: antes.flatMap(arriba), arriba: desdeArriba,
                                         visto: visible.height, primero: primero) else { return }
        var o = visible.origin
        o.y = vistaDoc.isFlipped ? nueva : alto - nueva - visible.height
        let destino = clip.constrainBoundsRect(NSRect(origin: o, size: visible.size)).origin
        clip.scroll(to: destino)
        scroll.reflectScrolledClipView(clip)
    }

    // MARK: El verde

    /// Los marcadores con el verde de la voz en `donde` (hoja, altura), o
    /// sin el: nunca mas de un verde.
    nonisolated static func conVerde(_ marcas: [MarcaDocumento], en donde: (Int, Float)?) -> [MarcaDocumento] {
        let sin = marcas.filter { $0.emoji != VozAlta.emojiDeVoz }
        guard let (pagina, altura) = donde else { return sin }
        return conMarca(sin, x: 0.5, y: Double(pagina) + Double(altura), emoji: VozAlta.emojiDeVoz,
                        ahora: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// **El verde con el lector cerrado**: la voz sigue sonando y en cada
    /// trozo mueve el 🟢 de los marcadores del documento (los que viajan);
    /// al acabar lo quita (`apuntar_el_verde`).
    static func apuntarElVerde(ruta: String, nucleo: Nucleo, donde: [(pagina: Int, altura: Float)],
                               altos: [Float]) -> @MainActor (Int?) -> Void {
        let cola = DispatchQueue(label: "pixpin.voz.verde", qos: .utility)
        return { i in
            let sitio = i.flatMap { donde[safe: $0] }.map { ($0.pagina, $0.altura) }
            cola.async {
                var l = nucleo.lecturaDeDocumento(documento: ruta)
                l.marcas = conVerde(l.marcas, en: sitio)
                try? nucleo.guardarLecturaDeDocumento(documento: ruta, lectura: l, altos: altos)
            }
        }
    }
}
