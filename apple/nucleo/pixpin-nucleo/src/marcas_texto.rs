//! **Marcar el texto leyendo** en los lectores del Mac (Windows a5b3c24,
//! a4fd8c8 y 9d2e2b1, 1-nov-2026): resaltar, raya ondulada, subrayar,
//! tachar y tapar lo elegido en un PDF, un Word o un PowerPoint (PDFKit) y
//! en el visor de Word, libros y paginas (el reflujado), con la misma
//! barrita que Windows.
//!
//! Aqui solo queda lo que Swift no tiene que saber: las figuras, los
//! colores y el grupo son los del motor (`pindesk_motor2d::marcas_texto`),
//! la barrita la dispone `pindesk_ui::barra_marcar` y cada visor pone las
//! cajas de lo elegido **en las unidades de su tinta** (las de la hoja, 1400
//! de ancho, o las del documento reflujado).
//!
//! # Donde van (igual que Windows, para que sincronice)
//!
//! **No hay fichero nuevo** (§3.9 de `docs/sincronizar-marcos-vistas-y-tinta.md`):
//! cada marca es dibujo normal de la capa de su hoja (`hoja-<n>.excalidraw`
//! de `<doc>.pixpin-anotado/`, o `anot-<uid>-p<n>` de un adjunto) o de la
//! del documento reflujado, con el grupo `marca-texto-<ms>`. Se guarda con
//! el mismo [`EditorLienzo`] que la tinta, asi que viaja, se exporta y se
//! imprime como cualquier trazo.

use pindesk_motor2d::Escena;
use pindesk_motor2d::marcas_texto::{self as mt, Marca};
use pindesk_ui::barra_marcar::{self, BotonMarcar};

use crate::editor::EditorLienzo;

/// Una caja `[x0, y0, x1, y1]` en las unidades de la tinta (Y hacia abajo)
/// o, para la barrita, en puntos de la ventana desde arriba a la izquierda.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct CajaDeMarca {
    pub x0: f32,
    pub y0: f32,
    pub x1: f32,
    pub y1: f32,
}

impl CajaDeMarca {
    fn arreglo(self) -> [f32; 4] {
        [self.x0, self.y0, self.x1, self.y1]
    }

    fn de(c: [f32; 4]) -> Self {
        CajaDeMarca {
            x0: c[0],
            y0: c[1],
            x1: c[2],
            y1: c[3],
        }
    }
}

/// Un boton de la barrita ya colocado.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BotonDeMarcar {
    pub x: f32,
    pub y: f32,
    pub ancho: f32,
    pub alto: f32,
    /// `copiar`, `color`, `quitar` o el nombre de la marca (`resaltar`,
    /// `ondulada`, `subrayar`, `tachar`, `tapar`: `Marca::nombre`).
    pub que: String,
    /// El color de `colores_de_marcar` (solo con `que == "color"`).
    pub color: u8,
    /// La clave de su nombre en `main.ftl` (vacia en los colores).
    pub clave: String,
}

/// **La barrita de marcar** dispuesta junto a lo elegido.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BarritaDeMarcar {
    pub x: f32,
    pub y: f32,
    pub ancho: f32,
    pub alto: f32,
    /// La x de la raya que separa copiar de lo demas.
    pub raya: f32,
    pub botones: Vec<BotonDeMarcar>,
}

/// La clave del nombre de cada boton, la de Windows (`lector::nombre_de_marcar`).
fn clave_de(b: BotonMarcar) -> &'static str {
    match b {
        BotonMarcar::Copiar => "pin-v2-marca-copiar",
        BotonMarcar::Color(_) => "",
        BotonMarcar::Marcar(Marca::Resaltar) => "pin-v2-marca-resaltar",
        BotonMarcar::Marcar(Marca::Ondulada) => "pin-v2-marca-ondulada",
        BotonMarcar::Marcar(Marca::Subrayar) => "pin-v2-marca-subrayar",
        BotonMarcar::Marcar(Marca::Tachar) => "pin-v2-marca-tachar",
        BotonMarcar::Marcar(Marca::Tapar) => "pin-v2-marca-tapar",
        BotonMarcar::Quitar => "pin-v2-marca-quitar",
    }
}

