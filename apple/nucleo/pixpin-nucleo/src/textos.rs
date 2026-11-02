//! **Los textos de la interfaz Swift**, de los mismos catalogos que Windows
//! (`pindesk-store/i18n/<etiqueta>/main.ftl`, los catorce idiomas de
//! `Idioma::TODOS`): una sola fuente de verdad. Swift pide cada texto por su
//! clave (`ajustes-idioma`, `chat-enviar`…) y Fluent hace los plurales de
//! cada lengua (`[few]` en ruso, `[two]` en arabe…).
//!
//! El idioma es el de `pixpinmax.toml` (`idioma`, el mismo campo y los
//! mismos codigos que Windows) o, con `sistema`, el del Mac
//! (`Locale.preferredLanguages`), resuelto como en Windows
//! (`resolver_idioma`). Como en Windows, vale desde el arranque: Swift crea
//! el catalogo una vez ([`textos_de_la_app`]).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use fluent_bundle::{FluentArgs, FluentValue};
use pindesk_store::ajustes::{self, PreferenciaIdioma};
use pindesk_store::idioma::{Catalogo, Idioma, resolver_idioma};
use pindesk_store::rutas::Ubicacion;

use crate::ajustes::{idioma_de, texto_idioma};

/// Una opcion del selector de idioma de Ajustes.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpcionDeIdioma {
    /// Lo que se guarda en `idioma` de `pixpinmax.toml` (`sistema`, `es`,
    /// `zh-CN`…), igual que Windows.
    pub valor: String,
    /// El nombre en su propia lengua («日本語», «العربية»); el de `sistema`,
    /// en el idioma actual.
    pub nombre: String,
}

/// El catalogo de textos de la app, ya resuelto a un idioma.
#[derive(uniffi::Object)]
pub struct CatalogoDeTextos {
    catalogo: Catalogo,
    idioma: Idioma,
    preferencia: PreferenciaIdioma,
}

impl CatalogoDeTextos {
    fn con(preferencia: PreferenciaIdioma, locale_sistema: &str) -> Arc<Self> {
        let idioma = resolver_idioma(locale_sistema, preferencia);
        Arc::new(CatalogoDeTextos {
            catalogo: Catalogo::nuevo(idioma),
            idioma,
            preferencia,
        })
    }
}

/// Los argumentos de Swift, todos texto: un entero (escrito tal cual, `12`)
/// entra en Fluent como numero, para que elija la forma de plural; lo demas
/// (`2.000` ya con sus puntos, `0,5`, un nombre), como texto.
fn argumentos(a: &HashMap<String, String>) -> FluentArgs<'static> {
    let mut args = FluentArgs::new();
    for (k, v) in a {
        let valor: FluentValue<'static> = match v.parse::<i64>() {
            Ok(n) if n.to_string() == *v => FluentValue::from(n),
            _ => FluentValue::from(v.clone()),
        };
        args.set(k.clone(), valor);
    }
    args
}

