// Borrar mensajes del chat, como en Windows (`ventana_chat.rs`):
//
// - en el menu de cada burbuja, «Borrar» en rojo y aparte (con ⌫ mientras
//   el menu esta abierto, la «Supr» de Windows) y «Elegir varios»;
// - ⌘-clic marca o desmarca una burbuja (el Ctrl+clic de Windows) y, con
//   alguna marcada, un clic tambien; ⇧-clic marca el tramo;
// - con marcadas, una barra encima de la caja de escribir: cuantas,
//   «Borrar» y «Cancelar» (Escape);
// - antes de borrar se pregunta, con «Cancelar» por defecto (el
//   `confirmar_destructivo` de Windows). No hay deshacer: Windows tampoco
//   lo tiene, y el fichero adjunto se borra con su mensaje.
//
// Lo que borra es `Almacen.borrar(mensajes:en:)` (`Nucleo.borrarMensajes`).

import AppKit
import PixPinCore
import SwiftUI

/// Lo que el menu de una burbuja puede hacer con su mensaje. Lo pone el
/// chat (`VistaChat`) en el entorno de cada burbuja, para que lo usen
/// tambien los menus propios de las burbujas (fichero, nota, voz), que
/// tapan al de fuera.
struct AccionesDeMensaje {
    var marcado: Bool
    var marcar: () -> Void
    var borrar: () -> Void
}

private struct ClaveAccionesDeMensaje: EnvironmentKey {
    static let defaultValue: AccionesDeMensaje? = nil
}

extension EnvironmentValues {
    var accionesDeMensaje: AccionesDeMensaje? {
        get { self[ClaveAccionesDeMensaje.self] }
        set { self[ClaveAccionesDeMensaje.self] = newValue }
    }
}

/// Las entradas comunes del menu de un mensaje: elegir varios y, en rojo y
/// aparte, borrar. Fuera de un chat (sin acciones en el entorno), nada.
struct EntradasDeMensaje: View {
    @Environment(\.accionesDeMensaje) private var acciones

    var body: some View {
        if let acciones {
            Divider()
            Button(acciones.marcado ? "Quitar de los elegidos" : "Elegir varios", action: acciones.marcar)
            Divider()
            Button("Borrar", role: .destructive, action: acciones.borrar)
                .keyboardShortcut(.delete, modifiers: [])
        }
    }
}

/// **La pregunta antes de borrar**, con los textos de Windows
/// (`chat-borrar`, `chat-borrar-aviso`). «Cancelar» es el boton por
/// defecto: Intro no borra nada.
@MainActor
enum ConfirmarBorrar {
    nonisolated static let titulo = "Borrar"
    nonisolated static let aviso = "Se quitará de la conversación. Un archivo adjunto se borra con él. ¿Seguir?"

    /// El titulo con cuantos son, si es mas de uno.
    nonisolated static func titulo(cuantos: Int) -> String {
        cuantos > 1 ? "Borrar \(cuantos) mensajes" : titulo
    }

    static func preguntar(cuantos: Int) -> Bool {
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        alerta.messageText = titulo(cuantos: cuantos)
        alerta.informativeText = aviso
        let borrar = alerta.addButton(withTitle: "Borrar")
        borrar.hasDestructiveAction = true
        borrar.keyEquivalent = ""
        let cancelar = alerta.addButton(withTitle: "Cancelar")
        cancelar.keyEquivalent = "\r"
        return alerta.runModal() == .alertFirstButtonReturn
    }
}

/// **Los mensajes elegidos de un chat** y como cambian al hacer clic
/// (puro, sin vistas: se prueba solo).
struct Eleccion: Equatable {
    private(set) var ids: Set<String> = []
    /// El ultimo tocado: desde el sale el tramo de ⇧-clic.
    private(set) var ancla: String?

    var vacia: Bool { ids.isEmpty }

    /// ⌘-clic (o «Elegir varios»): lo pone o lo quita.
    mutating func alternar(_ id: String) {
        if ids.remove(id) == nil { ids.insert(id) }
        ancla = id
    }

    /// ⇧-clic: todo lo de entre el ancla y `id` (en el orden de `orden`)
    /// queda elegido. Sin ancla que se vea, solo `id`.
    mutating func tramo(hasta id: String, en orden: [String]) {
        guard let ancla, let a = orden.firstIndex(of: ancla), let b = orden.firstIndex(of: id) else {
            alternar(id)
            return
        }
        ids.formUnion(orden[min(a, b)...max(a, b)])
        self.ancla = id
    }

    /// Los elegidos en el orden del chat (los que ya no estan, fuera).
    func enOrden(_ orden: [String]) -> [String] {
        orden.filter { ids.contains($0) }
    }

    /// Olvida los que ya no estan cargados (borrados, otra pagina).
    mutating func quedarse(con presentes: Set<String>) {
        ids.formIntersection(presentes)
        if let a = ancla, !presentes.contains(a) { ancla = nil }
    }

    mutating func vaciar() {
        ids = []
        ancla = nil
    }
}

/// La barra de los elegidos, encima de la caja de escribir.
struct BarraDeElegidos: View {
    let cuantos: Int
    let borrar: () -> Void
    let cancelar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(cuantos == 1 ? "1 elegido" : "\(cuantos) elegidos")
                .font(.callout.weight(.medium))
            Spacer()
            Button(role: .destructive, action: borrar) {
                Label("Borrar", systemImage: "trash")
            }
            .foregroundStyle(.red)
            Button("Cancelar", action: cancelar)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
