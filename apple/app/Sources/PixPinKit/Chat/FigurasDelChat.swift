// **Las figuras en el chat** (25-oct-2026 en Windows, el usuario:
// «especializalo para el asistente … que pueda adjuntar figuras para que
// las mejore, o decirle hazme una figura, y lo puedo anadir facilmente a la
// lista de figuras»):
//
// - en la hoja del clip del chat del asistente, **Figura** (un menu por
//   grupos con las de la biblioteca: la elegida entra en un lienzo nuevo
//   del chat con su nombre y la caja empieza con «Mejora la figura …») y
//   **Pedir una figura nueva** (la caja empieza con «Hazme una figura de »);
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

    /// El menu de las figuras por grupos (lo del usuario primero), donde
    /// esta el raton.
    private static func elegirFigura(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void,
                                     empezar: @escaping (String) -> Void) {
        let nucleo = almacen.nucleo
        let grupos = (try? nucleo.figurasPorGrupos()) ?? []
        guard !grupos.isEmpty else {
            return avisar("Todavía no hay figuras. En un lienzo, elige algo y «Guardar como figura».")
        }
        let menu = NSMenu()
        for g in grupos {
            let item = NSMenuItem(title: "\(g.nombre) (\(g.figuras.count))", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            for f in g.figuras {
                let i = ItemConAccion.nuevo(f.nombre) {
                    adjuntar(f, chat: chat, almacen: almacen, avisar: avisar, empezar: empezar)
                }
                i.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
                sub.addItem(i)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// La figura, a un lienzo nuevo del chat con su nombre.
    private static func adjuntar(_ f: FiguraDeBiblioteca, chat: String, almacen: Almacen,
                                 avisar: @escaping (String) -> Void, empezar: @escaping (String) -> Void) {
        let nucleo = almacen.nucleo
        let id = f.id
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.adjuntarFigura(chat: chat, id: id) }
            }.value
            switch r {
            case let .success(m):
                almacen.anadir([m], en: chat)
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                empezar("Mejora la figura «\(f.nombre)»: ")
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
