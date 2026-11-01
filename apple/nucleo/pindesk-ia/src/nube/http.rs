//! **Un POST por HTTPS que se lee a trozos**, con WinHTTP (lo que ya trae
//! Windows).
//!
//! Por que WinHTTP y no un cliente de crates.io: PinDesk ya lo usa para subir
//! (`pindesk_shell::subir`) y para bajar modelos (`pindesk-voz`); trae el TLS
//! del sistema (con sus certificados y su proxy) y no anade ni un byte de
//! criptografia propia al ejecutable.
//!
//! Lo unico especial aqui es que la respuesta se entrega **a medida que
//! llega** (las API de la nube contestan con Server-Sent Events) y que
//! `al_trozo` puede pedir parar entre trozo y trozo.
//!
//! `http://` solo se acepta hacia `127.0.0.1`/`localhost`: es para el
//! servidor falso de las pruebas. Una clave nunca sale sin cifrar a la red.
//!
//! Lo de WinHTTP habla con el sistema operativo: cada `unsafe` lleva su
//! `// SAFETY:`.
//!
//! **Fuera de Windows** solo se habla `http://` con este mismo equipo, con
//! un cliente HTTP/1.1 minimo sobre `TcpStream` (el mismo lector que
//! `llama-server`, [`LectorHttp`]): sirve para las pruebas
//! con el servidor falso y para cualquier motor local. `https://` devuelve
//! un [`Fallo::Red`] claro mientras la app no instale su [`Transporte`]: en
//! Apple la nube la habla URLSession desde Swift (TLS, proxy y certificados
//! del sistema), sin meter un TLS propio en el ejecutable (§4bis del plan
//! de Apple). Con el transporte puesto ([`instalar_transporte`]), el resto
//! (Claude, DeepSeek, reintentos, «probar») es el mismo codigo que Windows.

#[cfg(windows)]
use std::ffi::c_void;
use std::time::Duration;

#[cfg(windows)]
use windows::Win32::Networking::WinHttp::{
    WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_FLAG_SECURE, WINHTTP_OPEN_REQUEST_FLAGS,
    WINHTTP_QUERY_CUSTOM, WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_QUERY_STATUS_CODE, WinHttpCloseHandle,
    WinHttpConnect, WinHttpOpen, WinHttpOpenRequest, WinHttpQueryHeaders, WinHttpReadData,
    WinHttpReceiveResponse, WinHttpSendRequest, WinHttpSetTimeouts,
};
#[cfg(windows)]
use windows::core::{HSTRING, PCWSTR, w};

use crate::motor::Seguir;

/// Un asa de WinHTTP que se cierra sola.
#[cfg(windows)]
struct Asa(*mut c_void);

#[cfg(windows)]
impl Drop for Asa {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: el asa la devolvio WinHTTP, es de este `Asa` y no se
            // ha cerrado antes.
            let _ = unsafe { WinHttpCloseHandle(self.0) };
        }
    }
}

/// Por que no salio.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Fallo {
    /// No se llego a hablar con el servidor (sin red, DNS, TLS, tiempo).
    Red(String),
    /// El servidor contesto con un codigo que no es 2xx. `cuerpo` es el
    /// principio de lo que dijo (su JSON de error).
    Http {
        codigo: u32,
        cuerpo: String,
        /// Lo que pidio esperar con `retry-after`, si lo dijo.
        esperar: Option<Duration>,
    },
}

/// Lo que se manda.
pub struct Pedido<'a> {
    pub url: &'a str,
    /// Cabeceras extra (la clave va aqui: nunca se escribe en un registro).
    pub cabeceras: Vec<(&'static str, String)>,
    pub cuerpo: &'a [u8],
}

/// Una direccion partida: si va cifrada, servidor, puerto y ruta.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Direccion {
    pub segura: bool,
    pub servidor: String,
    pub puerto: u16,
    pub ruta: String,
}

/// Parte `https://servidor[:puerto]/ruta`. `http://` solo hacia este mismo
/// equipo.
pub fn partir(url: &str) -> Option<Direccion> {
    let (segura, resto) = if let Some(r) = url.strip_prefix("https://") {
        (true, r)
    } else {
        (false, url.strip_prefix("http://")?)
    };
    let (anfitrion, ruta) = match resto.find('/') {
        Some(i) => (&resto[..i], &resto[i..]),
        None => (resto, "/"),
    };
    let (servidor, puerto) = match anfitrion.rsplit_once(':') {
        Some((s, p)) => (s, p.parse::<u16>().ok()?),
        None => (anfitrion, if segura { 443 } else { 80 }),
    };
    if servidor.is_empty() {
        return None;
    }
    if !segura && !matches!(servidor, "127.0.0.1" | "localhost") {
        return None;
    }
    Some(Direccion {
        segura,
        servidor: servidor.to_string(),
        puerto,
        ruta: ruta.to_string(),
    })
}

