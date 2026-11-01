//! **La ventana de las figuras** (22 al 25-oct-2026 en Windows): las de
//! serie (`figuras_de_serie`: plantillas de pagina y simbolos por
//! categorias) y las propias, en una ventana aparte con categorias y su
//! cuenta, buscador, miniaturas, la elegida en grande con el intervalo de
//! las plantillas («del 1 al 40, de 10 en 10») y renombrar y quitar.
//!
//! Copia de lo que en Windows es `ventana_editor/figuras/ventana.rs` sin la
//! ventana (la pinta SwiftUI) y de lo de las figuras del chat
//! (`ventana_chat/figuras.rs`: adjuntar una figura al chat del asistente y
//! «Guardar en mis figuras» un lienzo del chat). La biblioteca es la de
//! siempre (`editor_figuras.rs`: `figuras.json` del chat «Asistente», el
//! formato del movil), con las de serie puestas una vez por version.
//!
//! Las miniaturas son el bufer plano de siempre (`lienzo.rs`): Swift las
//! pinta con `PintorLienzo`, como la vista previa de un lienzo en el chat.
//! Van **encuadradas a la caja de lo dibujado** (`miniatura`, como
//! `exportar::miniaturas` de Windows: la caja de sus elementos, con cada
//! trazo lo bastante grueso para que se vea encogido), y la cuenta de donde
//! cae la figura en la vista, con o sin zoom, es de aqui
//! ([`encuadre_de_figura`], [`acercar_figura`], [`mover_figura`]): la
//! vista previa grande se acerca, se aleja y se mueve.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};

use pindesk_motor2d::biblioteca::{self, FiguraGuardada};
use pindesk_motor2d::figuras_de_serie::{self as serie, Intervalo};
use pindesk_motor2d::vector::Punto2;

use crate::editor::EditorLienzo;
use crate::editor_figuras::FiguraDeBiblioteca;
use crate::lienzo::LienzoPlano;
use crate::{ErrorNucleo, Nucleo};

/// El grupo de las que no llevan categoria (`figuras-mis-figuras`).
pub const MIS_FIGURAS: &str = "Mis figuras";
/// Entre las hojas de una plantilla alargada (`al_lienzo.rs` de Windows).
const ENTRE_HOJAS: f32 = 60.0;

/// Una figura en la rejilla.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FichaDeFigura {
    pub id: String,
    /// El nombre entero («Diario · Gratitud»): el que se renombra.
    pub nombre: String,
    /// El nombre sin la categoria («Gratitud»): el que se ensena.
    pub corto: String,
    /// Su categoria («Diario»), o «Mis figuras».
    pub categoria: String,
    pub de_serie: bool,
    /// Si es una plantilla que se alarga con un intervalo.
    pub alargable: bool,
    pub piezas: u32,
    pub ancho: f32,
    pub alto: f32,
}

/// Una categoria de la barra de la izquierda con cuantas tiene.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CategoriaDeFiguras {
    pub nombre: String,
    pub cuenta: u32,
}

/// Un campo del intervalo de una plantilla, con su rotulo y la pista de lo
/// que trae la de serie.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CampoDeIntervalo {
    /// `desde`, `hasta`, `de_a`, `semanas_desde`, `semanas_hasta`, `mes` o
    /// `meses`.
    pub clave: String,
    pub rotulo: String,
    pub pista: String,
    /// Va solo en su fila (el «de … en …»); los demas, de dos en dos.
    pub a_lo_ancho: bool,
}

/// Lo tecleado en un campo del intervalo.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ValorDeCampo {
    pub clave: String,
    pub texto: String,
}

/// Lo que dice el panel bajo el intervalo: «4 hojas» o lo que falla.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PreviaDeIntervalo {
    pub texto: String,
    pub error: bool,
}

/// De que esta hecha una figura (el previsualizador del chat de Windows).
#[derive(Debug, Clone, Default, PartialEq, Eq, uniffi::Record)]
pub struct DetalleDeFigura {
    pub total: u32,
    pub trazos: u32,
    pub lineas: u32,
    pub formas: u32,
    pub textos: u32,
    pub otras: u32,
    /// Los textos que lleva, en orden de lectura.
    pub letras: Vec<String>,
}

/// Un grupo del menu de adjuntar una figura: su nombre y sus figuras (con
/// el nombre corto).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GrupoDeFiguras {
    pub nombre: String,
    pub figuras: Vec<FiguraDeBiblioteca>,
}

// ---------------------------------------------------------------------------
// Lo que se decide (las funciones puras de `ventana.rs` de Windows)
// ---------------------------------------------------------------------------

