//! **Cada asignatura es un grupo de tareas** (Windows, 18-oct,
//! `horario/asignaturas.rs`): una lista de tareas con su nombre en el chat
//! «Asignaturas», un chat como cualquier otro (viaja al movil, se ve en el
//! chat y en Tareas). El chat se reconoce por una marca en el indice; si ya
//! habia uno llamado «Asignaturas» sin marca, se adopta. Borrar una
//! asignatura del horario NO borra su lista.
//!
//! **El enlace** (Windows 71bf70f, 1-nov-2026,
//! `docs/novedades-2026-11-01-asignaturas-con-tareas.md`): cada linea
//! `Asignatura …` de `horario.md` lleva `lista:<id>`, el `id` del mensaje de
//! su lista. Asi renombrar la asignatura (en su ficha de la vista Horario, o
//! a mano) renombra su lista y no la deja huerfana.
//! [`Nucleo::enlazar_asignaturas`] (el vigia del horario, al arrancar y a
//! cada cambio) crea las listas que faltan, apunta los enlaces y renombra.
//! En la ventana de Tareas las listas de las asignaturas salen con su color
//! y aunque esten vacias ([`colorear`], `ListaTareas::asignatura`). La lista
//! sigue siendo una lista como las demas: el movil no necesita saber nada
//! nuevo, y el formato en disco es el de Windows letra a letra.
//!
//! Lo que Windows deja para Flow Launcher (`cache/asignaturas.json`) no se
//! escribe en el Mac: Flow es de Windows.

use std::path::Path;
use std::sync::Mutex;

use pindesk_ia::fechas::Momento;
use pindesk_proyecto::{almacen, cuaderno, mini};

use super::{Asignatura, Horario};
use crate::tareas::ListaTareas;
use crate::{ErrorNucleo, Nucleo};

/// Como se llama el chat de las asignaturas.
pub const NOMBRE_CHAT: &str = "Asignaturas";
/// Su marca en el indice (la misma de Windows).
const MARCA: &str = "asignaturas";

/// Que no creen dos la misma lista a la vez: la vista Horario (al añadir
/// una asignatura) y el vigia del horario ([`Nucleo::enlazar_asignaturas`])
/// corren en hilos distintos (el `CERROJO` de Windows).
static CERROJO: Mutex<()> = Mutex::new(());

/// Minusculas y sin tildes, como `normalizar` de Windows.
fn plegar(s: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    s.nfd()
        .filter(|c| !unicode_normalization::char::is_combining_mark(*c))
        .collect::<String>()
        .to_lowercase()
}

fn tiene_marca(f: &almacen::Ficha) -> bool {
    f.resto.get(MARCA).and_then(|v| v.as_bool()) == Some(true)
}

/// El chat «Asignaturas» si ya esta (el de la marca o, si no, el que se
/// llama asi). No crea nada.
fn ficha(raiz: &Path) -> Option<almacen::Ficha> {
    let indice = almacen::Indice::leer_si_esta(raiz).ok()?;
    indice
        .proyectos
        .iter()
        .find(|f| tiene_marca(f))
        .or_else(|| indice.proyectos.iter().find(|f| f.nombre == NOMBRE_CHAT))
        .cloned()
}

/// **Su foto al nacer o al adoptarlo** (Windows d81934f8): el libro azul
/// 📘, para reconocerlo en la lista. Solo si aun no tiene una: la que elija
/// el usuario manda (tambien «volver a lo de siempre»).
fn poner_su_foto(f: &mut almacen::Ficha) {
    use pindesk_proyecto::{asignatura, avatar};
    if avatar::valor_de(f).is_none() {
        let a = avatar::Avatar::emoji(asignatura::EMOJI, Some(asignatura::FONDO), crate::ahora_ms());
        f.resto.insert(avatar::CLAVE.into(), a.a_valor());
    }
}

/// El chat «Asignaturas», creandolo (o adoptando uno con ese nombre), con
/// su marca y su foto.
fn asegurar_ficha(raiz: &Path, aparato: &str) -> Result<almacen::Ficha, ErrorNucleo> {
    let mut indice = almacen::Indice::leer_si_esta(raiz)?;
    if let Some(f) = indice.proyectos.iter_mut().find(|f| tiene_marca(f)) {
        // Uno de antes del 6-nov, sin foto: el libro, una vez.
        if pindesk_proyecto::avatar::valor_de(f).is_none() {
            poner_su_foto(f);
            let f = f.clone();
            indice.guardar(raiz)?;
            return Ok(f);
        }
        return Ok(f.clone());
    }
    let f = match indice.proyectos.iter_mut().find(|f| f.nombre == NOMBRE_CHAT) {
        Some(f) => {
            f.resto.insert(MARCA.into(), serde_json::Value::Bool(true));
            poner_su_foto(f);
            f.clone()
        }
        None => {
            let mut f = almacen::Ficha::nueva(NOMBRE_CHAT, crate::ahora_ms(), aparato);
            f.resto.insert(MARCA.into(), serde_json::Value::Bool(true));
            poner_su_foto(&mut f);
            indice.proyectos.push(f.clone());
            f
        }
    };
    indice.guardar(raiz)?;
    Ok(f)
}

/// **La lista de la asignatura que se llama `nombre`** entre `listas` (las
/// del chat «Asignaturas»): sin mirar mayusculas ni tildes (`asignaturas::de`
/// de Windows).
pub fn de<'a>(listas: &'a [ListaTareas], nombre: &str) -> Option<&'a ListaTareas> {
    let n = plegar(nombre.trim());
    listas.iter().find(|l| plegar(l.titulo.trim()) == n)
}

