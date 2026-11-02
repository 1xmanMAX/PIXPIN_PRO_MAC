//! **La hoja del «+» del chat como la «Adjuntar» del iPhone** (Windows
//! f87468aa, `ventana_chat/hoja_adjuntar.rs`): arriba «Cerrar» y el titulo;
//! lo de todos los dias en una cuadricula de cuatro; «Más» en dos columnas
//! de pastillas y abajo «Pegar lo copiado» (apagado si no hay nada
//! copiado). Sin buscador.
//!
//! Aqui va como se recorre con las flechas (`mover_eleccion` de Windows):
//! izquierda y derecha de uno en uno; arriba y abajo, a lo que queda encima
//! o debajo y mas cerca en x. Los sitios se calculan con las medidas de
//! Windows al 100 %, que es lo que decide que hay encima de que.

/// Las medidas de Windows (logicos al 100 %).
const ANCHO: i32 = 480;
const RELLENO: i32 = 16;
const CABECERA: i32 = 34;
const HUECO: i32 = 12;
const COLUMNAS: i32 = 4;
const BALDOSA_ALTO: i32 = 90;
const BALDOSA_HUECO: i32 = 4;
const CABECERA_MAS: i32 = 20;
const COLUMNAS_CHIP: i32 = 2;
const CHIP_ALTO: i32 = 36;
const CHIP_HUECO: i32 = 8;
const PIE: i32 = 36;
const BOTON_PEGAR: i32 = 108;

/// Una flecha del teclado en la hoja.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FlechaDeLaHoja {
    Arriba,
    Abajo,
    Izquierda,
    Derecha,
}

/// Las columnas de la cuadricula y de «Más» (para que Swift coloque igual).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct ColumnasDeLaHoja {
    pub baldosas: u32,
    pub chips: u32,
}

#[uniffi::export]
pub fn columnas_de_la_hoja() -> ColumnasDeLaHoja {
    ColumnasDeLaHoja {
        baldosas: COLUMNAS as u32,
        chips: COLUMNAS_CHIP as u32,
    }
}

/// El centro de cada entrada elegible, en el orden de la hoja: baldosas,
/// chips y, si hay algo copiado, «Pegar».
fn centros(baldosas: u32, chips: u32, pegar: bool) -> Vec<(i32, i32)> {
    let dentro = ANCHO - 2 * RELLENO;
    let x0 = RELLENO;
    let mut y = RELLENO + CABECERA + HUECO;
    let mut v = Vec::new();
    let ancho_b = (dentro - (COLUMNAS - 1) * BALDOSA_HUECO) / COLUMNAS;
    for k in 0..baldosas as i32 {
        let (f, c) = (k / COLUMNAS, k % COLUMNAS);
        v.push((
            x0 + c * (ancho_b + BALDOSA_HUECO) + ancho_b / 2,
            y + f * (BALDOSA_ALTO + BALDOSA_HUECO) + BALDOSA_ALTO / 2,
        ));
    }
    if baldosas > 0 {
        let filas = (baldosas as i32 + COLUMNAS - 1) / COLUMNAS;
        y += filas * BALDOSA_ALTO + (filas - 1) * BALDOSA_HUECO;
    }
    if chips > 0 {
        y += 2 * HUECO + CABECERA_MAS + CHIP_HUECO;
        let ancho_c = (dentro - (COLUMNAS_CHIP - 1) * CHIP_HUECO) / COLUMNAS_CHIP;
        for k in 0..chips as i32 {
            let (f, c) = (k / COLUMNAS_CHIP, k % COLUMNAS_CHIP);
            v.push((
                x0 + c * (ancho_c + CHIP_HUECO) + ancho_c / 2,
                y + f * (CHIP_ALTO + CHIP_HUECO) + CHIP_ALTO / 2,
            ));
        }
        let filas = (chips as i32 + COLUMNAS_CHIP - 1) / COLUMNAS_CHIP;
        y += filas * CHIP_ALTO + (filas - 1) * CHIP_HUECO;
    }
    if pegar {
        y += 2 * HUECO;
        let boton = BOTON_PEGAR.min(dentro / 2);
        v.push((x0 + dentro - boton / 2, y + PIE / 2));
    }
    v
}

