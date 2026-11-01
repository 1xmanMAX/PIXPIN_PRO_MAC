//! **La prioridad de cada tarea segun su contexto** (Windows fa4ca12,
//! `apps/pixpin/src/jev/urgencia.rs`): por cada tarea pendiente, Jev juzga
//! lo que pasa si se hace tarde, si otro la espera, si el plazo lo puso otro
//! y si en su chat la piden ya (`pindesk_typesafe::urgencia`); cuanto falta
//! para su hora (`⏰`) lo cuenta el codigo, y la tabla de alli da urgente,
//! alta, normal o baja. Lo que el usuario marco (⏫, 🔼) manda.
//!
//! Va en segundo plano: al leer las listas ([`aplicar`], desde
//! `Nucleo::tareas_con_jev`) se pone lo ya sabido y se pregunta por lo que falta en
//! un hilo; Swift relee mientras [`jev_preguntando_tareas`] diga que si. Lo
//! sabido se queda en memoria mientras la app este abierta; nada va al
//! disco ni viaja.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use pindesk_proyecto::{almacen, cuaderno};
use pindesk_typesafe::urgencia::{self as ju, Contexto, Marca, Prioridad, Senales};

use super::Funcion;
use crate::tareas::ListaTareas;
use crate::{ErrorNucleo, Nucleo};
use crate::tareas::frase::{self, Urgencia};

enum Sabido {
    Senales(Senales),
    Fallo(Instant),
}

static SABIDO: Mutex<Option<HashMap<String, Sabido>>> = Mutex::new(None);
static PREGUNTANDO: AtomicBool = AtomicBool::new(false);

/// Tras un fallo, cuanto se espera para volver a preguntar.
const TRAS_UN_FALLO: Duration = Duration::from_secs(10 * 60);
const A_LA_VEZ: usize = 4;
const POR_TANDA: usize = 60;

fn con_sabido<R>(f: impl FnOnce(&mut HashMap<String, Sabido>) -> R) -> R {
    let mut g = SABIDO.lock().unwrap_or_else(|e| e.into_inner());
    f(g.get_or_insert_with(HashMap::new))
}

/// La clave de una tarea: su chat, el titulo de su lista y su texto.
fn clave_de(chat: &str, lista: &str, texto: &str) -> String {
    format!("{chat}\u{1f}{lista}\u{1f}{texto}")
}

fn marca_de(u: Urgencia) -> Marca {
    match u {
        Urgencia::MuyUrgente => Marca::MuyUrgente,
        Urgencia::Urgente => Marca::Urgente,
        Urgencia::Normal => Marca::Ninguna,
    }
}

/// Lo que se le manda de la tarea: su titulo sin marcas y, si tiene, su nota.
fn texto_para_jev(f: &frase::Frase) -> String {
    match &f.nota {
        Some(n) if !n.trim().is_empty() => format!("{} ({})", f.titulo.trim(), n.trim()),
        _ => f.titulo.trim().to_string(),
    }
}

/// Lo que se ensena (y con que se ordena): la de Jev.
fn id_de(p: Prioridad) -> String {
    p.id().to_string()
}

/// **Pone la prioridad de cada tarea pendiente** con lo ya sabido, y lanza
/// en su hilo las preguntas de lo que falta.
pub(crate) fn aplicar(raiz: &Path, listas: &mut [ListaTareas], desfase_ms: i64) {
    let Some(cliente) = super::para(raiz, Funcion::Urgencia) else {
        return;
    };
    let hoy = frase::ahora(desfase_ms).dia;
    let faltan = poner_sabido(listas, hoy);
    if faltan.is_empty() || PREGUNTANDO.swap(true, Ordering::SeqCst) {
        return;
    }
    let mut faltan = faltan;
    faltan.truncate(POR_TANDA);
    let raiz: PathBuf = raiz.to_path_buf();
    let lanzado = std::thread::Builder::new()
        .name("jev-urgencia".into())
        .spawn(move || {
            preguntar(&cliente, &raiz, faltan);
            PREGUNTANDO.store(false, Ordering::SeqCst);
        });
    if lanzado.is_err() {
        PREGUNTANDO.store(false, Ordering::SeqCst);
    }
}

/// Lo sabido, puesto; devuelve lo que falta preguntar (clave, chat, contexto).
fn poner_sabido(listas: &mut [ListaTareas], hoy: i64) -> Vec<(String, String, Contexto)> {
    let mut faltan = Vec::new();
    for l in listas.iter_mut() {
        let (chat, titulo, nombre) = (l.chat.clone(), l.titulo.clone(), l.nombre_chat.clone());
        for t in l.tareas.iter_mut().filter(|t| !t.hecha) {
            let m = frase::marcas(&t.texto);
            let texto = texto_para_jev(&m);
            if texto.is_empty() {
                continue;
            }
            let dias = m.hora.map(|h| h.dia - hoy);
            let clave = clave_de(&chat, &titulo, &texto);
            let sabido = con_sabido(|s| match s.get(&clave) {
                Some(Sabido::Senales(x)) => Some(Some(x.clone())),
                Some(Sabido::Fallo(t)) if t.elapsed() < TRAS_UN_FALLO => Some(None),
                _ => None,
            });
            match sabido {
                Some(Some(s)) => t.prioridad = Some(id_de(ju::decidir(marca_de(m.urgencia), Some(&s), dias))),
                Some(None) => {}
                None => faltan.push((
                    clave,
                    chat.clone(),
                    Contexto {
                        tarea: texto,
                        lista: titulo.clone(),
                        chat: nombre.clone(),
                        recientes: Vec::new(),
                    },
                )),
            }
        }
    }
    faltan
}

