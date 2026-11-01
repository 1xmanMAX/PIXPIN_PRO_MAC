//! **Lo importante de una clase o reunion** al acabar de pasarla a texto
//! (Windows 4c14408, `apps/pixpin/src/jev/reunion.rs`): cada renglon de la
//! transcripcion va a Jev con sus vecinos y el titulo
//! (`pindesk_typesafe::reunion`); lo hallado se escribe en la nota de voz,
//! `resto["importantes"]` y `resto["importantesDe"]`
//! (`pindesk_proyecto::clase`, el mismo formato que Windows y el movil).
//! «Estudiar la clase» lo ensena con sus chapitas y su filtro; las tareas
//! se pueden apuntar en Tareas ([`Nucleo::jev_importantes_a_tareas`]).
//!
//! Sin clave, con la funcion apagada o si algo falla, la nota se queda como
//! estaba (sin `importantes`): un fallo no se guarda como «no hay nada».

use std::collections::{BTreeSet, HashSet};
use std::sync::Mutex;

use pindesk_proyecto::almacen;
use pindesk_proyecto::clase::{self, Importante, TipoImportante};
use pindesk_proyecto::cuaderno::{self, Mensaje};
use pindesk_typesafe::reunion::{self as jr, Renglon};

use super::Funcion;
use crate::chats::validar_chat;
use crate::{ErrorNucleo, Nucleo};

/// Cuantas preguntas van a la vez (las de Windows).
const A_LA_VEZ: usize = 4;

/// Las notas que se estan mirando ahora (por id).
static EN_MARCHA: Mutex<Option<HashSet<String>>> = Mutex::new(None);

fn con_en_marcha<R>(f: impl FnOnce(&mut HashSet<String>) -> R) -> R {
    let mut g = EN_MARCHA.lock().unwrap_or_else(|e| e.into_inner());
    f(g.get_or_insert_with(HashSet::new))
}

/// Los renglones de la transcripcion de una nota de voz, como los lee
/// «Estudiar la clase» (sin las fotos metidas en el texto).
pub fn renglones_de(m: &Mensaje) -> Vec<Renglon> {
    crate::estudiar_clase::trozos_de_la_letra(m.transcripcion.as_deref().unwrap_or(""))
        .into_iter()
        .map(|(ms, texto)| Renglon { ms, texto })
        .filter(|r| !r.texto.trim().is_empty())
        .collect()
}

/// El color de cada tipo (el de Windows y su pagina compartida): azul la
/// tarea, verde la decision, morado la pregunta y rojo el examen.
pub fn color_de(t: TipoImportante) -> u32 {
    match t {
        TipoImportante::Tarea => 0x3b82f6,
        TipoImportante::Decision => 0x22a06b,
        TipoImportante::Pregunta => 0x8b5cf6,
        TipoImportante::Examen => 0xe5534b,
    }
}

fn a_guardar(h: &jr::Hallazgo) -> Importante {
    Importante {
        ms: h.ms,
        tipo: match h.tipo {
            jr::Tipo::Tarea => TipoImportante::Tarea,
            jr::Tipo::Decision => TipoImportante::Decision,
            jr::Tipo::Pregunta => TipoImportante::Pregunta,
            jr::Tipo::Examen => TipoImportante::Examen,
        },
        p: h.p,
        quien: h.quien,
        cuando: h.cuando,
        en_tareas: false,
    }
}

/// Escribe lo hallado en la nota de ahora (el chat o el movil pudieron
/// tocarla), y solo si el texto sigue siendo el que se miro. Lo ya apuntado
/// en Tareas sigue apuntado.
fn poner(m: &mut Mensaje, transcripcion: &Option<String>, v: &[Importante], modelo: &str) -> bool {
    if &m.transcripcion != transcripcion {
        return false;
    }
    let antes: Vec<i64> = clase::importantes_de(&m.resto)
        .unwrap_or_default()
        .into_iter()
        .filter(|i| i.en_tareas)
        .map(|i| i.ms)
        .collect();
    clase::poner_importantes(&mut m.resto, v, modelo);
    clase::marcar_en_tareas(&mut m.resto, &antes);
    true
}

/// El texto de la tarea apuntada desde la clase: lo dicho (recortado) y, en
/// su nota (`💬`), de que clase y en que minuto, para volver a el.
pub fn texto_de_tarea(dicho: &str, clase: &str, ms: i64) -> String {
    let dicho: String = dicho.split_whitespace().collect::<Vec<_>>().join(" ");
    let corto = if dicho.chars().count() > 140 {
        format!("{}…", dicho.chars().take(140).collect::<String>())
    } else {
        dicho
    };
    format!(
        "{corto} {} 🎙 {} ⏱ {}",
        pindesk_frase::tarea::NOTA,
        clase.trim(),
        pindesk_voz::tiempos::marca_de_tiempo(ms)
    )
}

/// Una parte importante, para Swift.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ImportanteDeClase {
    /// El minuto del renglon (el de [`crate::estudiar_clase::LineaDeClase::ms`]).
    pub ms: i64,
    /// `tarea`, `decision`, `pregunta` o `examen`.
    pub tipo: String,
    /// Su color (`0xRRGGBB`).
    pub color: u32,
    pub en_tareas: bool,
}

