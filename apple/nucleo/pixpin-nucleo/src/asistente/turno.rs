//! **Un turno del asistente con los ajustes de `[asistente]`**, como el de
//! Windows (`apps/pixpin/src/asistente/{turno,nube,motor,acciones}.rs`).
//!
//! - **Quien contesta** ([`ia_que_motor`]): `motor = "claude" | "deepseek"`
//!   es la nube (Claude Haiku 5.5 o DeepSeek V4.1 Flash, los modelos que
//!   fija `pixpin_ia::nube`) con la clave del Llavero y, si
//!   `respaldo_local`, el local detras ([`MotorConRespaldo`]); vacio o
//!   `local` es el modelo bajado (`modelo`: Qwen3.5 2B u 0.8B; con
//!   `mejor_vista` y una foto que mirar, Gemma 4 E2B si esta bajado) o, si
//!   no hay, el `llama-server` del usuario. Foundation Models no pasa por
//!   aqui: lo decide Swift (`ModeloAsistente`).
//! - **Pensar** (`pensar`): lo de los ajustes o, en automatico, solo las
//!   tareas complejas (`pixpin_ia::complejidad`), con la vuelta de planear,
//!   la hoja de trabajo de la conversacion y el reinicio del contexto al
//!   70 % (`buscar_historial` para lo viejo).
//! - **Las herramientas**: la nube recibe el catalogo entero (sin lo que el
//!   Mac aun no hace: editar el lienzo, figuras guardadas, hoja→lienzo,
//!   anotar documentos, las acciones de documentos y las del chat; eso es
//!   E1); el local, las pocas que vienen a cuento (`seleccion`). El camino
//!   rapido (`pixpin_ia::rapido`) hace las ordenes simples sin modelo.
//! - **Lo que hace cada herramienta** ([`EjecutorDelMac`]): dibujar y
//!   calcar juntan los elementos del lienzo; las acciones de la app
//!   (tareas, notas, ventanas...) son pedidos del protocolo
//!   (`docs/protocolo-pedidos.md`) que hace Swift ([`AppIa::pedido`]), con
//!   las tareas resueltas por su nombre contra las listas de verdad
//!   (`pixpin_ia::tareas::hacer`) y la pregunta de «¿seguro?» en la burbuja
//!   ([`AppIa::confirmar`]); leer un PDF o una foto adjunta es Vision o
//!   PDFKit desde Swift ([`AppIa::leer_texto`]); `buscar_en_mis_cosas`
//!   busca en los documentos y chats del usuario ([`documentos`]), con
//!   permiso si contesta la nube (`documentos_a_la_nube`), y sus citas
//!   vuelven en [`RespuestaIa::citas`].

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use pixpin_ia::acciones::AccionApp;
use pixpin_ia::agente::{self, Ejecutor, Evento, Opciones};
use pixpin_ia::contexto::{self, Fuente};
use pixpin_ia::fechas::{self, Momento};
use pixpin_ia::herramientas::{Herramienta, Llamada};
use pixpin_ia::hoja_trabajo::{HojaDeTrabajo, ResumenDelTurno};
use pixpin_ia::modelos::GEMMA4_E2B;
use pixpin_ia::motor::{Mensaje, Motor, Seguir};
use pixpin_ia::nube::{MotorConRespaldo, MotorNube, Proveedor, claves};
use pixpin_ia::pensar::Plan;
use pixpin_ia::tareas::{Chat, Fijas, FuenteTareas, VistaLista, VistaTarea};
use serde_json::Value;

use super::local;
use super::documentos::{self, LectorDelMac};
use super::{CitaIa, CorteIa, HerramientaUsada, LlamaDelUsuario, MensajeIa, OyenteIa, RespuestaIa, Tanda};
use crate::{ErrorNucleo, Nucleo};

/// La ventana que se mide con Claude o DeepSeek (la de Windows,
/// `pensado::VENTANA_NUBE`): les cabe mucho mas, pero cada token se paga
/// en cada vuelta.
pub const VENTANA_NUBE: u32 = 64_000;

/// Cuantos mensajes de antes se mandan, y cuanto de cada uno (Windows).
const ULTIMOS: usize = 12;
const LARGO: usize = 1500;

/// Lo que se le devuelve al modelo de un texto leido (OCR, PDF).
const LEIDO_PARA_EL_MODELO: usize = 6000;

