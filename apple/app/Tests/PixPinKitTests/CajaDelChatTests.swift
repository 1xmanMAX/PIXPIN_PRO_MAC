// La caja del chat (B3): la hoja del clip (`Chat/HojaAdjuntar.swift`), la
// lupa de la conversacion (`Chat/BuscarEnChat.swift`) y la escala
// (`Chat/EscalaChat.swift`). Lo que se prueba es lo mismo que prueba
// Windows en `hoja_adjuntar.rs` y `pixpin-ui/src/chat.rs`.

import Foundation
import PixPinCore
@testable import PixPinKit
import SwiftUI
import XCTest

@MainActor
final class CajaDelChatTests: XCTestCase {
    // MARK: Escala

    func testLaEscalaVaPorEscalonesYNoDaLaVuelta() {
        XCTAssertEqual(EscalaChat.siguiente(100), 110)
        XCTAssertEqual(EscalaChat.anterior(100), 90)
        XCTAssertEqual(EscalaChat.siguiente(250), 250, "en el tope se queda")
        XCTAssertEqual(EscalaChat.anterior(75), 75, "en el minimo se queda")
        // Lo escrito a mano acaba en el escalon mas cercano.
        XCTAssertEqual(EscalaChat.valida(137), 125)
        XCTAssertEqual(EscalaChat.valida(0), 75)
        XCTAssertEqual(EscalaChat.siguiente(137), 150)
    }

    func testLasTeclasDeLaEscala() {
        XCTAssertEqual(EscalaChat.pedida(tecla: "+", actual: 100), 110)
        XCTAssertEqual(EscalaChat.pedida(tecla: "=", actual: 100), 110, "el + sin mayusculas")
        XCTAssertEqual(EscalaChat.pedida(tecla: "-", actual: 100), 90)
        XCTAssertEqual(EscalaChat.pedida(tecla: "0", actual: 175), 100)
        XCTAssertNil(EscalaChat.pedida(tecla: "f", actual: 100))
        XCTAssertEqual(EscalaChat.aviso(125), "Escala de la interfaz: 125 %")
    }

    // MARK: Hoja del clip

