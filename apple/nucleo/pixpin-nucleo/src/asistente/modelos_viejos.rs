//! **Lo que quedo bajado del asistente local** (Windows
//! `apps/pixpin/src/asistente/modelos_viejos.rs`, 27-oct-2026).
//!
//! El asistente contesta solo con la nube desde ese dia (como Windows y
//! Android): el `llama-server` de llama.cpp para macOS y los modelos
//! (Qwen3.5 2B/0.8B, Gemma 4 E2B) ya no se usan, pero quien los bajo los
//! tiene en `~/Library/Application Support/PixPinMax/modelos` (la carpeta
//! que pasa Swift, `carpetaDeModelosViejos()`): de 1 a 7 GB. Como en
//! Windows, **se pregunta una vez**: la ventana del asistente dice cuanto
//! ocupan y ofrece liberarlo ([`ia_modelos_viejos_por_avisar`],
//! [`ia_modelos_viejos_borrar`], [`ia_modelos_viejos_no_avisar`]), y
//! Ajustes → Asistente tiene el boton mientras sigan ahi
//! ([`ia_modelos_viejos_ocupan`]).
//!
//! Esa carpeta era SOLO del asistente local: lo demas (Whisper, las
//! voces...) vive en otras carpetas de la de datos y no se toca.

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::ErrorNucleo;

/// El fichero que apunta «no me lo vuelvas a decir», dentro de la propia
/// carpeta: si se borra la carpeta, se va con ella.
const NO_AVISAR: &str = "no-avisar-pixpin.txt";

/// Lo que ocupa todo lo que hay debajo de `c` (sin seguir enlaces).
fn tamano_de(c: &Path) -> u64 {
    let Ok(entradas) = std::fs::read_dir(c) else {
        return 0;
    };
    entradas
        .flatten()
        .map(|e| match e.file_type() {
            Ok(t) if t.is_dir() => tamano_de(&e.path()),
            Ok(t) if t.is_file() => e.metadata().map_or(0, |m| m.len()),
            _ => 0,
        })
        .sum()
}

/// Lo ultimo medido: cuando, de que carpeta y cuanto (mirar el disco cada
/// vez que se pinta la ventana, no).
static MEDIDO: Mutex<Option<(Instant, PathBuf, u64)>> = Mutex::new(None);

/// Que la siguiente pregunta mire el disco otra vez.
fn olvidar() {
    if let Ok(mut g) = MEDIDO.lock() {
        *g = None;
    }
}

fn ocupan(c: &Path) -> Option<u64> {
    if c.as_os_str().is_empty() {
        return None;
    }
    let mut g = MEDIDO.lock().unwrap_or_else(|e| e.into_inner());
    if let Some((t, de, b)) = g.as_ref()
        && de == c
        && t.elapsed() < Duration::from_secs(30)
    {
        return (*b > 0).then_some(*b);
    }
    let b = if c.is_dir() { tamano_de(c) } else { 0 };
    *g = Some((Instant::now(), c.to_path_buf(), b));
    (b > 0).then_some(b)
}

/// **Cuanto ocupan** los modelos viejos de `carpeta`, o nada si no queda
/// nada. Se mide como mucho cada 30 s.
#[uniffi::export]
pub fn ia_modelos_viejos_ocupan(carpeta: String) -> Option<u64> {
    ocupan(Path::new(&carpeta))
}

/// Lo que ocupan si aun no se dijo «Dejarlos»: lo que ensena la tarjeta.
#[uniffi::export]
pub fn ia_modelos_viejos_por_avisar(carpeta: String) -> Option<u64> {
    let c = PathBuf::from(carpeta);
    let b = ocupan(&c)?;
    (!c.join(NO_AVISAR).is_file()).then_some(b)
}

