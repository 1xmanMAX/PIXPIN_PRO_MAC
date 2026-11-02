//! **El selector de color avanzado del lienzo** para Swift (Windows
//! 6fd2732a, f7599df9, 19f0c8c9): el cuadro de saturacion y brillo, la tira
//! de tonos, la de opacidad, el codigo de 3, 6 u 8 digitos, que marca se lee
//! encima de una muestra y los colores recientes. Las cuentas son las de
//! `pindesk_ui::selector_color` (las mismas de Windows); aqui solo se pasan
//! a los tipos del puente y se guarda lo que se recuerda.
//!
//! **Lo recordado va en `estado.toml`**, en los mismos campos de Windows
//! (`lienzo_colores_recientes`, `#rrggbb` con el ultimo delante, y
//! `lienzo_rugosidad`, 0 a 2): el mismo fichero, el mismo formato.
//!
//! **La opacidad no va dentro del color** (`selector_color` de Windows): los
//! dos digitos de mas del codigo van al campo `opacity` del elemento, y el
//! color se guarda siempre con seis.

use pindesk_motor2d::elemento::ColorRgba;
use pindesk_ui::selector_color::{self as sc, Hsv, Recientes};

use crate::editor_estilo::ColorEstilo;
use crate::Nucleo;

/// Un color en tono (0-360), saturacion (0-1) y brillo (0-1).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct ColorHsv {
    pub h: f32,
    pub s: f32,
    pub v: f32,
}

/// Un codigo escrito ya leido: el color (opaco) y, si traia los ocho
/// digitos, la opacidad de 0 a 1.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct CodigoDeColor {
    pub color: ColorEstilo,
    pub opacidad: Option<f32>,
}

/// Las flechas del selector abierto (Windows `tecla_del_selector`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FlechaDeColor {
    Izquierda,
    Derecha,
    Arriba,
    Abajo,
}

fn rgba(c: ColorEstilo) -> ColorRgba {
    let f = |v: f32| if v.is_finite() { v.clamp(0.0, 1.0) } else { 0.0 };
    ColorRgba {
        r: f(c.r),
        g: f(c.g),
        b: f(c.b),
        a: f(c.a),
    }
}

fn estilo(c: ColorRgba) -> ColorEstilo {
    ColorEstilo {
        r: c.r,
        g: c.g,
        b: c.b,
        a: c.a,
    }
}

fn a_hsv(h: ColorHsv) -> Hsv {
    Hsv {
        h: if h.h.is_finite() { h.h } else { 0.0 },
        s: if h.s.is_finite() { h.s } else { 0.0 },
        v: if h.v.is_finite() { h.v } else { 0.0 },
    }
}

fn del_hsv(h: Hsv) -> ColorHsv {
    ColorHsv {
        h: h.h,
        s: h.s,
        v: h.v,
    }
}

/// **El HSV de un color**, con el tono que se estaba eligiendo si el color
/// no tiene uno (un gris, el negro): sin el, la tira saltaria al rojo.
/// Sin color (transparente), el del blanco, como Windows.
#[uniffi::export]
pub fn hsv_de_color(color: Option<ColorEstilo>, tono_recordado: Option<f32>) -> ColorHsv {
    let c = color.map(rgba).unwrap_or(ColorRgba::opaco(1.0, 1.0, 1.0));
    del_hsv(Hsv::de(c).con_tono_de(tono_recordado.filter(|t| t.is_finite())))
}

/// El color opaco de un HSV.
#[uniffi::export]
pub fn color_de_hsv(valor: ColorHsv) -> ColorEstilo {
    estilo(a_hsv(valor).color())
}

/// El tono puro (saturacion y brillo enteros): el fondo del cuadro.
#[uniffi::export]
pub fn tono_puro(h: f32) -> ColorEstilo {
    estilo(sc::tono_puro(if h.is_finite() { h } else { 0.0 }))
}

