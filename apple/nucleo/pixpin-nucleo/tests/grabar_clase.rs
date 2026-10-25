//! «Grabar clase o reunion» tal como lo vera Swift: lo que queda en el
//! cuaderno al terminar es lo de Windows (`grabar_clase::guardar`), campo a
//! campo, para que sincronice; y «Enviar a Anki» sin Anki deja el fichero.

use std::path::PathBuf;
use std::sync::Arc;

use pixpin_nucleo::{CapturaClase, EnvioAnki, Nucleo};
use pixpin_proyecto::{almacen, cuaderno};

struct Temporal(PathBuf);

impl Temporal {
    fn nueva(etiqueta: &str) -> Temporal {
        let dir = std::env::temp_dir().join(format!(
            "pixpin-nucleo-clase-{etiqueta}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Temporal(dir)
    }

    fn datos(&self) -> PathBuf {
        self.0.join("datos")
    }

    fn nucleo(&self) -> Arc<Nucleo> {
        Nucleo::abrir(self.datos().display().to_string(), "Mac".into()).unwrap()
    }

    fn fichero(&self, nombre: &str, bytes: &[u8]) -> String {
        let p = self.0.join(nombre);
        std::fs::write(&p, bytes).unwrap();
        p.display().to_string()
    }
}

impl Drop for Temporal {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn la_clase_entra_con_sus_capturas_enlazadas_como_en_windows() {
    let t = Temporal::nueva("guardar");
    let n = t.nucleo();
    let chat = n.crear_chat("Física".into()).unwrap().id;
    let capturas = vec![
        CapturaClase {
            ms: 65_400,
            ruta_png: t.fichero("a.png", b"png-a"),
        },
        CapturaClase {
            ms: 2_000,
            ruta_png: t.fichero("b.png", b"png-b"),
        },
        // Caso negativo: una que ya no esta se salta sin llevarse las demas.
        CapturaClase {
            ms: 9_000,
            ruta_png: t.0.join("no-esta.png").display().to_string(),
        },
    ];
    let hecho = n
        .guardar_clase(
            chat.clone(),
            t.fichero("clase.m4a", b"m4a"),
            120_000,
            vec![5, 40_000],
            capturas,
            0,
        )
        .unwrap();
    assert_eq!(hecho.voz.clase, "VOZ");
    assert!(hecho.voz.nombre.starts_with("Clase "), "{}", hecho.voz.nombre);
    assert!(hecho.voz.nombre.ends_with(".m4a"));
    assert_eq!(hecho.voz.duracion_ms, 120_000);
    assert_eq!(hecho.voz.picos, vec![5, 32_767]);
    assert_eq!(hecho.capturas.len(), 2);

    let c = cuaderno::Cuaderno::leer_de(&almacen::carpeta(&t.datos(), &chat)).unwrap();
    assert_eq!(c.mensajes.len(), 3, "la voz y detras sus capturas");
    let voz = &c.mensajes[0];
    let nombre = voz.nombre.trim_end_matches(".m4a").to_string();
    assert_eq!(voz.resto.get("grabacion"), Some(&serde_json::json!("clase")));
    let a = &c.mensajes[1];
    let b = &c.mensajes[2];
    assert_eq!(a.numero, voz.numero + 1);
    assert_eq!(b.numero, voz.numero + 2);
    assert_eq!(a.clase, Some(cuaderno::Clase::Imagen));
    assert!(a.nombre.starts_with("clase-") && a.nombre.ends_with("-1.png"), "{}", a.nombre);
    assert!(b.nombre.ends_with("-2.png"));
    assert_eq!(a.texto, format!("⏱ 1:05 · {nombre}"));
    assert_eq!(
        a.resto.get("enGrabacion"),
        Some(&serde_json::json!({ "de": voz.id, "ms": 65_400 }))
    );
    // En la voz, en orden de minuto.
    assert_eq!(
        voz.resto.get("capturas"),
        Some(&serde_json::json!([
            { "ms": 2_000, "id": b.id },
            { "ms": 65_400, "id": a.id },
        ]))
    );

    // La pantalla de la letra: las capturas con su fichero de aqui.
    let lista = n.capturas_de_la_clase(chat.clone(), voz.id.clone()).unwrap();
    assert_eq!(lista.iter().map(|c| c.ms).collect::<Vec<_>>(), vec![2_000, 65_400]);
    assert!(lista.iter().all(|c| c.ruta.as_ref().is_some_and(|r| std::path::Path::new(r).is_file())));
    // Caso negativo: una foto suelta no es una clase.
    assert!(n.capturas_de_la_clase(chat.clone(), a.id.clone()).unwrap().is_empty());

    // «Enviar a Anki» de la clase: sin Anki en la maquina, el fichero.
    match n.enviar_a_anki(chat, voz.id.clone(), "¿Qué se explicó aquí?".into()).unwrap() {
        EnvioAnki::Fichero { n, mazo, ruta } => {
            assert_eq!(n, 2);
            assert_eq!(mazo, "PixPin::Física");
            assert!(std::fs::read_to_string(ruta).unwrap().contains("pixpin-"));
        }
        // Con un Anki de verdad escuchando, tambien vale.
        EnvioAnki::Hecho { .. } | EnvioAnki::YaEstaban { .. } | EnvioAnki::Fallo { .. } => {}
        EnvioAnki::Nada => panic!("una clase con capturas da tarjetas"),
    }
}

#[test]
fn sin_capturas_la_clase_es_una_nota_de_voz_sin_mas() {
    let t = Temporal::nueva("sola");
    let n = t.nucleo();
    let chat = n.crear_chat("Obra".into()).unwrap().id;
    let hecho = n
        .guardar_clase(chat.clone(), t.fichero("x.m4a", b"m4a"), 3_000, vec![], vec![], 3_600_000)
        .unwrap();
    assert!(hecho.capturas.is_empty());
    let c = cuaderno::Cuaderno::leer_de(&almacen::carpeta(&t.datos(), &chat)).unwrap();
    assert_eq!(c.mensajes.len(), 1);
    assert!(c.mensajes[0].resto.get("capturas").is_none());
    assert!(c.mensajes[0].resto.get("grabacion").is_none());
    // Caso negativo: una nota sin preguntas no da tarjetas de Anki.
    let nota = n.escribir_nota(chat.clone(), "un parrafo suelto".into(), None).unwrap();
    assert_eq!(n.enviar_a_anki(chat, nota.id, "?".into()).unwrap(), EnvioAnki::Nada);
}
