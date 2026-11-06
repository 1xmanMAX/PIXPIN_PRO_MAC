//! **Emparejar con el codigo sin depender de mDNS** y el enlace
//! `pindesk://emparejar` del QR (Windows c08e08b1, dcf2b70b,
//! `docs/emparejar.md`).
//!
//! Unirse con el codigo solo buscaba por mDNS: si el anuncio no llegaba en
//! 25 s, «No apareció ningún aparato». Ahora, a la vez que mDNS (lo hace
//! Swift con `NWBrowser`), se pregunta por **la baliza**: con la clave que
//! sale del codigo, una baliza `PXB1` con la bandera `PREGUNTA` cada segundo
//! a la difusion general, a la de cada red y a la multidifusion (puerto
//! 47475) y, a los 4 s, a cada direccion de cada red. Los aparatos del grupo
//! (el PC y el movil) contestan con su baliza y su puerto TCP. Las cuentas
//! son las de `pindesk_sincro::emparejar`; aqui solo el socket y el reloj.
//!
//! El enlace del QR se lee con cualquier camara y lleva el codigo, las IPv4
//! de quien lo enseña, su puerto, su nombre y hasta cuando vale.

use std::net::{Ipv4Addr, SocketAddr};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use pindesk_sincro::{baliza, codigo, emparejar};

/// Una red de este Mac: su IPv4 y el largo de su prefijo (24 en
/// `255.255.255.0`). La saca Swift con `getifaddrs`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct RedLocal {
    pub ip: String,
    pub prefijo: u8,
}

/// Un aparato del grupo que contesto a la baliza: donde llamarle.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EncontradoPorBaliza {
    pub id: String,
    pub host: String,
    pub puerto: u16,
}

/// Lo que lleva el enlace `pindesk://emparejar` (o el `pixpin://` de antes).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EnlaceEmparejar {
    /// El codigo del grupo, limpio (diez signos).
    pub codigo: String,
    /// Las IPv4 de quien lo enseña, la preferida primero (como mucho cuatro).
    pub hosts: Vec<String>,
    pub puerto: u16,
    /// Su nombre («PinDesk Casa»), si lo dice.
    pub nombre: String,
}

fn ahora_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn interfaces(redes: &[RedLocal]) -> Vec<baliza::Interfaz> {
    redes
        .iter()
        .filter_map(|r| {
            let ip: Ipv4Addr = r.ip.trim().parse().ok()?;
            (!ip.is_loopback() && !ip.is_unspecified() && r.prefijo <= 32)
                .then_some(baliza::Interfaz { ip, prefijo: r.prefijo })
        })
        .collect()
}

/// **Busca al grupo del `codigo` por la baliza** durante `tope_ms` (25 000
/// como Windows): pregunta cada segundo y devuelve el primero que contesta.
/// `yo` es el id de este aparato (para no contestarse a si mismo) y
/// `puerto_tcp` el de su sincronizar (0 si no escucha). Bloquea: Swift lo
/// llama en su hilo, a la vez que busca por mDNS. `None` si nadie contesta o
/// no se pudo abrir el puerto.
#[uniffi::export]
pub fn buscar_al_grupo_por_la_baliza(
    codigo: String,
    yo: String,
    puerto_tcp: u16,
    redes: Vec<RedLocal>,
    tope_ms: u64,
) -> Option<EncontradoPorBaliza> {
    let clave = codigo::clave_de_grupo(&codigo);
    let rs = interfaces(&redes);
    // Desde el puerto de la baliza (la respuesta del grupo va a el); si esta
    // ocupado, desde cualquiera (la respuesta directa tambien llega).
    let oyente = baliza::Oyente::abrir(baliza::PUERTO_BALIZA, &rs)
        .or_else(|_| baliza::Oyente::abrir(0, &rs))
        .ok()?;
    let fin = Instant::now() + Duration::from_millis(tope_ms);
    let cada = Duration::from_millis(emparejar::CADA_PREGUNTA_MS as u64);
    let mut vuelta = 0u32;
    let mut secuencia = 0u32;
    let mut ultima: Option<Instant> = None;
    let mut buf = [0u8; baliza::TOPE];
    while Instant::now() < fin {
        if ultima.is_none_or(|t| t.elapsed() >= cada) {
            ultima = Some(Instant::now());
            secuencia = secuencia.wrapping_add(1);
            let p = emparejar::pregunta(&clave, &yo, puerto_tcp, ahora_ms(), secuencia);
            oyente.mandar(&p, &emparejar::destinos(&rs, vuelta), baliza::PUERTO_BALIZA);
            vuelta += 1;
        }
        if let Ok(Some((n, SocketAddr::V4(de)))) = oyente.oir(&mut buf)
            && let Some(e) = emparejar::respuesta(&buf[..n], *de.ip(), &clave, &yo)
        {
            return Some(EncontradoPorBaliza {
                id: e.id,
                host: e.host.to_string(),
                puerto: e.puerto,
            });
        }
    }
    None
}

