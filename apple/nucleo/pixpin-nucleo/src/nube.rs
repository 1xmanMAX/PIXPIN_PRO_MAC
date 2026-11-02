//! **La nube de los chats compartidos, en el Mac** (Windows c5c94e4,
//! 1-nov-2026, `docs/nube.md` de Windows): `sincronizar/nube.rs` de Windows
//! sin la ventana.
//!
//! Lo de dentro —el protocolo, los deltas de trazos, juntar, «Sin
//! conexión»— es `pindesk_sincro::nube`, el mismo crate que Windows, probado
//! alli (tambien contra la nube de referencia). Aqui:
//!
//! - **Los ajustes**: la direccion de la web en `sincro/nube/ajustes.json`
//!   (el mismo fichero que Windows; `sincro/` no viaja) y la llave `pxn_…`
//!   del aparato **en el Llavero del Mac** ([`SERVICIO`], por el
//!   [`crate::llavero::LlaveroApp`] de Swift), nunca en `pixpinmax.toml` ni
//!   en un registro. Sin Llavero no se guarda.
//! - **La red**: el HTTPS de la app (URLSession desde Swift, el mismo
//!   `TransporteApp` del asistente y de Jev, [`PorLaApp`]); `http://` solo
//!   hacia `127.0.0.1`/`localhost` (`pindesk_ia::nube::http::partir`).
//! - **Los hilos de la nube** ([`Nucleo::arrancar_nube`]), los de Windows:
//!   uno mira cada 3 s la firma barata de la carpeta de cada chat de la nube
//!   y, cuando lleva 4 s quieta, hace una vuelta (solo lo cambiado); otro
//!   espera las novedades con la conexion abierta (`novedades?espera=25`) y
//!   despierta al primero. Sin red, espera creciente (`reintentos`). Nada de
//!   esto corre en el hilo principal: son hilos de Rust.
//! - **Lo que ve la ventana**: el modo (Red local / Nube) de cada chat
//!   compartido (`sincro/nube/chats.json`, **no** `compartidos.json`, que es
//!   byte a byte el de Android) y el estado de cada uno para la nubecita de
//!   la lista ([`Nucleo::estados_de_la_nube`]).
//! - **«En línea / Sin conexión»** de los visores ([`SitioNube`]).

use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

use pindesk_ia::nube::http::{self, Fallo};
use pindesk_proyecto::vista::DiscoPc;
use pindesk_sincro::compartidos::CompartidosEnDisco;
use pindesk_sincro::nube::cliente::{Contestado, FalloNube, Nube, Transporte};
use pindesk_sincro::nube::estado::{self, ChatsEnLaNube, EstadoDeChat, Modo};
use pindesk_sincro::nube::sin_conexion::SinConexion;
use pindesk_sincro::nube::tipos::Hola;
use pindesk_sincro::nube::vuelta::{self, Opciones};
use pindesk_sincro::reintentos;
use serde::{Deserialize, Serialize};

use crate::llavero::LlaveroApp;
use crate::{ErrorNucleo, Nucleo};

/// El servicio del Llavero donde vive la llave `pxn_…` de este aparato (en
/// Windows, `nube.clave` cifrada con DPAPI junto a las de la IA).
pub const SERVICIO: &str = "PixPinMax.nube";
/// La cuenta dentro del servicio.
const CUENTA: &str = "llave";
/// Cada cuanto se mira si cambio algo en un chat de la nube.
const MIRAR_CADA: Duration = Duration::from_secs(3);
/// Cuanto tiene que llevar quieto un chat para subirlo (juntar cambios).
const QUIETO: Duration = Duration::from_secs(4);
/// Cada cuanto se baja aunque no llegue ninguna novedad.
const BAJAR_CADA: Duration = Duration::from_secs(10 * 60);
/// Cuanto espera la nube con la conexion abierta antes de contestar.
const ESPERA_NOVEDADES: u64 = 25;
/// Lo mas que se baja de una vez (los topes de la nube: 512 MB un objeto).
const LIMITE: usize = 600 * 1024 * 1024;

// ------------------------------------------------------------------ tipos

/// Por donde va un chat compartido.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ModoNube {
    /// La red local (mDNS), lo de siempre.
    Local,
    /// La nube: sube y baja desde donde estes (y tambien la red local).
    Nube,
}

impl From<Modo> for ModoNube {
    fn from(m: Modo) -> Self {
        match m {
            Modo::Local => ModoNube::Local,
            Modo::Nube => ModoNube::Nube,
        }
    }
}

impl From<ModoNube> for Modo {
    fn from(m: ModoNube) -> Self {
        match m {
            ModoNube::Local => Modo::Local,
            ModoNube::Nube => Modo::Nube,
        }
    }
}

/// Como va un chat de la nube, para la nubecita de la lista.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum EstadoNube {
    /// Azul: subiendo (o aun sin la primera vuelta).
    Subiendo,
    /// Verde: al dia.
    AlDia,
    /// Gris: sin red, o sin direccion ni llave.
    SinRed,
    /// Roja: la llave no vale o no deja (hay que mirar los ajustes).
    Llave,
}

/// El estado de un chat de la nube, por su ficha (`FichaChat.id`).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EstadoNubeDeFicha {
    pub ficha: String,
    pub estado: EstadoNube,
}

/// Lo que ensena «Sincronizar → Nube».
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AjustesNube {
    /// La direccion de la web, sin barra final (o vacia).
    pub direccion: String,
    /// La llave guardada, enmascarada (`pxn_…a1b2`), si la hay.
    pub llave_guardada: Option<String>,
    /// Hay direccion y llave.
    pub configurada: bool,
}

/// Como acabo «Guardar».
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GuardadoNube {
    Guardado,
    /// `nube-direccion-mala`: ni `https://` ni `http://` a este equipo.
    DireccionMala,
    /// `nube-llave-mala`: no empieza por `pxn_`.
    LlaveMala,
}

/// Lo que dijo la nube al probarla.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SaludoNube {
    pub espacio: String,
    pub persona: Option<String>,
}

/// La ultima prueba de la conexion: el espacio, o el error en palabras.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct UltimoSaludoNube {
    pub bien: bool,
    /// El espacio si `bien`; si no, lo que fallo.
    pub texto: String,
}