/// **Mueve lo elegido con una flecha**: `actual` es el indice en el orden
/// de la hoja (las `baldosas`, luego los `chips` y, con `pegar`, el boton de
/// abajo). Sin nada elegido, la primera. `None` si no hay nada que elegir.
#[uniffi::export]
pub fn mover_en_la_hoja_adjuntar(
    actual: Option<u32>,
    flecha: FlechaDeLaHoja,
    baldosas: u32,
    chips: u32,
    pegar: bool,
) -> Option<u32> {
    let sitios = centros(baldosas, chips, pegar);
    if sitios.is_empty() {
        return None;
    }
    let Some(k) = actual.map(|a| a as usize).filter(|a| *a < sitios.len()) else {
        return Some(0);
    };
    let (cx, cy) = sitios[k];
    let nuevo = match flecha {
        FlechaDeLaHoja::Derecha => (k + 1).min(sitios.len() - 1),
        FlechaDeLaHoja::Izquierda => k.saturating_sub(1),
        FlechaDeLaHoja::Abajo | FlechaDeLaHoja::Arriba => {
            let abajo = flecha == FlechaDeLaHoja::Abajo;
            sitios
                .iter()
                .enumerate()
                .filter(|(_, (_, y))| if abajo { *y > cy } else { *y < cy })
                .min_by_key(|(_, (x, y))| ((y - cy).abs(), (x - cx).abs()))
                .map(|(j, _)| j)
                .unwrap_or(k)
        }
    };
    Some(nuevo as u32)
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use FlechaDeLaHoja::*;

    #[test]
    fn las_flechas_van_por_filas_como_en_windows() {
        // Siete baldosas (4 + 3), quince chips en dos columnas y «Pegar».
        let m = |a, f| mover_en_la_hoja_adjuntar(a, f, 7, 15, true);
        assert_eq!(m(None, Derecha), Some(0));
        assert_eq!(m(Some(1), Abajo), Some(5));
        // Bajo la cuarta (que no tiene nada debajo) se va a lo mas cercano
        // de la fila de abajo: la septima.
        assert_eq!(m(Some(3), Abajo), Some(6));
        // De la ultima fila de baldosas a los chips: el de la izquierda.
        assert_eq!(m(Some(4), Abajo), Some(7));
        assert_eq!(m(Some(6), Abajo), Some(8), "el de la derecha");
        assert_eq!(m(Some(8), Arriba), Some(6));
        // El ultimo chip (solo en su fila, a la izquierda) baja a «Pegar».
        assert_eq!(m(Some(21), Abajo), Some(22));
        assert_eq!(m(Some(22), Arriba), Some(21));
        // No se sale por los extremos.
        assert_eq!(m(Some(0), Izquierda), Some(0));
        assert_eq!(m(Some(22), Derecha), Some(22));
        assert_eq!(m(Some(22), Abajo), Some(22));
        assert_eq!(m(Some(0), Arriba), Some(0));
    }

    #[test]
    fn sin_nada_copiado_pegar_no_se_elige() {
        let m = |a, f| mover_en_la_hoja_adjuntar(a, f, 7, 15, false);
        assert_eq!(m(Some(21), Abajo), Some(21));
        assert_eq!(m(Some(21), Derecha), Some(21));
        // Caso negativo: nada que elegir, o un indice que ya no existe.
        assert_eq!(mover_en_la_hoja_adjuntar(Some(3), Abajo, 0, 0, false), None);
        assert_eq!(m(Some(99), Abajo), Some(0));
        assert_eq!(
            columnas_de_la_hoja(),
            ColumnasDeLaHoja {
                baldosas: 4,
                chips: 2
            }
        );
    }
}
