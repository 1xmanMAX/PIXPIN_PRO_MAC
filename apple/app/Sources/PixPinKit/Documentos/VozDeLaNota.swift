// **Escuchar una nota** (D2): la voz de la app (`LeerEnVoz`) leyendo el
// texto de una nota, desde el renglon del cursor, con lo que suena en ambar
// y la palabra que se dice encima, como en el lector. Las marcas del
// Markdown (`#`, `**`, `[ ]`…) no se dicen.
//
// Se engancha **sin tocar el editor**: el menu del clic derecho del texto
// (`textView(_:menu:for:at:)`, del delegado que el editor ya es) trae
// «Escuchar desde aquí» y, sonando, la pausa y «Dejar de escuchar». La barra
// es la flotante (`PanelEscuchar`). Para otro editor (el web) el gancho es
// `VozDeLaNota.escuchar(texto:desde:clave:titulo:)`, sin resaltar.

import AppKit

@MainActor
final class VozDeLaNota: LectorEnganchado {
    /// La que suena: la voz solo la tiene debil.
    private static var actual: VozDeLaNota?

    private weak var vista: NSTextView?
    /// Los trozos de la nota que se leen, en UTF-16 del texto.
    let rangos: [NSRange]
    private var pintado: [NSRange] = []

    init(vista: NSTextView?, rangos: [NSRange]) {
        self.vista = vista
        self.rangos = rangos
    }

    /// **Los trozos de una nota**: cada renglon con algo que decir, cortado
    /// por las frases (`VozAlta.cortes`).
    static func rangos(de texto: String) -> [NSRange] {
        let ns = texto as NSString
        var salida: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { s, r, _, _ in
            guard let s else { return }
            for c in VozAlta.cortes(sinMarcas(s), tope: VozAlta.tope) {
                salida.append(NSRange(location: r.location + c.location, length: c.length))
            }
        }
        return salida
    }

    /// **Sin las marcas del Markdown**, del mismo largo: lo que no se dice
    /// se hace espacio (asi las palabras caen en su sitio del texto).
    static func sinMarcas(_ s: String) -> String {
        // # * _ ` > ~ | [ ] $ y los guiones de las listas («- », «+ »)
        let marcas: Set<UInt16> = [0x23, 0x2A, 0x5F, 0x60, 0x3E, 0x7E, 0x7C, 0x5B, 0x5D, 0x24]
        var u = Array(s.utf16)
        for i in u.indices {
            if marcas.contains(u[i]) {
                u[i] = 0x20
            } else if (u[i] == 0x2D || u[i] == 0x2B), i + 1 < u.count, u[i + 1] == 0x20,
                      u[..<i].allSatisfy({ $0 == 0x20 }) {
                u[i] = 0x20
            }
        }
        // «[x]» de una casilla hecha: la x suelta tampoco se dice.
        let t = String(decoding: u, as: UTF16.self)
        return t.replacingOccurrences(of: "  x  ", with: "     ")
    }

    /// **Escucha la nota** desde el trozo de `desde` (una letra del texto).
    /// `false` si no hay nada que leer o el Mac no tiene voz.
    @discardableResult
    static func escuchar(texto: String, desde: Int, clave: String, titulo: String,
                         vista: NSTextView? = nil, voz: LeerEnVoz? = nil) -> Bool {
        let voz = voz ?? .compartida
        let rangos = rangos(de: texto)
        guard !rangos.isEmpty else { return false }
        let ns = texto as NSString
        let parrafos = rangos.map { sinMarcas(ns.substring(with: $0)) }
        let muestra = String(parrafos.prefix(40).joined(separator: " ").prefix(4000))
        let idioma = VozAlta.idiomaParaLeer(muestra: muestra, lang: "", delEquipo: VozAlta.idiomaDeLaApp)
        let nota = VozDeLaNota(vista: vista, rangos: rangos)
        guard voz.arrancar(LeerEnVoz.Documento(clave: clave, titulo: titulo, parrafos: parrafos, idioma: idioma),
                           lector: vista == nil ? nil : nota) else { return false }
        actual = nota
        let i = rangos.firstIndex { NSMaxRange($0) > desde } ?? 0
        voz.leer(desde: i)
        return true
    }

    // MARK: Lo que avisa la voz

    func vozSuena(_ i: Int, primero: Bool) {
        guard let r = rangos[safe: i] else { return }
        pintar([r], palabra: nil)
        vista?.scrollRangeToVisible(r)
    }

    func vozPalabra(_ r: NSRange?) {
        guard let t = rangos[safe: LeerEnVoz.compartida.actual] else { return }
        let p = r.flatMap { $0.length > 0 && NSMaxRange($0) <= t.length
            ? NSRange(location: t.location + $0.location, length: $0.length) : nil }
        pintar([t], palabra: p)
    }

    func vozAcabo() { pintar([], palabra: nil) }

    /// La barra es la flotante: el editor no tiene sitio para la suya.
    var pintaSuBarra: Bool { false }

    func vozFuera() {
        pintar([], palabra: nil)
        if VozDeLaNota.actual === self { VozDeLaNota.actual = nil }
    }

    /// El ambar con atributos de paso (no tocan el texto ni el deshacer).
    private func pintar(_ trozos: [NSRange], palabra: NSRange?) {
        guard let lm = vista?.layoutManager, let largo = vista?.textStorage?.length else { return }
        for r in pintado where NSMaxRange(r) <= largo {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        pintado = []
        for r in trozos where NSMaxRange(r) <= largo {
            lm.addTemporaryAttribute(.backgroundColor, value: VozDelLector.ambar, forCharacterRange: r)
            pintado.append(r)
        }
        if let p = palabra, NSMaxRange(p) <= largo {
            lm.addTemporaryAttribute(.backgroundColor, value: VozDelLector.ambarPalabra, forCharacterRange: p)
            pintado.append(p)
        }
    }
}

/// El gancho en el editor de notas (el de AppKit): su menu del clic derecho.
extension ControladorNota {
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let voz = LeerEnVoz.compartida
        let clave = "nota\u{0}" + chat + "\u{0}" + mensaje
        menu.insertItem(.separator(), at: 0)
        if voz.suena(clave) {
            menu.insertItem(conAccion(voz.leyendo ? "Pausa" : "Seguir escuchando") { voz.alternar() }, at: 0)
            menu.insertItem(conAccion("Dejar de escuchar") { voz.soltar() }, at: 1)
        } else {
            let desde = view.selectedRange().location
            let titulo = ventana.title
            menu.insertItem(conAccion("Escuchar desde aquí") { [weak view] in
                guard let view else { return }
                if !VozDeLaNota.escuchar(texto: view.string, desde: desde, clave: clave, titulo: titulo, vista: view) {
                    NSSound.beep()
                }
            }, at: 0)
        }
        return menu
    }

    private func conAccion(_ titulo: String, _ hacer: @escaping @MainActor () -> Void) -> NSMenuItem {
        let a = AccionMenuLector(hacer)
        let i = NSMenuItem(title: titulo, action: #selector(AccionMenuLector.hacer(_:)), keyEquivalent: "")
        i.target = a
        i.representedObject = a
        return i
    }
}
