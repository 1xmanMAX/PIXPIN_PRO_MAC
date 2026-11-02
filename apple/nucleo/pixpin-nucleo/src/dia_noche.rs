//! **El boton ☀/☾ redondo** para Swift (Windows 5d46665c, bbc1a9bd): un
//! circulo con filete, con el sol de dia y la luna de noche, que dice el
//! modo PUESTO (como el del movil). Al cambiar, el icono viejo gira y se
//! apaga mientras el nuevo entra girando. Las cuentas son las de
//! `pindesk_ui::dia_noche`; Swift solo mide el tiempo y pinta.

use pindesk_ui::dia_noche as dn;

/// Un icono del boton en un momento: lo que se ve (0..1), lo que mide
/// (0..1) y lo girado (radianes).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct IconoDiaNoche {
    /// `true`: la luna; `false`: el sol.
    pub luna: bool,
    pub alfa: f32,
    pub tam: f32,
    pub giro: f32,
}

/// Los dos iconos en un momento del cambio: el que se va (si aun se ve) y
/// el que llega.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct PasoDiaNoche {
    pub sale: Option<IconoDiaNoche>,
    pub entra: IconoDiaNoche,
}

/// Lo que mide el boton y lo que dura el cambio (los del movil).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct MedidasDiaNoche {
    /// El lado del circulo (logicos).
    pub lado: f32,
    /// El icono de dentro (logicos).
    pub icono: f32,
    pub dura_ms: u64,
}

fn icono(t: dn::Trazo) -> IconoDiaNoche {
    IconoDiaNoche {
        luna: t.luna,
        alfa: t.alfa,
        tam: t.tam,
        giro: t.giro,
    }
}

/// **Los iconos con el modo `noche` ya puesto** y el cambio en `progreso`
/// (0 recien cambiado, 1 o mas, quieto).
#[uniffi::export]
pub fn paso_dia_noche(noche: bool, progreso: f32) -> PasoDiaNoche {
    let p = if progreso.is_finite() { progreso.clamp(0.0, 1.0) } else { 1.0 };
    let paso = dn::paso(noche, p);
    PasoDiaNoche {
        sale: paso.sale.map(icono),
        entra: icono(paso.entra),
    }
}

#[uniffi::export]
pub fn medidas_dia_noche() -> MedidasDiaNoche {
    MedidasDiaNoche {
        lado: dn::LADO as f32,
        icono: dn::ICONO as f32,
        dura_ms: dn::DURA_MS,
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn quieto_solo_se_ve_el_del_modo_puesto() {
        let p = paso_dia_noche(true, 1.0);
        assert!(p.sale.is_none());
        assert!(p.entra.luna);
        assert_eq!((p.entra.alfa, p.entra.tam, p.entra.giro), (1.0, 1.0, 0.0));
        // Caso negativo: un progreso raro cuenta como quieto o recien
        // empezado, nunca fuera de 0..1.
        assert!(paso_dia_noche(false, f32::NAN).sale.is_none());
        assert_eq!(paso_dia_noche(false, 7.0), paso_dia_noche(false, 1.0));
    }

    #[test]
    fn a_medio_cambio_se_ven_los_dos_girando_al_reves() {
        let p = paso_dia_noche(false, 0.5);
        let sale = p.sale.expect("la luna aun se ve");
        assert!(sale.luna && !p.entra.luna);
        assert!(sale.giro > 0.0 && p.entra.giro < 0.0);
        assert!(sale.alfa > 0.0 && sale.alfa < 1.0);
        let m = medidas_dia_noche();
        assert_eq!((m.lado, m.icono, m.dura_ms), (36.0, 20.0, 260));
    }
}
