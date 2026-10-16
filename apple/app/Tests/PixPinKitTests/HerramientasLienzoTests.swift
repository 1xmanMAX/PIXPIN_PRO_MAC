// Las herramientas nuevas del lienzo: cambiar de herramienta desde la barra,
// el reloj del gesto de pararse (con un programador de mentira: sin esperar
// de verdad), la barra de estilo, los cajetines de medir y pegar una imagen
// por el puente de verdad.

import AppKit
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

/// Un programador que no espera: apunta lo programado y lo dispara a mano.
private final class ProgramadorDePrueba {
    struct Pendiente {
        let segundos: Double
        let accion: () -> Void
        var cancelada = false
    }

    var pendientes: [Pendiente] = []

    var programar: RelojFormaRapida.Programar {
        { [unowned self] segundos, accion in
            self.pendientes.append(Pendiente(segundos: segundos, accion: accion))
            let i = self.pendientes.count - 1
            return { self.pendientes[i].cancelada = true }
        }
    }

    var vivas: [Pendiente] { pendientes.filter { !$0.cancelada } }

    /// Dispara la ultima que no se cancelo.
    func vencer() {
        guard let i = pendientes.lastIndex(where: { !$0.cancelada }) else { return }
        pendientes[i].cancelada = true
        pendientes[i].accion()
    }
}

final class RelojFormaRapidaTests: XCTestCase {
    func testUnaSolaEsperaQueSeReprogramaAlMoverseYSeCancelaAlSoltar() {
        let p = ProgramadorDePrueba()
        let reloj = RelojFormaRapida(temblorPx: 8, programar: p.programar)
        var paradas = 0
        reloj.alPararse = { paradas += 1 }

        reloj.pulsar(en: CGPoint(x: 0, y: 0), esperaMs: 550)
        XCTAssertEqual(p.vivas.count, 1)
        XCTAssertEqual(p.vivas.first?.segundos ?? 0, 0.55, accuracy: 1e-9)
        XCTAssertTrue(reloj.armado)

        // El temblor de la mano no cuenta como moverse.
        reloj.mover(a: CGPoint(x: 3, y: 4))
        reloj.mover(a: CGPoint(x: 5, y: 5))
        XCTAssertEqual(reloj.programadas, 1)

        // Alejarse reprograma: la vieja se cancela y queda UNA viva.
        reloj.mover(a: CGPoint(x: 40, y: 0))
        XCTAssertEqual(reloj.programadas, 2)
        XCTAssertEqual(p.vivas.count, 1)

        // Vence: avisa una vez y se desarma.
        p.vencer()
        XCTAssertEqual(paradas, 1)
        XCTAssertFalse(reloj.armado)
        p.vencer()
        XCTAssertEqual(paradas, 1, "nada mas que vencer")

        // El siguiente movimiento la vuelve a armar; soltar la cancela.
        reloj.mover(a: CGPoint(x: 41, y: 0))
        XCTAssertTrue(reloj.armado)
        reloj.soltar()
        XCTAssertFalse(reloj.armado)
        XCTAssertTrue(p.vivas.isEmpty)
        p.vencer()
        XCTAssertEqual(paradas, 1, "lo cancelado al soltar no avisa")
    }

    func testSinTrazoAManoNoSeProgramaNada() {
        let p = ProgramadorDePrueba()
        let reloj = RelojFormaRapida(temblorPx: 8, programar: p.programar)
        reloj.pulsar(en: .zero, esperaMs: nil)
        reloj.mover(a: CGPoint(x: 100, y: 100))
        XCTAssertTrue(p.pendientes.isEmpty)
        XCTAssertFalse(reloj.armado)
    }

    func testElGrafitoEsperaElSegundoQueDiceElMotor() {
        let p = ProgramadorDePrueba()
        let reloj = RelojFormaRapida(temblorPx: 8, programar: p.programar)
        reloj.pulsar(en: .zero, esperaMs: 1000)
        XCTAssertEqual(p.vivas.first?.segundos ?? 0, 1.0, accuracy: 1e-9)
    }