/// **Donde se pulsa o arrastra en el cuadro** (0..1 a lo ancho y a lo alto,
/// 0 arriba, recortado): saturacion a lo ancho y brillo hacia arriba, con el
/// tono que ya habia.
#[uniffi::export]
pub fn hsv_del_cuadro(h: f32, x: f32, y: f32) -> ColorHsv {
    let f = |v: f32| if v.is_finite() { v.clamp(0.0, 1.0) } else { 0.0 };
    ColorHsv {
        h: if h.is_finite() { h.rem_euclid(360.0) } else { 0.0 },
        s: f(x),
        v: 1.0 - f(y),
    }
}

/// **El tono de la tira** donde se pulsa (0..1 a lo ancho): de 0 a casi 360
/// (360 seria otra vez el rojo del principio).
#[uniffi::export]
pub fn tono_de_la_tira(x: f32) -> f32 {
    let x = if x.is_finite() { x.clamp(0.0, 1.0) } else { 0.0 };
    (x * 360.0).min(359.9)
}

/// **La opacidad de la tira o de la barra** donde se pulsa (0..1): en pasos
/// del 1 %, los del campo `opacity` del fichero (Windows `Agarre::opacidad`).
#[uniffi::export]
pub fn opacidad_en_pasos(x: f32) -> f32 {
    let x = if x.is_finite() { x.clamp(0.0, 1.0) } else { 0.0 };
    (x * 100.0).round() / 100.0
}

/// **Las flechas con el selector abierto** (Windows `tecla_del_selector`):
/// izquierda y derecha mueven el tono (con ⌃, la saturacion), arriba y
/// abajo el brillo; con ⇧, el paso grande.
#[uniffi::export]
pub fn hsv_con_flecha(valor: ColorHsv, flecha: FlechaDeColor, grande: bool, saturacion: bool) -> ColorHsv {
    let mut h = a_hsv(valor);
    let signo = match flecha {
        FlechaDeColor::Derecha | FlechaDeColor::Arriba => 1.0,
        FlechaDeColor::Izquierda | FlechaDeColor::Abajo => -1.0,
    };
    let paso = |si: f32, no: f32| if grande { si } else { no };
    match flecha {
        FlechaDeColor::Izquierda | FlechaDeColor::Derecha if saturacion => {
            h.s = (h.s + signo * paso(0.1, 0.02)).clamp(0.0, 1.0);
        }
        FlechaDeColor::Izquierda | FlechaDeColor::Derecha => {
            h.h = (h.h + signo * paso(15.0, 2.0)).rem_euclid(360.0);
        }
        FlechaDeColor::Arriba | FlechaDeColor::Abajo => {
            h.v = (h.v + signo * paso(0.1, 0.02)).clamp(0.0, 1.0);
        }
    }
    del_hsv(h)
}

/// **RePag y AvPag con el selector abierto**: la opacidad de 5 en 5 (con
/// ⇧, de 10 en 10), en pasos del 1 %.
#[uniffi::export]
pub fn opacidad_con_tecla(antes: f32, sube: bool, grande: bool) -> f32 {
    let antes = if antes.is_finite() { antes } else { 1.0 };
    let paso = if grande { 0.1 } else { 0.05 };
    let o = if sube { antes + paso } else { antes - paso };
    (o.clamp(0.0, 1.0) * 100.0).round() / 100.0
}

/// **Un codigo escrito**: `#rgb`, `#rrggbb` o `#rrggbbaa`, con o sin la
/// almohadilla. `None` con cualquier otra cosa.
#[uniffi::export]
pub fn leer_codigo_de_color(escrito: String) -> Option<CodigoDeColor> {
    sc::leer_codigo(&escrito).map(|(c, a)| CodigoDeColor {
        color: estilo(c),
        opacidad: a,
    })
}

