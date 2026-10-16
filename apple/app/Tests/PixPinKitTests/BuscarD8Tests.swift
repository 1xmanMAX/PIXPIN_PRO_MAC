// «Buscar en PixPin» completo (D8): las pruebas de `buscar_todo/modelo.rs`
// de Windows pasadas a `EstadoBuscar`, las letras rapidas y el modelo con
// un nucleo de verdad (documentos, capturas, recientes).

import Foundation
@testable import PixPinKit
import PixPinCore
import XCTest

private func res(_ clase: ClaseDeResultado, _ titulo: String, clave: String? = nil, chat: String? = nil,
                 mensaje: String? = nil, posicion: UInt64? = nil, ruta: String? = nil,
                 tipo: String = "", hecha: Bool = false) -> ResultadoBusqueda {
    ResultadoBusqueda(clase: clase, chat: chat, nombreChat: chat == nil ? "" : "Obra", mensaje: mensaje,
                      posicion: posicion, tarea: clase == .tarea ? 0 : nil, hecha: hecha, momento: nil,
                      tipo: tipo, titulo: titulo, fragmento: "", cuando: 0,
                      clave: clave ?? "\(clase)/\(titulo)", ruta: ruta, leccion: nil, puntos: 0,
                      resaltado: [], dentro: false, bytes: 0, conservada: false, diasQueQuedan: nil, crudo: "")
}

private func captura(_ nombre: String) -> ResultadoBusqueda {
    res(.captura, nombre, clave: "captura/\(nombre)", ruta: "/datos/capturas/\(nombre)", tipo: "IMAGEN")
}

/// Los resultados de la maqueta de Windows («grie»), hechos a mano: el
/// nucleo ya los da ordenados por puntos.
private func mezcla() -> EstadoBuscar {
    var e = EstadoBuscar()
    e.consulta = "grie"
    e.poner([
        captura("grieta.png"),
        res(.fichero, "Informe de grietas.pdf", chat: "c1", mensaje: "m1", posicion: 3, ruta: "/x.pdf"),
        res(.tarea, "Revisar la grieta", chat: "c1", mensaje: "m2", posicion: 4),
        res(.leccion, "Sellar las grietas"),
        captura("grieta2.png"),
    ])
    return e
}

final class EstadoBuscarTests: XCTestCase {
    func testCadaResultadoVaASuPestana() {
        XCTAssertEqual(PestanaBuscar.de(.captura), .capturas)
        XCTAssertEqual(PestanaBuscar.de(.leccion), .lecciones)
        XCTAssertEqual(PestanaBuscar.de(.tarea), .tareas)
        for c in [ClaseDeResultado.chat, .mensaje, .fichero] {
            XCTAssertEqual(PestanaBuscar.de(c), .archivos, "\(c)")
        }
        XCTAssertEqual(PestanaBuscar.de(.momento), .timeline)
        // Caso negativo: una accion no se cuela en Archivos.
        XCTAssertEqual(FilaBuscar.accion(.capturar).pestana, .acciones)
    }

    func testLasCuentasDeLasPestanasSumanTodo() {
        let e = mezcla()
        // Los cinco resultados y «Apuntar tarea: grie».
        XCTAssertEqual(e.cuenta(.todo), 6)
        XCTAssertEqual(e.cuenta(.capturas), 2)
        XCTAssertEqual(e.cuenta(.archivos), 1)
        XCTAssertEqual(e.cuenta(.tareas), 1)
        XCTAssertEqual(e.cuenta(.lecciones), 1)
        XCTAssertEqual(e.cuenta(.acciones), 1)
        XCTAssertEqual(e.cuenta(.timeline), 0)
        let suma = PestanaBuscar.allCases.dropFirst().map { e.cuenta($0) }.reduce(0, +)
        XCTAssertEqual(suma, e.cuenta(.todo))
    }

    func testEnTodoElMejorArribaYElRestoPorGrupos() {
        var e = mezcla()
        let titulos: [String] = e.lineas().map {
            switch $0 {
            case let .cabecera(g): return "# \(g.rotulo)"
            case let .fila(f): return e.titulo(de: f)
            }
        }
        XCTAssertEqual(titulos, [
            "# Mejor resultado", "grieta.png",
            "# Tareas y lecciones", "Revisar la grieta", "Sellar las grietas",
            "# Archivos", "Informe de grietas.pdf",
            "# Capturas", "grieta2.png",
            "# Acciones", "Apuntar tarea: grie",
        ])
        XCTAssertEqual(e.visibles().count, 6)
        // Caso negativo: en otra pestana no hay cabeceras ni lo de otras.
        _ = e.ir(a: .capturas)
        XCTAssertEqual(e.lineas().count, 2)
        XCTAssertTrue(e.lineas().allSatisfy { if case .fila = $0 { return true }; return false })
    }