    /// Con el editor de verdad: el reloj pide la espera al motor y, al
    /// vencer, la raya quieta se vuelve una linea.
    func testAlVencerElTrazoQuietoSeVuelveFigura() throws {
        let carpeta = try carpetaTemporal("forma-rapida")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ruta = carpeta.appendingPathComponent("f.excalidraw").path
        let ed = try EditorLienzo.deFichero(ruta: ruta, crear: true)
        let p = ProgramadorDePrueba()
        let reloj = RelojFormaRapida(temblorPx: CGFloat(formaRapidaTemblorPx()), programar: p.programar)
        var convertido = false
        reloj.alPararse = { convertido = ed.formaRapida() }

        _ = ed.puntero(fase: .pulsar, x: 0, y: 0, presion: 0.5, modificadores: 0, zoom: 1)
        reloj.pulsar(en: .zero, esperaMs: ed.esperaFormaMs())
        for i in 1...40 {
            let x = Float(i) * 5
            _ = ed.puntero(fase: .mover, x: x, y: 0, presion: 0.5, modificadores: 0, zoom: 1)
            reloj.mover(a: CGPoint(x: CGFloat(x), y: 0))
        }
        p.vencer()
        XCTAssertTrue(convertido)
        reloj.soltar()
        _ = ed.puntero(fase: .soltar, x: 200, y: 0, presion: nil, modificadores: 0, zoom: 1)
        XCTAssertTrue(try ed.guardar())
        let json = try String(contentsOfFile: ruta, encoding: .utf8)
        XCTAssertTrue(json.contains("\"line\""))
        XCTAssertFalse(json.contains("\"freedraw\""))
    }
}

final class HerramientasLienzoTests: XCTestCase {
    @MainActor
    func testCadaHerramientaDeLaBarraLlegaAlMotorConSuNombre() throws {
        let carpeta = try carpetaTemporal("herramientas")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("h.excalidraw").path, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed)
        for h in HerramientaLienzo.herramientas {
            modelo.elegir(h.id)
            XCTAssertNil(modelo.error, h.id)
            XCTAssertEqual(modelo.herramienta, h.id)
            XCTAssertEqual(ed.herramientaActual(), h.id)
        }
        // Las nuevas estan, cada una en su grupo, y las teclas no se pisan.
        let ids = Set(HerramientaLienzo.herramientas.map(\.id))
        for id in ["lazo", "cota", "escalar", "escala_grafica", "relleno", "recortar", "extender", "punto",
                   "bolita", "zona", "nudo", "copiar_estilo", "mosaico", "lupa", "foco", "laser", "marco"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertEqual(GrupoHerramientaLienzo.arreglar.miembros.map(\.id),
                       ["recortar", "extender", "nudo", "copiar_estilo"])
        XCTAssertEqual(GrupoHerramientaLienzo.sacar.miembros.map(\.id), ["compartir", "imprimir"])
        XCTAssertTrue(GrupoHerramientaLienzo.sacar.miembros.allSatisfy(\.accion))
        XCTAssertEqual(GrupoHerramientaLienzo.medir.miembros.count, 3)
        let teclas = HerramientaLienzo.todas.compactMap(\.tecla)
        XCTAssertEqual(Set(teclas).count, teclas.count)
        // Caso negativo: un nombre que el motor no conoce deja el error.
        modelo.elegir("pincel_magico")
        XCTAssertNotNil(modelo.error)
        XCTAssertEqual(modelo.herramienta, HerramientaLienzo.herramientas.last?.id)
    }