/// **La lista de la asignatura `a`** entre `listas`: la de su enlace
/// (`lista:<id>`, aunque la lista ya se llame de otra forma) y, si no lo
/// tiene o esa lista ya no esta, la de su nombre (`de_asignatura` de
/// Windows).
pub fn de_asignatura<'a>(listas: &'a [ListaTareas], a: &Asignatura) -> Option<&'a ListaTareas> {
    a.lista
        .as_deref()
        .and_then(|id| listas.iter().find(|l| l.mensaje == id))
        .or_else(|| de(listas, &a.nombre))
}

/// Lo que hay que hacer para que cada asignatura tenga su lista, ya
/// decidido ([`plan`]): lo puro de [`Nucleo::enlazar_asignaturas`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Paso {
    /// Crear la lista de la asignatura (no hay ninguna con su enlace ni con
    /// su nombre).
    Crear(String),
    /// La lista `.0` (su mensaje) es la de la asignatura `.1`, que no lo
    /// tenia apuntado: apuntar el enlace en su linea.
    Enlazar(String, String),
    /// La asignatura se renombro (a mano o en la ficha): la lista `.0` pasa
    /// a llamarse `.1`.
    Renombrar(String, String),
}

/// **Que falta** para que cada asignatura del horario tenga su lista y el
/// enlace apuntado (`plan` de Windows). `con_linea`: las de la lista lateral
/// (las que tienen linea `Asignatura …` donde apuntar el enlace);
/// `solo_en_clases`: las que solo nombra alguna clase, que tienen lista pero
/// no enlace. Manda el nombre del horario: si la lista enlazada se llama de
/// otra forma, se renombra.
pub fn plan(con_linea: &[Asignatura], solo_en_clases: &[Asignatura], listas: &[ListaTareas]) -> Vec<Paso> {
    let mut pasos = Vec::new();
    for a in con_linea {
        match de_asignatura(listas, a) {
            Some(l) if a.lista.as_deref() == Some(l.mensaje.as_str()) => {
                if l.titulo.trim() != a.nombre.trim() {
                    pasos.push(Paso::Renombrar(l.mensaje.clone(), a.nombre.clone()));
                }
            }
            Some(l) => pasos.push(Paso::Enlazar(l.mensaje.clone(), a.nombre.clone())),
            None => pasos.push(Paso::Crear(a.nombre.clone())),
        }
    }
    for a in solo_en_clases {
        if de(listas, &a.nombre).is_none() {
            pasos.push(Paso::Crear(a.nombre.clone()));
        }
    }
    pasos
}

/// **El color de las listas de las asignaturas** en la ventana de Tareas
/// (`colorear` de Windows): a cada lista del chat `chat` («Asignaturas»)
/// que es de una asignatura del horario, el color de la asignatura
/// (`ListaTareas::asignatura`). Asi salen con su color y, aunque esten
/// vacias, se ven para apuntarles tareas. Las demas, como estaban.
pub fn colorear(h: &Horario, chat: &str, todas: &mut [ListaTareas]) {
    let suyas: Vec<ListaTareas> = todas.iter().filter(|l| l.chat == chat).cloned().collect();
    for a in h.todas_las_asignaturas() {
        let Some(mensaje) = de_asignatura(&suyas, &a).map(|l| l.mensaje.clone()) else {
            continue;
        };
        let color = a.color.unwrap_or_else(|| super::semana::color_por_nombre(&a.nombre));
        if let Some(l) = todas.iter_mut().find(|l| l.chat == chat && l.mensaje == mensaje) {
            l.asignatura = Some(color);
        }
    }
}

impl Nucleo {
    /// Las listas de tareas del chat «Asignaturas» (vacio si aun no esta).
    fn listas_de_asignaturas(&self, ficha: &almacen::Ficha) -> Result<Vec<ListaTareas>, ErrorNucleo> {
        let fichero = almacen::carpeta(self.ruta(), &ficha.id).join("guardados.jsonl");
        let hoy = mini::Fecha::de_ms_locales(crate::ahora_ms());
        Ok(crate::tareas::listas_del_cuaderno(&fichero)?
            .iter()
            .filter(|m| !m.en_buzon)
            .map(|m| self.lista_de(ficha, m, hoy))
            .collect())
    }

    /// Las listas de las asignaturas de `todas`, con su color (lo llama
    /// `Nucleo::tareas`).
    pub(crate) fn colorear_asignaturas(&self, todas: &mut [ListaTareas], desfase_ms: i64) {
        let Some(f) = ficha(self.ruta()) else {
            return;
        };
        let h = super::de_disco(self.ruta(), Momento::de_ms_locales(crate::ahora_ms() + desfase_ms));
        colorear(&h, &f.id, todas);
    }

    /// La lista de la asignatura `a` ya escrita (la de su enlace o la de su
    /// nombre), sin crear nada.
    pub(crate) fn lista_leida_de_asignatura(&self, a: &Asignatura) -> Option<ListaTareas> {
        let f = ficha(self.ruta())?;
        de_asignatura(&self.listas_de_asignaturas(&f).ok()?, a).cloned()
    }

    /// La lista de la asignatura `nombre`, creandola (y el chat) si no esta,
    /// sin el cerrojo (`asegurar_lista_sin_cerrojo` de Windows).
    fn asegurar_lista_sin_cerrojo(&self, nombre: &str, desfase_ms: i64) -> Result<ListaTareas, ErrorNucleo> {
        let aparato = self.identidad()?.yo.codigo();
        let ficha = asegurar_ficha(self.ruta(), &aparato)?;
        let m = self.lista_o_nueva(&ficha, nombre)?;
        let hoy = mini::Fecha::de_ms_locales(crate::ahora_ms() + desfase_ms);
        Ok(self.lista_de(&ficha, &m, hoy))
    }