/// `rrggbb` en minusculas y sin almohadilla; con `aa` detras si la
/// opacidad no es entera (lo que ensena el campo del codigo).
#[uniffi::export]
pub fn escribir_codigo_de_color(color: ColorEstilo, opacidad: f32) -> String {
    sc::escribir_codigo(rgba(color), if opacidad.is_finite() { opacidad } else { 1.0 })
}

/// **Lo que se deja escribir en el campo del codigo** (`EdicionHex` de
/// Windows): solo digitos hexadecimales, en minusculas, sin la almohadilla
/// (se acepta y no se guarda) y hasta ocho.
#[uniffi::export]
pub fn limpiar_codigo_de_color(escrito: String) -> String {
    escrito
        .chars()
        .filter(char::is_ascii_hexdigit)
        .map(|c| c.to_ascii_lowercase())
        .take(8)
        .collect()
}

/// El contraste WCAG entre dos colores (de 1 a 21).
#[uniffi::export]
pub fn contraste_de_colores(a: ColorEstilo, b: ColorEstilo) -> f32 {
    sc::contraste(rgba(a), rgba(b))
}

/// **Si la marca encima de esta muestra va blanca** (la de mas contraste):
/// blanca sobre el azul de Excalidraw, oscura sobre el amarillo.
#[uniffi::export]
pub fn marca_clara_sobre(fondo: ColorEstilo) -> bool {
    sc::marca_clara(rgba(fondo))
}

/// **Si un color ya esta a la vista** en el panel o en su paleta (los
/// rapidos, las quince casillas con sus tonos y los papeles): lo que no, es
/// un color elegido a mano y va a los recientes.
#[uniffi::export]
pub fn color_es_de_la_paleta(color: ColorEstilo) -> bool {
    pindesk_ui::panel_lateral::es_de_la_paleta(rgba(color))
}

/// Cuantos recientes se recuerdan (una fila del desplegable).
#[uniffi::export]
pub fn cuantos_colores_recientes() -> u32 {
    Recientes::CUANTOS as u32
}

impl Nucleo {
    fn recientes(&self) -> Recientes {
        Recientes::de_codigos(
            &pindesk_store::estado::cargar(&self.ubicacion()).lienzo_colores_recientes,
        )
    }
}

#[uniffi::export]
impl Nucleo {
    /// **Los colores elegidos a mano hace poco** en el selector del lienzo,
    /// el ultimo delante (`lienzo_colores_recientes` de `estado.toml`).
    pub fn lienzo_colores_recientes(&self) -> Vec<ColorEstilo> {
        self.recientes().colores().iter().copied().map(estilo).collect()
    }

    /// **Apunta un color elegido a mano** (con el cuadro, la tira, el codigo
    /// o el cuentagotas) y devuelve los recientes como quedan. Uno de la
    /// paleta no se apunta: ya esta a la vista. Si no se puede guardar solo
    /// se pierde que se recuerde.
    pub fn apuntar_color_reciente(&self, color: ColorEstilo) -> Vec<ColorEstilo> {
        let c = rgba(color);
        let mut r = self.recientes();
        if !pindesk_ui::panel_lateral::es_de_la_paleta(c) && r.apuntar(c) {
            let u = self.ubicacion();
            let mut e = pindesk_store::estado::cargar(&u);
            e.lienzo_colores_recientes = r.codigos();
            let _ = pindesk_store::estado::guardar(&u, &e);
        }
        r.colores().iter().copied().map(estilo).collect()
    }

    /// **El ultimo «trazo a mano» elegido** (0 arquitecto, 1 artista, 2
    /// caricaturista); `None` si nunca se toco: entonces el de fabrica,
    /// artista.
    pub fn lienzo_rugosidad(&self) -> Option<u8> {
        pindesk_store::estado::cargar(&self.ubicacion())
            .lienzo_rugosidad
            .map(|v| v.min(2))
    }

