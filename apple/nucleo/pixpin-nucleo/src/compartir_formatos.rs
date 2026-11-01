//! **Compartir igual en toda la app** (Windows 5df1ecde y 4a6112d4): lo que
//! la hoja de compartir del Mac (`PixPinKit/Compartir/`) decide igual venga
//! de donde venga.
//!
//! - **El orden y el nombre de los formatos** ([`orden_de_formatos_compartidos`],
//!   [`nombre_de_formato_compartido`]): `ClaseDeFormato` y
//!   `FORMATOS_EN_ORDEN` de `pindesk_ui::hoja_compartir` de Windows (el
//!   `FormatosDeCompartir.Clase` del movil). Quien abre la hoja solo dice
//!   **que** formatos hay, por su id; el orden (Imagen PNG, Imagen JPG,
//!   Dibujo SVG, PDF, Pagina web (HTML), Word, Markdown, Texto, Tabla (CSV),
//!   lo propio, PinDesk (.pindesk), Original, Anki) y el nombre se deciden
//!   aqui, una vez para toda la app. Se abre con el que iba primero (una
//!   foto o un PDF, su original).
//! - **Un cuaderno con todos sus formatos** (`compartir/carpeta.rs` de
//!   Windows): lo marcado con sus carpetas abiertas en paginas
//!   ([`Nucleo::mensajes_con_sus_paginas`], `con_sus_paginas`), y el
//!   Markdown, el texto y el Word de las notas y transcripciones de sus
//!   paginas ([`textos_de_cuaderno`], [`word_de_markdown`]).
//!
//! Los nombres son los del catalogo de Windows en español
//! (`crates/pindesk-store/i18n/es-ES/main.ftl`, `compartir-png`...): la app
//! del Mac habla español y el catalogo de este nucleo es anterior a esos
//! rotulos.

use std::collections::HashSet;

use pindesk_proyecto::almacen;
use pindesk_proyecto::carpeta_de_paginas::{self as carpetas, Carpeta};
use pindesk_proyecto::cuaderno::{self, Mensaje};

use crate::carpetas::PaginaDeCarpeta;
use crate::chats::validar_chat;
use crate::{ErrorNucleo, MensajeChat, Nucleo};

// ---------------------------------------------------------------------------
// El orden y el nombre de los formatos

/// Cada formato de la hoja, en el orden en que sale (`ClaseDeFormato` de
/// Windows).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ClaseDeFormato {
    Png,
    Jpg,
    Svg,
    Pdf,
    Web,
    Word,
    Markdown,
    Texto,
    Csv,
    /// Lo propio de un contenido (el DXF de un plano): con su nombre.
    Otro,
    Pixpin,
    Original,
    Anki,
    Wifi,
}

/// **La tabla unica**: cada clase, en el orden de la hoja, con su nombre
/// (`FORMATOS_EN_ORDEN` y sus rotulos del catalogo). `Otro` lleva el que le
/// da quien lo ofrece.
const FORMATOS_EN_ORDEN: [(ClaseDeFormato, &str, &str); 14] = [
    (ClaseDeFormato::Png, "png", "Imagen PNG"),
    (ClaseDeFormato::Jpg, "jpg", "Imagen JPG"),
    (ClaseDeFormato::Svg, "svg", "Dibujo SVG"),
    (ClaseDeFormato::Pdf, "pdf", "PDF"),
    (ClaseDeFormato::Web, "web", "Página web (HTML)"),
    (ClaseDeFormato::Word, "word", "Word"),
    (ClaseDeFormato::Markdown, "md", "Markdown"),
    (ClaseDeFormato::Texto, "texto", "Texto"),
    (ClaseDeFormato::Csv, "csv", "Tabla (CSV)"),
    (ClaseDeFormato::Otro, "otro", ""),
    // La clase sigue diciendose `pixpin` (la usa la app de Swift); el
    // fichero que sale es `.pindesk` (`compartir-pindesk` de Windows).
    (ClaseDeFormato::Pixpin, "pixpin", "PinDesk (.pindesk)"),
    (ClaseDeFormato::Original, "original", "Original"),
    (ClaseDeFormato::Anki, "anki", "Anki"),
    (ClaseDeFormato::Wifi, "wifi", "Por Wi‑Fi a mis aparatos"),
];