    /// **La lista de la asignatura que se llama `nombre`** (sin mirar
    /// mayusculas ni tildes, `lista_de_la_asignatura` de Windows): si esta en
    /// el horario, la de su enlace; si no, o aun no tiene, la de su nombre,
    /// creandola si hace falta. Lo que usan la caja de Tareas y los pedidos
    /// (`anadir_tarea` y `abrir_lista` con `asignatura`).
    pub(crate) fn lista_de_la_asignatura(&self, nombre: &str, desfase_ms: i64) -> Result<ListaTareas, ErrorNucleo> {
        let n = plegar(nombre.trim());
        if n.is_empty() {
            return Err(ErrorNucleo::Argumento { detalle: "falta la asignatura".into() });
        }
        let h = super::de_disco(self.ruta(), Momento::de_ms_locales(crate::ahora_ms() + desfase_ms));
        let a = h.todas_las_asignaturas().into_iter().find(|a| plegar(&a.nombre) == n);
        if let (Some(a), Some(f)) = (a.as_ref(), ficha(self.ruta()))
            && let Some(l) = de_asignatura(&self.listas_de_asignaturas(&f)?, a)
        {
            return Ok(l.clone());
        }
        // Con el nombre del horario, si esta: asi la lista nace bien escrita.
        let nombre = a.map_or_else(|| nombre.trim().to_string(), |a| a.nombre);
        let _c = CERROJO.lock().unwrap_or_else(|e| e.into_inner());
        self.asegurar_lista_sin_cerrojo(&nombre, desfase_ms)
    }

    /// **Renombra la lista** `mensaje` del chat `chat` (`asignaturas::renombrar`
    /// de Windows): cambia su titulo y deja sus tareas como estaban (hechas,
    /// fechas, imagenes). Es un mensaje reescrito, asi que el nombre nuevo
    /// viaja al movil como cualquier cambio de una lista.
    pub(crate) fn renombrar_lista_de_tareas(&self, chat: &str, mensaje: &str, nuevo: &str) -> Result<bool, ErrorNucleo> {
        crate::chats::validar_chat(chat)?;
        let nuevo = nuevo.trim();
        if nuevo.is_empty() {
            return Ok(false);
        }
        let carpeta = almacen::carpeta(self.ruta(), chat);
        let mut era_lista = true;
        let r = cuaderno::cambiar(&carpeta, mensaje, |m| {
            if !crate::tareas::es_lista(m) {
                era_lista = false;
                return false;
            }
            if crate::tareas::nombre_de_lista(m) == nuevo {
                return false;
            }
            let tareas = mini::leer_tareas(&m.texto);
            m.texto = mini::escribir_tareas(nuevo, &tareas);
            m.nombre = nuevo.to_string();
            true
        })?;
        if !era_lista {
            return Err(ErrorNucleo::Argumento { detalle: format!("no es una lista de tareas: {mensaje}") });
        }
        self.cache_tomada().quitar(&carpeta.join("guardados.jsonl"));
        Ok(r.is_some())
    }
}

#[uniffi::export]
impl Nucleo {
    /// Los nombres de las asignaturas del horario (la lista lateral y las de
    /// las clases), para elegir donde apuntar una tarea.
    pub fn nombres_de_asignaturas(&self, desfase_ms: i64) -> Vec<String> {
        let h = super::de_disco(self.ruta(), Momento::de_ms_locales(crate::ahora_ms() + desfase_ms));
        h.todas_las_asignaturas().into_iter().map(|a| a.nombre).collect()
    }

    /// **Apunta una tarea en la asignatura** `asignatura`: la lista de su
    /// enlace en el chat «Asignaturas» (o la de su nombre; los dos se crean
    /// si no estan).
    pub fn apuntar_en_asignatura(
        &self,
        asignatura: String,
        texto: String,
        imagenes: Vec<String>,
        desfase_ms: i64,
    ) -> Result<ListaTareas, ErrorNucleo> {
        let nombre = asignatura.trim();
        if nombre.is_empty() || (pindesk_proyecto::mini::saneado(&texto).is_empty() && imagenes.is_empty()) {
            return Err(ErrorNucleo::Argumento { detalle: "falta la asignatura o la tarea".into() });
        }
        let l = self.lista_de_la_asignatura(nombre, desfase_ms)?;
        self.apuntar_tarea_con_imagenes_en(l.chat, l.mensaje, texto, imagenes, desfase_ms)
    }

    /// **El grupo de tareas de una asignatura nueva**, ya (el «+» del
    /// Horario, `asignaturas::asegurar_lista` de Windows): su lista vacia en
    /// el chat «Asignaturas» (los dos se crean si no estan), para que salga
    /// en Tareas y en el chat. Si ya estaba, la de antes. Su `mensaje` es el
    /// enlace (`lista:<id>`) que se apunta en la linea de la asignatura.
    pub fn asegurar_lista_de_asignatura(&self, asignatura: String, desfase_ms: i64) -> Result<ListaTareas, ErrorNucleo> {
        let nombre = asignatura.trim();
        if nombre.is_empty() {
            return Err(ErrorNucleo::Argumento { detalle: "falta la asignatura".into() });
        }
        let _c = CERROJO.lock().unwrap_or_else(|e| e.into_inner());
        self.asegurar_lista_sin_cerrojo(nombre, desfase_ms)
    }