/// Las categorias en su orden: las de serie, las del usuario y «Mis
/// figuras» (las que no llevan categoria).
fn categorias(figuras: &[FiguraGuardada]) -> Vec<String> {
    let mut v: Vec<String> = serie::CATEGORIAS.iter().map(|c| c.to_string()).collect();
    for f in figuras {
        if let Some((c, _)) = serie::categoria_de(&f.nombre)
            && !v.iter().any(|o| o == c)
        {
            v.push(c.to_string());
        }
    }
    v.push(MIS_FIGURAS.to_string());
    v
}

/// La categoria de una figura (las sin categoria, en «Mis figuras») y su
/// nombre sin ella.
fn de_que_es(f: &FiguraGuardada) -> (&str, &str) {
    serie::categoria_de(&f.nombre).unwrap_or((MIS_FIGURAS, f.nombre.as_str()))
}

/// Sin tildes ni mayusculas, para buscar.
fn plegar(s: &str) -> String {
    pindesk_ia::acciones::normalizar(s)
}

/// **Las que se ven**: de la categoria `cat` (`None`, todas) y con todas las
/// palabras buscadas en el nombre (que lleva la categoria), en el orden de
/// las categorias.
fn visibles(figuras: &[FiguraGuardada], cat: Option<&str>, consulta: &str) -> Vec<usize> {
    let palabras: Vec<String> = plegar(consulta)
        .split_whitespace()
        .map(str::to_string)
        .collect();
    let mut v = Vec::new();
    for c in categorias(figuras) {
        if cat.is_some_and(|x| x != c) {
            continue;
        }
        for (i, f) in figuras.iter().enumerate() {
            if de_que_es(f).0 != c {
                continue;
            }
            let donde = plegar(&f.nombre);
            if palabras.iter().all(|p| donde.contains(p.as_str())) {
                v.push(i);
            }
        }
    }
    v
}

/// La clave de serie de una figura, si es una plantilla que se alarga.
fn alargable(f: &FiguraGuardada) -> Option<&str> {
    serie::clave_de(f).filter(|c| serie::se_alarga(c))
}

/// Los campos que lleva el panel para esa plantilla.
fn campos_de(clave: &str) -> &'static [&'static str] {
    match clave {
        "planificador-mensual" => &["mes", "meses"],
        "habitos" => &["desde", "hasta", "de_a", "mes", "meses"],
        "cronograma" => &["desde", "hasta", "de_a", "semanas_desde", "semanas_hasta"],
        _ => &["desde", "hasta", "de_a"],
    }
}

/// El rotulo y la pista de un campo (los textos de `figuras-ventana-*`).
fn campo(clave_plantilla: &str, c: &str) -> CampoDeIntervalo {
    let tramo = serie::tramo_de_serie(clave_plantilla);
    let (rotulo, pista) = match c {
        "desde" => ("Del", tramo.map(|t| t.0.to_string()).unwrap_or_default()),
        "hasta" => ("Al", tramo.map(|t| t.1.to_string()).unwrap_or_default()),
        "de_a" => (
            "De … en … (una hoja por cada tantos)",
            "Todo en una hoja".to_string(),
        ),
        "semanas_desde" => ("Semana desde", "1".into()),
        "semanas_hasta" => ("Semana hasta", "12".into()),
        "mes" => ("Mes", "2026-11".into()),
        _ => ("Cuántos meses", "1".into()),
    };
    CampoDeIntervalo {
        clave: c.to_string(),
        rotulo: rotulo.to_string(),
        pista,
        a_lo_ancho: c == "de_a",
    }
}

/// **El intervalo de los campos** (`None` si estan todos vacios: la de
/// serie, tal cual). Error en palabras si algo no es un numero.
fn intervalo_de(valores: &[ValorDeCampo]) -> Result<Option<Intervalo>, String> {
    let campos: HashMap<&str, &str> = valores
        .iter()
        .map(|v| (v.clave.as_str(), v.texto.trim()))
        .filter(|(_, t)| !t.is_empty())
        .collect();
    let n = |c: &str| -> Result<Option<u32>, String> {
        match campos.get(c) {
            None => Ok(None),
            Some(s) => s
                .parse()
                .map(Some)
                .map_err(|_| format!("«{s}» no es un número")),
        }
    };
    let mes = match campos.get("mes") {
        None => None,
        Some(s) => Some(
            pindesk_ia::figuras::mes_de(s)
                .ok_or_else(|| format!("«{s}»: escribe el mes como 2026-11"))?,
        ),
    };
    let semanas = match (n("semanas_desde")?, n("semanas_hasta")?) {
        (None, None) => None,
        (a, b) => Some((a.unwrap_or(1), b.or(a).unwrap_or(12))),
    };
    let iv = Intervalo {
        desde: n("desde")?,
        hasta: n("hasta")?,
        de_a: n("de_a")?,
        semanas,
        mes,
        meses: n("meses")?,
        ..Default::default()
    };
    Ok((iv != Intervalo::default()).then_some(iv))
}