/// **Lo anotado de un visor en un chat de la nube**: la carpeta de datos,
/// el chat (el id que viaja) y la clave de lo anotado (el codigo del
/// adjunto, `anot-<uid>…`, o la referencia de un lienzo,
/// `pins/draw/<referencia>.excalidraw.gz`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, uniffi::Record)]
pub struct SitioNube {
    pub raiz: String,
    pub chat: String,
    pub clave: String,
}

/// Lo elegido al salir de un documento sin conexion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AlCerrarNube {
    /// «Sí» (lo de por omision): descartar lo anotado sin conexion.
    Descartar,
    /// «No»: volver a en linea y subirlo.
    Subir,
    /// «Cancelar»: dejarlo sin conexion para la proxima vez.
    Dejar,
}

/// **Avisos de los hilos de la nube a Swift** (desde un hilo de Rust).
#[uniffi::export(callback_interface)]
pub trait AvisoNube: Send + Sync {
    /// Cambio el estado de algun chat (la nubecita) o, con `trajo`, llego
    /// algo de la nube a disco (hay que releer los chats).
    fn cambio(&self, trajo: bool);
}

// ------------------------------------------------------------------ ajustes

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
struct Ajustes {
    direccion: String,
}

fn sincro(raiz: &Path) -> PathBuf {
    raiz.join("sincro")
}

fn ruta_ajustes(raiz: &Path) -> PathBuf {
    estado::carpeta(&sincro(raiz)).join("ajustes.json")
}

fn leer_ajustes(raiz: &Path) -> Ajustes {
    std::fs::read_to_string(ruta_ajustes(raiz))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default()
}

/// La direccion de la web de la nube (sin barra final), o vacia.
fn direccion(raiz: &Path) -> String {
    leer_ajustes(raiz).direccion
}

/// Si una direccion se puede usar: `https://`, o `http://` hacia este
/// equipo (una nube de pruebas).
pub(crate) fn direccion_valida(d: &str) -> bool {
    http::partir(d.trim()).is_some()
}

/// La llave leida del Llavero: se lee una vez por proceso y al cambiarla
/// (el hilo la pide cada 3 s y el Llavero no es para leerlo en bucle).
static LLAVE: Mutex<Option<Option<String>>> = Mutex::new(None);

fn leer_de(ll: Option<&dyn LlaveroApp>) -> Option<String> {
    ll.and_then(|l| l.leer(SERVICIO.into(), CUENTA.into()))
        .map(|c| c.trim().to_string())
        .filter(|c| !c.is_empty())
}

fn llave() -> Option<String> {
    let mut g = LLAVE.lock().unwrap_or_else(|e| e.into_inner());
    if g.is_none() {
        if cfg!(test) {
            // En las pruebas solo vale la que puso la prueba.
            return None;
        }
        // Sin Llavero aun (Swift lo instala al arrancar) no se apunta nada:
        // se mira otra vez la proxima.
        let ll = crate::llavero::llavero_app()?;
        *g = Some(leer_de(Some(ll.as_ref())));
    }
    g.clone().flatten()
}

fn recordar_llave(l: Option<String>) {
    *LLAVE.lock().unwrap_or_else(|e| e.into_inner()) = Some(l);
}

fn sin_llavero() -> ErrorNucleo {
    ErrorNucleo::Ajustes {
        detalle: "no hay Llavero: la llave de la nube no se guarda en claro".into(),
    }
}

/// **Guarda los ajustes**: la direccion y, si viene, la llave (al Llavero).
fn guardar_con(
    raiz: &Path,
    ll: Option<&dyn LlaveroApp>,
    direccion: &str,
    llave: Option<&str>,
) -> Result<GuardadoNube, ErrorNucleo> {
    let direccion = direccion.trim().trim_end_matches('/').to_string();
    if !direccion.is_empty() && !direccion_valida(&direccion) {
        return Ok(GuardadoNube::DireccionMala);
    }
    if let Some(l) = llave.map(str::trim).filter(|l| !l.is_empty()) {
        if !pindesk_sincro::nube::llave_valida(l) {
            return Ok(GuardadoNube::LlaveMala);
        }
        let ll = ll.ok_or_else(sin_llavero)?;
        ll.guardar(SERVICIO.into(), CUENTA.into(), l.into())?;
        recordar_llave(Some(l.to_string()));
    }
    let t = serde_json::to_vec_pretty(&Ajustes { direccion }).map_err(|e| ErrorNucleo::Disco {
        detalle: e.to_string(),
    })?;
    pindesk_sincro::disco::escribir_atomico(&ruta_ajustes(raiz), &t)?;
    despertar(raiz);
    Ok(GuardadoNube::Guardado)
}

fn olvidar_con(raiz: &Path, ll: Option<&dyn LlaveroApp>) -> Result<(), ErrorNucleo> {
    let ll = ll.ok_or_else(sin_llavero)?;
    ll.borrar(SERVICIO.into(), CUENTA.into())?;
    recordar_llave(None);
    despertar(raiz);
    Ok(())
}

fn conexion(raiz: &Path) -> Option<(String, String)> {
    let d = direccion(raiz);
    if d.is_empty() {
        return None;
    }
    Some((d, llave()?))
}

/// Si hay direccion y llave.
fn configurada(raiz: &Path) -> bool {
    conexion(raiz).is_some()
}

// ---------------------------------------------------------------- transporte

/// **El transporte de la nube en el Mac**: el `pedir` del HTTPS de la app
/// (`pindesk_ia::nube::http::pedir`, URLSession desde Swift), con su plazo
/// en la cabecera que Swift quita (`jev::CABECERA_PLAZO`). `http://` a este
/// equipo va por el HTTP local de `pindesk-ia`, sin la app.
pub struct PorLaApp;

