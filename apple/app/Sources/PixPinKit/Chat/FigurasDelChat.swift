// **Las figuras en el chat** (25-oct-2026 en Windows, el usuario:
// «especializalo para el asistente … que pueda adjuntar figuras para que
// las mejore, o decirle hazme una figura, y lo puedo anadir facilmente a la
// lista de figuras»):
//
// - en la hoja del clip de cualquier chat, **Figura**: abre la ventana de
//   las figuras eligiendo para ese chat (Windows 1d50a7c, se elige viendola
//   y no en menus en cascada); la elegida entra en un lienzo nuevo del chat
//   con su nombre y, en el del asistente, la caja empieza con «Mejora la
//   figura …»;
// - en la del asistente, ademas, **Pedir una figura nueva** (la caja empieza
//   con «Hazme una figura de »);
// - en el menu de un lienzo del chat, **Guardar en mis figuras**.
//
// Lo que toca el disco es de Rust (`galeria_figuras.rs`: `adjuntar_figura`,
// `guardar_lienzo_en_figuras`, `figuras_por_grupos`).

import AppKit
import PixPinCore

@MainActor
enum FigurasDelChat {
    /// Hace `accion` si es de las figuras (y devuelve `true`); `empezar`
    /// pone el texto en la caja si estaba vacia.
    static func hacer(_ accion: AccionAdjuntar, chat: String, almacen: Almacen,
                      avisar: @escaping (String) -> Void, empezar: @escaping (String) -> Void) -> Bool {
        switch accion {
        case .figura:
            elegirFigura(chat: chat, almacen: almacen, avisar: avisar, empezar: empezar)
            return true
        case .pedirFigura:
            empezar("Hazme una figura de ")
            return true
        default:
            return false
        }
    }

    /// **«Figura»** (Windows 1d50a7c, el usuario: «al adjuntar figuras no
    /// veo las figuras, me sale una lista y tengo que buscar»): abre la
    /// ventana de las figuras eligiendo para este chat, con su boton
    /// «Adjuntar a …». La elegida entra como un lienzo con ella dentro.
    private static func elegirFigura(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void,
                                     empezar: @escaping (String) -> Void) {
        let ficha = almacen.chats.first { $0.id == chat }
        let destino = ChatDeLaFigura(chat: chat, nombre: ficha?.nombre ?? "") { f in
            // En el chat del asistente, la caja empieza con «Mejora la figura …».
            FigurasDelChat.adjuntar(f.id, nombre: f.corto, chat: chat, almacen: almacen, avisar: avisar,
                     empezar: ficha?.esAsistente == true ? empezar : nil)
        }
        VentanaFiguras.abrirParaAdjuntar(nucleo: almacen.nucleo, chat: destino)
    }

    /// La figura `id`, a un lienzo nuevo del chat con su nombre. Si el chat
    /// no es el que se ve, se trae (como `ir_a` de Windows).
    private static func adjuntar(_ id: String, nombre: String, chat: String, almacen: Almacen,
                                 avisar: @escaping (String) -> Void, empezar: ((String) -> Void)?) {
        let nucleo = almacen.nucleo
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.adjuntarFigura(chat: chat, id: id) }
            }.value
            switch r {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                PeticionDeChat.compartida.chat = chat
                empezar?("Mejora la figura «\(nombre)»: ")
            case .failure:
                avisar("No se pudo: mira el registro de PixPin")
            }
        }
    }
}

extension ChatAbierto {
    /// **«Guardar en mis figuras»** un lienzo del chat: lo que se ve en el,
    /// con el nombre del mensaje (sin el, «Figura de <chat>»).
    func guardarEnFiguras(_ m: MensajeChat) {
        guard let dibujo = m.referencia, !dibujo.isEmpty else { return }
        let nucleo = almacen.nucleo
        let chat = self.chat
        let nombre = m.nombre
        let nombreDelChat = almacen.chats.first { $0.id == chat }?.nombre ?? ""
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<String?, Error> in
                Result {
                    try nucleo.guardarLienzoEnFiguras(chat: chat, dibujo: dibujo, nombre: nombre,
                                                      nombreDelChat: nombreDelChat)
                }
            }.value
            switch r {
            case let .success(guardada?):
                avisar("Guardada en tus figuras como «\(guardada)»")
                VentanaFiguras.releer()
            case .success(nil):
                avisar("Ese lienzo está vacío: no hay nada que guardar")
            case .failure:
                avisar("No se pudo: mira el registro de PixPin")
            }
        }
    }
}