/// Solo los valores de los campos de esa plantilla (lo demas no cuenta).
fn de_la_plantilla(clave: &str, valores: &[ValorDeCampo]) -> Vec<ValorDeCampo> {
    let cs = campos_de(clave);
    valores
        .iter()
        .filter(|v| cs.contains(&v.clave.as_str()))
        .cloned()
        .collect()
}

/// De que esta hecha una figura (`piezas_de` y `letras_de` de Windows).
fn detalle_de(f: &FiguraGuardada) -> DetalleDeFigura {
    use pindesk_motor2d::Figura as F;
    let mut p = DetalleDeFigura::default();
    let mut letras: Vec<(f32, f32, String)> = Vec::new();
    for e in f.elementos.iter().filter(|e| !e.borrado) {
        p.total += 1;
        match &e.figura {
            F::Lapiz { .. } | F::Resaltador { .. } => p.trazos += 1,
            F::Linea { .. } | F::Flecha { .. } | F::Arco { .. } | F::Cota { .. } => p.lineas += 1,
            F::Rectangulo | F::Rombo | F::Elipse | F::Region { .. } => p.formas += 1,
            F::Texto { texto, .. } => {
                p.textos += 1;
                if !texto.trim().is_empty() {
                    letras.push((e.y, e.x, texto.trim().replace('\n', " ")));
                }
            }
            _ => p.otras += 1,
        }
    }
    letras.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.total_cmp(&b.1)));
    p.letras = letras.into_iter().map(|(_, _, t)| t).collect();
    p
}

fn ficha_de(f: &FiguraGuardada) -> FichaDeFigura {
    let (categoria, corto) = de_que_es(f);
    let (ancho, alto) = f.tamano();
    FichaDeFigura {
        id: f.id.clone(),
        nombre: f.nombre.clone(),
        corto: corto.to_string(),
        categoria: categoria.to_string(),
        de_serie: serie::es_de_serie(f),
        alargable: alargable(f).is_some(),
        piezas: f.elementos.iter().filter(|e| !e.borrado).count() as u32,
        ancho,
        alto,
    }
}

/// **La escena de un lienzo con la figura dentro**, desde el origen
/// (`escena_con` de Windows: la del chat y la de las miniaturas).
fn escena_con(f: &FiguraGuardada) -> pindesk_motor2d::Escena {
    let mut escena = pindesk_motor2d::Escena::nueva();
    let (w, h) = f.tamano();
    biblioteca::estampar_en_escena(&mut escena, f, Punto2::nuevo(w / 2.0, h / 2.0));
    escena
}

/// **La escena de la miniatura** de `lado` puntos: la de [`escena_con`]
/// con cada trazo de al menos 0,9 puntos ya encogido (Windows: «encogida,
/// una raya de 1 px de una hoja entera no llega a un pixel y la miniatura
/// de un bloc saldria en blanco»).
fn escena_de_miniatura(f: &FiguraGuardada, lado: u32) -> pindesk_motor2d::Escena {
    let mut escena = escena_con(f);
    if let Some((x0, y0, x1, y1)) = escena.caja() {
        let k = lado.max(1) as f32 / (x1 - x0).max(y1 - y0).max(1.0);
        for e in &mut escena.elementos {
            e.grosor = e.grosor.max(0.9 / k);
        }
    }
    escena
}

/// El plano de una escena con la caja de lo que se ve en ella.
fn plano_de(escena: &pindesk_motor2d::Escena) -> Option<LienzoPlano> {
    let caja = escena.caja()?;
    Some(crate::lienzo::empaquetar(
        &crate::grafito_plano::ordenes_de_escena(escena),
        escena.fondo,
        Some(caja),
    ))
}

// ---------------------------------------------------------------------------
// Donde cae la figura en su vista (miniatura y vista previa con zoom)
// ---------------------------------------------------------------------------

/// Lo mas que se acerca la vista previa (por encima de la figura encajada).
pub const ZOOM_MAXIMO: f32 = 32.0;
/// Lo mas que se aleja: la mitad de encajada.
pub const ZOOM_MINIMO: f32 = 0.5;

/// **Como se pinta la figura en una vista**: un punto del mundo `(x, y)` va
/// a `(x * escala + dx, y * escala + dy)` de la vista (Y hacia abajo).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct EncuadreDeFigura {
    pub escala: f32,
    pub dx: f32,
    pub dy: f32,
}

/// **Lo que se ve de la figura** en la vista previa: `zoom` 1 es encajada
/// entera; `centro_x, centro_y`, el punto del mundo que cae en el centro
/// de la vista.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct VistaDeFigura {
    pub zoom: f32,
    pub centro_x: f32,
    pub centro_y: f32,
}