    @MainActor
    func testElLazoEligeYLaBarraDeEstiloCambiaLoElegido() throws {
        let carpeta = try carpetaTemporal("lazo-estilo")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ruta = carpeta.appendingPathComponent("l.excalidraw").path
        let ed = try EditorLienzo.deFichero(ruta: ruta, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed)
        modelo.elegir("rectangulo")
        _ = ed.puntero(fase: .pulsar, x: 10, y: 10, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: 60, y: 60, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 60, y: 60, presion: nil, modificadores: 0, zoom: 1)
        modelo.elegir("lazo")
        let contorno: [(Float, Float)] = [(0, 0), (100, 0), (100, 100), (0, 100), (0, 1)]
        _ = ed.puntero(fase: .pulsar, x: 0, y: 0, presion: nil, modificadores: 0, zoom: 1)
        for (x, y) in contorno.dropFirst() {
            _ = ed.puntero(fase: .mover, x: x, y: y, presion: nil, modificadores: 0, zoom: 1)
        }
        _ = ed.puntero(fase: .soltar, x: 0, y: 1, presion: nil, modificadores: 0, zoom: 1)
        XCTAssertEqual(ed.cuantosElegidos(), 1)

        let rojo = OpcionesEstiloLienzo.trazos[1].valor
        modelo.cambiarEstilo(.trazo(color: rojo))
        XCTAssertTrue(OpcionesEstiloLienzo.igual(modelo.estilo.trazo, rojo))
        modelo.cambiarEstilo(.grosor(grosor: .grueso))
        XCTAssertEqual(OpcionesEstiloLienzo.nombre(modelo.estilo.grosor), "Grueso")
        modelo.cambiarEstilo(.linea(linea: .discontinua))
        modelo.cambiarEstilo(.fondo(color: OpcionesEstiloLienzo.fondos[1].valor))
        modelo.cambiarEstilo(.relleno(relleno: .solido))
        XCTAssertTrue(try ed.guardar())
        let json = try String(contentsOfFile: ruta, encoding: .utf8)
        XCTAssertTrue(json.contains("#e03131"), "el trazo rojo de la barra")
        XCTAssertTrue(json.contains("\"dashed\""))
        XCTAssertTrue(json.contains("#ffc9c9"))
        XCTAssertTrue(json.contains("\"fillStyle\" : \"solid\"") || json.contains("\"fillStyle\": \"solid\""))
    }

    func testLasOpcionesDeLaBarraYSusColores() {
        XCTAssertEqual(OpcionesEstiloLienzo.trazos.count, 5)
        XCTAssertNil(OpcionesEstiloLienzo.fondos[0].valor, "el primero es transparente")
        let c = OpcionesEstiloLienzo.hex(0x1971c2)
        XCTAssertEqual(c.r, Float(0x19) / 255, accuracy: 1e-6)
        XCTAssertEqual(c.b, Float(0xc2) / 255, accuracy: 1e-6)
        let ida = OpcionesEstiloLienzo.estilo(de: OpcionesEstiloLienzo.color(c))
        XCTAssertTrue(OpcionesEstiloLienzo.igual(ida, c))
        XCTAssertFalse(OpcionesEstiloLienzo.igual(c, nil))
        XCTAssertEqual(Set(OpcionesEstiloLienzo.rellenos.map(\.id)).count, 5)
    }

    func testLosNumerosDeLosCajetines() {
        XCTAssertEqual(CajetinMedida.numero("2,5"), 2.5)
        XCTAssertEqual(CajetinMedida.numero(" 3.25 "), 3.25)
        XCTAssertNil(CajetinMedida.numero("dos"))
        XCTAssertNil(CajetinMedida.numero(""))
    }