/// **Los ajustes `[asistente]`** que usa el turno (Swift los lee con
/// `Nucleo::ajustes`), mas donde viven los modelos y el puerto del
/// `llama-server` del usuario.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AjustesIa {
    /// `""`/`local`, `claude` o `deepseek`.
    pub motor: String,
    /// El modelo local (`qwen3.5-2b`, `qwen3.5-0.8b`; vacio: el 2B).
    pub modelo: String,
    /// `None`: automatico.
    pub pensar: Option<bool>,
    pub respaldo_local: bool,
    pub mejor_vista: bool,
    /// `""` preguntar, `si`, `no`. `buscar_en_mis_cosas` lo lee (y lo
    /// guarda al preguntar) de la carpeta de datos; aqui va para saberlo.
    pub documentos_a_la_nube: String,
    /// La carpeta de los modelos bajados.
    pub carpeta_modelos: String,
    /// El puerto del `llama-server` propio del usuario (8080).
    pub puerto_usuario: u16,
}

/// **Quien contestaria ahora.**
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum MotorIa {
    /// Claude o DeepSeek. `con_clave`: si hay clave en el Llavero.
    Nube { proveedor: String, nombre: String, modelo: String, con_clave: bool },
    /// El modelo bajado, con el `llama-server` de PixPin.
    Descargado { modelo: String, nombre: String },
    /// Un `llama-server` que arranco el usuario.
    Usuario { puerto: u16 },
    /// Ninguno local (Swift prueba Foundation Models).
    Ninguno,
}

/// La eleccion de los ajustes: un proveedor de la nube o el local.
fn proveedor(a: &AjustesIa) -> Option<Proveedor> {
    Proveedor::por_id(&a.motor)
}

/// El local que hay: el modelo de los ajustes si esta bajado, o el
/// servidor del usuario si contesta.
fn local_que_hay(a: &AjustesIa) -> MotorIa {
    let raiz = Path::new(&a.carpeta_modelos);
    let m = local::modelo_elegido(&a.modelo);
    if !a.carpeta_modelos.is_empty() && local::listo(raiz, &m) {
        return MotorIa::Descargado {
            modelo: m.id.into(),
            nombre: m.nombre.into(),
        };
    }
    if a.puerto_usuario != 0 && pixpin_ia::servidor::salud(a.puerto_usuario) {
        return MotorIa::Usuario { puerto: a.puerto_usuario };
    }
    MotorIa::Ninguno
}

/// **Quien contestaria con estos ajustes.** Mira el disco y, si hace falta,
/// hace un `GET /health` local (≤ 300 ms): fuera del hilo principal.
#[uniffi::export]
pub fn ia_que_motor(ajustes: AjustesIa) -> MotorIa {
    match proveedor(&ajustes) {
        Some(p) => MotorIa::Nube {
            proveedor: p.id().into(),
            nombre: p.nombre().into(),
            modelo: p.modelo().into(),
            con_clave: claves::leer(p).is_some(),
        },
        None => local_que_hay(&ajustes),
    }
}

/// **«Probar»** la clave guardada de un proveedor: una llamada minima (unos
/// pocos tokens). `Ok` con la frase para ensenar; el error, en palabras.
/// Es una peticion de red: fuera del hilo principal.
#[uniffi::export]
pub fn ia_probar_clave(proveedor_id: String) -> Result<String, ErrorNucleo> {
    let p = Proveedor::por_id(&proveedor_id).ok_or_else(|| ErrorNucleo::Argumento {
        detalle: format!("proveedor desconocido: {proveedor_id:?}"),
    })?;
    let clave = claves::leer(p).ok_or_else(|| ErrorNucleo::Asistente {
        detalle: format!("no hay clave de {} guardada", p.nombre()),
    })?;
    pixpin_ia::nube::probar(p, &clave).map_err(|detalle| ErrorNucleo::Asistente { detalle })
}

/// Una foto para que la mire el modelo (ya reducida por Swift a ~768 px).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FotoIa {
    pub bytes: Vec<u8>,
    /// `image/png`, `image/jpeg`.
    pub mime: String,
}

/// Un fichero adjunto a la conversacion (lo que se puede leer o calcar).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AdjuntoIa {
    /// Como lo ve el usuario (y como lo nombra el modelo).
    pub nombre: String,
    pub ruta: String,
}

