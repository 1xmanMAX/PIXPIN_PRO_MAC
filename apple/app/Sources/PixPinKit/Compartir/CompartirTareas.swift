// **Una lista de tareas en la hoja de compartir** (Windows f59890b, bc4533b
// y 1746154, `compartir/tareas.rs`; el usuario: «mejora la apariencia de mis
// quehaceres cuando los exporto»).
//
// Antes la mini-app `tareas` salia como cualquier texto, con las marcas
// crudas a la vista (`⏫`, `➕ 2026-10-28`, los enlaces de las fotos). Ahora
// cada formato sale de lo ya entendido (`pindesk_proyecto::tareas_exportar`
// por el nucleo, `pixpin-nucleo/src/compartir_tareas.rs`); aqui solo se pone
// en la hoja de siempre:
//
// - **PDF, PNG, JPG y SVG**: sus hojas A4 cuidadas (casillas, chapitas,
//   recordatorios, fotos y lo hecho al final), las ordenes de Windows
//   pintadas con el pintor del lienzo, como las de una grabacion;
// - **HTML**: si todo lo compartido son listas, la pagina propia de las
//   tareas (resumen, chapitas, fotos en miniatura y lo hecho plegado);
// - **Word**, **Markdown** y **Texto**, cuando la lista va sola.
//
// Los rotulos van en el idioma de la app (los catorce del catalogo).

import Foundation
import PixPinCore

extension PrepararCompartir {
    /// Si un mensaje es una lista de tareas (`tareas::es_lista` de Windows).
    static func esListaDeTareas(_ m: MensajeChat) -> Bool {
        m.clase == "MINIAPP" && m.miniapp == "tareas"
    }

    /// **Pone la lista** del mensaje `m` como paginas (y, sola, su Word, su
    /// Markdown y su texto), como `tareas::anadir` de Windows. Devuelve si
    /// puso alguna; si no, el mensaje va como texto, como antes.
    static func anadirLista(_ p: PreparadoCompartir, _ m: MensajeChat, chat: String, clave: String,
                            nombre: String, solo: Bool, almacen: Almacen) async -> Bool {
        let nucleo = almacen.nucleo
        let id = m.id
        let idioma = Lengua.catalogo.etiqueta()
        let desfase = desfaseLocalMs()
        let leido = await Task.detached(priority: .userInitiated) { () -> (ListaParaCompartir, HojasDeTareas)? in
            guard let l = try? nucleo.listaParaCompartir(chat: chat, mensaje: id) else { return nil }
            return (l, tareasHojas(lista: l, idioma: idioma, desfaseMs: desfase))
        }.value
        guard let (lista, hojas) = leido, !hojas.hojas.isEmpty else { return false }
        var rutas: [UInt64: URL] = [:]
        for f in hojas.fotos { rutas[f.idObjeto] = URL(fileURLWithPath: f.ruta) }
        let fotos = CacheDeFotos(rutas)
        for (i, h) in hojas.hojas.enumerated() {
            let pagina = i == 0
                ? PaginaCompartir(clave: clave, nombre: nombre, detalle: Lengua.t("compartir-tipo-tareas"))
                : PaginaCompartir(clave: "\(clave)|p\(i + 1)", nombre: "\(Lengua.t("compartir-pagina")) \(i + 1)",
                                  detalle: "", nivel: 1)
            var pieza = PiezasCompartir.dibujo(h, pagina: pagina, fotos: fotos)
            // La hoja de Windows es un A4 a 96 ppp: en el PDF, un A4 en puntos.
            pieza.tamano = PiezasCompartir.a4
            // El SVG lleva las fotos dentro: se hace al pedirlo.
            let indice = UInt32(i)
            pieza.svg = { tareasSvgDeHoja(lista: lista, idioma: idioma, desfaseMs: desfase, indice: indice) }
            p.anadir(pieza)
        }
        p.listasDeTareas.append(lista)
        if solo {
            let base = p.base
            let md = tareasMarkdown(lista: lista, idioma: idioma, desfaseMs: desfase)
            let texto = tareasTexto(lista: lista, idioma: idioma, desfaseMs: desfase)
            p.extras.append(word(titulo: lista.titulo, markdown: md, nombre: base))
            p.extras.append(ExtraCompartir(
                formato: FormatoCompartir(id: IdFormato.md, nombre: "Markdown", cuantas: .ninguna,
                                          simbolo: "square.and.pencil"),
                que: .escrito(nombre: "\(base).md") { Data(md.utf8) }))
            p.extras.append(ExtraCompartir(
                formato: FormatoCompartir(id: IdFormato.texto, nombre: "Texto", cuantas: .ninguna,
                                          simbolo: "text.alignleft"),
                que: .escrito(nombre: "\(base).txt") { Data(texto.utf8) }))
        }
        return true
    }

    /// **Solo listas de tareas**: la pagina web es la de las tareas, con el
    /// resumen y lo hecho plegado (`tareas::todas_son_listas` de Windows).
    /// Entre otras cosas, las listas van dibujadas como las demas paginas.
    static func paginaDeTareas(_ p: PreparadoCompartir, cuantos: Int) {
        guard !p.listasDeTareas.isEmpty, p.listasDeTareas.count == cuantos else { return }
        let listas = p.listasDeTareas
        let titulo = p.titulo
        let base = p.base
        let idioma = Lengua.catalogo.etiqueta()
        let desfase = desfaseLocalMs()
        p.paginaWeb = { carpeta in
            let ruta = carpeta.path
            let hechas = try await Task.detached(priority: .userInitiated) {
                try tareasWeb(listas: listas, titulo: titulo, idioma: idioma, desfaseMs: desfase, base: base, carpeta: ruta)
            }.value
            return hechas.map { URL(fileURLWithPath: $0) }
        }
    }
}
