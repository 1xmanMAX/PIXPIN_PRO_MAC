//! **El iPhone/iPad como camara de la reunion que graba el PC** (1-nov-2026,
//! como Android v0.152.0: `CamaraDelPc.kt`, `ConexionDeCamara.kt`,
//! `RelojDeGrabacion.kt`; la guia es `docs/movil-como-camara.md` de Windows).
//!
//! El cable es el de Windows tal cual ([`pindesk_sincro::camara`]): aqui solo
//! esta lo que Swift necesita para hacer de movil:
//!
//! - [`Nucleo::preguntar_camara`]: `camara_remota` a un aparato del grupo
//!   (saluda diciendo `camara1`, pregunta, mide el desfase como NTP y se
//!   despide). Sin `camara1` en el otro, `None`: no graba nada que nos
//!   importe.
//! - [`Nucleo::mandar_fotos_a_la_grabacion`]: los `suelto` con `destino:
//!   "grabacion"`, varios en la misma conexion, cada uno con su `ms`,
//!   `tomada_en`, `reloj` y `clave` (la reanudacion de un corte la hace el
//!   cable, con `desdeByte`).
//! - [`siguiente_aviso_de_camara`]: **el aviso del PC** (al empezar,
//!   pausar, seguir o acabar) que atendio la [`crate::Escucha`] de este
//!   aparato; ya se le contesto con la hora de aqui.
//! - [`RelojDeCamara`]: **el reloj de la grabacion del PC llevado aqui** (el
//!   `RelojDelMovil` de Android, sobre el [`Reloj`] de Windows): lo que dijo
//!   el ultimo anuncio y lo que paso desde entonces en un reloj que solo
//!   avanza. Cada foto lleva el `ms` del disparo.

use std::sync::Mutex;

use pindesk_proyecto::vista::DiscoPc;
use pindesk_sincro::al_lienzo::{Conexion, ErrorAlLienzo};
use pindesk_sincro::camara::{self, Anuncio, Camara, FotoDeCamara, Reloj};
use pindesk_sincro::disco::Disco;
use pindesk_sincro::mensajes::{Aparato, Hola};

use crate::red::{conectar, nonce};
use crate::{ErrorNucleo, Nucleo};

/// Lo que se deja pasar entre el anuncio y el reloj de aqui antes de
/// corregirlo (`CamaraRemota.TOLERANCIA_MS` de Android).
pub const TOLERANCIA_MS: i64 = 250;
/// Lo mas que se cree de la «ida» de una pregunta (la mitad de la vuelta).
const IDA_MAXIMA: i64 = 5_000;

/// **Como va la grabacion de un PC** (el `Anuncio` de Windows, sin lo que
/// el iPad no usa).
#[derive(Debug, Clone, Default, PartialEq, Eq, uniffi::Record)]
pub struct AnuncioDeCamara {
    /// El id de la grabacion. Vacio: el PC no graba nada.
    pub grabacion: String,
    /// «Clase 27-10 10h05».
    pub titulo: String,
    /// El nombre del PC.
    pub aparato: String,
    /// Grabando (aunque sea en pausa). `false` con `grabacion`: ya acabo, y
    /// lo pendiente de esa grabacion aun entra.
    pub activa: bool,
    pub en_pausa: bool,
    /// En que milisegundo de la grabacion iba al escribirlo.
    pub ms_actual: i64,
    /// Lo que duro, cuando ya acabo.
    pub duracion: i64,
    /// El reloj del PC al escribirlo (0 si no lo dijo).
    pub reloj: i64,
    /// Los codecs de video que el PC sabe ver (vacio: solo fotos).
    pub codecs: Vec<String>,
}

impl AnuncioDeCamara {
    fn de(a: &Anuncio) -> AnuncioDeCamara {
        AnuncioDeCamara {
            grabacion: a.grabacion.clone(),
            titulo: a.titulo.clone(),
            aparato: a.aparato.clone(),
            activa: a.activa,
            en_pausa: a.en_pausa,
            ms_actual: a.ms_actual,
            duracion: a.duracion,
            reloj: a.reloj,
            codecs: a.codecs.clone(),
        }
    }
}

