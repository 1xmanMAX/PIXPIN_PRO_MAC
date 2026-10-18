// Pruebas de E4: el panel de la barra de menus (el buscador de acciones,
// los favoritos y su `[bandeja]` en el TOML), los grupos de ventanas y los
// grupos de pines ocultos. Las mismas que `centro_bandeja/acciones.rs`,
// `pixpin_store::bandeja` y `grupos_ventanas.rs` de Windows, mas las del Mac.

import AppKit
import Foundation
@testable import PixPinKit
import XCTest

final class BandejaE4Tests: XCTestCase {
    // MARK: El buscador

    private func conTitulos() -> [(AccionBandeja, String)] {
        [(.comando(.capturarRegion), "Capturar"),
         (.galeria, "Galería de capturas"),
         (.comando(.capturarConScroll), "Captura larga con scroll"),
         (.tareas, "Tareas")]
    }

    func testBuscarSinTildesYLoQueEmpiezaAsiPrimero() {
        XCTAssertEqual(ReglasBandeja.buscar("galeria", en: conTitulos()), [.galeria])
        XCTAssertEqual(ReglasBandeja.buscar("CAPT", en: conTitulos()),
                       [.comando(.capturarRegion), .comando(.capturarConScroll), .galeria],
                       "primero las que empiezan por lo escrito; «Galería de capturas» al final")
        XCTAssertEqual(ReglasBandeja.buscar("larga scroll", en: conTitulos()), [.comando(.capturarConScroll)])
    }

    func testCasoNegativoBuscarLoQueNoHayONada() {
        XCTAssertTrue(ReglasBandeja.buscar("xyzzy", en: conTitulos()).isEmpty)
        XCTAssertTrue(ReglasBandeja.buscar("   ", en: conTitulos()).isEmpty, "una consulta vacia no es «todas»")
        XCTAssertTrue(ReglasBandeja.buscar("capturar tareas", en: conTitulos()).isEmpty, "cada palabra cuenta")
    }

    func testLosNombresVanYVuelvenYSalirNoEsFavorito() {
        for a in AccionBandeja.todas() {
            XCTAssertEqual(AccionBandeja.desde(nombre: a.nombre), a, "\(a)")
            XCTAssertFalse(a.titulo.isEmpty, "\(a) sin titulo")
            XCTAssertFalse(a.simbolo.isEmpty)
        }
        XCTAssertNil(AccionBandeja.desde(nombre: "salir"), "Salir no se puede poner de favorito")
        XCTAssertNil(AccionBandeja.desde(nombre: "recibir-del-movil"))
        XCTAssertNil(AccionBandeja.desde(nombre: "no-existe"))
        // Los nombres de Windows, tal cual.
        XCTAssertEqual(AccionBandeja.galeria.nombre, "galeria-capturas")
        XCTAssertEqual(AccionBandeja.gruposVentanas.nombre, "grupos-ventanas")
        XCTAssertEqual(AccionBandeja.comando(.pinearPortapapeles).titulo, "Pinear copiado")
    }

    func testTodasSinLoQueElMacNoSabeHacer() {
        let todas = AccionBandeja.todas { $0 != .alternarPasoDeClics }
        XCTAssertFalse(todas.contains(.comando(.alternarPasoDeClics)))
        XCTAssertTrue(todas.contains(.comando(.capturarRegion)))
        XCTAssertTrue(todas.contains(.tareas), "las ventanas siempre")
    }