impl ClaseDeFormato {
    /// **De que clase es un formato por su id** (`de_id` de Windows): las
    /// variantes caen en su clase por el prefijo (`pdf-limpio`,
    /// `web-imagen`).
    pub fn de_id(id: &str) -> ClaseDeFormato {
        let i = id.to_ascii_lowercase();
        match i.as_str() {
            "png" | "imagen" => ClaseDeFormato::Png,
            "jpg" | "jpeg" => ClaseDeFormato::Jpg,
            "svg" => ClaseDeFormato::Svg,
            "word" | "docx" => ClaseDeFormato::Word,
            "md" | "markdown" => ClaseDeFormato::Markdown,
            "texto" | "txt" => ClaseDeFormato::Texto,
            "csv" => ClaseDeFormato::Csv,
            "editable" | "pindesk" | "pixpin" => ClaseDeFormato::Pixpin,
            "original" | "originales" => ClaseDeFormato::Original,
            "anki" => ClaseDeFormato::Anki,
            "wifi" => ClaseDeFormato::Wifi,
            _ if i == "pdf" || i.starts_with("pdf-") => ClaseDeFormato::Pdf,
            _ if i == "web" || i.starts_with("web-") => ClaseDeFormato::Web,
            _ => ClaseDeFormato::Otro,
        }
    }

    fn fila(self) -> (ClaseDeFormato, &'static str, &'static str) {
        FORMATOS_EN_ORDEN
            .iter()
            .copied()
            .find(|(c, _, _)| *c == self)
            .unwrap_or((ClaseDeFormato::Otro, "otro", ""))
    }
}

/// **Los formatos puestos en el orden de la hoja**: `orden[k]` es la
/// posicion (en lo que se dio) del que va en el sitio `k`, y `inicial`, el
/// sitio en que quedo el que iba primero: es el que se pone al abrir.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OrdenDeFormatos {
    pub orden: Vec<u32>,
    pub inicial: u32,
}

/// **Pone los formatos `ids` en el orden de la hoja** (`ordenar` de
/// Windows): los de la misma clase, como venian.
#[uniffi::export]
pub fn orden_de_formatos_compartidos(ids: Vec<String>) -> OrdenDeFormatos {
    let mut orden: Vec<u32> = (0..ids.len() as u32).collect();
    orden.sort_by_key(|&i| ClaseDeFormato::de_id(&ids[i as usize]));
    let inicial = orden.iter().position(|&i| i == 0).unwrap_or(0) as u32;
    OrdenDeFormatos { orden, inicial }
}

/// **El nombre con el que sale el formato `id`**: el de su clase, o
/// `propio` si es lo propio de un contenido (el DXF de un plano).
#[uniffi::export]
pub fn nombre_de_formato_compartido(id: String, propio: String) -> String {
    match ClaseDeFormato::de_id(&id).fila() {
        (ClaseDeFormato::Otro, _, _) => propio,
        (_, _, nombre) => nombre.to_string(),
    }
}

/// **La clase del formato `id`**, por su nombre corto (`png`, `web`,
/// `original`, `otro`...): la que decide su icono, el mismo en toda la app
/// (`icono_de` de Windows).
#[uniffi::export]
pub fn clase_de_formato_compartido(id: String) -> String {
    ClaseDeFormato::de_id(&id).fila().1.to_string()
}

// ---------------------------------------------------------------------------
// Los cuadernos

/// Las paginas vivas de una carpeta en su orden (en una grabacion, lo
/// adjuntado detras), con `todos` el chat entero.
fn paginas_de<'a>(carpeta: &Mensaje, todos: &'a [Mensaje]) -> Vec<&'a Mensaje> {
    let Some(c) = Carpeta::de_mensaje(carpeta) else {
        return Vec::new();
    };
    let mut vivas = c.vivas(todos);
    if c.es_grabacion() {
        vivas.sort_by_key(|(_, p)| p.adjunto);
    }
    vivas.into_iter().map(|(i, _)| &todos[i]).collect()
}