/// **Manda el POST** y entrega la respuesta a trozos. Bloquea: llamarlo
/// desde un hilo de fondo. Devuelve `Ok(true)` si `al_trozo` pidio parar.
#[cfg(windows)]
pub fn enviar(p: &Pedido, al_trozo: &mut dyn FnMut(&[u8]) -> Seguir) -> Result<bool, Fallo> {
    let d = partir(p.url).ok_or_else(|| Fallo::Red(format!("direccion no valida: {}", p.url)))?;
    let mut cabeceras =
        String::from("Content-Type: application/json\r\nAccept: text/event-stream\r\n");
    for (k, v) in &p.cabeceras {
        cabeceras.push_str(k);
        cabeceras.push_str(": ");
        cabeceras.push_str(v);
        cabeceras.push_str("\r\n");
    }
    let cabeceras = HSTRING::from(cabeceras);
    let error = |que: &str| {
        Fallo::Red(format!(
            "{que}: {}",
            windows::core::Error::from_thread().message()
        ))
    };
    if p.cuerpo.len() > u32::MAX as usize {
        return Err(Fallo::Red("la peticion es demasiado grande".into()));
    }
    // SAFETY: las cadenas son literales o `HSTRING` vivos durante cada
    // llamada; cada asa se envuelve en `Asa` en cuanto existe, asi que se
    // cierra en todos los caminos y en orden inverso. Los bufferes que se
    // pasan a WinHTTP viven mientras dura cada llamada, que es sincrona.
    unsafe {
        let local = !d.segura;
        let mut sesion = Asa(WinHttpOpen(
            w!("PixPin"),
            if local {
                WINHTTP_ACCESS_TYPE_NO_PROXY
            } else {
                WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
            },
            PCWSTR::null(),
            PCWSTR::null(),
            0,
        ));
        if sesion.0.is_null() && !local {
            sesion = Asa(WinHttpOpen(
                w!("PixPin"),
                WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                PCWSTR::null(),
                PCWSTR::null(),
                0,
            ));
        }
        if sesion.0.is_null() {
            return Err(error("sin conexion"));
        }
        // 20 s para conectar y mandar; hasta 3 min sin recibir nada (un
        // modelo que piensa mucho antes de escribir manda latidos, pero
        // mejor holgado).
        let _ = WinHttpSetTimeouts(sesion.0, 20_000, 20_000, 30_000, 180_000);
        let conexion = Asa(WinHttpConnect(
            sesion.0,
            &HSTRING::from(d.servidor.as_str()),
            d.puerto,
            0,
        ));
        if conexion.0.is_null() {
            return Err(error("no se pudo conectar"));
        }
        let peticion = Asa(WinHttpOpenRequest(
            conexion.0,
            w!("POST"),
            &HSTRING::from(d.ruta.as_str()),
            PCWSTR::null(),
            PCWSTR::null(),
            std::ptr::null(),
            WINHTTP_OPEN_REQUEST_FLAGS(if d.segura { WINHTTP_FLAG_SECURE.0 } else { 0 }),
        ));
        if peticion.0.is_null() {
            return Err(error("no se pudo preparar la peticion"));
        }
        WinHttpSendRequest(
            peticion.0,
            Some(&cabeceras),
            Some(p.cuerpo.as_ptr().cast()),
            p.cuerpo.len() as u32,
            p.cuerpo.len() as u32,
            0,
        )
        .map_err(|e| Fallo::Red(format!("no se pudo mandar: {}", e.message())))?;
        WinHttpReceiveResponse(peticion.0, std::ptr::null_mut())
            .map_err(|e| Fallo::Red(format!("el servidor no contesto: {}", e.message())))?;
        let mut codigo: u32 = 0;
        let mut largo = std::mem::size_of::<u32>() as u32;
        let _ = WinHttpQueryHeaders(
            peticion.0,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            PCWSTR::null(),
            Some((&mut codigo as *mut u32).cast()),
            &mut largo,
            std::ptr::null_mut(),
        );
        let mut buf = vec![0u8; 16 * 1024];
        if !(200..300).contains(&codigo) {
            let esperar = cabecera(peticion.0, "retry-after")
                .and_then(|s| s.trim().parse::<f64>().ok())
                .filter(|s| s.is_finite() && *s >= 0.0)
                .map(|s| Duration::from_secs_f64(s.min(120.0)));
            let mut cuerpo = Vec::new();
            loop {
                let mut n: u32 = 0;
                if WinHttpReadData(
                    peticion.0,
                    buf.as_mut_ptr().cast(),
                    buf.len() as u32,
                    &mut n,
                )
                .is_err()
                    || n == 0
                {
                    break;
                }
                cuerpo.extend_from_slice(&buf[..n as usize]);
                if cuerpo.len() > 64 * 1024 {
                    break;
                }
            }
            return Err(Fallo::Http {
                codigo,
                cuerpo: String::from_utf8_lossy(&cuerpo).into_owned(),
                esperar,
            });
        }
        loop {
            let mut n: u32 = 0;
            WinHttpReadData(
                peticion.0,
                buf.as_mut_ptr().cast(),
                buf.len() as u32,
                &mut n,
            )
            .map_err(|e| Fallo::Red(format!("se corto la respuesta: {}", e.message())))?;
            if n == 0 {
                return Ok(false);
            }
            if al_trozo(&buf[..n as usize]) == Seguir::Parar {
                return Ok(true);
            }
        }
    }
}

/// El valor de una cabecera de la respuesta, si esta.
///
/// # Safety
/// `peticion` tiene que ser un asa de peticion de WinHTTP viva que ya
/// recibio la respuesta.
#[cfg(windows)]
unsafe fn cabecera(peticion: *mut c_void, nombre: &str) -> Option<String> {
    let nombre = HSTRING::from(nombre);
    let mut buf = vec![0u16; 256];
    let mut largo = (buf.len() * 2) as u32;
    // SAFETY: el bufer vive durante la llamada y su tamano en bytes es el
    // que se pasa; el nombre es un `HSTRING` vivo.
    unsafe {
        WinHttpQueryHeaders(
            peticion,
            WINHTTP_QUERY_CUSTOM,
            &nombre,
            Some(buf.as_mut_ptr().cast()),
            &mut largo,
            std::ptr::null_mut(),
        )
        .ok()?;
    }
    let n = (largo as usize / 2).min(buf.len());
    Some(String::from_utf16_lossy(&buf[..n]))
}

