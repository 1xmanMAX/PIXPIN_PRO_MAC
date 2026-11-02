//! **Las marcas de texto de las paginas que se reajustan** (Windows
//! 34adbfad, f8090d03 y bca03bb4, 2-nov-2026; `apps/pindesk/src/marcas_web.rs`):
//! resaltar, raya ondulada, subrayar, tachar y tapar lo elegido leyendo una
//! nota (el editor de notas, [`crate::notas::web`]) o una pagina web (el
//! visor de HTML), con los mismos botones y colores que la barrita del PDF.
//!
//! Una nota o una pagina se recolocan con el ancho, asi que la marca guarda
//! su cita y la pagina la vuelve a buscar al abrir (`pindesk_docs::ancla_texto`;
//! las cuentas, en el guion de la pagina, que es el de Windows tal cual:
//! `recursos/marcas-pagina.js` y la del editor de notas, `lector-md.html`).
//! La pagina elige, pinta, deshace y manda la lista entera; aqui solo el
//! fichero, **el mismo que Windows** (sincroniza sin cambios):
//!
//! - De un adjunto del chat o de una nota de un proyecto,
//!   `anot-<uid>.marcas-texto.json` de su mensaje: viaja con el
//!   (`pindesk_sincro::anotado::MARCAS_TEXTO`) y no se borra nunca para
//!   decir «vacio» (se escribe la lista vacia).
//! - Si no, `<doc>.pixpin-marcas-texto.json` a su lado (sin marcas, se quita).
//!
//! Al guardar se junta con lo que haya llegado al disco mientras tanto
//! (`ancla_texto::fusionar`), y lo que llegue con la pagina abierta se le
//! manda ([`MarcasDeLaPagina::mirar`]).
//!
//! Lo del Mac: el guion habla con `chrome.webview` (WebView2); en el Mac,
//! [`PUENTE_PAGINA`] lo pasa por `webkit.messageHandlers.pixpinMarcas` y
//! convierte ⌘Z / ⇧⌘Z / ⌘Y en los Ctrl de Windows (fuera de un campo). La
//! capa de la tinta del visor del Mac es `#pixpin-tinta` (en Windows,
//! `#pixpin-riel-capa`): su texto no cuenta.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use pindesk_docs::ancla_texto::{self as at, MarcasDeTexto};
use pindesk_proyecto::anotado::{self as an, Base};
use pindesk_store::idioma::{Catalogo, Idioma};
use serde_json::{Value, json};

use crate::Nucleo;

/// `apuntes.md` → `apuntes.md.pixpin-marcas-texto.json` (como los
/// `.pixpin-marcos` de junto al documento).
pub fn junto_a(doc: &Path) -> PathBuf {
    let mut s = doc.as_os_str().to_owned();
    s.push(".pixpin-marcas-texto.json");
    PathBuf::from(s)
}

/// Donde van las de `doc` y si viajan: del mensaje si es un adjunto del
/// chat (con lo de junto al fichero pasado la primera vez), si no a su lado
/// (`anotado_del_adjunto::del_mensaje_o_junto` de Windows).
pub fn ruta(raiz: &Path, doc: &Path) -> (PathBuf, bool) {
    let de_siempre = junto_a(doc);
    let es_pdf = doc
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("pdf"));
    match an::base_del_documento(raiz, doc).filter(|_| !es_pdf) {
        Some(b) => {
            let nuevo = b.fichero(pindesk_sincro::anotado::MARCAS_TEXTO);
            an::copiar_si_falta(&de_siempre, &nuevo);
            (nuevo, true)
        }
        None => (de_siempre, false),
    }
}

/// Las de la nota `codigo` de la ficha `ficha` (un mensaje `NOTA`): la base
/// `anot-<codigo>` de la nota, la de sus comentarios (Windows,
/// `base_de_la_nota_del_riel`). `None` si la ficha ya no esta.
pub fn ruta_de_nota(raiz: &Path, ficha: &str, codigo: &str) -> Option<(PathBuf, bool)> {
    if codigo.is_empty() {
        return None;
    }
    let b = Base {
        raiz: raiz.to_path_buf(),
        chat: pindesk_proyecto::vista::chat_de_ficha(raiz, ficha)?,
        base: format!("{}{codigo}", pindesk_sincro::anotado::PREFIJO),
    };
    Some((b.fichero(pindesk_sincro::anotado::MARCAS_TEXTO), true))
}