/// **Lo que se le pide** en un turno.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PeticionIa {
    /// Lo dicho antes, del mas antiguo al mas nuevo (solo texto).
    pub historial: Vec<MensajeIa>,
    pub pedido: String,
    pub foto: Option<FotoIa>,
    /// Todos los adjuntos de la conversacion, el ultimo al final.
    pub adjuntos: Vec<AdjuntoIa>,
    /// La hoja de trabajo de la conversacion (JSON de
    /// `HojaDeTrabajo::a_json`), o vacio la primera vez.
    pub hoja: String,
    /// El huso de quien pregunta (ms que se suman a UTC para la hora
    /// local): «mañana a las 10».
    pub desfase_ms: i64,
}

/// Un rango de paginas, de 1 en adelante, ambos incluidos.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct RangoPaginas {
    pub desde: u32,
    pub hasta: u32,
}

/// **Las manos del asistente en la app**: lo implementa Swift. Se le llama
/// desde el hilo del turno (no el principal) y puede esperar.
#[uniffi::export(foreign)]
pub trait AppIa: Send + Sync {
    /// Pregunta al usuario (en la burbuja, con «Sí» y «No») y espera.
    /// `true`: si. Sin respuesta (parado, ventana cerrada) es un no.
    fn confirmar(&self, pregunta: String) -> bool;
    /// Hace un pedido del protocolo (`{"pixpin":1,"accion":...}`), como si
    /// llegara de `pixpinmax://`. `None`: hecho; si no, el motivo.
    fn pedido(&self, json: String) -> Option<String>;
    /// El texto de un PDF o una imagen (la capa de texto o Vision). `paginas`
    /// vacio: todas.
    fn leer_texto(&self, ruta: String, paginas: Vec<RangoPaginas>) -> Result<String, ErrorNucleo>;
}

/// Lo que el Mac aun no hace (E1: el lienzo abierto, las figuras, las
/// acciones sobre documentos y las del chat): no se le ofrece al modelo.
fn el_mac_lo_hace(nombre: &str) -> bool {
    use pixpin_ia::acciones;
    !(nombre == pixpin_ia::figuras::NOMBRE
        || nombre == pixpin_ia::hoja::NOMBRE
        || nombre == pixpin_ia::anotacion::NOMBRE
        || acciones::es_en_el_chat(nombre)
        || pixpin_ia::acciones_documentos::es_de_documentos(nombre)
        || pixpin_ia::edicion::herramientas().iter().any(|h| h.nombre == nombre))
}

fn es_imagen(ruta: &str) -> bool {
    Path::new(ruta)
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase)
        .is_some_and(|e| matches!(e.as_str(), "png" | "jpg" | "jpeg" | "bmp" | "gif" | "webp" | "tif" | "tiff" | "heic"))
}

/// Si el pedido es «copia/dibuja esto» con una imagen: solo calcar
/// (Windows, `acciones::es_para_calcar`).
fn es_para_calcar(pedido: &str, con_imagen: bool) -> bool {
    let q = pixpin_ia::acciones::normalizar(pedido);
    let palabras: Vec<&str> = q.split(|c: char| !c.is_alphanumeric()).filter(|p| !p.is_empty()).collect();
    con_imagen
        && pixpin_ia::seleccion::pide_la_imagen(&palabras)
        && !pixpin_ia::seleccion::pide_una_tabla(&palabras)
        && !pixpin_ia::seleccion::pide_pegar_o_recortar(&palabras)
}

/// **Las herramientas de este turno.**
pub(crate) fn herramientas_del_turno(pedido: &str, con_imagen: bool, adjuntos: bool, nube: bool) -> Vec<Herramienta> {
    let mut h = if nube && !es_para_calcar(pedido, con_imagen) {
        pixpin_ia::herramientas::catalogo()
    } else {
        pixpin_ia::seleccion::para_el_pedido(pedido, con_imagen)
    };
    if adjuntos && !es_para_calcar(pedido, con_imagen) && !h.iter().any(|x| x.nombre == pixpin_ia::herramientas::OCR) {
        h.extend(
            pixpin_ia::herramientas::catalogo_base()
                .into_iter()
                .filter(|x| x.nombre == pixpin_ia::herramientas::OCR),
        );
    }
    h.retain(|x| el_mac_lo_hace(&x.nombre));
    h
}