    func testFavoritosSinRepetirNiPasarDelTope() {
        XCTAssertEqual(ReglasBandeja.favoritos(de: ["anotar", "anotar", "no-existe", "tareas"]),
                       [.comando(.anotar), .tareas])
        var f = Array(AccionBandeja.todas().prefix(AccionBandeja.tope))
        let fuera = AccionBandeja.todas()[AccionBandeja.tope]
        XCTAssertFalse(ReglasBandeja.alternarFavorito(&f, fuera), "caso negativo: lleno, no entra")
        XCTAssertTrue(ReglasBandeja.alternarFavorito(&f, AccionBandeja.todas()[0]), "quitar siempre se puede")
        XCTAssertTrue(ReglasBandeja.alternarFavorito(&f, fuera))
        XCTAssertTrue(f.contains(fuera))
        XCTAssertEqual(ReglasBandeja.favoritos(de: AccionBandeja.deFabrica),
                       [.comando(.pinearPortapapeles), .comando(.anotar), .comando(.pinearEnVivo)])
    }

    func testLosInterruptoresDejanElPanelAbiertoYCapturarMiraLaPantalla() {
        XCTAssertFalse(AccionBandeja.comando(.alternarPines).cierraElPanel)
        XCTAssertFalse(AccionBandeja.comando(.silenciarAtajos).cierraElPanel)
        XCTAssertTrue(AccionBandeja.comando(.capturarRegion).cierraElPanel)
        XCTAssertTrue(AccionBandeja.comando(.capturarRegion).miraLaPantalla)
        XCTAssertTrue(AccionBandeja.comando(.anotar).miraLaPantalla)
        XCTAssertFalse(AccionBandeja.tareas.miraLaPantalla, "caso negativo: abrir una ventana no")
    }

