//! **Que lleva el menu de un mensaje, segun lo que es** (Windows 12e107b,
//! `ventana_chat/opciones_del_mensaje.rs`, como el movil 442eadf): de lo que
//! antes salia en todos, que sale en cada tipo.
//!
//! - **Recordarmelo** (en una nota de voz, la llamada secreta): a la vista
//!   en una nota, un enlace, una mini-app y una nota de voz; en «Más» en
//!   una foto o una hoja; nunca en un documento, un archivo, un video, una
//!   cancion, una clase, una carpeta ni una respuesta del asistente. Con uno
//!   ya puesto se ofrece quitarlo siempre.
//! - **Hacer leccion**: a la vista de una nota, una nota de voz o una clase;
//!   en «Más» de un enlace, una foto, una hoja o una respuesta del
//!   asistente; nunca de un archivo, un documento, un video, una cancion,
//!   una mini-app ni una carpeta.
//! - **Letra**: la de una clase es «Estudiar la clase» (Windows no abre la
//!   letra de una clase: una sola pantalla para una misma clase).
//!
//! Va en [`crate::chats::MensajeChat`] ya decidido, para que Swift solo
//! ponga cada entrada donde se le dice.

use std::path::Path;

use pixpin_proyecto::cuaderno::{Clase, Mensaje};

/// Lo que es el mensaje, a efectos de su menu (`OpcionesDelMensaje.Tipo`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TipoDeMensaje {
    /// Una nota escrita.
    Nota,
    /// Una nota escrita que lleva una direccion web.
    Enlace,
    /// Una nota de voz.
    Voz,
    /// Una cancion (`estadoDelTexto = letra`).
    Musica,
    /// La nota de una clase o reunion grabada.
    Grabacion,
    Foto,
    Video,
    /// Un documento que se lee: PDF, Word, libro, pagina, texto...
    Documento,
    /// Cualquier otro archivo: un zip, un plano, un instalador.
    Archivo,
    /// Lo que se abre como hoja: un lienzo, una pagina de un PDF, un croquis.
    Hoja,
    /// Una lista de tareas, una tabla u otra mini-app.
    MiniApp,
    /// Una carpeta de paginas, la de una grabacion o el acceso a un proyecto.
    Carpeta,
    /// Una respuesta del asistente.
    Asistente,
}

/// Donde va una entrada del menu.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SitioEnElMenu {
    /// A la vista.
    Vista,
    /// En el submenu «Más».
    Mas,
}

/// Los videos (`pixpin_shell::asociaciones::VIDEOS` de Windows).
const VIDEOS: [&str; 10] = [
    "mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "mpg", "mpeg", "ts",
];

/// La palabra de `estadoDelTexto` de una cancion (`biblioteca_audio::TEXTO_LETRA`).
const TEXTO_LETRA: &str = "letra";

