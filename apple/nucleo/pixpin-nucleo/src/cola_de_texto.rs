//! **Toda grabacion se pasa a texto, aunque PixPin se cierre antes**
//! (Windows 5f4616f, `grabar_clase/cola_de_texto.rs`; Android `ColaDeTexto`).
//!
//! Cada nota de una clase guardada se apunta en
//! `voz/textos-pendientes/<id>.json` (`{proyecto, id, intentos}`, el mismo
//! fichero que Windows) **antes** de empezar a pasarla a texto, y se borra
//! al escribir el texto o si el usuario pulsa «Dejarlo sin texto». **Al
//! arrancar** se retoma lo que quedo: la nota que ya tiene texto (se paso a
//! mano desde el chat) o que ya no esta, fuera; la que no se pudo pasar (sin
//! reconocedor todavia), se queda para la siguiente vez; tras [`INTENTOS`]
//! fallos del reconocedor con ella, se deja (siempre queda «Pasar a texto»
//! en la nota). Es local de cada aparato: no viaja.
//!
//! Aqui el disco y la cuenta; el reconocedor es el de Swift.

use std::path::{Path, PathBuf};

use pixpin_proyecto::{almacen, cuaderno};
use serde::{Deserialize, Serialize};

use crate::{MensajeChat, Nucleo};

/// Los fallos del reconocedor con una nota antes de dejarla.
pub const INTENTOS: u32 = 3;

/// Una nota que espera su texto (lo que hay en el fichero).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Pendiente {
    proyecto: String,
    id: String,
    #[serde(default)]
    intentos: u32,
}

/// Una nota por retomar: su chat y la nota tal cual esta.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TextoPendiente {
    pub chat: String,
    pub voz: MensajeChat,
    pub intentos: u32,
}

fn carpeta(raiz: &Path) -> PathBuf {
    raiz.join("voz").join("textos-pendientes")
}

/// El fichero de la nota `id` (su id tal cual, sin lo que no puede ir en
/// un nombre de fichero).
fn fichero(raiz: &Path, id: &str) -> PathBuf {
    carpeta(raiz).join(format!("{}.json", almacen::nombre_seguro(id)))
}

fn escribir(f: &Path, p: &Pendiente) {
    if let Some(d) = f.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    if let Ok(b) = serde_json::to_vec(p) {
        let _ = std::fs::write(f, b);
    }
}

fn leer(f: &Path) -> Option<Pendiente> {
    serde_json::from_slice(&std::fs::read(f).ok()?).ok()
}

/// **Apunta la nota** (si ya estaba, se queda como estaba: no se pierden
/// sus intentos).
fn apuntar(raiz: &Path, proyecto: &str, id: &str) {
    let f = fichero(raiz, id);
    if f.is_file() {
        return;
    }
    escribir(
        &f,
        &Pendiente {
            proyecto: proyecto.to_string(),
            id: id.to_string(),
            intentos: 0,
        },
    );
}

fn quitar(raiz: &Path, id: &str) {
    let _ = std::fs::remove_file(fichero(raiz, id));
}

/// Un intento mas; tras [`INTENTOS`], fuera. Si sigue en la cola.
fn fallo(raiz: &Path, id: &str) -> bool {
    let f = fichero(raiz, id);
    let Some(mut p) = leer(&f) else {
        return false;
    };
    p.intentos += 1;
    if p.intentos >= INTENTOS {
        let _ = std::fs::remove_file(&f);
        return false;
    }
    escribir(&f, &p);
    true
}

/// Lo que espera, en el orden de sus nombres (lo que no se entiende, fuera;
/// lo que no es de la cola no se toca).
fn pendientes(raiz: &Path) -> Vec<Pendiente> {
    let Ok(dir) = std::fs::read_dir(carpeta(raiz)) else {
        return Vec::new();
    };
    let mut v: Vec<(PathBuf, Pendiente)> = Vec::new();
    for e in dir.flatten() {
        let ruta = e.path();
        if ruta.extension().is_none_or(|x| x != "json") {
            continue;
        }
        match leer(&ruta) {
            Some(p) => v.push((ruta, p)),
            None => {
                let _ = std::fs::remove_file(&ruta);
            }
        }
    }
    v.sort_by(|a, b| a.0.cmp(&b.0));
    v.into_iter().map(|(_, p)| p).collect()
}

#[uniffi::export]
impl Nucleo {
    /// **Apunta la nota `id` de `chat` para pasarla a texto**, antes de
    /// empezar (si PixPin se cierra a mitad, se retoma al arrancar).
    pub fn apuntar_texto_pendiente(&self, chat: String, id: String) {
        apuntar(self.ruta(), &chat, &id);
    }

    /// **Ya tiene su texto** (o el usuario no lo quiere): fuera de la cola.
    pub fn quitar_texto_pendiente(&self, id: String) {
        quitar(self.ruta(), &id);
    }

    /// **El reconocedor fallo con ella**: un intento mas; tras tres, fuera.
    /// Devuelve si sigue en la cola.
    pub fn fallo_texto_pendiente(&self, id: String) -> bool {
        fallo(self.ruta(), &id)
    }