/// La escala con que `caja` cabe entera en `ancho` x `alto` con `aire` a
/// cada lado, sin deformar (`encajar` de Windows).
fn escala_encajada(caja: crate::lienzo::CajaLienzo, ancho: f32, alto: f32, aire: f32) -> f32 {
    let (w, h) = ((caja.x1 - caja.x0).max(1.0), (caja.y1 - caja.y0).max(1.0));
    let util = |v: f32| (v - 2.0 * aire).max(1.0);
    (util(ancho) / w).min(util(alto) / h)
}

/// **La figura encajada y centrada** en la vista: solo la zona de la
/// figura, sin lo que sobre del lienzo.
#[uniffi::export]
pub fn encuadre_de_figura(
    caja: crate::lienzo::CajaLienzo,
    ancho: f32,
    alto: f32,
    aire: f32,
) -> EncuadreDeFigura {
    encuadre_con_zoom(caja, ancho, alto, aire, vista_encajada(caja))
}

/// La vista previa recien abierta: entera y centrada.
#[uniffi::export]
pub fn vista_encajada(caja: crate::lienzo::CajaLienzo) -> VistaDeFigura {
    VistaDeFigura {
        zoom: 1.0,
        centro_x: (caja.x0 + caja.x1) / 2.0,
        centro_y: (caja.y0 + caja.y1) / 2.0,
    }
}

/// **El encuadre con zoom**: la escala encajada por `vista.zoom`, con el
/// centro de la vista en `vista.centro`.
#[uniffi::export]
pub fn encuadre_con_zoom(
    caja: crate::lienzo::CajaLienzo,
    ancho: f32,
    alto: f32,
    aire: f32,
    vista: VistaDeFigura,
) -> EncuadreDeFigura {
    let escala = escala_encajada(caja, ancho, alto, aire) * vista.zoom;
    EncuadreDeFigura {
        escala,
        dx: ancho / 2.0 - vista.centro_x * escala,
        dy: alto / 2.0 - vista.centro_y * escala,
    }
}

/// El centro no sale de la caja: siempre se ve algo de la figura.
fn sujetar(caja: crate::lienzo::CajaLienzo, v: VistaDeFigura) -> VistaDeFigura {
    let zoom = v.zoom.clamp(ZOOM_MINIMO, ZOOM_MAXIMO);
    if zoom <= 1.0 {
        // Encajada o mas lejos: centrada, que no hay nada que buscar.
        return VistaDeFigura {
            zoom,
            ..vista_encajada(caja)
        };
    }
    VistaDeFigura {
        zoom,
        centro_x: v.centro_x.clamp(caja.x0.min(caja.x1), caja.x1.max(caja.x0)),
        centro_y: v.centro_y.clamp(caja.y0.min(caja.y1), caja.y1.max(caja.y0)),
    }
}

/// **Acerca (`factor` > 1) o aleja (< 1)** la vista previa dejando quieto lo
/// que hay bajo el punto `(px, py)` de la vista (el raton, o el centro con
/// los botones), entre la mitad de encajada y 32 veces.
#[uniffi::export]
#[allow(clippy::too_many_arguments)]
pub fn acercar_figura(
    caja: crate::lienzo::CajaLienzo,
    ancho: f32,
    alto: f32,
    aire: f32,
    vista: VistaDeFigura,
    factor: f32,
    px: f32,
    py: f32,
) -> VistaDeFigura {
    if !factor.is_finite() || factor <= 0.0 {
        return vista;
    }
    let antes = encuadre_con_zoom(caja, ancho, alto, aire, vista);
    // El punto del mundo bajo el raton.
    let (mx, my) = (
        (px - antes.dx) / antes.escala,
        (py - antes.dy) / antes.escala,
    );
    let zoom = (vista.zoom * factor).clamp(ZOOM_MINIMO, ZOOM_MAXIMO);
    let escala = escala_encajada(caja, ancho, alto, aire) * zoom;
    // Que siga bajo el raton: centro = m - (p - mitad) / escala.
    sujetar(
        caja,
        VistaDeFigura {
            zoom,
            centro_x: mx - (px - ancho / 2.0) / escala,
            centro_y: my - (py - alto / 2.0) / escala,
        },
    )
}