fn extension(s: &str) -> String {
    Path::new(s)
        .extension()
        .map(|e| e.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default()
}

/// Si Lectura Veloz lee el archivo (`chapas::se_ofrece_lectura_veloz`).
pub(crate) fn se_ofrece_lectura_veloz(m: &Mensaje) -> bool {
    use pixpin_docs::lectura_veloz::tipo_de;
    m.clase == Some(Clase::Archivo)
        && m.ruta.as_deref().is_some_and(|r| !r.is_empty())
        && (tipo_de(Path::new(&m.nombre)).is_some()
            || m.ruta
                .as_deref()
                .is_some_and(|r| tipo_de(r.as_ref()).is_some()))
}

/// Si es una cancion (`biblioteca_audio::es_musica`).
fn es_musica(m: &Mensaje) -> bool {
    m.clase == Some(Clase::Voz)
        && m.resto
            .get("estadoDelTexto")
            .and_then(|v| v.as_str())
            .is_some_and(|v| v == TEXTO_LETRA)
}

/// **Que [`TipoDeMensaje`] es `m`.**
pub fn tipo_de(m: &Mensaje) -> TipoDeMensaje {
    if crate::asistente::chat::es_del_asistente(m) && matches!(m.clase, None | Some(Clase::Nota)) {
        return TipoDeMensaje::Asistente;
    }
    if pixpin_proyecto::carpeta_de_paginas::es_carpeta(m) || m.clase == Some(Clase::Proyecto) {
        return TipoDeMensaje::Carpeta;
    }
    match &m.clase {
        None | Some(Clase::Nota) => {
            if crate::ficha_del_chat::primer_enlace(&m.texto).is_some() {
                TipoDeMensaje::Enlace
            } else {
                TipoDeMensaje::Nota
            }
        }
        Some(Clase::Voz) => {
            if es_musica(m) {
                TipoDeMensaje::Musica
            } else if crate::estudiar_clase::de_una_clase(m).is_some()
                || m.resto.contains_key("capturas")
            {
                TipoDeMensaje::Grabacion
            } else {
                TipoDeMensaje::Voz
            }
        }
        Some(Clase::Imagen) => TipoDeMensaje::Foto,
        Some(Clase::Archivo) => {
            let es_video = [m.nombre.as_str(), m.ruta.as_deref().unwrap_or_default()]
                .iter()
                .any(|s| VIDEOS.contains(&extension(s).as_str()));
            if es_video {
                TipoDeMensaje::Video
            } else if !crate::lecciones::es_leccion(m) && se_ofrece_lectura_veloz(m) {
                TipoDeMensaje::Documento
            } else {
                TipoDeMensaje::Archivo
            }
        }
        Some(Clase::MiniApp) => TipoDeMensaje::MiniApp,
        Some(Clase::Dibujo | Clase::Pagina | Clase::Proyecto | Clase::Otra(_)) => {
            TipoDeMensaje::Hoja
        }
    }
}

/// **Donde va «Recordármelo»** (o la llamada secreta), o `None` si en este
/// tipo no tiene sentido. `recordado`: ya tiene una hora puesta, y entonces
/// la entrada es la de quitarla, que va siempre a la vista.
pub fn recordar(tipo: TipoDeMensaje, recordado: bool) -> Option<SitioEnElMenu> {
    use TipoDeMensaje as T;
    if recordado {
        return Some(SitioEnElMenu::Vista);
    }
    match tipo {
        T::Nota | T::Enlace | T::MiniApp | T::Voz => Some(SitioEnElMenu::Vista),
        T::Foto | T::Hoja => Some(SitioEnElMenu::Mas),
        _ => None,
    }
}

/// **Donde va «Hacer lección»**, o `None` si de este tipo no sale una (ni de
/// una leccion: eso lo mira quien llama).
pub fn leccion(tipo: TipoDeMensaje) -> Option<SitioEnElMenu> {
    use TipoDeMensaje as T;
    match tipo {
        T::Nota | T::Voz | T::Grabacion => Some(SitioEnElMenu::Vista),
        T::Enlace | T::Foto | T::Hoja | T::Asistente => Some(SitioEnElMenu::Mas),
        _ => None,
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use TipoDeMensaje as T;

    fn de(clase: Clase, nombre: &str) -> Mensaje {
        Mensaje {
            id: "m".into(),
            clase: Some(clase),
            texto: "algo".into(),
            nombre: nombre.into(),
            ruta: (!nombre.is_empty()).then(|| nombre.to_string()),
            ..Mensaje::default()
        }
    }

    #[test]
    fn cada_mensaje_es_de_su_tipo() {
        assert_eq!(tipo_de(&de(Clase::Nota, "")), T::Nota);
        let mut enlace = de(Clase::Nota, "");
        enlace.texto = "mira https://example.com/a".into();
        assert_eq!(tipo_de(&enlace), T::Enlace);
        assert_eq!(tipo_de(&de(Clase::Voz, "voz.m4a")), T::Voz);
        let mut clase = de(Clase::Voz, "clase.m4a");
        clase
            .resto
            .insert("grabacion".into(), serde_json::json!("clase"));
        assert_eq!(tipo_de(&clase), T::Grabacion);
        let mut cancion = de(Clase::Voz, "cancion.mp3");
        cancion
            .resto
            .insert("estadoDelTexto".into(), serde_json::json!("letra"));
        assert_eq!(tipo_de(&cancion), T::Musica);
        assert_eq!(tipo_de(&de(Clase::Imagen, "f.png")), T::Foto);
        assert_eq!(tipo_de(&de(Clase::Archivo, "Tesis.pdf")), T::Documento);
        assert_eq!(tipo_de(&de(Clase::Archivo, "clase.mp4")), T::Video);
        assert_eq!(tipo_de(&de(Clase::Archivo, "fotos.zip")), T::Archivo);
        assert_eq!(tipo_de(&de(Clase::Dibujo, "")), T::Hoja);
        let mut lista = de(Clase::MiniApp, "");
        lista.miniapp = Some(pixpin_proyecto::mini::TAREAS.into());
        assert_eq!(tipo_de(&lista), T::MiniApp);
        let mut carpeta = de(Clase::MiniApp, "");
        carpeta.miniapp = Some(pixpin_proyecto::carpeta_de_paginas::MINIAPP.into());
        assert_eq!(tipo_de(&carpeta), T::Carpeta);
        let mut ia = de(Clase::Nota, "");
        ia.aparato = Some(crate::asistente::chat::APARATO.into());
        assert_eq!(tipo_de(&ia), T::Asistente);
    }

    /// El caso del usuario: un PDF no ofrece ni recordatorio ni leccion.
    #[test]
    fn un_pdf_no_ofrece_recordatorio_ni_leccion() {
        let pdf = tipo_de(&de(Clase::Archivo, "Tesis.pdf"));
        assert_eq!(recordar(pdf, false), None);
        assert_eq!(leccion(pdf), None);
        // Pero si ya tiene uno puesto (del movil de antes), se puede quitar.
        assert_eq!(recordar(pdf, true), Some(SitioEnElMenu::Vista));
    }

    #[test]
    fn recordar_solo_donde_tiene_sentido() {
        for t in [T::Nota, T::Enlace, T::MiniApp, T::Voz] {
            assert_eq!(recordar(t, false), Some(SitioEnElMenu::Vista), "{t:?}");
        }
        for t in [T::Foto, T::Hoja] {
            assert_eq!(recordar(t, false), Some(SitioEnElMenu::Mas), "{t:?}");
        }
        for t in [
            T::Musica,
            T::Grabacion,
            T::Video,
            T::Documento,
            T::Archivo,
            T::Carpeta,
            T::Asistente,
        ] {
            assert_eq!(recordar(t, false), None, "{t:?}");
        }
    }

    #[test]
    fn la_leccion_sale_de_lo_que_se_estudia() {
        for t in [T::Nota, T::Voz, T::Grabacion] {
            assert_eq!(leccion(t), Some(SitioEnElMenu::Vista), "{t:?}");
        }
        for t in [T::Enlace, T::Foto, T::Hoja, T::Asistente] {
            assert_eq!(leccion(t), Some(SitioEnElMenu::Mas), "{t:?}");
        }
        for t in [
            T::Musica,
            T::Video,
            T::Documento,
            T::Archivo,
            T::MiniApp,
            T::Carpeta,
        ] {
            assert_eq!(leccion(t), None, "{t:?}");
        }
    }

    /// El mensaje que llega a Swift trae el tipo y los sitios ya puestos.
    #[test]
    fn el_mensaje_del_chat_lleva_su_menu() {
        let pdf = crate::chats::MensajeChat::from(de(Clase::Archivo, "Tesis.pdf"));
        assert_eq!(pdf.tipo, Some(T::Documento));
        assert_eq!(pdf.menu_recordar, None);
        assert_eq!(pdf.menu_leccion, None);
        let nota = crate::chats::MensajeChat::from(de(Clase::Nota, ""));
        assert_eq!(nota.menu_recordar, Some(SitioEnElMenu::Vista));
        assert_eq!(nota.menu_leccion, Some(SitioEnElMenu::Vista));
    }
}