/// **Un turno con los ajustes**: elige el motor, piensa si toca, usa las
/// herramientas y las acciones de la app y va contando lo que pasa a
/// `oyente` (en tandas) hasta acabar o hasta que `corte` lo pare.
/// `nucleo`: la carpeta de datos (para las tareas por su nombre); sin ella
/// las tareas solo se pueden apuntar en el Inbox.
#[uniffi::export]
pub fn ia_turno(
    ajustes: AjustesIa,
    peticion: PeticionIa,
    nucleo: Option<Arc<Nucleo>>,
    app: Arc<dyn AppIa>,
    oyente: Arc<dyn OyenteIa>,
    corte: Arc<CorteIa>,
) -> Result<RespuestaIa, ErrorNucleo> {
    let pedido = peticion.pedido.trim().to_string();
    if pedido.is_empty() {
        return Err(ErrorNucleo::Argumento {
            detalle: "el pedido esta vacio".into(),
        });
    }
    let con_foto = peticion.foto.is_some();
    let (motor, nombre, nube) = motor_del_turno(&ajustes, &pedido, con_foto)?;
    // En la nube lo apaga `MotorNube::pensando`; al local se lo dicen las
    // opciones del turno.
    let pensar = pixpin_ia::complejidad::decidir(ajustes.pensar, &pedido);
    let entorno = Entorno {
        nombre,
        nube,
        pensar,
        ventana: if nube { VENTANA_NUBE } else { pixpin_ia::servidor::CONTEXTO },
        cada: Duration::from_millis(super::CADA_TANDA_MS),
    };
    let mut ejecutor = EjecutorDelMac::nuevo(peticion.adjuntos.clone(), peticion.desfase_ms)
        .con_app(app)
        .con_nucleo(nucleo)
        .en_la_nube(nube);
    turno_con(motor.as_ref(), &entorno, peticion, &mut ejecutor, oyente.as_ref(), &corte)
}

/// El motor de este turno, su nombre y si es de la nube.
fn motor_del_turno(a: &AjustesIa, pedido: &str, con_foto: bool) -> Result<(Arc<dyn Motor>, String, bool), ErrorNucleo> {
    let raiz = PathBuf::from(&a.carpeta_modelos);
    // El local de este turno (Gemma si toca mirar una foto y esta bajado).
    let local_para = |pedido: &str| -> Option<(Arc<dyn Motor>, String)> {
        if a.mejor_vista && pixpin_ia::seleccion::pide_mejor_vista(pedido, con_foto) && local::listo(&raiz, &GEMMA4_E2B) {
            return local::del_proceso(&raiz, &GEMMA4_E2B).map(|m| (m, GEMMA4_E2B.nombre.to_string()));
        }
        match local_que_hay(a) {
            MotorIa::Descargado { .. } => {
                let m = local::modelo_elegido(&a.modelo);
                local::del_proceso(&raiz, &m).map(|x| (x, m.nombre.to_string()))
            }
            MotorIa::Usuario { puerto } => Some((Arc::new(LlamaDelUsuario { puerto }) as Arc<dyn Motor>, format!("llama-server (127.0.0.1:{puerto})"))),
            _ => None,
        }
    };
    match proveedor(a) {
        Some(p) => {
            let clave = claves::leer(p).ok_or_else(|| ErrorNucleo::Asistente {
                detalle: format!("Falta la clave de {}: pégala en Ajustes → Asistente (se saca en {}).", p.nombre(), p.pagina_de_claves()),
            })?;
            if !pixpin_ia::nube::http::hay_transporte() {
                return Err(ErrorNucleo::Asistente {
                    detalle: format!("No hay conexion con {} desde esta app (falta el HTTPS del sistema).", p.nombre()),
                });
            }
            let pensar = pixpin_ia::complejidad::decidir(a.pensar, pedido);
            let nube: Arc<dyn Motor> = Arc::new(MotorNube::nuevo(p, clave).pensando(pensar));
            let respaldo = if a.respaldo_local { local_para(pedido).map(|(m, _)| m) } else { None };
            Ok((Arc::new(MotorConRespaldo::nuevo(nube, respaldo, p.nombre())), p.nombre().to_string(), true))
        }
        None => local_para(pedido).map(|(m, n)| (m, n, false)).ok_or_else(|| ErrorNucleo::Asistente {
            detalle: "No hay modelo local: bájalo desde la ventana del asistente o elige Claude o DeepSeek en Ajustes → Asistente.".into(),
        }),
    }
}

/// Como va el turno (lo que no es la peticion).
pub(crate) struct Entorno {
    pub nombre: String,
    pub nube: bool,
    pub pensar: bool,
    pub ventana: u32,
    pub cada: Duration,
}