/// **Mueve la vista previa** `(dx, dy)` puntos de la vista (arrastrar con el
/// raton o deslizar dos dedos): la figura va con el dedo.
#[uniffi::export]
pub fn mover_figura(
    caja: crate::lienzo::CajaLienzo,
    ancho: f32,
    alto: f32,
    aire: f32,
    vista: VistaDeFigura,
    dx: f32,
    dy: f32,
) -> VistaDeFigura {
    let e = encuadre_con_zoom(caja, ancho, alto, aire, vista);
    sujetar(
        caja,
        VistaDeFigura {
            centro_x: vista.centro_x - dx / e.escala,
            centro_y: vista.centro_y - dy / e.escala,
            ..vista
        },
    )
}

/// Lo del usuario primero y las categorias de serie en su orden; una
/// inventada por el usuario, detras (`orden_del_grupo` de Windows).
fn orden_del_grupo(g: &str) -> usize {
    if g == MIS_FIGURAS {
        0
    } else {
        serie::CATEGORIAS
            .iter()
            .position(|c| *c == g)
            .map_or(serie::CATEGORIAS.len() + 1, |i| i + 1)
    }
}

/// Los grupos del menu de adjuntar: lo del usuario primero y las categorias
/// en su orden (`por_grupos` de Windows).
fn por_grupos(figuras: &[FiguraGuardada]) -> Vec<GrupoDeFiguras> {
    let mut v: Vec<GrupoDeFiguras> = Vec::new();
    for f in figuras {
        let (g, n) = de_que_es(f);
        let figura = FiguraDeBiblioteca {
            id: f.id.clone(),
            nombre: n.to_string(),
        };
        match v.iter_mut().find(|x| x.nombre == g) {
            Some(x) => x.figuras.push(figura),
            None => v.push(GrupoDeFiguras {
                nombre: g.to_string(),
                figuras: vec![figura],
            }),
        }
    }
    v.sort_by_key(|g| orden_del_grupo(&g.nombre));
    v
}

/// Lo que mide una fila de hojas.
fn medida_de_las_hojas(hojas: &[FiguraGuardada]) -> (f32, f32) {
    let ancho = hojas.iter().map(|f| f.tamano().0).sum::<f32>()
        + ENTRE_HOJAS * hojas.len().saturating_sub(1) as f32;
    (
        ancho,
        hojas.iter().map(|f| f.tamano().1).fold(0.0, f32::max),
    )
}

impl EditorLienzo {
    /// **Las hojas de una plantilla alargada en fila**, centradas en
    /// `centro`, cada una su grupo, en un paso de deshacer y elegidas
    /// (`colocar_hojas_en_medio` de Windows).
    pub(crate) fn estampar_hojas(&self, hojas: &[FiguraGuardada], centro: Punto2) -> bool {
        let mut guarda = self.tomar();
        let st = &mut *guarda;
        if !st.gesto.en_reposo() || hojas.is_empty() {
            return false;
        }
        st.gesto.cerrar_texto(&mut st.escena);
        let (ancho, alto) = medida_de_las_hojas(hojas);
        let (mut x, y0) = (centro.x - ancho / 2.0, centro.y - alto / 2.0);
        let mut ids = Vec::new();
        st.escena.abrir_paso();
        for f in hojas {
            let (w, h) = f.tamano();
            let primero = st.escena.siguiente_id.max(1);
            let grupo = format!("g{primero}");
            let c = Punto2::nuevo(x + w / 2.0, y0 + h / 2.0);
            for e in biblioteca::estampar(f, c, primero, &grupo) {
                ids.push(st.escena.anadir(e));
            }
            x += w + ENTRE_HOJAS;
        }
        st.escena.cerrar_paso();
        if ids.is_empty() {
            return false;
        }
        st.gesto
            .tomar_herramienta(pindesk_motor2d::gesto::Herramienta::Mano);
        st.gesto.seleccion.poner_todos(ids);
        drop(guarda);
        self.subir_cambios();
        self.subir_version();
        true
    }
}

#[uniffi::export]
impl EditorLienzo {
    /// **El nombre que se propone al guardar lo elegido como figura**: si es
    /// una plantilla de serie (una alargada), su nombre con la categoria y
    /// un espacio («Planificación · Lista de tareas »), para que caiga en su
    /// categoria; si no, vacio (`guardar_seleccion` de Windows).
    pub fn nombre_propuesto_de_figura(&self) -> String {
        let elegidas: Vec<pindesk_motor2d::Elemento> = {
            let st = self.tomar();
            st.escena
                .visibles()
                .filter(|e| st.gesto.seleccion.contiene(e.id))
                .cloned()
                .collect()
        };
        serie::cual_es(&elegidas)
            .and_then(|clave| {
                serie::catalogo()
                    .into_iter()
                    .find(|f| serie::clave_de(f) == Some(clave.as_str()))
            })
            .map(|f| format!("{} ", f.nombre))
            .unwrap_or_default()
    }
}

// ---------------------------------------------------------------------------
// La ventana
// ---------------------------------------------------------------------------

