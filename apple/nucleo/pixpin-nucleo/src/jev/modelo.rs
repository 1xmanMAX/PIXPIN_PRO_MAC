//! **Que modelo contesta cada pedido al asistente** (Windows e51da39,
//! `apps/pixpin/src/jev/modelo.rs`): antes del turno, Jev dice lo dificil
//! que es, si es una orden simple, si pide razonar y si un error importaria
//! (`pixpin_typesafe::modelo`); la tabla de alli elige el modelo rapido
//! (Claude Haiku, DeepSeek Flash: el de siempre) o el fuerte del mismo
//! proveedor y con la misma clave (Claude Sonnet, DeepSeek V4 Pro).
//!
//! - Las ordenes del camino rapido ni preguntan: se hacen en este Mac.
//! - La pregunta se hace **en el hilo del turno**, al pedirle la primera
//!   respuesta ([`MotorSegunJev`]): el chat no espera nada al enviar.
//! - La pastilla del modelo del chat «Asistente» ensena lo elegido
//!   ([`jev_rotulo_del_modelo`]: «Claude Sonnet · Jev») durante 15 minutos.
//! - Sin clave de TypeSafe, con la funcion apagada, o si Jev falla o tarda,
//!   el de siempre.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use pixpin_ia::motor::{Motor, Peticion, Respuesta, Seguir, Trozo};
use pixpin_ia::nube::{self, MotorNube, Proveedor};
use pixpin_typesafe::Cliente;
use pixpin_typesafe::modelo::{self as jm, Contexto, Ruta};

use super::Funcion;

/// El modelo fuerte de cada proveedor y como se llama en la pastilla.
pub fn fuerte_de(p: Proveedor) -> (&'static str, &'static str) {
    match p {
        Proveedor::Claude => (nube::claude::MODELO_CRITICO, "Claude Sonnet"),
        Proveedor::DeepSeek => (nube::deepseek::MODELO_PRO, "DeepSeek V4 Pro"),
    }
}

/// El rapido (el de siempre) en la pastilla.
pub fn rapido_de(p: Proveedor) -> &'static str {
    match p {
        Proveedor::Claude => "Claude Haiku",
        Proveedor::DeepSeek => "DeepSeek",
    }
}

