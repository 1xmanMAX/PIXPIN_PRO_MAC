// Escuchar en voz alta (D2): las cuentas de `VozAlta` (las pruebas de
// `pixpin_docs::voz_alta` de Windows), la voz de la app con un altavoz mudo
// (parrafos, pausa, saltos, velocidad, el final y el verde con el lector
// cerrado) y los trozos de un PDF de verdad con su altura en la hoja.

import AppKit
import AVFoundation
import CoreText
import Foundation
import PDFKit
import PixPinCore
@testable import PixPinKit
import XCTest

/// Un PDF con renglones a distintas alturas: `hojas[i]` son los renglones de
/// la hoja `i`, de arriba abajo.
private func pdfConRenglones(_ hojas: [[String]]) -> Data {
    let datos = NSMutableData()
    var caja = CGRect(x: 0, y: 0, width: 400, height: 400)
    let consumidor = CGDataConsumer(data: datos as CFMutableData)!
    let ctx = CGContext(consumer: consumidor, mediaBox: &caja, nil)!
    for renglones in hojas {
        ctx.beginPDFPage(nil)
        for (n, texto) in renglones.enumerated() {
            let linea = CTLineCreateWithAttributedString(NSAttributedString(
                string: texto, attributes: [.font: NSFont.systemFont(ofSize: 12)]))
            ctx.textPosition = CGPoint(x: 20, y: 360 - CGFloat(n) * 150)
            CTLineDraw(linea, ctx)
        }
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return datos as Data
}

final class VozAltaTests: XCTestCase {
    func testLaVelocidadDaLaVueltaYSeEscribeComoEnElMovil() {
        XCTAssertEqual(VozAlta.siguienteVelocidad(1.0), 1.25)
        XCTAssertEqual(VozAlta.siguienteVelocidad(2.0), 0.75)
        XCTAssertEqual(VozAlta.siguienteVelocidad(3.3), 1.0, "una rara vuelve a la normal")
        XCTAssertEqual(VozAlta.rotulo(1.0), "1×")
        XCTAssertEqual(VozAlta.rotulo(1.5), "1,5×")
        XCTAssertEqual(VozAlta.rotulo(1.25), "1,25×")
        XCTAssertEqual(VozAlta.rotulo(0.75), "0,75×")
    }

    func testLaTasaDelMacCreceConLaVelocidadYSeQuedaEnSusTopes() {
        XCTAssertEqual(VozAlta.tasaDeApple(1.0), AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(VozAlta.tasaDeApple(0), AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertLessThanOrEqual(VozAlta.tasaDeApple(100), AVSpeechUtteranceMaximumSpeechRate)
        let tasas = VozAlta.velocidades.map(VozAlta.tasaDeApple)
        XCTAssertEqual(tasas, tasas.sorted(), "\(tasas)")
        XCTAssertEqual(Set(tasas).count, tasas.count)
    }

    func testUnParrafoCortoEsUnTrozoYUnoLargoSeCortaPorLasFrases() {
        XCTAssertEqual(VozAlta.trozos("  Hola   mundo. ", tope: 600), ["Hola mundo."])
        XCTAssertTrue(VozAlta.trozos("   ", tope: 600).isEmpty)
        let t = "Primera frase. Segunda frase! ¿Tercera? Cuarta."
        let v = VozAlta.trozos(t, tope: 20)
        XCTAssertEqual(v, ["Primera frase.", "Segunda frase!", "¿Tercera? Cuarta."])
        XCTAssertEqual(v.joined(separator: " "), t, "nada se pierde")
    }

    func testUnaFraseEternaSeCortaPorLasComasYLuegoPorLosEspacios() {
        let t = "uno, dos, tres, cuatro, cinco"
        let v = VozAlta.trozos(t, tope: 12)
        XCTAssertTrue(v.allSatisfy { $0.count <= 12 }, "\(v)")
        XCTAssertEqual(v.joined(separator: " "), t)
        let v2 = VozAlta.trozos(String(repeating: "a", count: 30), tope: 10)
        XCTAssertEqual(v2.count, 3)
        XCTAssertTrue(v2.allSatisfy { $0.count == 10 })
    }

    func testLosCortesSonRangosUTF16DelTextoOriginal() {
        let t = "Él dijo «sí». Y se fue. 🙂 Otra."
        let ns = t as NSString
        let textos = VozAlta.cortes(t, tope: 14).map { ns.substring(with: $0) }
        XCTAssertEqual(textos, ["Él dijo «sí».", "Y se fue.", "🙂 Otra."])
    }

    func testLoQueSeLeDaALaVozMideLoMismoQueElTextoDeLaHoja() {
        let t = "Una línea\ny otra\tcon 🙂  emoji"
        let d = VozAlta.paraDecir(t)
        XCTAssertEqual((d as NSString).length, (t as NSString).length)
        XCTAssertFalse(d.contains("\n"))
        XCTAssertEqual((d as NSString).range(of: "emoji"), (t as NSString).range(of: "emoji"))
    }

    func testElIdiomaSeAdivinaPorLasPalabrasYSeAfinaConElAcento() {
        let ingles = "The quick fox was in the house and it was not what they said of the dog"
        XCTAssertEqual(VozAlta.idiomaDelTexto(ingles, porDefecto: "es"), "en")
        let castellano = "El perro de la casa no es lo que dicen los vecinos y por eso se fue con su dueño"
        XCTAssertEqual(VozAlta.idiomaDelTexto(castellano, porDefecto: "en"), "es")
        XCTAssertEqual(VozAlta.idiomaDelTexto("hola", porDefecto: "fr"), "fr", "poca muestra")
        XCTAssertEqual(VozAlta.idiomaParaLeer(muestra: castellano, lang: "", delEquipo: "es-PE"), "es-PE")
        XCTAssertEqual(VozAlta.idiomaParaLeer(muestra: castellano, lang: "es-MX", delEquipo: "es-PE"), "es-MX")
        XCTAssertEqual(VozAlta.idiomaParaLeer(muestra: ingles, lang: "", delEquipo: "es-PE"), "en")
        XCTAssertEqual(VozAlta.idiomaParaLeer(muestra: "", lang: "", delEquipo: "es-PE"), "es-PE")
        XCTAssertTrue(VozAlta.partes("es_es") == ("es", "ES"))
    }

    func testSeEmpiezaPorElTrozoDeLaHojaYLaAlturaPedidas() {
        let donde: [(pagina: Int, altura: Float)] = [(0, 0.1), (0, 0.6), (2, 0.2), (2, 0.8)]
        XCTAssertEqual(VozAlta.trozoDesde(donde, pagina: 0, dentro: 0), 0)
        XCTAssertEqual(VozAlta.trozoDesde(donde, pagina: 0, dentro: 0.5), 1)
        XCTAssertEqual(VozAlta.trozoDesde(donde, pagina: 1, dentro: 0.9), 2, "la hoja sin texto: la siguiente")
        XCTAssertEqual(VozAlta.trozoDesde(donde, pagina: 2, dentro: 0.5), 3)
        XCTAssertEqual(VozAlta.trozoDesde(donde, pagina: 9, dentro: 0), 0, "pasado el final, desde el principio")
    }

    func testLaVistaSigueALaVozSoloSiSeEstabaMirando() {
        // Se ve de 1000 a 1500.
        XCTAssertNil(VozAlta.seguir(y: 1200, yAntes: 1100, arriba: 1000, visto: 500, primero: false))
        XCTAssertEqual(VozAlta.seguir(y: 1480, yAntes: 1400, arriba: 1000, visto: 500, primero: false), 1355)
        XCTAssertNil(VozAlta.seguir(y: 3000, yAntes: 2900, arriba: 1000, visto: 500, primero: false),
                     "quien se fue a mirar otra cosa no es arrastrado")
        XCTAssertEqual(VozAlta.seguir(y: 3000, yAntes: nil, arriba: 1000, visto: 500, primero: true), 2875)
    }

    func testLaVozDeUnIdiomaPrefiereLaElegidaYSiNoLaDelPais() throws {
        let todas = AVSpeechSynthesisVoice.speechVoices()
        // Un Mac sin voces (la CI) no tiene nada que elegir.
        guard !todas.isEmpty else { return }
        let una = try XCTUnwrap(todas.first)
        let lengua = VozAlta.partes(una.language).lengua
        XCTAssertEqual(VozAlta.voz(para: una.language, preferida: una.identifier, voces: todas)?.identifier,
                       una.identifier)
        XCTAssertEqual(VozAlta.partes(VozAlta.voz(para: lengua, preferida: nil, voces: todas)?.language ?? "").lengua,
                       lengua)
        XCTAssertNil(VozAlta.voz(para: "xx-YY", preferida: nil, voces: todas))
    }
}

/// Un lector de mentira que apunta lo que le cuenta la voz.
@MainActor
private final class LectorDePrueba: LectorEnganchado {
    var suenan: [Int] = []
    var palabras: [NSRange?] = []
    var acabos = 0
    var fueras = 0
    func vozSuena(_ i: Int, primero: Bool) { suenan.append(i) }
    func vozPalabra(_ r: NSRange?) { palabras.append(r) }
    func vozAcabo() { acabos += 1 }
    func vozFuera() { fueras += 1 }
}

@MainActor
final class LeerEnVozTests: XCTestCase {
    private func voz() -> (LeerEnVoz, AltavozMudo) {
        let a = AltavozMudo()
        return (LeerEnVoz(altavoz: a), a)
    }

    private func documento(_ parrafos: [String], apuntar: (@MainActor (Int?) -> Void)? = nil) -> LeerEnVoz.Documento {
        LeerEnVoz.Documento(clave: "/doc.pdf", titulo: "doc", parrafos: parrafos, idioma: "es-ES", apuntar: apuntar)
    }

    func testLeeLosParrafosSeguidosYAlAcabarQuitaElVerde() {
        let (v, a) = voz()
        let lector = LectorDePrueba()
        XCTAssertTrue(v.arrancar(documento(["Uno.", "Dos.\nmas", "Tres."]), lector: lector))
        XCTAssertTrue(v.suena("/doc.pdf"))
        XCTAssertTrue(a.dichos.isEmpty, "no suena hasta leer")
        v.leer(desde: 1)
        XCTAssertEqual(a.dichos, ["Dos. mas"], "los saltos de renglon se dicen como espacios")
        XCTAssertTrue(v.leyendo)
        a.acabar()
        XCTAssertEqual(v.actual, 2)
        XCTAssertEqual(a.dichos.last, "Tres.")
        a.acabar()
        XCTAssertFalse(v.leyendo)
        XCTAssertEqual(v.actual, 0)
        XCTAssertEqual(v.acabados, 1)
        XCTAssertEqual(lector.suenan, [1, 2])
        XCTAssertEqual(lector.acabos, 1)
        XCTAssertTrue(v.suena("/doc.pdf"), "la barra se queda al acabar")
    }

    func testLaPausaSigueAMediaFraseYSaltarEnPausaSoloSitua() {
        let (v, a) = voz()
        v.arrancar(documento(["Uno.", "Dos.", "Tres."]), lector: nil)
        v.leer(desde: 0)
        v.alternar()
        XCTAssertTrue(a.pausado)
        XCTAssertFalse(v.leyendo)
        v.alternar()
        XCTAssertFalse(a.pausado)
        XCTAssertEqual(a.dichos.count, 1, "seguir no vuelve a empezar la frase")
        v.alternar()
        XCTAssertEqual(v.saltar(1), 1)
        XCTAssertEqual(a.dichos.count, 1, "en pausa, saltar no habla")
        XCTAssertEqual(v.saltar(9), 2, "no se pasa del final")
        v.alternar()
        XCTAssertEqual(a.dichos.last, "Tres.")
        XCTAssertEqual(v.saltar(-5), 0)
        XCTAssertEqual(a.dichos.last, "Uno.", "leyendo, saltar dice el nuevo")
    }

    func testOtraVelocidadSigueDesdeLaPalabraQueSonaba() {
        let (v, a) = voz()
        let lector = LectorDePrueba()
        v.arrancar(documento(["Hola mundo bonito."]), lector: lector)
        v.leer(desde: 0)
        a.alDecir?(NSRange(location: 5, length: 5))
        XCTAssertEqual(lector.palabras.last, NSRange(location: 5, length: 5))
        XCTAssertEqual(v.otraVelocidad(), 1.25)
        XCTAssertEqual(a.dichos.last, "mundo bonito.")
        // La palabra que avisa ahora se cuenta desde el principio del parrafo.
        a.alDecir?(NSRange(location: 6, length: 7))
        XCTAssertEqual(lector.palabras.last, NSRange(location: 11, length: 7))
        // Lo que avise la frase callada ya no cuenta.
        let (v2, a2) = voz()
        v2.arrancar(documento(["A.", "B."]), lector: nil)
        v2.leer(desde: 0)
        let vieja = a2.alAcabar
        v2.saltar(1)
        vieja?()
        XCTAssertEqual(v2.actual, 1)
    }

    func testConElLectorCerradoElVerdeLoApuntaLaVozYSoltarAvisaAlLector() {
        let (v, a) = voz()
        var apuntados: [Int?] = []
        let lector = LectorDePrueba()
        v.arrancar(documento(["A.", "B."]) { apuntados.append($0) }, lector: lector)
        v.leer(desde: 0)
        XCTAssertTrue(apuntados.isEmpty, "con lector, el verde es suyo")
        v.desenganchar(lector)
        a.acabar()
        a.acabar()
        XCTAssertEqual(apuntados, [1, nil])
        // Se vuelve a abrir: solo se engancha el mismo documento contado igual.
        XCTAssertFalse(v.enganchar(lector, clave: "/otro.pdf", cuantos: 2))
        XCTAssertFalse(v.enganchar(lector, clave: "/doc.pdf", cuantos: 3))
        XCTAssertTrue(v.enganchar(lector, clave: "/doc.pdf", cuantos: 2))
        v.soltar()
        XCTAssertEqual(lector.fueras, 1)
        XCTAssertFalse(v.vivo)
        // Otro documento echa al lector de antes.
        let otro = LectorDePrueba()
        v.arrancar(documento(["A."]), lector: lector)
        v.arrancar(LeerEnVoz.Documento(clave: "/b", titulo: "b", parrafos: ["x"], idioma: "es"), lector: otro)
        XCTAssertEqual(lector.fueras, 2)
        XCTAssertEqual(otro.fueras, 0)
    }

    func testLosMandosDelMacManejanLaVoz() {
        let (v, a) = voz()
        v.arrancar(documento(["A.", "B."]), lector: nil)
        v.mandoTocar()
        XCTAssertEqual(a.dichos, ["A."])
        v.mandoPaso(1)
        XCTAssertEqual(a.dichos.last, "B.")
        v.mandoPausar()
        XCTAssertFalse(v.leyendo)
        v.mandoParar()
        XCTAssertFalse(v.vivo)
    }
}

@MainActor
final class VozDelLectorTests: XCTestCase {
    func testLosTrozosDeUnPDFVanPorHojasConSuAlturaYSuTexto() throws {
        let doc = try XCTUnwrap(PDFDocument(data: pdfConRenglones([
            ["Primera frase de arriba.", "Segunda frase de abajo."],
            [],
            ["Tercera hoja."],
        ])))
        let trozos = VozDelLector.trozos(de: doc)
        XCTAssertEqual(trozos.map(\.pagina), [0, 2], "los renglones juntos caben en un trozo; la hoja vacia no cuenta")
        let parrafos = VozDelLector.parrafos(de: doc, trozos)
        XCTAssertTrue(parrafos[0].contains("Primera"))
        XCTAssertTrue(parrafos[0].contains("Segunda"))
        XCTAssertEqual(VozAlta.juntarBlancos(parrafos[1]), "Tercera hoja.")
        XCTAssertGreaterThan(trozos[0].altura, 0.05)
        XCTAssertLessThan(trozos[0].altura, 0.2, "el primer renglon esta arriba")
        // Con trozos cortos, cada frase va sola y la de abajo, mas abajo.
        let cortos = VozAlta.cortes(try XCTUnwrap(doc.page(at: 0)?.string), tope: 30)
        XCTAssertEqual(cortos.count, 2)
    }

    func testElVerdeEsUnoSoloYSeQuitaAlAcabar() {
        let marca = MarcaDocumento(id: 1, x: 0.5, y: 0.3, emoji: "⭐")
        let con = VozDelLector.conVerde([marca], en: (2, 0.5))
        XCTAssertEqual(con.filter { $0.emoji == VozAlta.emojiDeVoz }.count, 1)
        XCTAssertEqual(con.first { $0.emoji == VozAlta.emojiDeVoz }?.y, 2.5)
        let otra = VozDelLector.conVerde(con, en: (3, 0))
        XCTAssertEqual(otra.filter { $0.emoji == VozAlta.emojiDeVoz }.map(\.y), [3])
        XCTAssertEqual(VozDelLector.conVerde(otra, en: nil), [marca])
    }
}

@MainActor
final class VozDeLaNotaTests: XCTestCase {
    func testLasMarcasDelMarkdownNoSeDicenYElLargoNoCambia() {
        let t = "## Título con **negrita**\n- [x] hecha\n  + otra `código`"
        let s = VozDeLaNota.sinMarcas(t)
        XCTAssertEqual((s as NSString).length, (t as NSString).length)
        XCTAssertFalse(s.contains("#") || s.contains("*") || s.contains("[") || s.contains("`"))
        XCTAssertFalse(s.contains(" x "), "la x de la casilla tampoco")
        XCTAssertTrue(s.contains("Título con   negrita"))
    }

    func testLaNotaSeLeeDesdeElRenglonDelCursor() {
        let texto = "# Lista\n\nPrimera cosa. Segunda cosa.\nTercera."
        let rangos = VozDeLaNota.rangos(de: texto)
        let ns = texto as NSString
        XCTAssertEqual(rangos.map { ns.substring(with: $0) }, ["Lista", "Primera cosa. Segunda cosa.", "Tercera."])
        let a = AltavozMudo()
        let voz = LeerEnVoz(altavoz: a)
        let desde = ns.range(of: "Tercera").location
        XCTAssertTrue(VozDeLaNota.escuchar(texto: texto, desde: desde, clave: "nota", titulo: "Lista", voz: voz))
        XCTAssertEqual(a.dichos, ["Tercera."])
        XCTAssertFalse(voz.conLector, "sin vista, la barra flota")
        XCTAssertFalse(VozDeLaNota.escuchar(texto: "  \n ", desde: 0, clave: "vacia", titulo: "", voz: voz))
    }
}
