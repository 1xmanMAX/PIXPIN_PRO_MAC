//! **El asistente**, visto desde Swift.
//!
//! **Contesta la nube** (Claude o DeepSeek), como en Windows desde el
//! 27-oct-2026 (`f86732c`, «Asistente solo con la nube»: fuera el modelo
//! local de llama.cpp, su descarga y sus ajustes) y en Android. El turno va
//! por [`turno::ia_turno`] con los ajustes `[asistente]`: la nube por el
//! HTTPS de Swift ([`transporte`]); pensar, la hoja de trabajo, el camino
//! rapido y las acciones de la app como en Windows. El texto va llegando a
//! Swift por un [`OyenteIa`] (un interfaz que implementa Swift) en tandas
//! de como mucho [`CADA_TANDA_MS`] (no una llamada por palabra: §4bis.1), y
//! se corta con [`CorteIa::cancelar`]. Lo que quedo bajado del modelo
//! local, para liberarlo: [`modelos_viejos`].
//!
//! **Apple Intelligence** (Foundation Models, macOS 26) es solo del Mac y
//! contesta cuando no hay clave de la nube guardada. No pasa por Rust:
//! Swift declara las herramientas con el JSON de [`ia_catalogo_para`] y,
//! cuando el modelo llama una, pasa el nombre y los argumentos a
//! [`ia_llamar`] (validar con las reglas de siempre y, si dibuja, los
//! elementos de Excalidraw). Una llamada por herramienta, no una por figura
//! (§4bis del plan).
//!
//! Todo es bloqueante y sin hilos propios: Swift lo llama desde una `Task`
//! con prioridad `.utility`.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use pindesk_ia::agente;
use serde_json::Value;

pub mod al_lienzo;
pub mod chat;
pub mod conexiones;
pub mod de_fondo;
pub mod documentos;
pub mod documentos_acciones;
pub mod hoja_a_lienzo;
pub mod letras;
pub mod en_la_conversacion;
pub mod memoria;
pub mod modelos_viejos;
pub mod ojos;
pub mod recetas;
pub mod transporte;
pub mod turno;

/// Un mensaje de la conversacion que guarda Swift, para la vuelta
/// siguiente. Solo texto: las llamadas a herramientas de turnos pasados no
/// se vuelven a mandar (un modelo pequeno se lia con ellas).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MensajeIa {
    /// `true` si lo escribio el usuario; `false`, el asistente.
    pub del_usuario: bool,
    pub texto: String,
}

/// Una herramienta que se uso en el turno.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HerramientaUsada {
    pub nombre: String,
    pub ok: bool,
    /// Lo que se le devolvio al modelo («dibujadas 4 figuras», el motivo).
    pub resumen: String,
}

/// Lo que contesto el asistente en un turno.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RespuestaIa {
    pub texto: String,
    pub herramientas: Vec<HerramientaUsada>,
    /// Lo dibujado en el turno, como un `.excalidraw` entero (el formato
    /// que lee el lienzo), o nada si no se dibujo.
    pub lienzo: Option<String>,
    /// Lo que penso antes de contestar (vacio si no penso).
    pub pensamiento: String,
    /// Cuanto penso («Pensó 12 s»), si penso.
    pub segundos_pensando: Option<f32>,
    /// Quien contesto («Claude Haiku 5.5», «DeepSeek V4.1 Flash»).
    pub motor: String,
    /// La hoja de trabajo de la conversacion, reescrita (JSON), para el
    /// turno siguiente. Vacia si el turno no la lleva.
    pub hoja: String,
    /// Lo citado de los documentos del usuario (`buscar_en_mis_cosas`): las
    /// tarjetas que abren el documento.
    pub citas: Vec<CitaIa>,
}

/// Una cita de los documentos del usuario.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CitaIa {
    /// El `[n]` de la respuesta.
    pub numero: u32,
    /// «Tesis.pdf · pág. 12».
    pub titulo: String,
    /// El pedido `abrir` del protocolo que lo abre (JSON).
    pub pedido: String,
}