/// **Dispone la barrita** junto a lo elegido (`eleccion`, en puntos de la
/// vista desde arriba a la izquierda) en una vista de `ancho` x `alto`:
/// centrada encima, debajo si arriba no cabe, sin salirse por los lados.
/// Los botones, en el orden del pin: copiar, los cinco colores, las cinco
/// marcas y quitar.
#[uniffi::export]
pub fn disponer_barrita_de_marcar(
    eleccion: CajaDeMarca,
    ancho: f32,
    alto: f32,
    escala: f32,
) -> BarritaDeMarcar {
    let b = barra_marcar::disponer(eleccion.arreglo(), (ancho, alto), escala);
    BarritaDeMarcar {
        x: b.caja.x,
        y: b.caja.y,
        ancho: b.caja.ancho,
        alto: b.caja.alto,
        raya: b.raya,
        botones: b
            .botones
            .iter()
            .map(|(c, boton)| BotonDeMarcar {
                x: c.x,
                y: c.y,
                ancho: c.ancho,
                alto: c.alto,
                que: match boton {
                    BotonMarcar::Copiar => "copiar".into(),
                    BotonMarcar::Color(_) => "color".into(),
                    BotonMarcar::Marcar(m) => m.nombre().into(),
                    BotonMarcar::Quitar => "quitar".into(),
                },
                color: match boton {
                    BotonMarcar::Color(k) => *k,
                    _ => 0,
                },
                clave: clave_de(*boton).into(),
            })
            .collect(),
    }
}

/// Los cinco colores de las marcas (`#RRGGBB`), los de la barra del pin.
#[uniffi::export]
pub fn colores_de_marcar() -> Vec<String> {
    mt::COLORES
        .iter()
        .map(|(r, g, b)| format!("#{r:02X}{g:02X}{b:02X}"))
        .collect()
}

/// El color con que se empieza: el amarillo.
#[uniffi::export]
pub fn color_inicial_de_marcar() -> u8 {
    mt::COLOR_INICIAL
}

/// El grupo de una marca nueva (`marca-texto-<ms>`): todas sus rayas o
/// fondos, en todas las hojas por las que pasa, lo llevan.
#[uniffi::export]
pub fn grupo_de_marca_nuevo() -> String {
    mt::grupo_nuevo(crate::ahora_ms())
}

/// **Lo elegido llevado a palabras enteras** (`capa_de_texto::a_palabras_enteras`):
/// `a` y `b` en letras (no en UTF-16) de `texto`. Lo que usa un texto
/// reconocido, que se elige por palabras como en el pin.
#[uniffi::export]
pub fn palabras_enteras_de(texto: String, a: u32, b: u32) -> Vec<u32> {
    let letras: Vec<char> = texto.chars().collect();
    let (a, b) = pindesk_docs::capa_de_texto::a_palabras_enteras(&letras, a as usize, b as usize);
    vec![a as u32, b as u32]
}

/// **Cambia las marcas de una escena** (un solo paso de deshacer): con
/// `de_marca`, se quita esa marca entera; sin ella y sin `que` (el circulo
/// tachado), las marcas que caen en `cajas`; con `que`, se pone la marca
/// sobre `cajas` en el grupo `grupo`. `true` si cambio algo.
pub(crate) fn cambiar(
    escena: &mut Escena,
    que: Option<Marca>,
    color: u8,
    cajas: &[[f32; 4]],
    de_marca: Option<&str>,
    grupo: &str,
) -> bool {
    let antes = (escena.pasos_cerrados(), escena.cuantos_visibles());
    let quitar: Vec<u64> = match (de_marca, que) {
        (Some(g), _) => escena
            .visibles()
            .filter(|el| el.grupos.iter().any(|x| x == g))
            .map(|el| el.id)
            .collect(),
        (None, None) => mt::las_que_tocan(escena, cajas),
        (None, Some(_)) => Vec::new(),
    };
    // Cambiar una marca elegida con un clic sin su texto elegido (no se
    // pudo volver a elegir): la nueva va sobre el texto de la vieja.
    let del_grupo: Vec<[f32; 4]>;
    let cajas = match (de_marca, que) {
        (Some(g), Some(_)) if cajas.is_empty() => {
            del_grupo = escena
                .visibles()
                .filter(|el| el.grupos.iter().any(|x| x == g))
                .filter_map(texto_bajo)
                .collect();
            &del_grupo[..]
        }
        _ => cajas,
    };
    let nuevos = match que {
        Some(m) if !cajas.is_empty() => mt::elementos_en(m, mt::rgb(color), cajas, grupo),
        _ => Vec::new(),
    };
    if quitar.is_empty() && nuevos.is_empty() {
        return false;
    }
    escena.abrir_paso();
    for id in quitar {
        escena.borrar_apuntando(id);
    }
    for el in nuevos {
        escena.anadir(el);
    }
    escena.cerrar_paso();
    (escena.pasos_cerrados(), escena.cuantos_visibles()) != antes
}

