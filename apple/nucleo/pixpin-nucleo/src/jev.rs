//! **Jev de TypeSafe en el Mac** (Windows 28-oct-2026, `docs/jev.md` y
//! `apps/pixpin/src/jev.rs` de Windows): la clave de Ajustes → Asistente →
//! «TypeSafe (Jev)», el interruptor de cada funcion (`[jev]` del mismo
//! `pixpinmax.toml`) y las funciones que le preguntan:
//!
//! - [`reunion`]: lo importante de una clase o reunion al acabar de pasarla a
//!   texto (tareas, decisiones, preguntas, examen), en
//!   `resto["importantes"]` de la nota de voz (viaja a Windows y al movil).
//! - Anki (`crate::anki`): solo las tarjetas de una clase que valen la pena.
//! - [`urgencia`]: la prioridad de cada tarea pendiente, en Tareas (solo en
//!   memoria: ni va al disco ni viaja).
//! - [`modelo`]: el modelo del asistente segun lo dificil del pedido.
//! - [`estado_ia`]: los puntitos del estado de Claude, DeepSeek y Jev.
//!
//! Las preguntas y las tablas de decision viven en `pixpin_typesafe` (el
//! mismo crate que Windows). Sin clave, sin el HTTPS de la app o con la
//! funcion apagada, [`para`] da `None` y cada funcion hace lo de siempre.
//!
//! **La red** es la de la app: el POST va por el `TransporteApp` de Swift
//! (URLSession, `asistente::transporte`), con el plazo de cada peticion en
//! la cabecera [`CABECERA_PLAZO`] (Swift la quita y la usa de
//! `timeoutInterval`). **La clave** va al Llavero del Mac (servicio
//! `PixPinMax.asistente`, cuenta [`CUENTA`]), como las de Claude y DeepSeek;
//! en Windows va cifrada con DPAPI. Ni la clave ni los interruptores
//! viajan (son de este aparato, como en Windows).
//!
//! Lo que Windows tiene y el Mac aun no: los temas de la reunion y lo que se
//! oye en ella mientras se graba (`en_vivo`, `temas`), dictar al chat y
//! repasar en voz alta. Sus interruptores se conservan en el TOML tal cual.

pub mod estado_ia;
pub mod modelo;
pub mod reunion;
pub mod urgencia;

use std::path::Path;
use std::sync::mpsc::channel;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use pixpin_ia::nube::http::{self, Fallo};
use pixpin_store::idioma::{Catalogo, resolver_idioma};
use pixpin_store::{Ubicacion, ajustes};
use pixpin_typesafe::transporte::{Contestado, Transporte};
use pixpin_typesafe::{Cliente, claves};

use crate::llavero::{LlaveroApp, SERVICIO};
use crate::{ErrorNucleo, Nucleo};

/// La cuenta de la clave de TypeSafe en el Llavero (`typesafe.clave` en
/// Windows).
pub const CUENTA: &str = "typesafe";

/// La cabecera con el plazo de la peticion, en segundos: no sale a la red
/// (Swift la quita y la usa de `timeoutInterval`).
pub const CABECERA_PLAZO: &str = "X-PixPin-Plazo";

/// La pagina donde se saca la clave.
pub const PAGINA_DE_CLAVES: &str = "console.typesafe.ai";

/// Lo que se espera a Jev en el Mac. Windows espera 2 s con su conexion
/// abierta (58ee21b); aqui cada peticion de URLSession abre la suya (TLS
/// incluido), y un segundo mas lo cubre.
pub const TIEMPO: Duration = Duration::from_secs(3);

/// Lo mas que se lee de una respuesta de Jev (son unos cientos de bytes).
const LIMITE: usize = 1024 * 1024;

/// Una funcion que usa Jev (su interruptor de `[jev]`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Funcion {
    Reunion,
    Anki,
    Urgencia,
    Modelo,
}

impl Funcion {
    pub fn encendida_en(self, a: &ajustes::Jev) -> bool {
        match self {
            Funcion::Reunion => a.reunion,
            Funcion::Anki => a.anki,
            Funcion::Urgencia => a.urgencia,
            Funcion::Modelo => a.modelo,
        }
    }
}