impl Transporte for PorLaApp {
    fn enviar(
        &self,
        metodo: &str,
        url: &str,
        cabeceras: &[(&'static str, String)],
        cuerpo: &[u8],
        tiempo: Duration,
    ) -> Result<Contestado, String> {
        let segura = http::partir(url).is_some_and(|d| d.segura);
        if segura && !http::hay_transporte() {
            return Err("falta el HTTPS de la app".into());
        }
        let mut cab = cabeceras.to_vec();
        cab.push((
            crate::jev::CABECERA_PLAZO,
            format!("{:.1}", tiempo.as_secs_f64().max(1.0)),
        ));
        let codigo = |c: u32| u16::try_from(c).unwrap_or(u16::MAX);
        match http::pedir(metodo, url, &cab, cuerpo, LIMITE) {
            Ok(r) => Ok(Contestado {
                codigo: codigo(r.codigo),
                cuerpo: r.cuerpo,
            }),
            Err(Fallo::Http {
                codigo: c, cuerpo, ..
            }) => Ok(Contestado {
                codigo: codigo(c),
                cuerpo: cuerpo.into_bytes(),
            }),
            Err(Fallo::Red(m)) => Err(m),
        }
    }
}

// ------------------------------------------------------------------ estado

#[derive(Default)]
struct Compartido {
    /// Por chat (el id que viaja).
    estados: HashMap<String, EstadoNube>,
    /// Chats con una novedad que bajar.
    pendientes: BTreeSet<String>,
    /// Algo pidio una vuelta ya (ajustes, modo, volver a en linea).
    despierto: bool,
    /// La ultima prueba de la conexion (para Ajustes).
    ultimo: Option<Result<String, String>>,
    /// Quien escucha en Swift.
    aviso: Option<Arc<dyn AvisoNube>>,
    /// Los hilos ya estan en marcha.
    arrancada: bool,
}

/// Lo compartido entre los hilos de la nube y la ventana, por carpeta de
/// datos (en la app hay una; en las pruebas, una por prueba).
struct Hilo {
    m: Mutex<Compartido>,
    cv: Condvar,
}

fn hilo(raiz: &Path) -> Arc<Hilo> {
    static TODOS: OnceLock<Mutex<HashMap<PathBuf, Arc<Hilo>>>> = OnceLock::new();
    let mut g = TODOS
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    g.entry(raiz.to_path_buf())
        .or_insert_with(|| {
            Arc::new(Hilo {
                m: Mutex::new(Compartido::default()),
                cv: Condvar::new(),
            })
        })
        .clone()
}

fn con<T>(raiz: &Path, f: impl FnOnce(&mut Compartido) -> T) -> T {
    let h = hilo(raiz);
    let mut g = h.m.lock().unwrap_or_else(|e| e.into_inner());
    f(&mut g)
}

/// Que el hilo de la nube de una vuelta ya.
fn despertar(raiz: &Path) {
    let h = hilo(raiz);
    h.m.lock().unwrap_or_else(|e| e.into_inner()).despierto = true;
    h.cv.notify_all();
}

/// Avisa a Swift (fuera del cerrojo).
fn avisar(raiz: &Path, trajo: bool) {
    if let Some(a) = con(raiz, |c| c.aviso.clone()) {
        a.cambio(trajo);
    }
}

fn poner_estado(raiz: &Path, chat: &str, e: EstadoNube) {
    let cambio = con(raiz, |c| c.estados.insert(chat.to_string(), e) != Some(e));
    if cambio {
        avisar(raiz, false);
    }
}

/// Por donde va un chat compartido (el id que viaja).
fn modo(raiz: &Path, chat: &str) -> Modo {
    if raiz.as_os_str().is_empty() {
        return Modo::Local;
    }
    ChatsEnLaNube::leer(&sincro(raiz)).modo(chat)
}

/// Cambia por donde va un chat compartido.
fn poner_modo(raiz: &Path, chat: &str, m: Modo) -> std::io::Result<()> {
    estado::cambiar_chats(&sincro(raiz), |c| c.poner(chat, m))?;
    if m == Modo::Local {
        con(raiz, |c| c.estados.remove(chat));
    }
    avisar(raiz, false);
    despertar(raiz);
    Ok(())
}

/// El estado de cada chat de la nube que ya tiene ficha aqui.
fn estados(raiz: &Path) -> Vec<EstadoNubeDeFicha> {
    let chats = ChatsEnLaNube::leer(&sincro(raiz)).chats;
    if chats.is_empty() {
        return Vec::new();
    }
    let d = DiscoPc::nuevo(raiz);
    let hay = configurada(raiz);
    let sabidos = con(raiz, |c| c.estados.clone());
    chats
        .iter()
        .filter_map(|chat| {
            let f = d.ficha_de(chat)?;
            let estado = sabidos.get(chat).copied().unwrap_or(if hay {
                EstadoNube::Subiendo
            } else {
                EstadoNube::SinRed
            });
            Some(EstadoNubeDeFicha {
                ficha: f.id,
                estado,
            })
        })
        .collect()
}

// --------------------------------------------------------------- el hilo

/// La firma de la carpeta de un chat: cuantos ficheros, la suma de tamanos
/// y la ultima fecha. Barata: no lee nada, solo mira.
fn firma_de(dir: &Path) -> (u64, u64, u128) {
    let mut f = (0u64, 0u64, 0u128);
    let mut pila = vec![dir.to_path_buf()];
    while let Some(d) = pila.pop() {
        let Ok(l) = std::fs::read_dir(&d) else {
            continue;
        };
        for e in l.flatten() {
            let Ok(m) = e.metadata() else { continue };
            if m.is_dir() {
                pila.push(e.path());
            } else {
                f.0 += 1;
                f.1 = f.1.wrapping_add(m.len());
                let t = m
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map_or(0, |d| d.as_millis());
                f.2 = f.2.max(t);
            }
        }
    }
    f
}

fn carpeta_del_chat(d: &DiscoPc, raiz: &Path, chat: &str) -> Option<PathBuf> {
    d.ficha_de(chat)
        .map(|f| pindesk_proyecto::almacen::carpeta(raiz, &f.id))
}

/// Presenta la persona de este aparato si la nube aun no la conoce
/// (`PUT /yo`, firmado con su clave P-256 de `compartidos`).
fn presentarse(raiz: &Path, n: &Nube<'_>, h: &Hola) {
    let d = DiscoPc::nuevo(raiz);
    let Ok(yo) = CompartidosEnDisco::nuevo(raiz).yo_de(&d) else {
        return;
    };
    if h.aparato.persona.as_deref() == Some(yo.id.as_str()) {
        return;
    }
    let firma = pindesk_sincro::nube::firma_de_yo(&yo.llaves, &h.aparato.id, &yo.id);
    if let Err(e) = n.presentar(&yo.id, &yo.clave(), &firma) {
        eprintln!("PixPin: la nube no acepto la persona de este aparato: {e}");
    }
}

/// Los compartidos que otros pusieron en la nube y donde estoy: entran solos.
fn adoptar(raiz: &Path, n: &Nube<'_>) -> Result<(), FalloNube> {
    let s = sincro(raiz);
    for c in n.chats()? {
        if c.compartido != Some(true) {
            continue;
        }
        vuelta::conocer_espacio(&s, &c.chat, &c.espacio)?;
        let mut nuevo = false;
        estado::cambiar_chats(&s, |l| nuevo = l.adoptar(&c.chat))?;
        if nuevo {
            con(raiz, |x| x.pendientes.insert(c.chat.clone()));
        }
    }
    Ok(())
}

/// Prueba la conexion: el espacio y la persona, o el error en palabras.
fn probar_con(raiz: &Path, t: &dyn Transporte) -> Result<SaludoNube, String> {
    let (direccion, llave) = conexion(raiz).ok_or_else(|| "sin-configurar".to_string())?;
    let n = Nube {
        direccion,
        llave,
        t,
    };
    let r = n.hola();
    let dicho = r
        .as_ref()
        .map(|h| h.aparato.espacio.clone())
        .map_err(|e| e.to_string());
    con(raiz, |c| c.ultimo = Some(dicho));
    match r {
        Ok(h) => {
            presentarse(raiz, &n, &h);
            despertar(raiz);
            Ok(SaludoNube {
                espacio: h.aparato.espacio,
                persona: h.aparato.persona,
            })
        }
        Err(e) => Err(e.to_string()),
    }
}

/// El estado que deja un fallo.
fn estado_de_fallo(e: &FalloNube) -> EstadoNube {
    if matches!(e, FalloNube::Llave(_)) {
        EstadoNube::Llave
    } else {
        EstadoNube::SinRed
    }
}

/// Una vuelta de un chat; dice si fallo por la red (para esperar mas).
fn una_vuelta(
    raiz: &Path,
    d: &DiscoPc,
    n: &Nube<'_>,
    chat: &str,
    deltas: bool,
    sc: &SinConexion,
    bajar: bool,
) -> bool {
    poner_estado(raiz, chat, EstadoNube::Subiendo);
    let op = Opciones {
        deltas,
        ahora: crate::ahora_ms(),
        retencion: sc,
        bajar,
    };
    match vuelta::vuelta_de_chat(d, n, chat, &op) {
        Ok(i) => {
            poner_estado(raiz, chat, EstadoNube::AlDia);
            if i.bajados > 0 {
                avisar(raiz, true);
            }
            false
        }
        Err(e) => {
            eprintln!("PixPin: nube: la vuelta de {chat} no salio: {e}");
            poner_estado(raiz, chat, estado_de_fallo(&e));
            e.pasajero()
        }
    }
}

fn bucle(raiz: PathBuf) {
    let t = PorLaApp;
    let h = hilo(&raiz);
    let mut saludo: Option<(String, bool)> = None;
    let mut firmas: HashMap<String, ((u64, u64, u128), Instant)> = HashMap::new();
    let mut subidas: HashMap<String, (u64, u64, u128)> = HashMap::new();
    let mut bajado = Instant::now();
    let mut fallos = 0u32;
    loop {
        let espera = if fallos > 0 {
            Duration::from_millis(
                reintentos::espera_tras_fallo(fallos, reintentos::azar_del_sistema()).max(0) as u64,
            )
        } else {
            MIRAR_CADA
        };
        {
            let g = h.m.lock().unwrap_or_else(|e| e.into_inner());
            let (mut g, _) =
                h.cv.wait_timeout_while(g, espera, |c| !c.despierto && c.pendientes.is_empty())
                    .unwrap_or_else(|e| e.into_inner());
            if g.despierto {
                g.despierto = false;
                fallos = 0;
                // Pudo cambiar la direccion o la llave: se saluda otra vez.
                saludo = None;
            }
        }
        let Some((direccion, llave)) = conexion(&raiz) else {
            saludo = None;
            continue;
        };
        let chats = ChatsEnLaNube::leer(&sincro(&raiz)).chats;
        let n = Nube {
            direccion: direccion.clone(),
            llave,
            t: &t,
        };
        if saludo.as_ref().is_none_or(|(d, _)| *d != direccion) {
            match n.hola() {
                Ok(hola) => {
                    presentarse(&raiz, &n, &hola);
                    if let Err(e) = adoptar(&raiz, &n) {
                        eprintln!("PixPin: nube: no se pudieron mirar los chats compartidos: {e}");
                    }
                    saludo = Some((direccion.clone(), hola.sabe(pindesk_sincro::nube::DELTAS)));
                }
                Err(e) => {
                    fallos += 1;
                    let est = estado_de_fallo(&e);
                    for c in &chats {
                        poner_estado(&raiz, c, est);
                    }
                    continue;
                }
            }
        }
        // Los adoptados recien entrados tambien.
        let chats = ChatsEnLaNube::leer(&sincro(&raiz)).chats;
        let deltas = saludo.as_ref().is_some_and(|s| s.1);
        let d = DiscoPc::nuevo(&raiz);
        let sc = SinConexion::nuevo(&sincro(&raiz));
        let toca_bajar = bajado.elapsed() > BAJAR_CADA;
        if toca_bajar {
            bajado = Instant::now();
        }
        let mut fallo = false;
        for chat in &chats {
            let pendiente = con(&raiz, |c| c.pendientes.remove(chat));
            let Some(dir) = carpeta_del_chat(&d, &raiz, chat) else {
                // Un compartido que aun no esta aqui: se baja entero.
                if pendiente || EstadoDeChat::leer(&sincro(&raiz), chat).revision == 0 {
                    fallo |= una_vuelta(&raiz, &d, &n, chat, deltas, &sc, true);
                }
                continue;
            };
            let f = firma_de(&dir);
            let quieto = match firmas.get(chat) {
                Some((g, desde)) if *g == f => desde.elapsed() >= QUIETO,
                _ => {
                    firmas.insert(chat.clone(), (f, Instant::now()));
                    false
                }
            };
            let cambio = subidas.get(chat) != Some(&f) && quieto;
            if pendiente || toca_bajar || cambio {
                let fallo_aqui =
                    una_vuelta(&raiz, &d, &n, chat, deltas, &sc, pendiente || toca_bajar);
                fallo |= fallo_aqui;
                if !fallo_aqui {
                    // Lo que acaba de escribir la vuelta tambien es «visto».
                    let f = firma_de(&dir);
                    subidas.insert(chat.clone(), f);
                    firmas.insert(chat.clone(), (f, Instant::now()));
                }
            }
        }
        fallos = if fallo { fallos + 1 } else { 0 };
    }
}

/// **Las novedades, con la conexion abierta**: en cuanto otro sube un chat
/// de la nube, se apunta y se despierta al hilo de la nube.
fn novedades(raiz: PathBuf) {
    let t = PorLaApp;
    let h = hilo(&raiz);
    let mut fallos = 0u32;
    loop {
        if fallos > 0 {
            std::thread::sleep(Duration::from_millis(
                reintentos::espera_tras_fallo(fallos, reintentos::azar_del_sistema()).max(0) as u64,
            ));
        }
        let Some((direccion, llave)) = conexion(&raiz) else {
            std::thread::sleep(Duration::from_secs(10));
            continue;
        };
        let n = Nube {
            direccion,
            llave,
            t: &t,
        };
        let s = sincro(&raiz);
        let desde = ChatsEnLaNube::leer(&s).seq;
        match n.novedades(desde, ESPERA_NOVEDADES) {
            Ok(nv) => {
                fallos = 0;
                let chats = ChatsEnLaNube::leer(&s);
                let mut hay = nv.reiniciar;
                for c in &nv.cambios {
                    if c.borrado == Some(true) {
                        continue;
                    }
                    if c.compartido == Some(true) && !chats.locales.contains(&c.chat) {
                        let _ = vuelta::conocer_espacio(&s, &c.chat, &c.espacio);
                        let _ = estado::cambiar_chats(&s, |l| {
                            l.adoptar(&c.chat);
                        });
                    }
                    if ChatsEnLaNube::leer(&s).modo(&c.chat) == Modo::Nube
                        && EstadoDeChat::leer(&s, &c.chat).revision < c.revision
                    {
                        con(&raiz, |x| x.pendientes.insert(c.chat.clone()));
                        hay = true;
                    }
                }
                let _ = estado::cambiar_chats(&s, |l| l.seq = nv.seq);
                if nv.reiniciar {
                    let _ = adoptar(&raiz, &n);
                    con(&raiz, |x| x.pendientes.extend(chats.chats.iter().cloned()));
                }
                if hay {
                    h.cv.notify_all();
                }
            }
            Err(_) => fallos += 1,
        }
    }
}

// ------------------------------------------------- «En línea / Sin conexión»

/// El documento de un visor, si es de un chat de la nube (Windows
/// 6f8ceca8, `sincronizar::nube::documento`):
///
/// - **El PDF de un proyecto** (`capas_del_pdf`): sus marcadores van en
///   `anot-<unico del proyecto>…` y su tinta en el lienzo de cada hoja, asi
///   que la clave lleva el codigo y esos lienzos
///   ([`clave_del_pdf_del_proyecto`]).
/// - Un adjunto del chat: el codigo de su mensaje.
pub(crate) fn documento(doc: &Path) -> Option<SitioNube> {
    if let Some(s) = clave_del_pdf_del_proyecto(doc) {
        return Some(s);
    }
    let raiz = pindesk_proyecto::anotado::raiz_de(doc)?;
    let x = pindesk_proyecto::anotado::adjunto_de(&raiz, doc)?;
    (modo(&raiz, &x.chat) == Modo::Nube).then(|| SitioNube {
        raiz: raiz.to_string_lossy().into_owned(),
        chat: x.chat,
        clave: x.uid,
    })
}

/// **La clave del PDF de un proyecto** de un chat de la nube: el codigo de
/// sus marcadores y el dibujo de cada hoja con pagina (los que el lector
/// escribe, con la misma huella; `sin_conexion::clave_con_lienzos`).
fn clave_del_pdf_del_proyecto(pdf: &Path) -> Option<SitioNube> {
    use pindesk_proyecto::capas_del_pdf;
    if !pdf
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("pdf"))
    {
        return None;
    }
    let raiz = pindesk_proyecto::anotado::raiz_de(pdf)?;
    let p = capas_del_pdf::de_este_pdf(&raiz, pdf)?;
    let b = pindesk_proyecto::anotado::base_del_pdf(&raiz, pdf, Some(&p.ficha))?;
    if modo(&raiz, &b.chat) != Modo::Nube {
        return None;
    }
    let codigo = b.base.strip_prefix(pindesk_sincro::anotado::PREFIJO)?;
    let huella = capas_del_pdf::huella(&pdf.to_string_lossy());
    let lienzos = capas_del_pdf::dibujos_de_las_paginas(&raiz, &p.ficha, &huella);
    Some(SitioNube {
        raiz: raiz.to_string_lossy().into_owned(),
        chat: b.chat,
        clave: pindesk_sincro::nube::sin_conexion::clave_con_lienzos(codigo, &lienzos),
    })
}

/// **Una nota de un proyecto** (el lector de notas, Windows 4fdfb7e1): lo
/// suyo cuelga de la base `anot-<codigo>` de la nota (sus comentarios, sus
/// marcas de texto), en el chat de la ficha `ficha`, si va por la nube.
pub(crate) fn nota(raiz: &Path, ficha: &str, codigo: &str) -> Option<SitioNube> {
    if codigo.is_empty() {
        return None;
    }
    let chat = pindesk_proyecto::vista::chat_de_ficha(raiz, ficha)?;
    (modo(raiz, &chat) == Modo::Nube).then(|| SitioNube {
        raiz: raiz.to_string_lossy().into_owned(),
        chat,
        clave: codigo.to_string(),
    })
}

/// El lienzo `referencia` de la ficha `ficha` (una hoja DIBUJO o PAGINA, o
/// el lienzo de una foto), si su chat va por la nube.
fn lienzo(raiz: &Path, ficha: &str, referencia: &str) -> Option<SitioNube> {
    if referencia.is_empty() || raiz.as_os_str().is_empty() {
        return None;
    }
    let chat = pindesk_proyecto::vista::chat_de_ficha(raiz, ficha)?;
    (modo(raiz, &chat) == Modo::Nube).then(|| SitioNube {
        raiz: raiz.to_string_lossy().into_owned(),
        chat,
        clave: referencia.to_string(),
    })
}

fn poner_sin_conexion(s: &SitioNube, sin: bool) -> std::io::Result<()> {
    let raiz = PathBuf::from(&s.raiz);
    let sc = SinConexion::nuevo(&sincro(&raiz));
    let r = if sin {
        sc.retener(&DiscoPc::nuevo(&raiz), &s.chat, &s.clave, crate::ahora_ms())
    } else {
        sc.volver(&s.chat, &s.clave)
    };
    despertar(&raiz);
    r
}

fn al_cerrar(s: &SitioNube, eleccion: AlCerrarNube) -> std::io::Result<()> {
    let raiz = PathBuf::from(&s.raiz);
    let sc = SinConexion::nuevo(&sincro(&raiz));
    if !sc.esta(&s.chat, &s.clave) {
        return Ok(());
    }
    match eleccion {
        AlCerrarNube::Descartar => {
            sc.descartar(&DiscoPc::nuevo(&raiz), &s.chat, &s.clave)?;
            avisar(&raiz, true);
        }
        AlCerrarNube::Subir => {
            sc.volver(&s.chat, &s.clave)?;
            despertar(&raiz);
        }
        AlCerrarNube::Dejar => {}
    }
    Ok(())
}

// ------------------------------------------------------------- el puente

/// Si una direccion se puede guardar en «Nube» (para avisar antes).
#[uniffi::export]
pub fn nube_direccion_valida(direccion: String) -> bool {
    direccion_valida(&direccion)
}

/// Si una llave tiene pinta de llave de la nube (`pxn_…`).
#[uniffi::export]
pub fn nube_llave_valida(llave: String) -> bool {
    pindesk_sincro::nube::llave_valida(&llave)
}

#[uniffi::export]
impl Nucleo {
    /// Lo que ensena «Sincronizar → Nube».
    pub fn nube_ajustes(&self) -> AjustesNube {
        let raiz = self.ruta();
        AjustesNube {
            direccion: direccion(raiz),
            llave_guardada: llave().map(|l| pindesk_ia::nube::claves::enmascarar(&l)),
            configurada: configurada(raiz),
        }
    }

