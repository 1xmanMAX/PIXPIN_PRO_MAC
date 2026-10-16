// Pruebas del almacen de pines (el `indice.json` de Windows) y de las
// cuentas de la vista de un pin (filtros, giro); al final, las teclas del
// pin y la vuelta al arrancar con ventanas de verdad.

import AppKit
import CoreGraphics
import Foundation
@testable import PixPinKit
import XCTest

final class AlmacenPinesTests: XCTestCase {
    private var raiz: URL!

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-almacen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: raiz)
    }

    private func pin() -> PinGuardado {
        var g = PinGuardado(x: 100, y: 200, ancho: 300, alto: 150, escalaPorCien: 200)
        g.giro = 1
        g.volteoH = true
        g.gris = true
        g.brillo = -3
        g.opacidad = 60
        g.pasante = true
        return g
    }

    func testGuardarYReabrirDevuelveLoMismo() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let (img, nota) = try {
            let a = try AlmacenPines(raiz: raiz)
            return (try a.guardarImagen(png: png, origen: "recorte", pin: pin()),
                    try a.guardarNota("Señal de canción — ñandú", origen: "nota", pin: pin()))
        }()
        // Nada vive solo en memoria.
        let a = try AlmacenPines(raiz: raiz)
        let e = try XCTUnwrap(a.entrada(img))
        XCTAssertEqual(e.tipo, .imagen)
        XCTAssertEqual(e.pin, pin(), "el giro, los filtros, la opacidad y el clic a traves vuelven")
        XCTAssertEqual(try Data(contentsOf: a.rutaObjeto(e)), png)
        XCTAssertTrue(e.objeto.hasPrefix("objetos/") && e.objeto.hasSuffix(String(format: "%06llu.png", img)))
        let n = try XCTUnwrap(a.entrada(nota))
        XCTAssertEqual(try String(contentsOf: a.rutaObjeto(n), encoding: .utf8), "Señal de canción — ñandú")
        XCTAssertNotEqual(img, nota)
    }

    func testElIndiceTieneElFormatoDeWindows() throws {
        let a = try AlmacenPines(raiz: raiz)
        let pdf = raiz.appendingPathComponent("ajeno.pdf")
        try Data("pdf".utf8).write(to: pdf)
        _ = try a.guardarArchivo(pdf, pin: pin())
        let texto = try String(contentsOf: raiz.appendingPathComponent("almacen/indice.json"), encoding: .utf8)
        for clave in ["\"siguiente_id\"", "\"escala_por_cien\"", "\"zoom_por_cien\"", "\"volteo_h\"",
                      "\"tipo\" : \"archivo\"", "\"grupo\" : null", "\"objeto\" : \"\""] {
            XCTAssertTrue(texto.contains(clave), "falta \(clave) en \(texto)")
        }
        // Por referencia: no se copia nada.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: raiz.appendingPathComponent("almacen/objetos").path), [])
        // Y no queda ningun temporal.
        XCTAssertFalse(FileManager.default.fileExists(atPath: raiz.appendingPathComponent("almacen/indice.json.tmp").path))
    }

    func testUnIndiceViejoDeWindowsAbreConLoDeFabrica() throws {
        let dir = raiz.appendingPathComponent("almacen", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        {"funcion_del_futuro": 42, "version":1,"siguiente_id":8,"entradas":[
          {"id":7,"tipo":"imagen","creado":"2026-09-02T03:07:55Z","origen":"recorte",
           "objeto":"objetos/2026/09/000007.png","grupo":null,
           "pin":{"x":1,"y":2,"ancho":3,"alto":4,"escala_por_cien":150}}]}
        """.utf8).write(to: dir.appendingPathComponent("indice.json"))
        let a = try AlmacenPines(raiz: raiz)
        XCTAssertEqual(a.entradas.count, 1)
        let g = try XCTUnwrap(a.entradas[0].pin)
        XCTAssertEqual(g.ancho, 3)
        XCTAssertEqual(g.opacidad, 100, "sin opacidad vuelve opaco, no invisible")
        XCTAssertEqual(g.giro, 0)
        XCTAssertFalse(g.pasante)
        XCTAssertNil(a.entradas[0].ruta)
        // El siguiente id sigue al del fichero.
        XCTAssertEqual(try a.guardarNota("x", origen: "nota", pin: nil), 8)
    }

    func testUnIndiceRotoSeApartaYSeEmpiezaDeCero() throws {
        let dir = raiz.appendingPathComponent("almacen", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ no es json".utf8).write(to: dir.appendingPathComponent("indice.json"))
        let a = try AlmacenPines(raiz: raiz)
        XCTAssertTrue(a.entradas.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("indice.json.roto").path))
    }

    func testCerrarNoBorraYSoloVuelvenLosAbiertosDeGruposVisibles() throws {
        let a = try AlmacenPines(raiz: raiz)
        let uno = try a.guardarNota("uno", origen: "nota", pin: pin())
        let dos = try a.guardarNota("dos", origen: "nota", pin: pin())
        let tres = try a.guardarNota("tres", origen: "nota", pin: pin())
        try a.actualizarPin(uno, nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.rutaObjeto(a.entrada(uno)!).path), "cerrar no borra")
        XCTAssertEqual(a.abiertas.map(\.id), [dos, tres])
        XCTAssertThrowsError(try a.actualizarPin(999, nil))

        // Un grupo oculto no vuelve solo.
        let g = try XCTUnwrap(try a.ponerGrupo(tres, color: .verde))
        XCTAssertEqual(a.colorDe(tres), .verde)
        XCTAssertEqual(try a.ponerGrupo(dos, color: .verde), g, "el color ES el grupo")
        try a.ponerGrupo(dos, color: nil)
        XCTAssertEqual(a.grupos.count, 1, "aun queda una entrada en el grupo")
        try a.ponerGrupo(tres, color: nil)
        XCTAssertTrue(a.grupos.isEmpty, "sin entradas, el grupo desaparece")
    }

    func testEliminarNoTocaElArchivoAjeno() throws {
        let a = try AlmacenPines(raiz: raiz)
        let ajeno = raiz.appendingPathComponent("ajeno.mov")
        try Data("no me toques".utf8).write(to: ajeno)
        let foto = raiz.appendingPathComponent("IMG_0001.JPG")
        try Data([0xFF, 0xD8]).write(to: foto)
        let copia = try a.guardarImagen(deFichero: foto, origen: AlmacenPines.origenFoto, pin: nil)
        let arch = try a.guardarArchivo(ajeno, pin: nil)
        let ruta = a.rutaObjeto(a.entrada(copia)!)
        XCTAssertTrue(ruta.lastPathComponent.hasSuffix(".jpg"), "la foto se copia con su extension")
        try a.eliminar(copia)
        try a.eliminar(arch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ruta.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ajeno.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foto.path))
    }

    func testLaNotaSeReescribeYLaFotoAnotadaEsUnObjetoNuevo() throws {
        let a = try AlmacenPines(raiz: raiz)
        let nota = try a.guardarNota("antes", origen: "mini:tareas", pin: pin())
        try a.reescribirNota(nota, texto: "después")
        XCTAssertEqual(try String(contentsOf: a.rutaObjeto(a.entrada(nota)!), encoding: .utf8), "después")
        let img = try a.guardarImagen(png: Data([1]), origen: "recorte", pin: pin())
        let vieja = a.rutaObjeto(a.entrada(img)!)
        try a.reemplazarImagen(img, png: Data([2]))
        let nueva = a.rutaObjeto(a.entrada(img)!)
        XCTAssertNotEqual(vieja, nueva)
        XCTAssertEqual(try Data(contentsOf: nueva), Data([2]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vieja.path))
        XCTAssertThrowsError(try a.reescribirNota(img, texto: "no es una nota"))
    }

    func testElOrigenDeLasMiniappsVaYVuelve() {
        let o = AlmacenPines.origenMini("tareas", chat: "c-1", mensaje: "m-9")
        XCTAssertEqual(o, "mini:tareas@m-9|c-1")
        let m = AlmacenPines.miniDeOrigen(o)
        XCTAssertEqual(m?.cual, "tareas")
        XCTAssertEqual(m?.chat, "c-1")
        XCTAssertEqual(m?.mensaje, "m-9")
        XCTAssertEqual(AlmacenPines.origenMini("contador", chat: nil, mensaje: nil), "mini:contador")
        XCTAssertNil(AlmacenPines.miniDeOrigen("mini:contador")?.chat)
        XCTAssertNil(AlmacenPines.miniDeOrigen("mini:tareas@|")?.chat)
        XCTAssertNil(AlmacenPines.miniDeOrigen("recorte"))
        XCTAssertNil(AlmacenPines.miniDeOrigen("mini:"))
    }

    func testLasRutasYExtensionesSonLasDeWindows() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fecha = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))!
        XCTAssertEqual(AlmacenPines.rutaRelativa(id: 7, extension: "png", fecha: fecha), "objetos/2026/09/000007.png")
        XCTAssertEqual(AlmacenPines.extensionDeObjeto(URL(fileURLWithPath: "/x/foto.HEIC")), "heic")
        XCTAssertEqual(AlmacenPines.extensionDeObjeto(URL(fileURLWithPath: "/x/foto")), "img")
        XCTAssertEqual(AlmacenPines.extensionDeObjeto(URL(fileURLWithPath: "/x/foto.demasiadolarga")), "img")
    }

    func testElMarcoVaYVuelveYEntraEnLaPantalla() {
        let techo: CGFloat = 900
        let marco = CGRect(x: 100, y: 500, width: 300, height: 200)
        let r = ReglasAlmacen.aAlmacen(marco, techo: techo)
        XCTAssertEqual(r.y, 200, "arriba a la izquierda, hacia abajo, como Windows")
        let g = PinGuardado(x: r.x, y: r.y, ancho: r.ancho, alto: r.alto, escalaPorCien: 200)
        XCTAssertEqual(ReglasAlmacen.deAlmacen(g, techo: techo), marco)

        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Fuera por la derecha y por arriba: entra entero.
        XCTAssertEqual(ReglasAlmacen.recolocar(CGRect(x: 900, y: 700, width: 300, height: 200), en: area),
                       CGRect(x: 700, y: 600, width: 300, height: 200))
        // Dentro: no se toca.
        XCTAssertEqual(ReglasAlmacen.recolocar(marco, en: area), marco)
        // Una pantalla que ya no esta: a la principal.
        let pantallas = [(marco: CGRect(x: 0, y: 0, width: 1000, height: 825), visible: area)]
        XCTAssertEqual(ReglasAlmacen.areaDeVuelta(CGRect(x: 5000, y: 0, width: 10, height: 10), pantallas: pantallas), area)
    }
}

final class FiltrosPinTests: XCTestCase {
    /// Una imagen de `w`×1 con estos pixeles RGBA (opacos).
    private func imagen(_ pixeles: [UInt8], ancho: Int, alto: Int = 1) -> CGImage {
        let datos = Data(pixeles) as CFData
        return CGImage(width: ancho, height: alto, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ancho * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: datos)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func pixeles(_ i: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: i.width * i.height * 4)
        return Array(UnsafeBufferPointer(start: p, count: i.width * i.height * 4))
    }

    func testElCanalSigueElOrdenDeWindows() {
        var f = FiltrosPin()
        XCTAssertEqual(f.canal(10, luma: 99), 10)
        f.gris = true
        XCTAssertEqual(f.canal(10, luma: 99), 99, "primero gris")
        f.invertido = true
        XCTAssertEqual(f.canal(10, luma: 99), 156, "luego invertir")
        f.brillo = 1
        XCTAssertEqual(f.canal(10, luma: 99), 182, "y el brillo al final: subir aclara")
        // El negro sube con el brillo (se suma, no se multiplica).
        XCTAssertEqual(FiltrosPin(brillo: 2).canal(0, luma: 0), 52)
        XCTAssertEqual(FiltrosPin().conBrillo(50).brillo, FiltrosPin.pasosMaximos)
        XCTAssertEqual(FiltrosPin().conBrillo(-50).brillo, -FiltrosPin.pasosMaximos)
        XCTAssertEqual(FiltrosPin.luminancia(0, 255, 0), 149, "el verde pesa mas que la media")
    }

    func testFiltrarNoTocaElOriginalYCeroLoDevuelve() {
        let original = imagen([10, 20, 30, 255, 200, 100, 50, 255], ancho: 2)
        let antes = pixeles(original)
        let invertida = ReglasFiltros.aplicar(original, filtros: FiltrosPin(invertido: true), giro: GiroPin())
        XCTAssertEqual(Array(pixeles(invertida).prefix(4)), [245, 235, 225, 255])
        XCTAssertEqual(pixeles(original), antes, "el original no se toca")
        XCTAssertTrue(ReglasFiltros.aplicar(original, filtros: FiltrosPin(), giro: GiroPin()) === original,
                      "sin nada que hacer, la misma")
    }

    func testGirarCambiaAnchoPorAltoYVoltearEsDeLoQueSeVe() {
        // Rojo a la izquierda, azul a la derecha.
        let original = imagen([255, 0, 0, 255, 0, 0, 255, 255], ancho: 2)
        var g = GiroPin()
        g.girar(1)
        let girada = ReglasFiltros.aplicar(original, filtros: FiltrosPin(), giro: g)
        XCTAssertEqual(girada.width, 1)
        XCTAssertEqual(girada.height, 2)
        // A la derecha: lo de la izquierda queda arriba (la primera fila).
        XCTAssertEqual(Array(pixeles(girada).prefix(4)), [255, 0, 0, 255])
        let volteada = ReglasFiltros.aplicar(original, filtros: FiltrosPin(), giro: GiroPin(volteoH: true))
        XCTAssertEqual(Array(pixeles(volteada).prefix(4)), [0, 0, 255, 255])
        g.girar(3)
        XCTAssertTrue(g.esNeutro, "derecha e izquierda se anulan")

        let marco = CGRect(x: 100, y: 100, width: 300, height: 100)
        let nuevo = ReglasFiltros.marcoGirado(marco)
        XCTAssertEqual(nuevo.size, CGSize(width: 100, height: 300))
        XCTAssertEqual(nuevo.midX, marco.midX)
        XCTAssertEqual(nuevo.midY, marco.midY, "no salta de sitio")
    }
}

/// Las teclas del pin y la vuelta del almacen, con ventanas de verdad (sin
/// ensenarlas al usuario: se cierran al acabar).
@MainActor
final class PinTeclasYVueltaTests: XCTestCase {
    private func tecla(_ pin: Pin, _ letra: String, codigo: UInt16, mods: NSEvent.ModifierFlags = []) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
                                 windowNumber: pin.panel.windowNumber, context: nil, characters: letra,
                                 charactersIgnoringModifiers: letra, isARepeat: false, keyCode: codigo)!
        _ = pin.atender(e)
    }

    private func foto() -> CGImage {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return ctx.makeImage()!
    }

    func testLasTeclasCambianLaVistaYSeGuardan() {
        let pin = Pin(id: 1, contenido: .imagen(foto(), fichero: nil), marco: CGRect(x: 100, y: 100, width: 200, height: 100))
        defer { pin.cerrar() }
        var guardados = 0
        pin.alGuardar = { _ in guardados += 1 }

        tecla(pin, "r", codigo: 15)
        XCTAssertEqual(pin.giro.cuartos, 1)
        XCTAssertEqual(pin.panel.frame.size, CGSize(width: 100, height: 200), "girar cambia ancho por alto")
        tecla(pin, "R", codigo: 15, mods: .shift)
        XCTAssertEqual(pin.giro.cuartos, 0, "⇧R gira a la izquierda")
        tecla(pin, "h", codigo: 4)
        XCTAssertTrue(pin.giro.volteoH)
        tecla(pin, "5", codigo: 23)
        tecla(pin, "7", codigo: 26)
        XCTAssertTrue(pin.filtros.gris)
        XCTAssertEqual(pin.filtros.brillo, 1)
        tecla(pin, "0", codigo: 29)
        XCTAssertTrue(pin.filtros.sonNeutros && pin.giro.esNeutro, "0 lo devuelve todo")
        tecla(pin, "n", codigo: 45)
        XCTAssertTrue(pin.negativo)

        let antes = pin.panel.frame.origin
        tecla(pin, "", codigo: 124)
        tecla(pin, "", codigo: 126, mods: .shift)
        XCTAssertEqual(pin.panel.frame.origin, CGPoint(x: antes.x + 1, y: antes.y + 10), "flechas, y ⇧ ×10")

        tecla(pin, "t", codigo: 17, mods: .command)
        XCTAssertTrue(pin.pasante)
        XCTAssertTrue(pin.panel.ignoresMouseEvents)
        let g = pin.guardado(techo: 1000)
        XCTAssertTrue(g.pasante)
        XCTAssertEqual(g.y, 1000 - Int(pin.panel.frame.maxY))
        XCTAssertGreaterThan(guardados, 5)
    }

    func testLosPinesVuelvenYElUltimoCerradoTambien() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-vuelta-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let techo = NSScreen.screens.first?.frame.maxY ?? 900
        var g = PinGuardado(x: 50, y: Int(techo) - 400, ancho: 300, alto: 200, escalaPorCien: 200)
        g.opacidad = 70
        do {
            let a = try AlmacenPines(raiz: raiz)
            _ = try a.guardarNota("# Hola", origen: "nota", pin: g)
            _ = try a.guardarNota("cerrada", origen: "nota", pin: nil)
        }
        let gestor = GestorPines()
        gestor.abrirAlmacen(en: raiz)
        gestor.restaurar()
        XCTAssertEqual(gestor.cuantos, 1, "solo vuelve la que estaba abierta")
        gestor.restaurar()
        XCTAssertEqual(gestor.cuantos, 1, "y no se duplica")

        gestor.cerrarTodos()
        XCTAssertEqual(gestor.cuantos, 0)
        XCTAssertNil(try AlmacenPines(raiz: raiz).entradas[0].pin, "cerrada en el almacen")
        XCTAssertTrue(gestor.restaurarUltimoCerrado())
        XCTAssertEqual(gestor.cuantos, 1)
        let vuelta = try XCTUnwrap(try AlmacenPines(raiz: raiz).entradas[0].pin)
        XCTAssertEqual(vuelta.opacidad, 70)
        XCTAssertFalse(gestor.restaurarUltimoCerrado(), "no queda otra")
        gestor.cerrarTodos()
    }
}