type Sello = Option<(SystemTime, u64)>;

fn sello_de(f: &Path) -> Sello {
    std::fs::metadata(f)
        .ok()
        .and_then(|m| Some((m.modified().ok()?, m.len())))
}

/// Las marcas de la pagina abierta.
pub struct MarcasDeLaPagina {
    /// El fichero y si viaja. `None`: sin sitio (solo mientras este abierta).
    fichero: Option<(PathBuf, bool)>,
    /// Lo que habia en el disco al leer (la base de la fusion).
    base: MarcasDeTexto,
    /// Lo de aqui.
    mio: MarcasDeTexto,
    /// El fichero no se entiende: no se escribe encima (seria perderlo).
    roto: bool,
    sello: Sello,
}

impl MarcasDeLaPagina {
    /// Las del fichero `fichero` (`None`: sin fichero). `sobre`: el texto en
    /// que cuentan las posiciones (`SOBRE_MARKDOWN` o `SOBRE_HTML`).
    pub fn abrir(fichero: Option<(PathBuf, bool)>, sobre: &str) -> Self {
        let mut m = MarcasDeLaPagina {
            fichero,
            base: MarcasDeTexto::default(),
            mio: MarcasDeTexto::default(),
            roto: false,
            sello: None,
        };
        m.mio.sobre = sobre.to_string();
        if let Some((f, _)) = &m.fichero {
            m.sello = sello_de(f);
            match pindesk_proyecto::comentarios_de_notas::leer(f).map(|t| at::leer(&t)) {
                Some(Ok(l)) => {
                    m.base = l.clone();
                    m.mio = l;
                    if m.mio.sobre.is_empty() {
                        m.mio.sobre = sobre.to_string();
                    }
                }
                Some(Err(e)) => {
                    eprintln!("PixPin: las marcas de texto de {} no se entienden: no se tocan ({e})", f.display());
                    m.roto = true;
                }
                None => m.roto = true,
            }
        }
        m
    }

    /// La lista para la pagina (JSON, la misma forma que manda ella).
    pub fn lista(&self) -> Value {
        serde_json::to_value(&self.mio.marcas).unwrap_or_else(|_| json!([]))
    }

    /// **Lo que mando la pagina** (la lista entera tras cada cambio): se
    /// guarda. Si al juntarla con el disco sale otra cosa (llego algo del
    /// movil), la lista nueva para mandarsela.
    pub fn de_la_pagina(&mut self, v: &Value) -> Option<Value> {
        let suyas = at::de_la_pagina(v);
        self.mio.marcas = suyas.clone();
        self.guardar();
        (self.mio.marcas != suyas).then(|| self.lista())
    }

    fn guardar(&mut self) {
        let Some((f, viaja)) = self.fichero.clone() else {
            return;
        };
        if self.roto {
            return;
        }
        // Lo que haya ahora en el disco (la sincronizacion pudo traer otras).
        let disco = match pindesk_proyecto::comentarios_de_notas::leer(&f).map(|t| at::leer(&t)) {
            Some(Ok(d)) => d,
            _ => self.base.clone(),
        };
        let junto = at::fusionar(&self.base, &self.mio, &disco);
        if junto.marcas.is_empty() && (!viaja || !f.exists()) {
            // Junto al fichero, sin marcas no queda fichero; del mensaje, uno
            // que no estaba no se crea vacio.
            if !viaja {
                let _ = std::fs::remove_file(&f);
            }
        } else {
            if let Some(c) = f.parent() {
                let _ = std::fs::create_dir_all(c);
            }
            if let Err(e) = an::escribir(&f, &at::escribir(&junto)) {
                eprintln!("PixPin: no se pudieron guardar las marcas de texto ({}): {e}", f.display());
                return;
            }
        }
        self.base = junto.clone();
        self.mio = junto;
        self.sello = sello_de(&f);
    }