    func testLaCotaYCalibrarPorElPuente() throws {
        let carpeta = try carpetaTemporal("cota")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("c.excalidraw").path, crear: true)
        try ed.herramienta(nombre: "escalar")
        _ = ed.puntero(fase: .pulsar, x: 0, y: 0, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: 100, y: 0, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 100, y: 0, presion: nil, modificadores: 0, zoom: 1)
        guard case let .calibrar(largoPx)? = ed.tomarPeticion() else {
            return XCTFail("tenia que pedir la medida")
        }
        XCTAssertTrue(ed.calibrar(largoPx: largoPx, valor: 50, unidad: "cm"))
        try ed.herramienta(nombre: "cota")
        _ = ed.puntero(fase: .pulsar, x: 0, y: 50, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: 200, y: 50, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 200, y: 50, presion: nil, modificadores: 0, zoom: 1)
        guard case let .dictarCota(id, largo, _, unidad)? = ed.tomarPeticion() else {
            return XCTFail("la cota tenia que pedir su medida")
        }
        XCTAssertEqual(unidad, "cm")
        XCTAssertEqual(largo, 100, accuracy: 0.01)
        XCTAssertTrue(ed.dictarCota(id: id, largo: 25, grados: 0))
        XCTAssertEqual(ed.cuantosElementos(), 1)
    }

    /// Una imagen pequena de verdad, en TIFF (lo que deja una captura en el
    /// portapapeles).
    private func tiff(ancho: Int, alto: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: ancho, pixelsHigh: alto,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<alto {
            for x in 0..<ancho {
                rep.setColor(NSColor(red: CGFloat(x) / CGFloat(ancho), green: 0.5, blue: 0.2, alpha: 1), atX: x, y: y)
            }
        }
        return try XCTUnwrap(rep.tiffRepresentation)
    }

    func testUnaImagenPegadaSeGuardaEnElChatConSuEntradaEnFiles() throws {
        let raiz = try carpetaTemporal("pegar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nucleo = try Nucleo.abrir(raiz: raiz.path, nombreDelAparato: "Mac")
        let chat = try nucleo.crearChat(nombre: "Obra")
        let referencia = try XCTUnwrap(try nucleo.crearLienzo(chat: chat.id, nombre: nil).referencia)
        let ed = try nucleo.editarLienzo(chat: chat.id, dibujo: referencia)

        let png = try XCTUnwrap(ImagenPegadaLienzo.png(de: try tiff(ancho: 40, alto: 30)))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4e, 0x47], "sale un PNG")
        // Un PNG que ya cabe pasa tal cual, sin recodificar.
        XCTAssertEqual(ImagenPegadaLienzo.png(de: png), png)
        XCTAssertNil(ImagenPegadaLienzo.png(de: Data("no soy una foto".utf8)))

        let foto = try ed.pegarImagen(png: png, centroX: 100, centroY: 100, anchoVista: 800, altoVista: 600)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foto.ruta))
        XCTAssertEqual(ed.herramientaActual(), "seleccion")
        XCTAssertTrue(try ed.guardar())

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ed.ruta())))
            as? [String: Any]
        let elementos = try XCTUnwrap(json?["elements"] as? [[String: Any]])
        let imagen = try XCTUnwrap(elementos.first { $0["type"] as? String == "image" })
        let clave = try XCTUnwrap(imagen["fileId"] as? String)
        XCTAssertTrue(clave.hasPrefix("pc"))
        let files = try XCTUnwrap(json?["files"] as? [String: Any])
        let entrada = try XCTUnwrap(files[clave] as? [String: Any])
        XCTAssertEqual(entrada["mimeType"] as? String, "image/png")
        XCTAssertEqual(entrada["path"] as? String, "imagenes/\(clave)")

        // Al reabrir, la foto sale con su ruta en la carpeta del chat.
        let otra = try nucleo.editarLienzo(chat: chat.id, dibujo: referencia)
        let fotos = otra.imagenes()
        XCTAssertEqual(fotos.count, 1)
        XCTAssertEqual(fotos.first?.idObjeto, foto.idObjeto)
        XCTAssertTrue(fotos.first?.ruta.hasSuffix("imagenes/\(clave)") ?? false)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(fotos.first?.ruta))), png)
    }

    @MainActor
    func testElCursorDelTextoColocaLaVentanitaDelMetodoDeEntrada() throws {
        let carpeta = try carpetaTemporal("ime")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("t.excalidraw").path, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed)
        let vista = VistaEditorLienzoNS(modelo: modelo)
        vista.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertNil(vista.rectanguloDelCursor())
        modelo.elegir("texto")
        _ = ed.puntero(fase: .pulsar, x: 150, y: 120, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 150, y: 120, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.teclear(texto: "Hola")
        let r = try XCTUnwrap(vista.rectanguloDelCursor())
        // La vista sin encajar: origen 0 y zoom 1, el cursor detras de «Hola».
        XCTAssertGreaterThan(r.minX, 150)
        XCTAssertGreaterThanOrEqual(r.minY, 115)
        XCTAssertLessThan(r.minY, 160)
        XCTAssertGreaterThan(r.height, 5)
        // Y la cuenta del mundo a la vista con camara.
        let c = CajaLienzo(x0: 10, y0: 20, x1: 10, y1: 40)
        let v = VistaEditorLienzoNS.aVista(c, origen: CGPoint(x: 5, y: 10), zoom: 2)
        XCTAssertEqual(v, NSRect(x: 10, y: 20, width: 1, height: 40))
    }
}