    /// **Lo que hay que retomar al arrancar**: las notas apuntadas que aun
    /// estan y no tienen texto. Las que ya lo tienen o ya no estan salen de
    /// la cola aqui mismo.
    pub fn textos_por_retomar(&self) -> Vec<TextoPendiente> {
        let raiz = self.ruta();
        let mut v = Vec::new();
        for p in pendientes(raiz) {
            let voz = cuaderno::Cuaderno::leer_de(&almacen::carpeta(raiz, &p.proyecto))
                .ok()
                .and_then(|c| c.mensajes.into_iter().find(|m| m.id == p.id));
            let Some(voz) = voz else {
                quitar(raiz, &p.id);
                continue;
            };
            if voz
                .transcripcion
                .as_deref()
                .is_some_and(|t| !t.trim().is_empty())
            {
                quitar(raiz, &p.id);
                continue;
            }
            v.push(TextoPendiente {
                chat: p.proyecto,
                voz: MensajeChat::from(voz),
                intentos: p.intentos,
            });
        }
        v
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn raiz(nombre: &str) -> PathBuf {
        let r = std::env::temp_dir().join(format!(
            "pixpin-nucleo-cola-de-texto-{nombre}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&r);
        r
    }

    /// Las de Windows, tal cual.
    #[test]
    fn se_apunta_se_quita_y_tras_tres_fallos_se_deja() {
        let r = raiz("apuntar");
        assert!(pendientes(&r).is_empty());
        apuntar(&r, "p1", "v-2");
        apuntar(&r, "p1", "v-1");
        let v = pendientes(&r);
        assert_eq!(v.len(), 2);
        assert_eq!(v[0].id, "v-1");
        assert!(fallo(&r, "v-1"));
        apuntar(&r, "p1", "v-1");
        assert_eq!(pendientes(&r)[0].intentos, 1);
        assert!(fallo(&r, "v-1"));
        assert!(!fallo(&r, "v-1"));
        assert_eq!(pendientes(&r).len(), 1);
        quitar(&r, "v-2");
        assert!(pendientes(&r).is_empty());
        assert!(!fallo(&r, "nada"));
        assert!(pendientes(&r).is_empty());
        let _ = std::fs::remove_dir_all(&r);
    }

    #[test]
    fn lo_que_no_se_entiende_se_tira() {
        let r = raiz("roto");
        std::fs::create_dir_all(carpeta(&r)).unwrap();
        std::fs::write(carpeta(&r).join("x.json"), b"no es json").unwrap();
        std::fs::write(carpeta(&r).join("otro.txt"), b"{}").unwrap();
        assert!(pendientes(&r).is_empty());
        assert!(!carpeta(&r).join("x.json").exists());
        assert!(carpeta(&r).join("otro.txt").exists());
        let _ = std::fs::remove_dir_all(&r);
    }

    /// El fichero es el de Windows: `{proyecto, id, intentos}`.
    #[test]
    fn el_fichero_es_el_de_windows() {
        let r = raiz("formato");
        apuntar(&r, "obra", "1730000000000");
        let texto = std::fs::read_to_string(fichero(&r, "1730000000000")).unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&texto).unwrap(),
            serde_json::json!({ "proyecto": "obra", "id": "1730000000000", "intentos": 0 })
        );
        assert!(r.join("voz/textos-pendientes/1730000000000.json").is_file());
        let _ = std::fs::remove_dir_all(&r);
    }

    /// Al arrancar: la que no esta o ya tiene texto sale; la otra se retoma.
    #[test]
    fn al_arrancar_se_retoma_solo_lo_que_falta() {
        let r = raiz("retomar");
        let n = Nucleo::abrir(r.display().to_string(), "Mac".into()).unwrap();
        let chat = n.crear_chat("Clase".into()).unwrap().id;
        let audio = r.join("a.m4a");
        std::fs::create_dir_all(&r).unwrap();
        std::fs::write(&audio, b"m4a").unwrap();
        let hecho = n
            .guardar_clase(
                chat.clone(),
                Some(audio.display().to_string()),
                60_000,
                vec![],
                None,
                vec![],
                0,
            )
            .unwrap();
        let voz = hecho.voz.unwrap();
        n.apuntar_texto_pendiente(chat.clone(), voz.id.clone());
        // Caso negativo: una nota que ya no esta.
        n.apuntar_texto_pendiente(chat.clone(), "no-esta".into());
        let v = n.textos_por_retomar();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].chat, chat);
        assert_eq!(v[0].voz.id, voz.id);
        assert!(
            !fichero(&r, "no-esta").exists(),
            "la que no esta sale de la cola"
        );
        // Ya con texto (pasada a mano desde el chat), sale tambien.
        let carpeta_chat = almacen::carpeta(&r, &chat);
        cuaderno::cambiar(&carpeta_chat, &voz.id, |m| {
            m.transcripcion = Some("[0:00] hola".into());
            true
        })
        .unwrap();
        n.cache_tomada()
            .quitar(&carpeta_chat.join("guardados.jsonl"));
        assert!(n.textos_por_retomar().is_empty());
        assert!(!fichero(&r, &voz.id).exists());
        let _ = std::fs::remove_dir_all(&r);
    }
}