    /// **«Guardar»**: la direccion (a `sincro/nube/ajustes.json`) y, si no
    /// viene vacia, la llave (al Llavero).
    pub fn nube_guardar(
        &self,
        direccion: String,
        llave: Option<String>,
    ) -> Result<GuardadoNube, ErrorNucleo> {
        let ll = crate::llavero::llavero_app();
        guardar_con(self.ruta(), ll.as_deref(), &direccion, llave.as_deref())
    }

    /// «Olvidar» la llave de este aparato.
    pub fn nube_olvidar_llave(&self) -> Result<(), ErrorNucleo> {
        let ll = crate::llavero::llavero_app();
        olvidar_con(self.ruta(), ll.as_deref())
    }

    /// **«Probar»**: `GET hola`, y presentarse si hace falta. Bloquea (red):
    /// llamarlo fuera del hilo principal.
    pub fn nube_probar(&self) -> Result<SaludoNube, ErrorNucleo> {
        probar_con(self.ruta(), &PorLaApp).map_err(|detalle| ErrorNucleo::Sincro { detalle })
    }

    /// Lo que dijo la nube la ultima vez que se probo.
    pub fn nube_ultimo_saludo(&self) -> Option<UltimoSaludoNube> {
        con(self.ruta(), |c| c.ultimo.clone()).map(|r| match r {
            Ok(espacio) => UltimoSaludoNube {
                bien: true,
                texto: espacio,
            },
            Err(e) => UltimoSaludoNube {
                bien: false,
                texto: e,
            },
        })
    }