/// Lo que se va juntando de los eventos (Windows, `turno::Recogido`).
#[derive(Default)]
struct Recogido {
    pensamiento: String,
    segundos: Option<f32>,
    plan: Option<Plan>,
    herramientas: Vec<String>,
    usadas: Vec<HerramientaUsada>,
    reinicio: bool,
}

/// **El turno con cualquier motor** (las pruebas usan uno guionado).
pub(crate) fn turno_con(
    motor: &dyn Motor,
    entorno: &Entorno,
    peticion: PeticionIa,
    ejecutor: &mut EjecutorDelMac,
    oyente: &dyn OyenteIa,
    corte: &CorteIa,
) -> Result<RespuestaIa, ErrorNucleo> {
    let pedido = peticion.pedido.trim().to_string();
    let vacia = |hoja: String| RespuestaIa {
        texto: String::new(),
        herramientas: Vec::new(),
        lienzo: None,
        pensamiento: String::new(),
        segundos_pensando: None,
        motor: entorno.nombre.clone(),
        hoja,
        citas: Vec::new(),
    };
    if corte.cortado() {
        return Ok(vacia(peticion.hoja));
    }
    let mut hoja = serde_json::from_str::<Value>(&peticion.hoja)
        .ok()
        .and_then(|v| HojaDeTrabajo::de_json(&v).ok())
        .unwrap_or_default();
    let con_imagen = peticion.foto.is_some() || peticion.adjuntos.iter().any(|a| es_imagen(&a.ruta));
    let herramientas = herramientas_del_turno(&pedido, con_imagen, !peticion.adjuntos.is_empty(), entorno.nube);

    // La conversacion: desde el ultimo reinicio, los ultimos, recortados.
    let anteriores: Vec<(bool, String)> = peticion
        .historial
        .iter()
        .filter(|m| !m.texto.trim().is_empty())
        .map(|m| (m.del_usuario, m.texto.chars().take(LARGO).collect::<String>()))
        .collect();
    let anteriores = &anteriores[anteriores.len().saturating_sub(ULTIMOS)..];
    let fuentes: Vec<Fuente> = anteriores
        .iter()
        .enumerate()
        .map(|(i, (u, t))| Fuente {
            etiqueta: format!("#{} {}", i + 1, if *u { "usuario" } else { "asistente" }),
            texto: t.clone(),
        })
        .collect();
    let nuevo = match &peticion.foto {
        Some(f) => Mensaje::usuario_con_imagen(pedido.clone(), f.bytes.clone(), &f.mime),
        None => Mensaje::usuario(pedido.clone()),
    };
    let sistema = contexto::sistema_con_hoja(&agente::instrucciones(), &hoja, None);
    let mut con_buscar = herramientas.clone();
    con_buscar.push(contexto::herramienta_buscar());
    let preparado = contexto::preparar(sistema, anteriores, nuevo, &con_buscar, entorno.ventana, contexto::RESERVA_RESPUESTA);
    if preparado.reiniciado {
        hoja.reinicios += 1;
    }
    let mut historial = preparado.historial;

    let buscar = |c: &str| contexto::buscar(&fuentes, c, 3);
    let todas: Vec<Herramienta> = pixpin_ia::herramientas::catalogo()
        .into_iter()
        .filter(|h| el_mac_lo_hace(&h.nombre) && (entorno.nube || !pixpin_ia::acciones::es_solo_nube(&h.nombre)))
        .collect();
    let ahora = Momento::de_ms_locales(crate::ahora_ms() + peticion.desfase_ms);
    let opciones = Opciones {
        planificar: entorno.pensar,
        pensar: entorno.pensar,
        hoja: Some(&hoja),
        ventana: entorno.ventana,
        buscar: (preparado.reiniciado || hoja.reinicios > 0).then_some(&buscar as &dyn Fn(&str) -> String),
        ampliar: Some(&todas[..]),
        rapido: Some(ahora),
        ojos: false,
        revisar: 0,
    };

    let mut tanda = Tanda::nueva(entorno.cada);
    let mut recogido = Recogido::default();
    let resultado = agente::turno_con(motor, &mut historial, &herramientas, ejecutor, &opciones, &mut |e| {
        match &e {
            Evento::Texto(t) => {
                if let Some(t) = tanda.meter(t) {
                    oyente.texto(t);
                }
            }
            Evento::Pensando(t) => {
                recogido.pensamiento.push_str(t);
                oyente.pensando(t.clone());
            }
            Evento::PensoListo { segundos } => *recogido.segundos.get_or_insert(0.0) += segundos,
            Evento::Peticion(p) => recogido.plan = Some(p.clone()),
            Evento::Reinicio { .. } => recogido.reinicio = true,
            Evento::Llamando(n) => {
                if let Some(t) = tanda.soltar() {
                    oyente.texto(t);
                }
                oyente.llamando(n.clone());
            }
            Evento::Resultado { nombre, ok, texto } => {
                if let Some(t) = tanda.soltar() {
                    oyente.texto(t);
                }
                let usada = HerramientaUsada {
                    nombre: nombre.clone(),
                    ok: *ok,
                    resumen: texto.clone(),
                };
                if *ok {
                    recogido.herramientas.push(nombre.clone());
                }
                recogido.usadas.push(usada.clone());
                oyente.herramienta(usada);
            }
            _ => {}
        }
        if corte.cortado() { Seguir::Parar } else { Seguir::Si }
    });
    if let Some(t) = tanda.soltar() {
        oyente.texto(t);
    }
    let fin = resultado.map_err(|e| ErrorNucleo::Asistente {
        detalle: agente::para_el_usuario(&e),
    })?;
    // La hoja reescrita con lo que entendio y lo que paso.
    let plan = recogido.plan.unwrap_or_else(|| Plan::por_omision(&pedido));
    let incompleto = fin.cortado || fin.texto.starts_with("No he sabido") || fin.texto.starts_with("Hecho en parte");
    hoja.reescribir(
        &plan,
        &ResumenDelTurno {
            herramientas: recogido.herramientas,
            respuesta: fin.texto.clone(),
            incompleto,
            pensamiento: recogido.pensamiento.clone(),
        },
    );
    let lienzo = ejecutor.lienzo();
    let citas = ejecutor
        .citas
        .citadas(&fin.texto)
        .into_iter()
        .map(|c| CitaIa {
            numero: c.numero as u32,
            titulo: c.titulo(),
            pedido: c.pedido().to_string(),
        })
        .collect();
    Ok(RespuestaIa {
        citas,
        texto: fin.texto,
        herramientas: recogido.usadas,
        lienzo,
        segundos_pensando: recogido.segundos.filter(|_| !recogido.pensamiento.trim().is_empty()),
        pensamiento: recogido.pensamiento,
        motor: entorno.nombre.clone(),
        hoja: hoja.a_json().to_string(),
    })
}

