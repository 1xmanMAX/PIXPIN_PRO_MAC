//! **La prioridad de cada tarea segun su contexto** (Windows fa4ca12,
//! `apps/pixpin/src/jev/urgencia.rs`): por cada tarea pendiente, Jev juzga
//! lo que pasa si se hace tarde, si otro la espera, si el plazo lo puso otro
//! y si en su chat la piden ya (`pindesk_typesafe::urgencia`); cuanto falta
//! para su hora (`⏰` o, si no tiene, la fecha del titulo de su lista:
//! «HOY SÁBADO», Windows 4fe2730) lo cuenta el codigo, y la tabla de alli da
//! urgente, alta, normal o baja. Lo que el usuario marco (⏫, 🔼) manda. Con
//! la prioridad va su porque ([`MotivoJev`], la pista de la chapita).
//!
//! **Las listas de temas de una reunion** (las que una nota de voz enlaza en
//! `temasLista`) no se preguntan: son puntos de una agenda, no tareas.
//!
//! Va en segundo plano: al leer las listas ([`aplicar`], desde
//! `Nucleo::tareas_con_jev`) se pone lo ya sabido y se pregunta por lo que falta en
//! un hilo; Swift relee mientras [`jev_preguntando_tareas`] diga que si.
//!
//! **La revision viaja** (Windows c3b09df6, Android): lo que dijo Jev de cada
//! tarea se guarda junto a su lista, en `pins/draw/anot-<uid>.urgencia.json`
//! del chat (`pindesk_sincro::urgencias`), y se sincroniza con los demas
//! aparatos. Antes de preguntar se mira ahi: lo que ya reviso este Mac, el
//! PC o el movil no se vuelve a preguntar.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use pindesk_proyecto::{almacen, cuaderno};
use pindesk_sincro::disco::Disco;
use pindesk_sincro::urgencias::{self as guardadas, Guardada};
use pindesk_typesafe::urgencia::{self as ju, Contexto, Marca, Prioridad, Senales};

use super::Funcion;
use crate::tareas::ListaTareas;
use crate::{ErrorNucleo, Nucleo};
use crate::tareas::frase::{self, Urgencia};

enum Sabido {
    Senales(Senales),
    Fallo(Instant),
    /// Un tema de una reunion: sin prioridad.
    Tema,
}

/// **El porque de la prioridad de Jev** (`pindesk_typesafe::urgencia::Motivo`).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MotivoJev {
    /// El nivel de la consecuencia (0 nada … 3 grave).
    pub consecuencia: u8,
    /// Otro la espera.
    pub espera: bool,
    /// El plazo lo puso otro.
    pub plazo_ajeno: bool,
    /// La piden en el chat.
    pub piden_ya: bool,
    /// Los dias que faltan (negativo: ya paso).
    pub dias: Option<i64>,
    /// Si esos dias salen del titulo de la lista y no de la tarea.
    pub de_la_lista: bool,
}

impl From<ju::Motivo> for MotivoJev {
    fn from(m: ju::Motivo) -> Self {
        MotivoJev {
            consecuencia: m.consecuencia,
            espera: m.espera,
            plazo_ajeno: m.plazo_ajeno,
            piden_ya: m.piden_ya,
            dias: m.dias,
            de_la_lista: m.de_la_lista,
        }
    }
}

