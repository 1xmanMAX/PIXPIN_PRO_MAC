//! **El estado de las IA en el Mac** (Windows 851979e y 1433523,
//! `apps/pixpin/src/estado_ia.rs`): lo que se sabe de Claude, DeepSeek y
//! Jev para los puntitos de junto al boton de sincronizar.
//!
//! - **De lo que se usa de verdad**: cada peticion del asistente, de
//!   «Probar» en Ajustes y de Jev avisa de como acabo
//!   (`pixpin_ia::nube::al_contestar` y `pixpin_typesafe::cliente::al_contestar`).
//! - **Una comprobacion que no gasta**, en su hilo («estado-ia»): la lista
//!   de modelos de cada API, a los 10 s de arrancar, al cambiar una clave,
//!   con «Comprobar ahora» y como mucho cada 30 min; sin red, antes y con
//!   espera creciente. Las reglas, con sus pruebas, en `pixpin_ui::estado_ia`
//!   (el mismo crate que Windows).
//!
//! Swift lo arranca una vez ([`ia_estado_arrancar`], con el Llavero y el
//! HTTPS ya puestos) y pinta lo que da [`ia_estado`] cuando cambia
//! [`ia_estado_novedades`].

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use fluent_bundle::FluentArgs;
use pixpin_ia::nube::{self, Proveedor};
use pixpin_ui::estado_ia::{Desenlace, Ficha, Luz, Servicio, Tablero, hace};

static TABLERO: Mutex<Option<Tablero>> = Mutex::new(None);
/// Despierta al hilo de las comprobaciones (clave nueva, «Comprobar ahora»).
static DESPERTADOR: Condvar = Condvar::new();
/// Sube cuando cambia algo que se ve.
static NOVEDADES: AtomicU64 = AtomicU64::new(0);
static RELOJ: OnceLock<Instant> = OnceLock::new();
static ARRANCADO: AtomicBool = AtomicBool::new(false);

/// Lo mas que duerme el hilo sin mirar si hay claves nuevas.
const VISTAZO: Duration = Duration::from_secs(5 * 60);

fn ahora_ms() -> u64 {
    RELOJ.get_or_init(Instant::now).elapsed().as_millis() as u64
}

fn tablero() -> MutexGuard<'static, Option<Tablero>> {
    TABLERO.lock().unwrap_or_else(|e| e.into_inner())
}

fn con<R>(f: impl FnOnce(&mut Tablero) -> R) -> R {
    f(tablero().get_or_insert_with(Tablero::nuevo))
}

fn cambio() {
    NOVEDADES.fetch_add(1, Ordering::SeqCst);
}

fn de_proveedor(p: Proveedor) -> Servicio {
    match p {
        Proveedor::Claude => Servicio::Claude,
        Proveedor::DeepSeek => Servicio::DeepSeek,
    }
}

fn apuntar(s: Servicio, d: Desenlace) {
    let ahora = ahora_ms();
    con(|t| t.apuntar(s, d, ahora));
    // Aunque el estado sea el mismo, cambia el «hace N min»: se repinta.
    cambio();
}

fn oir_nube(p: Proveedor, codigo: Option<u32>) {
    apuntar(de_proveedor(p), Desenlace::de_codigo(codigo));
}

fn oir_jev(codigo: Option<u16>) {
    apuntar(Servicio::Jev, Desenlace::de_codigo(codigo.map(u32::from)));
}

fn hay_clave(s: Servicio) -> bool {
    match s {
        Servicio::Claude => nube::claves::hay(Proveedor::Claude),
        Servicio::DeepSeek => nube::claves::hay(Proveedor::DeepSeek),
        Servicio::Jev => super::hay_clave(),
    }
}

/// **Arranca** el estado: escucha lo que pasa en cada peticion y lanza el
/// hilo de las comprobaciones. Una vez por proceso (las demas no hacen
/// nada), con el Llavero y el HTTPS de la app ya instalados.
#[uniffi::export]
pub fn ia_estado_arrancar() {
    if cfg!(test) || ARRANCADO.swap(true, Ordering::SeqCst) {
        return;
    }
    let arranque = ahora_ms();
    nube::al_contestar(oir_nube);
    pixpin_typesafe::cliente::al_contestar(oir_jev);
    let lanzado = std::thread::Builder::new()
        .name("estado-ia".into())
        .spawn(move || bucle(arranque));
    if lanzado.is_err() {
        ARRANCADO.store(false, Ordering::SeqCst);
    }
}