// ---------------------------------------------------------------------------
// El ejecutor

/// **Lo que hace cada herramienta en el Mac.**
pub(crate) struct EjecutorDelMac {
    elementos: Vec<Value>,
    semilla: u64,
    adjuntos: Vec<AdjuntoIa>,
    desfase_ms: i64,
    app: Option<Arc<dyn AppIa>>,
    nucleo: Option<Arc<Nucleo>>,
    /// Si contesta la nube: buscar en los documentos pide permiso.
    nube: bool,
    /// Lo citado de los documentos en el turno.
    pub(crate) citas: pixpin_ia::documentos::Citas,
}

impl EjecutorDelMac {
    pub(crate) fn nuevo(adjuntos: Vec<AdjuntoIa>, desfase_ms: i64) -> EjecutorDelMac {
        EjecutorDelMac {
            elementos: Vec::new(),
            semilla: 0,
            adjuntos,
            desfase_ms,
            app: None,
            nucleo: None,
            nube: false,
            citas: Default::default(),
        }
    }

    pub(crate) fn en_la_nube(mut self, nube: bool) -> EjecutorDelMac {
        self.nube = nube;
        self
    }

    /// **Busca en los documentos del usuario.** Con la nube, solo si lo
    /// permite (se pregunta la primera vez).
    fn buscar(&mut self, p: &pixpin_ia::documentos::PeticionBusqueda) -> Result<String, String> {
        let nucleo = self.nucleo.clone().ok_or("aqui no hay documentos en los que buscar")?;
        if self.nube {
            let app = self.app.clone();
            let confirmar = |q: &str| app.as_ref().is_some_and(|x| x.confirmar(q.to_string()));
            if !documentos::permiso_nube(Some(&nucleo), &confirmar) {
                return Err(documentos::SIN_PERMISO_NUBE.into());
            }
        }
        let raiz = nucleo.ruta().to_path_buf();
        let lector = LectorDelMac {
            raiz: raiz.clone(),
            app: self.app.clone(),
        };
        let (hallazgos, aviso) = documentos::buscar(&raiz, p, &lector);
        Ok(self.citas.anadir(&p.consulta, hallazgos, aviso.as_deref()))
    }