/// Lo que se agranda el resaltado alrededor de las letras
/// (`marcas_texto::AIRE`, privado en el motor).
const AIRE: f32 = 0.12;

/// El alto de las letras de una raya de `grosor` (`max(0,09h, 1,5)`; con
/// el grosor minimo el alto no se sabe y se toma el de ese minimo).
fn alto_de_raya(grosor: f32) -> f32 {
    (grosor / 0.09).max(4.0)
}

/// **El renglon de texto que tiene debajo una marca** (la vuelta de
/// `marcas_texto::elementos_en`): el del fondo es exacto; el de una raya se
/// supone encima de ella (subrayar u ondulada, lo mas usado; una tachadura
/// cae un poco mas arriba).
fn texto_bajo(el: &pindesk_motor2d::Elemento) -> Option<[f32; 4]> {
    use pindesk_motor2d::Figura;
    match &el.figura {
        Figura::Rectangulo => {
            let h = el.alto / (1.0 + 2.0 * AIRE);
            let a = h * AIRE;
            Some([el.x + a, el.y + a, el.x + el.ancho - a, el.y + a + h])
        }
        Figura::Linea { puntos } => {
            let onda = puntos.len() > 2;
            let g = if onda { el.grosor / 0.8 } else { el.grosor };
            let h = alto_de_raya(g);
            let raya = if onda { el.y + el.alto / 2.0 } else { el.y };
            Some([el.x, raya - g - h, el.x + el.ancho, raya - g])
        }
        _ => None,
    }
}

/// **Por donde volver a elegir el texto de una marca**: una franja fina
/// dentro de su renglon (en medio para un fondo; justo encima de la raya
/// para una raya, que cae dentro del renglon tanto si subraya como si
/// tacha). Arrastrar por ella de punta a punta elige lo que se marco.
fn sonda(el: &pindesk_motor2d::Elemento) -> Option<[f32; 4]> {
    use pindesk_motor2d::Figura;
    let t = texto_bajo(el)?;
    let h = t[3] - t[1];
    Some(match &el.figura {
        Figura::Rectangulo => [t[0], t[1] + 0.3 * h, t[2], t[1] + 0.7 * h],
        _ => [t[0], t[1] + 0.65 * h, t[2], t[1] + 0.85 * h],
    })
}

/// El grupo de la marca bajo `(x, y)`, si hay.
pub(crate) fn grupo_bajo(escena: &Escena, x: f32, y: f32, holgura: f32) -> Option<String> {
    let ids = mt::grupo_en(escena, x, y, holgura)?;
    let el = escena.buscar(*ids.first()?)?;
    el.grupos.iter().find(|g| g.starts_with(mt::GRUPO)).cloned()
}

/// Las cajas de lo del grupo `g`.
pub(crate) fn cajas_del_grupo(escena: &Escena, g: &str) -> Vec<[f32; 4]> {
    escena
        .visibles()
        .filter(|el| el.grupos.iter().any(|x| x == g))
        .map(|el| {
            let (x0, y0, x1, y1) = el.caja();
            [x0, y0, x1, y1]
        })
        .collect()
}

