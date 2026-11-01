// La pestana Funciones de la ventana de los chats (`FuncionesDeLaLista.swift`,
// Windows 2e0da60 y 768b73f): los mosaicos en el orden de Windows, la
// rejilla de la lista de siempre y el teclado, por el puente de verdad.

import Foundation
import PixPinCore
@testable import PixPinKit
import XCTest

@MainActor
final class FuncionesTests: XCTestCase {
    func testLosMosaicosVanEnElOrdenDeWindowsConSusTextos() {
        let es = textosDeFunciones(locale: "es-ES")
        XCTAssertEqual(es.mosaicos.map(\.funcion),
                       [.grabar, .lienzo, .tareas, .timeline, .horario, .galeria, .figuras])
        XCTAssertEqual(es.interruptorFunciones, "Funciones")
        XCTAssertEqual(es.mosaicos[1].titulo, "Nuevo lienzo")
        // Cada icono es uno de los trazados de Windows.
        for m in es.mosaicos {
            XCTAssertNotNil(TrazadosMaterial.todos[m.icono], m.icono)
        }
        // Caso negativo: en ingles no sale el espanol.
        XCTAssertEqual(textosDeFunciones(locale: "en-US").mosaicos[4].titulo, "Timetable")
    }

    /// **Cada mosaico abre lo suyo** (el usuario: «pulsar Grabar reunion
    /// abre Figuras»): el titulo que se ve, la funcion que hay en su caja
    /// (por el punto, como el clic) y la accion que hace van atados.
    func testCadaMosaicoAbreLoSuyoDondeSeVe() {
        let esperado: [(String, AccionDeFuncion)] = [
            ("Grabar reunión", .grabarClase),
            ("Nuevo lienzo", .nuevoLienzo),
            ("Tareas", .ventana(IdVentana.tareas)),
            ("Timeline", .ventana(IdVentana.timeline)),
            ("Horario", .vistaDeTareas(.horario)),
            ("Capturas", .ventana(IdVentana.galeria)),
            ("Figuras", .figuras),
        ]
        let es = textosDeFunciones(locale: "es-ES")
        XCTAssertEqual(es.mosaicos.map(\.titulo), esperado.map(\.0))
        for (ancho, alto) in [(UInt32(320), UInt32(700)), (900, 700), (320, 300)] {
            let g = rejillaDeFunciones(ancho: ancho, alto: alto)
            XCTAssertEqual(g.mosaicos.count, esperado.count)
            for (i, caja) in g.mosaicos.enumerated() {
                let (x, y) = (caja.x + Int32(caja.ancho / 2), caja.y + Int32(caja.alto / 2))
                let f = funcionEnElPunto(ancho: ancho, alto: alto, x: x, y: y)
                XCTAssertEqual(f, es.mosaicos[i].funcion, "\(esperado[i].0) en \(ancho)x\(alto)")
                XCTAssertEqual(f.map(AccionDeFuncion.de), esperado[i].1, esperado[i].0)
                // La esquina de arriba del mosaico tambien es suyo.
                XCTAssertEqual(funcionEnElPunto(ancho: ancho, alto: alto, x: caja.x, y: caja.y), f)
            }
        }
        // Caso negativo: Grabar no es Figuras ni en el rincon de la columna.
        XCTAssertNotEqual(AccionDeFuncion.de(.grabar), .figuras)
        XCTAssertNil(funcionEnElPunto(ancho: 320, alto: 700, x: 2, y: 2))
    }

    func testLaRejillaYElTeclado() {
        let g = rejillaDeFunciones(ancho: 320, alto: 700)
        XCTAssertEqual(g.columnas, 2)
        XCTAssertTrue(g.conDetalle)
        XCTAssertEqual(g.mosaicos.count, 7)
        let r = teclaEnFunciones(elegida: nil, tecla: .abajo, columnas: g.columnas)
        XCTAssertEqual(r.elegida, 0)
        XCTAssertEqual(teclaEnFunciones(elegida: 4, tecla: .hacer, columnas: 2).hacer, .horario)
        XCTAssertTrue(teclaEnFunciones(elegida: 4, tecla: .escape, columnas: 2).volver)
    }
}