    pub(crate) fn con_app(mut self, app: Arc<dyn AppIa>) -> EjecutorDelMac {
        self.app = Some(app);
        self
    }

    pub(crate) fn con_nucleo(mut self, nucleo: Option<Arc<Nucleo>>) -> EjecutorDelMac {
        self.nucleo = nucleo;
        self
    }

    /// Lo dibujado en el turno, como un `.excalidraw` entero.
    pub(crate) fn lienzo(&mut self) -> Option<String> {
        (!self.elementos.is_empty()).then(|| pixpin_ia::lienzo::documento(std::mem::take(&mut self.elementos)))
    }

    /// Donde empieza lo siguiente: debajo de lo de antes, para no pisarse.
    fn origen(&self) -> (f64, f64) {
        if self.elementos.is_empty() {
            return (0.0, 0.0);
        }
        let abajo = self
            .elementos
            .iter()
            .filter_map(|e| Some(e["y"].as_f64()? + e["height"].as_f64().unwrap_or(0.0)))
            .fold(0.0_f64, f64::max);
        (0.0, abajo + 40.0)
    }

    fn poner(&mut self, nuevos: Vec<Value>) -> String {
        let n = nuevos.len();
        self.elementos.extend(nuevos);
        format!("dibujadas {n} figuras")
    }

    /// El adjunto que se pide: por nombre (sin mayusculas, vale un trozo) o,
    /// sin nombre, el ultimo (Windows, `ocr::elegir`).
    fn elegir(&self, nombre: Option<&str>, solo_imagenes: bool) -> Result<&AdjuntoIa, String> {
        let lista: Vec<&AdjuntoIa> = self.adjuntos.iter().filter(|a| !solo_imagenes || es_imagen(&a.ruta)).collect();
        let Some(ultimo) = lista.last() else {
            return Err(if solo_imagenes {
                "no hay ninguna imagen adjunta; pide al usuario que adjunte la foto".into()
            } else {
                "no hay ningun PDF ni imagen adjunto en esta conversacion; pide al usuario que lo adjunte".into()
            });
        };
        let Some(nombre) = nombre.map(str::trim).filter(|n| !n.is_empty()) else {
            return Ok(ultimo);
        };
        let buscado = nombre.to_lowercase();
        lista
            .iter()
            .rev()
            .find(|a| a.nombre.to_lowercase() == buscado)
            .or_else(|| lista.iter().rev().find(|a| a.nombre.to_lowercase().contains(&buscado)))
            .copied()
            // Un nombre que no esta no es motivo para no calcar (Windows).
            .or(if solo_imagenes { Some(*ultimo) } else { None })
            .ok_or_else(|| {
                let hay: Vec<&str> = lista.iter().map(|a| a.nombre.as_str()).collect();
                format!("no hay ningun adjunto llamado «{nombre}»; hay: {}", hay.join(", "))
            })
    }

    fn calcar(&mut self, p: &pixpin_ia::calcar::Parametros) -> Result<String, String> {
        let ruta = PathBuf::from(&self.elegir(p.imagen.as_deref(), true)?.ruta);
        let img = pixpin_codec::imagen::cargar(&ruta).map_err(|e| format!("no se pudo abrir la imagen: {e}"))?;
        let c = pixpin_ia::calcar::calcar(&img.pixeles, img.ancho, img.alto, p);
        self.semilla += 1;
        let els = pixpin_ia::lienzo::elementos_de_calcado(&c, self.origen(), self.semilla);
        if els.is_empty() {
            return Err("la imagen no tiene formas que calcar (esta en blanco o casi)".into());
        }
        Ok(self.poner(els))
    }

    fn leer(&self, p: &pixpin_ia::herramientas::PeticionOcr) -> Result<String, String> {
        let a = self.elegir(p.archivo.as_deref(), false)?;
        let app = self.app.as_ref().ok_or("aqui no se pueden leer adjuntos")?;
        let paginas = p.paginas.iter().map(|&(desde, hasta)| RangoPaginas { desde, hasta }).collect();
        let texto = app.leer_texto(a.ruta.clone(), paginas).map_err(|e| e.to_string())?;
        if texto.trim().is_empty() {
            return Err(format!("{} no tiene texto que se pueda leer", a.nombre));
        }
        Ok(recortar(&texto, LEIDO_PARA_EL_MODELO))
    }