/// Si hay una grabacion a la que mandar fotos ahora mismo.
#[uniffi::export]
pub fn camara_grabando(anuncio: AnuncioDeCamara) -> bool {
    anuncio.activa && !anuncio.grabacion.is_empty()
}

/// **Lo que contesto un PC al preguntarle**, con lo medido de paso.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct RespuestaDeCamara {
    pub anuncio: AnuncioDeCamara,
    /// Lo que va adelantado el reloj de aqui sobre el del PC
    /// (`-desfase(t0, t1, t2)`): va en cada foto (`reloj`).
    pub adelanto: i64,
    /// La mitad de la vuelta: lo que hace que el PC escribio su anuncio.
    pub ida: i64,
    /// El PC, tal como se presento.
    pub pc_id: String,
    pub pc_nombre: String,
}

/// **El aviso de un PC** que atendio la escucha de este aparato.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AvisoDeCamara {
    pub anuncio: AnuncioDeCamara,
    pub pc_id: String,
    pub pc_nombre: String,
    /// La hora de aqui (ms desde 1970) al llegar: la que se le contesto.
    pub llego_en: i64,
}

/// **Una foto (o un clip) para la grabacion del PC**, ya en el disco.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FotoParaLaGrabacion {
    /// El fichero (JPEG, PNG, WebP o MP4: HEIC no).
    pub ruta: String,
    /// El nombre con que llega al PC (`IMG_20261101_100512.jpg`).
    pub nombre: String,
    /// La grabacion del PC (vacia: por su hora, `tomada_en`).
    pub grabacion: String,
    /// El minuto de la grabacion al disparar, calculado aqui.
    pub ms: Option<i64>,
    /// La hora de aqui al disparar (ms desde 1970).
    pub tomada_en: i64,
    /// Lo que va adelantado el reloj de aqui sobre el del PC.
    pub reloj: i64,
    /// Un clip: lo que dura (su `ms` es donde empezo). 0 una foto.
    pub duracion_ms: i64,
    /// El id de la toma, el mismo en cada intento.
    pub clave: String,
}

/// Como quedo cada foto mandada.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FotoSubida {
    pub clave: String,
    /// El minuto donde quedo en la grabacion; `None` si no entro.
    pub ms: Option<i64>,
    /// Por que no entro.
    pub error: Option<String>,
    /// **Un «no» para siempre** (la grabacion ya no esta, no es una foto,
    /// pesa demasiado, no cae en ninguna): no se vuelve a intentar. Lo
    /// demas (un corte, la camara apagada en el PC, ocupado) se reintenta.
    pub para_siempre: bool,
}

/// `CamaraRemota.esNoParaSiempre` de Android.
#[uniffi::export]
pub fn camara_es_no_para_siempre(error: String) -> bool {
    error.contains("ya no está en el PC")
        || error.starts_with("Solo se aceptan")
        || error.contains("demasiado grande")
        || error.contains("no dice de qué grabación")
        || error.contains("no cae en ninguna")
}

/// **El minuto como en el pie de las capturas del PC**: `12:34` o
/// `1:02:03`.
#[uniffi::export]
pub fn camara_minuto(ms: i64) -> String {
    let s = ms.max(0) / 1000;
    let (h, m, seg) = (s / 3600, (s / 60) % 60, s % 60);
    if h > 0 {
        format!("{h}:{m:02}:{seg:02}")
    } else {
        format!("{m}:{seg:02}")
    }
}

/// **Lo que ensena arriba la pantalla de la camara**: «● 12:34 grabando en
/// el PC», en pausa «‖ 12:34 en pausa», y al acabar «■ 12:34 · la grabación
/// del PC terminó» (`RelojDelMovil.rotulo` de Android).
#[uniffi::export]
pub fn camara_rotulo(ms: i64, en_pausa: bool, acabado: bool) -> String {
    let m = camara_minuto(ms);
    if acabado {
        format!("■ {m} · la grabación del PC terminó")
    } else if en_pausa {
        format!("‖ {m} en pausa")
    } else {
        format!("● {m} grabando en el PC")
    }
}

/// **El desfase entre dos relojes, como NTP** ([`camara::desfase`]): lo que
/// va adelantado el otro.
#[uniffi::export]
pub fn camara_desfase(t0: i64, t1: i64, t2: i64) -> i64 {
    camara::desfase(t0, t1, t2)
}