/// **Se guardo o se borro una clave** (`claude`, `deepseek` o `jev`): se
/// olvida lo de la anterior y, si hay una nueva, se comprueba ya.
#[uniffi::export]
pub fn ia_estado_clave_cambiada(servicio: String) {
    let s = match servicio.as_str() {
        "claude" => Servicio::Claude,
        "deepseek" => Servicio::DeepSeek,
        "jev" | "typesafe" => Servicio::Jev,
        _ => return,
    };
    clave_cambiada(s);
}

pub(crate) fn clave_cambiada(s: Servicio) {
    if cfg!(test) {
        return;
    }
    let hay = hay_clave(s);
    con(|t| t.clave_cambiada(s, hay));
    cambio();
    DESPERTADOR.notify_all();
}

/// **«Comprobar ahora»** (el menu de los puntitos).
#[uniffi::export]
pub fn ia_estado_comprobar_ahora() {
    con(|t| t.pedir_ahora());
    cambio();
    DESPERTADOR.notify_all();
}

/// Sube cada vez que cambia lo que se ve (Swift lo mira cada poco y relee
/// [`ia_estado`] si cambio).
#[uniffi::export]
pub fn ia_estado_novedades() -> u64 {
    NOVEDADES.load(Ordering::SeqCst)
}

fn bucle(arranque: u64) {
    loop {
        let claves: Vec<(Servicio, bool)> = Servicio::TODOS.into_iter().map(|s| (s, hay_clave(s))).collect();
        let ahora = ahora_ms();
        let (toca, cambiado) = con(|t| {
            let mut cambiado = false;
            for (s, hay) in &claves {
                cambiado |= t.poner_clave(*s, *hay);
            }
            let toca = t.por_comprobar(ahora, arranque);
            for s in &toca {
                t.empezar(*s, ahora);
            }
            (toca, cambiado)
        });
        if cambiado || !toca.is_empty() {
            cambio();
        }
        for s in toca {
            comprobar(s);
            con(|t| t.acabar(s));
            cambio();
        }
        let g = tablero();
        let espera = g
            .as_ref()
            .and_then(|t| t.proxima(arranque))
            .map(|t| Duration::from_millis(t.saturating_sub(ahora_ms())))
            .unwrap_or(VISTAZO)
            .min(VISTAZO);
        if espera.is_zero() {
            continue;
        }
        let _ = DESPERTADOR.wait_timeout(g, espera);
    }
}

/// Una comprobacion que no gasta tokens; lo que conteste llega por
/// `oir_nube`/`oir_jev`, como cualquier peticion. Sin el HTTPS de la app
/// no se puede: cuenta como sin red.
fn comprobar(s: Servicio) {
    if !nube::http::hay_transporte() {
        apuntar(s, Desenlace::Red);
        return;
    }
    match s {
        Servicio::Claude | Servicio::DeepSeek => {
            let p = if s == Servicio::Claude {
                Proveedor::Claude
            } else {
                Proveedor::DeepSeek
            };
            if let Some(clave) = nube::claves::leer(p) {
                let _ = nube::comprobar(p, &clave);
            }
        }
        Servicio::Jev => {
            if let Some(clave) = super::clave() {
                let _ = super::cliente(clave).modelos();
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Lo que pinta Swift

/// El color del puntito (`pixpin_ui::estado_ia::Luz`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum LuzIa {
    /// Funciona: verde lleno.
    Verde,
    /// Falla: rojo lleno.
    Roja,
    /// Sin clave: solo el aro rojo.
    Hueca,
    /// Hay clave y aun no se sabe: gris tenue.
    Gris,
}

impl From<Luz> for LuzIa {
    fn from(l: Luz) -> Self {
        match l {
            Luz::Verde => LuzIa::Verde,
            Luz::Roja => LuzIa::Roja,
            Luz::Hueca => LuzIa::Hueca,
            Luz::Gris => LuzIa::Gris,
        }
    }
}

/// Un servicio: su puntito y su frase («Claude · funciona · hace 3 min»).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ServicioIa {
    /// `claude`, `deepseek` o `jev`.
    pub id: String,
    pub nombre: String,
    pub luz: LuzIa,
    pub linea: String,
}

/// **Lo que se sabe ahora**, con los textos en el idioma de la app.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EstadoIa {
    /// Claude, DeepSeek y Jev, de arriba abajo.
    pub servicios: Vec<ServicioIa>,
    /// «Clic: comprobar ahora o ir a las claves».
    pub pista: String,
    /// «Comprobar ahora».
    pub comprobar: String,
    /// «Claves en Ajustes → Asistente».
    pub claves: String,
    pub todo_bien: bool,
}

fn id_de(s: Servicio) -> &'static str {
    match s {
        Servicio::Claude => "claude",
        Servicio::DeepSeek => "deepseek",
        Servicio::Jev => "jev",
    }
}