    fn accion(&self, a: &AccionApp) -> Result<String, String> {
        let app = self.app.clone();
        let confirmar = |q: &str| app.as_ref().is_some_and(|x| x.confirmar(q.to_string()));
        let mut mandar = |p: &Value| -> Result<(), String> {
            match app.as_ref() {
                Some(x) => x.pedido(p.to_string()).map_or(Ok(()), Err),
                None => Err("aqui no se pueden hacer acciones de la app".into()),
            }
        };
        let ahora = Momento::de_ms_locales(crate::ahora_ms() + self.desfase_ms);
        match &self.nucleo {
            Some(n) => {
                let fuente = FuenteDelMac {
                    nucleo: n.clone(),
                    desfase_ms: self.desfase_ms,
                    ahora,
                };
                pixpin_ia::tareas::hacer(a, &fuente, &confirmar, &mut mandar)
            }
            None if a.es_consulta() || !a.por_resolver.is_empty() => Err("no puedo leer las listas de tareas desde aqui".into()),
            None => {
                let fijas = Fijas {
                    ahora: Some(ahora),
                    ..Default::default()
                };
                pixpin_ia::tareas::hacer(a, &fijas, &confirmar, &mut mandar)
            }
        }
    }
}

impl Ejecutor for EjecutorDelMac {
    fn ejecutar(&mut self, llamada: &Llamada) -> Result<String, String> {
        match llamada {
            l if l.dibuja() => {
                self.semilla += 1;
                let nuevos = pixpin_ia::lienzo::elementos(l, self.origen(), self.semilla);
                Ok(self.poner(nuevos))
            }
            Llamada::Calcar(p) => self.calcar(p),
            Llamada::Ocr(p) => self.leer(p),
            Llamada::Ayuda(pregunta) => Ok(pixpin_ia::conocimiento::responder(pregunta)),
            Llamada::Buscar(p) => self.buscar(p),
            Llamada::App(a) if el_mac_lo_hace(a.herramienta) => self.accion(a),
            otra => Err(format!("{} aun no se puede hacer en PixPin para Mac", otra.nombre())),
        }
    }
}

/// Recorta a `n` letras diciendolo.
fn recortar(texto: &str, n: usize) -> String {
    if texto.chars().count() <= n {
        return texto.to_string();
    }
    let mut s: String = texto.chars().take(n).collect();
    s.push_str("\n[…recortado]");
    s
}

/// **Las tareas del usuario, para el asistente**: las listas de todos los
/// chats como las ve la ventana de Tareas (`Nucleo::tareas`) y los chats.
struct FuenteDelMac {
    nucleo: Arc<Nucleo>,
    desfase_ms: i64,
    ahora: Momento,
}

impl FuenteTareas for FuenteDelMac {
    fn listas(&self) -> Vec<VistaLista> {
        let Ok(listas) = self.nucleo.tareas(self.desfase_ms) else { return Vec::new() };
        listas
            .into_iter()
            .map(|l| VistaLista {
                proyecto: l.chat,
                chat: l.nombre_chat,
                guardados: l.guardados,
                codigo: l.mensaje,
                titulo: l.titulo,
                cuando: l.cuando,
                tareas: l
                    .tareas
                    .into_iter()
                    .map(|t| VistaTarea {
                        indice: t.indice as usize,
                        texto: t.texto.trim().to_string(),
                        hecha: t.hecha,
                        creada: t.creada.as_deref().and_then(dia_de),
                        vence: t.recuerda.map(Momento::de_ms_locales),
                    })
                    .collect(),
            })
            .collect()
    }

    fn chats(&self) -> Vec<Chat> {
        pixpin_proyecto::almacen::Indice::leer_si_esta(self.nucleo.ruta())
            .map(|i| {
                i.proyectos
                    .iter()
                    .map(|f| Chat {
                        id: f.id.clone(),
                        nombre: f.nombre.clone(),
                        guardados: f.es_guardados(),
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn ahora(&self) -> Momento {
        self.ahora
    }
}

/// `AAAA-MM-DD` en dias desde 1970.
fn dia_de(s: &str) -> Option<i64> {
    let mut p = s.trim().splitn(3, '-').map(|x| x.parse::<i64>().ok());
    let (y, m, d) = (p.next()??, p.next()??, p.next()??);
    fechas::existe(y, m, d).then(|| fechas::dias_de(y, m, d))
}

#[cfg(test)]
mod pruebas;
