// **Las ventanitas de la voz desde un chat** (tanda E5): lo que en Windows
// hacen `abrir_telepronter`, `abrir_pronunciar`, `abrir_conversacion` y
// `latido_de_la_voz` de `ventana_chat.rs`. La hoja del clip
// (`Chat/HojaAdjuntar.swift`) llama aqui; lo grabado entra en el chat como
// nota de voz (`Nucleo.adjuntarGrabacion`, que es lo que viaja) y, si no
// trae su texto, se pasa a texto.
//
// Y lo de **quien llama** en la llamada secreta (`ventana_chat/quien_llama.rs`):
// el nombre que sale al sonar, apuntado en el Mac y no en el mensaje (no
// viaja, como en el movil).

import AppKit
import PixPinCore

// MARK: - Lo escrito en la caja

/// **Lo que hay escrito en la caja de cada chat**: el telepronter ofrece
/// leerlo («Lo escrito en la caja»). Lo apunta la caja al cambiar.
@MainActor
enum BorradoresDelChat {
    private static var textos: [String: String] = [:]

    static func poner(_ texto: String, en chat: String) {
        textos[chat] = texto.isEmpty ? nil : texto
    }

    static func de(_ chat: String) -> String { textos[chat] ?? "" }
}

// MARK: - Que se lee en el telepronter (puro)

enum FuentesTelepronter {
    enum Fuente: Equatable {
        case borrador
        /// Una nota escrita (su texto) o un `.txt`/`.md` (su ruta).
        case nota(String)
        case adjunto(ruta: String)
    }

    struct Entrada: Equatable {
        var rotulo: String
        var fuente: Fuente
    }

    /// Si ese nombre de fichero es de los que el telepronter sabe leer:
    /// solo texto plano (un `.docx` pintaria su ZIP).
    static func esLeible(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        return n.hasSuffix(".txt") || n.hasSuffix(".md")
    }

    /// **De donde sacar el texto** (`menu_del_telepronter`): lo escrito en
    /// la caja, las notas de la conversacion y los `.txt`/`.md` adjuntos,
    /// lo mas nuevo primero y doce como mucho. Una nota sale por su primera
    /// linea recortada; un adjunto, por su nombre.
    static func entradas(borrador: String, mensajes: [MensajeChat]) -> [Entrada] {
        var v: [Entrada] = []
        if !borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v.append(Entrada(rotulo: "Lo escrito en la caja", fuente: .borrador))
        }
        for m in mensajes.reversed() {
            if v.count >= 12 { break }
            if let ruta = m.ruta {
                if esLeible(m.nombre) { v.append(Entrada(rotulo: m.nombre, fuente: .adjunto(ruta: ruta))) }
                continue
            }
            guard let linea = m.texto.split(separator: "\n").first(where: {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }) else { continue }
            let l = linea.trimmingCharacters(in: .whitespaces)
            let corto = l.count > 48 ? String(l.prefix(48)) + "…" : l
            v.append(Entrada(rotulo: corto, fuente: .nota(m.texto)))
        }
        return v
    }
}

// MARK: - Abrirlas desde un chat

@MainActor
enum VozEnElChat {
    static let sinTexto = "No hay ningún texto que leer: escribe algo en la caja o adjunta un .txt o un .md"