/// La frase de un servicio: «Claude · funciona · hace 3 min».
fn linea(textos: &pixpin_store::idioma::Catalogo, s: Servicio, f: &Ficha, ahora: u64) -> String {
    if f.comprobando() {
        return format!("{} · {}", s.nombre(), textos.t("ia-estado-comprobando"));
    }
    let mut args = FluentArgs::new();
    if let Some(c) = f.estado.codigo() {
        args.set("codigo", c.to_string());
    }
    let mut l = format!("{} · {}", s.nombre(), textos.t_args(f.estado.clave(), &args));
    if f.hay_clave()
        && let Some(cuando) = f.cuando
    {
        let (clave, n) = hace(cuando, ahora);
        let mut args = FluentArgs::new();
        args.set("n", n.to_string());
        l.push_str(" · ");
        l.push_str(&textos.t_args(clave, &args));
    }
    l
}

pub(crate) fn estado_de(t: &Tablero, ahora: u64, locale: &str) -> EstadoIa {
    let textos = super::catalogo(locale);
    EstadoIa {
        servicios: Servicio::TODOS
            .into_iter()
            .map(|s| {
                let f = t.ficha(s);
                ServicioIa {
                    id: id_de(s).into(),
                    nombre: s.nombre().into(),
                    luz: f.estado.luz().into(),
                    linea: linea(&textos, s, f, ahora),
                }
            })
            .collect(),
        pista: textos.t("ia-estado-pista"),
        comprobar: textos.t("ia-estado-comprobar"),
        claves: textos.t("ia-estado-claves"),
        todo_bien: t.todo_bien(),
    }
}

/// **El estado de las tres IA** para los puntitos y su menu.
#[uniffi::export]
pub fn ia_estado(locale: String) -> EstadoIa {
    let t = con(|t| t.clone());
    estado_de(&t, ahora_ms(), &locale)
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn las_frases_y_los_colores_de_cada_servicio() {
        let mut t = Tablero::nuevo();
        t.poner_clave(Servicio::Claude, true);
        t.apuntar(Servicio::Claude, Desenlace::Http(200), 0);
        t.poner_clave(Servicio::Jev, true);
        t.apuntar(Servicio::Jev, Desenlace::Http(401), 0);
        let e = estado_de(&t, 3 * 60_000, "es-ES");
        assert_eq!(e.servicios.len(), 3);
        assert_eq!(e.servicios[0].id, "claude");
        assert_eq!(e.servicios[0].luz, LuzIa::Verde);
        assert_eq!(e.servicios[0].linea, "Claude · funciona · hace 3 min");
        assert_eq!(e.servicios[1].luz, LuzIa::Hueca);
        assert_eq!(e.servicios[1].linea, "DeepSeek · sin clave");
        assert_eq!(e.servicios[2].luz, LuzIa::Roja);
        assert!(e.servicios[2].linea.starts_with("Jev · la clave no es válida (401)"), "{}", e.servicios[2].linea);
        assert_eq!(e.comprobar, "Comprobar ahora");
        assert!(!e.todo_bien);
    }

    #[test]
    fn un_servicio_desconocido_no_hace_nada() {
        let antes = ia_estado_novedades();
        ia_estado_clave_cambiada("openai".into());
        assert_eq!(ia_estado_novedades(), antes);
    }
}