    func testFlechasMuevenSinSalirseYTabCambiaDePestana() {
        var e = mezcla()
        XCTAssertFalse(e.mover(-1), "arriba del todo no se mueve")
        XCTAssertEqual(e.tecla(.abajo), .nada)
        XCTAssertEqual(e.filaElegida.map(e.titulo), "Revisar la grieta")
        for _ in 0 ..< 20 { _ = e.tecla(.abajo) }
        XCTAssertEqual(e.filaElegida.map(e.titulo), "Apuntar tarea: grie")
        _ = e.tecla(.rePag)
        XCTAssertEqual(e.elegido, 0, "RePag sube seis")
        // Tab avanza, Mayus+Tab vuelve, y se da la vuelta.
        XCTAssertEqual(e.tecla(.tab), .nada, "con algo escrito solo se filtra")
        XCTAssertEqual(e.pestana, .archivos)
        XCTAssertEqual(e.elegido, 0, "al cambiar de pestana se empieza arriba")
        _ = e.tecla(.tab, .mayus)
        _ = e.tecla(.tab, .mayus)
        XCTAssertEqual(e.pestana, .acciones)
    }

    func testConLaCajaVaciaCadaPestanaVuelveAPreguntar() {
        var e = EstadoBuscar()
        XCTAssertTrue(e.esInicio)
        XCTAssertEqual(e.tecla(.tab), .buscar)
        XCTAssertEqual(PestanaBuscar.tareas.clases, [.tarea])
        XCTAssertEqual(PestanaBuscar.capturas.clases, [.captura])
        // Caso negativo: «Todo» no limita las clases.
        XCTAssertTrue(PestanaBuscar.todo.clases.isEmpty)
    }

    func testEscapeCierraElMenuLuegoBorraYLuegoCierra() {
        var e = mezcla()
        XCTAssertTrue(e.abrirMenu([.copiar]))
        XCTAssertEqual(e.tecla(.escape), .nada)
        XCTAssertNil(e.menu)
        XCTAssertEqual(e.tecla(.escape), .vaciar)
        e.consulta = ""
        XCTAssertEqual(e.tecla(.escape), .cerrar)
    }

    func testIntroHaceLoPrincipalYComandoIntroVaAlChat() {
        var e = EstadoBuscar()
        e.consulta = "rev"
        let tarea = res(.tarea, "Revisar", chat: "p1", mensaje: "LST", posicion: 2)
        e.poner([tarea])
        let f = FilaBuscar.resultado(tarea)
        XCTAssertEqual(e.tecla(.intro), .hacer(f, verEnChat: false))
        XCTAssertEqual(e.tecla(.intro, .comando), .hacer(f, verEnChat: true))
        XCTAssertEqual(e.tecla(.c, .comando), .copiar(f))
        // Con letras elegidas en la caja, ⌘C es de la caja.
        XCTAssertEqual(e.tecla(.c, .comando, textoElegido: true), .noEsMia)
        // Caso negativo: ⌥↩ sin fichero no hace nada, y Supr en algo que no
        // es una captura sigue siendo de la caja.
        XCTAssertEqual(e.tecla(.intro, .opcion), .nada)
        XCTAssertEqual(e.tecla(.suprimir), .noEsMia)
    }