    /// Por donde va el chat compartido `chat` (el id que viaja,
    /// `ChatCompartidoMac.chat`).
    pub fn modo_de_chat_compartido(&self, chat: String) -> ModoNube {
        modo(self.ruta(), &chat).into()
    }

    /// **«Por dónde va»**: pasa el chat compartido `chat` a la red local o a
    /// la nube (`sincro/nube/chats.json`; `compartidos.json` no se toca).
    pub fn poner_modo_de_chat_compartido(
        &self,
        chat: String,
        modo: ModoNube,
    ) -> Result<(), ErrorNucleo> {
        Ok(poner_modo(self.ruta(), &chat, modo.into())?)
    }

    /// **La nubecita de la lista**: el estado de cada chat de la nube que
    /// ya tiene ficha aqui.
    pub fn estados_de_la_nube(&self) -> Vec<EstadoNubeDeFicha> {
        estados(self.ruta())
    }

    /// **«Chat compartido en la nube»** (el «+» de la lista): nace
    /// compartido, como [`Nucleo::crear_chat_compartido`], y va por la nube.
    pub fn crear_chat_compartido_en_la_nube(
        &self,
        nombre: String,
    ) -> Result<crate::conversacion::ChatNuevo, ErrorNucleo> {
        let r = self.crear_chat_compartido(nombre)?;
        if r.compartido {
            let chat = pindesk_proyecto::vista::chat_de_ficha(self.ruta(), &r.ficha.id)
                .unwrap_or_else(|| r.ficha.id.clone());
            if let Err(e) = poner_modo(self.ruta(), &chat, Modo::Nube) {
                eprintln!("PixPin: no se pudo poner el chat en la nube: {e}");
            }
        }
        Ok(r)
    }

