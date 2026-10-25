//! **Grabar una clase o una reunion** (Windows edd0ffa, 24-oct-2026): lo
//! que se guarda en el chat al terminar, al caracter de Windows
//! (`ventana_chat/grabar_clase.rs`), para que sincronice sin cambios.
//!
//! La ventanita (preparar, la barra de grabar con «Captura», la zona y la
//! pausa) es de Swift (`Grabar/GrabarClase.swift`): el microfono con
//! AVAudioEngine y el sonido del Mac con ScreenCaptureKit, mezclados en un
//! solo `.m4a`. Aqui entra lo ya grabado con [`Nucleo::guardar_clase`]:
//!
//! 1. la nota de voz `Clase 24-10 18h05.m4a` (`clase-nombre` y
//!    `fecha_del_nombre` de Windows), con `duracionMs` y `picos`, como
//!    `guardar_la_voz`;
//! 2. detras, cada captura como imagen `clase-<ms>-<n>.png` con el pie
//!    `⏱ 12:34 · Clase 24-10 18h05`, con numeros seguidos, y en `resto`
//!    `enGrabacion: {de: <id de la voz>, ms}`;
//! 3. si entro alguna, la voz lleva en `resto` `capturas: [{ms, id}]` en
//!    orden y `grabacion: "clase"`.
//!
//! La pantalla de la letra de Windows (el texto a un lado y la imagen del
//! minuto que suena al otro) sale de [`Nucleo::capturas_de_la_clase`] y
//! [`captura_de_la_clase_en`].

use pixpin_proyecto::almacen;
use pixpin_proyecto::cuaderno::{self, Mensaje};

use crate::chats::validar_chat;
use crate::voz::{acotar_picos, marca_de_tiempo};
use crate::{ErrorNucleo, MensajeChat, Nucleo};

/// El campo de la voz con sus capturas (`[{ms, id}]`).
pub const CAMPO_CAPTURAS: &str = "capturas";
/// El campo de cada captura con su nota (`{de, ms}`).
pub const CAMPO_EN_GRABACION: &str = "enGrabacion";
/// El campo que dice que la voz es de una clase (`"clase"`).
pub const CAMPO_GRABACION: &str = "grabacion";

/// El minuto de una captura en el pie y en los avisos: `12:34` o
/// `1:02:03` (`grabar_clase::minuto`, igual que `marca_de_tiempo`).
pub fn minuto(ms: i64) -> String {
    marca_de_tiempo(ms)
}

/// La fecha del nombre de la nota, en hora local: `24-10 18h05` (sin `:`,
/// que Windows no admite en un nombre de fichero).
pub fn fecha_del_nombre(ahora_local_ms: i64) -> String {
    let dias = ahora_local_ms.div_euclid(86_400_000);
    let (_, mes, dia) = crate::automatizaciones::fecha_civil(dias);
    let del_dia = ahora_local_ms.rem_euclid(86_400_000) / 60_000;
    format!("{dia:02}-{mes:02} {:02}h{:02}", del_dia / 60, del_dia % 60)
}

/// El nombre de la nota (`clase-nombre = Clase { $fecha }`), sin extension.
pub fn nombre_de_la_clase(ahora_local_ms: i64) -> String {
    format!("Clase {}", fecha_del_nombre(ahora_local_ms))
}

/// El fichero de una nota de voz con nombre puesto
/// (`ventana_chat::nombre_de_la_voz(Some(n), _)` de Windows): ese nombre
/// (80 caracteres como mucho) con su `.m4a`, sin doblarlo. En blanco, la
/// hora (`voz_<ms>.m4a`).
pub fn nombre_de_la_voz_con(nombre: &str, ahora_ms: i64) -> String {
    let n = nombre.trim();
    if n.is_empty() {
        return crate::voz::nombre_de_la_voz(ahora_ms);
    }
    let n: String = n.chars().take(80).collect();
    if n.to_lowercase().ends_with(".m4a") {
        n
    } else {
        format!("{n}.m4a")
    }
}

/// El fichero de la captura `n` (desde 1): `clase-<ms>-<n>.png`.
pub fn fichero_de_captura(cuando_ms: i64, n: usize) -> String {
    format!("clase-{cuando_ms}-{n}.png")
}

/// El pie de una captura: `⏱ 12:34 · Clase 24-10 18h05`.
pub fn pie_de_captura(ms: i64, nombre: &str) -> String {
    format!("⏱ {} · {}", minuto(ms), nombre)
}

/// Lo que se apunta en la nota de voz: sus capturas en orden, `[{ms, id}]`.
pub fn capturas_en_json(capturas: &[(i64, String)]) -> serde_json::Value {
    let mut v: Vec<&(i64, String)> = capturas.iter().collect();
    v.sort_by_key(|(ms, _)| *ms);
    serde_json::Value::Array(
        v.into_iter()
            .map(|(ms, id)| serde_json::json!({ "ms": ms, "id": id }))
            .collect(),
    )
}