/// **Lo marcado, con las carpetas abiertas** (`con_sus_paginas` de
/// Windows): una carpeta va con sus paginas (las que no esten ya), en su
/// sitio, y no con el JSON de su documento. Lo que no es carpeta, tal cual.
pub fn con_sus_paginas(lista: &[Mensaje], todos: &[Mensaje]) -> Vec<Mensaje> {
    let mut vistos = HashSet::new();
    lista
        .iter()
        .flat_map(|m| {
            if carpetas::es_carpeta(m) {
                paginas_de(m, todos).into_iter().cloned().collect()
            } else {
                vec![m.clone()]
            }
        })
        .filter(|m| vistos.insert(m.id.clone()))
        .collect()
}

#[uniffi::export]
impl Nucleo {
    /// **Los mensajes `ids` del chat, con sus carpetas abiertas en paginas**
    /// (lo marcado en el chat que lleva un cuaderno), en el orden en que se
    /// dan. Lo que ya no esta se salta. Bloqueante.
    pub fn mensajes_con_sus_paginas(
        &self,
        chat: String,
        ids: Vec<String>,
    ) -> Result<Vec<MensajeChat>, ErrorNucleo> {
        validar_chat(&chat)?;
        let todos = cuaderno::Cuaderno::leer_de(&almacen::carpeta(self.ruta(), &chat))?.mensajes;
        let lista: Vec<Mensaje> = ids
            .iter()
            .filter_map(|id| todos.iter().find(|m| &m.id == id).cloned())
            .collect();
        Ok(con_sus_paginas(&lista, &todos)
            .into_iter()
            .map(MensajeChat::from)
            .collect())
    }
}

/// El texto de una pagina que lo lleva (`texto_de` de Windows): una nota
/// escrita o la transcripcion de una nota de voz. Una mini-app, una foto o
/// un lienzo, no.
fn texto_de(m: &MensajeChat) -> Option<String> {
    let texto = match m.clase.as_str() {
        "" | "NOTA" if m.miniapp.is_none() => m.texto.trim().to_string(),
        "VOZ" => m.transcripcion.as_deref().unwrap_or("").trim().to_string(),
        _ => return None,
    };
    (!texto.is_empty()).then_some(texto)
}

/// Lo que un cuaderno da en texto: su Markdown y el mismo texto llano.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TextosDeCuaderno {
    /// El titulo del cuaderno arriba y cada pagina con texto bajo el suyo.
    pub markdown: String,
    /// Lo mismo sin las marcas de los titulos, para el `.txt`.
    pub texto: String,
}

/// **El Markdown y el texto de las notas del cuaderno** (`markdown` y
/// `texto_llano` de Windows). `None` si ninguna pagina lleva texto: entonces
/// no se ofrecen Word, Markdown ni Texto.
#[uniffi::export]
pub fn textos_de_cuaderno(
    titulo: String,
    paginas: Vec<PaginaDeCarpeta>,
) -> Option<TextosDeCuaderno> {
    let con_texto: Vec<(String, String)> = paginas
        .iter()
        .filter_map(|p| Some((p.titulo.clone(), texto_de(&p.mensaje)?)))
        .collect();
    if con_texto.is_empty() {
        return None;
    }
    let md: Vec<String> = con_texto
        .iter()
        .map(|(t, x)| format!("## {t}\n\n{x}"))
        .collect();
    let llano: Vec<String> = con_texto
        .iter()
        .map(|(t, x)| format!("{t}\n\n{x}"))
        .collect();
    Some(TextosDeCuaderno {
        markdown: format!("# {titulo}\n\n{}\n", md.join("\n\n")),
        texto: format!("{titulo}\n\n{}\n", llano.join("\n\n")),
    })
}