/// Cuantos renglones hay de un tipo (la chapita del filtro).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CuantosImportantes {
    pub tipo: String,
    pub color: u32,
    pub n: u32,
}

/// **Lo importante de una nota de voz**.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LoImportante {
    /// Ya se miro (`resto["importantes"]` esta, aunque sea vacio).
    pub mirado: bool,
    /// Jev la esta mirando ahora.
    pub buscando: bool,
    /// En orden de minuto.
    pub importantes: Vec<ImportanteDeClase>,
    /// Por tipo, en el orden de Windows; los que no hay, fuera.
    pub cuantos: Vec<CuantosImportantes>,
    /// Las tareas halladas que aun no estan en Tareas.
    pub por_apuntar: u32,
}

pub(crate) fn lo_importante_de(m: &Mensaje) -> LoImportante {
    let leidos = clase::importantes_de(&m.resto);
    let v = leidos.clone().unwrap_or_default();
    LoImportante {
        mirado: leidos.is_some(),
        buscando: con_en_marcha(|s| s.contains(&m.id)),
        importantes: v
            .iter()
            .map(|i| ImportanteDeClase {
                ms: i.ms,
                tipo: i.tipo.id().into(),
                color: color_de(i.tipo),
                en_tareas: i.en_tareas,
            })
            .collect(),
        cuantos: TipoImportante::TODOS
            .into_iter()
            .filter_map(|t| {
                let n = v.iter().filter(|i| i.tipo == t).map(|i| i.ms).collect::<BTreeSet<_>>().len();
                (n > 0).then(|| CuantosImportantes {
                    tipo: t.id().into(),
                    color: color_de(t),
                    n: n as u32,
                })
            })
            .collect(),
        por_apuntar: v
            .iter()
            .filter(|i| i.tipo == TipoImportante::Tarea && !i.en_tareas)
            .count() as u32,
    }
}

impl Nucleo {
    fn nota_de_voz(&self, chat: &str, voz: &str) -> Result<Mensaje, ErrorNucleo> {
        validar_chat(chat)?;
        cuaderno::Cuaderno::leer_de(&almacen::carpeta(self.ruta(), chat))?
            .mensajes
            .into_iter()
            .find(|m| m.id == voz)
            .ok_or_else(|| ErrorNucleo::NoExiste {
                que: "la nota ya no esta".into(),
            })
    }

    /// Cambia la nota en el cuaderno, con la cache del chat tomada.
    fn cambiar_nota_de_voz(
        &self,
        chat: &str,
        voz: &str,
        cambio: impl FnOnce(&mut Mensaje) -> bool,
    ) -> Result<bool, ErrorNucleo> {
        let carpeta = almacen::carpeta(self.ruta(), chat);
        let fichero = carpeta.join("guardados.jsonl");
        let mut cache = self.cache_tomada();
        let hecho = cuaderno::cambiar(&carpeta, voz, cambio);
        cache.quitar(&fichero);
        drop(cache);
        Ok(hecho?.is_some())
    }
}

#[uniffi::export]
impl Nucleo {
    /// **Lo importante de la nota de voz** `voz` de `chat` (lo guardado y si
    /// Jev la esta mirando).
    pub fn jev_lo_importante(&self, chat: String, voz: String) -> Result<LoImportante, ErrorNucleo> {
        Ok(lo_importante_de(&self.nota_de_voz(&chat, &voz)?))
    }

    /// **Busca lo importante de la nota** con Jev, si hay clave, la funcion
    /// esta encendida y la nota aun no se miro (`forzar`: aunque ya se
    /// mirara, tras volver a pasarla a texto). Bloquea (unos segundos por
    /// clase): Swift lo llama en segundo plano. Devuelve si se escribio.
    pub fn jev_buscar_lo_importante(&self, chat: String, voz: String, forzar: bool) -> Result<bool, ErrorNucleo> {
        let Some(cliente) = super::para(self.ruta(), Funcion::Reunion) else {
            return Ok(false);
        };
        let m = self.nota_de_voz(&chat, &voz)?;
        if !forzar && clase::importantes_de(&m.resto).is_some() {
            return Ok(false);
        }
        let renglones = renglones_de(&m);
        if renglones.is_empty() {
            return Ok(false);
        }
        if !con_en_marcha(|s| s.insert(voz.clone())) {
            return Ok(false);
        }
        let hallado = jr::buscar(&cliente, &crate::anki::titulo_de_audio(&m), &renglones, A_LA_VEZ);
        let r = match hallado {
            Ok((hallado, modelo)) => {
                let v: Vec<Importante> = hallado.iter().map(a_guardar).collect();
                let transcripcion = m.transcripcion.clone();
                let mut puesto = false;
                self.cambiar_nota_de_voz(&chat, &voz, |n| {
                    puesto = poner(n, &transcripcion, &v, &modelo);
                    puesto
                })
                .map(|_| puesto)
            }
            Err(e) => Err(ErrorNucleo::Asistente { detalle: e.to_string() }),
        };
        con_en_marcha(|s| s.remove(&voz));
        r
    }

