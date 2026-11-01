// **«Enviar a Anki»** del menu de un mensaje (Windows 2561be0,
// `ventana_chat/anki.rs`): las tarjetas de una clase grabada (una por
// captura), de una foto o de una nota («pregunta :: respuesta», «P: / R:»,
// huecos `{{c1::…}}`), al mazo `PixPin::<proyecto>`. Lo hace el nucleo
// (`Nucleo.enviarAAnki`: AnkiConnect en 127.0.0.1:8765 o, sin Anki, el
// fichero para importar); aqui, cuando sale en el menu y lo que se dice.

import Foundation
import PixPinCore

extension ChatAbierto {
    /// Si «Enviar a Anki» sale para este mensaje (`anki::se_puede`): una
    /// nota de voz con capturas, una foto con su fichero o una nota con
    /// tarjetas.
    func sePuedeAnki(_ m: MensajeChat) -> Bool {
        switch m.clase {
        case "VOZ": !ClaseEnElChat.capturas(m, chat: chat, nucleo: almacen.nucleo).isEmpty
        case "IMAGEN": m.ruta?.isEmpty == false
        default: ankiHayTarjetasEnNota(texto: m.texto)
        }
    }

    /// Manda las tarjetas del mensaje y dice como fue.
    func enviarAAnki(_ m: MensajeChat) {
        let nucleo = almacen.nucleo
        let chat = self.chat
        let id = m.id
        // Jev pregunta por el HTTPS de la app, con la clave del Llavero.
        LlaveroDelSistema.instalar()
        TransporteHttps.instalar()
        Task {
            // Con Jev, de una clase solo las que valen la pena (Windows
            // 6f70a41); lo que dejo fuera va al final del aviso.
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<EnvioAnkiConJev, Error> in
                Result { try nucleo.enviarAAnkiConJev(chat: chat, mensaje: id, preguntaDeLaClase: Lengua.t("anki-pregunta-clase")) }
            }.value
            switch hecho {
            case let .success(r):
                var texto = ChatAbierto.textoDeAnki(r.envio)
                if r.quitadas > 0 {
                    texto += " · " + textoJevAnkiQuitadas(locale: JevTextos.idioma, n: UInt64(r.quitadas))
                }
                avisar(texto)
            case .failure: avisar(Lengua.t("chat-no-se-pudo"))
            }
        }
    }

    /// Lo que se dice al acabar (`anki-*` de Windows).
    nonisolated static func textoDeAnki(_ r: EnvioAnki) -> String {
        switch r {
        case .nada:
            "Aquí no hay tarjetas. Escribe una por línea como «pregunta :: respuesta», o «P: …» y «R: …», o con huecos {{c1::así}}."
        case let .hecho(n, mazo):
            "\(n) tarjetas en Anki, mazo «\(mazo)»"
        case let .yaEstaban(_, mazo):
            "Esas tarjetas ya estaban en «\(mazo)»"
        case let .fichero(n, _, ruta):
            "Anki no está abierto (o le falta AnkiConnect). Guardé \(n) tarjetas en \(ruta): en Anki, Archivo → Importar."
        case let .fallo(motivo):
            "Anki no las admitió: \(motivo)"
        }
    }
}
