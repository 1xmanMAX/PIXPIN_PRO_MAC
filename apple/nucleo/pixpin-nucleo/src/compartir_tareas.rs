//! **Una lista de tareas en la hoja de compartir** (Windows f59890b,
//! bc4533b y 1746154, `compartir/tareas.rs`, 1-nov-2026; el usuario: «mejora
//! la apariencia de mis quehaceres cuando los exporto»).
//!
//! Antes la mini-app `tareas` salia como cualquier texto: renglones con las
//! marcas crudas a la vista (`⏫`, `➕ 2026-10-28`, los enlaces de las
//! fotos). Ahora cada formato sale de lo ya entendido
//! (`pindesk_proyecto::tareas_exportar`, el mismo de Windows):
//!
//! - **Pagina web** ([`tareas_web`]): la pagina propia de las tareas, con el
//!   resumen, las chapitas, las fotos dentro (en miniatura) y lo hecho
//!   plegado, si todo lo compartido son listas.
//! - **PDF, PNG, JPG y SVG**: las hojas A4 dibujadas con el mismo aire
//!   ([`tareas_hojas`], [`tareas_svg_de_hoja`]), que Swift pinta con el pintor
//!   del lienzo como las de una grabacion.
//! - **Word, Markdown y texto** ([`tareas_markdown`], [`tareas_texto`]),
//!   cuando la lista va sola. El Word es ese Markdown por el escritor de
//!   `.docx` (`word_de_markdown`).
//!
//! Los rotulos salen del catalogo (`tareas-exportar-*`, los catorce
//! idiomas) en el idioma de la app ([`rotulos`]).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use pindesk_ia::fechas::Momento;
use pindesk_motor2d::ColorRgba;
use pindesk_motor2d::exportar::{self as ex, Hoja};
use pindesk_motor2d::exportar_svg::{self, Incrustada, OpcionesSvg};
use pindesk_proyecto::almacen;
use pindesk_proyecto::tareas_exportar::{self as te, ListaParaExportar, Rotulos};
use pindesk_store::ajustes::PreferenciaIdioma;
use pindesk_store::idioma::{Catalogo, resolver_idioma};

use crate::chats::validar_chat;
use crate::compartir::HojaDeDibujo;
use crate::compartir_grabacion::FotoDeGrabacion;
use crate::{ErrorNucleo, Nucleo};

/// El lado mayor de una foto dentro de la pagina: se ensena en miniatura.
const LADO_FOTO: u32 = 360;
const BLANCO: ColorRgba = ColorRgba::opaco(1.0, 1.0, 1.0);

/// Una foto de una tarea: su enlace en el texto y su fichero en este Mac.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FotoDeTarea {
    pub enlace: String,
    pub ruta: String,
}

/// **Una lista lista para sacarla** (`ListaPreparada` de Windows): su
/// documento tal cual, el nombre de su fila y, de cada foto que esta en
/// este Mac, su fichero. Swift la guarda y la devuelve a cada formato.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ListaParaCompartir {
    pub titulo: String,
    pub documento: String,
    pub fotos: Vec<FotoDeTarea>,
}

impl ListaParaCompartir {
    fn lista(&self) -> ListaParaExportar {
        ListaParaExportar::del_documento(&self.documento, &self.titulo)
    }

    fn ruta(&self, enlace: &str) -> Option<PathBuf> {
        self.fotos
            .iter()
            .find(|f| f.enlace == enlace)
            .map(|f| PathBuf::from(&f.ruta))
    }
}

/// Las hojas A4 de una lista, con las fotos que pintan.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HojasDeTareas {
    pub hojas: Vec<HojaDeDibujo>,
    pub fotos: Vec<FotoDeGrabacion>,
}