/// **La pista de la chapita de Jev**: el porque de su prioridad en una linea
/// («Jev: consecuencia media · nadie la espera · sin fecha»), como
/// `tareas/chapitas.rs::pista_de_jev` de Windows.
#[uniffi::export]
pub fn pista_de_jev(motivo: MotivoJev, locale: String) -> String {
    let t = super::catalogo(&locale);
    let m = motivo;
    let consecuencia = match m.consecuencia {
        0 => "tareas-jev-consecuencia-nada",
        1 => "tareas-jev-consecuencia-leve",
        2 => "tareas-jev-consecuencia-media",
        _ => "tareas-jev-consecuencia-grave",
    };
    let mut partes = vec![t.t(consecuencia)];
    partes.push(t.t(if m.espera { "tareas-jev-la-esperan" } else { "tareas-jev-nadie-espera" }));
    if m.plazo_ajeno {
        partes.push(t.t("tareas-jev-plazo-ajeno"));
    }
    if m.piden_ya {
        partes.push(t.t("tareas-jev-la-piden"));
    }
    let cuando = match m.dias {
        None => t.t("tareas-jev-sin-fecha"),
        Some(d) if d < 0 => t.t("tareas-jev-ya-paso"),
        Some(0) => t.t("tareas-jev-hoy"),
        Some(1) => t.t("tareas-jev-manana"),
        Some(d) => {
            let mut a = fluent_bundle::FluentArgs::new();
            a.set("n", d);
            t.t_args("tareas-jev-en-dias", &a)
        }
    };
    partes.push(if m.de_la_lista {
        let mut a = fluent_bundle::FluentArgs::new();
        a.set("cuando", cuando);
        t.t_args("tareas-jev-por-la-lista", &a)
    } else {
        cuando
    });
    format!("Jev: {}", partes.join(" · "))
}

/// Una tarea por preguntar.
struct Falta {
    clave: String,
    chat: String,
    /// El id del mensaje de su lista.
    mensaje: String,
    /// Lo que se manda (`tarea` es tambien la clave en el fichero).
    contexto: Contexto,
    /// El fichero de la revision de su lista, si la lista es un mensaje del
    /// cuaderno de un chat del almacen.
    fichero: Option<PathBuf>,
}

/// Las senales de una tarea guardada en el fichero de su lista.
fn senales_de(g: &Guardada) -> Senales {
    Senales::de_partes(
        g.consecuencia.clone(),
        g.confianza,
        g.bloquea,
        g.plazo_ajeno,
        g.piden_ya,
    )
}

/// Lo que se guarda de lo que dijo Jev: cuando y en que aparato.
fn guardada_de(s: &Senales, cuando: i64, aparato: &str) -> Guardada {
    Guardada {
        consecuencia: s.consecuencia.niveles.clone(),
        confianza: s.consecuencia.confianza,
        bloquea: s.bloquea,
        plazo_ajeno: s.plazo_ajeno,
        piden_ya: s.piden_ya,
        cuando,
        aparato: aparato.to_string(),
    }
}

/// **Lo que ya se reviso de las listas, leido del disco una vez por
/// tanda**: el fichero de cada lista y lo que tiene, por su codigo unico.
struct DelDisco<'a> {
    raiz: &'a Path,
    /// El chat (`DiscoPc`) de cada ficha.
    chats: HashMap<String, Option<String>>,
    listas: HashMap<String, (Option<PathBuf>, guardadas::Tareas)>,
}