// ---------------------------------------------------------------------------
// La red: el HTTPS de la app

/// **El transporte de Jev en el Mac**: el `pedir` del HTTPS de la app
/// (`pixpin_ia::nube::http::pedir`, URLSession desde Swift), con su plazo.
pub struct PorLaApp;

/// Lo que contesto el HTTPS de la app, como lo quiere el cliente de Jev: un
/// codigo que no es 2xx es una respuesta (el cliente lee su detalle), no un
/// fallo de red.
fn contestado_de(r: Result<http::Respuesta, Fallo>) -> Result<Contestado, String> {
    let codigo = |c: u32| u16::try_from(c).unwrap_or(u16::MAX);
    match r {
        Ok(r) => Ok(Contestado {
            codigo: codigo(r.codigo),
            cuerpo: r.cuerpo,
        }),
        Err(Fallo::Http { codigo: c, cuerpo, .. }) => Ok(Contestado {
            codigo: codigo(c),
            cuerpo: cuerpo.into_bytes(),
        }),
        Err(Fallo::Red(e)) => Err(e),
    }
}

impl Transporte for PorLaApp {
    fn enviar(
        &self,
        metodo: &str,
        url: &str,
        cabeceras: &[(&'static str, String)],
        cuerpo: &[u8],
        tiempo: Duration,
    ) -> Result<Contestado, String> {
        if !http::hay_transporte() {
            return Err("falta el HTTPS de la app".into());
        }
        let mut cab = cabeceras.to_vec();
        cab.push((CABECERA_PLAZO, format!("{:.1}", tiempo.as_secs_f64().max(0.5))));
        let (metodo, url, cuerpo) = (metodo.to_string(), url.to_string(), cuerpo.to_vec());
        let (tx, rx) = channel();
        // En su hilo: si URLSession se pasa del plazo, Jev no espera mas (la
        // funcion sigue como siempre) y la peticion acaba sola.
        std::thread::Builder::new()
            .name("jev-https".into())
            .spawn(move || {
                let _ = tx.send(http::pedir(&metodo, &url, &cab, &cuerpo, LIMITE));
            })
            .map_err(|e| format!("no se pudo lanzar la peticion: {e}"))?;
        match rx.recv_timeout(tiempo + Duration::from_millis(500)) {
            Ok(r) => contestado_de(r),
            Err(_) => Err("se acabo el tiempo".into()),
        }
    }
}

fn cliente(clave: String) -> Cliente {
    Cliente::con_transporte(clave, Arc::new(PorLaApp)).con_tiempo(TIEMPO)
}

/// **El cliente para esta funcion**: con la clave guardada, el HTTPS de la
/// app puesto y la funcion encendida en `pixpinmax.toml` de `raiz`. `None`:
/// lo de siempre. En las pruebas, nunca (no salen a la red).
pub(crate) fn para(raiz: &Path, f: Funcion) -> Option<Cliente> {
    if cfg!(test) {
        return None;
    }
    if !http::hay_transporte() {
        return None;
    }
    let clave = clave()?;
    let a = ajustes::cargar(&Ubicacion::Instalado {
        raiz: raiz.to_path_buf(),
    })
    .unwrap_or_default();
    f.encendida_en(&a.jev).then(|| cliente(clave))
}

// ---------------------------------------------------------------------------
// La clave, en el Llavero

/// La clave leida del Llavero (se lee una vez por proceso y al cambiarla).
static CLAVE: Mutex<Option<Option<String>>> = Mutex::new(None);

fn leer_de(ll: Option<&dyn LlaveroApp>) -> Option<String> {
    ll.and_then(|l| l.leer(SERVICIO.into(), CUENTA.into()))
        .map(|c| c.trim().to_string())
        .filter(|c| !c.is_empty())
        // Fuera de la app (las pruebas de verdad): la del entorno.
        .or_else(claves::leer)
}

fn clave() -> Option<String> {
    let mut g = CLAVE.lock().unwrap_or_else(|e| e.into_inner());
    if g.is_none() {
        if cfg!(test) {
            return None;
        }
        let ll = crate::llavero::llavero_app();
        *g = Some(leer_de(ll.as_deref()));
    }
    g.clone().flatten()
}

fn olvidar_clave() {
    *CLAVE.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// Si hay clave de TypeSafe (no la ensena).
pub(crate) fn hay_clave() -> bool {
    clave().is_some()
}

/// Guarda `clave` en `ll` (recortada), si tiene pinta de clave.
fn guardar_en(ll: &dyn LlaveroApp, clave: &str) -> Result<(), ErrorNucleo> {
    let c = clave.trim();
    if !claves::parece_clave(c) {
        return Err(ErrorNucleo::Argumento {
            detalle: "eso no parece una clave".into(),
        });
    }
    ll.guardar(SERVICIO.into(), CUENTA.into(), c.into())
}

fn sin_llavero() -> ErrorNucleo {
    ErrorNucleo::Asistente {
        detalle: "no hay Llavero: la clave no se guarda en claro".into(),
    }
}

/// **Guarda la clave de TypeSafe** en el Llavero del Mac. Lo que no parece
/// una clave (espacios, muy corta) no se guarda. Luego Swift la prueba con
/// [`jev_probar_clave`].
#[uniffi::export]
pub fn jev_guardar_clave(clave: String) -> Result<(), ErrorNucleo> {
    let ll = crate::llavero::llavero_app().ok_or_else(sin_llavero)?;
    guardar_en(ll.as_ref(), &clave)?;
    olvidar_clave();
    estado_ia::clave_cambiada(pixpin_ui::estado_ia::Servicio::Jev);
    Ok(())
}

/// **Borra la clave de TypeSafe**: todo vuelve a lo de siempre.
#[uniffi::export]
pub fn jev_borrar_clave() -> Result<(), ErrorNucleo> {
    let ll = crate::llavero::llavero_app().ok_or_else(sin_llavero)?;
    let r = ll.borrar(SERVICIO.into(), CUENTA.into());
    olvidar_clave();
    estado_ia::clave_cambiada(pixpin_ui::estado_ia::Servicio::Jev);
    r
}

/// Si hay clave de TypeSafe guardada.
#[uniffi::export]
pub fn jev_hay_clave() -> bool {
    hay_clave()
}

/// Lo que se ensena de la clave guardada (`ts-…AbCd`), o `None`.
#[uniffi::export]
pub fn jev_clave_enmascarada() -> Option<String> {
    clave().map(|c| claves::enmascarar(&c))
}

/// **Prueba la clave** guardada con `GET /v1/models` (no gasta tokens) y
/// devuelve el modelo (`jev-latest`). Bloquea unos segundos: Swift la llama
/// fuera del hilo principal.
#[uniffi::export]
pub fn jev_probar_clave() -> Result<String, ErrorNucleo> {
    let clave = clave().ok_or_else(|| ErrorNucleo::Asistente {
        detalle: pixpin_typesafe::Error::SinClave.to_string(),
    })?;
    if !http::hay_transporte() {
        return Err(ErrorNucleo::Asistente {
            detalle: "falta el HTTPS de la app".into(),
        });
    }
    let modelos = cliente(clave)
        .modelos()
        .map_err(|e| ErrorNucleo::Asistente { detalle: e.to_string() })?;
    Ok(modelos
        .into_iter()
        .map(|m| m.name)
        .find(|n| n == pixpin_typesafe::api::MODELO)
        .unwrap_or_else(|| pixpin_typesafe::api::MODELO.to_string()))
}

// ---------------------------------------------------------------------------
// Los interruptores (`[jev]` de `pixpinmax.toml`)

/// **Los interruptores de Jev** que tiene el Mac (`[jev]`). Los demas de
/// Windows (temas, reunion en vivo, dictado, repaso) se conservan en el
/// fichero tal cual.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AjustesJev {
    /// Lo importante de clases y reuniones (`reunion`).
    pub reunion: bool,
    /// Solo las tarjetas de Anki que valen la pena (`anki`).
    pub anki: bool,
    /// Prioridad de las tareas segun el contexto (`urgencia`).
    pub urgencia: bool,
    /// Elegir el modelo segun el pedido (`modelo`).
    pub modelo: bool,
}

impl From<&ajustes::Jev> for AjustesJev {
    fn from(a: &ajustes::Jev) -> Self {
        AjustesJev {
            reunion: a.reunion,
            anki: a.anki,
            urgencia: a.urgencia,
            modelo: a.modelo,
        }
    }
}

#[uniffi::export]
impl Nucleo {
    /// Los interruptores de `[jev]` (los de fabrica: todos encendidos).
    pub fn ajustes_jev(&self) -> Result<AjustesJev, ErrorNucleo> {
        Ok(AjustesJev::from(&ajustes::cargar(&self.ubicacion())?.jev))
    }

    /// Los de fabrica (para el punto azul y «Restablecer»).
    pub fn ajustes_jev_de_fabrica(&self) -> AjustesJev {
        AjustesJev::from(&ajustes::Jev::default())
    }

    /// Guarda los interruptores sin tocar lo demas del fichero.
    pub fn guardar_ajustes_jev(&self, nuevos: AjustesJev) -> Result<(), ErrorNucleo> {
        let u = self.ubicacion();
        let mut a = ajustes::cargar(&u)?;
        a.jev.reunion = nuevos.reunion;
        a.jev.anki = nuevos.anki;
        a.jev.urgencia = nuevos.urgencia;
        a.jev.modelo = nuevos.modelo;
        ajustes::guardar_conservando(&u, &a)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Los textos (los de Windows, `pixpin-store/i18n`)

/// Un interruptor de Jev en Ajustes: su titulo y su explicacion.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TextoInterruptorJev {
    pub titulo: String,
    pub ayuda: String,
}

/// **Los textos de Jev** en el idioma de la app.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TextosJev {
    /// «TypeSafe (Jev)», el grupo de Ajustes.
    pub grupo: String,
    /// «Clave de TypeSafe (Jev)».
    pub clave: String,
    pub clave_marcador: String,
    pub guardar_y_probar: String,
    pub borrar: String,
    pub probando: String,
    /// «Guardada y cifrada en este PC:» (en el Mac: en el Llavero).
    pub guardada: String,
    /// «Sin clave. Sácala en console.typesafe.ai».
    pub falta: String,
    pub reunion: TextoInterruptorJev,
    pub anki: TextoInterruptorJev,
    pub urgencia: TextoInterruptorJev,
    pub modelo: TextoInterruptorJev,
    /// «Todo», «Tarea», «Decisión», «Pregunta», «Examen».
    pub importante_todo: String,
    pub importante_tarea: String,
    pub importante_decision: String,
    pub importante_pregunta: String,
    pub importante_examen: String,
    pub importante_buscando: String,
    pub importante_nada: String,
    /// «Urgente», «Alta», «Baja» (con «✦ » delante en la chapita).
    pub prioridad_urgente: String,
    pub prioridad_alta: String,
    pub prioridad_baja: String,
}

fn catalogo(locale: &str) -> Catalogo {
    Catalogo::nuevo(resolver_idioma(locale, ajustes::PreferenciaIdioma::Sistema))
}

fn con_n(t: &Catalogo, clave: &str, n: u64) -> String {
    let mut a = fluent_bundle::FluentArgs::new();
    a.set("n", n);
    t.t_args(clave, &a)
}

/// **Los textos de Jev** para `locale` (`es-ES`, `en`…).
#[uniffi::export]
pub fn textos_de_jev(locale: String) -> TextosJev {
    let t = catalogo(&locale);
    let mut proveedor = fluent_bundle::FluentArgs::new();
    proveedor.set("proveedor", t.t("ajustes2-jev-proveedor"));
    let par = |a: &str, b: &str| TextoInterruptorJev {
        titulo: t.t(a),
        ayuda: t.t(b),
    };
    TextosJev {
        grupo: t.t("ajustes2-g-jev"),
        clave: t.t_args("ajustes2-clave-de", &proveedor),
        clave_marcador: t.t("ajustes2-clave-marcador"),
        guardar_y_probar: t.t("ajustes2-clave-probar"),
        borrar: t.t("ajustes2-clave-borrar"),
        probando: t.t("ajustes2-clave-probando"),
        guardada: t.t("ajustes2-clave-guardada"),
        falta: format!("{} {PAGINA_DE_CLAVES}", t.t("ajustes2-clave-falta")),
        reunion: par("ajustes2-jev-reunion", "ajustes2-ayuda-jev-reunion"),
        anki: par("ajustes2-jev-anki", "ajustes2-ayuda-jev-anki"),
        urgencia: par("ajustes2-jev-urgencia", "ajustes2-ayuda-jev-urgencia"),
        modelo: par("ajustes2-jev-modelo", "ajustes2-ayuda-jev-modelo"),
        importante_todo: t.t("clase-importante-todo"),
        importante_tarea: t.t("clase-importante-tarea"),
        importante_decision: t.t("clase-importante-decision"),
        importante_pregunta: t.t("clase-importante-pregunta"),
        importante_examen: t.t("clase-importante-examen"),
        importante_buscando: t.t("clase-importante-buscando"),
        importante_nada: t.t("clase-importante-nada"),
        prioridad_urgente: t.t("tareas-prioridad-urgente"),
        prioridad_alta: t.t("tareas-prioridad-alta"),
        prioridad_baja: t.t("tareas-prioridad-baja"),
    }
}

/// «+ 3 tareas a Tareas» (`clase-importante-tareas`).
#[uniffi::export]
pub fn texto_jev_tareas_por_apuntar(locale: String, n: u64) -> String {
    con_n(&catalogo(&locale), "clase-importante-tareas", n)
}

/// «3 tareas apuntadas en el Inbox de Tareas» (`clase-importante-anadidas`).
#[uniffi::export]
pub fn texto_jev_tareas_apuntadas(locale: String, n: u64) -> String {
    con_n(&catalogo(&locale), "clase-importante-anadidas", n)
}

/// «Jev dejó fuera 2 capturas sin nada que estudiar» (`anki-jev-quitadas`).
#[uniffi::export]
pub fn texto_jev_anki_quitadas(locale: String, n: u64) -> String {
    con_n(&catalogo(&locale), "anki-jev-quitadas", n)
}

/// «✓ funciona (jev-latest)» de la prueba de la clave (`ajustes2-jev-probada`).
#[uniffi::export]
pub fn texto_jev_probada(locale: String, modelo: String) -> String {
    let t = catalogo(&locale);
    let mut a = fluent_bundle::FluentArgs::new();
    a.set("modelo", modelo);
    t.t_args("ajustes2-jev-probada", &a)
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use std::collections::HashMap;

    #[derive(Default)]
    struct EnMemoria {
        claves: Mutex<HashMap<(String, String), String>>,
    }

    impl LlaveroApp for EnMemoria {
        fn guardar(&self, s: String, c: String, clave: String) -> Result<(), ErrorNucleo> {
            self.claves.lock().unwrap().insert((s, c), clave);
            Ok(())
        }
        fn leer(&self, s: String, c: String) -> Option<String> {
            self.claves.lock().unwrap().get(&(s, c)).cloned()
        }
        fn borrar(&self, s: String, c: String) -> Result<(), ErrorNucleo> {
            self.claves.lock().unwrap().remove(&(s, c));
            Ok(())
        }
    }

    #[test]
    fn la_clave_va_al_llavero_con_su_servicio_y_cuenta() {
        let ll = EnMemoria::default();
        guardar_en(&ll, "  ts-0123456789abcdefABCDEF  ").unwrap();
        assert_eq!(
            ll.leer(SERVICIO.into(), CUENTA.into()).as_deref(),
            Some("ts-0123456789abcdefABCDEF")
        );
        assert_eq!(leer_de(Some(&ll)).as_deref(), Some("ts-0123456789abcdefABCDEF"));
        // Lo que no parece una clave no se guarda.
        assert!(guardar_en(&ll, "hola que tal").is_err());
        assert!(guardar_en(&ll, "corta").is_err());
    }

    #[test]
    fn en_las_pruebas_no_hay_cliente() {
        let dir = std::env::temp_dir().join("pixpin-jev-mac-sin-red");
        for f in [Funcion::Reunion, Funcion::Anki, Funcion::Urgencia, Funcion::Modelo] {
            assert!(para(&dir, f).is_none());
        }
        assert!(!jev_hay_clave());
        assert!(jev_clave_enmascarada().is_none());
    }

    #[test]
    fn cada_funcion_lee_su_interruptor() {
        let mut a = ajustes::Jev::default();
        assert!(Funcion::Reunion.encendida_en(&a));
        a.urgencia = false;
        assert!(!Funcion::Urgencia.encendida_en(&a));
        assert!(Funcion::Modelo.encendida_en(&a));
    }

    #[test]
    fn un_error_http_es_una_respuesta_y_la_red_un_fallo() {
        let ok = contestado_de(Ok(http::Respuesta {
            codigo: 200,
            cuerpo: b"{}".to_vec(),
            ubicacion: None,
        }))
        .unwrap();
        assert_eq!(ok.codigo, 200);
        let mala = contestado_de(Err(Fallo::Http {
            codigo: 401,
            cuerpo: "{\"detail\":\"bad key\"}".into(),
            esperar: None,
        }))
        .unwrap();
        assert_eq!(mala.codigo, 401);
        assert_eq!(mala.cuerpo, b"{\"detail\":\"bad key\"}");
        assert!(contestado_de(Err(Fallo::Red("sin red".into()))).is_err());
    }

    #[test]
    fn sin_el_https_de_la_app_el_transporte_falla_sin_esperar() {
        if http::hay_transporte() {
            return; // otra prueba lo instalo en este proceso
        }
        let r = PorLaApp.enviar("GET", "https://api.typesafe.ai/v1/models", &[], &[], TIEMPO);
        assert!(r.is_err());
    }

    #[test]
    fn los_interruptores_se_guardan_en_jev_sin_tocar_lo_demas() {
        let dir = std::env::temp_dir().join(format!("pixpin-jev-ajustes-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("pixpinmax.toml"),
            "# mio\nidioma = \"es\"\n\n[jev]\ntemas = false\n",
        )
        .unwrap();
        let n = Nucleo::abrir(dir.display().to_string(), "Mac".into()).unwrap();
        let a = n.ajustes_jev().unwrap();
        assert_eq!(a, n.ajustes_jev_de_fabrica());
        n.guardar_ajustes_jev(AjustesJev {
            anki: false,
            ..a.clone()
        })
        .unwrap();
        assert!(!n.ajustes_jev().unwrap().anki);
        let texto = std::fs::read_to_string(dir.join("pixpinmax.toml")).unwrap();
        assert!(texto.contains("# mio"), "{texto}");
        assert!(texto.contains("anki = false"), "{texto}");
        // Lo de Windows que el Mac no tiene sigue como estaba.
        assert!(texto.contains("temas = false"), "{texto}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn los_textos_son_los_de_windows() {
        let t = textos_de_jev("es-ES".into());
        assert_eq!(t.grupo, "TypeSafe (Jev)");
        assert_eq!(t.reunion.titulo, "Lo importante de clases y reuniones");
        assert_eq!(t.importante_buscando, "Buscando lo importante…");
        assert_eq!(t.prioridad_urgente, "Urgente");
        assert!(t.falta.ends_with("console.typesafe.ai"));
        assert!(texto_jev_tareas_por_apuntar("es".into(), 3).contains('3'));
        let en = textos_de_jev("en-US".into());
        assert_ne!(en.reunion.titulo, t.reunion.titulo);
    }
}
