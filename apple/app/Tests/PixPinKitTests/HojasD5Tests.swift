// La tanda D5: las hojas de calculo como en Windows. Las teclas del modo
// editar (`hoja_pin::accion_de_tecla`, con ⌘ donde Windows pone Ctrl), un
// CSV del chat abierto como libro, y el editor de verdad (fuera de la
// pantalla): un rango en negrita de una vez, deshacer y copiar/pegar.

import AppKit
import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class HojasD5Tests: XCTestCase {
    private func tecla(_ t: UInt16, _ letra: String = "", mayus: Bool = false, comando: Bool = false,
                       opcion: Bool = false, control: Bool = false, escribiendo: Bool = false) -> AccionHoja? {
        AccionHoja.de(tecla: t, letra: letra, mayus: mayus, comando: comando, opcion: opcion, control: control,
                      escribiendo: escribiendo)
    }

    func testLasTeclasDelModoEditarSonLasDeWindowsConComando() {
        typealias T = AccionHoja.Tecla
        XCTAssertEqual(tecla(6, "z", comando: true), .deshacer)
        XCTAssertEqual(tecla(6, "z", mayus: true, comando: true), .rehacer)
        XCTAssertEqual(tecla(16, "y", comando: true), .rehacer)
        // Los de formato, tambien escribiendo.
        for (l, f) in [("b", FormatoHoja.negrita), ("i", .cursiva), ("u", .subrayado), ("5", .tachado)] {
            XCTAssertEqual(tecla(0, l, comando: true), .formato(f), l)
            XCTAssertEqual(tecla(0, l, comando: true, escribiendo: true), .formato(f), "\(l) escribiendo")
        }
        XCTAssertEqual(tecla(14, "e", mayus: true, comando: true), .formato(.alinear(alineacion: "c")))
        XCTAssertEqual(tecla(37, "l", mayus: true, comando: true), .formato(.alinear(alineacion: "i")))
        XCTAssertEqual(tecla(15, "r", mayus: true, comando: true), .formato(.alinear(alineacion: "d")))
        XCTAssertEqual(tecla(8, "c", comando: true), .copiar)
        XCTAssertEqual(tecla(7, "x", comando: true), .cortar)
        XCTAssertEqual(tecla(9, "v", comando: true), .pegar)
        XCTAssertEqual(tecla(T.f2), .empezar)
        XCTAssertEqual(tecla(T.suprimir), .borrar)
        XCTAssertEqual(tecla(T.retroceso), .borrar)
        XCTAssertEqual(tecla(T.escape, escribiendo: true), .cancelar)
        // Las hojas: ⌃⇟ / ⌃⇞ (Ctrl+AvPag / RePag de Windows) y ⌥⌘→ / ⌥⌘←.
        XCTAssertEqual(tecla(T.avPag, control: true), .hojaSiguiente)
        XCTAssertEqual(tecla(T.rePag, control: true), .hojaAnterior)
        XCTAssertEqual(tecla(T.derecha, comando: true, opcion: true), .hojaSiguiente)
        XCTAssertEqual(tecla(T.abajo, comando: true), .borde(dx: 0, dy: 1))
        // Casos negativos: escribiendo, copiar, pegar, deshacer y ⌘A son del
        // texto de la barra; Suprimir escribiendo no vacia la celda; ⌘N, ⌘K y
        // ⌘S son de macOS; una letra sola es un caracter.
        XCTAssertNil(tecla(8, "c", comando: true, escribiendo: true))
        XCTAssertNil(tecla(9, "v", comando: true, escribiendo: true))
        XCTAssertNil(tecla(6, "z", comando: true, escribiendo: true))
        XCTAssertNil(tecla(0, "a", comando: true, escribiendo: true))
        XCTAssertNil(tecla(T.suprimir, escribiendo: true))
        for l in ["n", "k", "s"] { XCTAssertNil(tecla(0, l, comando: true), l) }
        XCTAssertNil(tecla(0, "a"))
        XCTAssertNil(tecla(T.escape))
    }

    func testUnCsvDelChatSeEditaComoLibroConRangoDeshacerYPegar() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-d5-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let nucleo = try Nucleo.abrir(raiz: raiz.path, nombreDelAparato: "Mac")
        let chat = try nucleo.crearChat(nombre: "Datos")
        let csv = raiz.appendingPathComponent("datos.csv")
        try "Nombre;Edad\nAna;31\nLuis;40\n".write(to: csv, atomically: true, encoding: .utf8)
        let m = try nucleo.adjuntar(chat: chat.id, rutaOrigen: csv.path, nombre: nil)
        XCTAssertTrue(nucleo.esHojaDeCalculo(chat: chat.id, mensaje: m.id), "un CSV del chat es un libro")
        let hoja = try nucleo.abrirHojaDeCalculo(chat: chat.id, mensaje: m.id)
        XCTAssertEqual(hoja.hojas().count, 1)
        XCTAssertEqual(hoja.contenido(fila: 2, columna: 1), "40")

        let c = ControladorHoja(hoja: hoja, titulo: "datos.csv")
        // A1:B3 en negrita de una vez, y un deshacer lo quita todo.
        hoja.elegir(s: SeleccionHoja(anclaFila: 0, anclaColumna: 0, fila: 2, columna: 1))
        c.hacer(.formato(.negrita))
        XCTAssertEqual(hoja.estilo(fila: 2, columna: 1)?.negrita, true)
        XCTAssertTrue(hoja.avisoAlEditar() == false, "el aviso del archivo ya se dio al editar")
        c.hacer(.deshacer)
        XCTAssertNil(hoja.estilo(fila: 2, columna: 1))
        // Copiar y pegar pasan por el portapapeles del Mac (texto y HTML).
        hoja.elegir(s: SeleccionHoja(anclaFila: 1, anclaColumna: 0, fila: 1, columna: 1))
        c.hacer(.copiar)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string)?.hasPrefix("Ana\t31"), true)
        XCTAssertNotNil(NSPasteboard.general.string(forType: .html))
        hoja.elegir(s: SeleccionHoja(anclaFila: 5, anclaColumna: 0, fila: 5, columna: 0))
        c.hacer(.pegar)
        XCTAssertEqual(hoja.contenido(fila: 5, columna: 1), "31")
        // Guardar: la hoja pasa al chat como tabla y el CSV no cambia.
        XCTAssertTrue(try hoja.guardar())
        XCTAssertEqual(try String(contentsOf: csv, encoding: .utf8), "Nombre;Edad\nAna;31\nLuis;40\n")
        let mensajes = try nucleo.ultimosMensajes(chat: chat.id, cuantos: 10).mensajes
        XCTAssertTrue(mensajes.contains { $0.clase == "MINIAPP" && $0.texto.contains("\"A6\"") },
                      "la tabla con lo pegado esta en el chat")
        c.ventana.close()
    }
}