/// **Lo que dicen las paginas**, del catalogo del idioma `idioma` (la
/// etiqueta de la app, `es-ES`…), como `rotulos` de Windows. Los patrones
/// llevan sus huecos entre llaves, que llena `tareas_exportar` (el catalogo
/// no aisla las variables, asi que pasan tal cual).
pub fn rotulos(idioma: &str) -> Rotulos {
    let t = Catalogo::nuevo(resolver_idioma(idioma, PreferenciaIdioma::Sistema));
    let con = |clave: &str, pares: &[(&str, &str)]| {
        let mut args = fluent_bundle::FluentArgs::new();
        for (k, v) in pares {
            args.set(*k, v.to_string());
        }
        t.t_args(clave, &args)
    };
    let fecha = [("dia", "{dia}"), ("mes", "{mes}"), ("ano", "{ano}")];
    Rotulos {
        idioma: t.t("grabacion-idioma"),
        tareas: t.t("tareas-exportar-titulo"),
        exportado: con("tareas-exportar-exportado", &[("fecha", "{fecha}")]),
        pendientes: t.t("tareas-exportar-pendientes"),
        hechas: t.t("tareas-exportar-hechas"),
        completado: t.t("tareas-exportar-completado"),
        pendiente: t.t("tareas-exportar-pendiente"),
        hecha: t.t("tareas-exportar-hecha"),
        todo_hecho: t.t("tareas-exportar-todo-hecho"),
        vacia: t.t("tareas-exportar-vacia"),
        urgente: t.t("tareas-urgente"),
        muy_urgente: t.t("tareas-muy-urgente"),
        recordatorio: t.t("tareas-exportar-recordatorio"),
        pasada: t.t("tareas-exportar-pasada"),
        creada: con("tareas-exportar-creada", &[("fecha", "{fecha}")]),
        hoy: t.t("tareas-selector-hoy"),
        manana: t.t("tareas-selector-manana"),
        ayer: t.t("chat-ayer"),
        de: con("tareas-exportar-de", &[("hechas", "{hechas}"), ("total", "{total}")]),
        foto: t.t("tareas-exportar-foto"),
        dias: std::array::from_fn(|i| t.t(&format!("tareas-dia-{i}"))),
        // Van dentro de «{dia} de {mes}»: el mes de dentro de una fecha
        // (genitivo en ruso, `chat-mes-dia-*`), no el suelto (Windows
        // 668fa506, `ventana_chat::mes_en_fecha`).
        meses: std::array::from_fn(|i| {
            let clave = format!("chat-mes-dia-{}", i + 1);
            if t.traducida(&clave) {
                t.t(&clave)
            } else {
                t.t(&format!("chat-mes-{}", i + 1))
            }
        }),
        fecha: con("chat-fecha", &fecha),
        fecha_con_ano: con("chat-fecha-con-ano", &fecha),
    }
}

fn ahora(desfase_ms: i64) -> Momento {
    Momento::de_ms_locales(crate::ahora_ms() + desfase_ms)
}

/// Las hojas y, de cada foto que va en ellas, su id (desde 1) y su fichero.
fn hojas_de(l: &ListaParaCompartir, r: &Rotulos, desfase_ms: i64) -> (Vec<Hoja>, Vec<(u64, PathBuf)>) {
    let lista = l.lista();
    let mut fotos: Vec<(u64, PathBuf)> = Vec::new();
    let mut ids: HashMap<String, u64> = HashMap::new();
    let titulo = lista.titulo.clone();
    let hojas = te::hojas(std::slice::from_ref(&lista), &titulo, r, ahora(desfase_ms), &mut |e| {
        let ruta = l.ruta(e)?;
        let (w, h) = pindesk_codec::imagen::medidas(&ruta).ok()?;
        let id = match ids.get(e) {
            Some(id) => *id,
            None => {
                let id = fotos.len() as u64 + 1;
                ids.insert(e.to_string(), id);
                fotos.push((id, ruta));
                id
            }
        };
        Some((id, w as f32, h as f32))
    });
    (hojas, fotos)
}

/// **Las hojas A4 de la lista** para el PDF, el PNG, el JPG y el SVG, con
/// las fotos que pintan. Siempre una al menos. Bloqueante (mide las fotos).
#[uniffi::export]
pub fn tareas_hojas(lista: ListaParaCompartir, idioma: String, desfase_ms: i64) -> HojasDeTareas {
    let (hojas, fotos) = hojas_de(&lista, &rotulos(&idioma), desfase_ms);
    HojasDeTareas {
        hojas: hojas
            .into_iter()
            .map(|h| {
                let (x0, y0, x1, y1) = h.caja;
                HojaDeDibujo {
                    nombre: String::new(),
                    es_marco: false,
                    x0,
                    y0,
                    x1,
                    y1,
                    plano: crate::lienzo::empaquetar(&h.ordenes, BLANCO, Some(h.caja)),
                    svg: String::new(),
                    fondo: ex::hex(BLANCO),
                }
            })
            .collect(),
        fotos: fotos
            .into_iter()
            .map(|(id, ruta)| FotoDeGrabacion {
                id_objeto: id,
                ruta: ruta.display().to_string(),
            })
            .collect(),
    }
}

