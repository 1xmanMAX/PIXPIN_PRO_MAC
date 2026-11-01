// Las capturas caducadas a la Papelera, saltar a un mensaje desde Buscar,
// las claves en el Llavero y las acciones de Atajos (el asistente en vivo,
// con la nube falsa de `AsistenteD6Tests`). Cruzan el puente de verdad sobre
// carpetas temporales; nada pide permisos de pantalla ni de micro.

import Foundation
import Network
import PixPinCore
@testable import PixPinKit
import XCTest

// MARK: - Capturas caducadas

final class BarrenderoCapturasTests: XCTestCase {
    private func viejo(_ url: URL, dias: Double) throws {
        let fecha = Date().addingTimeInterval(-dias * 86_400)
        try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: url.path)
    }

    /// Una carpeta de datos con tres capturas: una vieja, una vieja pero
    /// conservada y una de hoy. El registro dice que la caducidad se
    /// estreno hace mucho (como un Windows que ya la usaba).
    private func preparar(_ nombre: String) throws -> (Nucleo, URL, URL) {
        let raiz = try carpetaTemporal(nombre)
        let datos = raiz.appendingPathComponent("datos", isDirectory: true)
        let nucleo = try Nucleo.abrir(raiz: datos.path, nombreDelAparato: "Mac de prueba")
        let capturas = URL(fileURLWithPath: nucleo.carpetaCapturas(), isDirectory: true)
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        for n in ["vieja.png", "guardada.png", "nueva.png"] {
            try Data("png".utf8).write(to: capturas.appendingPathComponent(n))
        }
        try viejo(capturas.appendingPathComponent("vieja.png"), dias: 8)
        try viejo(capturas.appendingPathComponent("guardada.png"), dias: 30)
        // El mismo fichero que Windows y Android (`capturas-caducidad.json`).
        let registro = #"{"desde": 0, "conservadas": ["guardada.png", "borrada-a-mano.png"]}"#
        try Data(registro.utf8).write(to: datos.appendingPathComponent("capturas-caducidad.json"))
        return (nucleo, raiz, capturas)
    }

    func testLasCaducadasVanALaPapeleraYLasConservadasSeQuedan() throws {
        let (nucleo, raiz, capturas) = try preparar("barrer")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let papelera = raiz.appendingPathComponent("papelera-falsa", isDirectory: true)
        try FileManager.default.createDirectory(at: papelera, withIntermediateDirectories: true)

        let barrendero = BarrenderoCapturas(nucleo: nucleo)
        barrendero.dias = { 7 }
        barrendero.tirar = { url in
            try FileManager.default.moveItem(at: url, to: papelera.appendingPathComponent(url.lastPathComponent))
        }
        let hecho = barrendero.barrer()
        XCTAssertEqual(hecho.idas, ["vieja.png"])
        XCTAssertTrue(hecho.fallos.isEmpty)
        XCTAssertEqual(hecho.olvidadas, 1, "la conservada borrada a mano se olvida")
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturas.appendingPathComponent("vieja.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: papelera.appendingPathComponent("vieja.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: capturas.appendingPathComponent("guardada.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: capturas.appendingPathComponent("nueva.png").path))
        // La galeria ya no la ensena.
        let pagina = try nucleo.galeria(desde: 0, cuantos: 10, dias: 7, desfaseMs: 0)
        XCTAssertEqual(Set(pagina.capturas.map(\.nombre)), ["guardada.png", "nueva.png"])

        // Otra vez: no queda nada que barrer.
        XCTAssertEqual(barrendero.barrer(), BarrenderoCapturas.Barrido())
    }

    func testConElAjusteACeroNoSeVaNinguna() throws {
        let (nucleo, raiz, capturas) = try preparar("barrer-cero")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let barrendero = BarrenderoCapturas(nucleo: nucleo)
        barrendero.dias = { 0 }
        barrendero.tirar = { _ in XCTFail("no tenia que tirar nada") }
        XCTAssertTrue(barrendero.barrer().idas.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capturas.appendingPathComponent("vieja.png").path))
        // Y con un plazo largo, tampoco la de hace 8 dias.
        barrendero.dias = { 30 }
        XCTAssertTrue(barrendero.barrer().idas.isEmpty)
    }

    func testElPlazoSaleDePixpinmaxToml() throws {
        let (nucleo, raiz, _) = try preparar("barrer-toml")
        defer { try? FileManager.default.removeItem(at: raiz) }
        var tres = nucleo.ajustesDeFabrica()
        tres.diasCaducidad = 3
        try nucleo.guardarAjustes(nuevos: tres)
        XCTAssertEqual(BarrenderoCapturas(nucleo: nucleo).dias(), 3)
    }

    func testDeVerdadALaPapeleraDelMac() throws {
        let (nucleo, raiz, capturas) = try preparar("barrer-papelera")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let barrendero = BarrenderoCapturas(nucleo: nucleo)
        barrendero.dias = { 7 }
        let hecho = barrendero.barrer()
        if !hecho.fallos.isEmpty {
            throw XCTSkip("Esta maquina no tiene Papelera para la carpeta temporal: \(hecho.fallos)")
        }
        XCTAssertEqual(hecho.idas, ["vieja.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturas.appendingPathComponent("vieja.png").path))
    }
}

// MARK: - Saltar a un mensaje desde Buscar

@MainActor
final class SaltoAMensajeTests: XCTestCase {
    func testLaVentanaContieneElMensajeYNoSeSaleDelChat() {
        let n: UInt64 = 60
        XCTAssertEqual(ventanaDeSalto(posicion: 500, total: 1000, tam: n).desde, 470)
        XCTAssertEqual(ventanaDeSalto(posicion: 500, total: 1000, tam: n).cuantos, 60)
        // Al principio y al final se corre hacia dentro.
        XCTAssertEqual(ventanaDeSalto(posicion: 0, total: 1000, tam: n).desde, 0)
        XCTAssertEqual(ventanaDeSalto(posicion: 10, total: 1000, tam: n).desde, 0)
        XCTAssertEqual(ventanaDeSalto(posicion: 999, total: 1000, tam: n).desde, 940)
        XCTAssertEqual(ventanaDeSalto(posicion: 990, total: 1000, tam: n).cuantos, 60)
        // Un chat corto entra entero.
        XCTAssertEqual(ventanaDeSalto(posicion: 5, total: 10, tam: n).desde, 0)
        XCTAssertEqual(ventanaDeSalto(posicion: 5, total: 10, tam: n).cuantos, 10)
        // Casos negativos: chat vacio, posicion de mas, pagina de cero.
        XCTAssertEqual(ventanaDeSalto(posicion: 3, total: 0, tam: n).cuantos, 0)
        XCTAssertEqual(ventanaDeSalto(posicion: 5000, total: 1000, tam: n).desde, 940)
        XCTAssertEqual(ventanaDeSalto(posicion: 7, total: 1000, tam: 0).cuantos, 1)
        // Siempre contiene la posicion pedida.
        for p in stride(from: UInt64(0), to: 1000, by: 37) {
            let v = ventanaDeSalto(posicion: p, total: 1000, tam: n)
            XCTAssertTrue(v.desde <= p && p < v.desde + UInt64(v.cuantos), "posicion \(p)")
        }
    }

    func testSaltarCargaSuPaginaLasDeAlrededorYVuelveAlFinalAlEscribir() async throws {
        let raiz = try carpetaTemporal("salto")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let chat = try almacen.nucleo.crearChat(nombre: "Largo").id
        for i in 0 ..< 200 {
            _ = try almacen.nucleo.escribirNota(chat: chat, texto: "nota \(i)", respondeA: nil)
        }
        await almacen.abrir(chat: chat, en: 100)
        let pagina = try XCTUnwrap(almacen.mensajes[chat])
        XCTAssertEqual(pagina.count, Int(Almacen.tamPagina))
        XCTAssertTrue(pagina.contains { $0.texto == "nota 100" })
        XCTAssertTrue(almacen.quedanAnteriores(chat: chat))
        XCTAssertTrue(almacen.quedanPosteriores(chat: chat))

        // Bajar: la pagina siguiente se pega detras, sin huecos.
        await almacen.cargarPosteriores(chat: chat)
        let bajado = try XCTUnwrap(almacen.mensajes[chat])
        XCTAssertEqual(bajado.count, 2 * Int(Almacen.tamPagina))
        XCTAssertEqual(bajado.map(\.texto), (70 ..< 190).map { "nota \($0)" })
        // Subir: la anterior delante.
        await almacen.cargarAnteriores(chat: chat)
        XCTAssertEqual(almacen.mensajes[chat]?.first?.texto, "nota 10")

        // Escribir con un hueco al final: se vuelve a la ultima pagina.
        let m = await almacen.escribir(nota: "la nueva", en: chat)
        XCTAssertNotNil(m)
        XCTAssertFalse(almacen.quedanPosteriores(chat: chat))
        XCTAssertEqual(almacen.mensajes[chat]?.last?.texto, "la nueva")
        XCTAssertEqual(almacen.mensajes[chat]?.count, Int(Almacen.tamPagina))

        // Caso negativo: con todo cargado no hay nada despues.
        await almacen.cargarPosteriores(chat: chat)
        XCTAssertEqual(almacen.mensajes[chat]?.last?.texto, "la nueva")
    }

    func testBuscarPideElSaltoConLaPosicionDelMensaje() async throws {
        let raiz = try carpetaTemporal("salto-buscar")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let chat = try almacen.nucleo.crearChat(nombre: "Notas").id
        for i in 0 ..< 90 {
            _ = try almacen.nucleo.escribirNota(chat: chat, texto: i == 12 ? "la aguja" : "paja \(i)", respondeA: nil)
        }
        let r = try XCTUnwrap(almacen.nucleo.buscar(consulta: "aguja", desde: 0, cuantos: 10, busqueda: nil)
            .resultados.first { $0.clase == .mensaje })
        let posicion = try XCTUnwrap(r.posicion)
        XCTAssertEqual(posicion, 12)
        await almacen.abrir(chat: chat, en: posicion)
        XCTAssertTrue(almacen.mensajes[chat]?.contains { $0.id == r.mensaje } == true)
        // Cerca del principio la pagina empieza en el primero.
        XCTAssertEqual(almacen.mensajes[chat]?.first?.texto, "paja 0")
    }
}

// MARK: - Llavero

final class LlaveroDelSistemaTests: XCTestCase {
    func testIdaYVueltaPorElLlaveroYPorElPuente() throws {
        // Un servicio propio de la prueba: las claves de verdad no se tocan.
        let llavero = LlaveroDelSistema(sufijo: ".pruebas-\(UUID().uuidString)")
        do {
            try llavero.guardar(servicio: "PixPinMax.asistente", cuenta: "prueba", clave: "uno")
        } catch {
            throw XCTSkip("No hay Llavero de inicio de sesion utilizable aqui: \(error)")
        }
        XCTAssertEqual(llavero.leer(servicio: "PixPinMax.asistente", cuenta: "prueba"), "uno")
        // Guardar otra vez la sustituye.
        try llavero.guardar(servicio: "PixPinMax.asistente", cuenta: "prueba", clave: "dos ñ")
        XCTAssertEqual(llavero.leer(servicio: "PixPinMax.asistente", cuenta: "prueba"), "dos ñ")
        try llavero.borrar(servicio: "PixPinMax.asistente", cuenta: "prueba")
        // Casos negativos: borrada no se lee, y borrar lo que no esta vale.
        XCTAssertNil(llavero.leer(servicio: "PixPinMax.asistente", cuenta: "prueba"))
        XCTAssertNoThrow(try llavero.borrar(servicio: "PixPinMax.asistente", cuenta: "prueba"))

        // Por el puente: Rust guarda y lee la clave en el llavero de las
        // pruebas (el nucleo instala uno por proceso: el mismo para todas).
        let puente = LlaveroDelSistema.dePruebas
        XCTAssertTrue(LlaveroDelSistema.instalar(puente))
        try iaGuardarClave(proveedorId: "claude", clave: "  sk-ant-api03-PRUEBA1234567890abcd  ")
        XCTAssertTrue(iaHayClave(proveedorId: "claude"))
        XCTAssertEqual(iaClaveEnmascarada(proveedorId: "claude"), "sk-ant-…abcd")
        XCTAssertEqual(puente.leer(servicio: "PixPinMax.asistente", cuenta: "claude"),
                       "sk-ant-api03-PRUEBA1234567890abcd", "recortada, en su servicio y cuenta")
        try iaBorrarClave(proveedorId: "claude")
        XCTAssertFalse(iaHayClave(proveedorId: "claude"))
        XCTAssertThrowsError(try iaGuardarClave(proveedorId: "nadie", clave: "x"))
    }
}

// MARK: - Asistente en vivo

/// Lo que llega por el oyente, apuntado desde el hilo del turno.
final class Tandas: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var lista: [String] = []
    func meter(_ t: String) {
        cerrojo.lock()
        lista.append(t)
        cerrojo.unlock()
    }

    var todas: [String] {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return lista
    }
}

// MARK: - Acciones de Atajos

@MainActor
final class AccionesAppTests: XCTestCase {
    func testNotaYBuscarComoDesdeAtajos() async throws {
        let raiz = try carpetaTemporal("acciones")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        let chat = try almacen.nucleo.crearChat(nombre: "Compras").id
        let acciones = AccionesApp()
        var capturas = 0
        acciones.registrar(almacen: almacen, sincro: nil, capturar: { capturas += 1 })

        let proyectos = try await acciones.proyectos()
        XCTAssertTrue(proyectos.contains(AccionesApp.Proyecto(id: chat, nombre: "Compras")))
        try await acciones.escribirNota("  leche y pan  ", en: chat)
        let encontrados = try await acciones.buscar("leche")
        XCTAssertTrue(encontrados.contains { $0.detalle.contains("leche") }, "\(encontrados)")
        try acciones.capturarZona()
        XCTAssertEqual(capturas, 1)

        // Casos negativos: nota vacia, y sincronizar sin sincronizador.
        do {
            try await acciones.escribirNota("   ", en: chat)
            XCTFail("una nota vacia no se escribe")
        } catch let fallo as AccionesApp.Fallo {
            XCTAssertEqual(fallo, .vacio)
        }
        do {
            _ = try await acciones.sincronizarAhora()
            XCTFail("sin sincronizador no se sincroniza")
        } catch let fallo as AccionesApp.Fallo {
            XCTAssertEqual(fallo, .sinApp)
        }
    }
}