/// Lo elegido en el ultimo pedido de cada chat: cuando y el rotulo.
static ELEGIDO: Mutex<Option<HashMap<String, (Instant, &'static str)>>> = Mutex::new(None);

/// Lo que dura en la pastilla lo elegido para el ultimo pedido.
const EN_LA_PASTILLA: Duration = Duration::from_secs(15 * 60);

fn apuntar(chat: &str, rotulo: &'static str) {
    let mut g = ELEGIDO.lock().unwrap_or_else(|e| e.into_inner());
    g.get_or_insert_with(HashMap::new)
        .insert(chat.to_string(), (Instant::now(), rotulo));
}

/// **El rotulo de la pastilla del modelo**: lo que eligio Jev para el ultimo
/// pedido de `chat` («Claude Sonnet · Jev»), si fue hace poco. `chat` vacio:
/// la ventana del asistente.
#[uniffi::export]
pub fn jev_rotulo_del_modelo(chat: String) -> Option<String> {
    let g = ELEGIDO.lock().ok()?;
    let (cuando, r) = g.as_ref()?.get(&chat)?;
    (cuando.elapsed() < EN_LA_PASTILLA).then(|| format!("{r} · Jev"))
}

/// **Un motor que elige su modelo** al pedirle la primera respuesta.
pub struct MotorSegunJev {
    rapido: Arc<dyn Motor>,
    fuerte: Arc<dyn Motor>,
    rotulos: (&'static str, &'static str),
    cliente: Cliente,
    contexto: Contexto,
    chat: String,
    elegido: OnceLock<Arc<dyn Motor>>,
}

impl MotorSegunJev {
    fn elegido(&self) -> &Arc<dyn Motor> {
        self.elegido.get_or_init(|| match jm::elegir(&self.cliente, &self.contexto) {
            Ok((ruta, _)) => {
                let (motor, rotulo) = match ruta {
                    Ruta::Fuerte => (&self.fuerte, self.rotulos.1),
                    Ruta::Rapido => (&self.rapido, self.rotulos.0),
                };
                apuntar(&self.chat, rotulo);
                motor.clone()
            }
            // Un fallo no elige nada: el de siempre.
            Err(_) => self.rapido.clone(),
        })
    }
}

impl Motor for MotorSegunJev {
    fn completar(
        &self,
        peticion: &Peticion,
        al_trozo: &mut dyn FnMut(&Trozo) -> Seguir,
    ) -> Result<Respuesta, pixpin_ia::ErrorIa> {
        self.elegido().completar(peticion, al_trozo)
    }

    fn catalogo_completo(&self) -> bool {
        self.rapido.catalogo_completo()
    }

    fn ve_imagenes(&self) -> bool {
        self.rapido.ve_imagenes()
    }

    fn a_la_vez(&self) -> usize {
        self.rapido.a_la_vez()
    }
}

/// Los ultimos mensajes de la conversacion, con quien los dijo.
pub fn recientes(conversacion: &[(bool, String)]) -> Vec<(String, String)> {
    let n = conversacion.len();
    conversacion
        .iter()
        .skip(n.saturating_sub(jm::RECIENTES))
        .map(|(del_usuario, t)| {
            (
                if *del_usuario { "usuario" } else { "asistente" }.to_string(),
                t.clone(),
            )
        })
        .collect()
}

/// **El motor de este pedido**: `motor` (el de los ajustes) o, con Jev, uno
/// que elige entre ese y el fuerte. `p` es el proveedor elegido; `pensar`,
/// si piensa este turno; `raiz`, la carpeta de datos (sus ajustes).
pub(crate) fn segun_jev(
    raiz: &Path,
    chat: &str,
    motor: Arc<dyn Motor>,
    p: Proveedor,
    pensar: bool,
    pedido: &str,
    conversacion: &[(bool, String)],
) -> Arc<dyn Motor> {
    if crate::asistente::turno::ia_es_orden_rapida(pedido.to_string()) {
        return motor;
    }
    let Some(cliente) = super::para(raiz, Funcion::Modelo) else {
        return motor;
    };
    let Some(clave) = nube::claves::leer(p) else {
        return motor;
    };
    let (modelo, nombre) = fuerte_de(p);
    let fuerte: Arc<dyn Motor> = Arc::new(MotorNube::nuevo(p, clave).con_modelo(modelo).pensando(pensar));
    Arc::new(MotorSegunJev {
        rapido: motor,
        fuerte,
        rotulos: (rapido_de(p), nombre),
        cliente,
        contexto: Contexto {
            pedido: pedido.to_string(),
            recientes: recientes(conversacion),
        },
        chat: chat.to_string(),
        elegido: OnceLock::new(),
    })
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn los_recientes_son_los_ultimos_con_quien() {
        let c: Vec<(bool, String)> = (1..=5).map(|i| (i % 2 == 1, format!("m{i}"))).collect();
        let r = recientes(&c);
        assert_eq!(r.len(), jm::RECIENTES);
        assert_eq!(r[0], ("usuario".to_string(), "m3".to_string()));
        assert_eq!(r[1].0, "asistente");
    }

    #[test]
    fn el_fuerte_de_cada_proveedor() {
        assert_eq!(fuerte_de(Proveedor::Claude).0, "claude-sonnet-5-5");
        assert_eq!(fuerte_de(Proveedor::DeepSeek).0, nube::deepseek::MODELO_PRO);
    }

    #[test]
    fn sin_jev_el_motor_es_el_mismo() {
        let m: Arc<dyn Motor> = Arc::new(pixpin_ia::motor::MotorGuionado::nuevo(vec![]));
        let r = segun_jev(&std::env::temp_dir(), "p", m.clone(), Proveedor::Claude, false, "explica la entropía", &[]);
        assert!(Arc::ptr_eq(&m, &r));
        assert!(jev_rotulo_del_modelo("p".into()).is_none());
    }

    #[test]
    fn el_rotulo_dura_un_rato() {
        apuntar("chat-de-prueba", "Claude Sonnet");
        assert_eq!(jev_rotulo_del_modelo("chat-de-prueba".into()).as_deref(), Some("Claude Sonnet · Jev"));
        assert!(jev_rotulo_del_modelo("otro".into()).is_none());
    }
}