// ------------------------------------------------------------ el reloj

struct Estado {
    grabacion: String,
    reloj: Reloj,
}

/// **El reloj de la grabacion del PC, llevado aqui** (`RelojDelMovil` de
/// Android). `ahora` es siempre un reloj que solo avanza (en el iPhone,
/// `ProcessInfo.systemUptime` en ms; en las pruebas, el que se quiera).
#[derive(uniffi::Object)]
pub struct RelojDeCamara {
    estado: Mutex<Estado>,
}

/// El minuto que dice el anuncio, mas la ida si sigue corriendo.
fn ms_de(a: &AnuncioDeCamara, ida: i64) -> i64 {
    a.ms_actual
        + if a.activa && !a.en_pausa {
            ida.clamp(0, IDA_MAXIMA)
        } else {
            0
        }
}

fn reloj_de(a: &AnuncioDeCamara, ahora: i64, ida: i64) -> Reloj {
    if !a.activa {
        // Ya acabo: congelado en lo que duro.
        let mut r = Reloj::empezar(
            ahora,
            if a.duracion > 0 {
                a.duracion
            } else {
                a.ms_actual
            },
        );
        r.acabar(ahora);
        return r;
    }
    let mut r = Reloj::empezar(ahora, ms_de(a, ida));
    if a.en_pausa {
        r.pausar(ahora);
    }
    r
}

#[uniffi::export]
impl RelojDeCamara {
    /// El reloj de lo que dice `anuncio`, recibido en `ahora`.
    #[uniffi::constructor]
    pub fn nuevo(anuncio: AnuncioDeCamara, ahora: i64, ida: i64) -> std::sync::Arc<RelojDeCamara> {
        std::sync::Arc::new(RelojDeCamara {
            estado: Mutex::new(Estado {
                grabacion: anuncio.grabacion.clone(),
                reloj: reloj_de(&anuncio, ahora, ida),
            }),
        })
    }

    /// **Al dia con otro anuncio.** De otra grabacion, o acabada, empieza
    /// de nuevo; de la misma, se corrige sin saltos pequenos
    /// ([`TOLERANCIA_MS`]).
    pub fn al_dia(&self, anuncio: AnuncioDeCamara, ahora: i64, ida: i64) {
        let mut e = self.estado.lock().unwrap_or_else(|e| e.into_inner());
        if anuncio.grabacion != e.grabacion || !anuncio.activa || e.reloj.acabado() {
            *e = Estado {
                grabacion: anuncio.grabacion.clone(),
                reloj: reloj_de(&anuncio, ahora, ida),
            };
            return;
        }
        e.reloj
            .seguir_a(ahora, ms_de(&anuncio, ida), anuncio.en_pausa, TOLERANCIA_MS);
    }

    /// El milisegundo de la grabacion en `ahora`.
    pub fn ms(&self, ahora: i64) -> i64 {
        self.estado
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .reloj
            .ms_en(ahora)
    }

    pub fn grabacion(&self) -> String {
        self.estado
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .grabacion
            .clone()
    }

    pub fn en_pausa(&self) -> bool {
        self.estado
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .reloj
            .en_pausa()
    }

    pub fn acabado(&self) -> bool {
        self.estado
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .reloj
            .acabado()
    }
}

// ------------------------------------------------------------ el aviso

/// Los avisos de los PC que aun no ha leido Swift (los ultimos, sin pasar
/// de unos pocos: solo importa el ultimo de cada PC).
static AVISOS: Mutex<Vec<AvisoDeCamara>> = Mutex::new(Vec::new());
const AVISOS_GUARDADOS: usize = 16;

fn apuntar_aviso(a: AvisoDeCamara) {
    let mut v = AVISOS.lock().unwrap_or_else(|e| e.into_inner());
    v.retain(|x| x.pc_id != a.pc_id);
    v.push(a);
    if v.len() > AVISOS_GUARDADOS {
        let sobra = v.len() - AVISOS_GUARDADOS;
        v.drain(..sobra);
    }
}