    /// **Telepronter**: un menu con de donde sacar el texto, y la ventana.
    static func telepronter(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        if Telepronter.abierto {
            avisar("El teleprónter ya está abierto")
            return
        }
        let entradas = FuentesTelepronter.entradas(borrador: BorradoresDelChat.de(chat),
                                                   mensajes: almacen.mensajes[chat] ?? [])
        guard !entradas.isEmpty else { return avisar(sinTexto) }
        let menu = NSMenu()
        let accion = AccionDeMenu { i in
            MainActor.assumeIsolated {
                leer(entradas[i].fuente, chat: chat, almacen: almacen, avisar: avisar)
            }
        }
        for (i, e) in entradas.enumerated() {
            let item = NSMenuItem(title: e.rotulo, action: #selector(AccionDeMenu.pulsado(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: e.fuente == .borrador ? "doc.text" : "captions.bubble",
                                 accessibilityDescription: nil)
            item.target = accion
            item.tag = i
            item.representedObject = accion
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// El texto de una fuente (un adjunto se lee del disco al elegirlo, no
    /// al abrir el menu) y la ventana con el.
    private static func leer(_ f: FuentesTelepronter.Fuente, chat: String, almacen: Almacen,
                             avisar: @escaping (String) -> Void) {
        Task {
            let texto: String
            switch f {
            case .borrador: texto = BorradoresDelChat.de(chat)
            case let .nota(t): texto = t
            case let .adjunto(ruta):
                guard let u = await almacen.url(deRuta: ruta, en: chat),
                      let d = await Task.detached(operation: { try? Data(contentsOf: u) }).value
                else { return avisar(sinTexto) }
                // Sin exigir UTF-8: una tilde mal codificada no impide leer.
                texto = String(decoding: d, as: UTF8.self)
            }
            let abierto = Telepronter.abrir(texto: texto) { lectura in
                Task {
                    let g = GrabacionVoz(rutaOrigen: lectura.nota.url.path, duracionMs: lectura.nota.duracionMs,
                                         picos: lectura.nota.picos, texto: lectura.cuerpo, turnos: [])
                    let m = await almacen.adjuntarGrabacion(g, en: chat)
                    avisar(m != nil ? "Lectura guardada como nota de voz" : "No se pudo guardar la lectura")
                }
            }
            if !abierto { avisar(sinTexto) }
        }
    }

    /// **Pronunciar**, con lo del chat que sirve de guia. Cada toma guardada
    /// entra como nota de voz y se pasa a texto en el idioma practicado.
    static func pronunciar(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        let guias = Pronunciar.guiasDelChat(almacen.mensajes[chat] ?? [])
        Pronunciar.abrir(delChat: guias, resolver: { await almacen.url(deRuta: $0, en: chat) }) { toma in
            Task {
                let g = GrabacionVoz(rutaOrigen: toma.nota.url.path, duracionMs: toma.nota.duracionMs,
                                     picos: toma.nota.picos, texto: nil, turnos: [])
                guard let m = await almacen.adjuntarGrabacion(g, en: chat) else { return }
                await almacen.transcribir(m, en: chat, idioma: toma.idioma)
            }
        }
    }

    /// **La conversacion por turnos**: entra con sus turnos y se pasa a
    /// texto con los nombres.
    static func conversacion(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        if ConversacionPorTurnos.abierto {
            avisar("La conversación ya está abierta")
        }
        ConversacionPorTurnos.abrir { nota, turnos in
            Task {
                let g = GrabacionVoz(rutaOrigen: nota.url.path, duracionMs: nota.duracionMs, picos: nota.picos,
                                     texto: nil, turnos: turnos)
                guard let m = await almacen.adjuntarGrabacion(g, en: chat) else { return }
                avisar("Pasando la conversación a texto…")
                await almacen.transcribir(m, en: chat)
            }
        }
    }
}

extension Almacen {
    /// Guarda en `chat` una nota de las ventanitas de la voz
    /// (`Nucleo.adjuntarGrabacion`) y la anade al final de lo cargado. El
    /// fichero grabado se borra: ya esta dentro del proyecto.
    @discardableResult
    func adjuntarGrabacion(_ g: GrabacionVoz, en chat: String) async -> MensajeChat? {
        let nucleo = self.nucleo
        let resultado = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
            Result { try nucleo.adjuntarGrabacion(chat: chat, grabacion: g) }
        }.value
        switch resultado {
        case let .success(m):
            try? FileManager.default.removeItem(atPath: g.rutaOrigen)
            anadir([m], en: chat)
            ponerError(nil)
            return m
        case let .failure(e):
            ponerError("\(e)")
            return nil
        }
    }
}

// MARK: - Quien llama

/// **Quien llama** en la llamada secreta de una nota de voz: el nombre
/// apuntado o, si no, el de la nota sin extension. Se guarda en el Mac
/// (`Nucleo.ponerQuienLlama`); aqui se recuerda lo leido para no ir al
/// disco cada vez que sale el menu.
@MainActor
enum QuienLlama {
    private static var leidos: [String: String?] = [:]

    /// El que se ensena ahora para la nota `m`.
    static func actual(_ m: MensajeChat, nucleo: Nucleo) -> String {
        let apuntado: String?
        if let ya = leidos[m.id] {
            apuntado = ya
        } else {
            apuntado = nucleo.quienLlama(mensaje: m.id)
            leidos[m.id] = .some(apuntado)
        }
        return apuntado ?? nombreDeLlamada(nombre: m.nombre)
    }

    /// Apunta quien llama (en blanco, lo olvida y vuelve el de la nota).
    static func poner(_ nombre: String, en m: MensajeChat, nucleo: Nucleo) {
        let limpio = String(nombre.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        leidos[m.id] = .some(limpio.isEmpty ? nil : limpio)
        let id = m.id
        Task.detached(priority: .utility) { try? nucleo.ponerQuienLlama(mensaje: id, nombre: limpio) }
    }

    /// Al ponerle la hora a una nota de voz se apunta quien llama (el que se
    /// ve, aunque no se haya tocado), como el movil al elegir.
    static func alPonerLaHora(_ m: MensajeChat, nucleo: Nucleo) {
        guard m.clase == "VOZ" else { return }
        poner(actual(m, nucleo: nucleo), en: m, nucleo: nucleo)
    }
}

// MARK: - Al sonar un recordatorio

extension Recordatorios {
    /// **Si el recordatorio vencido es una llamada secreta, suena como
    /// tal**: una nota de voz con su audio en este Mac. Devuelve si lo era
    /// (si no, sale el aviso de siempre). Bloquea un poco: lee el cuaderno.
    nonisolated static func llamada(de r: RecordatorioPuesto, nucleo: Nucleo) -> LlamadaSecreta? {
        guard r.tarea == nil else { return nil }
        return (try? nucleo.llamadaSecreta(chat: r.chat, mensaje: r.id)) ?? nil
    }
}
