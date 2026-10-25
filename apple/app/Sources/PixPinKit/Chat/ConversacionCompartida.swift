// **Un chat compartido como conversacion** (Windows b89c058 y e3f1d60,
// 25-oct-2026, el usuario: «cuando sea compartido, que el chat se vuelva
// como un chat real: mis burbujas a la derecha y las de la otra persona al
// otro lado»):
//
// - `ChapasDeCompartidos`: que chats de la lista son compartidos y con
//   cuantas personas (la chapa verde del avatar y «Compartido · N personas»
//   en la cabecera).
// - `ConversacionDelChat`: el lado de cada burbuja de un chat compartido. Lo
//   decide Rust (`Nucleo.conversacionDelChat`, sobre `pixpin_ui::conversacion`
//   y `historial::colocar`, los de Windows): lo mio a la derecha, lo de cada
//   otra persona a la izquierda con su nombre encima de la primera de su
//   tanda. Un chat normal sigue siendo un cuaderno propio y no cambia.
// - `EnSuLado`: lo pinta.
// - `PeticionDeInvitar`: el chat recien nacido compartido abre «Chats
//   compartidos» invitando ya a ese chat.

import AppKit
import PixPinCore
import SwiftUI

/// Los textos de los chats compartidos que salen en la lista y el chat
/// (`cc-*` y `chat-nuevo-*` de Windows).
enum TextosCompartido {
    static let normal = "Chat normal"
    static let normalDetalle = "Solo tú y tus aparatos"
    static let compartido = "Chat compartido"
    static let compartidoDetalle = "Con otras personas, cada una en su lado"
    static let nuevoError = "No se pudo compartir el chat nuevo: queda como chat normal"

    /// `cc-chapa-personas`.
    static func chapa(_ n: UInt32) -> String {
        n == 1 ? "Compartido · 1 persona" : "Compartido · \(n) personas"
    }
}

/// **Los chats compartidos donde estoy**, por su ficha, con cuantas
/// personas son. Se relee al cambiar la lista de chats o los compartidos.
@MainActor
public final class ChapasDeCompartidos: ObservableObject {
    public static let compartidas = ChapasDeCompartidos()
    /// `FichaChat.id` -> personas dentro (yo incluido).
    @Published public private(set) var personas: [String: UInt32] = [:]
    private var turno = 0

    public func releer(_ nucleo: Nucleo) {
        turno += 1
        let mio = turno
        Task {
            let lista = (try? await Task.detached(priority: .utility) {
                try nucleo.chapasDeCompartidos()
            }.value) ?? []
            guard mio == self.turno else { return }
            var nuevo: [String: UInt32] = [:]
            for c in lista { nuevo[c.ficha] = c.personas }
            if nuevo != self.personas { self.personas = nuevo }
        }
    }
}

/// **El lado de cada burbuja** de un chat (vacio en uno normal).
@MainActor
final class ConversacionDelChat: ObservableObject {
    /// `MensajeChat.id` -> su lado.
    @Published private(set) var lados: [String: LadoDeMensaje] = [:]
    let chat: String
    let nucleo: Nucleo
    private var turno = 0

    init(chat: String, nucleo: Nucleo) {
        self.chat = chat
        self.nucleo = nucleo
    }

    /// Vuelve a mirar de quien es cada uno de `mensajes` (los que se ven,
    /// del mas viejo al mas nuevo: las tandas dependen del de al lado).
    func releer(_ mensajes: [MensajeChat]) {
        turno += 1
        let mio = turno
        let autorias = mensajes.map { AutoriaDeMensaje(id: $0.id, cuando: $0.cuando, aparato: $0.aparato) }
        let chat = self.chat
        let nucleo = self.nucleo
        let desfase = desfaseLocalMs()
        Task {
            let c = try? await Task.detached(priority: .userInitiated) {
                try nucleo.conversacionDelChat(ficha: chat, mensajes: autorias, desfaseMs: desfase)
            }.value
            guard mio == self.turno else { return }
            var nuevos: [String: LadoDeMensaje] = [:]
            for l in c?.lados ?? [] { nuevos[l.id] = l }
            if nuevos != self.lados { self.lados = nuevos }
        }
    }
}

/// **Una burbuja en su lado** de la conversacion: la mia a la derecha con
/// mi color, la de otra persona a la izquierda y, si abre su tanda, su
/// circulo con la inicial y su nombre encima, los dos de su color (como un
/// grupo de Telegram). Sin lado (un chat normal), como siempre.
struct EnSuLado: ViewModifier {
    let lado: LadoDeMensaje?
    let f: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let lado {
            VStack(alignment: lado.mio ? .trailing : .leading, spacing: 3 * f) {
                if let nombre = lado.nombre {
                    NombreDePersona(nombre: nombre, inicial: lado.inicial, color: Color(hex: lado.color), f: f)
                }
                content.environment(\.burbujaMia, lado.mio)
            }
            // Lo que se le reserva al lado contrario (`MARGEN_CONTRARIO`):
            // de un vistazo se ve de quien es cada tanda.
            .padding(lado.mio ? .leading : .trailing, 56 * f)
            .padding(.top, lado.abreTanda ? 6 * f : 0)
            .frame(maxWidth: .infinity, alignment: lado.mio ? .trailing : .leading)
        } else {
            content
        }
    }
}

/// El nombre de quien escribe, encima de su tanda
/// (`pintar_nombre_de_persona` de Windows).
struct NombreDePersona: View {
    let nombre: String
    let inicial: String
    let color: Color
    let f: CGFloat

    var body: some View {
        HStack(spacing: 6 * f) {
            ZStack {
                Circle().fill(color)
                Text(inicial)
                    .font(.system(size: 9.5 * f, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 17.5 * f, height: 17.5 * f)
            Text(nombre)
                .font(.system(size: 12.5 * f, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.leading, 2 * f)
    }
}

/// **La chapa de chat compartido**: un circulito verde con las dos
/// personas, abajo a la derecha del avatar y con un aro del color de lo de
/// detras (`aro`), como el punto de «en linea» de Telegram
/// (`pintar_chapa_compartido` de Windows).
struct ChapaCompartido: View {
    /// El lado del avatar.
    let avatar: CGFloat
    let aro: Color

    var body: some View {
        let lado = max(avatar * 0.46, 10)
        let grosor = max(lado * 0.12, 1)
        ZStack {
            Circle().fill(aro)
            // `VERDE_COMPARTIDO` de Windows: ni el azul de lo mio ni ningun
            // color de persona.
            Circle().fill(Color(hex: 0x2E9E62)).padding(grosor)
            Image(systemName: "person.2.fill")
                .font(.system(size: (lado - 2 * grosor) * 0.45))
                .foregroundStyle(.white)
        }
        .frame(width: lado, height: lado)
        // Asoma un quinto por fuera del avatar, como en Windows.
        .offset(x: lado * 0.2, y: lado * 0.2)
    }
}

private struct ClaveBurbujaMia: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// La burbuja es mia en un chat compartido: lleva mi color.
    var burbujaMia: Bool {
        get { self[ClaveBurbujaMia.self] }
        set { self[ClaveBurbujaMia.self] = newValue }
    }
}

/// **El chat recien nacido compartido**: «Chats compartidos» abre ya su
/// invitacion (sus personas: el codigo y el QR), como Windows al ponerle
/// nombre.
@MainActor
public final class PeticionDeInvitar: ObservableObject {
    public static let compartida = PeticionDeInvitar()
    /// La ficha (`FichaChat.id`) a la que invitar.
    @Published public var ficha: String?
}
