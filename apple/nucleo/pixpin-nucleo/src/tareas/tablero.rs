//! **Lo que se ve en Tarjetas y en Kanban**, como Windows
//! (`tareas/tarjetas.rs` y `tareas/ventana.rs` de la app): que tareas salen
//! con lo buscado, en que orden, y el color de cada lista.
//!
//! - **Buscar** (`tarjetas::coincide`): sin mayusculas ni tildes
//!   (`pindesk_ui::resaltado`), y han de estar TODAS las palabras, cada una
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

use pindesk_proyecto::mini;
use pindesk_ui::resaltado::hay_coincidencia;

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
    grupos_con(listas, busqueda, hoy, &|_, _| false)
}

/// El degradado de la lista de una asignatura (`degradado_de_lista` de
/// Windows): su color y, abajo, el mismo un 35 % hacia el negro.
fn degradado_de_asignatura(c: u32) -> (u32, u32) {
    let oscuro = |x: u32| ((x as f32) * 0.65).round() as u32;
    let hasta = (oscuro((c >> 16) & 0xFF) << 16) | (oscuro((c >> 8) & 0xFF) << 8) | oscuro(c & 0xFF);
    (c, hasta)
}

/// Lo de [`grupos_el`] con lo que se queda arriba aunque este hecho
/// (`sigue_arriba`, lo recien tachado de [`TareasQuietas`]), como
/// `tarjetas::agrupar` con `Lista::a_la_vista` de Windows: arriba lo
/// pendiente y lo que sigue arriba, ordenado con `orden_de_pendiente`; lo
/// demas, plegado en el orden del documento. La lista de una asignatura
/// (`ListaTareas::asignatura`, Windows 71bf70f) sale aunque este vacia
/// (buscando, si su nombre o el de su chat coincide) y con su color.
fn grupos_con(
    listas: &[ListaTareas],
    busqueda: &str,
    hoy: mini::Fecha,
    sigue_arriba: &dyn Fn(&ListaTareas, &Tarea) -> bool,
) -> Vec<GrupoTareas> {
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
            let mut arriba: Vec<&Tarea> = l
                .tareas
                .iter()
                .filter(|t| !t.hecha || sigue_arriba(l, t))
                .filter(vale)
                .collect();
            arriba.sort_by_key(|t| orden_de_pendiente(t));
            let hechas: Vec<u32> = l
                .tareas
                .iter()
                .filter(|t| t.hecha && !sigue_arriba(l, t))
                .filter(vale)
                .map(|t| t.indice)
                .collect();
            let de_asignatura = l.asignatura.is_some()
                && palabras
                    .iter()
                    .all(|p| hay_coincidencia(&l.titulo, p) || hay_coincidencia(&l.nombre_chat, p));
            if arriba.is_empty() && hechas.is_empty() && !de_asignatura {
                return None;
            }
            let (desde, hasta) = match l.asignatura {
                Some(c) => degradado_de_asignatura(c),
                None => DEGRADADOS[colores[li] % DEGRADADOS.len()],
            };
            Some(GrupoTareas {
                lista: li as u32,
                clave: claves[li].0.clone(),
                pendientes: arriba.iter().filter(|t| !t.hecha).count() as u32,
                arriba: arriba.into_iter().map(|t| t.indice).collect(),
                hechas,
                desde,
                hasta,
            })
        })
        .collect()
}

/// **Lo que no se mueve bajo el raton** en la ventana de Tareas (Windows
/// 8ce1927, `pindesk_ui::tareas_quietas`, 1-nov-2026; el usuario: «cuando
/// hago clic en la casilla de una tarea y voy a hacer clic en la siguiente,
/// la anterior se va y acabo pulsando otra»). Marcar se guarda al momento;
/// lo que se queda quieto es solo la vista: lo recien tachado sigue arriba,
/// en su sitio, tachado; lo recien destachado sigue en «Hechas», y el orden
/// de las listas y de sus tareas no cambia (tampoco por lo que contesta Jev
/// tarde). Se suelta ([`TareasQuietas::soltar`]) al salir de Tareas:
/// cerrar, minimizar, volver a pedirla, otra vista u otra busqueda.
#[derive(uniffi::Object, Default)]
pub struct TareasQuietas {
    q: std::sync::Mutex<pindesk_ui::tareas_quietas::Quietas>,
}

impl TareasQuietas {
    fn tomar(&self) -> std::sync::MutexGuard<'_, pindesk_ui::tareas_quietas::Quietas> {
        self.q.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn grupos_el(&self, listas: &[ListaTareas], busqueda: &str, hoy: mini::Fecha) -> Vec<GrupoTareas> {
        let mut q = self.tomar();
        q.buscar(busqueda);
        let mut grupos = {
            let q: &pindesk_ui::tareas_quietas::Quietas = &q;
            grupos_con(listas, busqueda, hoy, &|l, t| q.sigue_arriba(&clave(l), &t.crudo))
        };
        for g in &mut grupos {
            let Some(l) = listas.get(g.lista as usize) else {
                continue;
            };
            let crudo = |i: &u32| l.tareas.iter().find(|t| t.indice == *i).map(|t| t.crudo.clone()).unwrap_or_default();
            q.ordenar_tareas(&g.clave, &mut g.arriba, &mut g.hechas, crudo);
            // Lo recien destachado que se quedo en «Hechas» sigue pendiente.
            g.pendientes = g
                .arriba
                .iter()
                .chain(&g.hechas)
                .filter(|i| l.tareas.iter().any(|t| t.indice == **i && !t.hecha))
                .count() as u32;
        }
        q.ordenar_listas(&mut grupos, |g| g.clave.clone());
        grupos
    }
}

