//! **La ventana semanal del horario para Swift** (Windows, 18-oct,
//! `horario/ventana.rs`): la lista de asignaturas y los bloques de la
//! semana ([`super::semana`]) en un objeto que Swift edita (soltar,
//! mover, alargar, borrar) y guarda en el MISMO `horario.md`, cambiando
//! solo las lineas de clases y de asignaturas.

use std::sync::{Arc, Mutex};

use pindesk_ia::fechas::Momento;

use super::semana::{self, Semana};
use crate::{ErrorNucleo, Nucleo};

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AsignaturaHorario {
    pub nombre: String,
    pub aula: Option<String>,
    /// `0xRRGGBB`.
    pub color: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct BloqueHorario {
    /// 0 lunes … 6 domingo.
    pub dia: u8,
    /// Minutos del dia.
    pub inicio: u32,
    pub fin: u32,
    pub nombre: String,
    pub aula: Option<String>,
    pub color: u32,
}

/// **La ficha de una clase** (Windows: el panel de la clase elegida, con
/// aula, nota y aviso): lo que no sale en [`BloqueHorario`].
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FichaDeClase {
    pub aula: Option<String>,
    /// Lo que lee la voz al contestar la llamada (las lineas `>`), una por
    /// linea.
    pub notas: Vec<String>,
    /// Minutos de antes del aviso; `None` es la del horario.
    pub antelacion: Option<u32>,
}

/// **Lo que paso al pulsar «+»** con lo escrito en «Nueva asignatura»
/// (el `Accion::Anadir` de Windows).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum AsignaturaAnadida {
    /// Nueva, en el puesto `indice` (Windows: «Arrastra «X» a la semana»).
    Nueva { indice: u32, nombre: String },
    /// Ya estaba en el puesto `indice` (Windows: «X» ya está en la lista).
    Repetida { indice: u32, nombre: String },
    /// No habia nombre: nada.
    Nada,
}

/// **Lo que paso al renombrar una asignatura** en su ficha (Windows 71bf70f,
/// el campo «Nombre»).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum AsignaturaRenombrada {
    /// Renombrada (y sus clases, y su lista de tareas si la tiene).
    Hecho { antes: String, nombre: String },
    /// Ya hay otra que se llama asi (Windows: «X» ya está en la lista): no
    /// se cambio nada.
    Repetida { nombre: String },
    /// Vacio o el mismo nombre: nada.
    Igual,
}

/// La semana abierta en la ventana.
#[derive(uniffi::Object)]
pub struct SemanaHorario {
    nucleo: Arc<Nucleo>,
    semana: Mutex<Semana>,
    /// Lo ultimo escrito en `horario.md` y lo de antes del ultimo cambio
    /// guardado («Deshacer», el `deshacer` del panel de Windows).
    guardada: Mutex<(Semana, Option<Semana>)>,
}

impl SemanaHorario {
    fn tomar(&self) -> std::sync::MutexGuard<'_, Semana> {
        self.semana.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn tomar_guardada(&self) -> std::sync::MutexGuard<'_, (Semana, Option<Semana>)> {
        self.guardada.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// **Los enlaces que ya estan en `horario.md`** (`lista:<id>`, los que
    /// apunta el vigia mientras la ventana esta abierta) para las
    /// asignaturas de `s` que aun no lo tienen, por su nombre: asi guardar
    /// desde la ventana no los borra.
    fn completar_enlaces(&self, s: &mut Semana) {
        let Some(texto) = self.nucleo.fichero_del_horario().ok().and_then(|r| std::fs::read_to_string(r).ok()) else {
            return;
        };
        let h = super::leer(&texto, Momento::de_ms_locales(0));
        for a in s.asignaturas.iter_mut().filter(|a| a.lista.is_none()) {
            let n = pindesk_ia::acciones::normalizar(a.nombre.trim());
            if let Some(b) = h
                .asignaturas
                .iter()
                .find(|b| b.lista.is_some() && pindesk_ia::acciones::normalizar(b.nombre.trim()) == n)
            {
                a.lista = b.lista.clone();
            }
        }
    }