/// «Dejarlos»: la tarjeta no vuelve a salir (el boton de Ajustes sigue).
#[uniffi::export]
pub fn ia_modelos_viejos_no_avisar(carpeta: String) {
    let c = PathBuf::from(carpeta);
    if !c.is_dir() {
        return;
    }
    let texto = "PixPin Max ya no usa esta carpeta: el asistente contesta con la nube.\n\
                 Se puede borrar entera (Ajustes > Asistente > Liberar espacio).\n";
    let _ = std::fs::write(c.join(NO_AVISAR), texto);
}

/// **Borra la carpeta entera** y devuelve lo liberado. Solo esa carpeta:
/// es la que la app creo para el asistente local.
#[uniffi::export]
pub fn ia_modelos_viejos_borrar(carpeta: String) -> Result<u64, ErrorNucleo> {
    let c = PathBuf::from(carpeta);
    if c.as_os_str().is_empty() {
        return Ok(0);
    }
    let b = if c.is_dir() { tamano_de(&c) } else { 0 };
    let r = match std::fs::remove_dir_all(&c) {
        Ok(()) => Ok(b),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(b),
        Err(e) => Err(ErrorNucleo::from(e)),
    };
    // Lo que se pudo borrar ya no cuenta: que se vuelva a medir.
    olvidar();
    r
}

/// «1,9 GB», «740 MB»: como lo dicen la tarjeta y los ajustes.
#[uniffi::export]
pub fn ia_tamano_en_disco(bytes: u64) -> String {
    let mb = bytes as f64 / 1_000_000.0;
    if mb >= 1000.0 {
        format!("{:.1} GB", mb / 1000.0).replace('.', ",")
    } else {
        format!("{:.0} MB", mb.max(1.0))
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn se_avisa_una_vez_y_borrar_libera_el_espacio() {
        let c = std::env::temp_dir().join(format!(
            "pixpin-modelos-viejos-{}-{}",
            std::process::id(),
            crate::ahora_ms()
        ));
        let _ = std::fs::remove_dir_all(&c);
        let s = c.display().to_string();
        // Sin carpeta, nada que decir.
        olvidar();
        assert_eq!(ia_modelos_viejos_ocupan(s.clone()), None);
        assert_eq!(ia_modelos_viejos_por_avisar(s.clone()), None);
        assert_eq!(ia_modelos_viejos_borrar(s.clone()).unwrap(), 0);
        assert_eq!(ia_modelos_viejos_borrar(String::new()).unwrap(), 0);
        // Lo que dejaba la app: el motor y un modelo.
        std::fs::create_dir_all(c.join("llama.cpp").join("b11580-macos")).unwrap();
        std::fs::create_dir_all(c.join("qwen3.5-2b")).unwrap();
        std::fs::write(c.join("llama.cpp/b11580-macos/llama-server"), [0u8; 300]).unwrap();
        std::fs::write(c.join("qwen3.5-2b/Qwen3.5-2B-Q4_K_M.gguf"), [0u8; 700]).unwrap();
        olvidar();
        assert_eq!(ia_modelos_viejos_ocupan(s.clone()), Some(1000));
        assert_eq!(ia_modelos_viejos_por_avisar(s.clone()), Some(1000));
        // «Dejarlos»: la tarjeta se calla, el boton de Ajustes sigue.
        ia_modelos_viejos_no_avisar(s.clone());
        olvidar();
        assert_eq!(ia_modelos_viejos_por_avisar(s.clone()), None);
        assert!(ia_modelos_viejos_ocupan(s.clone()).is_some_and(|b| b > 1000));
        // «Liberar espacio»: la carpeta entera fuera.
        assert!(ia_modelos_viejos_borrar(s.clone()).unwrap() > 1000);
        assert!(!c.exists());
        assert_eq!(ia_modelos_viejos_ocupan(s), None);
    }

    #[test]
    fn el_tamano_como_lo_dice_la_tarjeta() {
        assert_eq!(ia_tamano_en_disco(1_981_062_350), "2,0 GB");
        assert_eq!(ia_tamano_en_disco(737_504_352), "738 MB");
        assert_eq!(ia_tamano_en_disco(10), "1 MB");
    }
}