    func testSieteBaldosasNumeradasYLosChipsDebajo() {
        let o = HojaAdjuntar.opciones
        // Como la «Adjuntar» del iPhone (Windows f87468aa): siete baldosas.
        XCTAssertEqual(o.compactMap(\.numero), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(o.filter(\.esBaldosa).map(\.accion),
                       [.foto, .archivo, .lienzo, .nota, .mini("tareas"), .tabla, .captura])
        XCTAssertEqual(o.count, 21)
        // «Figura» y la carpeta de paginas, en «Más».
        XCTAssertTrue(o.contains { $0.accion == .figura && !$0.esBaldosa })
        XCTAssertTrue(o.contains { $0.accion == .carpeta && !$0.esBaldosa })
        // La conversacion pasa a «Más».
        XCTAssertTrue(o.contains { $0.accion == .conversacion && !$0.esBaldosa })
        // Las baldosas primero, los chips despues.
        XCTAssertTrue(o.dropFirst(7).allSatisfy { !$0.esBaldosa })
        let minis = o.compactMap { if case let .mini(m) = $0.accion { m } else { nil } }
        XCTAssertEqual(minis, ["tareas", "contador", "ruleta", "gastos", "cronometro", "temporizador", "alarma"])
        XCTAssertEqual(AdjuntarEnChat.nombre(deMini: "cronometro"), "Cronómetro")
        // Cuatro columnas de baldosas y dos de «Más», las de Windows.
        XCTAssertEqual(HojaAdjuntar.columnas, 4)
        XCTAssertEqual(HojaAdjuntar.columnasChips, 2)
    }

    func testLaHojaDelAsistenteEmpiezaPorLaFigura() {
        let o = HojaAdjuntar.delAsistente
        XCTAssertEqual(o.filter(\.esBaldosa).map(\.accion), [.figura, .foto, .archivo, .captura, .lienzo, .nota])
        XCTAssertEqual(o.compactMap(\.numero), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(o.filter { !$0.esBaldosa }.map(\.accion), [.pedirFigura, .pagina, .proyecto, .tabla, .delMovil])
        // Caso negativo: la hoja de siempre no trae «Pedir una figura nueva».
        XCTAssertFalse(HojaAdjuntar.opciones.contains { $0.accion == .pedirFigura })
        XCTAssertFalse(HojaAdjuntar.opciones.contains { $0.accion == .figura && $0.esBaldosa })
    }

    func testLasFlechasVanALoQueQuedaEncimaODebajo() {
        // 7 baldosas (4 + 3), 14 chips en dos columnas y «Pegar».
        XCTAssertEqual(moverEnLaHojaAdjuntar(actual: nil, flecha: .derecha, baldosas: 7, chips: 14, pegar: true), 0)
        XCTAssertEqual(moverEnLaHojaAdjuntar(actual: 1, flecha: .abajo, baldosas: 7, chips: 14, pegar: true), 5)
        // De la ultima fila de baldosas, a los chips.
        let abajo = moverEnLaHojaAdjuntar(actual: 5, flecha: .abajo, baldosas: 7, chips: 14, pegar: true)
        XCTAssertNotNil(abajo)
        XCTAssertGreaterThanOrEqual(abajo ?? 0, 7)
        // No se sale por los extremos.
        XCTAssertEqual(moverEnLaHojaAdjuntar(actual: 0, flecha: .izquierda, baldosas: 7, chips: 14, pegar: true), 0)
        XCTAssertEqual(moverEnLaHojaAdjuntar(actual: 21, flecha: .derecha, baldosas: 7, chips: 14, pegar: true), 21)
        XCTAssertNil(moverEnLaHojaAdjuntar(actual: 0, flecha: .derecha, baldosas: 0, chips: 0, pegar: false))
    }

    func testLoQueElMacAunNoHaceSaleMarcado() {
        let faltan = HojaAdjuntar.opciones.filter { !$0.accion.enElMac }.map(\.rotulo)
        // Conversacion, Teleprónter y Pronunciar ya abren sus ventanitas (E5).
        XCTAssertTrue(faltan.isEmpty, "\(faltan)")
    }

    // MARK: La ficha del chat

    func testLaIslaOcupaSuParteDelHuecoYSinSitioLoLlenaEntero() {
        let (t, completa) = MedidasFicha.isla(en: CGSize(width: 1000, height: 800))
        XCTAssertFalse(completa)
        XCTAssertEqual(t.width, 580, accuracy: 0.5, "el 58 %")
        XCTAssertEqual(t.height, 800 - 2 * 24)
        // Topes: no pasa de 720 de ancho ni de 860 de alto.
        let grande = MedidasFicha.isla(en: CGSize(width: 3000, height: 2000)).tamano
        XCTAssertEqual(grande.width, 720)
        XCTAssertEqual(grande.height, 860)
        // Estrecha: al menos 360.
        XCTAssertEqual(MedidasFicha.isla(en: CGSize(width: 500, height: 600)).tamano.width, 360)
        // Caso negativo: sin sitio para la minima, el hueco entero.
        let chica = MedidasFicha.isla(en: CGSize(width: 400, height: 300))
        XCTAssertTrue(chica.completa)
        XCTAssertEqual(chica.tamano, CGSize(width: 400, height: 300))
    }

    func testLosTextosDeLaFicha() {
        XCTAssertEqual(TextosFicha.rotulo(.videos), "Vídeos")
        XCTAssertEqual(TextosFicha.rotulo(.enlaces), "Enlaces")
        XCTAssertEqual(TextosFicha.resumen(cosas: 1, codigo: "K7Q2"), "1 cosa  ·  K7Q2")
        XCTAssertEqual(TextosFicha.resumen(cosas: 24, codigo: ""), "24 cosas")
        XCTAssertEqual(TextosFicha.posicion(3, de: 24), "3 de 24")
        XCTAssertNil(TextosFicha.clase("NOTA"), "una nota es solo su texto")
        XCTAssertEqual(TextosFicha.clase("VOZ"), "Nota de voz")
        XCTAssertEqual(TextosFicha.clase("CROQUIS"), "CROQUIS", "lo que no se conoce, con su palabra")
        // Sin la pestana «Proyectos» (Windows e16087a): la galeria va delante.
        XCTAssertEqual(TextosFicha.rotulo(.galeria), "Galería")
        XCTAssertEqual(TextosFicha.vacia(.galeria), "Las hojas del proyecto saldrán aquí")
    }

    func testLosMesesDeLaFichaYSuRotulo() {
        var c = DateComponents()
        c.year = 2026
        c.month = 10
        c.day = 25
        c.hour = 12
        let octubre = Int64(Calendar.current.date(from: c)!.timeIntervalSince1970 * 1000)
        c.month = 11
        let noviembre = Int64(Calendar.current.date(from: c)!.timeIntervalSince1970 * 1000)
        XCTAssertEqual(TextosFicha.rotuloDelMes(octubre), "Octubre de 2026")
        XCTAssertEqual(TextosFicha.claveDelMes(noviembre) - TextosFicha.claveDelMes(octubre), 1)
        // Lo buscado, en negrita; sin nada buscado, nada que marcar.
        XCTAssertEqual(negritasDeLaFicha(texto: "Casa Lima", buscado: "lima").first?.inicio, 5)
        XCTAssertTrue(negritasDeLaFicha(texto: "Casa Lima", buscado: "").isEmpty)
    }

    // MARK: Buscar en el chat

    func testCasaSinMayusculasNiTildesEnElTextoOElNombre() {
        XCTAssertTrue(casaLaBusqueda(texto: "Cemento para el muro", nombre: "", aguja: "cemento"))
        XCTAssertTrue(casaLaBusqueda(texto: "Revisión", nombre: "", aguja: "REVISION"))
        XCTAssertTrue(casaLaBusqueda(texto: "", nombre: "planos.pdf", aguja: "Planos"))
        XCTAssertFalse(casaLaBusqueda(texto: "ladrillo", nombre: "foto.png", aguja: "cemento"))
        // En blanco casa con todo: con la caja abierta y vacia se ve todo.
        XCTAssertTrue(casaLaBusqueda(texto: "x", nombre: "", aguja: "  "))
    }

    func testLasEtiquetasUsadasEnSuOrden() {
        XCTAssertEqual(etiquetasUsadas(["\u{1F4CD}", nil, "\u{2B50}", "\u{1F600}", "\u{2B50}", " "]),
                       ["\u{2B50}", "\u{1F4CD}", "\u{1F600}"])
        XCTAssertEqual(etiquetasUsadas([nil, ""]), [])
    }

    func testLoBuscadoSeResaltaEnCadaAparicion() {
        let a = textoResaltado("Cemento y cemento", aguja: "CEMENTO")
        let marcados = a.runs.filter { $0.backgroundColor != nil }.map { String(a[$0.range].characters) }
        XCTAssertEqual(marcados, ["Cemento", "cemento"])
        XCTAssertTrue(textoResaltado("nada", aguja: "").runs.allSatisfy { $0.backgroundColor == nil })
    }

    func testLaLupaBuscaEnTodoElChatYLlevaAlElegido() async throws {
        let raiz = try carpetaTemporal("lupa-chat")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let obra = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        for t in ["Cemento para el muro", "ladrillo", "Más cemento gris", "arena"] {
            await almacen.escribir(nota: t, en: obra)
        }
        let b = BuscadorDelChat(chat: obra, nucleo: almacen.nucleo)
        XCTAssertFalse(b.filtrando)
        b.abrir()
        await b.carga?.value
        XCTAssertTrue(b.abierto)
        XCTAssertFalse(b.filtrando, "abierta y vacia no filtra")
        XCTAssertNil(b.resultados)

        b.texto = "CEMENTO"
        XCTAssertEqual(b.hallados.map(\.mensaje.texto), ["Cemento para el muro", "Más cemento gris"])
        XCTAssertEqual(b.hallados.map(\.posicion), [0, 2])
        XCTAssertEqual(b.elegido, 1, "el mas nuevo, el de abajo")
        XCTAssertEqual(b.cuenta, "2 de 2")
        XCTAssertEqual(b.resultados, "2 resultados")
        b.mover(1)
        XCTAssertEqual(b.elegido, 0, "da la vuelta")
        b.mover(-1)
        XCTAssertEqual(b.elegido, 1)

        b.texto = "hormigon"
        XCTAssertTrue(b.hallados.isEmpty)
        XCTAssertEqual(b.cuenta, "Nada con eso")
        XCTAssertNil(b.resultados)

        // «Ver en contexto»: el salto al elegido y la lupa apagada.
        b.texto = "cemento"
        b.mover(-1)
        let salto = try XCTUnwrap(b.enContexto())
        XCTAssertEqual(salto.chat, obra)
        XCTAssertEqual(salto.posicion, 0)
        XCTAssertFalse(b.abierto)
        XCTAssertTrue(b.texto.isEmpty)
        XCTAssertTrue(b.hallados.isEmpty)
    }

    func testElChipFiltraPorSuEtiquetaYSeQuitaAlPulsarlo() throws {
        func m(_ id: String, _ texto: String, _ emoji: String?) -> MensajeChat {
            MensajeChat(id: id, cuando: 0, clase: "NOTA", texto: texto, nombre: "", ruta: nil, bytes: 0,
                        resumen: texto, codigoChat: nil, respondeA: nil, emoji: emoji, fijado: false,
                        referencia: nil, pagina: nil, duracionMs: 0, transcripcion: nil, picos: [],
                        enBuzon: false, recuerdaEn: nil, miniapp: nil, esLeccion: false,
                        sePuedeRenombrar: false, sePuedeDescribir: false, punto: nil, soloLaFoto: true,
                        vieneDe: nil, vieneDeDibujo: nil, recibidoDe: nil, lienzoIa: nil)
        }
        let todos = [m("1", "muro", "\u{2B50}"), m("2", "muro sur", nil), m("3", "techo", "\u{2B50}")]
        XCTAssertEqual(BuscadorDelChat.filtrar(todos, aguja: "", etiqueta: "\u{2B50}").map(\.id), ["1", "3"])
        XCTAssertEqual(BuscadorDelChat.filtrar(todos, aguja: "muro", etiqueta: "\u{2B50}").map(\.id), ["1"])
        XCTAssertEqual(BuscadorDelChat.filtrar(todos, aguja: "muro", etiqueta: nil).map(\.id), ["1", "2"])
    }

    // MARK: Lo creado desde la hoja

    func testLoCreadoVaAlFinalDeLoCargado() async throws {
        let raiz = try carpetaTemporal("hoja-clip")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = try Almacen(raiz: raiz.appendingPathComponent("datos"), nombreDelAparato: "Mac de prueba")
        await almacen.crearChat(nombre: "Obra")
        let obra = try XCTUnwrap(almacen.chats.first { $0.nombre == "Obra" }).id
        await almacen.abrir(chat: obra)
        await almacen.escribir(nota: "hola", en: obra)
        let nucleo = almacen.nucleo
        let mini = try nucleo.crearMiniapp(chat: obra, miniapp: "tareas",
                                           titulo: AdjuntarEnChat.nombre(deMini: "tareas"), moneda: "EUR")
        await almacen.alFinal(mini, en: obra)
        let tabla = try nucleo.crearTabla(chat: obra, nombre: "Tabla")
        await almacen.alFinal(tabla, en: obra)
        let cargados = almacen.mensajes[obra] ?? []
        XCTAssertEqual(cargados.map(\.id).suffix(2), [mini.id, tabla.id])
        XCTAssertEqual(cargados.first { $0.id == mini.id }?.miniapp, "tareas")
        XCTAssertTrue(BurbujaTabla.esTabla(tabla))
    }
}