/// **El SVG de la hoja `indice`** de [`tareas_hojas`], con las fotos dentro.
/// `None` si no hay esa hoja.
#[uniffi::export]
pub fn tareas_svg_de_hoja(lista: ListaParaCompartir, idioma: String, desfase_ms: i64, indice: u32) -> Option<String> {
    let (hojas, fotos) = hojas_de(&lista, &rotulos(&idioma), desfase_ms);
    let hoja = hojas.into_iter().nth(indice as usize)?;
    let incrustada = |id: u64| -> Option<Incrustada> {
        let (_, ruta) = fotos.iter().find(|(i, _)| *i == id)?;
        let bytes = std::fs::read(ruta).ok()?;
        Some(Incrustada {
            mime: crate::editor_exportar::mime_de(&bytes)?,
            bytes,
        })
    };
    Some(exportar_svg::svg(&hoja, OpcionesSvg { fondo: Some(BLANCO), marcos: false }, &incrustada))
}

/// Una foto en miniatura, como `data:` (JPEG si es opaca).
fn miniatura(ruta: &Path) -> Option<String> {
    let mut img = pindesk_codec::cargar(ruta).ok()?;
    let lado = img.ancho.max(img.alto);
    if lado > LADO_FOTO {
        let k = LADO_FOTO as f32 / lado as f32;
        let (w, h) = (
            ((img.ancho as f32 * k).round() as u32).max(1),
            ((img.alto as f32 * k).round() as u32).max(1),
        );
        img = pindesk_codec::imagen::redimensionar(img, w, h).ok()?;
    }
    let (mime, bytes) = if img.pixeles.chunks_exact(4).all(|q| q[3] == 255) {
        ("image/jpeg", pindesk_codec::imagen::codificar_jpg(&img, 82).ok()?)
    } else {
        ("image/png", pindesk_codec::codificar_png(&img).ok()?)
    };
    Some(format!("data:{mime};base64,{}", ex::base64(&bytes)))
}

/// **La pagina web de las listas** (una o varias) en `carpeta`, como
/// `<base>.html` (`tareas::web` de Windows). `titulo`: el de lo compartido;
/// con una lista sola, el suyo.
#[uniffi::export]
pub fn tareas_web(
    listas: Vec<ListaParaCompartir>,
    titulo: String,
    idioma: String,
    desfase_ms: i64,
    base: String,
    carpeta: String,
) -> Result<Vec<String>, ErrorNucleo> {
    let solo: Vec<ListaParaExportar> = listas.iter().map(ListaParaCompartir::lista).collect();
    let titulo = match solo.as_slice() {
        [una] if !una.titulo.trim().is_empty() => una.titulo.clone(),
        _ => titulo,
    };
    let foto = |e: &str| listas.iter().find_map(|l| l.ruta(e)).and_then(|r| miniatura(&r));
    let pagina = te::html(&solo, &titulo, &rotulos(&idioma), ahora(desfase_ms), &foto);
    let ruta = Path::new(&carpeta).join(format!("{base}.html"));
    std::fs::write(&ruta, pagina.as_bytes()).map_err(|e| ErrorNucleo::Disco {
        detalle: format!("no se pudo escribir {}: {e}", ruta.display()),
    })?;
    Ok(vec![ruta.display().to_string()])
}

/// **El Markdown de la lista** (de ahi sale tambien el Word).
#[uniffi::export]
pub fn tareas_markdown(lista: ListaParaCompartir, idioma: String, desfase_ms: i64) -> String {
    let l = lista.lista();
    te::markdown(std::slice::from_ref(&l), &l.titulo, &rotulos(&idioma), ahora(desfase_ms))
}

/// **El texto de la lista**, con sus casillas y sin las marcas crudas.
#[uniffi::export]
pub fn tareas_texto(lista: ListaParaCompartir, idioma: String, desfase_ms: i64) -> String {
    let l = lista.lista();
    te::texto(std::slice::from_ref(&l), &l.titulo, &rotulos(&idioma), ahora(desfase_ms))
}