/// **Los textos que usa solo el Mac** y que Windows quito de su catalogo
/// (`i18n-mac/<etiqueta>.ftl`): se leen solo si la clave falta en
/// `pindesk-store`, en el idioma elegido o, si no, en ingles o espanol.
fn del_mac(idioma: Idioma, clave: &str, args: Option<&FluentArgs>) -> Option<String> {
    use fluent_bundle::{FluentResource, concurrent::FluentBundle};
    use std::sync::OnceLock;
    static MAC: OnceLock<Vec<(Idioma, FluentBundle<FluentResource>)>> = OnceLock::new();
    let todos = MAC.get_or_init(|| {
        Idioma::TODOS
            .into_iter()
            .filter_map(|i| {
                let texto = match i.etiqueta() {
                    "es-ES" => include_str!("../i18n-mac/es-ES.ftl"),
                    "en-US" => include_str!("../i18n-mac/en-US.ftl"),
                    "zh-CN" => include_str!("../i18n-mac/zh-CN.ftl"),
                    "hi-IN" => include_str!("../i18n-mac/hi-IN.ftl"),
                    "ar-SA" => include_str!("../i18n-mac/ar-SA.ftl"),
                    "pt-BR" => include_str!("../i18n-mac/pt-BR.ftl"),
                    "fr-FR" => include_str!("../i18n-mac/fr-FR.ftl"),
                    "de-DE" => include_str!("../i18n-mac/de-DE.ftl"),
                    "ja-JP" => include_str!("../i18n-mac/ja-JP.ftl"),
                    "ru-RU" => include_str!("../i18n-mac/ru-RU.ftl"),
                    "ko-KR" => include_str!("../i18n-mac/ko-KR.ftl"),
                    "it-IT" => include_str!("../i18n-mac/it-IT.ftl"),
                    "id-ID" => include_str!("../i18n-mac/id-ID.ftl"),
                    "tr-TR" => include_str!("../i18n-mac/tr-TR.ftl"),
                    _ => return None,
                };
                let recurso = FluentResource::try_new(texto.to_string()).unwrap_or_else(|(r, _)| r);
                let lang = i.etiqueta().parse().ok()?;
                let mut b = FluentBundle::new_concurrent(vec![lang]);
                b.set_use_isolating(false);
                b.add_resource_overriding(recurso);
                Some((i, b))
            })
            .collect()
    });
    [idioma, Idioma::Ingles, Idioma::Espanol].into_iter().find_map(|i| {
        let (_, b) = todos.iter().find(|(j, _)| *j == i)?;
        let patron = b.get_message(clave)?.value()?;
        let mut errores = Vec::new();
        Some(b.format_pattern(patron, args, &mut errores).into_owned())
    })
}

/// El texto de `clave` en `c`, o el del Mac si `pindesk-store` ya no la
/// tiene ([`del_mac`]).
pub(crate) fn texto(c: &Catalogo, clave: &str) -> String {
    let t = c.t(clave);
    if t != clave {
        return t;
    }
    del_mac(c.idioma(), clave, None).unwrap_or(t)
}

/// El texto de «el del sistema» en el Mac: el catalogo dice «El de
/// Windows» en cada lengua; aqui es macOS.
fn nombre_del_sistema(c: &Catalogo) -> String {
    c.t("ajustes-idioma-sistema").replace("Windows", "macOS")
}

#[uniffi::export]
impl CatalogoDeTextos {
    /// `idioma`: el codigo de `pixpinmax.toml` (`sistema`, `es`, `zh-CN`…;
    /// uno desconocido, `sistema`). `locale_sistema`: el del Mac
    /// (`Locale.preferredLanguages.first`).
    #[uniffi::constructor]
    pub fn nuevo(idioma: String, locale_sistema: String) -> Arc<Self> {
        Self::con(idioma_de(&idioma).unwrap_or(PreferenciaIdioma::Sistema), &locale_sistema)
    }

    /// El texto de `clave` (la propia clave si no esta en ningun catalogo).
    pub fn t(&self, clave: String) -> String {
        texto(&self.catalogo, &clave)
    }

    /// El texto de `clave` con sus `{ $argumentos }`.
    pub fn con_argumentos(&self, clave: String, argumentos: HashMap<String, String>) -> String {
        let args = self::argumentos(&argumentos);
        let t = self.catalogo.t_args(&clave, &args);
        if t != clave {
            return t;
        }
        del_mac(self.idioma, &clave, Some(&args)).unwrap_or(t)
    }

    /// Si `clave` esta en algun catalogo (el elegido, ingles o espanol).
    pub fn tiene(&self, clave: String) -> bool {
        texto(&self.catalogo, &clave) != clave
    }

    /// La etiqueta BCP 47 del idioma (`es-ES`, `ar-SA`…): el `Locale` de
    /// las fechas y los numeros.
    pub fn etiqueta(&self) -> String {
        self.idioma.etiqueta().to_string()
    }