/// La barra como la de Windows: sus grupos, sus letras, la regla del clic y
/// los iconos de Excalidraw leidos de sus trazados SVG.
final class BarraHerramientasLienzoTests: XCTestCase {
    func testLasLetrasSonLasDeWindowsYNoSePisan() {
        // `tecla_a_herramienta` de Windows, para las que el Mac tiene.
        let windows: [Character: String] = [
            "m": "seleccion", "l": "lapiz", "r": "resaltador", "t": "texto", "b": "borrador",
            "a": "cota", "e": "escalar", "g": "escala_grafica", "p": "grafito",
            "f": "foco", "q": "lupa", "c": "marco", "z": "zona", "j": "laser",
        ]
        for (c, id) in windows {
            XCTAssertEqual(HerramientaLienzo.deTecla(c)?.id, id, String(c))
            XCTAssertEqual(HerramientaLienzo.deTecla(Character(c.uppercased()))?.id, id)
        }
        // Caso negativo: una letra sin herramienta no elige nada.
        XCTAssertNil(HerramientaLienzo.deTecla("k"))
        XCTAssertEqual(OpcionesEstiloLienzo.grosor(tecla: "3").map { "\($0)" }, "grueso")
        XCTAssertNil(OpcionesEstiloLienzo.grosor(tecla: "4"))
    }

    func testTodaHerramientaSeAlcanzaDesdeLaBarraYLosSeparadoresVanEntreSecciones() {
        var alcanzables = Set<String>()
        for b in BotonBarraLienzo.barra {
            switch b {
            case let .herramienta(id): alcanzables.insert(id)
            case let .grupo(g): g.miembros.forEach { alcanzables.insert($0.id) }
            default: break
            }
        }
        XCTAssertEqual(alcanzables, Set(HerramientaLienzo.todas.map(\.id)), "ninguna se queda sin boton")
        // Cada grupo de la barra tiene a alguien dentro.
        for g in GrupoHerramientaLienzo.allCases { XCTAssertFalse(g.miembros.isEmpty, g.rawValue) }
        // Elegir | dibujar | medir, imagen y goma | acciones: tres cortes.
        let cortes = BotonBarraLienzo.barra.indices.filter { BotonBarraLienzo.corte(tras: $0) }
        XCTAssertEqual(cortes.count, 3)
        XCTAssertEqual(BotonBarraLienzo.barra.last, .salir)
        XCTAssertFalse(BotonBarraLienzo.corte(tras: BotonBarraLienzo.barra.count - 1))
    }

    @MainActor
    func testPulsarUnGrupoCogeSuCaraDespliegaYRecuerdaLaUltimaUsada() {
        GruposBarraLienzo.olvidar()
        defer { GruposBarraLienzo.olvidar() }
        // De fabrica, la cara de las formas es el rectangulo: se coge y se abre.
        var r = GruposBarraLienzo.pulsar(.formas, activa: "lapiz", desplegado: nil)
        XCTAssertEqual(r.elegir, "rectangulo")
        XCTAssertEqual(r.desplegado, .formas)
        // Pulsado otra vez, abierto y con lo suyo puesto: se cierra sin mas.
        r = GruposBarraLienzo.pulsar(.formas, activa: "rectangulo", desplegado: .formas)
        XCTAssertNil(r.elegir)
        XCTAssertNil(r.desplegado)
        // Se usa el rombo: se queda de cara aunque luego se coja el lapiz.
        XCTAssertEqual(GruposBarraLienzo.cara(.formas, activa: "rombo")?.id, "rombo")
        XCTAssertEqual(GruposBarraLienzo.cara(.formas, activa: "lapiz")?.id, "rombo")
        XCTAssertEqual(GruposBarraLienzo.pulsar(.formas, activa: "lapiz", desplegado: nil).elegir, "rombo")
        // Caso negativo: la cara de un grupo de acciones no se dispara (nada
        // de imprimir por sorpresa), solo se despliega.
        r = GruposBarraLienzo.pulsar(.sacar, activa: "lapiz", desplegado: nil)
        XCTAssertNil(r.elegir)
        XCTAssertEqual(r.desplegado, .sacar)
        // Una accion usada se queda de cara de su grupo.
        GruposBarraLienzo.usado("imprimir")
        XCTAssertEqual(GruposBarraLienzo.cara(.sacar, activa: "lapiz")?.id, "imprimir")
    }