    /// **La lista de la asignatura que se llama `asignatura`**, creandola
    /// vacia si aun no tiene (los pedidos `anadir_tarea` y `abrir_lista` con
    /// `asignatura`, Windows dbbd4ec): la de su enlace en el horario o la de
    /// su nombre. Su clave (`chat/mensaje`) abre Tareas en ella.
    pub fn lista_para_asignatura(&self, asignatura: String, desfase_ms: i64) -> Result<ListaTareas, ErrorNucleo> {
        self.lista_de_la_asignatura(&asignatura, desfase_ms)
    }

    /// **La lista de la asignatura** `asignatura` entre `listas` (las de
    /// Tareas): la de su enlace en el horario o, si no, la del chat
    /// «Asignaturas» que se llama asi, sin tildes ni mayusculas. No crea
    /// nada: `None` si aun no tiene. Lo que ensena el Horario debajo de la
    /// elegida.
    pub fn lista_de_asignatura(&self, listas: Vec<ListaTareas>, asignatura: String) -> Option<ListaTareas> {
        let chat = ficha(self.ruta())?.id;
        let suyas: Vec<ListaTareas> = listas.into_iter().filter(|l| l.chat == chat).collect();
        let buscado = plegar(asignatura.trim());
        let h = super::de_disco(self.ruta(), Momento::de_ms_locales(crate::ahora_ms()));
        match h.todas_las_asignaturas().into_iter().find(|a| plegar(&a.nombre) == buscado) {
            Some(a) => de_asignatura(&suyas, &a).cloned(),
            None => de(&suyas, &asignatura).cloned(),
        }
    }

    /// **Cada asignatura con su lista** (Windows 71bf70f, `asignaturas::enlazar`;
    /// el usuario: «que cada asignatura se cree a la vez como asignatura y
    /// como grupo de tareas»): crea las que faltan (las de horarios de antes
    /// y las escritas a mano), apunta su enlace `lista:<id>` en `horario.md`
    /// (solo el final de las lineas `Asignatura …`) y renombra la lista de
    /// una asignatura renombrada. Lo llama el vigia del horario al arrancar y
    /// cada vez que `horario.md` cambia.
    ///
    /// No borra nada: una lista sin asignatura (se quito del horario) se
    /// queda en el chat con sus tareas. Devuelve si cambio algo.
    pub fn enlazar_asignaturas(&self, desfase_ms: i64) -> Result<bool, ErrorNucleo> {
        let ruta = super::ruta(self.ruta());
        let Ok(original) = std::fs::read_to_string(&ruta) else {
            return Ok(false);
        };
        let _c = CERROJO.lock().unwrap_or_else(|e| e.into_inner());
        let ahora = Momento::de_ms_locales(crate::ahora_ms() + desfase_ms);
        let h = super::leer(&original, ahora);
        let todas = h.todas_las_asignaturas();
        if todas.is_empty() {
            return Ok(false);
        }
        let solo_en_clases = &todas[h.asignaturas.len()..];
        // Con una asignatura, el chat esta siempre (Windows d81934f8): es
        // donde va todo lo suyo, aunque sus listas ya existieran.
        let mut cambio = false;
        if ficha(self.ruta())
            .is_none_or(|f| !tiene_marca(&f) || pindesk_proyecto::avatar::valor_de(&f).is_none())
        {
            let aparato = self.identidad()?.yo.codigo();
            asegurar_ficha(self.ruta(), &aparato)?;
            cambio = true;
        }
        let ls = match ficha(self.ruta()) {
            Some(f) => self.listas_de_asignaturas(&f)?,
            None => Vec::new(),
        };
        let pasos = plan(&h.asignaturas, solo_en_clases, &ls);
        let mut enlaces: Vec<(String, String)> = Vec::new();
        for p in &pasos {
            match p {
                Paso::Crear(nombre) => {
                    let l = self.asegurar_lista_sin_cerrojo(nombre, desfase_ms)?;
                    enlaces.push((plegar(nombre), l.mensaje));
                    cambio = true;
                }
                Paso::Enlazar(mensaje, nombre) => enlaces.push((plegar(nombre), mensaje.clone())),
                Paso::Renombrar(mensaje, nombre) => {
                    if let Some(l) = ls.iter().find(|l| &l.mensaje == mensaje) {
                        cambio |= self.renombrar_lista_de_tareas(&l.chat, &l.mensaje, nombre)?;
                        // Lo que era de la asignatura renombrada, tambien.
                        cambio |= self.reetiquetar(&l.chat, &l.titulo, nombre)? > 0;
                    }
                }
            }
        }
        let nuevo = super::con_enlaces(&original, &|a| {
            let n = plegar(&a.nombre);
            enlaces.iter().find(|(k, _)| *k == n).map(|(_, id)| id.clone())
        });
        // Si entre medias se guardo desde la ventana, lo suyo manda: el
        // vigia vuelve a pasar con el horario nuevo.
        if nuevo != original && std::fs::read_to_string(&ruta).ok().as_deref() == Some(original.as_str()) {
            let tmp = ruta.with_extension("md.parte");
            std::fs::write(&tmp, &nuevo)?;
            std::fs::rename(&tmp, &ruta)?;
            cambio = true;
        }
        Ok(cambio)
    }
}

// ------------------------------------------------- un chat para todas

/// Un chip de la fila de arriba del chat «Asignaturas»: la asignatura y su
/// color (`None`: ya no esta en el horario, sale en gris).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChipAsignatura {
    pub nombre: String,
    pub color: Option<u32>,
}