/// Cada cuanto, como mucho, cruza el texto nuevo a Swift mientras llega.
/// Unas 16 tandas por segundo: se ve fluido y el puente casi no se nota.
pub const CADA_TANDA_MS: u64 = 60;

/// **Quien escucha la respuesta en vivo**: lo implementa Swift. Se le
/// llama desde el hilo del turno (no el principal): Swift pasa lo recibido
/// al hilo de la interfaz.
#[uniffi::export(foreign)]
pub trait OyenteIa: Send + Sync {
    /// Texto nuevo de la respuesta (una tanda; se pega detras de lo de antes).
    fn texto(&self, trozo: String);
    /// Se uso una herramienta (con su resultado).
    fn herramienta(&self, usada: HerramientaUsada);
    /// Un trozo de lo que piensa (la seccion plegable «Pensando…»).
    fn pensando(&self, trozo: String);
    /// El modelo empezo a pedir una herramienta («dibujando…»).
    fn llamando(&self, nombre: String);
}

/// **Para cortar un turno en vivo** desde otro hilo (el boton «Parar»).
#[derive(Debug, Default, uniffi::Object)]
pub struct CorteIa {
    cortado: AtomicBool,
}

#[uniffi::export]
impl CorteIa {
    #[uniffi::constructor]
    pub fn nuevo() -> Arc<CorteIa> {
        Arc::new(CorteIa::default())
    }

    /// Pide parar: el turno acaba en el siguiente trozo que llegue, con lo
    /// que hubiera hasta ahi.
    pub fn cancelar(&self) {
        self.cortado.store(true, Ordering::Relaxed);
    }

    pub fn cortado(&self) -> bool {
        self.cortado.load(Ordering::Relaxed)
    }
}

/// Junta el texto que llega y lo suelta en tandas.
pub(crate) struct Tanda {
    pendiente: String,
    ultima: Instant,
    cada: Duration,
}

impl Tanda {
    pub(crate) fn nueva(cada: Duration) -> Tanda {
        Tanda {
            pendiente: String::new(),
            ultima: Instant::now(),
            cada,
        }
    }

    /// Mete texto; devuelve la tanda si ya toca soltarla.
    pub(crate) fn meter(&mut self, texto: &str) -> Option<String> {
        self.pendiente.push_str(texto);
        if self.pendiente.is_empty() || self.ultima.elapsed() < self.cada {
            return None;
        }
        self.soltar()
    }

    /// Lo que quede, toque o no.
    pub(crate) fn soltar(&mut self) -> Option<String> {
        self.ultima = Instant::now();
        (!self.pendiente.is_empty()).then(|| std::mem::take(&mut self.pendiente))
    }
}

/// Las instrucciones de sistema del asistente (las mismas que en Windows).
#[uniffi::export]
pub fn ia_instrucciones() -> String {
    agente::instrucciones()
}

/// Todas las herramientas, como la lista `tools` de OpenAI (JSON).
#[uniffi::export]
pub fn ia_catalogo() -> String {
    pindesk_ia::puente::catalogo()
}

/// Las pocas herramientas que vienen a cuento para `pedido` (JSON, lista
/// `tools` de OpenAI): un modelo pequeno se pierde con el catalogo entero.
#[uniffi::export]
pub fn ia_catalogo_para(pedido: String, con_imagen: bool) -> String {
    pindesk_ia::puente::catalogo_para(&pedido, con_imagen)
}

/// Una llamada del modelo, de cualquier motor (ver
/// `pindesk_ia::puente::llamar`): devuelve el objeto JSON con `ok`,
/// `elementos`, `argumentos`... o `para_el_modelo` si estaba mal.
#[uniffi::export]
pub fn ia_llamar(
    nombre: String,
    argumentos: String,
    origen_x: f64,
    origen_y: f64,
    semilla: u64,
) -> String {
    pindesk_ia::puente::llamar(&nombre, &argumentos, (origen_x, origen_y), semilla)
}