    /// Recuerda el trazo a mano elegido (redondeado a 0, 1 o 2), sin tocar
    /// lo demas que se recuerda.
    pub fn recordar_lienzo_rugosidad(&self, valor: f32) {
        let v = if valor.is_finite() { valor.round().clamp(0.0, 2.0) as u8 } else { 1 };
        let u = self.ubicacion();
        let mut e = pindesk_store::estado::cargar(&u);
        if e.lienzo_rugosidad == Some(v) {
            return;
        }
        e.lienzo_rugosidad = Some(v);
        let _ = pindesk_store::estado::guardar(&u, &e);
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::Arc;

    fn hex(v: u32) -> ColorEstilo {
        let c = |s: u32| ((v >> s) & 0xff) as f32 / 255.0;
        ColorEstilo {
            r: c(16),
            g: c(8),
            b: c(0),
            a: 1.0,
        }
    }

    fn igual(a: ColorEstilo, b: ColorEstilo) -> bool {
        let k = |v: f32| (v * 255.0).round() as i32;
        k(a.r) == k(b.r) && k(a.g) == k(b.g) && k(a.b) == k(b.b)
    }

    fn raiz(etiqueta: &str) -> PathBuf {
        let r = std::env::temp_dir().join(format!(
            "pixpin-nucleo-selector-{etiqueta}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&r);
        std::fs::create_dir_all(&r).unwrap();
        r
    }

    fn nucleo(r: &Path) -> Arc<Nucleo> {
        Nucleo::abrir(r.display().to_string(), "Mac".into()).unwrap()
    }

    #[test]
    fn el_hsv_va_y_vuelve_y_un_gris_conserva_el_tono() {
        for v in [0x1e1e1e, 0xe03131, 0x1971c2, 0xffec99, 0x123456] {
            let c = hex(v);
            assert!(igual(color_de_hsv(hsv_de_color(Some(c), None)), c), "{v:06x}");
        }
        assert_eq!(hsv_de_color(Some(hex(0x808080)), Some(210.0)).h, 210.0);
        // Caso negativo: un color con tono propio no se lo deja quitar, y
        // sin color se mira el blanco.
        let azul = hsv_de_color(Some(hex(0x1971c2)), Some(10.0));
        assert!((azul.h - 10.0).abs() > 100.0);
        let blanco = hsv_de_color(None, None);
        assert_eq!((blanco.s, blanco.v), (0.0, 1.0));
        assert!(igual(tono_puro(240.0), hex(0x0000ff)));
    }

    #[test]
    fn el_cuadro_y_las_tiras_dan_su_valor_y_no_se_salen() {
        let c = hsv_del_cuadro(120.0, 1.0, 0.0);
        assert_eq!((c.h, c.s, c.v), (120.0, 1.0, 1.0));
        assert!(igual(color_de_hsv(c), hex(0x00ff00)));
        let fuera = hsv_del_cuadro(370.0, -3.0, 9.0);
        assert_eq!((fuera.s, fuera.v), (0.0, 0.0));
        assert!((fuera.h - 10.0).abs() < 1e-4);
        assert_eq!(tono_de_la_tira(0.5), 180.0);
        assert!(tono_de_la_tira(1.0) < 360.0, "el final no vuelve al rojo");
        assert_eq!(tono_de_la_tira(f32::NAN), 0.0);
        assert_eq!(opacidad_en_pasos(0.523), 0.52);
        assert_eq!(opacidad_en_pasos(2.0), 1.0);
        assert_eq!(opacidad_en_pasos(-1.0), 0.0);
    }

    #[test]
    fn las_teclas_mueven_tono_brillo_saturacion_y_opacidad() {
        let base = ColorHsv {
            h: 359.0,
            s: 0.5,
            v: 0.99,
        };
        let d = hsv_con_flecha(base, FlechaDeColor::Derecha, false, false);
        assert!((d.h - 1.0).abs() < 1e-3, "da la vuelta: {}", d.h);
        let s = hsv_con_flecha(base, FlechaDeColor::Izquierda, true, true);
        assert!((s.s - 0.4).abs() < 1e-5 && s.h == base.h);
        let v = hsv_con_flecha(base, FlechaDeColor::Arriba, false, false);
        assert_eq!(v.v, 1.0, "el brillo no pasa de entero");
        assert_eq!(opacidad_con_tecla(0.5, true, false), 0.55);
        assert_eq!(opacidad_con_tecla(0.5, false, true), 0.4);
        assert_eq!(opacidad_con_tecla(0.98, true, false), 1.0);
    }

    #[test]
    fn el_codigo_se_lee_se_escribe_y_se_limpia() {
        let l = leer_codigo_de_color("#1971c280".into()).unwrap();
        assert!(igual(l.color, hex(0x1971c2)));
        assert!((l.opacidad.unwrap() - 128.0 / 255.0).abs() < 1e-6);
        assert!(igual(leer_codigo_de_color("f0a".into()).unwrap().color, hex(0xff00aa)));
        assert_eq!(leer_codigo_de_color("#12345".into()), None);
        assert_eq!(escribir_codigo_de_color(hex(0x1e1e1e), 1.0), "1e1e1e");
        assert_eq!(escribir_codigo_de_color(hex(0x1e1e1e), 0.5), "1e1e1e80");
        assert_eq!(limpiar_codigo_de_color("#AbC-dEf 123zz".into()), "abcdef12");
        assert_eq!(limpiar_codigo_de_color("nada".into()), "ada");
    }

    #[test]
    fn la_marca_y_el_contraste_son_los_de_windows() {
        assert!(marca_clara_sobre(hex(0x1971c2)));
        assert!(!marca_clara_sobre(hex(0xffec99)));
        assert!((contraste_de_colores(hex(0), hex(0xffffff)) - 21.0).abs() < 0.01);
        assert!(color_es_de_la_paleta(hex(0x1e1e1e)));
        assert!(!color_es_de_la_paleta(hex(0x123456)));
    }

    #[test]
    fn los_recientes_y_el_trazo_a_mano_se_recuerdan_en_estado_toml() {
        let r = raiz("recientes");
        let n = nucleo(&r);
        assert!(n.lienzo_colores_recientes().is_empty());
        assert_eq!(n.lienzo_rugosidad(), None);
        // Uno de la paleta no se apunta.
        assert!(n.apuntar_color_reciente(hex(0x1e1e1e)).is_empty());
        n.apuntar_color_reciente(hex(0x123456));
        let ahora = n.apuntar_color_reciente(hex(0xabcdef));
        assert_eq!(ahora.len(), 2);
        assert!(igual(ahora[0], hex(0xabcdef)), "el ultimo delante");
        n.recordar_lienzo_rugosidad(1.8);
        // Lo mismo que lee Windows, en su fichero.
        let otro = nucleo(&r);
        let e = pindesk_store::estado::cargar(&otro.ubicacion());
        assert_eq!(e.lienzo_colores_recientes, vec!["#abcdef", "#123456"]);
        assert_eq!(e.lienzo_rugosidad, Some(2));
        assert_eq!(otro.lienzo_rugosidad(), Some(2));
        assert_eq!(otro.lienzo_colores_recientes().len(), 2);
        // Caso negativo: no se recortan los demas campos del estado.
        let mut e = pindesk_store::estado::cargar(&otro.ubicacion());
        e.figuras_de_noche = Some(true);
        pindesk_store::estado::guardar(&otro.ubicacion(), &e).unwrap();
        otro.recordar_lienzo_rugosidad(0.0);
        let e = pindesk_store::estado::cargar(&otro.ubicacion());
        assert_eq!(e.figuras_de_noche, Some(true));
        assert_eq!(e.lienzo_rugosidad, Some(0));
        let _ = std::fs::remove_dir_all(&r);
    }
}