    func testLaCapturaSePineaSeCopiaYSuprLaBorra() {
        var e = EstadoBuscar()
        e.consulta = "muro"
        let c = captura("muro.png")
        e.poner([c])
        let f = FilaBuscar.resultado(c)
        XCTAssertEqual(rotuloPrincipal(f), "Pinear")
        XCTAssertEqual(botonesDe(f), [.principal, .copiar, .mas])
        XCTAssertEqual(e.filaElegida, f, "la captura antes que «Apuntar tarea: muro»")
        XCTAssertEqual(e.tecla(.c, .comando), .copiar(f))
        XCTAssertEqual(e.tecla(.suprimir), .borrarCaptura(c))
        XCTAssertEqual(e.tecla(.suprimir, .comando, cajaAlFinal: false), .borrarCaptura(c), "⌘⌫ tambien")
        // Con la rayita en medio, Supr es de la caja.
        XCTAssertEqual(e.tecla(.suprimir, cajaAlFinal: false), .noEsMia)
        XCTAssertEqual(e.tecla(.intro, .opcion), .abrirCon(f))
        // Sin captura borrada, ⌘Z es de la caja (deshacer lo escrito).
        XCTAssertEqual(e.tecla(.z, .comando), .noEsMia)
        e.seDeshace = true
        XCTAssertEqual(e.tecla(.z, .comando), .deshacer)
    }

    func testElMenuSeRecorreConFlechasYSeEligeConIntro() {
        var e = mezcla()
        let f = e.filaElegida!
        XCTAssertTrue(e.abrirMenu([.pinear, .copiar]))
        _ = e.tecla(.abajo)
        _ = e.tecla(.abajo)
        XCTAssertEqual(e.elegido, 0, "con el menu abierto las flechas son suyas")
        XCTAssertEqual(e.tecla(.intro), .opcion(.copiar, f))
        XCTAssertEqual(e.tecla(.izquierda), .nada)
        XCTAssertNil(e.menu)
        // → abre el de la fila; con la rayita en medio es de la caja.
        XCTAssertEqual(e.tecla(.derecha), .abrirMenu(f))
        XCTAssertEqual(e.tecla(.derecha, cajaAlFinal: false), .noEsMia)
        // Caso negativo: un menu sin opciones no se abre.
        XCTAssertFalse(e.abrirMenu([]))
        XCTAssertNil(e.menu)
    }

    func testElBotonAzulDiceLoQueHace() {
        XCTAssertEqual(rotuloPrincipal(.resultado(res(.tarea, "x"))), "Hecha")
        XCTAssertEqual(rotuloPrincipal(.resultado(res(.tarea, "x", hecha: true))), "Desmarcar")
        XCTAssertEqual(rotuloPrincipal(.resultado(res(.fichero, "a.pdf"))), "Abrir")
        XCTAssertEqual(rotuloPrincipal(.resultado(res(.fichero, "voz", tipo: "VOZ"))), "Reproducir")
        XCTAssertEqual(rotuloPrincipal(.accion(.apuntarTarea("pan"))), "Apuntar")
        XCTAssertEqual(rotuloPrincipal(.accion(.nuevaNota(""))), "Crear")
        XCTAssertEqual(rotuloPrincipal(.accion(.capturar)), "Capturar")
    }

    func testElChatNoRepiteVerEnElChatEnSuFila() {
        let chat = FilaBuscar.resultado(res(.chat, "Thesis", chat: "t"))
        XCTAssertEqual(botonesDe(chat), [.principal])
        // Un fichero del chat si lo lleva, y su menu ofrece abrirlo con otra
        // app; uno sin fichero en este Mac solo «Ver en el chat».
        let pdf = FilaBuscar.resultado(res(.fichero, "a.pdf", chat: "c", mensaje: "m", posicion: 1, ruta: "/a.pdf"))
        XCTAssertEqual(botonesDe(pdf), [.principal, .verEnChat, .copiar, .mas])
        XCTAssertTrue(opcionesDeMenu(pdf).contains(.otraApp))
        let lejos = FilaBuscar.resultado(res(.fichero, "b.pdf", chat: "c", mensaje: "m", posicion: 1))
        XCTAssertEqual(opcionesDeMenu(lejos), [.verEnChat])
    }

    func testLasLetrasRapidas() {
        XCTAssertEqual(String(LetrasRapidas.todas.map(\.letra)), "tnlgcua")
        XCTAssertEqual(LetrasRapidas.analizar("t comprar pan")?.resto, "comprar pan")
        XCTAssertEqual(LetrasRapidas.analizar("g")?.letra, "g")
        XCTAssertEqual(accionesBuscar(para: "t comprar pan"), [.apuntarTarea("comprar pan")])
        XCTAssertEqual(accionesBuscar(para: "c "), [.capturar])
        // Una letra pegada a otras es buscar: las funciones que se llaman
        // asi y, al final, apuntarlo.
        XCTAssertNil(LetrasRapidas.analizar("tx"))
        XCTAssertNil(LetrasRapidas.analizar("nota"))
        let v = accionesBuscar(para: "galer")
        XCTAssertEqual(v.first, .ventana(id: IdVentana.galeria, titulo: "Galería de capturas"))
        XCTAssertEqual(v.last, .apuntarTarea("galer"))
        // Caso negativo: sin nada escrito, ninguna.
        XCTAssertTrue(accionesBuscar(para: "  ").isEmpty)
        // Con una letra, su accion va primero en «Todo».
        var e = EstadoBuscar()
        e.consulta = "g muro"
        e.poner([captura("muro.png")])
        XCTAssertEqual(e.filaElegida, .accion(.ventana(id: IdVentana.galeria, titulo: "Galería de capturas")))
    }
}