    /// **Arranca la nube** (una vez, al arrancar la app): los dos hilos de
    /// Rust. Sin direccion ni llave no hacen nada (miran cada pocos
    /// segundos). `aviso` lo llaman desde esos hilos.
    pub fn arrancar_nube(&self, aviso: Box<dyn AvisoNube>) {
        let raiz = self.ruta().to_path_buf();
        let aviso: Arc<dyn AvisoNube> = Arc::from(aviso);
        let ya = con(&raiz, |c| {
            c.aviso = Some(aviso);
            std::mem::replace(&mut c.arrancada, true)
        });
        if ya || cfg!(test) {
            return;
        }
        let r = raiz.clone();
        let _ = std::thread::Builder::new()
            .name("nube".into())
            .spawn(move || bucle(r));
        let _ = std::thread::Builder::new()
            .name("nube-novedades".into())
            .spawn(move || novedades(raiz));
    }

    /// El sitio de lo anotado del documento `ruta` (PDF, Word, hoja,
    /// plano...), si es un adjunto de un chat de la nube. `None`: no sale
    /// el boton.
    pub fn nube_sitio_de_documento(&self, ruta: String) -> Option<SitioNube> {
        documento(Path::new(&ruta))
    }

    /// El sitio del lienzo `referencia` de la ficha `ficha`, si su chat va
    /// por la nube.
    pub fn nube_sitio_de_lienzo(&self, ficha: String, referencia: String) -> Option<SitioNube> {
        lienzo(self.ruta(), &ficha, &referencia)
    }

    /// Si lo anotado de `sitio` esta «Sin conexión».
    pub fn nube_sin_conexion(&self, sitio: SitioNube) -> bool {
        SinConexion::nuevo(&sincro(Path::new(&sitio.raiz))).esta(&sitio.chat, &sitio.clave)
    }