/// **Manda el POST** (fuera de Windows): solo `http://` hacia este equipo.
/// Mismo contrato que el de WinHTTP: bloquea, entrega la respuesta a
/// trozos y devuelve `Ok(true)` si `al_trozo` pidio parar.
#[cfg(not(windows))]
pub fn enviar(p: &Pedido, al_trozo: &mut dyn FnMut(&[u8]) -> Seguir) -> Result<bool, Fallo> {
    use std::io::{Read, Write};
    use std::net::{TcpStream, ToSocketAddrs};

    let d = partir(p.url).ok_or_else(|| Fallo::Red(format!("direccion no valida: {}", p.url)))?;
    if d.segura {
        return match TRANSPORTE.get() {
            Some(t) => por_transporte(t.as_ref(), p, al_trozo),
            None => Err(Fallo::Red(
                "en este sistema el HTTPS lo hace la app (en Apple, URLSession desde Swift), no el nucleo".into(),
            )),
        };
    }
    let red = |que: &str, e: std::io::Error| Fallo::Red(format!("{que}: {e}"));
    let direccion = (d.servidor.as_str(), d.puerto)
        .to_socket_addrs()
        .map_err(|e| red("no se pudo conectar", e))?
        .next()
        .ok_or_else(|| Fallo::Red(format!("no se pudo conectar: {} sin direccion", d.servidor)))?;
    // Los mismos plazos que con WinHTTP: 20 s para conectar y mandar, hasta
    // 3 min sin recibir nada.
    let mut s = TcpStream::connect_timeout(&direccion, Duration::from_secs(20))
        .map_err(|e| red("no se pudo conectar", e))?;
    let _ = s.set_write_timeout(Some(Duration::from_secs(20)));
    let _ = s.set_read_timeout(Some(Duration::from_secs(180)));
    let mut cabeza = format!(
        "POST {} HTTP/1.1\r\nHost: {}:{}\r\nContent-Type: application/json\r\nAccept: text/event-stream\r\n\
         Content-Length: {}\r\nConnection: close\r\n",
        d.ruta,
        d.servidor,
        d.puerto,
        p.cuerpo.len()
    );
    for (k, v) in &p.cabeceras {
        cabeza.push_str(k);
        cabeza.push_str(": ");
        cabeza.push_str(v);
        cabeza.push_str("\r\n");
    }
    cabeza.push_str("\r\n");
    s.write_all(cabeza.as_bytes())
        .map_err(|e| red("no se pudo mandar", e))?;
    s.write_all(p.cuerpo)
        .map_err(|e| red("no se pudo mandar", e))?;

    let mut lector = LectorHttp::nuevo();
    let mut buf = vec![0u8; 16 * 1024];
    let mut error: Option<Vec<u8>> = None;
    loop {
        let n = s
            .read(&mut buf)
            .map_err(|e| red("se corto la respuesta", e))?;
        if n == 0 {
            break;
        }
        let cuerpo = lector
            .meter(&buf[..n])
            .map_err(|e| Fallo::Red(e.to_string()))?;
        let Some(codigo) = lector.estado else {
            continue;
        };
        if !(200..300).contains(&codigo) {
            let e = error.get_or_insert_with(Vec::new);
            e.extend_from_slice(&cuerpo);
            if e.len() > 64 * 1024 || lector.terminado {
                break;
            }
            continue;
        }
        if !cuerpo.is_empty() && al_trozo(&cuerpo) == Seguir::Parar {
            return Ok(true);
        }
        if lector.terminado {
            break;
        }
    }
    let Some(codigo) = lector.estado else {
        return Err(Fallo::Red("el servidor no contesto".into()));
    };
    if let Some(cuerpo) = error {
        let esperar = lector
            .cabecera("retry-after")
            .and_then(|s| s.trim().parse::<f64>().ok())
            .filter(|s| s.is_finite() && *s >= 0.0)
            .map(|s| Duration::from_secs_f64(s.min(120.0)));
        return Err(Fallo::Http {
            codigo: u32::from(codigo),
            cuerpo: String::from_utf8_lossy(&cuerpo).into_owned(),
            esperar,
        });
    }
    Ok(false)
}