/// **La biblioteca abierta en la ventana de las figuras**: se lee una vez
/// al abrirla (el catalogo es grande) y se busca y se filtra en memoria.
/// Renombrar y quitar se guardan al momento y viajan.
#[derive(uniffi::Object)]
pub struct GaleriaFiguras {
    nucleo: Arc<Nucleo>,
    figuras: Mutex<Vec<FiguraGuardada>>,
    /// **El interruptor ☀/☾** (Windows 22878f0, 4d7c01e, 9848a06): de noche
    /// se ven las gemelas «(noche)» de las plantillas en el sitio de las de
    /// dia, nunca las dos (`figuras_de_serie::segun_el_modo`).
    noche: std::sync::atomic::AtomicBool,
}

/// Las posiciones de `figuras` que se ven de dia o de noche, en su orden.
fn del_modo(figuras: &[FiguraGuardada], noche: bool) -> Vec<usize> {
    let pares: Vec<(&str, &str)> = figuras
        .iter()
        .map(|f| (f.id.as_str(), f.nombre.as_str()))
        .collect();
    serie::segun_el_modo(&pares, noche)
}

/// **Si los paneles de figuras van de noche**: `figuras_de_noche` de
/// `estado.toml`, el mismo de Windows; sin tocar, de dia, como el movil.
fn figuras_de_noche(nucleo: &Nucleo) -> bool {
    pindesk_store::estado::cargar(&nucleo.ubicacion())
        .figuras_de_noche
        .unwrap_or(false)
}

impl GaleriaFiguras {
    fn tomar(&self) -> MutexGuard<'_, Vec<FiguraGuardada>> {
        self.figuras.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Las del modo puesto (dia o noche), en su orden de siempre.
    fn las_del_modo(&self) -> Vec<FiguraGuardada> {
        let figuras = self.tomar();
        del_modo(
            &figuras,
            self.noche.load(std::sync::atomic::Ordering::Relaxed),
        )
        .into_iter()
        .map(|i| figuras[i].clone())
        .collect()
    }

    fn figura(&self, id: &str) -> Option<FiguraGuardada> {
        self.tomar().iter().find(|f| f.id == id).cloned()
    }

    /// Las hojas que pide el intervalo, `None` si se inserta tal cual.
    fn hojas(
        &self,
        f: &FiguraGuardada,
        valores: &[ValorDeCampo],
    ) -> Result<Option<Vec<FiguraGuardada>>, String> {
        let Some(clave) = alargable(f) else {
            return Ok(None);
        };
        match intervalo_de(&de_la_plantilla(clave, valores))? {
            None => Ok(None),
            Some(iv) => serie::alargar(clave, &iv).map(Some),
        }
    }

    /// Cambia la lista y la guarda (y la hace viajar).
    fn cambiar(
        &self,
        cambio: impl FnOnce(&mut Vec<FiguraGuardada>) -> bool,
    ) -> Result<bool, ErrorNucleo> {
        let lista = {
            let mut figuras = self.tomar();
            if !cambio(&mut figuras) {
                return Ok(false);
            }
            figuras.clone()
        };
        self.nucleo.guardar_biblioteca(&lista)
    }
}

#[uniffi::export]
impl GaleriaFiguras {
    /// Vuelve a leer la biblioteca (llego una por la sincro, se guardo una
    /// desde el lienzo).
    pub fn releer(&self) -> Result<(), ErrorNucleo> {
        let lista = self.nucleo.biblioteca_cargar()?;
        *self.tomar() = lista;
        Ok(())
    }

    /// Cuantas hay en el modo puesto (el subtitulo: «N figuras y
    /// plantillas»).
    pub fn cuantas(&self) -> u32 {
        let figuras = self.tomar();
        del_modo(
            &figuras,
            self.noche.load(std::sync::atomic::Ordering::Relaxed),
        )
        .len() as u32
    }

    /// **Si va de noche** (el interruptor ☀/☾). Se relee de `estado.toml`:
    /// el de la otra ventana de figuras pudo cambiarlo.
    pub fn de_noche(&self) -> bool {
        let noche = figuras_de_noche(&self.nucleo);
        self.noche
            .store(noche, std::sync::atomic::Ordering::Relaxed);
        noche
    }

    /// **Pone el interruptor ☀/☾** y lo recuerda (uno para todos los paneles
    /// de figuras). Si no se puede guardar solo se pierde que se recuerde.
    pub fn poner_de_noche(&self, noche: bool) {
        self.noche
            .store(noche, std::sync::atomic::Ordering::Relaxed);
        let u = self.nucleo.ubicacion();
        let mut e = pindesk_store::estado::cargar(&u);
        e.figuras_de_noche = Some(noche);
        let _ = pindesk_store::estado::guardar(&u, &e);
    }

