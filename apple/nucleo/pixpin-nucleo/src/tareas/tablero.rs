//! **Lo que se ve en Tarjetas y en Kanban**, como Windows
//! (`tareas/tarjetas.rs` y `tareas/ventana.rs` de la app): que tareas salen
//! con lo buscado, en que orden, y el color de cada lista.
//!
//! - **Buscar** (`tarjetas::coincide`): sin mayusculas ni tildes
//!   (`pixpin_ui::resaltado`), y han de estar TODAS las palabras, cada una
//!   en el texto de la tarea, en el nombre de su lista o en el de su chat.
//!   Una palabra que nombra un dia («hoy», «ayer», «anteayer» o
//!   `2026-10-01`) vale tambien por el dia en que se apunto. El Mac buscaba
//!   solo en el texto de la tarea: abrir una lista desde el chat la buscaba
//!   por su nombre («hoy sábado») y no salia ninguna de sus tareas.
//! - **Agrupar** (`tarjetas::agrupar`): una lista sin nada que salga no
//!   sale; lo pendiente arriba con `orden_de_pendiente` y lo hecho aparte,
//!   en el orden del documento.
//! - **El color de cada lista** (`colores_de_listas` y `DEGRADADOS`): doce
//!   degradados hondos, sin repetir mientras haya, el mismo que en Windows
//!   para la misma lista (sale de su clave, `chat/mensaje`, y de las demas
//!   listas con tareas). No viaja en el mensaje: Windows lo calcula asi.

use pixpin_proyecto::mini;
use pixpin_ui::resaltado::hay_coincidencia;

use super::{ListaTareas, Tarea};

/// Los degradados de los grupos (`DEGRADADOS` de Windows): violeta, verde,
/// rojo, naranja, azul, rosa, turquesa, oliva, marron, anil, magenta y
/// dorado, hondos para que el texto claro se lea encima.
pub const DEGRADADOS: [(u32, u32); 12] = [
    (0x5B2DA8, 0x3A1F7A),
    (0x0F7A4A, 0x0B5236),
    (0xA8323E, 0x6E1F33),
    (0xB8650F, 0x7A3D0C),
    (0x1767A8, 0x0F3F75),
    (0xA8306E, 0x6B1F52),
    (0x0E7C86, 0x0A4F5E),
    (0x6E7A12, 0x434D0C),
    (0x7A4A2A, 0x4D2C1A),
    (0x3A44B8, 0x232A7A),
    (0x8A2AA8, 0x561A70),
    (0x9C7A0E, 0x5E4808),
];

/// Lo que distingue a una lista de las demas (`Lista::clave` de Windows):
/// su chat y su mensaje.
pub fn clave(l: &ListaTareas) -> String {
    format!("{}/{}", l.chat, l.mensaje)
}

/// El sitio en [`DEGRADADOS`] de cada lista (`colores_de_listas` de
/// Windows): cada una parte del color de su clave (FNV-1a) y, si ya lo
/// tiene otra, toma el siguiente libre; se reparten por orden de clave, y
/// las vacias no gastan color.
fn colores_de_listas(claves: &[(String, bool)]) -> Vec<usize> {
    let n = DEGRADADOS.len();
    let semilla = |c: &str| {
        c.bytes().fold(0x811c_9dc5u32, |h, b| {
            (h ^ u32::from(b)).wrapping_mul(0x0100_0193)
        }) as usize
            % n
    };
    let mut orden: Vec<usize> = (0..claves.len()).filter(|&i| claves[i].1).collect();
    orden.sort_by(|a, b| claves[*a].0.cmp(&claves[*b].0));
    let mut usado = vec![false; n];
    let mut out: Vec<usize> = claves.iter().map(|(c, _)| semilla(c)).collect();
    for i in orden {
        let desde = semilla(&claves[i].0);
        let k = (0..n)
            .map(|d| (desde + d) % n)
            .find(|k| !usado[*k])
            .unwrap_or(desde);
        usado[k] = true;
        out[i] = k;
    }
    out
}