    func testHaceCuanto() {
        let ahora: Int64 = 10_000_000_000
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora - 10_000, ahora: ahora), "ahora mismo")
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora - 5 * 60_000, ahora: ahora), "hace 5 min")
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora - 3 * 3_600_000, ahora: ahora), "hace 3 h")
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora - 30 * 3_600_000, ahora: ahora), "ayer")
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora - 4 * 86_400_000, ahora: ahora), "hace 4 días")
        XCTAssertEqual(ReglasBandeja.haceCuanto(ahora + 99, ahora: ahora), "ahora mismo", "un reloj adelantado no da negativos")
        XCTAssertEqual(ReglasBandeja.estadoSincro(ultima: 0, ahora: ahora), "Sin sincronizar todavía")
    }

    // MARK: [bandeja] favoritos

    func testFavoritosSeGuardanYSeLeenSinTocarLoDemas() {
        let antes = "# mis ajustes\ntema_cosmos = true\n\n[sincro]\npresencia = false # puerta\n"
        let despues = FavoritosBandeja.enTexto(antes, ["anotar", "tareas"])
        XCTAssertTrue(despues.contains("# mis ajustes"))
        XCTAssertTrue(despues.contains("presencia = false # puerta"))
        XCTAssertEqual(FavoritosBandeja.deTexto(despues), ["anotar", "tareas"])
        // Otra vez: se sustituye, no se duplica.
        let otra = FavoritosBandeja.enTexto(despues, ["galeria-capturas"])
        XCTAssertEqual(FavoritosBandeja.deTexto(otra), ["galeria-capturas"])
        XCTAssertEqual(otra.components(separatedBy: "[bandeja]").count, 2)
        XCTAssertEqual(otra.components(separatedBy: "favoritos =").count, 2)
    }

    func testFavoritosEscritosAManoEnVariasLineasYConLaSeccionEnMedio() {
        let toml = """
        [bandeja] # el panel
        otra = 1
        favoritos = [
          "anotar", # el lapiz
          'tareas',
          "anotar",
        ]

        [sincro]
        favoritos = ["no-es-este"]
        """
        XCTAssertEqual(FavoritosBandeja.deTexto(toml), ["anotar", "tareas"], "sin repetir, comillas simples y comentarios")
        let nuevo = FavoritosBandeja.enTexto(toml, ["pinear"])
        XCTAssertEqual(FavoritosBandeja.deTexto(nuevo), ["pinear"])
        XCTAssertTrue(nuevo.contains("otra = 1"))
        XCTAssertTrue(nuevo.contains("favoritos = [\"no-es-este\"]"), "la de otra seccion no se toca")
        XCTAssertFalse(nuevo.contains("el lapiz"), "la lista vieja entera se va")
    }

    func testCasoNegativoSinSeccionNoHayListaYVaciaNoEsDeFabrica() throws {
        XCTAssertNil(FavoritosBandeja.deTexto("idioma = \"es-ES\"\n"))
        XCTAssertNil(FavoritosBandeja.deTexto("[bandeja]\nancho = 3\n"), "seccion sin favoritos")
        let vacia = FavoritosBandeja.enTexto("", [])
        XCTAssertEqual(FavoritosBandeja.deTexto(vacia), [], "quitar todos es una eleccion")
        // Sin fichero, los de fabrica; con el, lo guardado.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-bandeja-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ruta = dir.appendingPathComponent("pixpinmax.toml")
        XCTAssertEqual(FavoritosBandeja.leer(ruta), AccionBandeja.deFabrica)
        try FavoritosBandeja.guardar(ruta, [])
        XCTAssertEqual(FavoritosBandeja.leer(ruta), [])
        try FavoritosBandeja.guardar(ruta, ["tareas", "lecciones"])
        XCTAssertEqual(FavoritosBandeja.leer(ruta), ["tareas", "lecciones"])
    }

    // MARK: Grupos de ventanas

    private func lector(_ ruta: String, x: Double = 0) -> VentanaDeGrupo {
        VentanaDeGrupo(clase: .lector(ruta: ruta), colocacion: ColocacionVentana(x: x, y: 0, ancho: 800, alto: 600))
    }

    func testGuardarUnGrupoSustituyeElDelMismoNombreYVaPrimero() {
        var g = ReglasGruposVentanas.conGrupo([], nombre: "Tesis", ventanas: [lector("/a.pdf")], ahora: 1)
        g = ReglasGruposVentanas.conGrupo(g, nombre: "Obra", ventanas: [lector("/b.pdf")], ahora: 2)
        g = ReglasGruposVentanas.conGrupo(g, nombre: "  tesis ", ventanas: [lector("/c.pdf"), lector("/c.pdf", x: 9)], ahora: 3)
        XCTAssertEqual(g.map(\.nombre), ["tesis", "Obra"])
        XCTAssertEqual(g[0].ventanas.count, 1, "lo mismo abierto dos veces se guarda una")
        XCTAssertEqual(g[0].id, "g-3")
    }

    func testCasoNegativoSinNombreYTope() {
        var g: [GrupoVentanas] = []
        g = ReglasGruposVentanas.conGrupo(g, nombre: "   ", ventanas: [], ahora: 1)
        XCTAssertEqual(g[0].nombre, "Grupo 1")
        for i in 0..<20 { g = ReglasGruposVentanas.conGrupo(g, nombre: "n\(i)", ventanas: [], ahora: Int64(i + 2)) }
        XCTAssertEqual(g.count, ReglasGruposVentanas.tope)
        XCTAssertEqual(g.first?.nombre, "n19")
        XCTAssertEqual(ReglasGruposVentanas.sinGrupo(g, id: g[0].id).count, ReglasGruposVentanas.tope - 1)
        XCTAssertEqual(ReglasGruposVentanas.sinGrupo(g, id: "no-existe").count, ReglasGruposVentanas.tope)
    }

    func testLasEntradasDelMenu() {
        let g = ReglasGruposVentanas.conGrupo([], nombre: "Tesis", ventanas: [lector("/a"), lector("/b")], ahora: 7)
        XCTAssertEqual(ReglasGruposVentanas.entradas(abiertas: 0, grupos: []).map(\.que), [.nada])
        let e = ReglasGruposVentanas.entradas(abiertas: 3, grupos: g)
        XCTAssertEqual(e.map(\.titulo), ["Guardar las 3 ventanas abiertas como grupo…", "Abrir «Tesis» · 2", "Borrar «Tesis»"])
        XCTAssertEqual(e.map(\.que), [.guardar, .abrir("g-7"), .borrar("g-7")])
        XCTAssertEqual(ReglasGruposVentanas.entradas(abiertas: 1, grupos: []).first?.titulo,
                       "Guardar la ventana abierta como grupo…")
    }

    func testLosGruposSeGuardanEnLaRaizYUnFicheroRotoNoTumbaNada() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-grupos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        XCTAssertEqual(ReglasGruposVentanas.leer(raiz), [])
        let ventanas = [
            VentanaDeGrupo(clase: .lienzo(proyecto: "p1", referencia: "dibujo-3"),
                           colocacion: ColocacionVentana(x: 10, y: 20, ancho: 1000, alto: 700, minimizada: true)),
            VentanaDeGrupo(clase: .nota(proyecto: "p1", mensaje: "m9", ruta: nil),
                           colocacion: ColocacionVentana(x: 0, y: 0, ancho: 760, alto: 820)),
            VentanaDeGrupo(clase: .nota(proyecto: nil, mensaje: nil, ruta: "/x/nota.md"),
                           colocacion: ColocacionVentana(x: 0, y: 0, ancho: 760, alto: 820)),
            lector("/docs/a.pdf"),
        ]
        let g = ReglasGruposVentanas.conGrupo([], nombre: "Todo", ventanas: ventanas, ahora: 5)
        try ReglasGruposVentanas.escribir(raiz, g)
        XCTAssertEqual(ReglasGruposVentanas.leer(raiz), g)
        let texto = try String(contentsOf: raiz.appendingPathComponent("grupos-de-ventanas.json"), encoding: .utf8)
        XCTAssertTrue(texto.contains("\"clase\" : \"lienzo\""), texto)
        try Data("no es json".utf8).write(to: raiz.appendingPathComponent("grupos-de-ventanas.json"))
        XCTAssertEqual(ReglasGruposVentanas.leer(raiz), [], "caso negativo: roto, sin grupos")
    }

    @MainActor
    func testSoloSeGuardanLasVentanasDeLienzoLectorYNota() {
        let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertNil(GruposVentanas.clase(de: w), "una ventana cualquiera no")
        w.identifier = NSUserInterfaceItemIdentifier("p1\u{0}dibujo")
        XCTAssertNil(GruposVentanas.clase(de: w), "sin ser del gestor de lienzos, tampoco")
        w.delegate = VentanasDeLienzo.compartidas
        XCTAssertEqual(GruposVentanas.clase(de: w), .lienzo(proyecto: "p1", referencia: "dibujo"))
        w.delegate = nil
    }

    // MARK: Grupos de pines ocultos

    func testOcultarUnGrupoDejaSusPinesEnElAlmacenYNoVuelvenAlArrancar() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-ocultos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try AlmacenPines(raiz: raiz)
        let g = PinGuardado(x: 1, y: 2, ancho: 3, alto: 4, escalaPorCien: 100)
        let uno = try a.guardarNota("uno", origen: "nota", pin: g)
        let dos = try a.guardarNota("dos", origen: "nota", pin: g)
        let tres = try a.guardarNota("tres", origen: "nota", pin: g)
        let rojo = try XCTUnwrap(try a.ponerGrupo(uno, color: .rojo))
        try a.ponerGrupo(dos, color: .rojo)
        XCTAssertEqual(a.grupoDe(uno)?.color, .rojo)
        XCTAssertNil(a.grupoDe(tres))
        XCTAssertTrue(a.gruposOcultos.isEmpty)

        try a.ponerGrupoOculto(rojo, true)
        XCTAssertEqual(a.abiertas.map(\.id), [tres], "los del grupo oculto no vuelven al arrancar")
        XCTAssertEqual(a.entrada(uno)?.pin, g, "pero siguen con su sitio")
        // Y asi queda escrito.
        let otra = try AlmacenPines(raiz: raiz)
        XCTAssertEqual(otra.gruposOcultos.map(\.cuantos), [2])
        XCTAssertEqual(otra.gruposOcultos.first?.grupo.color, .rojo)

        try otra.ponerGrupoOculto(rojo, false)
        XCTAssertEqual(Set(otra.abiertas.map(\.id)), [uno, dos, tres])
        XCTAssertThrowsError(try otra.ponerGrupoOculto(999, true), "caso negativo: un grupo que no existe")
    }

    func testLaEtiquetaDeUnGrupoOculto() {
        XCTAssertEqual(GestorPines.GrupoOculto(id: 1, color: 0, cuantos: 3).etiqueta, "● Rojo (3)")
        XCTAssertEqual(GestorPines.GrupoOculto(id: 2, color: 7, cuantos: 1).etiqueta, "● Rosa (1)")
    }

    // MARK: El panel

    @MainActor
    func testElPanelBuscaEligeYEscDeshacePorPasos() {
        let atajos = GestorAtajos()
        atajos.poner(.capturarRegion) {}
        atajos.poner(.grabarGif) {}
        var pedidas: [AccionBandeja] = []
        var cerrado = false
        let m = ModeloBandeja(atajos: atajos, nucleo: nil, sincro: nil)
        m.alPedir = { pedidas.append($0) }
        m.alCerrar = { cerrado = true }
        XCTAssertFalse(m.enLista)
        m.intro()
        XCTAssertEqual(pedidas, [.comando(.capturarRegion)], "sin buscar, Intro captura")
        m.consulta = "galer"
        XCTAssertTrue(m.enLista)
        XCTAssertEqual(m.filas.first, .galeria)
        m.mover(5)
        XCTAssertEqual(m.elegida, m.filas.count - 1, "las flechas no salen de la lista")
        m.mover(-9)
        XCTAssertEqual(m.elegida, 0)
        m.intro()
        XCTAssertEqual(pedidas.last, .galeria)
        XCTAssertFalse(m.filas.contains(.comando(.alternarPasoDeClics)), "lo que no se sabe hacer no sale")
        m.escape()
        XCTAssertEqual(m.consulta, "")
        XCTAssertFalse(cerrado, "el primer Esc borra lo buscado")
        m.empezarAEditar()
        XCTAssertEqual(m.filas.count, AccionBandeja.todas { atajos.disponible($0) }.count, "eligiendo, todas")
        m.escape()
        XCTAssertFalse(m.editando)
        XCTAssertFalse(cerrado)
        m.escape()
        XCTAssertTrue(cerrado, "y el ultimo cierra")
    }

    @MainActor
    func testAlEditarUnClicMarcaYDesmarcaFavoritos() {
        let m = ModeloBandeja(atajos: GestorAtajos(), nucleo: nil, sincro: nil)
        var pedidas = 0
        m.alPedir = { _ in pedidas += 1 }
        m.empezarAEditar()
        m.consulta = "tareas"
        let antes = m.favoritos
        m.activarFila(0)
        XCTAssertEqual(m.favoritos, antes + [.tareas])
        m.activarFila(0)
        XCTAssertEqual(m.favoritos, antes)
        XCTAssertEqual(pedidas, 0, "elegir favoritos no hace la accion")
        m.activarFila(99)
        XCTAssertEqual(m.favoritos, antes, "caso negativo: una fila que no hay")
    }

    func testCuandoEnLasMiniaturas() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let ahora = Date(timeIntervalSince1970: 1_760_000_000)
        let ayer = Int64((ahora.timeIntervalSince1970 - 86_400) * 1000)
        XCTAssertEqual(VistaBandeja.cuando(ayer, ahora: ahora, calendario: cal), "ayer")
        XCTAssertFalse(VistaBandeja.cuando(Int64(ahora.timeIntervalSince1970 * 1000), ahora: ahora, calendario: cal).isEmpty)
    }
}