#[uniffi::export]
impl EditorLienzo {
    /// **Marca lo elegido** en esta capa (ver [`cambiar`]): `marca` es el
    /// nombre de la marca (`resaltar`, `ondulada`, `subrayar`, `tachar`,
    /// `tapar`) o `None` para quitar; `color`, el de `colores_de_marcar`;
    /// `cajas`, lo elegido en esta hoja en unidades de la tinta; `de_marca`,
    /// el grupo de la marca elegida con un clic; `grupo`, el de la marca
    /// nueva (`grupo_de_marca_nuevo`, el mismo en todas las hojas). Un paso
    /// de deshacer; cuenta como cambio para guardar. `true` si cambio algo.
    pub fn marcar_texto(
        &self,
        marca: Option<String>,
        color: u8,
        cajas: Vec<CajaDeMarca>,
        de_marca: Option<String>,
        grupo: String,
    ) -> bool {
        let que = match marca.as_deref() {
            None => None,
            Some(n) => match Marca::de_nombre(n) {
                Some(m) => Some(m),
                None => return false,
            },
        };
        let cajas: Vec<[f32; 4]> = cajas.into_iter().map(CajaDeMarca::arreglo).collect();
        self.con_la_escena(|escena, _| {
            cambiar(escena, que, color, &cajas, de_marca.as_deref(), &grupo)
        })
    }

    /// El grupo de la marca de texto bajo `(x, y)` (unidades de la tinta,
    /// con `holgura` alrededor), si hay: lo que elige un clic encima.
    pub fn marca_de_texto_en(&self, x: f32, y: f32, holgura: f32) -> Option<String> {
        self.con_la_escena(|escena, _| grupo_bajo(escena, x, y, holgura))
    }

    /// **Por donde volver a elegir el texto de la marca `grupo`** en esta
    /// capa (ver [`sonda`]): una franja por renglon, de arriba abajo.
    pub fn sondas_de_marca(&self, grupo: String) -> Vec<CajaDeMarca> {
        let mut v: Vec<[f32; 4]> = self.con_la_escena(|escena, _| {
            escena
                .visibles()
                .filter(|el| el.grupos.iter().any(|x| *x == grupo))
                .filter_map(sonda)
                .collect()
        });
        v.sort_by(|a, b| a[1].total_cmp(&b[1]).then(a[0].total_cmp(&b[0])));
        v.into_iter().map(CajaDeMarca::de).collect()
    }

    /// Las cajas de la marca `grupo` en esta capa (vacio si no pasa por ella).
    pub fn cajas_de_marca(&self, grupo: String) -> Vec<CajaDeMarca> {
        self.con_la_escena(|escena, _| cajas_del_grupo(escena, &grupo))
            .into_iter()
            .map(CajaDeMarca::de)
            .collect()
    }
}

// ------------------------------------------------ las celdas de una hoja

/// Mas filas que esto no se rayan una a una (una columna entera elegida):
/// se marca hasta ahi (`visor_hoja::marcar::MAX_FILAS` de Windows).
pub const MAX_FILAS_DE_MARCA: u32 = 2000;

/// El borde `i` de una rejilla (`xs` o `ys`): mas alla de lo medido, a
/// `defecto` cada una.
fn borde(bordes: &[f64], defecto: f64, i: u32) -> f64 {
    match bordes.get(i as usize) {
        Some(v) => *v,
        None => {
            let n = bordes.len().saturating_sub(1);
            let ultimo = bordes.last().copied().unwrap_or(0.0);
            ultimo + (i as usize - n) as f64 * defecto
        }
    }
}