    /// **Las categorias de la izquierda** con su cuenta, en su orden: las
    /// que tienen alguna y siempre «Mis figuras» (al final). «Todas» la
    /// pone la ventana.
    pub fn categorias(&self) -> Vec<CategoriaDeFiguras> {
        let figuras = self.las_del_modo();
        categorias(&figuras)
            .into_iter()
            .map(|c| {
                let cuenta = figuras.iter().filter(|f| de_que_es(f).0 == c).count() as u32;
                CategoriaDeFiguras { nombre: c, cuenta }
            })
            .filter(|c| c.cuenta > 0 || c.nombre == MIS_FIGURAS)
            .collect()
    }

    /// **Las que se ven** en la categoria (`None`, todas) con lo buscado,
    /// en el orden de las categorias.
    pub fn visibles(&self, categoria: Option<String>, consulta: String) -> Vec<FichaDeFigura> {
        let figuras = self.las_del_modo();
        visibles(&figuras, categoria.as_deref(), &consulta)
            .into_iter()
            .map(|i| ficha_de(&figuras[i]))
            .collect()
    }

    /// **La figura tal cual**: el bufer plano de su lienzo (`lienzo.rs`),
    /// con la caja de lo dibujado (la vista previa con zoom). `None` si no
    /// esta o no tiene piezas.
    pub fn plano(&self, id: String) -> Option<LienzoPlano> {
        plano_de(&escena_con(&self.figura(&id)?))
    }

    /// **La miniatura** de la figura `id` para pintarla en `lado` puntos: su
    /// plano con la caja de lo dibujado (solo la zona de la figura, como
    /// Windows) y cada trazo lo bastante grueso para que se vea.
    pub fn miniatura(&self, id: String, lado: u32) -> Option<LienzoPlano> {
        plano_de(&escena_de_miniatura(&self.figura(&id)?, lado))
    }

    /// De que piezas esta hecha y los textos que lleva.
    pub fn detalle(&self, id: String) -> Option<DetalleDeFigura> {
        self.figura(&id).map(|f| detalle_de(&f))
    }

    /// **Los campos del intervalo** de la figura `id`; ninguno si no es una
    /// plantilla que se alarga.
    pub fn campos(&self, id: String) -> Vec<CampoDeIntervalo> {
        let Some(f) = self.figura(&id) else {
            return Vec::new();
        };
        let Some(clave) = alargable(&f) else {
            return Vec::new();
        };
        campos_de(clave).iter().map(|c| campo(clave, c)).collect()
    }

    /// **Lo que saldria con ese intervalo** («4 hojas») o lo que falla;
    /// `None` con los campos vacios (la de serie, tal cual).
    pub fn previa(&self, id: String, valores: Vec<ValorDeCampo>) -> Option<PreviaDeIntervalo> {
        let f = self.figura(&id)?;
        match self.hojas(&f, &valores) {
            Ok(None) => None,
            Ok(Some(h)) => Some(PreviaDeIntervalo {
                texto: if h.len() == 1 {
                    "1 hoja".into()
                } else {
                    format!("{} hojas", h.len())
                },
                error: false,
            }),
            Err(texto) => Some(PreviaDeIntervalo { texto, error: true }),
        }
    }

    /// **Inserta la figura `id`** en `editor`, centrada en `(centro_x,
    /// centro_y)` y elegida, en un paso de deshacer; una plantilla con su
    /// intervalo, ya alargada (sus hojas en fila). Error con el aviso si el
    /// intervalo no vale.
    pub fn insertar(
        &self,
        id: String,
        valores: Vec<ValorDeCampo>,
        editor: Arc<EditorLienzo>,
        centro_x: f32,
        centro_y: f32,
    ) -> Result<bool, ErrorNucleo> {
        let Some(f) = self.figura(&id) else {
            return Ok(false);
        };
        let centro = Punto2::nuevo(centro_x, centro_y);
        match self.hojas(&f, &valores) {
            Ok(Some(h)) => Ok(editor.estampar_hojas(&h, centro)),
            Ok(None) => Ok(editor.estampar_figura(&f, centro)),
            Err(detalle) => Err(ErrorNucleo::Argumento { detalle }),
        }
    }

    /// **Renombra la figura `id`** (el nombre entero: con «Categoria · »
    /// delante cae en esa categoria). `false` si no cambia nada.
    pub fn renombrar(&self, id: String, nombre: String) -> Result<bool, ErrorNucleo> {
        let nuevo = nombre.trim().chars().take(80).collect::<String>();
        if nuevo.is_empty() {
            return Ok(false);
        }
        self.cambiar(|lista| match lista.iter_mut().find(|f| f.id == id) {
            Some(f) if f.nombre != nuevo => {
                f.nombre = nuevo;
                true
            }
            _ => false,
        })
    }