/// Las capturas de una nota de voz grabada como clase, `(ms, id)` en orden.
/// Vacio si no es de una clase o si lo apuntado no se entiende.
pub fn capturas_de(m: &Mensaje) -> Vec<(i64, String)> {
    let mut v: Vec<(i64, String)> = m
        .resto
        .get(CAMPO_CAPTURAS)
        .and_then(|c| c.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|c| Some((c.get("ms")?.as_i64()?, c.get("id")?.as_str()?.to_string())))
                .collect()
        })
        .unwrap_or_default();
    v.sort_by_key(|(ms, _)| *ms);
    v
}

/// La captura que toca en `posicion_ms`: la ultima hecha antes (o en ese
/// mismo momento). Antes de la primera, la primera: algo hay que ensenar.
pub fn captura_en(tiempos: &[i64], posicion_ms: i64) -> Option<usize> {
    if tiempos.is_empty() {
        return None;
    }
    Some(tiempos.iter().rposition(|ms| *ms <= posicion_ms).unwrap_or(0))
}

/// **La captura del minuto que suena** entre las de una clase (`tiempos`,
/// en orden): su posicion, o `None` sin capturas.
#[uniffi::export]
pub fn captura_de_la_clase_en(tiempos: Vec<i64>, posicion_ms: i64) -> Option<u32> {
    captura_en(&tiempos, posicion_ms).map(|n| n as u32)
}

/// Una captura hecha grabando: en que milisegundo de la nota y el PNG ya
/// escrito en un temporal (lo borra quien lo escribio).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CapturaClase {
    pub ms: i64,
    pub ruta_png: String,
}

/// Lo que dejo la clase en el chat: la voz como quedo y sus capturas, en el
/// orden del cuaderno.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ClaseGuardada {
    pub voz: MensajeChat,
    pub capturas: Vec<MensajeChat>,
}

/// Una captura de una clase para la pantalla de su letra (o sus tarjetas):
/// su minuto, el id de su mensaje y su fichero en este Mac (`None` si el
/// mensaje ya no esta o su ruta no se resuelve aqui).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CapturaDeLaClase {
    pub ms: i64,
    pub id: String,
    pub ruta: Option<String>,
}

#[uniffi::export]
impl Nucleo {
    /// **Mete una clase grabada en `chat`**: la nota de voz de `ruta_audio`
    /// y detras cada captura, enlazadas, como `grabar_clase::guardar` de
    /// Windows. `desfase_ms` es el de la hora local (el nombre lleva la
    /// fecha de aqui). Bloqueante: copia los ficheros. Los de origen no se
    /// tocan. Una captura que no entra se salta sin llevarse las demas.
    pub fn guardar_clase(
        &self,
        chat: String,
        ruta_audio: String,
        duracion_ms: i64,
        picos: Vec<i32>,
        capturas: Vec<CapturaClase>,
        desfase_ms: i64,
    ) -> Result<ClaseGuardada, ErrorNucleo> {
        validar_chat(&chat)?;
        let ahora = crate::ahora_ms();
        let nombre = nombre_de_la_clase(ahora + desfase_ms);
        let picos = acotar_picos(&picos);
        let voz = self.adjuntar_con(
            chat.clone(),
            ruta_audio,
            Some(nombre_de_la_voz_con(&nombre, ahora)),
            move |m| {
                m.duracion_ms = duracion_ms.max(0);
                m.resto
                    .insert("picos".into(), serde_json::Value::from(picos));
            },
        )?;
        let mut hechas = Vec::new();
        for (i, c) in capturas.into_iter().enumerate() {
            let fichero = fichero_de_captura(crate::ahora_ms(), i + 1);
            let pie = pie_de_captura(c.ms, &nombre);
            let de = voz.id.clone();
            let ms = c.ms;
            match self.adjuntar_con(chat.clone(), c.ruta_png, Some(fichero), move |m| {
                m.texto = pie.trim().to_string();
                m.resto.insert(
                    CAMPO_EN_GRABACION.into(),
                    serde_json::json!({ "de": de, "ms": ms }),
                );
            }) {
                Ok(m) => hechas.push((ms, m)),
                // Como Windows: la que no entra se salta.
                Err(_) => continue,
            }
        }
        if hechas.is_empty() {
            return Ok(ClaseGuardada {
                voz,
                capturas: Vec::new(),
            });
        }
        let enlazadas: Vec<(i64, String)> =
            hechas.iter().map(|(ms, m)| (*ms, m.id.clone())).collect();
        let carpeta = almacen::carpeta(self.ruta(), &chat);
        let fichero = carpeta.join("guardados.jsonl");
        let mut cache = self.cache_tomada();
        let cambiada = cuaderno::cambiar(&carpeta, &voz.id, |m| {
            m.resto
                .insert(CAMPO_CAPTURAS.into(), capturas_en_json(&enlazadas));
            m.resto
                .insert(CAMPO_GRABACION.into(), serde_json::json!("clase"));
            true
        })?;
        cache.quitar(&fichero);
        drop(cache);
        Ok(ClaseGuardada {
            voz: cambiada.map(MensajeChat::from).unwrap_or(voz),
            capturas: hechas.into_iter().map(|(_, m)| m).collect(),
        })
    }

