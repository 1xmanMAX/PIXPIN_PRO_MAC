//! **La mudanza de la carpeta de datos** (`pindesk_sistema::nombre` de
//! Windows): `~/Library/Application Support/PixPinMax` pasa a
//! `~/Library/Application Support/PinDesk` una sola vez, al arrancar la app,
//! antes de abrir ningun fichero (docs/formato-pindesk.md, «la migracion al
//! actualizar»).
//!
//! Como en el PC: se **renombra** (lo normal: la misma unidad); si no se
//! puede, se **copia** a `PinDesk.migrando` y, entera, se renombra a
//! `PinDesk`, y la vieja se queda con sus datos. En los dos casos queda en la
//! vieja `MOVIDO-A-PINDESK.txt`. Si la copia falla se borra solo la copia a
//! medias y se sigue con la vieja. Dentro de la carpeta ya mudada,
//! `pixpinmax.toml` pasa a `pindesk.toml`.
//!
//! Lo hace la app (Swift llama a [`mudar_carpeta_de_datos`]); los ayudantes
//! (el MCP, el puente, las extensiones) solo eligen con la misma regla
//! (`nombre::carpeta_de_datos`) y nunca mueven nada. El Llavero
//! (`PixPinMax.*`) no cambia, como la entropia de DPAPI en Windows.

use std::path::Path;

use pindesk_sistema::nombre::{self, Migracion};

/// Lo que paso al mudar.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum QuePasoConLosDatos {
    /// No habia carpeta vieja, o ya estaba la nueva.
    Nada,
    /// Se renombro.
    Movida,
    /// Se copio; la vieja se queda con sus datos y la nota.
    Copiada,
    /// No se pudo: se sigue con la vieja, intacta.
    Fallo,
}

/// **La carpeta de datos que se usa** tras la mudanza y que paso.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MudanzaDeDatos {
    /// La ruta que hay que abrir: `<base>/PinDesk`, o `<base>/PixPinMax` si
    /// no se pudo mudar.
    pub carpeta: String,
    pub que_paso: QuePasoConLosDatos,
    /// El motivo, si fallo (para el registro).
    pub detalle: String,
}

/// **Muda `<base>/PixPinMax` a `<base>/PinDesk`** si hace falta y dice cual
/// usar. `base` es `~/Library/Application Support`. Bloqueante (una copia
/// puede tardar): Swift la llama una vez al arrancar, antes de abrir el
/// nucleo.
#[uniffi::export]
pub fn mudar_carpeta_de_datos(base: String) -> MudanzaDeDatos {
    mudar(Path::new(&base))
}

/// **La carpeta de datos bajo `base`** sin mover nada: la nueva si existe;
/// si no, la vieja si aun tiene datos; si no, la nueva (la regla de los
/// ayudantes, `nombre::carpeta_de_datos`).
#[uniffi::export]
pub fn carpeta_de_datos_en(base: String) -> String {
    nombre::carpeta_de_datos(Path::new(&base))
        .display()
        .to_string()
}