    /// **Quita la figura `id`** de la biblioteca.
    pub fn quitar(&self, id: String) -> Result<bool, ErrorNucleo> {
        self.cambiar(|lista| {
            let antes = lista.len();
            lista.retain(|f| f.id != id);
            lista.len() != antes
        })
    }
}

#[uniffi::export]
impl Nucleo {
    /// **Abre la biblioteca para la ventana de las figuras** (con las de
    /// serie puestas).
    pub fn galeria_de_figuras(self: Arc<Self>) -> Result<Arc<GaleriaFiguras>, ErrorNucleo> {
        let figuras = self.biblioteca_cargar()?;
        let noche = figuras_de_noche(&self);
        Ok(Arc::new(GaleriaFiguras {
            nucleo: self,
            figuras: Mutex::new(figuras),
            noche: std::sync::atomic::AtomicBool::new(noche),
        }))
    }

    /// **Las figuras por grupos** para el menu de adjuntar del asistente:
    /// lo del usuario primero, con el nombre corto.
    pub fn figuras_por_grupos(&self) -> Result<Vec<GrupoDeFiguras>, ErrorNucleo> {
        Ok(por_grupos(&self.biblioteca_cargar()?))
    }

    /// **Adjunta la figura `id` al chat**: un lienzo nuevo con la figura
    /// dentro y su nombre, para que el asistente la mejore
    /// (`adjuntar_figura` de Windows).
    pub fn adjuntar_figura(
        &self,
        chat: String,
        id: String,
    ) -> Result<crate::MensajeChat, ErrorNucleo> {
        let Some(f) = self.biblioteca_cargar()?.into_iter().find(|f| f.id == id) else {
            return Err(ErrorNucleo::NoExiste { que: id });
        };
        let nombre = de_que_es(&f).1.to_string();
        let m = self.crear_lienzo_con(chat.clone(), Some(nombre), |_| {})?;
        let dibujo = m.referencia.clone().unwrap_or_default();
        let ruta = pindesk_proyecto::almacen::lienzo(self.ruta(), &chat, &dibujo);
        use pindesk_motor2d::excalidraw;
        let lienzo = excalidraw::con_escena(&excalidraw::Lienzo::vacio(), &escena_con(&f));
        std::fs::write(&ruta, excalidraw::escribir(&lienzo))?;
        Ok(crate::MensajeChat::from(m))
    }

    /// **«Guardar en mis figuras»** el lienzo `dibujo` del chat: lo que se
    /// ve en el, con `nombre` (el del mensaje; sin el, «Figura de
    /// <chat>»). Devuelve el nombre con que quedo, o `None` si el lienzo
    /// esta vacio (`guardar_en_figuras` de Windows).
    pub fn guardar_lienzo_en_figuras(
        &self,
        chat: String,
        dibujo: String,
        nombre: String,
        nombre_del_chat: String,
    ) -> Result<Option<String>, ErrorNucleo> {
        crate::chats::validar_chat(&chat)?;
        if dibujo.is_empty() || dibujo.contains(['/', '\\', '\0']) || dibujo == ".." {
            return Err(ErrorNucleo::Argumento {
                detalle: format!("nombre no valido: {dibujo:?}"),
            });
        }
        let ruta = pindesk_proyecto::almacen::lienzo(self.ruta(), &chat, &dibujo);
        let texto = std::fs::read_to_string(&ruta)?;
        let l = pindesk_motor2d::excalidraw::leer(&texto).map_err(|e| ErrorNucleo::Lienzo {
            detalle: e.to_string(),
        })?;
        let escena = pindesk_motor2d::excalidraw::a_escena(&l);
        let piezas: Vec<pindesk_motor2d::Elemento> = escena.visibles().cloned().collect();
        if piezas.is_empty() {
            return Ok(None);
        }
        // Sin nombre puesto, la fila se llama como su fichero.
        let nombre = if nombre.trim().is_empty() || nombre.ends_with(".excalidraw") {
            format!("Figura de {}", nombre_del_chat.trim())
        } else {
            nombre.trim().to_string()
        };
        let nombre: String = nombre.chars().take(80).collect();
        let figura = FiguraGuardada {
            id: biblioteca::id_nuevo(),
            nombre: nombre.clone(),
            elementos: biblioteca::normalizar(&piezas),
        };
        if !self.biblioteca_anadir(figura)? {
            return Err(ErrorNucleo::Argumento {
                detalle: "no se pudo escribir la biblioteca de figuras".into(),
            });
        }
        Ok(Some(nombre))
    }
}

#[cfg(test)]
#[path = "galeria_figuras_pruebas.rs"]
mod pruebas;