/// **Lee un enlace `pindesk://emparejar`** (o `pixpin://emparejar`). `None`
/// si no es uno, le falta el codigo o ya caduco (diez minutos y cinco de
/// margen por los relojes).
#[uniffi::export]
pub fn leer_enlace_de_emparejar(texto: String) -> Option<EnlaceEmparejar> {
    let e = emparejar::Enlace::leer(&texto)?;
    if !e.vigente(ahora_ms()) {
        return None;
    }
    Some(EnlaceEmparejar {
        codigo: e.codigo,
        hosts: e.hosts.iter().map(Ipv4Addr::to_string).collect(),
        puerto: e.puerto,
        nombre: e.nombre,
    })
}

/// Si `texto` es un enlace de emparejar, aunque haya caducado (para decir
/// «Este QR ya no vale» en vez de otra cosa).
#[uniffi::export]
pub fn es_enlace_de_emparejar(texto: String) -> bool {
    emparejar::Enlace::leer(&texto).is_some()
}

/// **El enlace del QR de emparejar** de este Mac: el codigo, sus IPv4 de la
/// red local (solo las privadas, como mucho cuatro), su puerto y su nombre;
/// vale diez minutos desde ahora.
#[uniffi::export]
pub fn enlace_de_emparejar(codigo: String, ips: Vec<String>, puerto: u16, nombre: String) -> String {
    let ips: Vec<Ipv4Addr> = ips.iter().filter_map(|i| i.trim().parse().ok()).collect();
    emparejar::Enlace {
        codigo,
        hosts: emparejar::direcciones_para_el_enlace(&ips),
        puerto,
        nombre,
        expira: Some(ahora_ms() + emparejar::VIGENCIA_QR_MS),
    }
    .texto()
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn el_enlace_va_y_vuelve_y_solo_lleva_ips_de_la_red_local() {
        let t = enlace_de_emparejar(
            "k7q2m-9xmpa".into(),
            vec!["192.168.1.20".into(), "8.8.8.8".into(), "10.0.0.5".into()],
            47474,
            "PinDesk Casa".into(),
        );
        assert!(t.starts_with("pindesk://emparejar?v=1&c=K7Q2M9XMPA&h=192.168.1.20,10.0.0.5&p=47474"), "{t}");
        let e = leer_enlace_de_emparejar(t.clone()).unwrap();
        assert_eq!(e.codigo, "K7Q2M9XMPA");
        assert_eq!(e.hosts, vec!["192.168.1.20", "10.0.0.5"]);
        assert_eq!(e.puerto, 47474);
        assert_eq!(e.nombre, "PinDesk Casa");
        assert!(es_enlace_de_emparejar(t));
    }

    #[test]
    fn un_enlace_caducado_o_ajeno_no_vale() {
        // Caducado hace una hora (mas que el margen de cinco minutos).
        let viejo = format!("pindesk://emparejar?v=1&c=K7Q2M9XMPA&e={}", ahora_ms() - 3_600_000);
        assert!(leer_enlace_de_emparejar(viejo.clone()).is_none());
        assert!(es_enlace_de_emparejar(viejo), "es de emparejar, aunque ya no valga");
        // El de antes tambien se lee.
        assert!(leer_enlace_de_emparejar("pixpin://emparejar?c=K7Q2M9XMPA".into()).is_some());
        // Caso negativo: otro enlace o sin codigo.
        assert!(leer_enlace_de_emparejar("pindesk://abrir?c=K7Q2M9XMPA".into()).is_none());
        assert!(leer_enlace_de_emparejar("pindesk://emparejar?v=1".into()).is_none());
        assert!(!es_enlace_de_emparejar("https://ejemplo.com".into()));
    }

    #[test]
    fn sin_nadie_que_conteste_la_busqueda_acaba_a_su_hora() {
        let antes = Instant::now();
        let r = buscar_al_grupo_por_la_baliza(
            "K7Q2M9XMPA".into(),
            "yo-de-prueba".into(),
            0,
            vec![RedLocal { ip: "127.0.0.1".into(), prefijo: 8 }],
            400,
        );
        assert!(r.is_none());
        assert!(antes.elapsed() < Duration::from_secs(3));
    }

    #[test]
    fn las_redes_raras_no_entran() {
        let rs = interfaces(&[
            RedLocal { ip: "192.168.1.20".into(), prefijo: 24 },
            RedLocal { ip: "127.0.0.1".into(), prefijo: 8 },
            RedLocal { ip: "no-es-ip".into(), prefijo: 24 },
            RedLocal { ip: "10.0.0.5".into(), prefijo: 40 },
        ]);
        assert_eq!(rs.len(), 1);
        assert_eq!(rs[0].ip, Ipv4Addr::new(192, 168, 1, 20));
    }
}