    /// **Apunta en el Inbox de Tareas** las tareas halladas en la nota que
    /// aun no se apuntaron (con su clase y su minuto en la nota) y las marca
    /// (`enTareas`). Devuelve cuantas.
    pub fn jev_importantes_a_tareas(&self, chat: String, voz: String, desfase_ms: i64) -> Result<u32, ErrorNucleo> {
        let m = self.nota_de_voz(&chat, &voz)?;
        let pendientes: Vec<i64> = clase::importantes_de(&m.resto)
            .unwrap_or_default()
            .into_iter()
            .filter(|i| i.tipo == TipoImportante::Tarea && !i.en_tareas)
            .map(|i| i.ms)
            .collect();
        if pendientes.is_empty() {
            return Ok(0);
        }
        let renglones = renglones_de(&m);
        let titulo = crate::anki::titulo_de_audio(&m);
        let mut hechas = Vec::new();
        for ms in pendientes {
            let Some(r) = renglones.iter().find(|r| r.ms == Some(ms)) else {
                continue;
            };
            if self.apuntar_tarea(texto_de_tarea(&r.texto, &titulo, ms), desfase_ms).is_ok() {
                hechas.push(ms);
            }
        }
        if !hechas.is_empty() {
            self.cambiar_nota_de_voz(&chat, &voz, |n| clase::marcar_en_tareas(&mut n.resto, &hechas))?;
        }
        Ok(hechas.len() as u32)
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn nota(transcripcion: &str) -> Mensaje {
        Mensaje {
            id: "n1".into(),
            nombre: "Cálculo I.m4a".into(),
            clase: Some(cuaderno::Clase::Voz),
            transcripcion: Some(transcripcion.into()),
            ..Default::default()
        }
    }

    #[test]
    fn la_tarea_lleva_de_que_clase_y_que_minuto() {
        let t = texto_de_tarea("Para el lunes   resuelvan los ejercicios del 1 al 5.", "Cálculo I", 65_000);
        assert_eq!(t, "Para el lunes resuelvan los ejercicios del 1 al 5. 💬 🎙 Cálculo I ⏱ 1:05");
        assert!(texto_de_tarea(&"palabra ".repeat(60), "x", 0).contains('…'));
    }

    #[test]
    fn los_renglones_son_los_de_estudiar_la_clase() {
        let m = nota("[0:00] Hola a todos.\n\n[1:05] Para el lunes resuelvan del 1 al 5.\n\n![foto](x.png)");
        let r = renglones_de(&m);
        assert_eq!(r.len(), 2);
        assert_eq!(r[1].ms, Some(65_000));
        assert_eq!(crate::anki::titulo_de_audio(&m), "Cálculo I");
    }

    #[test]
    fn lo_hallado_se_escribe_como_windows_y_respeta_lo_apuntado() {
        let mut m = nota("[1:05] Para el lunes resuelvan del 1 al 5.");
        let sin = lo_importante_de(&m);
        assert!(!sin.mirado && sin.importantes.is_empty());
        let v = vec![
            Importante {
                ms: 65_000,
                tipo: TipoImportante::Tarea,
                p: 0.94,
                quien: Some(true),
                cuando: Some(true),
                en_tareas: false,
            },
            Importante {
                ms: 65_000,
                tipo: TipoImportante::Examen,
                p: 0.8,
                quien: None,
                cuando: None,
                en_tareas: false,
            },
        ];
        let t = m.transcripcion.clone();
        assert!(poner(&mut m, &t, &v, "jev-1.14.0"));
        assert_eq!(m.resto["importantesDe"], "jev-1.14.0");
        assert_eq!(m.resto["importantes"][0]["tipo"], "tarea");
        assert_eq!(m.resto["importantes"][0]["p"], 0.94);
        let l = lo_importante_de(&m);
        assert!(l.mirado);
        assert_eq!(l.por_apuntar, 1);
        assert_eq!(l.cuantos.len(), 2);
        assert_eq!(l.cuantos[0].tipo, "tarea");
        assert_eq!(l.cuantos[0].color, 0x3b82f6);
        // Apuntada en Tareas: al volver a mirar sigue apuntada.
        assert!(clase::marcar_en_tareas(&mut m.resto, &[65_000]));
        assert!(poner(&mut m, &t, &v, "jev-1.14.0"));
        assert_eq!(lo_importante_de(&m).por_apuntar, 0);
        // Si el texto cambio mientras se miraba, no se toca.
        assert!(!poner(&mut m, &Some("otro".into()), &[], ""));
    }

    #[test]
    fn sin_clave_no_se_busca_nada() {
        let dir = std::env::temp_dir().join(format!("pixpin-jev-reunion-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let n = Nucleo::abrir(dir.display().to_string(), "Mac".into()).unwrap();
        assert!(!n.jev_buscar_lo_importante("x".into(), "n1".into(), true).unwrap());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