    /// Solo el idioma (`es`, `zh`, `ar`…).
    pub fn codigo(&self) -> String {
        self.idioma.codigo().to_string()
    }

    /// Si se escribe de derecha a izquierda (el arabe).
    pub fn de_derecha_a_izquierda(&self) -> bool {
        self.idioma.es_rtl()
    }

    /// Si sigue al idioma del Mac (`idioma = "sistema"`).
    pub fn sigue_al_sistema(&self) -> bool {
        self.preferencia == PreferenciaIdioma::Sistema
    }

    /// El codigo guardado en los ajustes con el que se creo.
    pub fn preferencia(&self) -> String {
        texto_idioma(self.preferencia).to_string()
    }

    /// Las quince opciones del selector, en el orden de Windows: el del
    /// sistema y los catorce idiomas, cada uno con su nombre en su lengua.
    pub fn opciones_de_idioma(&self) -> Vec<OpcionDeIdioma> {
        PreferenciaIdioma::opciones()
            .map(|p| OpcionDeIdioma {
                valor: texto_idioma(p).to_string(),
                nombre: match p.idioma() {
                    Some(i) => i.nombre_propio().to_string(),
                    None => nombre_del_sistema(&self.catalogo),
                },
            })
            .collect()
    }
}

/// **El catalogo de la app**: el idioma de `pixpinmax.toml` de la carpeta
/// de datos `raiz` (si no se puede leer, el del Mac).
#[uniffi::export]
pub fn textos_de_la_app(raiz: String, locale_sistema: String) -> Arc<CatalogoDeTextos> {
    let ubicacion = Ubicacion::Instalado {
        raiz: PathBuf::from(raiz),
    };
    let preferencia = ajustes::cargar(&ubicacion)
        .map(|a| a.idioma)
        .unwrap_or(PreferenciaIdioma::Sistema);
    CatalogoDeTextos::con(preferencia, &locale_sistema)
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn mapa(pares: &[(&str, &str)]) -> HashMap<String, String> {
        pares.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn el_idioma_de_los_ajustes_gana_al_del_mac() {
        let c = CatalogoDeTextos::nuevo("ja".into(), "es-ES".into());
        assert_eq!(c.etiqueta(), "ja-JP");
        assert_eq!(c.preferencia(), "ja");
        assert!(!c.sigue_al_sistema());
        assert_eq!(c.t("ajustes-idioma".into()), Catalogo::nuevo(Idioma::Japones).t("ajustes-idioma"));
        // Lo que Windows quito y el Mac usa sale del catalogo del Mac.
        assert_ne!(c.t("carpeta-renombrar".into()), "carpeta-renombrar");
        assert!(c.tiene("info-ver-en-el-chat".into()));
    }

    #[test]
    fn con_sistema_sigue_al_mac_y_lo_desconocido_es_sistema() {
        let c = CatalogoDeTextos::nuevo("sistema".into(), "fr-CA".into());
        assert_eq!(c.etiqueta(), "fr-FR");
        assert!(c.sigue_al_sistema());
        let c = CatalogoDeTextos::nuevo("klingon".into(), "zh-Hans-CN".into());
        assert_eq!(c.etiqueta(), "zh-CN");
        assert_eq!(c.preferencia(), "sistema");
        // Las etiquetas largas que tambien acepta el fichero.
        assert_eq!(CatalogoDeTextos::nuevo("pt-BR".into(), "en".into()).codigo(), "pt");
        assert_eq!(CatalogoDeTextos::nuevo("de-DE".into(), "en".into()).codigo(), "de");
    }

    #[test]
    fn el_arabe_va_de_derecha_a_izquierda_y_los_demas_no() {
        for o in CatalogoDeTextos::nuevo("es".into(), "es".into()).opciones_de_idioma() {
            let c = CatalogoDeTextos::nuevo(o.valor.clone(), "es".into());
            assert_eq!(c.de_derecha_a_izquierda(), o.valor == "ar", "{}", o.valor);
        }
    }

    #[test]
    fn el_selector_tiene_el_sistema_y_los_catorce_con_su_nombre() {
        let c = CatalogoDeTextos::nuevo("es".into(), "es".into());
        let o = c.opciones_de_idioma();
        assert_eq!(o.len(), 15);
        assert_eq!(o[0].valor, "sistema");
        assert_eq!(o[0].nombre, "El de macOS");
        let valores: Vec<&str> = o.iter().map(|x| x.valor.as_str()).collect();
        assert_eq!(
            valores,
            [
                "sistema", "es", "en", "zh-CN", "hi", "ar", "pt-BR", "fr", "de", "ja", "ru", "ko",
                "it", "id", "tr"
            ]
        );
        assert_eq!(o[4].nombre, "हिन्दी");
        assert_eq!(o[5].nombre, "العربية");
        // Cada codigo vuelve a ser el mismo al leerlo (sincroniza con Windows).
        for x in &o {
            assert_eq!(CatalogoDeTextos::nuevo(x.valor.clone(), "en".into()).preferencia(), x.valor);
        }
        // Ningun idioma dice «Windows» en el selector del Mac.
        for x in &o {
            let c = CatalogoDeTextos::nuevo(x.valor.clone(), "en".into());
            assert!(!c.opciones_de_idioma()[0].nombre.contains("Windows"), "{}", x.valor);
        }
    }

    #[test]
    fn los_argumentos_numericos_eligen_el_plural() {
        let es = CatalogoDeTextos::nuevo("es".into(), "es".into());
        let uno = es.con_argumentos("ajustes2-resultados-sub".into(), mapa(&[("n", "1")]));
        let tres = es.con_argumentos("ajustes2-resultados-sub".into(), mapa(&[("n", "3")]));
        assert!(uno.contains('1') && tres.contains('3'), "{uno} / {tres}");
        assert_ne!(uno.replace('1', ""), tres.replace('3', ""), "el plural cambia la frase");
        let texto = es.con_argumentos("ajustes2-resultados".into(), mapa(&[("busqueda", "voz")]));
        assert!(texto.contains("voz"), "{texto}");
        // Un numero ya escrito con sus puntos se queda como esta.
        let px = es.con_argumentos("ajustes2-u-px".into(), mapa(&[("n", "2.000")]));
        assert_eq!(px, "2.000 px");
        let dias = es.con_argumentos("ajustes2-u-dias".into(), mapa(&[("n", "1")]));
        assert_eq!(dias, "1 día");
    }

    #[test]
    fn una_clave_que_falta_se_devuelve_tal_cual() {
        let c = CatalogoDeTextos::nuevo("ko".into(), "es".into());
        assert_eq!(c.t("no-existe-esta-clave".into()), "no-existe-esta-clave");
        assert!(!c.tiene("no-existe-esta-clave".into()));
        assert!(c.tiene("ajustes-idioma".into()));
    }

    #[test]
    fn la_app_lee_el_idioma_de_pixpinmax_toml() {
        let d = std::env::temp_dir().join(format!("pixpin-nucleo-textos-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let raiz = d.display().to_string();
        // Sin fichero: el del Mac.
        assert_eq!(textos_de_la_app(raiz.clone(), "it-IT".into()).etiqueta(), "it-IT");
        let u = Ubicacion::Instalado { raiz: d.clone() };
        let mut a = ajustes::Ajustes::default();
        a.idioma = PreferenciaIdioma::Arabe;
        ajustes::guardar(&u, &a).unwrap();
        let c = textos_de_la_app(raiz, "it-IT".into());
        assert_eq!(c.etiqueta(), "ar-SA");
        assert!(c.de_derecha_a_izquierda());
        let _ = std::fs::remove_dir_all(&d);
    }
}
