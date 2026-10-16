// Quien hace los pedidos (C2): los nombres de proyecto por su id, el cuadro
// de confirmar de los enlaces, el menu del Dock (la Jump List de Windows),
// los Servicios del Finder y lo que declaran los Info.plist.

import Foundation
@testable import PixPinKit
import XCTest

@MainActor
final class PedidosC2Tests: XCTestCase {
    private let proyectos: [(id: String, nombre: String, guardados: Bool)] = [
        ("g", "Mensajes guardados", true), ("pr-1", "Obra Lima", false), ("pr-2", "Tesis", false),
    ]

    func testElNombreDelProyectoSeCambiaPorSuId() throws {
        let v = HacerPedidos.ponerIds([
            Pedido("chat", ["texto": .texto("x"), "proyecto": .texto("obra lima")]),
            Pedido("chat", ["texto": .texto("x"), "proyecto": .texto("Mensajes guardados")]),
            Pedido("chat", ["texto": .texto("x"), "proyecto": .texto("guardados")]),
            Pedido("abrir", ["que": .objeto(["tipo": .texto("proyecto"), "proyecto": .texto(" TESIS ")])]),
            Pedido("chat", ["texto": .texto("x"), "proyecto": .texto("pr-2")]),
        ], proyectos: proyectos)
        XCTAssertEqual(v[0]["proyecto"], .texto("pr-1"))
        XCTAssertEqual(v[1]["proyecto"], .nulo)
        XCTAssertEqual(v[2]["proyecto"], .nulo)
        XCTAssertEqual(v[3]["que"]?.objeto?["proyecto"], .texto("pr-2"))
        XCTAssertEqual(v[4]["proyecto"], .texto("pr-2"))
        // Caso negativo: uno que no existe se deja (al hacerlo se dice), y
        // sin `proyecto` no se inventa ninguno.
        let otro = HacerPedidos.ponerIds([Pedido("chat", ["proyecto": .texto("Cocina")]), Pedido("capturar")],
                                         proyectos: proyectos)
        XCTAssertEqual(otro[0]["proyecto"], .texto("Cocina"))
        XCTAssertNil(otro[1]["proyecto"])
    }

    func testLasFichasSeQuitanDelTexto() {
        XCTAssertEqual(HacerPedidos.sinFichas("el plano [archivo 01] y la foto [img 01]"), "el plano y la foto")
        XCTAssertEqual(HacerPedidos.sinFichas("[img 01]"), "")
        XCTAssertEqual(HacerPedidos.sinFichas("sin fichas [img x]"), "sin fichas [img x]")
    }

    /// Un `HacerPedidos` de prueba: apunta lo que pregunta y lo que dice.
    private func hacedor(confirmar si: Bool) -> (HacerPedidos, () -> [String], () -> [String]) {
        let h = HacerPedidos()
        var preguntas: [String] = []
        var avisos: [String] = []
        h.confirmar = { preguntas.append($0); return si }
        h.avisar = { avisos.append($0) }
        h.registrar(almacen: nil, sincro: nil)
        return (h, { preguntas }, { avisos })
    }

    func testUnEnlaceQueNoEsInofensivoPreguntaYUnNoNoHaceNada() throws {
        let (h, preguntas, avisos) = hacedor(confirmar: false)
        h.hacer(try Enlaces.leer("pixpinmax://grabar?nombre=Reunion", firmas: nil))
        XCTAssertEqual(preguntas().count, 1)
        XCTAssertTrue(preguntas()[0].contains("grabar"))
        XCTAssertTrue(preguntas()[0].contains("micrófono"))
        XCTAssertTrue(avisos().isEmpty)
        // Lo inofensivo no pregunta.
        h.hacer(try Enlaces.leer("pixpinmax://capturas", firmas: nil))
        XCTAssertEqual(preguntas().count, 1)
    }

    func testCasoNegativoUnaRutaDeRedNoPasaNiFirmada() throws {
        let (h, preguntas, avisos) = hacedor(confirmar: true)
        let firmas = FirmaEnlaces(clave: [UInt8](repeating: 3, count: 32))
        let url = try firmas.firmar("pixpinmax://abrir?ruta=/net/atacante/x.pdf")
        h.hacer(try Enlaces.leer(url, firmas: firmas))
        XCTAssertTrue(preguntas().isEmpty)
        XCTAssertEqual(avisos().count, 1)
        XCTAssertTrue(avisos()[0].contains("No se hizo nada"))
        // Un enlace firmado de la casa no pregunta.
        h.hacer(try Enlaces.leer(try firmas.firmar("pixpinmax://sincronizar/todos"), firmas: firmas))
        XCTAssertTrue(preguntas().isEmpty)
    }

    func testLoQueLlegaAntesDeRegistrarSeHaceAlRegistrar() throws {
        let h = HacerPedidos()
        var preguntas: [String] = []
        h.confirmar = { preguntas.append($0); return false }
        h.avisar = { _ in }
        h.hacer(try Enlaces.leer("pixpinmax://grabar", firmas: nil))
        XCTAssertTrue(preguntas.isEmpty)
        h.registrar(almacen: nil, sincro: nil)
        XCTAssertEqual(preguntas.count, 1)
    }