    /// **Pasa lo anotado a sin conexion** (`sin`) **o lo vuelve a en linea**
    /// (lo de aqui sube en la vuelta siguiente, solo los trazos nuevos).
    pub fn nube_poner_sin_conexion(&self, sitio: SitioNube, sin: bool) -> Result<(), ErrorNucleo> {
        Ok(poner_sin_conexion(&sitio, sin)?)
    }

    /// **Al salir de un documento sin conexion** (despues de que el visor
    /// guarde lo suyo), lo elegido: descartar, subir o dejarlo.
    pub fn nube_al_cerrar(
        &self,
        sitio: SitioNube,
        eleccion: AlCerrarNube,
    ) -> Result<(), ErrorNucleo> {
        Ok(al_cerrar(&sitio, eleccion)?)
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn carpeta(nombre: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("pixpin-nube-{nombre}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    /// Un llavero en memoria (el papel del Llavero de Swift).
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

    /// Una nube que contesta siempre lo mismo (o no contesta).
    struct Fija(Result<u16, String>, AtomicUsize);

    impl Transporte for Fija {
        fn enviar(
            &self,
            _: &str,
            _: &str,
            cab: &[(&'static str, String)],
            _: &[u8],
            _: Duration,
        ) -> Result<Contestado, String> {
            self.1.fetch_add(1, Ordering::SeqCst);
            assert!(
                cab.iter()
                    .any(|(k, v)| *k == "Authorization" && v.starts_with("Bearer pxn_")),
                "la llave va en la cabecera"
            );
            self.0.clone().map(|codigo| Contestado {
                codigo,
                cuerpo: br#"{"error":"llave revocada"}"#.to_vec(),
            })
        }
    }

    #[test]
    fn los_ajustes_van_a_su_fichero_y_la_llave_al_llavero() {
        let raiz = carpeta("ajustes");
        let ll = EnMemoria::default();
        // Casos negativos: ni direccion sin TLS hacia fuera ni llave rara.
        assert_eq!(
            guardar_con(&raiz, Some(&ll), "http://obra.ejemplo.com", None).unwrap(),
            GuardadoNube::DireccionMala
        );
        assert_eq!(
            guardar_con(&raiz, Some(&ll), "https://obra.ejemplo.com", Some("sk-123")).unwrap(),
            GuardadoNube::LlaveMala
        );
        assert!(!ruta_ajustes(&raiz).exists(), "lo que no vale no se guarda");
        // Sin Llavero, la llave no se guarda en claro.
        assert!(
            guardar_con(
                &raiz,
                None,
                "https://obra.ejemplo.com",
                Some("pxn_abcdefghijklmn")
            )
            .is_err()
        );

        assert_eq!(
            guardar_con(
                &raiz,
                Some(&ll),
                " https://obra.ejemplo.com/ ",
                Some(" pxn_abcdefghijklmn ")
            )
            .unwrap(),
            GuardadoNube::Guardado
        );
        // El mismo fichero que Windows, con solo la direccion.
        let t = std::fs::read_to_string(raiz.join("sincro/nube/ajustes.json")).unwrap();
        let v: serde_json::Value = serde_json::from_str(&t).unwrap();
        assert_eq!(
            v,
            serde_json::json!({"direccion": "https://obra.ejemplo.com"})
        );
        assert!(!t.contains("pxn_"), "la llave nunca en el fichero");
        assert_eq!(
            ll.leer(SERVICIO.into(), CUENTA.into()).as_deref(),
            Some("pxn_abcdefghijklmn")
        );
        assert!(configurada(&raiz));
        // http:// a este equipo vale (una nube de pruebas).
        assert!(direccion_valida("http://127.0.0.1:3000"));
        assert!(!direccion_valida("ftp://127.0.0.1"));

        // «Probar» con la llave que no vale: la nubecita roja.
        let n = Nube {
            direccion: "https://obra.ejemplo.com".into(),
            llave: "pxn_abcdefghijklmn".into(),
            t: &Fija(Ok(401), AtomicUsize::new(0)),
        };
        let e = n.hola().unwrap_err();
        assert_eq!(estado_de_fallo(&e), EstadoNube::Llave);
        let t = Fija(Ok(401), AtomicUsize::new(0));
        assert!(probar_con(&raiz, &t).is_err());
        assert_eq!(t.1.load(Ordering::SeqCst), 1);
        assert!(con(&raiz, |c| matches!(c.ultimo, Some(Err(_)))));
        // Sin red: gris, y se reintenta con espera.
        let sin_red = Nube {
            direccion: "https://obra.ejemplo.com".into(),
            llave: "pxn_abcdefghijklmn".into(),
            t: &Fija(Err("sin conexion".into()), AtomicUsize::new(0)),
        };
        let e = sin_red.hola().unwrap_err();
        assert_eq!(estado_de_fallo(&e), EstadoNube::SinRed);
        assert!(e.pasajero());

        olvidar_con(&raiz, Some(&ll)).unwrap();
        assert!(ll.leer(SERVICIO.into(), CUENTA.into()).is_none());
        assert!(!configurada(&raiz));
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn el_modo_va_en_chats_json_y_no_toca_compartidos() {
        let raiz = carpeta("modo");
        let compartidos = raiz.join("sincro/compartidos.json");
        std::fs::create_dir_all(compartidos.parent().unwrap()).unwrap();
        std::fs::write(&compartidos, b"[]").unwrap();
        assert_eq!(modo(&raiz, "p1"), Modo::Local);
        poner_modo(&raiz, "p1", Modo::Nube).unwrap();
        assert_eq!(modo(&raiz, "p1"), Modo::Nube);
        let v: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(raiz.join("sincro/nube/chats.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(v["chats"], serde_json::json!(["p1"]));
        poner_modo(&raiz, "p1", Modo::Local).unwrap();
        let l = ChatsEnLaNube::leer(&sincro(&raiz));
        assert!(
            l.locales.contains("p1"),
            "lo puesto a mano en Local no vuelve solo"
        );
        assert_eq!(
            std::fs::read(&compartidos).unwrap(),
            b"[]",
            "compartidos.json igual"
        );
        // Un chat de la nube sin ficha aqui no tiene nubecita.
        poner_modo(&raiz, "p2", Modo::Nube).unwrap();
        assert!(estados(&raiz).is_empty());
        // Caso negativo: sin carpeta de datos, nada va por la nube.
        assert_eq!(modo(Path::new(""), "p2"), Modo::Local);
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn un_chat_nuevo_en_la_nube_lleva_su_nubecita() {
        let raiz = carpeta("nuevo");
        let n = Nucleo::abrir(raiz.to_string_lossy().into_owned(), "Mac de prueba".into()).unwrap();
        let r = n.crear_chat_compartido_en_la_nube("Obra".into()).unwrap();
        assert!(r.compartido);
        let chat = pindesk_proyecto::vista::chat_de_ficha(&raiz, &r.ficha.id)
            .unwrap_or(r.ficha.id.clone());
        assert_eq!(n.modo_de_chat_compartido(chat.clone()), ModoNube::Nube);
        // Sin direccion ni llave: gris.
        assert_eq!(
            n.estados_de_la_nube(),
            vec![EstadoNubeDeFicha {
                ficha: r.ficha.id.clone(),
                estado: EstadoNube::SinRed
            }]
        );
        // Lo que dice la vuelta manda.
        poner_estado(&raiz, &chat, EstadoNube::AlDia);
        assert_eq!(n.estados_de_la_nube()[0].estado, EstadoNube::AlDia);
        // Un chat normal no.
        let normal = n.crear_chat("Mio".into()).unwrap();
        assert!(n.estados_de_la_nube().iter().all(|e| e.ficha != normal.id));
        // Su lienzo: con referencia hay sitio; sin ella, no.
        let s = n
            .nube_sitio_de_lienzo(r.ficha.id.clone(), "d1".into())
            .unwrap();
        assert_eq!((s.chat.as_str(), s.clave.as_str()), (chat.as_str(), "d1"));
        assert!(
            n.nube_sitio_de_lienzo(r.ficha.id.clone(), String::new())
                .is_none()
        );
        assert!(
            n.nube_sitio_de_lienzo(normal.id.clone(), "d1".into())
                .is_none()
        );
        // Sin conexion y vuelta.
        assert!(!n.nube_sin_conexion(s.clone()));
        n.nube_poner_sin_conexion(s.clone(), true).unwrap();
        assert!(n.nube_sin_conexion(s.clone()));
        n.nube_al_cerrar(s.clone(), AlCerrarNube::Dejar).unwrap();
        assert!(
            n.nube_sin_conexion(s.clone()),
            "Cancelar lo deja sin conexion"
        );
        n.nube_al_cerrar(s.clone(), AlCerrarNube::Subir).unwrap();
        assert!(!n.nube_sin_conexion(s.clone()));
        n.nube_poner_sin_conexion(s.clone(), true).unwrap();
        n.nube_al_cerrar(s.clone(), AlCerrarNube::Descartar)
            .unwrap();
        assert!(!n.nube_sin_conexion(s));
        // Un fichero suelto no es de ningun chat: no hay boton.
        assert!(
            n.nube_sitio_de_documento("/no/esta/plano.dwg".into())
                .is_none()
        );
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn el_pdf_de_un_proyecto_de_la_nube_retiene_los_lienzos_de_sus_hojas() {
        use pindesk_proyecto::{Hoja, Proyecto, almacen};
        let raiz = carpeta("pdf-proyecto");
        let n = Nucleo::abrir(raiz.to_string_lossy().into_owned(), "Mac de prueba".into()).unwrap();
        let r = n.crear_chat_compartido_en_la_nube("Obra".into()).unwrap();
        let ficha = r.ficha.id.clone();
        let carpeta_chat = almacen::carpeta(&raiz, &ficha);
        std::fs::create_dir_all(carpeta_chat.join("archivos")).unwrap();
        let pdf = carpeta_chat.join("archivos/doc-7.pdf");
        std::fs::write(&pdf, b"%PDF-1.4 doc").unwrap();
        let hoja = |id: &str, pagina: u32, dibujo: Option<&str>| Hoja {
            id: id.into(),
            pagina: Some(pagina),
            dibujo: dibujo.map(str::to_string),
            ..Default::default()
        };
        let p = Proyecto {
            id: ficha.clone(),
            nombre: "Obra".into(),
            hojas: vec![hoja("h0", 0, Some("dib-1")), hoja("h1", 1, None)],
            tocado: 10,
            pdf_origen: Some("archivos/doc-7.pdf".into()),
            ..Default::default()
        };
        std::fs::write(carpeta_chat.join("proyecto.json"), serde_json::to_string(&p).unwrap()).unwrap();
        let s = n
            .nube_sitio_de_documento(pdf.to_string_lossy().into_owned())
            .expect("el PDF del proyecto tiene boton");
        let huella = pindesk_proyecto::capas_del_pdf::huella(&pdf.to_string_lossy());
        let partes: Vec<&str> = s.clave.split('|').collect();
        assert_eq!(partes.len(), 3, "{}", s.clave);
        assert_eq!(&partes[1..], ["dib-1".to_string(), format!("pdf-{huella}-p1")]);
        assert!(!partes[0].is_empty() && !partes[0].starts_with("anot-"));
        // Sin conexion y vuelta, con la clave compuesta.
        n.nube_poner_sin_conexion(s.clone(), true).unwrap();
        assert!(n.nube_sin_conexion(s.clone()));
        n.nube_al_cerrar(s.clone(), AlCerrarNube::Subir).unwrap();
        assert!(!n.nube_sin_conexion(s));
        // Caso negativo: un PDF que no es de ningun proyecto ni adjunto.
        let suelto = raiz.join("suelto.pdf");
        std::fs::write(&suelto, b"%PDF-1.4").unwrap();
        assert!(n.nube_sitio_de_documento(suelto.to_string_lossy().into_owned()).is_none());
        // Una nota de ese proyecto, por su codigo; sin codigo, no.
        let nota = nota(&raiz, &ficha, "ABCDE23456").unwrap();
        assert_eq!(nota.clave, "ABCDE23456");
        assert!(super::nota(&raiz, &ficha, "").is_none());
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn la_firma_cambia_al_escribir() {
        let d = carpeta("firma");
        let a = firma_de(&d);
        std::fs::create_dir_all(d.join("pins")).unwrap();
        std::fs::write(d.join("pins/x.txt"), b"hola").unwrap();
        let b = firma_de(&d);
        assert_ne!(a, b);
        assert_eq!(b.0, 1);
        assert_eq!(b, firma_de(&d), "mirar no cambia nada");
        let _ = std::fs::remove_dir_all(&d);
    }
}