/// Un `.excalidraw` entero con los `elementos` (texto JSON de una lista,
/// los que van juntando las llamadas de [`ia_llamar`]). Lo que no es una
/// lista da un lienzo vacio.
#[uniffi::export]
pub fn ia_lienzo_de(elementos: String) -> String {
    let lista = match serde_json::from_str::<Value>(&elementos) {
        Ok(Value::Array(v)) => v,
        _ => Vec::new(),
    };
    pindesk_ia::lienzo::documento(lista)
}

#[cfg(test)]
pub(crate) mod pruebas {
    use super::*;
    use pindesk_ia::herramientas;

    #[test]
    fn el_catalogo_y_la_llamada_cruzan_como_texto_json() {
        let v: Value =
            serde_json::from_str(&ia_catalogo_para("dibuja un circulo".into(), false)).unwrap();
        assert!(!v.as_array().unwrap().is_empty());
        let r: Value = serde_json::from_str(&ia_llamar(
            herramientas::DIBUJAR.into(),
            r#"{"elementos":[{"tipo":"elipse","x":0,"y":0,"ancho":50,"alto":50,"color":"azul"}]}"#
                .into(),
            0.0,
            0.0,
            3,
        ))
        .unwrap();
        assert_eq!(r["ok"], true, "{r}");
        assert!(!ia_instrucciones().is_empty());
        assert!(
            serde_json::from_str::<Value>(&ia_catalogo())
                .unwrap()
                .is_array()
        );
        let doc = ia_lienzo_de(r["elementos"].to_string());
        assert!(pindesk_motor2d::excalidraw::leer(&doc).is_ok());
        assert!(pindesk_motor2d::excalidraw::leer(&ia_lienzo_de("roto".into())).is_ok());
    }

    #[test]
    fn las_tandas_juntan_el_texto_y_sueltan_lo_que_queda() {
        // Sin espera: cada trozo cruza en cuanto llega.
        let mut t = Tanda::nueva(Duration::ZERO);
        assert_eq!(t.meter("Hola").as_deref(), Some("Hola"));
        assert_eq!(t.meter("").as_deref(), None);
        // Con espera larga: no se cruza el puente por cada palabra.
        let mut t = Tanda::nueva(Duration::from_secs(3600));
        for p in ["uno ", "dos ", "tres"] {
            assert_eq!(t.meter(p), None);
        }
        assert_eq!(t.soltar().as_deref(), Some("uno dos tres"));
        assert_eq!(t.soltar(), None);
    }

    #[test]
    fn el_corte_se_ve_desde_otro_hilo() {
        let c = CorteIa::nuevo();
        assert!(!c.cortado());
        let otro = c.clone();
        std::thread::spawn(move || otro.cancelar()).join().unwrap();
        assert!(c.cortado());
    }

    /// Lo que oye Swift, apuntado.
    #[derive(Default)]
    pub(crate) struct Apunta {
        pub(crate) tandas: std::sync::Mutex<Vec<String>>,
        pub(crate) herramientas: std::sync::Mutex<Vec<HerramientaUsada>>,
        pub(crate) pensado: std::sync::Mutex<String>,
        pub(crate) llamadas: std::sync::Mutex<Vec<String>>,
        /// Si se pone, corta al llegar la primera tanda.
        cortar: Option<Arc<CorteIa>>,
    }

    impl OyenteIa for Apunta {
        fn texto(&self, trozo: String) {
            self.tandas.lock().unwrap().push(trozo);
            if let Some(c) = &self.cortar {
                c.cancelar();
            }
        }
        fn herramienta(&self, usada: HerramientaUsada) {
            self.herramientas.lock().unwrap().push(usada);
        }
        fn pensando(&self, trozo: String) {
            self.pensado.lock().unwrap().push_str(&trozo);
        }
        fn llamando(&self, nombre: String) {
            self.llamadas.lock().unwrap().push(nombre);
        }
    }
}