    /// Escribe `s` en `horario.md` (solo las lineas de clases y
    /// asignaturas), como `Panel::guardar` de Windows.
    fn escribir(&self, s: &Semana) -> Result<(), ErrorNucleo> {
        let mut s = s.clone();
        self.completar_enlaces(&mut s);
        let s = &s;
        let ruta = self.nucleo.fichero_del_horario()?;
        let original =
            std::fs::read_to_string(&ruta).unwrap_or_else(|_| super::PLANTILLA.to_string());
        let nuevo = semana::reescribir(&original, s);
        if nuevo != original {
            let tmp = format!("{ruta}.parte");
            std::fs::write(&tmp, nuevo)?;
            std::fs::rename(&tmp, &ruta)?;
        }
        Ok(())
    }
}

#[uniffi::export]
impl SemanaHorario {
    /// Lee el horario (lo crea con la plantilla si no esta).
    #[uniffi::constructor]
    pub fn abrir(nucleo: Arc<Nucleo>) -> Result<Arc<SemanaHorario>, ErrorNucleo> {
        let ruta = nucleo.fichero_del_horario()?;
        let texto = std::fs::read_to_string(&ruta)?;
        let h = super::leer(&texto, Momento::de_ms_locales(crate::ahora_ms()));
        let s = Semana::de_horario(&h);
        Ok(Arc::new(SemanaHorario {
            nucleo,
            semana: Mutex::new(s.clone()),
            guardada: Mutex::new((s, None)),
        }))
    }

    pub fn asignaturas(&self) -> Vec<AsignaturaHorario> {
        let s = self.tomar();
        s.asignaturas
            .iter()
            .map(|a| AsignaturaHorario {
                nombre: a.nombre.clone(),
                aula: a.aula.clone(),
                color: s.color_de(&a.nombre),
            })
            .collect()
    }

    pub fn bloques(&self) -> Vec<BloqueHorario> {
        let s = self.tomar();
        s.bloques
            .iter()
            .map(|b| BloqueHorario {
                dia: b.dia,
                inicio: b.inicio,
                fin: b.fin,
                nombre: b.nombre.clone(),
                aula: b.aula.clone(),
                color: s.color_de(&b.nombre),
            })
            .collect()
    }

    /// Una asignatura nueva («Geometría @A-12»). `false`: ya estaba.
    pub fn anadir_asignatura(&self, escrito: String) -> bool {
        matches!(self.tomar().anadir_asignatura(&escrito), Ok(Some(_)))
    }

    /// **«+» de «Nueva asignatura»**: la anade (con el aula detras si se
    /// pone) o dice cual era la repetida.
    pub fn anadir_asignatura_escrita(&self, escrito: String) -> AsignaturaAnadida {
        let mut s = self.tomar();
        match s.anadir_asignatura(&escrito) {
            Ok(Some(i)) => AsignaturaAnadida::Nueva {
                indice: i as u32,
                nombre: s.asignaturas[i].nombre.clone(),
            },
            Err(i) => AsignaturaAnadida::Repetida {
                indice: i as u32,
                nombre: s.asignaturas[i].nombre.clone(),
            },
            Ok(None) => AsignaturaAnadida::Nada,
        }
    }

    /// **El enlace de la asignatura `i` con su lista** (`lista:<id>`, el
    /// `mensaje` de [`Nucleo::asegurar_lista_de_asignatura`]): la linea
    /// nace con el al guardar, como en Windows.
    pub fn poner_lista_de_asignatura(&self, i: u32, lista: String) {
        let lista = lista.trim().to_string();
        if let Some(a) = self.tomar().asignaturas.get_mut(i as usize) {
            a.lista = (!lista.is_empty()).then_some(lista);
        }
    }

    /// **Renombra la asignatura `i`** desde su ficha (Windows 71bf70f): sus
    /// clases y su lista de tareas (la de su enlace o, sin el, la de su
    /// nombre de antes), que sigue con sus tareas. Si cambio, se guarda ya.
    pub fn renombrar_asignatura(&self, i: u32, nuevo: String) -> Result<AsignaturaRenombrada, ErrorNucleo> {
        let i = i as usize;
        let mut s = self.tomar().clone();
        self.completar_enlaces(&mut s);
        let Some(a) = s.asignaturas.get(i).cloned() else {
            return Ok(AsignaturaRenombrada::Igual);
        };
        let lista = self.nucleo.lista_leida_de_asignatura(&a);
        let antes = match s.renombrar_asignatura(i, &nuevo) {
            Err(j) => {
                return Ok(AsignaturaRenombrada::Repetida {
                    nombre: s.asignaturas[j].nombre.clone(),
                });
            }
            Ok(None) => return Ok(AsignaturaRenombrada::Igual),
            Ok(Some(antes)) => antes,
        };
        if let Some(l) = &lista {
            s.asignaturas[i].lista = Some(l.mensaje.clone());
        }
        let nombre = s.asignaturas[i].nombre.clone();
        *self.tomar() = s;
        self.guardar()?;
        if let Some(l) = lista {
            self.nucleo.renombrar_lista_de_tareas(&l.chat, &l.mensaje, &nombre)?;
        }
        Ok(AsignaturaRenombrada::Hecho { antes, nombre })
    }

