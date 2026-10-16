// Los atajos globales (C1): el catalogo de Windows, leer y escribir
// «Ctrl+Alt+X», los choques con macOS y entre comandos, lo guardado en
// UserDefaults (y lo de antes, solo capturar), regiones y apps ignoradas.
// Sin tocar Carbon (`registrar: false`).

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
@testable import PixPinKit
import XCTest

final class AtajosTests: XCTestCase {
    private typealias C = AtajoGlobal.Combinacion

    private func defaultsNuevos() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "pixpin-atajos-\(UUID().uuidString)"))
    }

    // MARK: El catalogo

    func testElCatalogoTieneLosNombresDeWindows() {
        // Los 27 de `pixpin-store/src/comandos.rs` y grabar (solo Mac).
        let windows = ["capturar-region", "capturar-y-copiar", "capturar-con-scroll", "capturar-y-anotar",
                       "grabar-gif", "capturar-ultima-region", "cuentagotas", "pinear", "pinear-en-vivo",
                       "pinear-portapapeles", "anotar", "anotar-congelada", "pinear-seleccion",
                       "capturar-con-retardo", "silenciar-atajos", "alternar-paso-de-clics", "alternar-pines",
                       "restaurar-ultimo-pin", "cerrar-todos-los-pines", "copiar-texto", "ventana-encima",
                       "abrir-chat", "abrir-ajustes", "recibir-del-movil", "salir", "sincronizar", "buscar"]
        for n in windows { XCTAssertNotNil(ComandoAtajo.desde(nombre: n), n) }
        XCTAssertEqual(ComandoAtajo.allCases.count, windows.count + 1)
        XCTAssertEqual(Set(ComandoAtajo.allCases.map(\.titulo)).count, ComandoAtajo.allCases.count, "titulos repetidos")
        // Caso negativo: un nombre que no existe no se inventa.
        XCTAssertNil(ComandoAtajo.desde(nombre: "capturar"))
    }

    func testDeFabricaSoloCapturarPinesYGrabarYSinChoques() {
        let con = ComandoAtajo.allCases.filter { $0.deFabrica != nil }
        XCTAssertEqual(Set(con), [.capturarRegion, .alternarPines, .grabarPantalla])
        XCTAssertEqual(ComandoAtajo.capturarRegion.deFabrica?.texto, "Ctrl+Alt+X")
        XCTAssertEqual(ComandoAtajo.alternarPines.deFabrica?.texto, "Ctrl+2")
        XCTAssertNil(EnlacesAtajos().choque())
    }

    // MARK: El texto

    func testElTextoVaYVuelve() throws {
        XCTAssertEqual(C.capturar.texto, "Ctrl+Alt+X")
        XCTAssertEqual(C.capturar.descripcion, "⌃⌥X")
        let todos = C(tecla: UInt32(kVK_F5), modificadores: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(todos.texto, "Ctrl+Alt+Shift+Cmd+F5")
        XCTAssertEqual(todos.descripcion, "⌃⌥⇧⌘F5")
        XCTAssertEqual(C(texto: todos.texto), todos)
        // Sin distinguir mayusculas, con espacios y con los nombres del Mac.
        XCTAssertEqual(C(texto: " ctrl + option + x "), .capturar)
        XCTAssertEqual(C(texto: "Control+Opt+X"), .capturar)
        XCTAssertEqual(C(texto: "Win+Alt+1")?.modificadores, UInt32(cmdKey | optionKey))
        XCTAssertEqual(C(texto: "Ctrl+Alt+F20")?.tecla, UInt32(kVK_F20))
    }

    func testTextosQueNoSonAtajos() {
        XCTAssertNil(C(texto: ""))
        XCTAssertNil(C(texto: "X"), "sin modificador")
        XCTAssertNil(C(texto: "Shift+X"), "Mayusculas sola no basta")
        XCTAssertNil(C(texto: "Ctrl+Ctrl+X"), "modificador repetido")
        XCTAssertNil(C(texto: "Ctrl+Alt+"), "sin tecla")
        XCTAssertNil(C(texto: "Ctrl+Alt+Intro"), "Intro no vale de tecla final")
        XCTAssertNil(C(texto: "Ctrl+Hiper+X"))
        XCTAssertNil(C(texto: "Ctrl+Alt+F21"))
        XCTAssertFalse(C.teclaValida(UInt32(kVK_Return)))
        XCTAssertFalse(C.teclaValida(UInt32(kVK_Space)))
        XCTAssertTrue(C.teclaValida(UInt32(kVK_ANSI_9)))
    }

    func testLosModificadoresDeUnaPulsacion() {
        XCTAssertEqual(C.modificadores(de: [.command, .shift]), UInt32(cmdKey | shiftKey))
        XCTAssertEqual(C.modificadores(de: [.control, .option, .capsLock]), UInt32(controlKey | optionKey))
    }

    func testElAtajoDelMenu() throws {
        let m = try XCTUnwrap(C.capturar.enMenu)
        XCTAssertEqual(m.key, KeyEquivalent("x"))
        XCTAssertEqual(m.modifiers, [.control, .option])
        XCTAssertNotNil(C(tecla: UInt32(kVK_F3), modificadores: UInt32(optionKey)).enMenu)
    }

    // MARK: Choques

    func testLosDeMacOSNoSeDejan() throws {
        for texto in ["Shift+Cmd+3", "Shift+Cmd+4", "Shift+Cmd+5", "Ctrl+Shift+Cmd+4",
                      "Cmd+Q", "Cmd+H", "Cmd+M", "Shift+Cmd+N", "Alt+Cmd+H", "Alt+Cmd+M", "Alt+Cmd+D",
                      "Ctrl+Cmd+Q", "Ctrl+Cmd+F"] {
            let c = try XCTUnwrap(C(texto: texto), texto)
            XCTAssertEqual(ChoqueAtajo.de(c)?.bloquea, true, texto)
        }
    }

    func testLosDudososSeAvisanYLosLibresPasan() throws {
        let escritorio = try XCTUnwrap(C(texto: "Ctrl+2"))
        XCTAssertEqual(ChoqueAtajo.de(escritorio)?.bloquea, false, "⌃2 es Escritorio 2: aviso, no bloqueo")
        XCTAssertEqual(ChoqueAtajo.de(try XCTUnwrap(C(texto: "Ctrl+F2")))?.bloquea, false)
        for libre in ["Ctrl+Alt+X", "Ctrl+Alt+1", "Ctrl+Alt+Shift+S", "Ctrl+Alt+Cmd+P", "Alt+Cmd+P"] {
            XCTAssertNil(ChoqueAtajo.de(try XCTUnwrap(C(texto: libre))), libre)
        }
    }

    func testDosComandosConElMismoAtajoChocan() throws {
        var e = EnlacesAtajos()
        let a = try XCTUnwrap(C(texto: "Ctrl+Alt+C"))
        e.poner(.capturarYCopiar, a)
        XCTAssertNil(e.choque())
        XCTAssertEqual(e.quien(tiene: a), .capturarYCopiar)
        XCTAssertNil(e.quien(tiene: a, salvo: .capturarYCopiar))
        e.poner(.pinear, a)
        let par = try XCTUnwrap(e.choque())
        XCTAssertEqual(Set([par.0, par.1]), [.capturarYCopiar, .pinear])
    }

    // MARK: La tabla (como `[comandos]` de Windows)

    func testLaTablaComoLaDeWindows() throws {
        var e = EnlacesAtajos()
        XCTAssertTrue(e.tabla.isEmpty, "lo de fabrica no se escribe")
        let raros = e.aplicar(tabla: ["capturar-y-copiar": "Ctrl+Alt+C", "alternar-pines": "",
                                      "no-existe": "Ctrl+Alt+Q", "pinear": "Ctrl+Nada"])
        XCTAssertEqual(e.atajo(de: .capturarYCopiar), C(texto: "Ctrl+Alt+C"))
        XCTAssertNil(e.atajo(de: .alternarPines), "cadena vacia = sin atajo")
        XCTAssertEqual(e.atajo(de: .capturarRegion), .capturar, "lo no nombrado sigue de fabrica")
        XCTAssertEqual(Set(raros), ["no-existe", "pinear = Ctrl+Nada"])
        XCTAssertEqual(e.tabla, ["capturar-y-copiar": "Ctrl+Alt+C", "alternar-pines": ""])
        // Volver al de fabrica lo quita de la tabla.
        e.poner(.alternarPines, .alternarPines)
        XCTAssertEqual(e.tabla, ["capturar-y-copiar": "Ctrl+Alt+C"])
    }

    // MARK: El gestor

    @MainActor
    func testElGestorGuardaYLee() throws {
        let d = try defaultsNuevos()
        let g = GestorAtajos(defaults: d, registrar: false)
        XCTAssertEqual(g.enlaces.atajo(de: .capturarRegion), .capturar)
        let s = try XCTUnwrap(C(texto: "Ctrl+Alt+S"))
        XCTAssertEqual(g.cambiar(.capturarConScroll, a: s), .hecho)
        XCTAssertEqual(g.cambiar(.alternarPines, a: nil), .hecho)
        XCTAssertEqual(d.dictionary(forKey: GestorAtajos.claveComandos) as? [String: String],
                       ["capturar-con-scroll": "Ctrl+Alt+S", "alternar-pines": ""])
        let otro = GestorAtajos(defaults: d, registrar: false)
        XCTAssertEqual(otro.enlaces.atajo(de: .capturarConScroll), s)
        XCTAssertNil(otro.enlaces.atajo(de: .alternarPines))
        otro.restablecerTodos()
        XCTAssertNil(d.object(forKey: GestorAtajos.claveComandos))
        XCTAssertEqual(GestorAtajos(defaults: d, registrar: false).enlaces.atajo(de: .alternarPines), .alternarPines)
    }

    @MainActor
    func testElGestorRechazaChoques() throws {
        let g = GestorAtajos(defaults: try defaultsNuevos(), registrar: false)
        guard case .rechazado = g.cambiar(.pinear, a: .capturar) else { return XCTFail("ya es de capturar") }
        guard case .rechazado = g.cambiar(.pinear, a: C(texto: "Shift+Cmd+4")) else { return XCTFail("es de macOS") }
        guard case .hechoConAviso = g.cambiar(.pinear, a: C(texto: "Ctrl+5")) else { return XCTFail("aviso") }
        XCTAssertEqual(g.enlaces.atajo(de: .pinear), C(texto: "Ctrl+5"))
        XCTAssertEqual(g.restablecer(.pinear), .hecho)
        XCTAssertNil(g.enlaces.atajo(de: .pinear))
    }

    @MainActor
    func testSeMigraElAtajoDeCapturarDeAntes() throws {
        let d = try defaultsNuevos()
        d.set(kVK_ANSI_S, forKey: GestorAtajos.claveViejaTecla)
        d.set(cmdKey | shiftKey | controlKey, forKey: GestorAtajos.claveViejaModificadores)
        let g = GestorAtajos(defaults: d, registrar: false)
        XCTAssertEqual(g.enlaces.atajo(de: .capturarRegion)?.texto, "Ctrl+Shift+Cmd+S")
        // Al guardar algo, lo viejo se va y queda en la tabla nueva.
        g.cambiar(.buscar, a: C(texto: "Ctrl+Alt+F"))
        XCTAssertNil(d.object(forKey: GestorAtajos.claveViejaTecla))
        XCTAssertEqual(GestorAtajos(defaults: d, registrar: false).enlaces.atajo(de: .capturarRegion)?.texto,
                       "Ctrl+Shift+Cmd+S")
    }

    @MainActor
    func testLoGuardadoQueChocaSeQuedaSinAtajoYSeDice() throws {
        let d = try defaultsNuevos()
        d.set(["pinear": "Ctrl+Alt+X"], forKey: GestorAtajos.claveComandos)
        let g = GestorAtajos(defaults: d, registrar: false)
        XCTAssertNil(g.enlaces.choque())
        XCTAssertEqual(g.enlaces.atajo(de: .capturarRegion), .capturar)
        XCTAssertNil(g.enlaces.atajo(de: .pinear))
        XCTAssertFalse(g.noEntendidos.isEmpty)
    }

    @MainActor
    func testSoloSeEnsenanLosQueTienenQuienLosHaga() throws {
        let g = GestorAtajos(defaults: try defaultsNuevos(), registrar: false)
        XCTAssertFalse(g.disponible(.cuentagotas))
        var hecho = 0
        g.poner(.cuentagotas) { hecho += 1 }
        XCTAssertTrue(g.disponibles.contains(.cuentagotas))
        g.ejecutar(.cuentagotas)
        g.ejecutar(.pinear) // sin accion: no hace nada
        XCTAssertEqual(hecho, 1)
        XCTAssertEqual(g.atajoActivo(de: .capturarRegion), .capturar)
        g.silenciar(true)
        XCTAssertNil(g.atajoActivo(de: .capturarRegion), "silenciados no se ensenan en el menu")
    }

    // MARK: Regiones

    @MainActor
    func testLasRegionesSeGuardanConSuAtajo() throws {
        let d = try defaultsNuevos()
        let g = GestorAtajos(defaults: d, registrar: false)
        g.anadir(RegionGuardada(nombre: "panel", x: 10, y: 20, ancho: 300, alto: 200))
        let id = try XCTUnwrap(g.regiones.first?.id)
        XCTAssertEqual(g.cambiarAtajo(region: id, a: C(texto: "Ctrl+Alt+1")), .hecho)
        guard case .rechazado = g.cambiarAtajo(region: id, a: .capturar) else { return XCTFail("es de capturar") }
        guard case .rechazado = g.cambiar(.pinear, a: C(texto: "Ctrl+Alt+1")) else { return XCTFail("es de la region") }
        g.renombrarRegion(id, a: "  barra  ")
        let leidas = GestorAtajos(defaults: d, registrar: false).regiones
        XCTAssertEqual(leidas.count, 1)
        XCTAssertEqual(leidas.first?.nombre, "barra")
        XCTAssertEqual(leidas.first?.atajo, "Ctrl+Alt+1")
        XCTAssertEqual(leidas.first?.rectCG, CGRect(x: 10, y: 20, width: 300, height: 200))
        // Con las claves de `[[regiones]]` de Windows.
        let json = try XCTUnwrap(String(data: try XCTUnwrap(d.data(forKey: GestorAtajos.claveRegiones)), encoding: .utf8))
        for clave in ["\"nombre\"", "\"x\"", "\"y\"", "\"ancho\"", "\"alto\"", "\"atajo\""] {
            XCTAssertTrue(json.contains(clave), clave)
        }
        g.quitarRegion(id)
        XCTAssertNil(d.data(forKey: GestorAtajos.claveRegiones))
    }

    func testRegionDesdeAppKitYVuelta() {
        // Pantalla principal de 1000 de alto: en AppKit la y va hacia arriba.
        let r = RegionGuardada.desde(appKit: CGRect(x: 100, y: 700, width: 200, height: 100),
                                     altoPantallaPrincipal: 1000, nombre: "arriba")
        XCTAssertEqual(r.rectCG, CGRect(x: 100, y: 200, width: 200, height: 100))
        XCTAssertEqual(r.rectAppKit(altoPantallaPrincipal: 1000), CGRect(x: 100, y: 700, width: 200, height: 100))
        XCTAssertTrue(r.esUtil)
        XCTAssertFalse(RegionGuardada(nombre: "vacia", x: 0, y: 0, ancho: 0, alto: 10).esUtil)
    }

    // MARK: Apps ignoradas

    func testAppsIgnoradas() {
        let lista = ["1Password", "com.apple.keychainaccess", "Banca.app"]
        XCTAssertTrue(ProgramasIgnorados.estaEnLaLista(nombre: "1password", paquete: nil, identificador: nil, lista: lista))
        XCTAssertTrue(ProgramasIgnorados.estaEnLaLista(nombre: "Acceso a Llaveros", paquete: "Keychain Access.app",
                                                       identificador: "com.apple.keychainaccess", lista: lista))
        XCTAssertTrue(ProgramasIgnorados.estaEnLaLista(nombre: "Banca", paquete: nil, identificador: nil, lista: lista))
        XCTAssertFalse(ProgramasIgnorados.estaEnLaLista(nombre: "Safari", paquete: "Safari.app",
                                                        identificador: "com.apple.Safari", lista: lista))
        XCTAssertFalse(ProgramasIgnorados.estaEnLaLista(nombre: nil, paquete: nil, identificador: nil, lista: lista))
    }

    @MainActor
    func testLaListaDeIgnoradosSeGuarda() throws {
        let d = try defaultsNuevos()
        let g = GestorAtajos(defaults: d, registrar: false)
        g.ignorar("1Password")
        g.ignorar("1password.app") // la misma
        g.ignorar("  ")
        XCTAssertEqual(g.ignorados, ["1Password"])
        XCTAssertEqual(GestorAtajos(defaults: d, registrar: false).ignorados, ["1Password"])
        g.dejarDeIgnorar("1Password")
        XCTAssertNil(d.object(forKey: GestorAtajos.claveIgnorar))
    }
}
