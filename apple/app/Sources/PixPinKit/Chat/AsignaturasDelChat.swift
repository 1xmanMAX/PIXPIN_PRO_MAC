// **Un solo chat para todas las asignaturas** (Windows d81934f8,
// `docs/novedades-2026-11-06-un-chat-para-las-asignaturas.md`): en el chat
// «Asignaturas», la fila «Todas · Geometría · Física…» con los colores del
// horario (en gris las que ya no estan); con un chip elegido se ve solo lo
// suyo y lo que se pone es de ella. Lo que es de una asignatura lleva su
// chapa «📘 Geometría». En los demas chats, «Enviar a asignatura…» lo copia
// (con lo de dentro de una carpeta) sin duplicar. La etiqueta es
// `"asignatura": "<nombre>"` en el mensaje: viaja y la entienden Windows y
// Android.

import PixPinCore
import SwiftUI

/// La fila de las asignaturas, debajo de la cabecera del chat.
struct FilaDeAsignaturas: View {
    let chips: [ChipAsignatura]
    let elegida: String?
    /// El chip pulsado (el mismo otra vez lo quita: `nil` es «Todas»).
    let elegir: (String?) -> Void

    /// Sin mayusculas ni tildes («geometria» es «Geometría»), como el nucleo.
    static func misma(_ a: String, _ b: String) -> Bool {
        let f: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        return f(a) == f(b)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(Lengua.t("asignaturas-todas"), color: nil, puesto: elegida == nil) { elegir(nil) }
                ForEach(chips, id: \.nombre) { c in
                    let puesto = elegida.map { Self.misma($0, c.nombre) } ?? false
                    chip(c.nombre, color: c.color, puesto: puesto) { elegir(puesto ? nil : c.nombre) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ rotulo: String, color: UInt32?, puesto: Bool,
                      accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                if rotulo != Lengua.t("asignaturas-todas") {
                    Circle()
                        .fill(Color(hex: color ?? 0x8E8E93))
                        .frame(width: 8, height: 8)
                }
                Text(rotulo)
                    .font(.system(size: 13))
                    .foregroundStyle(color == nil && rotulo != Lengua.t("asignaturas-todas")
                                     ? Color.secondary : Color.primary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(puesto ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(puesto ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// La chapa «📘 Geometría» bajo lo que es de una asignatura.
struct ChapaDeAsignatura: View {
    let nombre: String

    var body: some View {
        Text("📘 \(nombre)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// «Asignatura…» (en el chat «Asignaturas») o «Enviar a asignatura…» (en
/// los demas), en el menu de un mensaje.
struct MenuDeAsignatura: View {
    let mensaje: MensajeChat
    @ObservedObject var c: ChatAbierto

    var body: some View {
        let nucleo = c.almacen.nucleo
        let enSuChat = nucleo.chatDeAsignaturas() == c.chat
        let opciones = nucleo.asignaturasParaElMenu(chat: c.chat, mensaje: mensaje.id, desfaseMs: 0)
        if !opciones.isEmpty || (enSuChat && mensaje.asignatura != nil) {
            Menu {
                ForEach(opciones, id: \.self) { n in
                    Button(n) { hacer(n, enSuChat: enSuChat) }
                }
                if enSuChat, mensaje.asignatura != nil {
                    Divider()
                    Button(Lengua.t("chat-asignatura-quitar")) { hacer("", enSuChat: true) }
                }
            } label: {
                Label(Lengua.t(enSuChat ? "chat-asignatura-poner" : "chat-enviar-a-asignatura"),
                      systemImage: "book.closed")
            }
        }
    }

    private func hacer(_ nombre: String, enSuChat: Bool) {
        let nucleo = c.almacen.nucleo
        let chat = c.chat
        let ids = c.eleccion.ids.contains(mensaje.id) ? Array(c.eleccion.ids) : [mensaje.id]
        let c = self.c
        Task {
            let n = await Task.detached(priority: .userInitiated) { () -> UInt32 in
                if enSuChat {
                    return (try? nucleo.ponerAsignatura(chat: chat, mensajes: ids, nombre: nombre)) ?? 0
                }
                return (try? nucleo.enviarAAsignatura(chat: chat, mensajes: ids, nombre: nombre)) ?? 0
            }.value
            if enSuChat {
                await c.almacen.abrir(chat: chat)
            } else if n > 0 {
                c.avisar(Lengua.t("chat-enviado-a-asignatura",
                                  ["chat": "Asignaturas", "asignatura": nombre]))
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            }
        }
    }
}