/// El dia de la semana (0 lunes) y el minuto del dia de `ms` locales.
fn dia_y_minuto(ms_locales: i64) -> (u8, u32) {
    let dia = ms_locales.div_euclid(86_400_000);
    // El 1-ene-1970 fue jueves (3 contando desde el lunes).
    (((dia + 3).rem_euclid(7)) as u8, (ms_locales.rem_euclid(86_400_000) / 60_000) as u32)
}

impl Nucleo {
    fn horario_de_ahora(&self, desfase_ms: i64) -> Option<Horario> {
        let texto = std::fs::read_to_string(super::ruta(self.ruta())).ok()?;
        Some(super::leer(&texto, Momento::de_ms_locales(crate::ahora_ms() + desfase_ms)))
    }

    /// Las asignaturas del horario con su color, en su orden.
    fn con_su_color(&self, desfase_ms: i64) -> Vec<(String, u32)> {
        self.horario_de_ahora(desfase_ms)
            .map(|h| {
                h.todas_las_asignaturas()
                    .into_iter()
                    .map(|a| {
                        let c = a.color.unwrap_or_else(|| super::semana::color_por_nombre(&a.nombre));
                        (a.nombre, c)
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn mensajes_de(&self, chat: &str) -> Vec<cuaderno::Mensaje> {
        cuaderno::Cuaderno::leer_de(&almacen::carpeta(self.ruta(), chat))
            .map(|c| c.mensajes)
            .unwrap_or_default()
    }

    fn olvidar_lo_leido(&self, chat: &str) {
        let fichero = almacen::carpeta(self.ruta(), chat).join("guardados.jsonl");
        self.cache_tomada().quitar(&fichero);
    }

    /// **La etiqueta de lo de una asignatura renombrada**: lo que llevaba
    /// `viejo` en el chat pasa a llevar `nuevo` (Windows `reetiquetar`).
    fn reetiquetar(&self, chat: &str, viejo: &str, nuevo: &str) -> Result<usize, ErrorNucleo> {
        let carpeta = almacen::carpeta(self.ruta(), chat);
        let mut mensajes = self.mensajes_de(chat);
        let cambiados = pindesk_proyecto::asignatura::renombrar(&mut mensajes, viejo, nuevo);
        for &i in &cambiados {
            cuaderno::reemplazar(&carpeta, &mensajes[i])?;
        }
        if !cambiados.is_empty() {
            self.olvidar_lo_leido(chat);
        }
        Ok(cambiados.len())
    }
}

#[uniffi::export]
impl Nucleo {
    /// **El chat «Asignaturas»** (el de la marca), si ya esta.
    pub fn chat_de_asignaturas(&self) -> Option<String> {
        ficha(self.ruta()).filter(tiene_marca).map(|f| f.id)
    }

    /// **Los chips de su fila**: las del horario con su color y, detras, las
    /// que solo nombran sus mensajes (en gris).
    pub fn chips_de_asignaturas(&self, desfase_ms: i64) -> Vec<ChipAsignatura> {
        use pindesk_proyecto::asignatura;
        let del_horario = asignatura::del_horario(&self.con_su_color(desfase_ms));
        let mensajes = self
            .chat_de_asignaturas()
            .map(|c| self.mensajes_de(&c))
            .unwrap_or_default();
        asignatura::chips(&del_horario, &mensajes)
            .into_iter()
            .map(|c| ChipAsignatura { nombre: c.nombre, color: c.color })
            .collect()
    }

    /// **Las asignaturas que ofrece el menu de un mensaje** («Asignatura…» en
    /// su chat, «Enviar a asignatura…» en los demas): sus chips o las del
    /// horario, y la que ya lleve, sin la puesta.
    pub fn asignaturas_para_el_menu(&self, chat: String, mensaje: String, desfase_ms: i64) -> Vec<String> {
        use pindesk_proyecto::asignatura;
        let mensajes = self.mensajes_de(&chat);
        let m = mensajes.iter().find(|m| m.id == mensaje);
        let puesta = m.and_then(asignatura::de);
        let mut cs = if self.chat_de_asignaturas().as_deref() == Some(chat.as_str()) {
            self.chips_de_asignaturas(desfase_ms)
                .into_iter()
                .map(|c| asignatura::Chip { nombre: c.nombre, color: c.color })
                .collect()
        } else {
            asignatura::del_horario(&self.con_su_color(desfase_ms))
        };
        if let Some(n) = puesta
            && !cs.iter().any(|c| asignatura::mismo(&c.nombre, n))
        {
            cs.push(asignatura::Chip { nombre: n.to_string(), color: None });
        }
        asignatura::para_enviar(&cs, puesta)
    }

    /// **La asignatura de la clase de ahora** (en marcha, o que empieza en
    /// diez minutos): de quien es lo que se graba ahora.
    pub fn asignatura_en_clase(&self, desfase_ms: i64) -> Option<String> {
        use pindesk_proyecto::asignatura;
        let h = self.horario_de_ahora(desfase_ms)?;
        let (dia, minuto) = dia_y_minuto(crate::ahora_ms() + desfase_ms);
        let tramos: Vec<asignatura::Tramo> = h
            .clases
            .iter()
            .map(|c| asignatura::Tramo { dias: &c.dias, inicio: c.inicio, fin: c.fin, nombre: &c.nombre })
            .collect();
        let n = asignatura::en_clase(&tramos, dia, minuto)?;
        Some(
            h.todas_las_asignaturas()
                .into_iter()
                .find(|a| asignatura::mismo(&a.nombre, n))
                .map_or_else(|| n.to_string(), |a| a.nombre),
        )
    }

    /// **Pone (o quita, con `""`) la asignatura** de unos mensajes de `chat`,
    /// con lo que lleven dentro (una carpeta, sus paginas). Devuelve cuantos
    /// cambiaron.
    pub fn poner_asignatura(&self, chat: String, mensajes: Vec<String>, nombre: String) -> Result<u32, ErrorNucleo> {
        use pindesk_proyecto::asignatura;
        let carpeta = almacen::carpeta(self.ruta(), &chat);
        let mut todos = self.mensajes_de(&chat);
        let elegidos: Vec<usize> = todos
            .iter()
            .enumerate()
            .filter(|(_, m)| mensajes.contains(&m.id))
            .map(|(i, _)| i)
            .collect();
        let mut n = 0;
        for i in asignatura::paquete(&todos, &elegidos) {
            let m = &mut todos[i];
            if asignatura::poner(m, &nombre) && cuaderno::reemplazar(&carpeta, m)? {
                n += 1;
            }
        }
        if n > 0 {
            self.olvidar_lo_leido(&chat);
        }
        Ok(n)
    }

    /// **Le pone su asignatura a lo nuevo** del chat «Asignaturas» con un chip
    /// elegido: lo de este Mac puesto desde `desde_ms`, entrara por donde
    /// entrara. Devuelve cuantos.
    pub fn etiquetar_lo_nuevo(&self, chat: String, nombre: String, desde_ms: i64) -> Result<u32, ErrorNucleo> {
        use pindesk_proyecto::asignatura;
        if nombre.trim().is_empty() || self.chat_de_asignaturas().as_deref() != Some(chat.as_str()) {
            return Ok(0);
        }
        let aparato = self.identidad()?.yo.codigo();
        let carpeta = almacen::carpeta(self.ruta(), &chat);
        let mut todos = self.mensajes_de(&chat);
        let mut n = 0;
        for i in asignatura::por_etiquetar(&todos, &aparato, desde_ms) {
            let m = &mut todos[i];
            asignatura::poner(m, &nombre);
            // Una hoja que solo esta en `proyecto.json` no tiene linea: nada.
            if cuaderno::reemplazar(&carpeta, m).unwrap_or(false) {
                n += 1;
            }
        }
        if n > 0 {
            self.olvidar_lo_leido(&chat);
        }
        Ok(n)
    }

    /// **«Enviar a asignatura…»** (Windows d81934f8): copia unos mensajes de
    /// `chat` al chat «Asignaturas» con su asignatura. Una carpeta va con lo
    /// suyo y sus enlaces se rehacen con los `id` de las copias; mandarlo
    /// otra vez no lo duplica (por su `origen`), solo le cambia la
    /// asignatura si iba a otra. Devuelve cuantos se copiaron o cambiaron.
    pub fn enviar_a_asignatura(&self, chat: String, mensajes: Vec<String>, nombre: String) -> Result<u32, ErrorNucleo> {
        use pindesk_proyecto::asignatura;
        if nombre.trim().is_empty() {
            return Ok(0);
        }
        let aparato = self.identidad()?.yo.codigo();
        let destino = asegurar_ficha(self.ruta(), &aparato)?.id;
        if destino == chat {
            return self.poner_asignatura(chat, mensajes, nombre);
        }
        let origen = self.mensajes_de(&chat);
        let elegidos: Vec<usize> = origen
            .iter()
            .enumerate()
            .filter(|(_, m)| mensajes.contains(&m.id))
            .map(|(i, _)| i)
            .collect();
        let todo = asignatura::paquete(&origen, &elegidos);
        let carpeta = almacen::carpeta(self.ruta(), &destino);
        let alli = self.mensajes_de(&destino);
        let mut n = 0u32;
        let mut por_copiar = Vec::new();
        for &i in &todo {
            let m = &origen[i];
            match asignatura::ya_esta(&alli, m) {
                Some(x) => {
                    if asignatura::de(x).is_none_or(|a| !asignatura::mismo(a, &nombre)) {
                        let mut c = x.clone();
                        asignatura::poner(&mut c, &nombre);
                        cuaderno::reemplazar(&carpeta, &c)?;
                        n += 1;
                    }
                }
                None => por_copiar.push(m.id.clone()),
            }
        }
        if !por_copiar.is_empty() {
            n += self.reenviar_mensajes(chat.clone(), por_copiar.clone(), destino.clone())?;
            // Las copias: su asignatura y los enlaces de dentro con los ids
            // nuevos (la nota de una clase a sus capturas, la carpeta a sus
            // paginas).
            let alli = self.mensajes_de(&destino);
            let mut mapa = std::collections::HashMap::new();
            let mut copias = Vec::new();
            for id in &por_copiar {
                let Some(m) = origen.iter().find(|m| &m.id == id) else { continue };
                let o = asignatura::origen_de(m);
                if let Some(c) = alli.iter().rev().find(|x| x.origen.as_deref() == Some(o.as_str())) {
                    mapa.insert(m.id.clone(), c.id.clone());
                    copias.push(c.clone());
                }
            }
            for mut c in copias {
                asignatura::poner(&mut c, &nombre);
                asignatura::remapear(&mut c, &mapa);
                cuaderno::reemplazar(&carpeta, &c)?;
            }
        }
        self.olvidar_lo_leido(&destino);
        Ok(n)
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn raiz(etiqueta: &str) -> (std::sync::Arc<Nucleo>, std::path::PathBuf) {
        let d = std::env::temp_dir().join(format!("pixpin-asignaturas-{etiqueta}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        (n, d)
    }

    fn asig(nombre: &str, lista: Option<&str>) -> Asignatura {
        Asignatura {
            nombre: nombre.into(),
            aula: None,
            color: None,
            lista: lista.map(str::to_string),
        }
    }

    fn lista_suelta(mensaje: &str, titulo: &str) -> ListaTareas {
        ListaTareas {
            chat: "asig".into(),
            nombre_chat: NOMBRE_CHAT.into(),
            guardados: false,
            mensaje: mensaje.into(),
            titulo: titulo.into(),
            cuando: 1,
            es_inbox: false,
            tareas: Vec::new(),
            pendientes: 0,
            asignatura: None,
        }
    }

    #[test]
    fn la_lista_de_una_asignatura_se_encuentra_sin_tildes_y_solo_en_su_chat() {
        let (n, d) = raiz("lista");
        // Antes de apuntar nada: ni chat ni lista.
        assert_eq!(n.lista_de_asignatura(Vec::new(), "Geometría".into()), None);
        n.apuntar_en_asignatura("Geometría".into(), "repasar el tema 3".into(), Vec::new(), 0).unwrap();
        // Una lista con el mismo titulo en otro chat no es la de la asignatura.
        let otro = n.crear_chat("Otro".into()).unwrap();
        let indice = almacen::Indice::leer_si_esta(n.ruta()).unwrap();
        let ficha = indice.proyectos.iter().find(|f| f.id == otro.id).unwrap().clone();
        n.apuntar_en_lista(&ficha, "Geometria", "otra cosa".into(), &[], 0).unwrap();
        let listas = n.tareas(0).unwrap();
        let l = n.lista_de_asignatura(listas.clone(), "GEOMETRIA".into()).unwrap();
        assert_eq!(l.titulo, "Geometría");
        assert_ne!(l.chat, otro.id);
        assert_eq!(l.tareas.len(), 1);
        assert_eq!(n.lista_de_asignatura(listas, "Física".into()), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn anadir_una_asignatura_le_da_su_lista_vacia_una_sola_vez() {
        let (n, d) = raiz("nueva");
        let l = n.asegurar_lista_de_asignatura(" Física ".into(), 0).unwrap();
        assert_eq!((l.titulo.as_str(), l.tareas.len()), ("Física", 0));
        // Otra vez (o sin tildes): la misma, no otra.
        let otra = n.asegurar_lista_de_asignatura("fisica".into(), 0).unwrap();
        assert_eq!((otra.chat.as_str(), otra.mensaje.as_str()), (l.chat.as_str(), l.mensaje.as_str()));
        let listas = n.tareas(0).unwrap();
        assert_eq!(n.lista_de_asignatura(listas, "FÍSICA".into()).map(|x| x.mensaje), Some(l.mensaje.clone()));
        // Caso negativo: sin nombre no se crea nada.
        assert!(n.asegurar_lista_de_asignatura("  ".into(), 0).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn el_plan_crea_enlaza_y_renombra_sin_borrar_nada() {
        let ls = vec![lista_suelta("m1", "Geometría"), lista_suelta("m2", "Fisica"), lista_suelta("m3", "Historia")];
        let con_linea = vec![
            // Ya enlazada y con el mismo nombre: nada.
            asig("Geometría", Some("m1")),
            // Renombrada en el horario: la lista la sigue por su enlace.
            asig("Física II", Some("m2")),
            // De antes, sin enlace: se enlaza con la de su nombre.
            asig("historia", None),
            // Nueva: se crea.
            asig("Química", None),
            // Su lista se borro en el chat: se crea otra (vacia).
            asig("Arte", Some("m9")),
        ];
        let solo = vec![asig("Inglés", None), asig("geometria", None)];
        assert_eq!(
            plan(&con_linea, &solo, &ls),
            vec![
                Paso::Renombrar("m2".into(), "Física II".into()),
                Paso::Enlazar("m3".into(), "historia".into()),
                Paso::Crear("Química".into()),
                Paso::Crear("Arte".into()),
                Paso::Crear("Inglés".into()),
            ]
        );
        // Caso negativo: todo en orden, ningun paso.
        assert!(plan(&[asig("Geometría", Some("m1"))], &[], &ls).is_empty());
    }

    #[test]
    fn el_color_de_la_asignatura_pasa_a_su_lista_y_solo_a_ella() {
        let h = super::super::leer(
            "Asignatura Geometría #FF0000 lista:m1\nAsignatura Física\n",
            Momento::de_ms_locales(0),
        );
        let mut ls = vec![
            lista_suelta("m1", "Geometría analítica"),
            lista_suelta("m2", "física"),
            lista_suelta("m3", "Suelta"),
            ListaTareas { chat: "otro".into(), ..lista_suelta("m4", "Física") },
        ];
        colorear(&h, "asig", &mut ls);
        assert_eq!(ls[0].asignatura, Some(0xFF0000), "por su enlace");
        assert_eq!(
            ls[1].asignatura,
            Some(super::super::semana::color_por_nombre("Física")),
            "por su nombre, con el color de su nombre"
        );
        assert_eq!(ls[2].asignatura, None, "sin asignatura");
        assert_eq!(ls[3].asignatura, None, "de otro chat no");
    }

    #[test]
    fn enlazar_crea_las_listas_apunta_el_enlace_y_renombra() {
        let (n, d) = raiz("enlazar");
        let ruta = super::super::ruta(n.ruta());
        std::fs::write(
            &ruta,
            "# Horario\nAsignatura Geometría @A-12\nLun 8:00-9:00 Geometría\nMar 9:00-10:00 Inglés\n",
        )
        .unwrap();
        assert!(n.enlazar_asignaturas(0).unwrap());
        let texto = std::fs::read_to_string(&ruta).unwrap();
        let f = ficha(n.ruta()).unwrap();
        let geo = de(&n.listas_de_asignaturas(&f).unwrap(), "Geometría").unwrap().clone();
        assert!(texto.contains(&format!("Asignatura Geometría @A-12 lista:{}\n", geo.mensaje)), "{texto}");
        assert!(de(&n.listas_de_asignaturas(&f).unwrap(), "Inglés").is_some(), "la de la clase tambien");
        assert!(texto.contains("Mar 9:00-10:00 Inglés\n"), "lo demas igual");
        // En Tareas, con su color aunque esten vacias.
        let todas = n.tareas(0).unwrap();
        let en_tareas = todas.iter().find(|l| l.mensaje == geo.mensaje).unwrap();
        assert_eq!(en_tareas.asignatura, Some(super::super::semana::color_por_nombre("Geometría")));
        // Otra vez: nada que hacer.
        assert!(!n.enlazar_asignaturas(0).unwrap());
        // Renombrada a mano (su linea y su clase): la lista la sigue, con
        // sus tareas.
        n.apuntar_en_asignatura("Geometría".into(), "compás".into(), Vec::new(), 0).unwrap();
        std::fs::write(&ruta, texto.replace("Geometría", "Dibujo")).unwrap();
        assert!(n.enlazar_asignaturas(0).unwrap());
        let ls = n.listas_de_asignaturas(&f).unwrap();
        let dibujo = de(&ls, "Dibujo").unwrap();
        assert_eq!(dibujo.mensaje, geo.mensaje, "la misma lista");
        assert_eq!(dibujo.tareas[0].texto, "compás");
        assert!(de(&ls, "Geometría").is_none(), "no queda otra con el nombre viejo");
        // Apuntar por el nombre nuevo va a la misma lista (la del enlace).
        let l = n.lista_de_la_asignatura("dibujo", 0).unwrap();
        assert_eq!(l.mensaje, geo.mensaje);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn caso_negativo_quitar_una_asignatura_no_borra_su_lista() {
        let (n, d) = raiz("quitar");
        let ruta = super::super::ruta(n.ruta());
        std::fs::write(&ruta, "Asignatura Arte\n").unwrap();
        n.enlazar_asignaturas(0).unwrap();
        n.apuntar_en_asignatura("Arte".into(), "acuarelas".into(), Vec::new(), 0).unwrap();
        std::fs::write(&ruta, "# sin asignaturas\n").unwrap();
        n.enlazar_asignaturas(0).unwrap();
        let f = ficha(n.ruta()).unwrap();
        let ls = n.listas_de_asignaturas(&f).unwrap();
        assert_eq!(de(&ls, "Arte").unwrap().tareas.len(), 1, "sigue con su tarea");
        // Ya sin asignatura: en Tareas sin color (y vacia no saldria).
        let todas = n.tareas(0).unwrap();
        assert!(todas.iter().all(|l| l.asignatura.is_none()));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn el_chat_de_las_asignaturas_nace_con_su_libro_y_lo_suyo_se_etiqueta() {
        let (n, d) = raiz("asig-chat");
        std::fs::write(super::super::ruta(&d), "Asignatura Geometría #4F8EF7\n").unwrap();
        assert!(n.enlazar_asignaturas(0).unwrap());
        let chat = n.chat_de_asignaturas().expect("el chat esta");
        let f = ficha(&d).unwrap();
        assert!(pindesk_proyecto::avatar::valor_de(&f).is_some(), "con su 📘");
        let chips = n.chips_de_asignaturas(0);
        assert_eq!(chips, vec![ChipAsignatura { nombre: "Geometría".into(), color: Some(0x4F8EF7) }]);
        // Una nota de otro chat, enviada a la asignatura dos veces: una copia.
        let otro = n.crear_chat("Otro".into()).unwrap().id;
        let m = n.escribir_nota(otro.clone(), "Teorema de Pitágoras".into(), None).unwrap();
        assert_eq!(n.enviar_a_asignatura(otro.clone(), vec![m.id.clone()], "Geometría".into()).unwrap(), 1);
        assert_eq!(n.enviar_a_asignatura(otro.clone(), vec![m.id.clone()], "geometria".into()).unwrap(), 0);
        let alli = n.mensajes_de(&chat);
        let copias: Vec<_> = alli.iter().filter(|x| x.texto == "Teorema de Pitágoras").collect();
        assert_eq!(copias.len(), 1);
        assert_eq!(pindesk_proyecto::asignatura::de(copias[0]), Some("Geometría"));
        // El original se queda donde estaba y sin etiqueta.
        assert!(n.mensajes_de(&otro).iter().all(|x| pindesk_proyecto::asignatura::de(x).is_none()));
        // Renombrar la asignatura renombra la etiqueta.
        std::fs::write(
            super::super::ruta(&d),
            std::fs::read_to_string(super::super::ruta(&d)).unwrap().replace("Geometría", "Geometría plana"),
        )
        .unwrap();
        n.enlazar_asignaturas(0).unwrap();
        let alli = n.mensajes_de(&chat);
        let c = alli.iter().find(|x| x.texto == "Teorema de Pitágoras").unwrap();
        assert_eq!(pindesk_proyecto::asignatura::de(c), Some("Geometría plana"));
    }

    #[test]
    fn el_dia_de_la_semana_empieza_en_lunes() {
        // 1-ene-1970, jueves a las 00:00; 5-ene-1970, lunes a las 10:30.
        assert_eq!(dia_y_minuto(0), (3, 0));
        assert_eq!(dia_y_minuto(4 * 86_400_000 + (10 * 60 + 30) * 60_000), (0, 630));
    }
}