    func testSiNoCabeLaBarraSePartePorUnSeparadorEnDosFilasParejas() {
        let n = BotonBarraLienzo.barra.count
        let entera = BotonBarraLienzo.anchoDeFila(BotonBarraLienzo.barra[...])
        // 17 botones, 3 separadores: lo de Windows (36, 4, 4 de relleno, 9 por corte).
        XCTAssertEqual(entera, 2 * 4 + CGFloat(n) * 36 + CGFloat(n - 1) * 4 + 3 * 9)
        XCTAssertEqual(BotonBarraLienzo.cortePara(ancho: entera), n, "si cabe, una fila")
        let corte = BotonBarraLienzo.cortePara(ancho: entera - 1)
        XCTAssertLessThan(corte, n)
        XCTAssertNotEqual(BotonBarraLienzo.barra[corte - 1].seccion, BotonBarraLienzo.barra[corte].seccion,
                          "se parte por un separador")
        let a = BotonBarraLienzo.anchoDeFila(BotonBarraLienzo.barra[..<corte])
        let b = BotonBarraLienzo.anchoDeFila(BotonBarraLienzo.barra[corte...])
        XCTAssertLessThan(max(a, b), entera * 0.7, "las dos filas, parejas")
    }

    @MainActor
    func testElModeloAbreYCierraElDesplegableYElPanelSabeSiHayElegidos() throws {
        GruposBarraLienzo.olvidar()
        defer { GruposBarraLienzo.olvidar() }
        let carpeta = try carpetaTemporal("barra-grupos")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("b.excalidraw").path, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed)
        XCTAssertFalse(modelo.papelOscuro, "el papel de fabrica es blanco")
        modelo.pulsarGrupo(.flechas)
        XCTAssertEqual(modelo.herramienta, "flecha")
        XCTAssertEqual(modelo.desplegado, .flechas)
        modelo.elegirDelDesplegable("flecha_codos")
        XCTAssertEqual(ed.herramientaActual(), "flecha_codos")
        XCTAssertNil(modelo.desplegado)
        // Un rectangulo y elegirlo todo: hay elegidos para el panel.
        modelo.elegir("rectangulo")
        _ = ed.puntero(fase: .pulsar, x: 10, y: 10, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: 60, y: 60, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 60, y: 60, presion: nil, modificadores: 0, zoom: 1)
        modelo.elegir("seleccion")
        ed.seleccionarTodo()
        modelo.refrescarBarra()
        XCTAssertTrue(modelo.hayElegidos)
        modelo.elegir("lapiz")
        XCTAssertFalse(modelo.hayElegidos, "coger una que dibuja suelta lo elegido")
    }

    func testElLectorDeTrazadosSVG() throws {
        // Numeros pegados, relativas y la recta implicita tras M.
        let p = try XCTUnwrap(TrayectoSVG.leer("M1 2 3 4l-1.5.5h2v-1z"))
        XCTAssertEqual(p.boundingBoxOfPath.minX, 1, accuracy: 1e-6)
        XCTAssertEqual(p.boundingBoxOfPath.maxX, 3.5, accuracy: 1e-6)
        XCTAssertEqual(p.boundingBoxOfPath.maxY, 4.5, accuracy: 1e-6)
        // Un circulo de radio 2 con dos arcos (banderas pegadas incluidas).
        let c = try XCTUnwrap(TrayectoSVG.leer("M5 15m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0"))
        let caja = c.boundingBoxOfPath
        XCTAssertEqual(caja.midX, 5, accuracy: 0.01)
        XCTAssertEqual(caja.midY, 15, accuracy: 0.01)
        XCTAssertEqual(caja.width, 4, accuracy: 0.02)
        XCTAssertEqual(caja.height, 4, accuracy: 0.02)
        XCTAssertNotNil(TrayectoSVG.leer("M0 0a2 2 0 105 5"), "banderas pegadas al numero")
        XCTAssertNotNil(TrayectoSVG.leer("M0 0C1 1 2 2 3 3S5 5 6 6Q7 7 8 8T9 9"))
        // Casos negativos: basura o numeros sin orden.
        XCTAssertNil(TrayectoSVG.leer("hola"))
        XCTAssertNil(TrayectoSVG.leer("1 2 3"))
        XCTAssertNil(TrayectoSVG.leer(""))
    }

    func testTodosLosIconosDeLaBarraSeLeen() {
        var iconos = HerramientaLienzo.todas.map(\.icono)
        iconos += [.image, .undo, .redo, .close, .fillLineas]
        iconos += OpcionesEstiloLienzo.rellenos.map { OpcionesEstiloLienzo.icono($0.valor) }
        iconos += OpcionesEstiloLienzo.grosores.map { OpcionesEstiloLienzo.icono($0.valor) }
        iconos += OpcionesEstiloLienzo.lineas.map { OpcionesEstiloLienzo.icono($0.valor) }
        iconos += OpcionesEstiloLienzo.rugosidades.map { OpcionesEstiloLienzo.icono(rugosidad: $0.valor) }
        for (i, icono) in iconos.enumerated() {
            XCTAssertFalse(icono.trazos.isEmpty, "icono \(i) sin trazos")
            for t in icono.trazos {
                let p = TrayectoSVG.leer(t.d)
                XCTAssertNotNil(p, "icono \(i): \(t.d)")
                // Cae dentro (o casi) de su viewBox: se leyo bien.
                if let caja = p?.boundingBoxOfPath {
                    XCTAssertTrue(icono.vista.insetBy(dx: -4, dy: -4).contains(caja) || t.mascara != nil,
                                  "icono \(i) fuera de su caja: \(caja)")
                }
            }
        }
    }
}

