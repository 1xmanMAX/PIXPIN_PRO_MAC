// La barra de arriba del chat «Asistente» (Windows, 17-oct): la pastilla
// del modelo (Local / Claude Haiku / DeepSeek), que cambia el MISMO ajuste
// que Ajustes → Asistente → Motor, al instante; y «+ Nuevo chat» (la
// «Conversación nueva» de Windows, 22 y 23-oct, siempre a la vista), una
// nota del asistente que corta el contexto que se le manda (lo de antes
// sigue a la vista y viaja como siempre).

import PixPinCore
import SwiftUI

struct CabeceraDelAsistente: View {
    let almacen: Almacen
    let chat: String
    @State private var motor = ""

    static let motores: [(id: String, nombre: String)] = [("", "Local"), ("claude", "Claude Haiku"),
                                                           ("deepseek", "DeepSeek")]

    static func nombre(de motor: String) -> String {
        motores.first { $0.id == motor }?.nombre ?? "Local"
    }

    var body: some View {
        // «+ Nuevo chat» siempre a la vista y pegado a la derecha (Windows,
        // 23-oct: «el asistente no tiene un boton de nuevo chat»), y a su
        // izquierda la pastilla del modelo. Sin sitio, solo el «+».
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Menu {
                ForEach(Self.motores, id: \.id) { m in
                    Button {
                        elegir(m.id)
                    } label: {
                        if m.id == motor { Label(m.nombre, systemImage: "checkmark") } else { Text(m.nombre) }
                    }
                }
            } label: {
                Label(Self.nombre(de: motor), systemImage: "sparkles")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Quién contesta (el mismo ajuste que Ajustes → Asistente)")
            ViewThatFits(in: .horizontal) {
                botonNuevo(conRotulo: true)
                botonNuevo(conRotulo: false)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .task { motor = (try? almacen.nucleo.ajustes().asistenteMotor) ?? "" }
    }

    /// «+ Nuevo chat» (`asistente-nuevo-chat`): una «Conversación nueva»,
    /// lo mismo que la entrada del menu.
    private func botonNuevo(conRotulo: Bool) -> some View {
        Button {
            nueva()
        } label: {
            Group {
                if conRotulo {
                    Label("Nuevo chat", systemImage: "plus")
                } else {
                    Image(systemName: "plus")
                }
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Conversación nueva: lo de arriba ya no se le manda al asistente")
    }

    private func elegir(_ nuevo: String) {
        guard var a = try? almacen.nucleo.ajustes() else { return }
        a.asistenteMotor = nuevo
        do {
            try almacen.nucleo.guardarAjustes(nuevos: a)
            motor = nuevo
        } catch {
            NSSound.beep()
        }
    }

    private func nueva() {
        let (nucleo, chat) = (almacen.nucleo, chat)
        Task {
            guard let m = try? await Task.detached(operation: { try nucleo.iaConversacionNueva(chat: chat) }).value
            else { return NSSound.beep() }
            almacen.anadir([m], en: chat)
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        }
    }
}