    pub fn borrar_asignatura(&self, i: u32) {
        self.tomar().borrar_asignatura(i as usize);
    }

    pub fn cambiar_color(&self, i: u32) {
        self.tomar().cambiar_color(i as usize);
    }

    /// Suelta la asignatura `asignatura` en el dia y minuto: un bloque nuevo.
    pub fn soltar(&self, asignatura: u32, dia: u8, minuto: u32) {
        self.tomar()
            .soltar(asignatura as usize, dia, semana::redondear_abajo(minuto));
    }

    pub fn mover(&self, i: u32, dia: u8, inicio: i64) {
        self.tomar().mover(i as usize, dia, inicio);
    }

    pub fn alargar(&self, i: u32, fin: u32) {
        self.tomar().alargar(i as usize, semana::redondear(fin));
    }

    pub fn borrar(&self, i: u32) {
        self.tomar().borrar(i as usize);
    }

    /// La ficha del bloque `i` (aula, notas y aviso), o nada si no esta.
    pub fn ficha_de_clase(&self, i: u32) -> Option<FichaDeClase> {
        let s = self.tomar();
        s.bloques.get(i as usize).map(|b| FichaDeClase {
            aula: b.aula.clone(),
            notas: b.notas.clone(),
            antelacion: b.antelacion,
        })
    }

    /// Cambia la ficha del bloque `i` como la de Windows al guardarla: el
    /// aula vacia es ninguna, las notas sin lineas en blanco y el aviso
    /// como mucho de un dia.
    pub fn poner_ficha_de_clase(&self, i: u32, ficha: FichaDeClase) {
        let mut s = self.tomar();
        let Some(b) = s.bloques.get_mut(i as usize) else {
            return;
        };
        b.aula = ficha
            .aula
            .map(|a| a.trim().to_string())
            .filter(|a| !a.is_empty());
        b.notas = ficha
            .notas
            .iter()
            .flat_map(|n| n.lines())
            .map(|l| l.trim().to_string())
            .filter(|l| !l.is_empty())
            .collect();
        b.antelacion = ficha.antelacion.map(|n| n.min(24 * 60));
    }

    /// Cambia el aula de la asignatura `i` (y de sus clases que tenian la
    /// de antes).
    pub fn poner_aula_de_asignatura(&self, i: u32, aula: Option<String>) {
        let aula = aula.map(|a| a.trim().to_string()).filter(|a| !a.is_empty());
        self.tomar().poner_aula_de_asignatura(i as usize, aula);
    }

    /// Los minutos de antes que avisa una clase sin aviso propio (los del
    /// horario).
    pub fn antelacion_del_horario(&self) -> u32 {
        self.nucleo
            .fichero_del_horario()
            .ok()
            .and_then(|r| std::fs::read_to_string(r).ok())
            .map(|t| super::leer(&t, Momento::de_ms_locales(crate::ahora_ms())).antelacion)
            .unwrap_or(super::ANTELACION)
    }

    /// **Guarda** en `horario.md` (solo las lineas de clases y asignaturas).
    /// Si cambio algo, lo de antes queda para «Deshacer».
    pub fn guardar(&self) -> Result<(), ErrorNucleo> {
        let s = self.tomar().clone();
        let mut g = self.tomar_guardada();
        self.escribir(&s)?;
        if g.0 != s {
            let antes = std::mem::replace(&mut g.0, s);
            g.1 = Some(antes);
        }
        Ok(())
    }

    /// Si hay un cambio que deshacer.
    pub fn puede_deshacer(&self) -> bool {
        self.tomar_guardada().1.is_some()
    }