/// Las herramientas que lleva quien tiene la escena (la zona, el laser, el
/// mosaico y la lupa) y sacar el dibujo, por el puente de verdad.
final class TaparYSacarLienzoTests: XCTestCase {
    private func trazar(_ ed: EditorLienzo, _ h: String, _ a: (Float, Float), _ b: (Float, Float)) throws {
        try ed.herramienta(nombre: h)
        _ = ed.puntero(fase: .pulsar, x: a.0, y: a.1, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .mover, x: b.0, y: b.1, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: b.0, y: b.1, presion: nil, modificadores: 0, zoom: 1)
    }

    @MainActor
    func testLaZonaPideSuFotoYLaCopiaEntraElegida() throws {
        let carpeta = try carpetaTemporal("zona")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("z.excalidraw").path, crear: true)
        try trazar(ed, "rectangulo", (10, 10), (90, 60))
        try trazar(ed, "zona", (0, 0), (100, 80))
        guard case let .zona(x0, y0, x1, y1)? = ed.tomarPeticion() else { return XCTFail("tenia que pedir la foto") }
        XCTAssertEqual([x0, y0, x1, y1], [0, 0, 100, 80])
        XCTAssertNil(ed.tomarPeticion(), "se pide una vez")
        let caja = CGRect(x: 0, y: 0, width: 100, height: 80)
        let plano = ed.planoDeVista(x: 0, y: 0, zoom: 2, anchoPx: 200, altoPx: 160)
        let img = try XCTUnwrap(PintorDeHojas.imagen(plano, caja: caja, escala: 2, transparente: false,
                                                     tapados: nil, version: 0, fotos: { _ in nil }))
        XCTAssertEqual(img.width, 200)
        let png = try XCTUnwrap(PintorDeHojas.enRedondo(img, papelDeNoche: false).flatMap(PintorDeHojas.png))
        _ = try ed.ponerCopiaDeZona(png: png, x0: 0, y0: 0, x1: 100, y1: 80, zoom: 1)
        XCTAssertEqual(ed.cuantosElementos(), 2)
        XCTAssertEqual(ed.cuantosElegidos(), 1)
        XCTAssertEqual(ed.herramientaActual(), "zona", "la zona se queda en la mano")
        // Caso negativo: un clic suelto no pide nada.
        try trazar(ed, "zona", (300, 300), (302, 301))
        XCTAssertNil(ed.tomarPeticion())
    }

    func testElLaserSeAnimaYNoDejaNada() throws {
        let carpeta = try carpetaTemporal("laser")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("l.excalidraw").path, crear: true)
        XCTAssertFalse(ed.animando())
        try trazar(ed, "laser", (0, 0), (80, 40))
        XCTAssertTrue(ed.animando(), "la estela se apaga sola")
        XCTAssertEqual(ed.cuantosElementos(), 0)
        XCTAssertFalse(ed.puedeDeshacer())
    }

    @MainActor
    func testElMosaicoTapaConCuadrosYLaLupaEnsenaAgrandado() throws {
        let carpeta = try carpetaTemporal("tapar")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("t.excalidraw").path, crear: true)
        try trazar(ed, "rectangulo", (0, 0), (100, 100))
        try trazar(ed, "mosaico", (-10, -10), (60, 60))
        try trazar(ed, "elipse", (300, 0), (400, 100))
        // La lupa: tocar la elipse con la varita.
        try ed.herramienta(nombre: "lupa")
        _ = ed.puntero(fase: .pulsar, x: 350, y: 50, presion: nil, modificadores: 0, zoom: 1)
        _ = ed.puntero(fase: .soltar, x: 350, y: 50, presion: nil, modificadores: 0, zoom: 1)
        XCTAssertEqual(ed.herramientaActual(), "seleccion", "hecha la lupa, la mano")
        let leido = try leerLienzo(ed.planoDeVista(x: -50, y: -50, zoom: 1, anchoPx: 600, altoPx: 300))
        let tapados: [UInt64] = leido.figuras.compactMap {
            if case let .imagen(id, _, _, _, _, _) = $0, PintorDeTapados.esTapado(id) { return id }
            return nil
        }
        XCTAssertEqual(tapados.count, 2, "el mosaico y la lupa")
        let modelo = ModeloEditorLienzo(editor: ed)
        for id in tapados {
            let c = try XCTUnwrap(ed.contenidoDeTapado(idObjeto: id))
            XCTAssertNotNil(PintorDeTapados.pintar(c, escala: 2, fotos: { _ in nil }))
            XCTAssertNotNil(modelo.tapados.imagen(id, version: ed.version(), escala: 2))
        }
        // Caso negativo: el id de una foto no es un tapado.
        XCTAssertFalse(PintorDeTapados.esTapado(12345))
        XCTAssertNil(ed.contenidoDeTapado(idObjeto: 12345))
    }

    @MainActor
    func testSeExportaEnPngPdfYSvgYCadaMarcoEsUnaHoja() throws {
        let carpeta = try carpetaTemporal("exportar")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("e.excalidraw").path, crear: true)
        let modelo = ModeloEditorLienzo(editor: ed, titulo: "Mi/lienzo")
        XCTAssertTrue(modelo.ficheros(.png, que: .todo, transparente: false).isEmpty, "en blanco no sale nada")
        try trazar(ed, "rectangulo", (0, 0), (100, 50))
        try trazar(ed, "marco", (-20, -20), (150, 80))
        try trazar(ed, "elipse", (400, 400), (450, 450))
        try trazar(ed, "marco", (380, 380), (480, 480))
        XCTAssertEqual(ed.hojasParaExportar(que: .marcos).count, 2)
        let pngs = modelo.ficheros(.png, que: .marcos, transparente: true)
        XCTAssertEqual(pngs.count, 2)
        XCTAssertEqual(Array(pngs[0].prefix(4)), [0x89, 0x50, 0x4e, 0x47])
        let pdf = try XCTUnwrap(modelo.ficheros(.pdf, que: .marcos, transparente: false).first)
        XCTAssertEqual(String(decoding: pdf.prefix(4), as: UTF8.self), "%PDF")
        XCTAssertEqual(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)?.numberOfPages, 2)
        let svg = try XCTUnwrap(modelo.ficheros(.svg, que: .todo, transparente: false).first)
        XCTAssertTrue(String(decoding: svg, as: UTF8.self).contains("<svg"))
        XCTAssertEqual(modelo.nombreDeFichero, "Mi-lienzo")
        let url = URL(fileURLWithPath: "/tmp/a.png")
        XCTAssertEqual(ModeloEditorLienzo.numerada(url, 1, 3).lastPathComponent, "a-2.png")
        XCTAssertEqual(ModeloEditorLienzo.numerada(url, 0, 1).lastPathComponent, "a.png")
    }

    func testLaGraficaYLaTablaEntranPorElPuente() throws {
        let carpeta = try carpetaTemporal("figuras")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ed = try EditorLienzo.deFichero(ruta: carpeta.appendingPathComponent("f.excalidraw").path, crear: true)
        XCTAssertTrue(try ed.estamparGrafica(formulas: ["x^2"], xDesde: -3, xHasta: 3, yDesde: -1, yHasta: 9,
                                             escala: 30, centroX: 0, centroY: 0))
        XCTAssertNotNil(avisoDeGrafica(formulas: ["x^"], xDesde: -3, xHasta: 3, yDesde: -1, yHasta: 9, escala: 30))
        XCTAssertEqual(celdasDeTexto(texto: "a\tb\n1\t2"), [["a", "b"], ["1", "2"]])
        XCTAssertTrue(ed.estamparTabla(celdas: [["", ""], ["", ""]], cabecera: true, centroX: 0, centroY: 0))
        XCTAssertTrue(ed.estamparInstrumento(ejes: 2, centroX: 0, centroY: 0))
    }
}