/// **El siguiente aviso de un PC** que llego por la escucha (el mas viejo
/// primero), o `None`. Swift lo pregunta tras cada conexion atendida.
#[uniffi::export]
pub fn siguiente_aviso_de_camara() -> Option<AvisoDeCamara> {
    let mut v = AVISOS.lock().unwrap_or_else(|e| e.into_inner());
    if v.is_empty() {
        None
    } else {
        Some(v.remove(0))
    }
}

/// **Quien atiende la camara en este aparato** cuando llama un PC: no graba
/// nada que ofrecer (contesta «no grabo» con la hora de aqui) y apunta su
/// aviso para Swift.
#[derive(Default)]
pub(crate) struct CamaraDeEsteAparato;

impl Camara for CamaraDeEsteAparato {
    fn anuncio(&mut self) -> Option<Anuncio> {
        None
    }

    fn aceptar_foto(&mut self, _p: &pindesk_sincro::al_lienzo::Suelto) -> Result<(), String> {
        // Este aparato no graba para que otro le mande capturas (aun).
        Err("Este aparato no está grabando".into())
    }

    fn guardar_foto(
        &mut self,
        _p: &pindesk_sincro::al_lienzo::Suelto,
        _fichero: &std::path::Path,
    ) -> Result<i64, String> {
        Err("Este aparato no está grabando".into())
    }

    fn aviso(&mut self, de: &Aparato, anuncio: &Anuncio, llego_en: i64) {
        apuntar_aviso(AvisoDeCamara {
            anuncio: AnuncioDeCamara::de(anuncio),
            pc_id: de.id.clone(),
            pc_nombre: de.nombre.clone(),
            llego_en,
        });
    }
}

// ------------------------------------------------------------ preguntar y mandar

fn error_de(e: ErrorAlLienzo, host: &str) -> ErrorNucleo {
    ErrorNucleo::Sincro {
        detalle: if e.es_codigo_distinto() {
            format!("{host} no aceptó la conexión: ¿tiene el mismo código de grupo?")
        } else {
            e.to_string()
        },
    }
}

impl Nucleo {
    /// Saluda a `host:puerto` diciendo que sabe hacer de camara.
    fn abrir_camara(
        &self,
        host: &str,
        puerto: u16,
    ) -> Result<Conexion<std::net::TcpStream>, ErrorNucleo> {
        let i = DiscoPc::nuevo(self.ruta()).identidad()?;
        let codigo = i.codigo.clone().ok_or_else(|| ErrorNucleo::Argumento {
            detalle: "este aparato no esta en un grupo".into(),
        })?;
        let flujo = conectar(host, puerto)?;
        let hola = Hola {
            yo: i.yo.clone(),
            reloj: crate::ahora_ms(),
            puerto: self.mi_puerto(),
            capacidades: pindesk_sincro::CAPACIDADES_DEL_IPAD
                .iter()
                .map(|c| c.to_string())
                .collect(),
            ..Default::default()
        };
        Conexion::abrir(flujo, &codigo, nonce()?, hola).map_err(|e| error_de(e, host))
    }
}

#[uniffi::export]
impl Nucleo {
    /// **Pregunta a un aparato del grupo como va su grabacion**
    /// (`camara_remota`, §2.1 de la guia) y mide de paso el desfase de los
    /// relojes. `None` si el otro no sabe de la camara (`camara1`): un
    /// telefono, otro iPad o un PixPin de antes. Apunta donde escucha.
    /// Bloquea (red): desde una `Task` fuera del hilo principal.
    pub fn preguntar_camara(
        &self,
        host: String,
        puerto: u16,
    ) -> Result<Option<RespuestaDeCamara>, ErrorNucleo> {
        let mut c = self.abrir_camara(&host, puerto)?;
        if c.puerto_del_otro > 0 {
            let _ = crate::aparatos::apuntar_direccion(
                self.ruta(),
                &c.otro.id,
                &host,
                u16::try_from(c.puerto_del_otro).unwrap_or(puerto),
            );
        }
        if !c.sabe_de_camara() {
            c.adios();
            return Ok(None);
        }
        let t0 = crate::ahora_ms();
        let r = c.preguntar_camara(&crate::ahora_ms);
        let t2 = crate::ahora_ms();
        let (otro_id, otro_nombre) = (c.otro.id.clone(), c.otro.nombre.clone());
        match r {
            Ok((anuncio, adelanto)) => {
                c.adios();
                Ok(Some(RespuestaDeCamara {
                    anuncio: AnuncioDeCamara::de(&anuncio),
                    adelanto,
                    ida: ((t2 - t0) / 2).max(0),
                    pc_id: otro_id,
                    pc_nombre: otro_nombre,
                }))
            }
            // Un «No sé qué es» deja la conexion sana: no graba para nadie.
            Err(ErrorAlLienzo::MovilSinSoporte | ErrorAlLienzo::Remoto(_)) => {
                c.adios();
                Ok(None)
            }
            Err(e) => Err(error_de(e, &host)),
        }
    }