/// El dia que nombra una palabra (`tarjetas::Dia`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Dia {
    /// Hace tantos dias: hoy es 0, ayer 1.
    Hace(u32),
    El(mini::Fecha),
}

fn plano(s: &str) -> String {
    s.chars()
        .flat_map(char::to_lowercase)
        .map(|c| match c {
            'á' | 'à' | 'ä' | 'â' => 'a',
            'é' | 'è' | 'ë' | 'ê' => 'e',
            'í' | 'ì' | 'ï' | 'î' => 'i',
            'ó' | 'ò' | 'ö' | 'ô' => 'o',
            'ú' | 'ù' | 'ü' | 'û' => 'u',
            otra => otra,
        })
        .collect()
}

fn dia_de(palabra: &str) -> Option<Dia> {
    match plano(palabra).as_str() {
        "hoy" | "today" => Some(Dia::Hace(0)),
        "ayer" | "yesterday" => Some(Dia::Hace(1)),
        "anteayer" => Some(Dia::Hace(2)),
        otra => mini::Fecha::leer(otra).map(Dia::El),
    }
}

impl Dia {
    fn es(self, creada: Option<mini::Fecha>, hoy: mini::Fecha) -> bool {
        let Some(c) = creada else {
            return false;
        };
        match self {
            // Una fecha del futuro (el reloj de otro equipo) no es «hoy».
            Dia::Hace(n) => c.dias() <= hoy.dias() && mini::dias_desde(c, hoy) == n,
            Dia::El(f) => c == f,
        }
    }
}

/// Si la tarea `t` de la lista `l` sale con estas palabras
/// (`tarjetas::coincide`). El chat de «Mensajes guardados» se llama asi
/// tambien aqui, que es lo que se ve en su encabezado.
fn coincide(l: &ListaTareas, t: &Tarea, palabras: &[&str], hoy: mini::Fecha) -> bool {
    let creada = t.creada.as_deref().and_then(mini::Fecha::leer);
    palabras.iter().all(|p| {
        hay_coincidencia(&t.texto, p)
            || hay_coincidencia(&l.titulo, p)
            || hay_coincidencia(&l.nombre_chat, p)
            || (l.guardados && hay_coincidencia("Mensajes guardados", p))
            || dia_de(p).is_some_and(|d| d.es(creada, hoy))
    })
}

/// Como se ordena lo pendiente (`orden_de_pendiente` de Windows): primero
/// por su prioridad segun su contexto, luego lo que tiene fecha (la mas
/// vieja arriba), detras lo que no, y a igualdad el orden del documento.
///
/// La prioridad la pone Jev (`crate::jev::urgencia`, Windows fa4ca12); lo
/// que aun no se sabe cuenta como «normal», y sin Jev todas lo son: el
/// orden es el de siempre.
fn orden_de_pendiente(t: &Tarea) -> (u8, bool, Option<mini::Fecha>, u32) {
    let creada = t.creada.as_deref().and_then(mini::Fecha::leer);
    let rango = match t.prioridad.as_deref() {
        Some("urgente") => 0,
        Some("alta") => 1,
        Some("baja") => 3,
        _ => 2,
    };
    (rango, creada.is_none(), creada, t.indice)
}

/// Una lista como se ensena en Tarjetas y en Kanban.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GrupoTareas {
    /// El sitio de la lista en las listas leidas.
    pub lista: u32,
    /// Su clave (`chat/mensaje`).
    pub clave: String,
    /// Lo pendiente que sale, ya ordenado (los `indice` de sus tareas).
    pub arriba: Vec<u32>,
    /// Lo hecho que sale, en el orden del documento.
    pub hechas: Vec<u32>,
    /// Cuantas quedan pendientes (lo del encabezado).
    pub pendientes: u32,
    /// Su degradado (`0xRRGGBB`), de arriba a la izquierda a abajo a la
    /// derecha; `desde` es tambien la marca de su encabezado.
    pub desde: u32,
    pub hasta: u32,
}