impl<'a> DelDisco<'a> {
    fn nuevo(raiz: &'a Path) -> DelDisco<'a> {
        DelDisco {
            raiz,
            chats: HashMap::new(),
            listas: HashMap::new(),
        }
    }

    fn de(&mut self, l: &ListaTareas) -> Option<&(Option<PathBuf>, guardadas::Tareas)> {
        let uid = l.uid.as_deref()?;
        if !self.listas.contains_key(uid) {
            let raiz = self.raiz;
            let chat = self
                .chats
                .entry(l.chat.clone())
                .or_insert_with(|| pindesk_proyecto::vista::chat_de_ficha(raiz, &l.chat))
                .clone();
            let fichero = chat.map(|c| {
                pindesk_proyecto::vista::DiscoPc::nuevo(raiz)
                    .ruta(&c, &pindesk_proyecto::anotado::urgencia_rel(uid))
            });
            let dentro = fichero.as_deref().map(guardadas::leer).unwrap_or_default();
            self.listas.insert(uid.to_string(), (fichero, dentro));
        }
        self.listas.get(uid)
    }
}

/// El codigo de este Mac, el que va en `aparato` de lo que se pregunta aqui.
fn yo(raiz: &Path) -> String {
    pindesk_proyecto::identidad::Identidad::leer_o_crear(raiz, "Mac")
        .map(|i| i.yo.codigo())
        .unwrap_or_default()
}

/// Los dias que faltan para la fecha del titulo de la lista (dicha el dia en
/// que se creo, `cuando` en ms UTC), contados desde `hoy` (dia local).
fn dias_de_la_lista(l: &ListaTareas, hoy: i64, desfase_ms: i64) -> Option<i64> {
    use pindesk_typesafe::fechas::Fecha;
    let creada = (l.cuando + desfase_ms).div_euclid(86_400_000);
    ju::dias_de_la_lista(&l.titulo, Fecha::de_dias(creada), Fecha::de_dias(hoy))
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
    let faltan = poner_sabido(listas, hoy, desfase_ms, &mut DelDisco::nuevo(raiz));
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

/// Lo sabido, puesto; devuelve lo que falta preguntar.
fn poner_sabido(
    listas: &mut [ListaTareas],
    hoy: i64,
    desfase_ms: i64,
    disco: &mut DelDisco,
) -> Vec<Falta> {
    let mut faltan = Vec::new();
    for l in listas.iter_mut() {
        let dias_lista = dias_de_la_lista(l, hoy, desfase_ms);
        let lista = l.clone();
        let (chat, titulo, nombre) = (l.chat.clone(), l.titulo.clone(), l.nombre_chat.clone());
        let mensaje = l.mensaje.clone();
        for t in l.tareas.iter_mut().filter(|t| !t.hecha) {
            let m = frase::marcas(&t.texto);
            let texto = texto_para_jev(&m);
            if texto.is_empty() {
                continue;
            }
            let dias = m.hora.map(|h| h.dia - hoy).or(dias_lista);
            let clave = clave_de(&chat, &titulo, &texto);
            let mut sabido = con_sabido(|s| match s.get(&clave) {
                Some(Sabido::Senales(x)) => Some(Some(x.clone())),
                Some(Sabido::Fallo(t)) if t.elapsed() < TRAS_UN_FALLO => Some(None),
                Some(Sabido::Tema) => Some(None),
                _ => None,
            });
            // Lo que ya reviso este u otro aparato, del disco: no se
            // pregunta otra vez (aunque aqui hubiera fallado hace poco).
            if !matches!(sabido, Some(Some(_)))
                && let Some(g) = disco.de(&lista).and_then(|(_, d)| d.get(&texto))
            {
                let s = senales_de(g);
                con_sabido(|m| m.insert(clave.clone(), Sabido::Senales(s.clone())));
                sabido = Some(Some(s));
            }
            match sabido {
                Some(Some(s)) => {
                    let marca = marca_de(m.urgencia);
                    t.prioridad = Some(id_de(ju::decidir(marca, Some(&s), dias)));
                    t.motivo_jev = (marca == Marca::Ninguna)
                        .then(|| ju::Motivo::de(&s, dias, m.hora.is_none()).into());
                }
                // Fallo reciente o tema de reunion: lo de siempre.
                Some(None) => {}
                None => faltan.push(Falta {
                    clave,
                    chat: chat.clone(),
                    mensaje: mensaje.clone(),
                    contexto: Contexto {
                        tarea: texto,
                        lista: titulo.clone(),
                        chat: nombre.clone(),
                        recientes: Vec::new(),
                    },
                    fichero: disco.de(&lista).and_then(|(f, _)| f.clone()),
                }),
            }
        }
    }
    faltan
}

fn preguntar(cliente: &pindesk_typesafe::Cliente, raiz: &Path, faltan: Vec<Falta>) {
    let mut chats: HashMap<String, Chat> = HashMap::new();
    let mut temas = Vec::new();
    let faltan: Vec<Falta> = faltan
        .into_iter()
        .filter_map(|mut f| {
            let leido = chats.entry(f.chat.clone()).or_insert_with(|| leer_chat(raiz, &f.chat));
            if leido.temas.contains(&(f.chat.clone(), f.mensaje.clone())) {
                temas.push(f.clave);
                return None;
            }
            f.contexto.recientes = leido.recientes.clone();
            Some(f)
        })
        .collect();
    con_sabido(|s| {
        for clave in temas {
            s.insert(clave, Sabido::Tema);
        }
    });
    let contextos: Vec<Contexto> = faltan.iter().map(|f| f.contexto.clone()).collect();
    let respuestas = ju::preguntar_varias(cliente, &contextos, A_LA_VEZ);
    // Lo dicho, por lista: a su fichero, para que ningun aparato lo vuelva
    // a preguntar.
    let ahora = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64);
    let aparato = yo(raiz);
    let mut a_guardar: HashMap<PathBuf, guardadas::Tareas> = HashMap::new();
    con_sabido(|s| {
        for (f, r) in faltan.into_iter().zip(respuestas) {
            match r {
                Ok(x) => {
                    if let Some(fichero) = f.fichero {
                        a_guardar
                            .entry(fichero)
                            .or_default()
                            .insert(f.contexto.tarea, guardada_de(&x, ahora, &aparato));
                    }
                    s.insert(f.clave, Sabido::Senales(x));
                }
                Err(_) => {
                    s.insert(f.clave, Sabido::Fallo(Instant::now()));
                }
            }
        }
    });
    for (fichero, nuevas) in a_guardar {
        let _ = guardadas::anadir(&fichero, &nuevas);
    }
}

/// Lo que se lee de un chat para sus tareas.
#[derive(Default)]
struct Chat {
    /// Los ultimos mensajes escritos (notas con texto, no las listas de
    /// tareas), del mas viejo al mas nuevo.
    recientes: Vec<String>,
    /// Las listas de temas de sus reuniones, `(chat, mensaje)`.
    temas: Vec<(String, String)>,
}

fn leer_chat(raiz: &Path, chat: &str) -> Chat {
    let Ok(c) = cuaderno::Cuaderno::leer_de(&almacen::carpeta(raiz, chat)) else {
        return Chat::default();
    };
    Chat {
        recientes: recientes_de(&c),
        temas: c
            .mensajes
            .iter()
            .filter_map(|m| pindesk_proyecto::temas::lista_de(&m.resto))
            .collect(),
    }
}

fn recientes_de(c: &cuaderno::Cuaderno) -> Vec<String> {
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
                    motivo_jev: None,
                })
                .collect(),
            pendientes: textos.len() as u32,
            asignatura: None,
            uid: None,
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
        let raiz = std::env::temp_dir();
        let faltan = poner_sabido(&mut l, 0, 0, &mut DelDisco::nuevo(&raiz));
        assert_eq!(l[0].tareas[0].prioridad.as_deref(), Some("urgente"));
        assert!(l[0].tareas[1].prioridad.is_none());
        assert_eq!(faltan.len(), 1);
        assert_eq!(faltan[0].contexto.tarea, "regar las plantas zz-prueba");
        assert_eq!(faltan[0].contexto.chat, "Mensajes guardados");
        // Sin marca del usuario, con su porque.
        let m = l[0].tareas[0].motivo_jev.clone().unwrap();
        assert_eq!((m.consecuencia, m.espera, m.plazo_ajeno, m.dias), (3, true, true, None));
    }

    /// **Lo que ya reviso otro aparato se lee del fichero de su lista**, el
    /// mismo que viaja: no se vuelve a preguntar (Windows c3b09df6).
    #[test]
    fn el_fichero_de_la_lista_es_el_que_viaja_y_se_lee() {
        let raiz =
            std::env::temp_dir().join(format!("pindesk-mac-jev-urgencia-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&raiz);
        let g = almacen::asegurar_guardados(&raiz, 1, "K7Q2").unwrap();
        let f =
            pindesk_proyecto::anotado::urgencia_de_la_lista(&raiz, &g.id, "ABCDE23456").unwrap();
        let s = Senales::de_partes(vec![0.0, 0.0, 1.0], 0.6, 0.1, 0.0, None);
        let tareas = guardadas::Tareas::from([("pan".to_string(), guardada_de(&s, 5, "MOVI"))]);
        assert!(guardadas::anadir(&f, &tareas).unwrap());
        let con = |chat: &str, uid: Option<&str>| ListaTareas {
            chat: chat.into(),
            uid: uid.map(str::to_string),
            ..lista(&["pan", "leche zz-prueba"])
        };
        let mut disco = DelDisco::nuevo(&raiz);
        let (fichero, dentro) = disco.de(&con(&g.id, Some("ABCDE23456"))).unwrap();
        assert_eq!(fichero.as_deref(), Some(f.as_path()));
        assert_eq!(dentro.get("pan").map(senales_de), Some(s));
        // Lo del fichero se pone; solo se pregunta lo que no esta, y su
        // respuesta ira al mismo fichero.
        let mut l = vec![con(&g.id, Some("ABCDE23456"))];
        let faltan = poner_sabido(&mut l, 0, 0, &mut DelDisco::nuevo(&raiz));
        assert!(l[0].tareas[0].prioridad.is_some());
        assert_eq!(faltan.len(), 1);
        assert_eq!(faltan[0].contexto.tarea, "leche zz-prueba");
        assert_eq!(faltan[0].fichero.as_deref(), Some(f.as_path()));
        // Casos negativos: sin codigo no hay fichero, y de un chat que no
        // esta en el almacen tampoco.
        assert!(disco.de(&con(&g.id, None)).is_none());
        let (fichero, dentro) = disco.de(&con("no-esta", Some("ZZZZZ23456"))).unwrap();
        assert!(fichero.is_none() && dentro.is_empty());
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn lo_dicho_se_guarda_con_cuando_y_donde() {
        let s = Senales::de_partes(vec![0.0, 1.0], 0.8, 0.5, 0.2, Some(0.3));
        let g = guardada_de(&s, 1_793_582_613_265, "K7Q2");
        assert_eq!((g.cuando, g.aparato.as_str()), (1_793_582_613_265, "K7Q2"));
        assert_eq!(senales_de(&g), s);
    }

    #[test]
    fn la_pista_dice_el_porque_como_windows() {
        let m = MotivoJev {
            consecuencia: 2,
            espera: false,
            plazo_ajeno: false,
            piden_ya: false,
            dias: None,
            de_la_lista: false,
        };
        assert_eq!(
            pista_de_jev(m.clone(), "es-ES".into()),
            "Jev: consecuencia media · nadie la espera · sin fecha"
        );
        let m = MotivoJev {
            consecuencia: 3,
            espera: true,
            plazo_ajeno: true,
            dias: Some(0),
            de_la_lista: true,
            ..m
        };
        assert_eq!(
            pista_de_jev(m, "es-ES".into()),
            "Jev: consecuencia grave · alguien la espera · plazo de otro · hoy (por el título de la lista)"
        );
        assert_eq!(super::super::textos_de_jev("es-ES".into()).prioridad_normal, "Normal");
    }

    #[test]
    fn la_fecha_del_titulo_de_la_lista_cuenta() {
        // «Hoy» dicho el dia en que se creo la lista, mirado ese mismo dia.
        let mut l = lista(&["x"]);
        l.titulo = "Hoy".into();
        l.cuando = 20_000 * 86_400_000;
        assert_eq!(dias_de_la_lista(&l, 20_000, 0), Some(0));
        assert_eq!(dias_de_la_lista(&l, 20_002, 0), Some(-2));
        l.titulo = "Inbox".into();
        assert_eq!(dias_de_la_lista(&l, 20_000, 0), None);
    }
}
