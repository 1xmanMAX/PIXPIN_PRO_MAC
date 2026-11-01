// Las notas de voz en el almacen: guardar una grabada y escribir su texto,
// cruzando el puente fuera del hilo principal (como el resto del almacen).

import Foundation
import PixPinCore

extension Almacen {
    /// Guarda una nota grabada en `chat` (`Nucleo.adjuntarVoz`: se copia
    /// como `voz_<hora>.m4a` con su duracion y sus picos) y la anade al
    /// final de lo cargado. El fichero grabado no se borra aqui.
    @discardableResult
    public func adjuntarVoz(_ nota: NotaGrabada, en chat: String) async -> MensajeChat? {
        let nucleo = self.nucleo
        let resultado = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
            Result {
                try nucleo.adjuntarVoz(chat: chat, rutaOrigen: nota.url.path,
                                       duracionMs: nota.duracionMs, picos: nota.picos)
            }
        }.value
        switch resultado {
        case let .success(m):
            anadir([m], en: chat)
            ponerError(nil)
            return m
        case let .failure(e):
            ponerError("\(e)")
            return nil
        }
    }

    /// Escribe lo reconocido en la nota `mensaje` (`Nucleo.ponerTranscripcion`:
    /// con sus minutos y `estadoDelTexto`, como Windows) y la cambia en lo
    /// cargado.
    @discardableResult
    public func ponerTranscripcion(_ segmentos: [SegmentoVoz], en mensaje: String,
                                   chat: String) async -> MensajeChat? {
        let nucleo = self.nucleo
        let resultado = await Task.detached(priority: .utility) { () -> Result<MensajeChat, Error> in
            Result { try nucleo.ponerTranscripcion(chat: chat, mensaje: mensaje, segmentos: segmentos) }
        }.value
        switch resultado {
        case let .success(m):
            sustituir(m, en: chat)
            // Lo importante de lo dicho (Jev, en segundo plano; sin clave,
            // nada), como Windows al acabar de pasar una nota a texto.
            buscarLoImportante(m.id, en: chat, forzar: true)
            return m
        case let .failure(e):
            ponerError("\(e)")
            return nil
        }
    }

    /// **Busca lo importante de una nota de voz** con Jev (tareas,
    /// decisiones, preguntas, examen: `resto["importantes"]`, que viaja), en
    /// segundo plano. `forzar`: aunque ya se mirara (el texto es nuevo).
    /// Sin clave de TypeSafe o con la funcion apagada no hace nada.
    public func buscarLoImportante(_ voz: String, en chat: String, forzar: Bool) {
        LlaveroDelSistema.instalar()
        TransporteHttps.instalar()
        let nucleo = self.nucleo
        Task {
            let escrito = await Task.detached(priority: .utility) {
                (try? nucleo.jevBuscarLoImportante(chat: chat, voz: voz, forzar: forzar)) ?? false
            }.value
            // A los otros aparatos, como cualquier cambio de aqui.
            if escrito { NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil) }
        }
    }

    /// Pasa a texto una nota de voz que ya esta en el chat (la grabada aqui
    /// al acabar, o una que llego sin texto) y lo guarda. `idioma`: el que
    /// se practicaba en Pronunciar (`en-US`), que manda. Devuelve si salio.
    @discardableResult
    public func transcribir(_ m: MensajeChat, en chat: String, idioma: String? = nil) async -> Bool {
        guard m.clase == "VOZ", let ruta = m.ruta, let url = await url(deRuta: ruta, en: chat) else { return false }
        do {
            let segmentos = try await TranscriptorVoz.transcribir(url, idioma: idioma.map(Locale.init(identifier:)))
            return await ponerTranscripcion(segmentos, en: m.id, chat: chat) != nil
        } catch {
            if idioma != nil, (error as? ErrorVoz) == .sinReconocedor {
                ponerError("Este Mac no tiene el reconocimiento de voz sin conexión para ese idioma. Actívalo en Ajustes del Sistema > Teclado > Dictado.")
            } else {
                ponerError(TranscriptorVoz.explicar(error))
            }
            return false
        }
    }
}

extension TranscriptorVoz {
    /// Lo que se le dice al usuario cuando no sale el texto.
    public static func explicar(_ error: Error) -> String {
        switch error as? ErrorVoz {
        case .sinPermisoTranscribir?:
            return "PinDesk no tiene permiso para reconocer voz (Ajustes del Sistema > Privacidad y seguridad > Reconocimiento de voz)."
        case .sinReconocedor?:
            return "Este Mac no tiene el reconocimiento de voz sin conexion para espanol. Activalo en Ajustes del Sistema > Teclado > Dictado."
        default:
            return "No se pudo pasar a texto: \(error.localizedDescription)"
        }
    }
}