#[uniffi::export]
impl TareasQuietas {
    #[uniffi::constructor]
    pub fn nuevas() -> std::sync::Arc<TareasQuietas> {
        std::sync::Arc::new(TareasQuietas::default())
    }

    /// Se marco (`hecha`) o destaco la tarea `crudo` de la lista `clave`
    /// (`chat/mensaje`). Deshacer lo recien hecho la deja como estaba.
    pub fn marcar(&self, clave: String, crudo: String, hecha: bool) {
        self.tomar().marcar(&clave, &crudo, hecha);
    }

    /// La tarea ya no esta (se quito o se movio a otra lista).
    pub fn quitar(&self, clave: String, crudo: String) {
        self.tomar().quitar(&clave, &crudo);
    }

    /// Se sale de Tareas: lo tachado se va a «Hechas» y todo se vuelve a
    /// ordenar como toca.
    pub fn soltar(&self) {
        self.tomar().soltar();
    }

    /// Cuantas se marcaron o destacaron desde la ultima vez que se solto.
    pub fn tocadas(&self) -> u32 {
        self.tomar().tocadas() as u32
    }

    /// **Los grupos de Tarjetas y Kanban, quietos** (`grupos_quietos` de
    /// Windows): como [`grupos_de_tareas`], con lo recien tachado arriba en
    /// su sitio, lo recien destachado en «Hechas» y las listas y sus tareas
    /// en el orden en que ya se veian. Buscar otra cosa suelta todo.
    pub fn grupos(&self, listas: Vec<ListaTareas>, busqueda: String, desfase_ms: i64) -> Vec<GrupoTareas> {
        let hoy = mini::Fecha::de_ms_locales(crate::ahora_ms() + desfase_ms);
        self.grupos_el(&listas, &busqueda, hoy)
    }
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
            motivo_jev: None,
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
            asignatura: None,
            uid: None,
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
    fn la_lista_de_una_asignatura_sale_aunque_este_vacia_y_con_su_color() {
        let mut v = vec![lista("a", "g1", "Geometría", false, vec![]), lista("c", "m0", "Nada", false, vec![])];
        v[0].asignatura = Some(0x0A84FF);
        let g = grupos_el(&v, "", HOY);
        assert_eq!(g.len(), 1, "solo la de la asignatura");
        assert_eq!(g[0].lista, 0);
        assert!(g[0].arriba.is_empty() && g[0].hechas.is_empty());
        assert_eq!(g[0].desde, 0x0A84FF);
        assert_eq!(g[0].hasta, degradado_de_asignatura(0x0A84FF).1);
        assert!(g[0].hasta < g[0].desde, "mas oscuro abajo");
        // Buscando, si su nombre coincide (sin tildes).
        assert_eq!(grupos_el(&v, "geometria", HOY).len(), 1);
        // Caso negativo: buscando otra cosa no sale.
        assert!(grupos_el(&v, "fontanero", HOY).is_empty());
    }

    #[test]
    fn lo_tachado_se_queda_arriba_y_el_orden_quieto_hasta_soltar() {
        let q = TareasQuietas::default();
        let l = sabado();
        let g = q.grupos_el(std::slice::from_ref(&l), "", HOY);
        assert_eq!((g[0].arriba.clone(), g[0].pendientes), (vec![1, 0], 2));
        // Se tacha «lavar el coche» (1): se guarda tachada, y se queda arriba.
        let mut tachada = l.clone();
        tachada.tareas[1].hecha = true;
        q.marcar("g/m1".into(), "lavar el coche".into(), true);
        let g = q.grupos_el(std::slice::from_ref(&tachada), "", HOY);
        assert_eq!(g[0].arriba, [1, 0], "en su sitio");
        assert_eq!(g[0].hechas, [2]);
        assert_eq!(g[0].pendientes, 1, "lo recien tachado no cuenta");
        // Jev contesta tarde: «comprar pan» urgente; no salta bajo el raton.
        let mut urgente = tachada.clone();
        urgente.tareas[0].prioridad = Some("urgente".into());
        assert_eq!(q.grupos_el(std::slice::from_ref(&urgente), "", HOY)[0].arriba, [1, 0]);
        // Al salir de Tareas, a «Hechas» y ordenado.
        q.soltar();
        let g = q.grupos_el(std::slice::from_ref(&urgente), "", HOY);
        assert_eq!((g[0].arriba.clone(), g[0].hechas.clone()), (vec![0], vec![1, 2]));
        // Caso negativo: sin marcar nada, como `grupos_de_tareas`.
        let otra = TareasQuietas::default();
        assert_eq!(otra.grupos_el(std::slice::from_ref(&l), "", HOY), grupos_el(std::slice::from_ref(&l), "", HOY));
    }

    #[test]
    fn lo_destachado_sigue_en_hechas_y_cuenta_como_pendiente() {
        let q = TareasQuietas::default();
        let l = sabado();
        q.grupos_el(std::slice::from_ref(&l), "", HOY);
        let mut destachada = l.clone();
        destachada.tareas[2].hecha = false;
        q.marcar("g/m1".into(), "llamar a mamá".into(), false);
        let g = q.grupos_el(std::slice::from_ref(&destachada), "", HOY);
        assert_eq!(g[0].hechas, [2], "se queda abajo");
        assert_eq!(g[0].pendientes, 3);
        // Buscar otra cosa es mirar de otra manera: se suelta.
        let g = q.grupos_el(std::slice::from_ref(&destachada), "mama", HOY);
        assert_eq!((g[0].arriba.clone(), g[0].hechas.clone()), (vec![2], vec![]));
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