    func testElMenuDelDockEsLaJumpList() throws {
        let chats: [(id: String, nombre: String, guardados: Bool, archivado: Bool)] = [
            ("g", "Mensajes guardados", true, false), ("b", "Obra Lima", false, false),
            ("c", "  ", false, false), ("x", "Archivado", false, true), ("d", "Charla", false, false),
            ("a", "Tesis con un nombre larguisimo que no cabe", false, false), ("e", "Viejo", false, false),
        ]
        let (fijas, recientes) = MenuDelDock.entradas(chats: chats)
        XCTAssertEqual(fijas.map(\.titulo), ["Capturar", "Mensajes guardados", "Proyectos", "Sincronizar"])
        XCTAssertEqual(fijas.map(\.pedido), [
            try Pedido.de(json: #"{"pixpin":1,"accion":"capturar"}"#),
            try Pedido.de(json: #"{"pixpin":1,"accion":"abrir","que":{"tipo":"proyecto","proyecto":null}}"#),
            try Pedido.de(json: #"{"pixpin":1,"accion":"ventana_principal"}"#),
            try Pedido.de(json: #"{"pixpin":1,"accion":"ventana","cual":"sincronizar"}"#),
        ])
        // Los tres ultimos tocados, sin guardados, sin nombre ni archivados.
        XCTAssertEqual(recientes.map(\.titulo), ["Obra Lima", "Charla", "Tesis con un nombre larg"])
        XCTAssertEqual(recientes[0].pedido,
                       try Pedido.de(json: #"{"pixpin":1,"accion":"abrir","que":{"tipo":"proyecto","proyecto":"b"}}"#))
        // Caso negativo: sin proyectos, solo las fijas.
        XCTAssertTrue(MenuDelDock.entradas(chats: []).recientes.isEmpty)
    }

    func testLosServiciosDelFinderSonLosVerbos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-servicios-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("foto.png").path
        let plano = dir.appendingPathComponent("--plano.pdf").path
        for f in [foto, plano] { FileManager.default.createFile(atPath: f, contents: Data([1])) }
        guard case let .success(chat)? = ServiciosFinder.orden(verbo: "chat", rutas: [foto, plano]),
              case let .pedidos(v) = chat.orden else { return XCTFail() }
        XCTAssertEqual(v, [Pedido("chat", ["texto": .texto(""), "proyecto": .nulo,
                                           "imagenes": .textos([foto]), "archivos": .textos([plano])])])
        XCTAssertEqual(chat.origen, .consola)
        guard case let .success(p)? = ServiciosFinder.orden(verbo: "asistente", rutas: [plano]) else { return XCTFail() }
        XCTAssertEqual(p.orden, .preguntar(rutas: [plano], proyecto: nil))
        // Cada servicio del Info.plist tiene su verbo y su metodo.
        for s in ServiciosFinder.servicios {
            XCTAssertNotNil(Verbos.fila(s.verbo), s.verbo)
            XCTAssertTrue(ServiciosFinder.compartidos.responds(to: NSSelectorFromString(s.mensaje + ":userData:error:")), s.mensaje)
        }
        // Caso negativo: copiar texto de algo que no es una imagen.
        guard case let .failure(f)? = ServiciosFinder.orden(verbo: "copiar-texto", rutas: [plano]) else { return XCTFail() }
        XCTAssertEqual(f.codigo, FalloOrden.Codigo.fallo)
    }

    func testLosDosInfoPlistDeclaranLoMismo() throws {
        let aqui = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        let apple = aqui.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let rutas = [apple.appendingPathComponent("app/Recursos/Info.plist"),
                     apple.appendingPathComponent("xcode/Soporte/App-Info.plist")]
        var vistos: [NSDictionary] = []
        for r in rutas {
            let d = try XCTUnwrap(NSDictionary(contentsOf: r), r.path)
            let esquemas = (d["CFBundleURLTypes"] as? [[String: Any]])?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            XCTAssertEqual(esquemas, ["pixpinmax"], r.path)
            let tipos = (d["CFBundleDocumentTypes"] as? [[String: Any]])?.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] } ?? []
            for t in ["public.image", "public.movie", "public.audio", "com.adobe.pdf"] { XCTAssertTrue(tipos.contains(t), t) }
            let mensajes = (d["NSServices"] as? [[String: Any]])?.compactMap { $0["NSMessage"] as? String } ?? []
            XCTAssertEqual(mensajes, ServiciosFinder.servicios.map(\.mensaje), r.path)
            vistos.append(d)
        }
        for clave in ["CFBundleURLTypes", "CFBundleDocumentTypes", "NSServices", "UTImportedTypeDeclarations"] {
            XCTAssertEqual(vistos[0][clave] as? NSArray, vistos[1][clave] as? NSArray, clave)
        }
    }
}