/// Lo que el [`Transporte`] de la app va contando de la respuesta.
#[cfg(not(windows))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventoHttp<'a> {
    /// Llego la cabecera: el codigo y lo que pide esperar (`retry-after`).
    Estado {
        codigo: u32,
        esperar: Option<Duration>,
    },
    /// Un trozo del cuerpo, tal cual llega.
    Datos(&'a [u8]),
    /// La cabecera `Location` (la subida reanudable de Drive), si la hay;
    /// llega despues de `Estado` y antes de los datos.
    Ubicacion(&'a str),
    /// La cabecera `Content-Type`, si la hay ([`bajar_web`]); llega despues
    /// de `Estado` y antes de los datos.
    Tipo(&'a str),
}

/// **El HTTPS de la app** (fuera de Windows): en Apple, URLSession desde
/// Swift (`pixpin-nucleo`, `TransporteApp`). Manda el POST de `p` y va
/// contando la respuesta a `al_evento` (primero el estado, luego los
/// trozos); si `al_evento` dice [`Seguir::Parar`], corta la peticion.
/// `Err`: no se llego a hablar con el servidor (sin red, TLS, tiempo).
#[cfg(not(windows))]
pub trait Transporte: Send + Sync {
    fn enviar(
        &self,
        p: &Pedido,
        al_evento: &mut dyn FnMut(EventoHttp) -> Seguir,
    ) -> Result<(), String>;
    /// Una peticion cualquiera (GET, POST, PUT...) con solo las cabeceras
    /// de quien llama ([`pedir`], las conexiones del asistente).
    fn pedir(
        &self,
        _metodo: &str,
        _url: &str,
        _cabeceras: &[(&'static str, String)],
        _cuerpo: &[u8],
        _al_evento: &mut dyn FnMut(EventoHttp) -> Seguir,
    ) -> Result<(), String> {
        Err("este transporte solo sabe mandar el POST del asistente".into())
    }
    /// **Un GET a una pagina de internet** ([`bajar_web`]): sin cookies ni
    /// credenciales y **sin seguir redirecciones** (una 3xx vuelve con su
    /// `Location`), contando tambien el `Content-Type`.
    fn bajar(
        &self,
        _url: &str,
        _cabeceras: &[(&'static str, String)],
        _al_evento: &mut dyn FnMut(EventoHttp) -> Seguir,
    ) -> Result<(), String> {
        Err("este transporte aun no sabe bajar paginas web".into())
    }
}

#[cfg(not(windows))]
static TRANSPORTE: std::sync::OnceLock<Box<dyn Transporte>> = std::sync::OnceLock::new();

/// **Instala el HTTPS de la app** (una vez por proceso, al arrancar). Otra
/// vez da error y se queda el primero.
#[cfg(not(windows))]
pub fn instalar_transporte(t: Box<dyn Transporte>) -> Result<(), String> {
    TRANSPORTE
        .set(t)
        .map_err(|_| "el transporte HTTPS ya estaba instalado".to_string())
}

/// Si la app ya puso su HTTPS (sin el, la nube no se puede usar aqui).
#[cfg(not(windows))]
pub fn hay_transporte() -> bool {
    TRANSPORTE.get().is_some()
}

/// El POST por el transporte de la app, con el mismo contrato que el de
/// WinHTTP: los trozos solo si es 2xx; si no, el principio del cuerpo va en
/// [`Fallo::Http`].
#[cfg(not(windows))]
fn por_transporte(
    t: &dyn Transporte,
    p: &Pedido,
    al_trozo: &mut dyn FnMut(&[u8]) -> Seguir,
) -> Result<bool, Fallo> {
    let mut estado: Option<(u32, Option<Duration>)> = None;
    let mut error: Vec<u8> = Vec::new();
    let mut parado = false;
    let r = t.enviar(p, &mut |e| match e {
        EventoHttp::Estado { codigo, esperar } => {
            estado = Some((codigo, esperar));
            Seguir::Si
        }
        EventoHttp::Ubicacion(_) | EventoHttp::Tipo(_) => Seguir::Si,
        EventoHttp::Datos(b) => match estado {
            Some((c, _)) if (200..300).contains(&c) => {
                if b.is_empty() || al_trozo(b) == Seguir::Si {
                    Seguir::Si
                } else {
                    parado = true;
                    Seguir::Parar
                }
            }
            _ => {
                error.extend_from_slice(b);
                if error.len() > 64 * 1024 {
                    Seguir::Parar
                } else {
                    Seguir::Si
                }
            }
        },
    });
    if parado {
        return Ok(true);
    }
    // Un error de red tras un codigo malo: vale el codigo (dice mas).
    match (estado, r) {
        (Some((codigo, esperar)), _) if !(200..300).contains(&codigo) => Err(Fallo::Http {
            codigo,
            cuerpo: String::from_utf8_lossy(&error).into_owned(),
            esperar,
        }),
        (_, Err(e)) => Err(Fallo::Red(e)),
        (None, Ok(())) => Err(Fallo::Red("el servidor no contesto".into())),
        (Some(_), Ok(())) => Ok(false),
    }
}

/// Lo que contesto una peticion entera ([`pedir`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Respuesta {
    pub codigo: u32,
    pub cuerpo: Vec<u8>,
    /// La cabecera `Location` (la subida reanudable de Drive la usa).
    pub ubicacion: Option<String>,
}

/// **Una peticion cualquiera** (GET, POST, PUT...) leida entera, con las
/// cabeceras que diga quien llama (las conexiones del asistente: Google
/// Drive y su OAuth), el mismo contrato que el de WinHTTP de Windows: el
/// HTTPS por el transporte de la app, `http://` solo hacia este equipo;
/// una respuesta de mas de `limite` bytes se corta con error, y un codigo
/// que no es 2xx es [`Fallo::Http`]. Bloquea.
#[cfg(not(windows))]
pub fn pedir(
    metodo: &str,
    url: &str,
    cabeceras: &[(&'static str, String)],
    cuerpo: &[u8],
    limite: usize,
) -> Result<Respuesta, Fallo> {
    let d = partir(url).ok_or_else(|| Fallo::Red(format!("direccion no valida: {url}")))?;
    if !d.segura {
        return pedir_local(metodo, &d, cabeceras, cuerpo, limite);
    }
    let t = TRANSPORTE.get().ok_or_else(|| {
        Fallo::Red("en este sistema el HTTPS lo hace la app (en Apple, URLSession desde Swift), no el nucleo".into())
    })?;
    let mut estado: Option<(u32, Option<Duration>)> = None;
    let mut ubicacion = None;
    let mut todo = Vec::new();
    let mut grande = false;
    let r = t.pedir(metodo, url, cabeceras, cuerpo, &mut |e| match e {
        EventoHttp::Estado { codigo, esperar } => {
            estado = Some((codigo, esperar));
            Seguir::Si
        }
        EventoHttp::Ubicacion(u) => {
            ubicacion = Some(u.to_string());
            Seguir::Si
        }
        EventoHttp::Tipo(_) => Seguir::Si,
        EventoHttp::Datos(b) => {
            todo.extend_from_slice(b);
            if todo.len() > limite {
                grande = true;
                Seguir::Parar
            } else {
                Seguir::Si
            }
        }
    });
    terminar(
        estado,
        r.map_err(Fallo::Red),
        todo,
        ubicacion,
        grande,
        limite,
    )
}

#[cfg(not(windows))]
fn terminar(
    estado: Option<(u32, Option<Duration>)>,
    r: Result<(), Fallo>,
    cuerpo: Vec<u8>,
    ubicacion: Option<String>,
    grande: bool,
    limite: usize,
) -> Result<Respuesta, Fallo> {
    match (estado, r) {
        (Some((codigo, esperar)), _) if !(200..300).contains(&codigo) => {
            let mut c = cuerpo;
            c.truncate(64 * 1024);
            Err(Fallo::Http {
                codigo,
                cuerpo: String::from_utf8_lossy(&c).into_owned(),
                esperar,
            })
        }
        _ if grande => Err(Fallo::Red(format!(
            "la respuesta pasa de {} MB",
            (limite / (1024 * 1024)).max(1)
        ))),
        (_, Err(e)) => Err(e),
        (None, Ok(())) => Err(Fallo::Red("el servidor no contesto".into())),
        (Some((codigo, _)), Ok(())) => Ok(Respuesta {
            codigo,
            cuerpo,
            ubicacion,
        }),
    }
}

/// [`pedir`] hacia este equipo (`http://127.0.0.1`), por TCP a mano.
#[cfg(not(windows))]
fn pedir_local(
    metodo: &str,
    d: &Direccion,
    cabeceras: &[(&'static str, String)],
    cuerpo: &[u8],
    limite: usize,
) -> Result<Respuesta, Fallo> {
    use std::io::{Read, Write};
    use std::net::{TcpStream, ToSocketAddrs};

    let red = |que: &str, e: std::io::Error| Fallo::Red(format!("{que}: {e}"));
    let direccion = (d.servidor.as_str(), d.puerto)
        .to_socket_addrs()
        .map_err(|e| red("no se pudo conectar", e))?
        .next()
        .ok_or_else(|| Fallo::Red(format!("no se pudo conectar: {} sin direccion", d.servidor)))?;
    let mut s = TcpStream::connect_timeout(&direccion, Duration::from_secs(20))
        .map_err(|e| red("no se pudo conectar", e))?;
    let _ = s.set_write_timeout(Some(Duration::from_secs(20)));
    let _ = s.set_read_timeout(Some(Duration::from_secs(180)));
    let mut cabeza = format!(
        "{metodo} {} HTTP/1.1\r\nHost: {}:{}\r\nContent-Length: {}\r\nConnection: close\r\n",
        d.ruta,
        d.servidor,
        d.puerto,
        cuerpo.len()
    );
    for (k, v) in cabeceras {
        cabeza.push_str(k);
        cabeza.push_str(": ");
        cabeza.push_str(v);
        cabeza.push_str("\r\n");
    }
    cabeza.push_str("\r\n");
    s.write_all(cabeza.as_bytes())
        .map_err(|e| red("no se pudo mandar", e))?;
    s.write_all(cuerpo)
        .map_err(|e| red("no se pudo mandar", e))?;
    let mut lector = LectorHttp::nuevo();
    let mut buf = vec![0u8; 64 * 1024];
    let mut todo = Vec::new();
    let mut grande = false;
    loop {
        let n = s
            .read(&mut buf)
            .map_err(|e| red("se corto la respuesta", e))?;
        if n == 0 {
            break;
        }
        let trozo = lector
            .meter(&buf[..n])
            .map_err(|e| Fallo::Red(e.to_string()))?;
        todo.extend_from_slice(&trozo);
        if todo.len() > limite {
            grande = true;
            break;
        }
        if lector.terminado {
            break;
        }
    }
    let estado = lector.estado.map(|c| {
        let esperar = lector
            .cabecera("retry-after")
            .and_then(|s| s.trim().parse::<f64>().ok())
            .filter(|s| s.is_finite() && *s >= 0.0)
            .map(|s| Duration::from_secs_f64(s.min(120.0)));
        (u32::from(c), esperar)
    });
    let ubicacion = lector.cabecera("location").map(str::to_string);
    terminar(estado, Ok(()), todo, ubicacion, grande, limite)
}

/// Lo que contesto una pagina web ([`bajar_web`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RespuestaWeb {
    pub codigo: u32,
    pub cuerpo: Vec<u8>,
    /// La cabecera `Content-Type`.
    pub tipo: Option<String>,
    /// A donde manda una redireccion (3xx), sin seguirla.
    pub ubicacion: Option<String>,
}

/// Como se presenta PixPin a las paginas (el `AGENTE_WEB` de Windows, con
/// el Mac): como un navegador que dice quien es.
#[cfg(not(windows))]
const AGENTE_WEB: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) PixPinMax/1.0 (asistente; lee la pagina para el usuario)";

/// La cabecera con el plazo en segundos para el transporte de la app (no
/// sale a la red: Swift la usa de `timeoutInterval`).
#[cfg(not(windows))]
pub const CABECERA_PLAZO: &str = "X-PinDesk-Plazo";

/// **Un GET a una pagina cualquiera de internet** (el asistente con
/// DeepSeek que lee la web, `crate::web`), como el de WinHTTP de Windows:
/// sin cookies ni credenciales y **sin seguir redirecciones** (una 3xx
/// vuelve con su `ubicacion`: quien llama comprueba cada una con
/// `pindesk_paginas::direccion`), con un `plazo` para la respuesta entera;
/// mas de `limite` bytes, error. Un codigo que no es 2xx ni 3xx es
/// [`Fallo::Http`]. Fuera de Windows va por el transporte de la app
/// ([`Transporte::bajar`], URLSession en el Mac). Bloquea.
#[cfg(not(windows))]
pub fn bajar_web(
    url: &str,
    cabeceras: &[(&'static str, String)],
    limite: usize,
    plazo: Duration,
) -> Result<RespuestaWeb, Fallo> {
    let t = TRANSPORTE.get().ok_or_else(|| {
        Fallo::Red("en este sistema el HTTPS lo hace la app (en Apple, URLSession desde Swift), no el nucleo".into())
    })?;
    bajar_por(t.as_ref(), url, cabeceras, limite, plazo)
}

/// [`bajar_web`] por un transporte dado.
#[cfg(not(windows))]
fn bajar_por(
    t: &dyn Transporte,
    url: &str,
    cabeceras: &[(&'static str, String)],
    limite: usize,
    plazo: Duration,
) -> Result<RespuestaWeb, Fallo> {
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err(Fallo::Red(format!("direccion no valida: {url}")));
    }
    let mut cab: Vec<(&'static str, String)> = cabeceras.to_vec();
    if !cab
        .iter()
        .any(|(k, _)| k.eq_ignore_ascii_case("user-agent"))
    {
        cab.push(("User-Agent", AGENTE_WEB.to_string()));
    }
    cab.push((
        CABECERA_PLAZO,
        format!("{:.1}", plazo.as_secs_f64().max(1.0)),
    ));
    let empezo = std::time::Instant::now();
    let mut estado: Option<(u32, Option<Duration>)> = None;
    let (mut tipo, mut ubicacion) = (None, None);
    let mut todo = Vec::new();
    let (mut grande, mut tarde) = (false, false);
    let r = t.bajar(url, &cab, &mut |e| match e {
        EventoHttp::Estado { codigo, esperar } => {
            estado = Some((codigo, esperar));
            Seguir::Si
        }
        EventoHttp::Tipo(v) => {
            tipo = Some(v.to_string());
            Seguir::Si
        }
        EventoHttp::Ubicacion(v) => {
            ubicacion = Some(v.to_string());
            Seguir::Si
        }
        EventoHttp::Datos(b) => {
            todo.extend_from_slice(b);
            if todo.len() > limite {
                grande = true;
                Seguir::Parar
            } else if empezo.elapsed() > plazo {
                tarde = true;
                Seguir::Parar
            } else {
                Seguir::Si
            }
        }
    });
    if tarde {
        return Err(Fallo::Red(format!(
            "la pagina tarda demasiado (mas de {} s)",
            plazo.as_secs()
        )));
    }
    if grande {
        return Err(Fallo::Red(format!(
            "la pagina pasa de {} MB",
            (limite / (1024 * 1024)).max(1)
        )));
    }
    match (estado, r) {
        (Some((codigo, _)), _) if (200..400).contains(&codigo) => Ok(RespuestaWeb {
            codigo,
            cuerpo: todo,
            tipo,
            ubicacion,
        }),
        (Some((codigo, esperar)), _) => {
            todo.truncate(64 * 1024);
            Err(Fallo::Http {
                codigo,
                cuerpo: String::from_utf8_lossy(&todo).into_owned(),
                esperar,
            })
        }
        (None, Err(e)) => Err(Fallo::Red(e)),
        (None, Ok(())) => Err(Fallo::Red("el servidor no contesto".into())),
    }
}

// ---------------------------------------------------------------------------
// El protocolo HTTP/1.1 a mano (fuera de Windows): era de `servidor`, el
// motor local que Windows quito (f86732c); aqui lo usan las peticiones a
// este equipo (las pruebas).
/// La respuesta HTTP/1.1 por partes: la cabecera y luego el cuerpo, que
/// `llama-server` manda troceado (`Transfer-Encoding: chunked`).
/// El codigo de la primera linea de una respuesta (`HTTP/1.1 200 OK`).
#[cfg(not(windows))]
fn estado_http(cabecera: &[u8]) -> Option<u16> {
    let t = std::str::from_utf8(cabecera.get(..cabecera.len().min(32))?).ok()?;
    t.strip_prefix("HTTP/1.")?
        .get(2..)?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

#[cfg(not(windows))]
pub struct LectorHttp {
    pendiente: Vec<u8>,
    pub estado: Option<u16>,
    /// La cabecera de la respuesta tal cual (sin la linea en blanco final).
    pub cabeceras: String,
    troceado: bool,
    en_cuerpo: bool,
    /// Bytes que faltan del trozo actual (troceado).
    falta: usize,
    /// Falta el CRLF que cierra el trozo.
    cola: bool,
    pub terminado: bool,
}

#[cfg(not(windows))]
impl LectorHttp {
    pub fn nuevo() -> LectorHttp {
        LectorHttp {
            pendiente: Vec::new(),
            estado: None,
            cabeceras: String::new(),
            troceado: false,
            en_cuerpo: false,
            falta: 0,
            cola: false,
            terminado: false,
        }
    }

    /// Mete bytes y devuelve los del cuerpo que ya se pueden leer.
    pub fn meter(&mut self, bytes: &[u8]) -> Result<Vec<u8>, crate::ErrorIa> {
        self.pendiente.extend_from_slice(bytes);
        if !self.en_cuerpo {
            let Some(fin) = self.pendiente.windows(4).position(|v| v == b"\r\n\r\n") else {
                if self.pendiente.len() > 64 * 1024 {
                    return Err(crate::ErrorIa::Protocolo(
                        "cabecera HTTP interminable".into(),
                    ));
                }
                return Ok(Vec::new());
            };
            let cabecera = String::from_utf8_lossy(&self.pendiente[..fin]).to_string();
            self.pendiente.drain(..fin + 4);
            self.estado = estado_http(cabecera.as_bytes());
            if self.estado.is_none() {
                return Err(crate::ErrorIa::Protocolo("respuesta que no es HTTP".into()));
            }
            self.troceado = cabecera.lines().any(|l| {
                l.to_ascii_lowercase().starts_with("transfer-encoding:")
                    && l.to_ascii_lowercase().contains("chunked")
            });
            self.en_cuerpo = true;
            self.cabeceras = cabecera;
        }
        if !self.troceado {
            return Ok(std::mem::take(&mut self.pendiente));
        }
        let mut salida = Vec::new();
        loop {
            if self.terminado {
                self.pendiente.clear();
                break;
            }
            if self.cola {
                // Tras los datos de cada trozo va un «\r\n».
                if self.pendiente.len() < 2 {
                    break;
                }
                self.pendiente.drain(..2);
                self.cola = false;
            }
            if self.falta > 0 {
                let n = self.falta.min(self.pendiente.len());
                salida.extend(self.pendiente.drain(..n));
                self.falta -= n;
                if self.falta > 0 {
                    break;
                }
                self.cola = true;
                continue;
            }
            let Some(fin) = self.pendiente.windows(2).position(|v| v == b"\r\n") else {
                break;
            };
            let linea = String::from_utf8_lossy(&self.pendiente[..fin]).to_string();
            let tam = usize::from_str_radix(linea.split(';').next().unwrap_or("").trim(), 16)
                .map_err(|_| {
                    crate::ErrorIa::Protocolo(format!("trozo HTTP ilegible: {linea:.40}"))
                })?;
            self.pendiente.drain(..fin + 2);
            if tam == 0 {
                self.terminado = true;
                continue;
            }
            self.falta = tam;
        }
        Ok(salida)
    }
}

#[cfg(not(windows))]
impl LectorHttp {
    /// El valor de una cabecera de la respuesta (sin distinguir mayusculas).
    pub fn cabecera(&self, nombre: &str) -> Option<&str> {
        self.cabeceras.lines().skip(1).find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.trim().eq_ignore_ascii_case(nombre).then(|| v.trim())
        })
    }
}

#[cfg(not(windows))]
impl Default for LectorHttp {
    fn default() -> Self {
        LectorHttp::nuevo()
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn https_con_y_sin_puerto() {
        let d = partir("https://api.anthropic.com/v1/messages").unwrap();
        assert!(d.segura);
        assert_eq!(
            (d.servidor.as_str(), d.puerto, d.ruta.as_str()),
            ("api.anthropic.com", 443, "/v1/messages")
        );
        let d = partir("https://x.y:8443").unwrap();
        assert_eq!((d.puerto, d.ruta.as_str()), (8443, "/"));
    }

    /// Un transporte falso: contesta lo guionado sin salir a la red.
    #[cfg(not(windows))]
    struct Guion {
        codigo: u32,
        trozos: Vec<&'static str>,
        red: Option<&'static str>,
    }

    #[cfg(not(windows))]
    impl Transporte for Guion {
        fn enviar(
            &self,
            p: &Pedido,
            al_evento: &mut dyn FnMut(EventoHttp) -> Seguir,
        ) -> Result<(), String> {
            assert!(p.url.starts_with("https://"));
            if let Some(e) = self.red {
                return Err(e.into());
            }
            let esperar = (self.codigo == 429).then(|| Duration::from_secs(2));
            al_evento(EventoHttp::Estado {
                codigo: self.codigo,
                esperar,
            });
            for t in &self.trozos {
                if al_evento(EventoHttp::Datos(t.as_bytes())) == Seguir::Parar {
                    break;
                }
            }
            Ok(())
        }
    }

    /// Una pagina de mentira para [`bajar_por`]: su codigo, su tipo, su
    /// `Location` y su cuerpo; apunta las cabeceras que le llegaron.
    #[cfg(not(windows))]
    struct Pagina {
        codigo: u32,
        tipo: Option<&'static str>,
        ubicacion: Option<&'static str>,
        cuerpo: &'static str,
        vistas: std::sync::Mutex<Vec<(String, String)>>,
    }

    #[cfg(not(windows))]
    impl Transporte for Pagina {
        fn enviar(
            &self,
            _: &Pedido,
            _: &mut dyn FnMut(EventoHttp) -> Seguir,
        ) -> Result<(), String> {
            Err("no".into())
        }
        fn bajar(
            &self,
            _url: &str,
            cabeceras: &[(&'static str, String)],
            al_evento: &mut dyn FnMut(EventoHttp) -> Seguir,
        ) -> Result<(), String> {
            *self.vistas.lock().unwrap() = cabeceras
                .iter()
                .map(|(k, v)| (k.to_string(), v.clone()))
                .collect();
            al_evento(EventoHttp::Estado {
                codigo: self.codigo,
                esperar: None,
            });
            if let Some(t) = self.tipo {
                al_evento(EventoHttp::Tipo(t));
            }
            if let Some(u) = self.ubicacion {
                al_evento(EventoHttp::Ubicacion(u));
            }
            for trozo in self.cuerpo.as_bytes().chunks(4) {
                if al_evento(EventoHttp::Datos(trozo)) == Seguir::Parar {
                    break;
                }
            }
            Ok(())
        }
    }

    #[cfg(not(windows))]
    fn pagina(
        codigo: u32,
        tipo: Option<&'static str>,
        ubicacion: Option<&'static str>,
        cuerpo: &'static str,
    ) -> Pagina {
        Pagina {
            codigo,
            tipo,
            ubicacion,
            cuerpo,
            vistas: std::sync::Mutex::new(Vec::new()),
        }
    }

    #[cfg(not(windows))]
    #[test]
    fn bajar_una_pagina_trae_su_tipo_y_no_sigue_redirecciones() {
        let plazo = Duration::from_secs(20);
        let p = pagina(
            200,
            Some("text/html; charset=utf-8"),
            None,
            "<html>hola</html>",
        );
        let r = bajar_por(&p, "https://ejemplo.org/", &[], 1024, plazo).unwrap();
        assert_eq!(r.codigo, 200);
        assert_eq!(r.tipo.as_deref(), Some("text/html; charset=utf-8"));
        assert_eq!(r.cuerpo, b"<html>hola</html>");
        let vistas = p.vistas.lock().unwrap().clone();
        assert!(
            vistas
                .iter()
                .any(|(k, v)| k == "User-Agent" && v.contains("PixPinMax"))
        );
        assert!(
            vistas
                .iter()
                .any(|(k, v)| k == CABECERA_PLAZO && v == "20.0")
        );
        // Una redireccion vuelve con su `Location`, sin seguirla.
        let p = pagina(301, None, Some("http://192.168.1.1/"), "");
        let r = bajar_por(&p, "https://ejemplo.org/", &[], 1024, plazo).unwrap();
        assert_eq!(
            (r.codigo, r.ubicacion.as_deref()),
            (301, Some("http://192.168.1.1/"))
        );
        // Un 404 es un fallo HTTP; lo que pasa del limite, un error.
        let p = pagina(404, None, None, "no esta");
        assert!(matches!(
            bajar_por(&p, "https://ejemplo.org/x", &[], 1024, plazo),
            Err(Fallo::Http { codigo: 404, .. })
        ));
        let p = pagina(200, None, None, "muchos bytes de mas");
        assert!(matches!(
            bajar_por(&p, "https://ejemplo.org/", &[], 8, plazo),
            Err(Fallo::Red(_))
        ));
        assert!(bajar_por(&p, "file:///etc/passwd", &[], 8, plazo).is_err());
    }

    #[cfg(not(windows))]
    #[test]
    fn el_transporte_de_la_app_reparte_trozos_errores_y_cortes() {
        let p = Pedido {
            url: "https://api.x/v1",
            cabeceras: vec![],
            cuerpo: b"{}",
        };
        let mut oido = String::new();
        let bien = Guion {
            codigo: 200,
            trozos: vec!["data: a\n\n", "data: b\n\n"],
            red: None,
        };
        let r = por_transporte(&bien, &p, &mut |b| {
            oido.push_str(std::str::from_utf8(b).unwrap());
            Seguir::Si
        });
        assert_eq!(r, Ok(false));
        assert_eq!(oido, "data: a\n\ndata: b\n\n");
        // Parar en el primer trozo corta y lo dice.
        let mut n = 0;
        assert_eq!(
            por_transporte(&bien, &p, &mut |_| {
                n += 1;
                Seguir::Parar
            }),
            Ok(true)
        );
        assert_eq!(n, 1);
        // Un 429 trae su cuerpo y su espera, y no llega como trozo.
        let lleno = Guion {
            codigo: 429,
            trozos: vec![r#"{"error":{"message":"slow"}}"#],
            red: None,
        };
        match por_transporte(&lleno, &p, &mut |_| panic!("un error no es un trozo")) {
            Err(Fallo::Http {
                codigo: 429,
                cuerpo,
                esperar,
            }) => {
                assert!(cuerpo.contains("slow"));
                assert_eq!(esperar, Some(Duration::from_secs(2)));
            }
            otro => panic!("{otro:?}"),
        }
        // Sin red.
        let sin = Guion {
            codigo: 0,
            trozos: vec![],
            red: Some("sin conexion"),
        };
        assert_eq!(
            por_transporte(&sin, &p, &mut |_| Seguir::Si),
            Err(Fallo::Red("sin conexion".into()))
        );
    }

    #[test]
    fn http_sin_cifrar_solo_hacia_este_equipo() {
        assert!(partir("http://127.0.0.1:5555/v1/messages").is_some());
        assert!(partir("http://localhost:1/a").is_some());
        assert!(partir("http://api.deepseek.com/chat/completions").is_none());
        assert!(partir("ftp://x").is_none());
        assert!(partir("https://:44/").is_none());
        assert!(partir("https://x:noesnumero/").is_none());
    }
}