    /// **«Deshacer»**: la semana de antes del ultimo cambio, otra vez en
    /// `horario.md` (una sola vez, como en Windows). `false`: no habia nada.
    pub fn deshacer(&self) -> Result<bool, ErrorNucleo> {
        let mut g = self.tomar_guardada();
        let Some(antes) = g.1.take() else {
            return Ok(false);
        };
        self.escribir(&antes)?;
        *self.tomar() = antes.clone();
        g.0 = antes;
        Ok(true)
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn soltar_una_asignatura_la_escribe_en_el_horario_y_avisa() {
        let d = std::env::temp_dir().join(format!("pixpin-semana-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        let s = SemanaHorario::abrir(n.clone()).unwrap();
        assert!(s.anadir_asignatura("Geometría @A-12".into()));
        assert!(!s.anadir_asignatura("geometria".into()), "ya estaba");
        for dia in 0..7 {
            s.soltar(0, dia, 8 * 60 + 7);
        }
        assert_eq!(s.bloques().len(), 7);
        assert_eq!(s.bloques()[0].inicio, 8 * 60, "a los 15 min de abajo");
        s.guardar().unwrap();
        let texto = std::fs::read_to_string(n.fichero_del_horario().unwrap()).unwrap();
        assert!(texto.contains("Geometría"), "{texto}");
        assert!(
            texto.contains("# Horario de clases"),
            "lo del usuario se queda"
        );
        assert!(!n.avisos_del_horario(0).is_empty(), "y ya avisa");
        // La ficha de una clase: aula, notas y aviso, y vuelven al leer.
        s.poner_ficha_de_clase(
            1,
            FichaDeClase {
                aula: Some(" B-3 ".into()),
                notas: vec!["llevar la escuadra\n\n".into()],
                antelacion: Some(5000),
            },
        );
        assert_eq!(
            s.ficha_de_clase(1),
            Some(FichaDeClase {
                aula: Some("B-3".into()),
                notas: vec!["llevar la escuadra".into()],
                antelacion: Some(24 * 60)
            })
        );
        assert_eq!(s.ficha_de_clase(99), None);
        s.guardar().unwrap();
        let otra = SemanaHorario::abrir(n.clone()).unwrap();
        assert_eq!(
            otra.ficha_de_clase(1).unwrap().notas,
            ["llevar la escuadra"]
        );
        assert!(otra.antelacion_del_horario() > 0);
        // Borrar un bloque.
        s.borrar(0);
        assert_eq!(s.bloques().len(), 6);
        let _ = std::fs::remove_dir_all(&d);
    }

    /// Lo que deja Windows en `horario.md` al anadir «Geometría @A-12» con
    /// el «+» a un horario nuevo (la plantilla) y soltarla el lunes y el
    /// miercoles a las 8 (`semana::reescribir` del panel de Windows).
    const COMO_WINDOWS: &str = "# Horario de clases

Una línea por clase: los días, la hora y la asignatura (el aula con @).
Debajo de una clase, lo que empieza por > lo lee la voz al contestar.
También puedes pegar una tabla (de Excel o de la web).

<!-- Ejemplo (quita estas dos líneas de comentario para usarlo):
Lun Mie 8:00-10:00 Geometría @A-12
> traer el compás
Mar Jue 10:15-12:00 Física
Evaluación Geometría 23/10
-->

avisar 10 min antes

## Asignaturas
Asignatura Geometría @A-12
";

    #[test]
    fn renombrar_una_asignatura_renombra_su_lista_y_sus_clases() {
        let d = std::env::temp_dir().join(format!("pixpin-semana-renombrar-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        let ruta = n.fichero_del_horario().unwrap();
        let s = SemanaHorario::abrir(n.clone()).unwrap();
        // Al anadirla, su lista ya, y la linea nace con el enlace.
        let AsignaturaAnadida::Nueva { indice, nombre } = s.anadir_asignatura_escrita("Geometría".into()) else {
            panic!("nueva");
        };
        let l = n.asegurar_lista_de_asignatura(nombre, 0).unwrap();
        s.poner_lista_de_asignatura(indice, l.mensaje.clone());
        s.soltar(0, 0, 8 * 60);
        s.guardar().unwrap();
        let texto = std::fs::read_to_string(&ruta).unwrap();
        assert!(texto.contains(&format!("Asignatura Geometría lista:{}\n", l.mensaje)), "{texto}");
        n.apuntar_en_asignatura("Geometría".into(), "compás".into(), Vec::new(), 0).unwrap();
        // Renombrarla: la linea, la clase y la lista, que sigue con su tarea.
        assert_eq!(
            s.renombrar_asignatura(0, " Dibujo  técnico ".into()).unwrap(),
            AsignaturaRenombrada::Hecho { antes: "Geometría".into(), nombre: "Dibujo técnico".into() }
        );
        let texto = std::fs::read_to_string(&ruta).unwrap();
        assert!(texto.contains(&format!("Asignatura Dibujo técnico lista:{}\n", l.mensaje)), "{texto}");
        assert!(texto.contains("Lun 8:00-9:00 Dibujo técnico"), "{texto}");
        let listas = n.tareas(0).unwrap();
        let la = listas.iter().find(|x| x.mensaje == l.mensaje).unwrap();
        assert_eq!((la.titulo.as_str(), la.tareas.len()), ("Dibujo técnico", 1));
        // Casos negativos: a una que ya esta, o en blanco, nada.
        s.anadir_asignatura_escrita("Física".into());
        assert_eq!(
            s.renombrar_asignatura(1, "dibujo TECNICO".into()).unwrap(),
            AsignaturaRenombrada::Repetida { nombre: "Dibujo técnico".into() }
        );
        assert_eq!(s.renombrar_asignatura(0, "  ".into()).unwrap(), AsignaturaRenombrada::Igual);
        // Un enlace que apunta el vigia con la ventana abierta no se pierde al guardar.
        std::fs::write(&ruta, "Asignatura Física\n").unwrap();
        let abierta = SemanaHorario::abrir(n.clone()).unwrap();
        std::fs::write(&ruta, "Asignatura Física lista:m-fis\n").unwrap();
        abierta.cambiar_color(0);
        abierta.guardar().unwrap();
        assert!(std::fs::read_to_string(&ruta).unwrap().contains("lista:m-fis"));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn anadir_una_asignatura_deja_el_horario_como_windows_y_se_deshace() {
        let d = std::env::temp_dir().join(format!("pixpin-semana-anadir-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let n = Nucleo::abrir(d.display().to_string(), "Mac".into()).unwrap();
        let ruta = n.fichero_del_horario().unwrap();
        let s = SemanaHorario::abrir(n.clone()).unwrap();
        assert!(!s.puede_deshacer(), "recien abierto, nada que deshacer");
        assert_eq!(
            s.anadir_asignatura_escrita("   ".into()),
            AsignaturaAnadida::Nada
        );
        assert_eq!(
            s.anadir_asignatura_escrita("Geometría @A-12".into()),
            AsignaturaAnadida::Nueva {
                indice: 0,
                nombre: "Geometría".into()
            }
        );
        s.guardar().unwrap();
        assert_eq!(std::fs::read_to_string(&ruta).unwrap(), COMO_WINDOWS);
        // Repetida (sin tildes ni mayusculas): no se anade otra.
        assert_eq!(
            s.anadir_asignatura_escrita("GEOMETRIA".into()),
            AsignaturaAnadida::Repetida {
                indice: 0,
                nombre: "Geometría".into()
            }
        );
        assert_eq!(s.asignaturas().len(), 1);
        // Y lo que lee el horario de ahi es la asignatura con su aula.
        let leido = SemanaHorario::abrir(n.clone()).unwrap();
        assert_eq!(
            leido.asignaturas(),
            [AsignaturaHorario {
                nombre: "Geometría".into(),
                aula: Some("A-12".into()),
                color: s.asignaturas()[0].color
            }]
        );
        // Dos clases: el lunes y el miercoles de 8 a 9, en una linea.
        s.soltar(0, 0, 8 * 60);
        s.soltar(0, 2, 8 * 60);
        s.guardar().unwrap();
        let con_clases = std::fs::read_to_string(&ruta).unwrap();
        assert_eq!(
            con_clases,
            format!("{COMO_WINDOWS}\n## Clases\nLun Mié 8:00-9:00 Geometría @A-12\n"),
        );
        // «Deshacer»: el fichero vuelve a como estaba, una sola vez.
        assert!(s.puede_deshacer());
        assert!(s.deshacer().unwrap());
        assert_eq!(std::fs::read_to_string(&ruta).unwrap(), COMO_WINDOWS);
        assert!(s.bloques().is_empty());
        assert!(!s.deshacer().unwrap(), "caso negativo: no hay dos deshacer");
        // Quitar la asignatura la quita del fichero (sus tareas siguen).
        s.borrar_asignatura(0);
        s.guardar().unwrap();
        assert!(
            !std::fs::read_to_string(&ruta)
                .unwrap()
                .contains("Asignatura Geometría")
        );
        let _ = std::fs::remove_dir_all(&d);
    }
}