/// **Los grupos de Tarjetas y Kanban** (`tarjetas::agrupar` de Windows):
/// en el orden de las listas, con lo que sale con `busqueda` (vacia: todo),
/// y una lista sin nada que salga no sale. Los colores se reparten entre
/// TODAS las listas con tareas, busques o no, asi no cambian al buscar.
/// `desfase_ms` es el huso de quien mira (para «hoy» y «ayer»).
#[uniffi::export]
pub fn grupos_de_tareas(
    listas: Vec<ListaTareas>,
    busqueda: String,
    desfase_ms: i64,
) -> Vec<GrupoTareas> {
    let hoy = mini::Fecha::de_ms_locales(crate::ahora_ms() + desfase_ms);
    grupos_el(&listas, &busqueda, hoy)
}

fn grupos_el(listas: &[ListaTareas], busqueda: &str, hoy: mini::Fecha) -> Vec<GrupoTareas> {
    let palabras: Vec<&str> = busqueda.split_whitespace().collect();
    let claves: Vec<(String, bool)> = listas
        .iter()
        .map(|l| (clave(l), !l.tareas.is_empty()))
        .collect();
    let colores = colores_de_listas(&claves);
    listas
        .iter()
        .enumerate()
        .filter_map(|(li, l)| {
            let vale = |t: &&Tarea| coincide(l, t, &palabras, hoy);
            let mut arriba: Vec<&Tarea> =
                l.tareas.iter().filter(|t| !t.hecha).filter(vale).collect();
            arriba.sort_by_key(|t| orden_de_pendiente(t));
            let hechas: Vec<u32> = l
                .tareas
                .iter()
                .filter(|t| t.hecha)
                .filter(vale)
                .map(|t| t.indice)
                .collect();
            if arriba.is_empty() && hechas.is_empty() {
                return None;
            }
            let (desde, hasta) = DEGRADADOS[colores[li] % DEGRADADOS.len()];
            Some(GrupoTareas {
                lista: li as u32,
                clave: claves[li].0.clone(),
                pendientes: arriba.len() as u32,
                arriba: arriba.into_iter().map(|t| t.indice).collect(),
                hechas,
                desde,
                hasta,
            })
        })
        .collect()
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn tarea(i: u32, texto: &str, hecha: bool, creada: Option<&str>) -> Tarea {
        Tarea {
            indice: i,
            crudo: texto.into(),
            texto: texto.into(),
            hecha,
            recuerda: None,
            creada: creada.map(str::to_string),
            dias: None,
            imagenes: Vec::new(),
            prioridad: None,
        }
    }

    fn lista(
        chat: &str,
        mensaje: &str,
        titulo: &str,
        guardados: bool,
        tareas: Vec<Tarea>,
    ) -> ListaTareas {
        ListaTareas {
            chat: chat.into(),
            nombre_chat: if guardados {
                "Guardados".into()
            } else {
                "Obra".into()
            },
            guardados,
            mensaje: mensaje.into(),
            titulo: titulo.into(),
            cuando: 0,
            es_inbox: false,
            pendientes: tareas.iter().filter(|t| !t.hecha).count() as u32,
            tareas,
        }
    }

    const HOY: mini::Fecha = mini::Fecha {
        anio: 2026,
        mes: 10,
        dia: 31,
    };

    fn sabado() -> ListaTareas {
        lista(
            "g",
            "m1",
            "hoy sábado",
            true,
            vec![
                tarea(0, "comprar pan", false, None),
                tarea(1, "lavar el coche", false, Some("2026-10-30")),
                tarea(2, "llamar a mamá", true, Some("2026-10-29")),
            ],
        )
    }

    #[test]
    fn la_lista_de_mensajes_guardados_sale_entera_sin_buscar() {
        let g = grupos_el(&[sabado()], "", HOY);
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].clave, "g/m1");
        // Lo pendiente: con fecha primero, la mas vieja arriba.
        assert_eq!(g[0].arriba, [1, 0]);
        assert_eq!(g[0].hechas, [2]);
        assert_eq!(g[0].pendientes, 2);
    }

    /// Con Jev (Windows fa4ca12): primero por prioridad, luego como siempre.
    #[test]
    fn con_prioridad_de_jev_lo_urgente_va_arriba() {
        let mut l = sabado();
        l.tareas[0].prioridad = Some("urgente".into());
        assert_eq!(grupos_el(&[l.clone()], "", HOY)[0].arriba, [0, 1]);
        l.tareas[0].prioridad = Some("baja".into());
        l.tareas[1].prioridad = Some("normal".into());
        assert_eq!(grupos_el(&[l], "", HOY)[0].arriba, [1, 0]);
    }

    #[test]
    fn buscar_por_el_nombre_de_la_lista_la_encuentra() {
        // Lo que el Mac hacia al abrir una lista desde el chat: buscarla por
        // su nombre. Solo miraba el texto de cada tarea y salia vacia.
        let otra = lista(
            "c",
            "m2",
            "Obra",
            false,
            vec![tarea(0, "pedir ladrillo", false, None)],
        );
        let g = grupos_el(&[otra.clone(), sabado()], "hoy SABADO", HOY);
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].lista, 1);
        assert_eq!(g[0].arriba.len() + g[0].hechas.len(), 3);
        // Y por su chat, y por «Mensajes guardados».
        assert_eq!(
            grupos_el(&[otra.clone(), sabado()], "obra", HOY)[0].lista,
            0
        );
        assert_eq!(
            grupos_el(&[otra, sabado()], "mensajes guardados", HOY)[0].lista,
            1
        );
    }

    #[test]
    fn todas_las_palabras_sin_tildes_y_los_dias_por_su_fecha() {
        let l = sabado();
        let g = grupos_el(std::slice::from_ref(&l), "mama", HOY);
        assert_eq!(
            (g[0].arriba.clone(), g[0].hechas.clone()),
            (vec![], vec![2])
        );
        assert!(grupos_el(std::slice::from_ref(&l), "pan coche", HOY).is_empty());
        // «ayer» es lo apuntado ayer (30-oct); «2026-10-29», ese dia.
        let g = grupos_el(
            &[lista("c", "m", "Casa", false, l.tareas.clone())],
            "ayer",
            HOY,
        );
        assert_eq!(g[0].arriba, [1]);
        let g = grupos_el(
            &[lista("c", "m", "Casa", false, l.tareas.clone())],
            "2026-10-29",
            HOY,
        );
        assert_eq!(g[0].hechas, [2]);
    }

    #[test]
    fn una_lista_vacia_no_sale_ni_gasta_color() {
        let vacia = lista("c", "m0", "Nada", false, vec![]);
        let g = grupos_el(&[vacia, sabado()], "", HOY);
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].lista, 1);
    }

    #[test]
    fn cada_lista_su_color_sin_repetir_y_el_mismo_de_windows() {
        // FNV-1a de la clave, modulo 12: como en Windows.
        let claves: Vec<(String, bool)> = (0..12).map(|i| (format!("c/m{i}"), true)).collect();
        let c = colores_de_listas(&claves);
        let mut vistos = c.clone();
        vistos.sort_unstable();
        vistos.dedup();
        assert_eq!(vistos.len(), 12, "doce listas, doce colores");
        // Una sola lista lleva el color de su semilla.
        let semilla = "g/m1".bytes().fold(0x811c_9dc5u32, |h, b| {
            (h ^ u32::from(b)).wrapping_mul(0x0100_0193)
        }) as usize
            % 12;
        let g = grupos_el(&[sabado()], "", HOY);
        assert_eq!((g[0].desde, g[0].hasta), DEGRADADOS[semilla]);
        // Buscar no cambia los colores.
        let otra = lista(
            "c",
            "m2",
            "Obra",
            false,
            vec![tarea(0, "pedir ladrillo", false, None)],
        );
        let todas = grupos_el(&[otra.clone(), sabado()], "", HOY);
        let buscando = grupos_el(&[otra, sabado()], "sabado", HOY);
        assert_eq!(todas[1].desde, buscando[0].desde);
    }
}