    /// **Si el fichero cambio por fuera** (la sincronizacion): se junta con
    /// lo de aqui y devuelve la lista nueva para la pagina.
    pub fn mirar(&mut self) -> Option<Value> {
        let (f, _) = self.fichero.as_ref()?;
        let ahora = sello_de(f);
        if ahora == self.sello {
            return None;
        }
        self.sello = ahora;
        let disco = at::leer(&pindesk_proyecto::comentarios_de_notas::leer(f)?).ok()?;
        let junto = at::fusionar(&self.base, &self.mio, &disco);
        self.base = disco;
        if junto.marcas == self.mio.marcas {
            return None;
        }
        self.mio = junto;
        Some(self.lista())
    }

    /// **Lo que pide el guion de una pagina web**: el guion que la contesta
    /// (si hay que contestar).
    pub fn atender_web(&mut self, p: DeLaPaginaWeb, textos: &Catalogo) -> Option<String> {
        match p {
            DeLaPaginaWeb::Pedir => Some(guion_recibir(&self.lista(), Some(&rotulos(textos)))),
            DeLaPaginaWeb::Lista(l) => self.de_la_pagina(&l).map(|l| guion_recibir(&l, None)),
        }
    }
}

/// **El guion de marcar de las paginas web**, el de Windows tal cual
/// (`herramientas/lector-md`, `npm run build`: `src/marcas-pagina.js`).
pub const GUION_PAGINA: &str = include_str!("../recursos/marcas-pagina.js");

/// Lo que va delante del guion en el Mac: `chrome.webview` sobre WebKit y
/// las teclas de deshacer con ⌘ (el guion mira Ctrl). Si la pagina no se
/// queda la tecla, sigue su camino.
pub const PUENTE_PAGINA: &str = r#"(()=>{if(window.top!==window)return;window.chrome=window.chrome||{};
if(!window.chrome.webview){window.chrome.webview={postMessage:s=>{try{window.webkit.messageHandlers.pixpinMarcas.postMessage(String(s))}catch(e){}},addEventListener:()=>{}}}
addEventListener('keydown',e=>{if(!e.isTrusted||!e.metaKey||e.ctrlKey||e.altKey)return;const k=(e.key||'').toLowerCase();if(k!=='z'&&k!=='y')return;
const t=e.target&&e.target.dispatchEvent?e.target:window;const c=new KeyboardEvent('keydown',{key:e.key,code:e.code,ctrlKey:true,shiftKey:e.shiftKey,bubbles:true,cancelable:true});
if(!t.dispatchEvent(c)){e.preventDefault();e.stopImmediatePropagation()}},true)})();"#;

/// **El guion que el visor de HTML pone en cada pagina** (antes que lo
/// suyo, al empezar el documento): el puente del Mac y el de Windows, con
/// la capa de la tinta del Mac fuera del texto.
pub fn guion_mac() -> String {
    format!(
        "{PUENTE_PAGINA}\n{}",
        GUION_PAGINA.replace("\"pixpin-riel-capa\"", "\"pixpin-tinta\"")
    )
}

/// Lo que manda el guion de una pagina web (`{"pixpin_marcas": …}`).
#[derive(Debug, Clone, PartialEq)]
pub enum DeLaPaginaWeb {
    /// Acaba de cargar: quiere las marcas y los rotulos.
    Pedir,
    /// Cambiaron: la lista entera.
    Lista(Value),
}

/// Si el mensaje `m` de la pagina es del guion de marcar, que dice.
pub fn de_la_pagina_web(m: &str) -> Option<DeLaPaginaWeb> {
    if !m.contains("pixpin_marcas") {
        return None;
    }
    let v: Value = serde_json::from_str(m).ok()?;
    match v.get("pixpin_marcas")?.as_str()? {
        "pedir" => Some(DeLaPaginaWeb::Pedir),
        "lista" => Some(DeLaPaginaWeb::Lista(v.get("marcas")?.clone())),
        _ => None,
    }
}