    /// **Manda fotos (o clips) a la grabacion de un PC**, una detras de otra
    /// en la misma conexion. Devuelve como quedo cada una: un «no» del PC
    /// antes del «vale» no corta las demas; si se corta la red, las que
    /// faltan salen con su error (para reintentar). Falla entera solo si no
    /// se pudo ni saludar, o si el PC no sabe de la camara.
    pub fn mandar_fotos_a_la_grabacion(
        &self,
        host: String,
        puerto: u16,
        fotos: Vec<FotoParaLaGrabacion>,
    ) -> Result<Vec<FotoSubida>, ErrorNucleo> {
        let mut c = self.abrir_camara(&host, puerto)?;
        if !c.sabe_de_camara() {
            c.adios();
            return Err(ErrorNucleo::Sincro {
                detalle: "El PC no sabe de la cámara del móvil: actualiza PixPin en el PC".into(),
            });
        }
        let mut salida = Vec::with_capacity(fotos.len());
        let mut cortado: Option<String> = None;
        for f in fotos {
            if let Some(e) = &cortado {
                salida.push(FotoSubida {
                    clave: f.clave,
                    ms: None,
                    error: Some(e.clone()),
                    para_siempre: false,
                });
                continue;
            }
            let ruta = std::path::PathBuf::from(&f.ruta);
            if !ruta.is_file() {
                salida.push(FotoSubida {
                    clave: f.clave,
                    ms: None,
                    error: Some(format!("«{}» ya no está en este aparato", f.nombre)),
                    para_siempre: true,
                });
                continue;
            }
            let foto = FotoDeCamara {
                grabacion: f.grabacion.clone(),
                // Por su hora (§12.4): sin grabacion, sin `ms`.
                ms: if f.grabacion.is_empty() { None } else { f.ms },
                tomada_en: f.tomada_en,
                reloj: f.reloj,
                duracion_ms: f.duracion_ms,
                clave: f.clave.clone(),
            };
            match c.mandar_foto(&ruta, &f.nombre, &foto) {
                Ok(ms) => salida.push(FotoSubida {
                    clave: f.clave,
                    ms: Some(ms),
                    error: None,
                    para_siempre: false,
                }),
                Err(e) => {
                    // Estos dejan la conexion sana: no salio ningun trozo.
                    let sana = matches!(
                        e,
                        ErrorAlLienzo::SoloFotos
                            | ErrorAlLienzo::MovilSinSoporte
                            | ErrorAlLienzo::Ocupado
                            | ErrorAlLienzo::Remoto(_)
                    );
                    let texto = e.to_string();
                    if !sana {
                        cortado = Some(texto.clone());
                    }
                    salida.push(FotoSubida {
                        clave: f.clave,
                        ms: None,
                        para_siempre: sana && camara_es_no_para_siempre(texto.clone()),
                        error: Some(texto),
                    });
                }
            }
        }
        if cortado.is_none() {
            c.adios();
        }
        Ok(salida)
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn anuncio(grabacion: &str, activa: bool, pausa: bool, ms: i64) -> AnuncioDeCamara {
        AnuncioDeCamara {
            grabacion: grabacion.into(),
            activa,
            en_pausa: pausa,
            ms_actual: ms,
            ..Default::default()
        }
    }

    #[test]
    fn el_reloj_corre_desde_el_anuncio_y_se_congela_en_pausa() {
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, false, 754_000), 1_000, 0);
        assert_eq!(r.ms(1_000), 754_000);
        assert_eq!(r.ms(11_000), 764_000);
        // El PC pausa a los 10 s: congelado.
        r.al_dia(anuncio("g-1", true, true, 764_000), 11_000, 0);
        assert!(r.en_pausa());
        assert_eq!(r.ms(41_000), 764_000);
        // Sigue: corre otra vez desde donde se paro.
        r.al_dia(anuncio("g-1", true, false, 764_000), 41_000, 0);
        assert_eq!(r.ms(46_000), 769_000);
    }

    #[test]
    fn la_ida_cuenta_solo_corriendo_y_con_tope() {
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, false, 10_000), 0, 40);
        assert_eq!(r.ms(0), 10_040);
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, true, 10_000), 0, 40);
        assert_eq!(r.ms(0), 10_000);
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, false, 0), 0, 60_000);
        assert_eq!(r.ms(0), IDA_MAXIMA);
    }

    #[test]
    fn una_deriva_pequena_no_mueve_el_minuto_y_una_grande_si() {
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, false, 0), 0, 0);
        r.al_dia(anuncio("g-1", true, false, 10_200), 10_000, 0);
        assert_eq!(r.ms(10_000), 10_000);
        r.al_dia(anuncio("g-1", true, false, 12_000), 10_000, 0);
        assert_eq!(r.ms(10_000), 12_000);
    }

    #[test]
    fn otra_grabacion_o_el_final_empiezan_de_nuevo() {
        let r = RelojDeCamara::nuevo(anuncio("g-1", true, false, 5_000), 0, 0);
        r.al_dia(anuncio("g-2", true, false, 1_000), 3_000, 0);
        assert_eq!(r.grabacion(), "g-2");
        assert_eq!(r.ms(3_000), 1_000);
        // Acabo: lo que duro, congelado.
        let fin = AnuncioDeCamara {
            duracion: 90_000,
            ..anuncio("g-2", false, false, 0)
        };
        r.al_dia(fin, 4_000, 0);
        assert!(r.acabado());
        assert_eq!(r.ms(100_000), 90_000);
    }

    #[test]
    fn el_minuto_y_el_rotulo_como_android() {
        assert_eq!(camara_minuto(754_000), "12:34");
        assert_eq!(camara_minuto(3_723_000), "1:02:03");
        assert_eq!(camara_minuto(-5), "0:00");
        assert_eq!(
            camara_rotulo(754_000, false, false),
            "● 12:34 grabando en el PC"
        );
        assert_eq!(camara_rotulo(754_000, true, false), "‖ 12:34 en pausa");
        assert_eq!(
            camara_rotulo(754_000, false, true),
            "■ 12:34 · la grabación del PC terminó"
        );
    }

    #[test]
    fn el_desfase_y_lo_que_no_se_reintenta() {
        // El otro va 7 s adelantado; la vuelta tarda 100 ms.
        assert_eq!(camara_desfase(1_000, 8_050, 1_100), 7_000);
        assert!(camara_es_no_para_siempre(
            "Solo se aceptan fotos (JPEG, PNG o WebP) y clips MP4".into()
        ));
        assert!(camara_es_no_para_siempre(
            "La foto no cae en ninguna grabación de este equipo".into()
        ));
        assert!(!camara_es_no_para_siempre(
            "Está sincronizando con otro aparato".into()
        ));
    }

    #[test]
    fn el_aviso_del_pc_se_apunta_uno_por_pc() {
        let pc = Aparato {
            id: "pc-prueba-aviso".into(),
            nombre: "PORTATIL".into(),
            ..Default::default()
        };
        let mut c = CamaraDeEsteAparato;
        let a = Anuncio {
            grabacion: "g-1".into(),
            activa: true,
            ..Anuncio::nada()
        };
        c.aviso(&pc, &a, 10);
        c.aviso(&pc, &Anuncio { ms_actual: 5, ..a }, 20);
        let mut mios = Vec::new();
        while let Some(x) = siguiente_aviso_de_camara() {
            if x.pc_id == pc.id {
                mios.push(x);
            }
        }
        assert_eq!(mios.len(), 1);
        assert_eq!(mios[0].llego_en, 20);
        assert_eq!(mios[0].anuncio.ms_actual, 5);
        assert!(camara_grabando(mios[0].anuncio.clone()));
    }
}