/// **Un Markdown como Word** (`.docx`), por el mismo escritor de las notas
/// (`pindesk_notas::word::exportar` de Windows).
#[uniffi::export]
pub fn word_de_markdown(titulo: String, markdown: String) -> Result<Vec<u8>, ErrorNucleo> {
    let sin_fotos = |_: &str| None;
    pindesk_docs::exportar_docx::exportar(&pindesk_docs::exportar_docx::Nota {
        markdown: &markdown,
        titulo: &titulo,
        letra: pindesk_docs::exportar_docx::Letra::default(),
        comentarios: None,
        imagen: &sin_fotos,
        autor: "",
        ahora_ms: crate::ahora_ms(),
    })
    .map_err(|e| ErrorNucleo::Disco {
        detalle: format!("no se pudo hacer el Word: {e}"),
    })
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn ids(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    /// El orden de Windows (`FORMATOS_EN_ORDEN`), venga como venga.
    #[test]
    fn los_formatos_salen_siempre_en_el_mismo_orden() {
        let dados = ids(&[
            "web",
            "pdf",
            "png",
            "jpg",
            "svg",
            "texto",
            "originales",
            "pixpin",
        ]);
        let o = orden_de_formatos_compartidos(dados.clone());
        let puestos: Vec<&str> = o
            .orden
            .iter()
            .map(|&i| dados[i as usize].as_str())
            .collect();
        assert_eq!(
            puestos,
            [
                "png",
                "jpg",
                "svg",
                "pdf",
                "web",
                "texto",
                "pixpin",
                "originales"
            ]
        );
        // Se abre con el que iba primero (la pagina web), no con el PNG.
        assert_eq!(puestos[o.inicial as usize], "web");
    }

    #[test]
    fn una_foto_se_abre_con_su_original_aunque_vaya_al_final() {
        let dados = ids(&["original", "pixpin", "web", "pdf", "png", "jpg", "svg"]);
        let o = orden_de_formatos_compartidos(dados.clone());
        let puestos: Vec<&str> = o
            .orden
            .iter()
            .map(|&i| dados[i as usize].as_str())
            .collect();
        assert_eq!(puestos.last(), Some(&"original"));
        assert_eq!(puestos[o.inicial as usize], "original");
    }

    #[test]
    fn lo_de_una_misma_clase_va_como_venia_y_lo_propio_antes_del_pixpin() {
        let dados = ids(&["anki", "dxf", "pdf-limpio", "pdf", "editable", "md", "word"]);
        let o = orden_de_formatos_compartidos(dados.clone());
        let puestos: Vec<&str> = o
            .orden
            .iter()
            .map(|&i| dados[i as usize].as_str())
            .collect();
        assert_eq!(
            puestos,
            ["pdf-limpio", "pdf", "word", "md", "dxf", "editable", "anki"]
        );
        // Caso negativo: sin formatos no hay nada que poner.
        let vacio = orden_de_formatos_compartidos(Vec::new());
        assert!(vacio.orden.is_empty());
        assert_eq!(vacio.inicial, 0);
    }

    #[test]
    fn cada_formato_se_llama_como_en_windows() {
        let n = |id: &str| nombre_de_formato_compartido(id.into(), "DXF".into());
        assert_eq!(n("png"), "Imagen PNG");
        assert_eq!(n("web"), "Página web (HTML)");
        assert_eq!(n("svg"), "Dibujo SVG");
        assert_eq!(n("originales"), "Original");
        assert_eq!(n("editable"), "PinDesk (.pindesk)");
        assert_eq!(n("pindesk"), "PinDesk (.pindesk)");
        assert_eq!(n("pixpin"), "PinDesk (.pindesk)");
        assert_eq!(clase_de_formato_compartido("pindesk".into()), "pixpin");
        assert_eq!(n("md"), "Markdown");
        // Lo propio lleva el nombre de quien lo ofrece.
        assert_eq!(n("dxf"), "DXF");
        assert_eq!(clase_de_formato_compartido("pdf-limpio".into()), "pdf");
        assert_eq!(clase_de_formato_compartido("originales".into()), "original");
        assert_eq!(clase_de_formato_compartido("dxf".into()), "otro");
    }

    fn mensaje(id: &str, clase: &str, texto: &str) -> MensajeChat {
        let mut m = MensajeChat::from(Mensaje {
            id: id.into(),
            texto: texto.into(),
            ..Default::default()
        });
        m.clase = clase.into();
        m
    }

    fn pagina(titulo: &str, m: MensajeChat) -> PaginaDeCarpeta {
        PaginaDeCarpeta {
            titulo: titulo.into(),
            mensaje: m,
            ms: None,
            adjunto: false,
            esquina: String::new(),
        }
    }

    /// El caso de Windows (`un_cuaderno_se_comparte_con_sus_paginas_y_los_formatos_de_texto`).
    #[test]
    fn el_texto_de_un_cuaderno_son_sus_notas_bajo_su_titulo() {
        let mut voz = mensaje("v", "VOZ", "");
        voz.transcripcion = Some("[0:01] lo dicho".into());
        let paginas = vec![
            pagina("Día 1", mensaje("d", "DIBUJO", "")),
            pagina("Día 2", mensaje("n", "NOTA", "Lo que paso entre medias")),
            pagina("Día 3", voz),
        ];
        let t = textos_de_cuaderno("Diario".into(), paginas).expect("con texto");
        assert!(t.markdown.starts_with("# Diario\n\n"), "{}", t.markdown);
        assert!(
            t.markdown.contains("## Día 2\n\nLo que paso entre medias"),
            "{}",
            t.markdown
        );
        assert!(
            t.markdown.contains("## Día 3\n\n[0:01] lo dicho"),
            "{}",
            t.markdown
        );
        assert!(!t.markdown.contains("Día 1"), "un lienzo no aporta texto");
        assert!(t.texto.starts_with("Diario\n\nDía 2\n\n"), "{}", t.texto);
        assert!(!t.texto.contains('#'));
        let docx = word_de_markdown("Diario".into(), t.markdown).unwrap();
        assert!(docx.starts_with(b"PK"), "un .docx es un zip");
    }

    #[test]
    fn un_cuaderno_sin_notas_no_da_texto() {
        let mut lista = mensaje("t", "NOTA", "[]");
        lista.miniapp = Some("tareas".into());
        let paginas = vec![
            pagina("Día 1", mensaje("d", "DIBUJO", "")),
            pagina("Día 2", lista),
            pagina("Día 3", mensaje("vacia", "NOTA", "   ")),
        ];
        assert_eq!(textos_de_cuaderno("Diario".into(), paginas), None);
        assert_eq!(textos_de_cuaderno("Diario".into(), Vec::new()), None);
    }

    fn nucleo(etiqueta: &str) -> (std::sync::Arc<Nucleo>, std::path::PathBuf, String) {
        let d = std::env::temp_dir().join(format!(
            "pixpin-compartir-formatos-{etiqueta}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        let chat = n.crear_chat("Diario".into()).unwrap();
        (n, d, chat.id)
    }

    /// `lo_marcado_con_un_cuaderno_lleva_sus_paginas_sin_repetir` de Windows.
    #[test]
    fn lo_marcado_con_un_cuaderno_lleva_sus_paginas_sin_repetir() {
        let (n, d, chat) = nucleo("marcado");
        let lienzo = n.crear_lienzo(chat.clone(), None).unwrap();
        let carpeta = n
            .crear_carpeta_de_paginas(chat.clone(), Some(lienzo.id.clone()))
            .unwrap();
        let nota = n
            .escribir_nota(chat.clone(), "Suelta".into(), None)
            .unwrap();
        let v = n
            .mensajes_con_sus_paginas(
                chat.clone(),
                vec![
                    lienzo.id.clone(),
                    carpeta.id.clone(),
                    nota.id.clone(),
                    "no-esta".into(),
                ],
            )
            .unwrap();
        let puestos: Vec<&str> = v.iter().map(|m| m.id.as_str()).collect();
        // El lienzo ya estaba: la carpeta no lo repite, y no va su JSON.
        assert_eq!(puestos, [lienzo.id.as_str(), nota.id.as_str()]);
        // Caso negativo: un chat que no es valido.
        assert!(
            n.mensajes_con_sus_paginas("../fuera".into(), vec![])
                .is_err()
        );
        let _ = std::fs::remove_dir_all(&d);
    }
}