/// El guion que le deja a la pagina sus marcas (y los rotulos, si van).
pub fn guion_recibir(marcas: &Value, rotulos: Option<&Value>) -> String {
    let mut d = json!({ "marcas": marcas });
    if let Some(r) = rotulos {
        d["rotulos"] = r.clone();
    }
    format!("window.__pixpinMarcas&&window.__pixpinMarcas.recibir({d})")
}

/// Los rotulos de los botones, en el idioma de la app (los de la barra del
/// pin).
pub fn rotulos(t: &Catalogo) -> Value {
    let x = |k: &str| crate::textos::texto(t, k);
    json!({
        "copiar": x("pin-v2-marca-copiar"),
        "resaltar": x("pin-v2-marca-resaltar"),
        "ondulada": x("pin-v2-marca-ondulada"),
        "subrayar": x("pin-v2-marca-subrayar"),
        "tachar": x("pin-v2-marca-tachar"),
        "tapar": x("pin-v2-marca-tapar"),
        "quitar": x("pin-v2-marca-quitar"),
        "color": x("marcas-texto-color"),
    })
}

/// El catalogo del idioma `etiqueta` (`es-ES`, `ja-JP`… o solo `es`); uno
/// que no se conoce, el espanol.
pub fn catalogo_de(etiqueta: &str) -> Catalogo {
    let idioma = Idioma::de_etiqueta(etiqueta)
        .or_else(|| {
            let base = etiqueta.split(['-', '_']).next().unwrap_or("");
            Idioma::TODOS.into_iter().find(|i| i.codigo() == base)
        })
        .unwrap_or(Idioma::Espanol);
    Catalogo::nuevo(idioma)
}

/// **Las marcas de texto de una pagina del visor de HTML**, abiertas.
#[derive(uniffi::Object)]
pub struct MarcasDePagina {
    marcas: Mutex<MarcasDeLaPagina>,
    textos: Catalogo,
}

#[uniffi::export]
impl Nucleo {
    /// **Abre las marcas de texto de la pagina `documento`** (un `.html`)
    /// para el visor de HTML. `idioma`: la etiqueta del idioma de la app
    /// (`CatalogoDeTextos::etiqueta`), la de los rotulos de la burbuja.
    pub fn marcas_de_pagina(&self, documento: String, idioma: String) -> Arc<MarcasDePagina> {
        let f = ruta(self.ruta(), Path::new(&documento));
        Arc::new(MarcasDePagina {
            marcas: Mutex::new(MarcasDeLaPagina::abrir(Some(f), at::SOBRE_HTML)),
            textos: catalogo_de(&idioma),
        })
    }
}

/// **El guion de marcar** que el visor de HTML pone en cada pagina al
/// empezar el documento (`WKUserScript`, `.atDocumentStart`, solo el marco
/// principal). Habla por `webkit.messageHandlers.pixpinMarcas`.
#[uniffi::export]
pub fn guion_de_marcar_paginas() -> String {
    static G: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    G.get_or_init(guion_mac).clone()
}

#[uniffi::export]
impl MarcasDePagina {
    /// **Un mensaje del guion** (lo que llego por `pixpinMarcas`, tal cual):
    /// el JavaScript con que se le contesta, si hay que contestar. Escribe
    /// en el disco: fuera del hilo principal.
    pub fn atender(&self, mensaje: String) -> Option<String> {
        let p = de_la_pagina_web(&mensaje)?;
        self.marcas
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .atender_web(p, &self.textos)
    }

