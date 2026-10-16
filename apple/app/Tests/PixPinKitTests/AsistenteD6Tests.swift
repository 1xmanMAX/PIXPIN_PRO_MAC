// Pruebas del asistente con los ajustes (D6): la nube por URLSession con un
// `URLProtocol` falso (nunca una API de pago), «Probar», las manos de la
// app (pedidos de tareas, leer un PDF, «¿seguro?»), el historial y el
// catalogo del modelo local.

import AppKit
import CoreText
import Foundation
import PixPinCore
import XCTest
@testable import PixPinKit

/// Claude de mentira: contesta a `api.anthropic.com` sin salir a la red.
final class ClaudeFalso: URLProtocol {
    /// Lo que se le pidio (cabeceras en minusculas y el cuerpo).
    nonisolated(unsafe) static var pedidos: [(cabeceras: [String: String], cuerpo: [String: Any])] = []
    nonisolated(unsafe) static var codigo = 200

    static func sse(_ eventos: [[String: Any]]) -> Data {
        var s = ""
        for e in eventos {
            let d = try! JSONSerialization.data(withJSONObject: e)
            s += "event: \(e["type"] as! String)\ndata: \(String(decoding: d, as: UTF8.self))\n\n"
        }
        return Data(s.utf8)
    }

    static func respuesta(_ texto: String) -> Data {
        sse([
            ["type": "message_start", "message": ["id": "msg_1", "type": "message", "role": "assistant",
                                                  "usage": ["input_tokens": 10, "output_tokens": 1]]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": texto]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": 5]],
            ["type": "message_stop"],
        ])
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.anthropic.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var cuerpo = Data()
        if let s = request.httpBodyStream {
            s.open()
            var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable {
                let n = s.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                cuerpo.append(buf, count: n)
            }
            s.close()
        } else if let b = request.httpBody {
            cuerpo = b
        }
        let json = (try? JSONSerialization.jsonObject(with: cuerpo)) as? [String: Any] ?? [:]
        var cab: [String: String] = [:]
        for (k, v) in request.allHTTPHeaderFields ?? [:] { cab[k.lowercased()] = v }
        ClaudeFalso.pedidos.append((cab, json))
        let codigo = ClaudeFalso.codigo
        let datos: Data
        if codigo != 200 {
            datos = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        } else if json["stream"] as? Bool == true {
            datos = ClaudeFalso.respuesta("Hola desde la nube.")
        } else {
            datos = Data(#"{"id":"msg_1","type":"message","model":"claude-haiku-5-5","content":[{"type":"text","text":"ok"}]}"#.utf8)
        }
        let r = HTTPURLResponse(url: request.url!, statusCode: codigo, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": codigo == 200 && json["stream"] as? Bool == true
                                    ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        // A trozos, como la red.
        var i = 0
        while i < datos.count {
            let fin = min(i + 97, datos.count)
            client?.urlProtocol(self, didLoad: datos.subdata(in: i ..< fin))
            i = fin
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AsistenteNubeTests: XCTestCase {
    override func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ClaudeFalso.self]
        TransporteHttps.configuracion = c
        TransporteHttps.instalar()
        ClaudeFalso.pedidos = []
        ClaudeFalso.codigo = 200
    }

    private func conClave() throws {
        XCTAssertTrue(LlaveroDelSistema.instalar(LlaveroDelSistema.dePruebas))
        do {
            try iaGuardarClave(proveedorId: "claude", clave: "sk-ant-api03-PRUEBA1234567890abcd")
        } catch {
            throw XCTSkip("No hay Llavero de inicio de sesion utilizable aqui: \(error)")
        }
    }

    private func ajustes(_ motor: String) -> AjustesIa {
        AjustesIa(motor: motor, modelo: "", pensar: false, respaldoLocal: false, mejorVista: false,
                  documentosALaNube: "", carpetaModelos: "", puertoUsuario: 9)
    }

    func testUnTurnoConClaudeVaPorUrlSessionYLlegaEnVivo() throws {
        try conClave()
        defer { try? iaBorrarClave(proveedorId: "claude") }
        XCTAssertTrue(hayTransporte())
        guard case let .nube(proveedor, _, modelo, conClave) = iaQueMotor(ajustes: ajustes("claude")) else {
            return XCTFail("la nube")
        }
        XCTAssertEqual(proveedor, "claude")
        XCTAssertTrue(conClave)
        XCTAssertTrue(modelo.hasPrefix("claude-"), modelo)
        let tandas = Tandas()
        let oyente = OyenteDelAsistente(alTexto: { tandas.meter($0) })
        let corte = CorteIa.nuevo()
        let manos = ManosDelAsistente(nucleo: nil, corte: corte) { _, r in r(false) }
        let peticion = PeticionIa(historial: [], pedido: "saluda", foto: nil, adjuntos: [], hoja: "", desfaseMs: 0)
        let r = try iaTurno(ajustes: ajustes("claude"), peticion: peticion, nucleo: nil, app: manos,
                            oyente: oyente, corte: corte)
        XCTAssertEqual(r.texto, "Hola desde la nube.")
        XCTAssertEqual(tandas.todas.joined(), r.texto)
        XCTAssertFalse(r.hoja.isEmpty, "la hoja de trabajo vuelve")
        let pedido = try XCTUnwrap(ClaudeFalso.pedidos.last)
        XCTAssertEqual(pedido.cabeceras["x-api-key"], "sk-ant-api03-PRUEBA1234567890abcd")
        XCTAssertEqual(pedido.cuerpo["model"] as? String, modelo)
        XCTAssertEqual(pedido.cuerpo["stream"] as? Bool, true)
        // La nube recibe el catalogo entero (sin lo que el Mac aun no hace).
        let nombres = (pedido.cuerpo["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertTrue(nombres.contains("anadir_tarea"), "\(nombres)")
        XCTAssertFalse(nombres.contains("hoja_a_lienzo"))
    }

    func testProbarLaClaveYUnaClaveMala() throws {
        try conClave()
        defer { try? iaBorrarClave(proveedorId: "claude") }
        let bien = try iaProbarClave(proveedorId: "claude")
        XCTAssertTrue(bien.contains("funciona"), bien)
        XCTAssertNotEqual(ClaudeFalso.pedidos.last?.cuerpo["stream"] as? Bool, true, "probar no hace streaming")
        // Caso negativo: el servidor no acepta la clave.
        ClaudeFalso.codigo = 401
        XCTAssertThrowsError(try iaProbarClave(proveedorId: "claude")) { e in
            XCTAssertTrue(ModeloAjustes.texto(de: e).contains("no acepta la clave"), ModeloAjustes.texto(de: e))
        }
        // Sin clave guardada, ni se llama.
        try iaBorrarClave(proveedorId: "claude")
        let antes = ClaudeFalso.pedidos.count
        XCTAssertThrowsError(try iaProbarClave(proveedorId: "claude"))
        XCTAssertEqual(ClaudeFalso.pedidos.count, antes)
    }

    @MainActor
    func testSinClaveLaBurbujaLoDice() async throws {
        XCTAssertTrue(LlaveroDelSistema.instalar(LlaveroDelSistema.dePruebas))
        try? iaBorrarClave(proveedorId: "deepseek")
        let dir = try carpetaTemporal("asistente-sin-clave")
        let almacen = try Almacen(raiz: dir, nombreDelAparato: "Mac de prueba")
        var a = try almacen.nucleo.ajustes()
        a.asistenteMotor = "deepseek"
        try almacen.nucleo.guardarAjustes(nuevos: a)
        let modelo = ModeloAsistente(almacen: almacen, puertoLlama: 9, usarApple: false)
        let motor = await modelo.comprobarMotor()
        XCTAssertEqual(motor, .nube("DeepSeek V4.1 Flash", conClave: false))
        await modelo.enviar("hola")
        XCTAssertEqual(modelo.burbujas.count, 2)
        XCTAssertTrue(modelo.burbujas[1].esAviso)
        XCTAssertTrue(modelo.burbujas[1].texto.contains("Falta la clave"), modelo.burbujas[1].texto)
    }
}

final class ManosDelAsistenteTests: XCTestCase {
    @MainActor
    func testLasTareasSeHacenAquiSinQuienAtiendaLosPedidos() async throws {
        let dir = try carpetaTemporal("asistente-tareas")
        let nucleo = try Nucleo.abrir(raiz: dir.path, nombreDelAparato: "Mac de prueba")
        let antes = PedidosDelAsistente.hacer
        PedidosDelAsistente.hacer = nil
        defer { PedidosDelAsistente.hacer = antes }
        let r = await ManosDelAsistente.hacerAqui(#"{"pixpin":1,"accion":"anadir_tarea","texto":"comprar pan"}"#, nucleo: nucleo)
        XCTAssertNil(r)
        let lista = try XCTUnwrap(nucleo.tareas(desfaseMs: 0).first)
        XCTAssertEqual(lista.tareas.first?.texto, "comprar pan")
        let marcar = #"{"pixpin":1,"accion":"marcar_tarea","codigo":"\#(lista.mensaje)","indice":0,"hecha":true}"#
        let marcada = await ManosDelAsistente.hacerAqui(marcar, nucleo: nucleo)
        XCTAssertNil(marcada)
        XCTAssertEqual(try nucleo.tareas(desfaseMs: 0).first?.tareas.first?.hecha, true)
        // Casos negativos: lo que no se sabe hacer aqui se dice.
        let otra = await ManosDelAsistente.hacerAqui(#"{"pixpin":1,"accion":"capturar"}"#, nucleo: nucleo)
        XCTAssertTrue(otra?.contains("capturar") ?? false)
        let rota = await ManosDelAsistente.hacerAqui("roto", nucleo: nucleo)
        XCTAssertNotNil(rota)
        // Lo que no es de tareas va a quien atiende `pixpinmax://`.
        XCTAssertTrue(ManosDelAsistente.esDeTareas(#"{"pixpin":1,"accion":"marcar_tarea"}"#))
        XCTAssertFalse(ManosDelAsistente.esDeTareas(#"{"pixpin":1,"accion":"anadir_tarea","codigo":"x"}"#))
        XCTAssertFalse(ManosDelAsistente.esDeTareas(#"{"pixpin":1,"accion":"nota_nueva"}"#))
        XCTAssertNotNil(ManosDelAsistente.aLaApp(#"{"accion":"nota_nueva"}"#), "sin version no se entiende")
    }

    func testConfirmarEsperaElSiYParadoEsUnNo() async throws {
        let corte = CorteIa.nuevo()
        let si = ManosDelAsistente(nucleo: nil, corte: corte) { _, responder in responder(true) }
        let r = await Task.detached { si.confirmar(pregunta: "¿Borro la lista?") }.value
        XCTAssertTrue(r)
        // Nadie contesta y se pulsa «Parar»: no.
        let nadie = ManosDelAsistente(nucleo: nil, corte: corte) { _, _ in }
        corte.cancelar()
        let r2 = await Task.detached { nadie.confirmar(pregunta: "¿Seguro?") }.value
        XCTAssertFalse(r2)
    }

    func testLeeElTextoDeUnPdf() throws {
        let dir = try carpetaTemporal("asistente-pdf")
        let pdf = dir.appendingPathComponent("acta.pdf")
        var caja = CGRect(x: 0, y: 0, width: 400, height: 300)
        let ctx = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &caja, nil))
        for pagina in ["Primera pagina: se aprueba el presupuesto de la obra.", "Segunda pagina: firmas de los asistentes."] {
            ctx.beginPDFPage(nil)
            let linea = CTLineCreateWithAttributedString(NSAttributedString(string: pagina, attributes: [.font: NSFont.systemFont(ofSize: 12)]))
            ctx.textPosition = CGPoint(x: 20, y: 150)
            CTLineDraw(linea, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        let manos = ManosDelAsistente(nucleo: nil, corte: CorteIa.nuevo()) { _, r in r(false) }
        let todo = try manos.leerTexto(ruta: pdf.path, paginas: [])
        XCTAssertTrue(todo.contains("presupuesto") && todo.contains("firmas"), todo)
        let segunda = try manos.leerTexto(ruta: pdf.path, paginas: [RangoPaginas(desde: 2, hasta: 2)])
        XCTAssertFalse(segunda.contains("presupuesto"))
        XCTAssertTrue(segunda.contains("[página 2]"))
        XCTAssertThrowsError(try manos.leerTexto(ruta: dir.appendingPathComponent("no-esta.pdf").path, paginas: []))
    }
}

final class HistorialYModelosTests: XCTestCase {
    func testLasConversacionesSeGuardanYSeLeen() throws {
        let dir = try carpetaTemporal("asistente-historial")
        let h = HistorialAsistente(carpeta: dir)
        var c = Conversacion()
        XCTAssertEqual(c.rotulo, "Conversación nueva")
        h.guardar(c)
        XCTAssertTrue(h.todas().isEmpty, "una vacia no se guarda")
        var b = ModeloAsistente.Burbuja(delUsuario: false, texto: "Listo.", lienzo: "{}")
        b.pensamiento = "pienso"
        b.llamando = "Dibujando…"
        c.burbujas = [ModeloAsistente.Burbuja(delUsuario: true, texto: "dibuja una casa\ncon jardin"), b]
        c.hoja = #"{"objetivo":"casa"}"#
        h.guardar(c)
        let leida = try XCTUnwrap(h.todas().first)
        XCTAssertEqual(leida.id, c.id)
        XCTAssertEqual(leida.rotulo, "dibuja una casa")
        XCTAssertEqual(leida.burbujas[1].pensamiento, "pienso")
        XCTAssertNil(leida.burbujas[1].llamando, "lo de en vivo no se guarda")
        XCTAssertEqual(leida.hoja, c.hoja)
        h.borrar(c.id)
        XCTAssertTrue(h.todas().isEmpty)
        // Una burbuja guardada sin los campos nuevos se sigue leyendo.
        let vieja = #"{"id":"\#(UUID().uuidString)","delUsuario":false,"texto":"hola"}"#
        let b2 = try JSONDecoder().decode(ModeloAsistente.Burbuja.self, from: Data(vieja.utf8))
        XCTAssertEqual(b2.texto, "hola")
        XCTAssertTrue(b2.citas.isEmpty && b2.herramientas.isEmpty)
    }

    func testElCatalogoLocalEsElDeWindowsConElMotorDelMac() throws {
        let dir = try carpetaTemporal("asistente-modelos")
        let c = iaCatalogoLocal(carpeta: dir.path)
        XCTAssertTrue(c.motor.url.contains("macos"))
        XCTAssertFalse(c.motor.listo)
        let qwen = try XCTUnwrap(c.modelos.first { $0.id == "qwen3.5-2b" })
        XCTAssertFalse(qwen.opcional)
        XCTAssertEqual(qwen.ficheros.count, 2)
        XCTAssertTrue(c.modelos.contains { $0.id == "gemma-4-e2b" && $0.opcional })
        // Sin nada bajado y sin servidor del usuario, no hay local.
        let a = AjustesIa(motor: "", modelo: "", pensar: nil, respaldoLocal: true, mejorVista: false,
                          documentosALaNube: "", carpetaModelos: dir.path, puertoUsuario: 9)
        XCTAssertEqual(iaQueMotor(ajustes: a), .ninguno)
        // Un pid apuntado que no es nuestro no se mata.
        XCTAssertFalse(iaLimpiarHuerfanos(carpeta: dir.path))
    }

    @MainActor
    func testLaFotoSeReduceParaElModelo() throws {
        let dir = try carpetaTemporal("asistente-foto")
        let png = dir.appendingPathComponent("grande.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1000, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: png)
        let foto = try XCTUnwrap(ModeloAsistente.foto(png.path))
        XCTAssertEqual(foto.mime, "image/jpeg")
        let img = try XCTUnwrap(NSBitmapImageRep(data: foto.bytes))
        XCTAssertEqual(max(img.pixelsWide, img.pixelsHigh), 768)
        XCTAssertNil(ModeloAsistente.foto(dir.appendingPathComponent("no.png").path))
        let modelo = ModeloAsistente(almacen: nil, usarApple: false)
        modelo.adjuntar([png])
        XCTAssertEqual(modelo.pendientes.first?.esImagen, true)
    }
}