@MainActor
final class ModeloBuscarD8Tests: XCTestCase {
    private func almacenTemporal(_ nombre: String) throws -> (Almacen, URL) {
        let raiz = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-buscar-d8-\(nombre)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return (try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba"), raiz)
    }

    func testBuscaEnTodoConPestanasYLetrasYRecuerdaLoAbierto() async throws {
        let (almacen, raiz) = try almacenTemporal("todo")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let datos = raiz.appendingPathComponent("datos")
        let capturas = datos.appendingPathComponent("capturas")
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: capturas.appendingPathComponent("grieta-muro.png"))
        let chat = try almacen.nucleo.crearChat(nombre: "Obra").id
        _ = try almacen.nucleo.escribirNota(chat: chat, texto: "la grieta del muro norte", respondeA: nil)
        _ = try almacen.nucleo.apuntarTarea(texto: "sellar la grieta", desfaseMs: 0)
        // Un documento con la palabra solo dentro.
        let fuera = raiz.appendingPathComponent("acta.txt")
        try Data("Acta de obra\nfisura en el pilar P7".utf8).write(to: fuera)
        _ = try almacen.nucleo.adjuntar(chat: chat, rutaOrigen: fuera.path, nombre: nil)
        let p = try almacen.nucleo.documentosSinTexto(cuantos: 10)
        XCTAssertEqual(p.leidos, 1)

        let modelo = ModeloBuscar(almacen: almacen)
        await modelo.buscarAhora("grieta")
        let e = modelo.estado
        XCTAssertGreaterThanOrEqual(e.cuenta(.capturas), 1)
        XCTAssertGreaterThanOrEqual(e.cuenta(.archivos), 1)
        XCTAssertEqual(e.cuenta(.tareas), 1)
        XCTAssertEqual(e.cuenta(.acciones), 1, "apuntar «grieta»")
        // Lo de dentro del documento.
        await modelo.buscarAhora("pilar P7")
        let doc = try XCTUnwrap(modelo.estado.resultados.first { $0.clase == .fichero })
        XCTAssertTrue(doc.dentro)
        XCTAssertEqual(doc.titulo, "acta.txt")
        // «g muro»: solo las capturas, y la accion de la galeria primero.
        await modelo.buscarAhora("g muro")
        XCTAssertTrue(modelo.estado.resultados.allSatisfy { $0.clase == .captura })
        XCTAssertEqual(modelo.estado.resultados.count, 1)
        // «t pan» no pregunta al nucleo: solo apunta.
        await modelo.buscarAhora("t pan")
        XCTAssertTrue(modelo.estado.resultados.isEmpty)
        XCTAssertEqual(modelo.estado.visibles(), [.accion(.apuntarTarea("pan"))])

        // Lo elegido se recuerda y sale en la caja vacia.
        await modelo.buscarAhora("grieta")
        let cap = try XCTUnwrap(modelo.estado.resultados.first { $0.clase == .captura })
        try almacen.nucleo.buscarApuntar(consulta: "grieta", abierto: cap)
        await modelo.buscarAhora("")
        XCTAssertTrue(modelo.estado.esInicio)
        XCTAssertEqual(modelo.estado.resultados.first?.clave, cap.clave)
        XCTAssertEqual(modelo.busquedas, ["grieta"])
        modelo.quitarBusqueda(0)
        XCTAssertTrue(modelo.busquedas.isEmpty)
        // Con la caja vacia, «Tareas» pide las pendientes.
        modelo.ir(a: .tareas)
        _ = await modelo.tarea?.value
        XCTAssertEqual(modelo.estado.resultados.map(\.titulo), ["sellar la grieta"])
    }
}