    /// **Lo que llego al disco** con la pagina abierta (la sincronizacion):
    /// el JavaScript que se lo deja a la pagina. Para llamarlo cada 2 s.
    pub fn mirar(&self) -> Option<String> {
        let l = self.marcas.lock().unwrap_or_else(|e| e.into_inner()).mirar()?;
        Some(guion_recibir(&l, None))
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn carpeta(etiqueta: &str) -> PathBuf {
        let r = std::env::temp_dir().join(format!(
            "pixpin-marcas-web-{etiqueta}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&r);
        std::fs::create_dir_all(&r).unwrap();
        r
    }

    fn marca(id: &str, exact: &str) -> Value {
        json!({"id": id, "marca": "resaltar", "color": "#F5C218", "cuando": 1,
            "cita": {"type": "TextQuoteSelector", "exact": exact, "prefix": "", "suffix": ""},
            "posicion": {"type": "TextPositionSelector", "start": 0, "end": exact.len()}})
    }

    #[test]
    fn junto_a_un_fichero_suelto_y_sin_marcas_no_queda_fichero() {
        let d = carpeta("suelto");
        let doc = d.join("pagina.html");
        std::fs::write(&doc, "<p>hola</p>").unwrap();
        let (f, viaja) = ruta(&d, &doc);
        assert!(!viaja);
        assert!(f.ends_with("pagina.html.pixpin-marcas-texto.json"));
        let mut m = MarcasDeLaPagina::abrir(Some((f.clone(), viaja)), at::SOBRE_HTML);
        assert_eq!(m.lista(), json!([]));
        assert_eq!(m.de_la_pagina(&json!([marca("marca-texto-1", "hola")])), None);
        let leido = at::leer(&std::fs::read_to_string(&f).unwrap()).unwrap();
        assert_eq!(leido.sobre, "html");
        assert_eq!(leido.marcas.len(), 1);
        // Otra vez abierta, ahi estan.
        let otra = MarcasDeLaPagina::abrir(Some(ruta(&d, &doc)), at::SOBRE_HTML);
        assert_eq!(otra.lista().as_array().unwrap().len(), 1);
        // Quitadas todas: fuera el fichero.
        m.de_la_pagina(&json!([]));
        assert!(!f.exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn lo_que_llega_al_disco_con_la_pagina_abierta_se_junta_y_no_se_pisa() {
        let d = carpeta("juntar");
        let doc = d.join("nota.md");
        let mut m = MarcasDeLaPagina::abrir(Some(ruta(&d, &doc)), at::SOBRE_MARKDOWN);
        m.de_la_pagina(&json!([marca("marca-texto-1", "losa")]));
        // El movil anade otra al fichero.
        let f = junto_a(&doc);
        let mut disco = at::leer(&std::fs::read_to_string(&f).unwrap()).unwrap();
        disco
            .marcas
            .extend(at::de_la_pagina(&json!([marca("marca-texto-2", "obra")])));
        std::fs::write(&f, at::escribir(&disco) + "\n\n").unwrap();
        let nueva = m.mirar().expect("se nota lo nuevo");
        assert_eq!(nueva.as_array().unwrap().len(), 2);
        // Llega otra del movil sin que la pagina la vea aun, y aqui se pone
        // una tercera: la del movil no se pierde y se le devuelve a la pagina.
        let mut disco = at::leer(&std::fs::read_to_string(&f).unwrap()).unwrap();
        disco
            .marcas
            .extend(at::de_la_pagina(&json!([marca("marca-texto-4", "muro")])));
        std::fs::write(&f, at::escribir(&disco)).unwrap();
        let devuelta = m
            .de_la_pagina(&json!([
                marca("marca-texto-1", "losa"),
                marca("marca-texto-2", "obra"),
                marca("marca-texto-3", "piso")
            ]))
            .expect("la pagina no tenia la del movil");
        let ids: Vec<&str> = devuelta
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["marca-texto-1", "marca-texto-2", "marca-texto-3", "marca-texto-4"]);
        // Caso negativo: sin cambios en el disco no hay nada que mandar.
        assert_eq!(m.mirar(), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn caso_negativo_un_fichero_roto_no_se_pisa() {
        let d = carpeta("roto");
        let doc = d.join("nota.md");
        let f = junto_a(&doc);
        std::fs::write(&f, "{roto").unwrap();
        let mut m = MarcasDeLaPagina::abrir(Some(ruta(&d, &doc)), at::SOBRE_MARKDOWN);
        m.de_la_pagina(&json!([marca("marca-texto-1", "losa")]));
        assert_eq!(std::fs::read_to_string(&f).unwrap(), "{roto");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn la_pagina_web_pide_y_manda_por_pixpin_marcas() {
        assert_eq!(de_la_pagina_web(r#"{"pixpin_marcas":"pedir"}"#), Some(DeLaPaginaWeb::Pedir));
        assert_eq!(
            de_la_pagina_web(r#"{"pixpin_marcas":"lista","marcas":[]}"#),
            Some(DeLaPaginaWeb::Lista(json!([])))
        );
        // Caso negativo: lo que no es suyo.
        assert_eq!(de_la_pagina_web(r#"{"pixpin_riel":"sitio","x":0}"#), None);
        assert_eq!(de_la_pagina_web(r#"{"pixpin_marcas":"otra"}"#), None);
        let d = carpeta("web");
        let doc = d.join("p.html");
        let mut m = MarcasDeLaPagina::abrir(Some(ruta(&d, &doc)), at::SOBRE_HTML);
        let t = catalogo_de("es-ES");
        let js = m.atender_web(DeLaPaginaWeb::Pedir, &t).unwrap();
        assert!(js.starts_with("window.__pixpinMarcas&&window.__pixpinMarcas.recibir({"));
        assert!(js.contains("\"rotulos\"") && js.contains("Resaltar"));
        // Guardar no contesta si la lista no cambia al juntarla.
        assert_eq!(
            m.atender_web(DeLaPaginaWeb::Lista(json!([marca("marca-texto-1", "x")])), &t),
            None
        );
        assert!(junto_a(&doc).exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn el_guion_del_mac_lleva_el_puente_delante_y_la_capa_de_la_tinta() {
        let g = guion_de_marcar_paginas();
        assert!(g.starts_with(PUENTE_PAGINA));
        assert!(g.contains("pixpin_marcas") && g.contains("__pixpinMarcas"));
        assert!(g.contains("messageHandlers.pixpinMarcas"));
        assert!(GUION_PAGINA.contains("\"pixpin-riel-capa\""), "el guion de Windows cambio");
        assert!(g.contains("\"pixpin-tinta\"") && !g.contains("\"pixpin-riel-capa\""));
    }

    #[test]
    fn cada_rotulo_existe_en_los_catalogos() {
        for i in Idioma::TODOS {
            let t = Catalogo::nuevo(i);
            for (k, v) in rotulos(&t).as_object().unwrap() {
                let v = v.as_str().unwrap();
                assert!(!v.is_empty() && !v.contains("marcas-texto-") && !v.contains("pin-v2-"), "{i:?} {k}: {v}");
            }
        }
        // Una etiqueta corta o desconocida tambien vale.
        assert_eq!(catalogo_de("ja").idioma(), Idioma::Japones);
        assert_eq!(catalogo_de("xx-YY").idioma(), Idioma::Espanol);
    }

    #[test]
    fn la_de_un_adjunto_va_al_mensaje_y_viaja() {
        let raiz = carpeta("adjunto");
        let n = Nucleo::abrir(raiz.to_string_lossy().into_owned(), "Mac de prueba".into()).unwrap();
        let ficha = n.crear_chat("Obra".into()).unwrap();
        // Una nota del proyecto: la base de su codigo, en su chat.
        let (f, viaja) = ruta_de_nota(&raiz, &ficha.id, "ABCDE23456").unwrap();
        assert!(viaja);
        assert!(f.to_string_lossy().ends_with("anot-ABCDE23456.marcas-texto.json"), "{}", f.display());
        let mut m = MarcasDeLaPagina::abrir(Some((f.clone(), true)), at::SOBRE_MARKDOWN);
        m.de_la_pagina(&json!([marca("marca-texto-1", "losa")]));
        assert!(f.is_file());
        // Del mensaje no se borra nunca: sin marcas, la lista vacia.
        m.de_la_pagina(&json!([]));
        assert!(at::leer(&std::fs::read_to_string(&f).unwrap()).unwrap().marcas.is_empty());
        // Caso negativo: una ficha que no esta o sin codigo.
        assert!(ruta_de_nota(&raiz, "no-esta", "ABCDE23456").is_none());
        assert!(ruta_de_nota(&raiz, &ficha.id, "").is_none());
        let _ = std::fs::remove_dir_all(&raiz);
    }
}