/// **Las cajas de unas celdas marcadas** (Windows 100857f2,
/// `visor_hoja::marcar::cajas`): en las unidades de la tinta de la hoja
/// (`rejilla`, la de `rejilla_del_libro`, la misma en todos los aparatos).
/// Resaltar, tapar y quitar (`marca` `None`) cubren el rango entero de una
/// pieza; las rayas van fila a fila, de lado a lado del rango, sin las filas
/// ocultas (alto 0). Se marca la celda entera: el texto de una celda se
/// recorta o se desborda segun el ancho de la columna de cada aparato.
#[uniffi::export]
pub fn cajas_de_celdas_marcadas(
    rejilla: crate::hojas::RejillaTinta,
    fila0: u32,
    columna0: u32,
    fila1: u32,
    columna1: u32,
    marca: Option<String>,
) -> Vec<CajaDeMarca> {
    let (f0, f1) = (fila0.min(fila1), fila0.max(fila1));
    let (c0, c1) = (columna0.min(columna1), columna0.max(columna1));
    let fila_a_fila = !matches!(
        marca.as_deref().and_then(Marca::de_nombre),
        None | Some(Marca::Resaltar | Marca::Tapar)
    );
    let f1 = f1.min(f0.saturating_add(MAX_FILAS_DE_MARCA));
    let x = |c: u32| borde(&rejilla.xs, rejilla.ancho_defecto, c);
    let y = |f: u32| borde(&rejilla.ys, rejilla.alto_defecto, f);
    let (x0, x1) = (x(c0) as f32, x(c1 + 1) as f32);
    let caja = |a: u32, b: u32| CajaDeMarca {
        x0,
        y0: y(a) as f32,
        x1,
        y1: y(b + 1) as f32,
    };
    if fila_a_fila {
        (f0..=f1)
            .filter(|&f| y(f + 1) - y(f) > 0.0)
            .map(|f| caja(f, f))
            .collect()
    } else {
        vec![caja(f0, f1)]
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn las_celdas_se_marcan_enteras_las_rayas_fila_a_fila() {
        let r = crate::hojas::RejillaTinta {
            xs: vec![0.0, 64.0, 128.0, 200.0],
            // La fila 2 esta oculta (alto 0).
            ys: vec![0.0, 20.0, 40.0, 40.0, 60.0],
            ancho_defecto: 64.0,
            alto_defecto: 20.0,
        };
        // Resaltar: el rango entero de una pieza, de C1 hasta mas alla de lo medido.
        let v = cajas_de_celdas_marcadas(r.clone(), 3, 1, 0, 4, Some("resaltar".into()));
        assert_eq!(v, vec![caja(64.0, 0.0, 200.0 + 2.0 * 64.0, 60.0)]);
        // Quitar, igual.
        assert_eq!(cajas_de_celdas_marcadas(r.clone(), 0, 1, 3, 4, None).len(), 1);
        // Subrayar: una por fila, sin la oculta.
        let v = cajas_de_celdas_marcadas(r.clone(), 0, 0, 3, 1, Some("subrayar".into()));
        assert_eq!(
            v,
            vec![
                caja(0.0, 0.0, 128.0, 20.0),
                caja(0.0, 20.0, 128.0, 40.0),
                caja(0.0, 40.0, 128.0, 60.0),
            ]
        );
        // Una columna entera no raya mas de 2000 filas (2001 sin la oculta).
        let v = cajas_de_celdas_marcadas(r.clone(), 0, 0, 1_000_000, 0, Some("tachar".into()));
        assert_eq!(v.len(), MAX_FILAS_DE_MARCA as usize);
        // Caso negativo: una marca que no existe es como quitar (de una pieza).
        assert_eq!(cajas_de_celdas_marcadas(r, 0, 0, 3, 1, Some("otra".into())).len(), 1);
    }

    fn caja(x0: f32, y0: f32, x1: f32, y1: f32) -> CajaDeMarca {
        CajaDeMarca { x0, y0, x1, y1 }
    }

    #[test]
    fn la_barrita_tiene_los_botones_del_pin_en_su_orden_con_sus_nombres() {
        let b = disponer_barrita_de_marcar(caja(400.0, 300.0, 600.0, 320.0), 1200.0, 800.0, 1.0);
        let que: Vec<&str> = b.botones.iter().map(|x| x.que.as_str()).collect();
        assert_eq!(
            que,
            [
                "copiar", "color", "color", "color", "color", "color", "resaltar", "ondulada",
                "subrayar", "tachar", "tapar", "quitar"
            ]
        );
        assert_eq!(b.botones[5].color, 4);
        assert_eq!(b.botones[0].clave, "pin-v2-marca-copiar");
        assert_eq!(b.botones[11].clave, "pin-v2-marca-quitar");
        assert!(b.botones[1].clave.is_empty());
        // Encima de lo elegido.
        assert!(b.y + b.alto <= 300.0);
        // Cada clave esta en el catalogo de Windows.
        let ftl = include_str!("../../pindesk-store/i18n/es-ES/main.ftl");
        for x in b.botones.iter().filter(|x| !x.clave.is_empty()) {
            assert!(ftl.contains(&format!("{} =", x.clave)), "{}", x.clave);
        }
    }

    #[test]
    fn los_colores_son_los_de_windows() {
        assert_eq!(
            colores_de_marcar(),
            ["#F47286", "#B99CF5", "#5BA4F5", "#3FC88C", "#F5C218"]
        );
        assert_eq!(color_inicial_de_marcar(), 4);
        assert!(grupo_de_marca_nuevo().starts_with("marca-texto-"));
    }

    #[test]
    fn marcar_quitar_y_elegir_una_marca_en_la_escena() {
        let mut e = Escena::nueva();
        let renglones = [[100.0, 100.0, 300.0, 120.0], [100.0, 130.0, 200.0, 150.0]];
        assert!(cambiar(
            &mut e,
            Some(Marca::Resaltar),
            4,
            &renglones,
            None,
            "marca-texto-1"
        ));
        assert_eq!(e.cuantos_visibles(), 2);
        // Apilar otra encima (tachar a la vez), en otro grupo.
        assert!(cambiar(
            &mut e,
            Some(Marca::Tachar),
            0,
            &renglones[..1],
            None,
            "marca-texto-2"
        ));
        assert_eq!(e.cuantos_visibles(), 3);
        // Un clic en el segundo renglon elige la marca entera (sus dos fondos).
        assert_eq!(
            grupo_bajo(&e, 150.0, 140.0, 2.0).as_deref(),
            Some("marca-texto-1")
        );
        assert_eq!(cajas_del_grupo(&e, "marca-texto-1").len(), 2);
        // Quitar la elegida: se van sus dos fondos y queda la tachadura.
        assert!(cambiar(&mut e, None, 0, &[], Some("marca-texto-1"), "x"));
        assert_eq!(e.cuantos_visibles(), 1);
        // El circulo sobre lo elegido quita lo que cae en ello.
        assert!(cambiar(&mut e, None, 0, &renglones[..1], None, "x"));
        assert_eq!(e.cuantos_visibles(), 0);
        // Caso negativo: sin nada que quitar ni poner no se abre ningun paso.
        let pasos = e.pasos_cerrados();
        assert!(!cambiar(&mut e, None, 0, &renglones, None, "x"));
        assert!(!cambiar(&mut e, Some(Marca::Tachar), 0, &[], None, "x"));
        assert_eq!(e.pasos_cerrados(), pasos);
        assert_eq!(grupo_bajo(&e, 150.0, 140.0, 2.0), None);
    }

    #[test]
    fn el_texto_de_una_marca_se_vuelve_a_encontrar() {
        let renglon = [100.0, 100.0, 300.0, 120.0];
        for m in mt::MARCAS {
            let els = mt::elementos_en(m, mt::rgb(0), &[renglon], "marca-texto-1");
            let el = &els[0];
            let t = texto_bajo(el).unwrap();
            let s = sonda(el).unwrap();
            // La franja cae dentro del renglon, sea cual sea la marca.
            let medio = (s[1] + s[3]) / 2.0;
            assert!(medio > renglon[1] && medio < renglon[3], "{m:?}: {s:?}");
            assert!(
                (s[0] - renglon[0]).abs() < 0.01 && (s[2] - renglon[2]).abs() < 0.01,
                "{m:?}"
            );
            match m {
                // El fondo y la raya de debajo dan el renglon exacto.
                Marca::Resaltar | Marca::Tapar | Marca::Subrayar | Marca::Ondulada => {
                    for k in 0..4 {
                        assert!((t[k] - renglon[k]).abs() < 0.05, "{m:?}: {t:?}");
                    }
                }
                Marca::Tachar => {}
            }
        }
        // Caso negativo: un texto escrito no es una raya ni un fondo.
        let el = pindesk_motor2d::Elemento {
            figura: pindesk_motor2d::Figura::Elipse,
            ..Default::default()
        };
        assert_eq!(sonda(&el), None);
    }

    #[test]
    fn cambiar_una_marca_elegida_sin_su_texto_la_pone_en_su_sitio() {
        let mut e = Escena::nueva();
        let renglon = [100.0, 100.0, 300.0, 120.0];
        assert!(cambiar(
            &mut e,
            Some(Marca::Subrayar),
            0,
            &[renglon],
            None,
            "marca-texto-1"
        ));
        assert!(cambiar(
            &mut e,
            Some(Marca::Resaltar),
            2,
            &[],
            Some("marca-texto-1"),
            "marca-texto-2"
        ));
        assert_eq!(e.cuantos_visibles(), 1);
        let c = cajas_del_grupo(&e, "marca-texto-2");
        assert_eq!(c.len(), 1);
        // El fondo nuevo abarca el renglon de la raya vieja.
        assert!(c[0][1] < 100.0 && c[0][3] > 120.0, "{c:?}");
        // Deshacer devuelve la raya.
        assert!(e.deshacer());
        assert_eq!(cajas_del_grupo(&e, "marca-texto-1").len(), 1);
    }

    #[test]
    fn la_tinta_a_mano_no_es_una_marca() {
        let mut e = Escena::nueva();
        e.abrir_paso();
        e.anadir(pindesk_motor2d::Elemento {
            figura: pindesk_motor2d::Figura::Rectangulo,
            x: 100.0,
            y: 100.0,
            ancho: 200.0,
            alto: 20.0,
            ..Default::default()
        });
        e.cerrar_paso();
        assert_eq!(grupo_bajo(&e, 150.0, 110.0, 2.0), None);
        assert!(!cambiar(
            &mut e,
            None,
            0,
            &[[100.0, 100.0, 300.0, 120.0]],
            None,
            "x"
        ));
        assert_eq!(e.cuantos_visibles(), 1);
    }

    #[test]
    fn las_palabras_enteras_del_texto_reconocido() {
        assert_eq!(palabras_enteras_de("uno dos tres".into(), 1, 6), vec![0, 7]);
        assert_eq!(palabras_enteras_de("uno".into(), 2, 2), vec![2, 2]);
    }

    #[test]
    fn la_marca_se_guarda_como_dibujo_con_su_grupo_y_se_deshace_entera() {
        let d = std::env::temp_dir().join(format!("pixpin-marcas-texto-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let ruta = d.join("hoja-0.excalidraw");
        let ed = EditorLienzo::de_fichero(ruta.display().to_string(), true).unwrap();
        let cajas = vec![
            caja(100.0, 100.0, 300.0, 120.0),
            caja(100.0, 130.0, 200.0, 150.0),
        ];
        assert!(ed.marcar_texto(
            Some("resaltar".into()),
            4,
            cajas.clone(),
            None,
            "marca-texto-7".into()
        ));
        assert!(ed.sin_guardar());
        assert_eq!(
            ed.marca_de_texto_en(150.0, 140.0, 2.0).as_deref(),
            Some("marca-texto-7")
        );
        assert_eq!(ed.cajas_de_marca("marca-texto-7".into()).len(), 2);
        let sondas = ed.sondas_de_marca("marca-texto-7".into());
        assert_eq!(sondas.len(), 2);
        assert!(sondas[0].y0 > 100.0 && sondas[0].y1 < 120.0 && sondas[1].y0 > 130.0);
        assert!(ed.guardar().unwrap());
        let json: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&ruta).unwrap()).unwrap();
        let elementos: Vec<&serde_json::Value> = json["elements"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|e| e["isDeleted"] != true)
            .collect();
        assert_eq!(elementos.len(), 2);
        for e in &elementos {
            assert_eq!(e["type"], "rectangle");
            assert_eq!(e["groupIds"][0], "marca-texto-7");
            assert_eq!(e["opacity"], 40);
            assert_eq!(e["roughness"], 0);
            assert_eq!(
                e["backgroundColor"]
                    .as_str()
                    .map(str::to_lowercase)
                    .as_deref(),
                Some("#f5c218")
            );
        }
        // Un Ctrl+Z la quita entera (los dos renglones).
        assert!(ed.deshacer());
        assert_eq!(ed.cajas_de_marca("marca-texto-7".into()).len(), 0);
        // Caso negativo: una marca que no se conoce no hace nada.
        assert!(!ed.marcar_texto(
            Some("brillar".into()),
            0,
            cajas,
            None,
            "marca-texto-8".into()
        ));
        let _ = std::fs::remove_dir_all(&d);
    }
}