fn mudar(base: &Path) -> MudanzaDeDatos {
    let nueva = base.join(nombre::CARPETA_DATOS);
    let vieja = base.join(nombre::CARPETA_DATOS_VIEJA);
    let m = nombre::migrar_carpeta(&vieja, &nueva);
    // Una carpeta ya mudada a mano (o por una version anterior) puede traer
    // aun el toml viejo.
    if nueva.is_dir() {
        let _ = nombre::migrar_ajustes(&nueva);
    }
    let (que_paso, detalle) = match m {
        Migracion::NadaQueHacer => (QuePasoConLosDatos::Nada, String::new()),
        Migracion::Movida => (QuePasoConLosDatos::Movida, String::new()),
        Migracion::Copiada => (QuePasoConLosDatos::Copiada, String::new()),
        Migracion::Fallo(e) => (QuePasoConLosDatos::Fallo, e),
    };
    MudanzaDeDatos {
        carpeta: nombre::carpeta_de_datos(base).display().to_string(),
        que_paso,
        detalle,
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use std::path::PathBuf;

    fn base(etiqueta: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "pindesk-mudanza-{etiqueta}-{}-{}",
            std::process::id(),
            crate::ahora_ms()
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn la_carpeta_vieja_pasa_a_pindesk_con_su_toml_y_deja_la_nota() {
        let b = base("mover");
        let vieja = b.join("PixPinMax");
        std::fs::create_dir_all(vieja.join("proyectos/p1")).unwrap();
        std::fs::write(vieja.join("proyectos/p1/proyecto.json"), "{}").unwrap();
        std::fs::write(vieja.join("pixpinmax.toml"), "idioma = \"es\"\n").unwrap();
        std::fs::write(vieja.join("enlaces.clave"), [7u8; 32]).unwrap();

        let m = mudar_carpeta_de_datos(b.display().to_string());
        assert_eq!(m.que_paso, QuePasoConLosDatos::Movida, "{m:?}");
        let nueva = b.join("PinDesk");
        assert_eq!(PathBuf::from(&m.carpeta), nueva);
        assert!(nueva.join("proyectos/p1/proyecto.json").is_file());
        assert!(nueva.join("enlaces.clave").is_file());
        assert!(nueva.join("pindesk.toml").is_file());
        assert!(!nueva.join("pixpinmax.toml").exists());
        // En la vieja solo queda la nota, y los ayudantes ya miran la nueva.
        assert!(vieja.join("MOVIDO-A-PINDESK.txt").is_file());
        assert_eq!(PathBuf::from(carpeta_de_datos_en(b.display().to_string())), nueva);

        // La segunda vez no hace nada.
        let otra = mudar_carpeta_de_datos(b.display().to_string());
        assert_eq!(otra.que_paso, QuePasoConLosDatos::Nada);
        assert_eq!(PathBuf::from(&otra.carpeta), nueva);
        let _ = std::fs::remove_dir_all(&b);
    }

    #[test]
    fn sin_nada_que_mudar_se_usa_pindesk_y_la_nueva_no_se_pisa() {
        // Un Mac nuevo: ni vieja ni nueva.
        let b = base("vacio");
        let m = mudar_carpeta_de_datos(b.display().to_string());
        assert_eq!(m.que_paso, QuePasoConLosDatos::Nada);
        assert_eq!(PathBuf::from(&m.carpeta), b.join("PinDesk"));
        assert!(!b.join("PixPinMax").exists());

        // Caso negativo: con las dos, la nueva manda y la vieja no se toca.
        std::fs::create_dir_all(b.join("PinDesk")).unwrap();
        std::fs::create_dir_all(b.join("PixPinMax")).unwrap();
        std::fs::write(b.join("PixPinMax/pixpinmax.toml"), "x = 1\n").unwrap();
        let m = mudar_carpeta_de_datos(b.display().to_string());
        assert_eq!(m.que_paso, QuePasoConLosDatos::Nada);
        assert_eq!(PathBuf::from(&m.carpeta), b.join("PinDesk"));
        assert!(b.join("PixPinMax/pixpinmax.toml").is_file());
        assert!(!b.join("PixPinMax/MOVIDO-A-PINDESK.txt").exists());
        let _ = std::fs::remove_dir_all(&b);
    }

    #[test]
    fn la_carpeta_mudada_a_mano_pasa_su_toml_viejo() {
        let b = base("a-mano");
        std::fs::create_dir_all(b.join("PinDesk")).unwrap();
        std::fs::write(b.join("PinDesk/pixpinmax.toml"), "idioma = \"en\"\n").unwrap();
        mudar_carpeta_de_datos(b.display().to_string());
        assert!(b.join("PinDesk/pindesk.toml").is_file());
        assert!(!b.join("PinDesk/pixpinmax.toml").exists());
        let _ = std::fs::remove_dir_all(&b);
    }
}