    /// **Las capturas de una nota de voz grabada como clase** (`mensaje` es
    /// su id), en orden, con su fichero en este Mac. Vacio si no es de una
    /// clase. Bloqueante (lee el cuaderno): Swift lo guarda por mensaje.
    pub fn capturas_de_la_clase(
        &self,
        chat: String,
        mensaje: String,
    ) -> Result<Vec<CapturaDeLaClase>, ErrorNucleo> {
        validar_chat(&chat)?;
        let carpeta = almacen::carpeta(self.ruta(), &chat);
        let c = match cuaderno::Cuaderno::leer_de(&carpeta) {
            Ok(c) => c,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(e.into()),
        };
        let Some(voz) = c.mensajes.iter().find(|m| m.id == mensaje) else {
            return Ok(Vec::new());
        };
        Ok(capturas_de(voz)
            .into_iter()
            .map(|(ms, id)| {
                let ruta = c
                    .mensajes
                    .iter()
                    .find(|m| m.id == id)
                    .and_then(|m| m.ruta.as_deref())
                    .and_then(|r| self.resolver(&chat, r))
                    .map(|r| r.display().to_string());
                CapturaDeLaClase { ms, id, ruta }
            })
            .collect())
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn el_minuto_de_una_captura_se_lee_como_un_reloj() {
        assert_eq!(minuto(0), "0:00");
        assert_eq!(minuto(65_400), "1:05");
        assert_eq!(minuto(3_723_000), "1:02:03");
        // Caso negativo: un reloj que se fue atras no da minutos negativos.
        assert_eq!(minuto(-5), "0:00");
    }

    #[test]
    fn la_fecha_del_nombre_no_lleva_dos_puntos() {
        // 24-oct-2026 18:05 en hora local.
        let dias = 20_750; // 2026-10-24
        let ms = dias * 86_400_000 + (18 * 60 + 5) * 60_000;
        let f = fecha_del_nombre(ms);
        assert_eq!(f, "24-10 18h05");
        assert!(!f.contains(':'));
        assert_eq!(nombre_de_la_clase(ms), "Clase 24-10 18h05");
    }

    #[test]
    fn el_nombre_de_la_voz_lleva_su_m4a_una_vez() {
        assert_eq!(nombre_de_la_voz_con("Clase 24-10 18h05", 1), "Clase 24-10 18h05.m4a");
        assert_eq!(nombre_de_la_voz_con("ya.M4A", 1), "ya.M4A");
        let largo = "x".repeat(100);
        assert_eq!(nombre_de_la_voz_con(&largo, 1).chars().count(), 84);
        // Caso negativo: en blanco no hay nombre, va la hora.
        assert_eq!(nombre_de_la_voz_con("  ", 7), "voz_7.m4a");
    }

    #[test]
    fn el_pie_y_el_fichero_de_cada_captura_son_los_de_windows() {
        assert_eq!(pie_de_captura(65_400, "Clase 24-10 18h05"), "⏱ 1:05 · Clase 24-10 18h05");
        assert_eq!(fichero_de_captura(1_700, 2), "clase-1700-2.png");
    }

    #[test]
    fn las_capturas_van_y_vuelven_en_orden() {
        let mut m = Mensaje::default();
        m.resto.insert(
            CAMPO_CAPTURAS.into(),
            capturas_en_json(&[(9_000, "b".into()), (2_000, "a".into())]),
        );
        let v = capturas_de(&m);
        assert_eq!(v, vec![(2_000, "a".to_string()), (9_000, "b".to_string())]);
        // Caso negativo: una nota sin capturas no tiene ninguna, y una
        // entrada rota se salta sin llevarse las demas.
        assert!(capturas_de(&Mensaje::default()).is_empty());
        m.resto.insert(
            CAMPO_CAPTURAS.into(),
            serde_json::json!([{ "ms": "x" }, { "ms": 5, "id": "c" }]),
        );
        assert_eq!(capturas_de(&m), vec![(5, "c".to_string())]);
    }

    #[test]
    fn la_captura_del_momento_es_la_ultima_hecha_antes() {
        let c = vec![2_000, 9_000];
        assert_eq!(captura_en(&c, 500), Some(0), "antes de la primera, la primera");
        assert_eq!(captura_en(&c, 2_000), Some(0));
        assert_eq!(captura_en(&c, 8_999), Some(0));
        assert_eq!(captura_en(&c, 9_000), Some(1));
        assert_eq!(captura_de_la_clase_en(c, 99_000), Some(1));
        assert_eq!(captura_en(&[], 1_000), None);
    }
}