fn preguntar(cliente: &pindesk_typesafe::Cliente, raiz: &Path, mut faltan: Vec<(String, String, Contexto)>) {
    let mut recientes: HashMap<String, Vec<String>> = HashMap::new();
    for (_, chat, c) in &mut faltan {
        let r = recientes.entry(chat.clone()).or_insert_with(|| recientes_del_chat(raiz, chat));
        c.recientes = r.clone();
    }
    let contextos: Vec<Contexto> = faltan.iter().map(|(_, _, c)| c.clone()).collect();
    let respuestas = ju::preguntar_varias(cliente, &contextos, A_LA_VEZ);
    con_sabido(|s| {
        for ((clave, _, _), r) in faltan.into_iter().zip(respuestas) {
            match r {
                Ok(x) => s.insert(clave, Sabido::Senales(x)),
                Err(_) => s.insert(clave, Sabido::Fallo(Instant::now())),
            };
        }
    });
}

/// Los ultimos mensajes escritos del chat (notas con texto, no las listas
/// de tareas), del mas viejo al mas nuevo.
fn recientes_del_chat(raiz: &Path, chat: &str) -> Vec<String> {
    let Ok(c) = cuaderno::Cuaderno::leer_de(&almacen::carpeta(raiz, chat)) else {
        return Vec::new();
    };
    let mut v: Vec<String> = c
        .mensajes
        .iter()
        .rev()
        .filter(|m| m.ruta.is_none() && !crate::tareas::es_lista(m))
        .map(|m| m.texto.trim().to_string())
        .filter(|t| !t.is_empty())
        .take(ju::RECIENTES)
        .collect();
    v.reverse();
    v
}

#[uniffi::export]
impl Nucleo {
    /// **Las listas de la ventana de Tareas**, como [`crate::Nucleo::tareas`]
    /// y con la prioridad de Jev en cada tarea pendiente ya sabida (lo que
    /// falta se pregunta en su hilo). Solo la ventana de Tareas: los demas
    /// lectores de tareas (avisos, horario) no gastan en Jev, como Windows.
    pub fn tareas_con_jev(&self, desfase_ms: i64) -> Result<Vec<ListaTareas>, ErrorNucleo> {
        let mut listas = self.tareas(desfase_ms)?;
        aplicar(self.ruta(), &mut listas, desfase_ms);
        Ok(listas)
    }
}

/// **Si Jev aun esta mirando la prioridad de las tareas**: mientras diga
/// que si, Tareas relee cada poco para ensenar lo que llega.
#[uniffi::export]
pub fn jev_preguntando_tareas() -> bool {
    PREGUNTANDO.load(Ordering::SeqCst)
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::tareas::Tarea;
    use pindesk_typesafe::api::Escala;

    fn lista(textos: &[&str]) -> ListaTareas {
        ListaTareas {
            chat: "p".into(),
            nombre_chat: "Mensajes guardados".into(),
            guardados: true,
            mensaje: "m".into(),
            titulo: "Inbox".into(),
            cuando: 0,
            es_inbox: true,
            tareas: textos
                .iter()
                .enumerate()
                .map(|(i, t)| Tarea {
                    indice: i as u32,
                    crudo: (*t).into(),
                    texto: (*t).into(),
                    hecha: false,
                    recuerda: None,
                    creada: None,
                    dias: None,
                    imagenes: Vec::new(),
                    prioridad: None,
                })
                .collect(),
            pendientes: textos.len() as u32,
        }
    }

    #[test]
    fn sin_clave_no_se_toca_nada() {
        let mut l = vec![lista(&["pagar la matrícula ⏫", "pan"])];
        aplicar(&std::env::temp_dir(), &mut l, 0);
        assert!(l[0].tareas.iter().all(|t| t.prioridad.is_none()));
    }

    #[test]
    fn la_marca_y_el_texto_que_se_manda() {
        assert_eq!(marca_de(Urgencia::MuyUrgente), Marca::MuyUrgente);
        assert_eq!(marca_de(Urgencia::Normal), Marca::Ninguna);
        let m = frase::marcas("llamar al banco 🔼 #casa 💬 cierran a las 3");
        assert_eq!(texto_para_jev(&m), "llamar al banco (cierran a las 3)");
    }

    #[test]
    fn lo_sabido_se_pone_y_lo_demas_se_pregunta() {
        let mut l = vec![lista(&["entregar el informe al jefe", "regar las plantas zz-prueba"])];
        let clave = clave_de("p", "Inbox", "entregar el informe al jefe");
        // Dano serio (3), otro la espera y el plazo es ajeno: 5 puntos.
        let escala = Escala {
            valor: 3.0,
            confianza: 0.9,
            niveles: vec![0.0, 0.0, 0.0, 1.0],
        };
        con_sabido(|s| {
            s.insert(
                clave,
                Sabido::Senales(Senales {
                    consecuencia: escala,
                    bloquea: 0.9,
                    plazo_ajeno: 0.9,
                    piden_ya: None,
                }),
            )
        });
        let faltan = poner_sabido(&mut l, 0);
        assert_eq!(l[0].tareas[0].prioridad.as_deref(), Some("urgente"));
        assert!(l[0].tareas[1].prioridad.is_none());
        assert_eq!(faltan.len(), 1);
        assert_eq!(faltan[0].2.tarea, "regar las plantas zz-prueba");
        assert_eq!(faltan[0].2.chat, "Mensajes guardados");
    }
}