#[uniffi::export]
impl Nucleo {
    /// **La lista `mensaje` del chat `chat`** para compartirla, con sus
    /// fotos resueltas en este Mac. `None` si no es una lista de tareas.
    pub fn lista_para_compartir(&self, chat: String, mensaje: String) -> Result<Option<ListaParaCompartir>, ErrorNucleo> {
        validar_chat(&chat)?;
        let fichero = almacen::carpeta(self.ruta(), &chat).join("guardados.jsonl");
        let Some(m) = crate::tareas::listas_del_cuaderno(&fichero)?
            .into_iter()
            .find(|m| m.id == mensaje)
        else {
            return Ok(None);
        };
        let titulo = crate::tareas::nombre_de_lista(&m);
        let lista = ListaParaExportar::del_documento(&m.texto, &titulo);
        let mut fotos: Vec<FotoDeTarea> = Vec::new();
        for e in lista.tareas.iter().flat_map(|t| &t.imagenes) {
            if fotos.iter().any(|f| &f.enlace == e) {
                continue;
            }
            if let Some(r) = self.resolver(&chat, e).filter(|r| r.is_file()) {
                fotos.push(FotoDeTarea {
                    enlace: e.clone(),
                    ruta: r.display().to_string(),
                });
            }
        }
        Ok(Some(ListaParaCompartir {
            titulo,
            documento: m.texto,
            fotos,
        }))
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    const DOC: &str = "# Casa\n\n- [ ] llamar al banco ⏫ #casa ➕ 2026-10-17\n- [x] pan ➕ 2026-10-16\n";

    fn lista() -> ListaParaCompartir {
        ListaParaCompartir {
            titulo: "Casa".into(),
            documento: DOC.into(),
            fotos: Vec::new(),
        }
    }

    #[test]
    fn la_lista_sale_sin_las_marcas_crudas_en_cada_formato() {
        let md = tareas_markdown(lista(), "es-ES".into(), 0);
        assert!(md.contains("llamar al banco"), "{md}");
        assert!(!md.contains('⏫') && !md.contains('➕'), "{md}");
        let t = tareas_texto(lista(), "es-ES".into(), 0);
        assert!(t.contains("pan") && !t.contains("➕"), "{t}");
        let h = tareas_hojas(lista(), "es-ES".into(), 0);
        assert!(!h.hojas.is_empty() && h.fotos.is_empty());
        assert!(tareas_svg_de_hoja(lista(), "es-ES".into(), 0, 0).unwrap().contains("<svg"));
        // Caso negativo: una hoja que no esta.
        assert!(tareas_svg_de_hoja(lista(), "es-ES".into(), 0, 99).is_none());
    }

    #[test]
    fn la_pagina_web_es_la_de_las_tareas_en_el_idioma_de_la_app() {
        let d = std::env::temp_dir().join(format!("pixpin-tareas-web-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let r = tareas_web(vec![lista()], "x".into(), "en-US".into(), 0, "Casa".into(), d.display().to_string()).unwrap();
        let html = std::fs::read_to_string(&r[0]).unwrap();
        assert!(html.contains("<title>Casa</title>"), "con una lista sola, su titulo");
        assert!(html.contains("lang=\"en\""), "{}", &html[..200]);
        assert!(html.contains("llamar al banco") && !html.contains('➕'));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn los_rotulos_salen_del_catalogo_con_sus_huecos() {
        let r = rotulos("es-ES");
        assert_eq!(r.idioma, "es");
        assert_eq!(r.exportado, "Exportado el {fecha}");
        assert_eq!(r.de, "{hechas} de {total}");
        assert_eq!(r.fecha_con_ano, "{dia} de {mes} de {ano}");
        assert_eq!(r.meses[0], "enero");
        let en = rotulos("en-US");
        assert_ne!(en.tareas, "");
        assert_eq!(en.idioma, "en");
        // El mes va como dentro de una fecha (Windows 668fa506): «5 октября».
        let ru = rotulos("ru-RU");
        assert_eq!(ru.meses[9], "октября");
        assert_ne!(ru.meses[9], "октябрь", "caso negativo: no el mes suelto");
    }

    #[test]
    fn de_un_mensaje_solo_las_listas() {
        let d = std::env::temp_dir().join(format!("pixpin-tareas-compartir-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        let l = n.apuntar_tarea("comprar pan".into(), 0).unwrap();
        let c = n.lista_para_compartir(l.chat.clone(), l.mensaje.clone()).unwrap().unwrap();
        assert_eq!(c.titulo, "Inbox");
        assert!(c.documento.contains("comprar pan"));
        assert_eq!(n.lista_para_compartir(l.chat, "no-esta".into()).unwrap(), None);
        let _ = std::fs::remove_dir_all(&d);
    }
}
