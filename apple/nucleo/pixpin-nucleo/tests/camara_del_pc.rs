//! **El iPhone/iPad como camara de la reunion del PC** (1-nov-2026), por la
//! red de esta maquina: la escucha de un aparato dice `camara1`, contesta a
//! `camara_remota` y deja el aviso del PC para Swift.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use pixpin_nucleo::camara_del_pc::siguiente_aviso_de_camara;
use pixpin_nucleo::{Atendido, Escucha, Nucleo};
use pixpin_sincro::al_lienzo::Conexion;
use pixpin_sincro::camara::Anuncio;
use pixpin_sincro::mensajes::{Aparato, Hola};

struct Temporal(PathBuf);

impl Temporal {
    fn nueva(etiqueta: &str) -> Temporal {
        let dir = std::env::temp_dir().join(format!(
            "pixpin-nucleo-camara-{etiqueta}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Temporal(dir)
    }

    fn nucleo(&self, nombre: &str) -> Arc<Nucleo> {
        Nucleo::abrir(self.0.join(nombre).display().to_string(), nombre.into()).unwrap()
    }
}

impl Drop for Temporal {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn pool(e: &Arc<Escucha>) -> std::sync::mpsc::Receiver<Atendido> {
    let (tx, rx) = std::sync::mpsc::channel();
    for _ in 0..2 {
        let e = Arc::clone(e);
        let tx = tx.clone();
        std::thread::spawn(move || {
            loop {
                match e.atender() {
                    Ok(Atendido::Cerrada) => return,
                    Ok(a) => {
                        let _ = tx.send(a);
                    }
                    Err(_) => {}
                }
            }
        });
    }
    rx
}

#[test]
fn la_escucha_dice_camara_contesta_y_deja_el_aviso_del_pc() {
    let t = Temporal::nueva("aviso");
    let ipad = t.nucleo("iPad");
    let otro = t.nucleo("Otro");
    ipad.crear_grupo().unwrap();
    let e = Arc::clone(&ipad).escuchar(0).unwrap();
    let rx = pool(&e);
    let puerto = e.puerto();
    let codigo = ipad.aparato().unwrap().grupo.unwrap();
    otro.unirse_a_grupo("127.0.0.1".into(), puerto, codigo.clone())
        .unwrap();
    let _ = rx.recv_timeout(Duration::from_secs(10)).unwrap();

    // Otro aparato de PixPin (que sabe de la camara) pregunta: el iPad no
    // graba, y lo dice con su hora.
    let r = otro
        .preguntar_camara("127.0.0.1".into(), puerto)
        .unwrap()
        .expect("la escucha del iPad dice camara1");
    assert!(r.anuncio.grabacion.is_empty());
    assert!(r.anuncio.reloj > 0);
    assert_eq!(r.pc_nombre, "iPad");
    let _ = rx.recv_timeout(Duration::from_secs(10)).unwrap();

    // **El PC avisa** de que empezo a grabar: se le contesta con la hora de
    // aqui y el aviso queda para Swift.
    let yo = otro.aparato().unwrap();
    let flujo = std::net::TcpStream::connect(("127.0.0.1", puerto)).unwrap();
    let mut c = Conexion::abrir(
        flujo,
        &codigo,
        [5; 32],
        Hola {
            yo: Aparato {
                id: yo.id.clone(),
                nombre: "PORTATIL".into(),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .unwrap();
    assert!(c.sabe_de_camara());
    let anuncio = Anuncio {
        grabacion: "g-1761559500000".into(),
        titulo: "Clase 27-10 10h05".into(),
        aparato: "PORTATIL".into(),
        activa: true,
        ms_actual: 754_000,
        ..Anuncio::nada()
    };
    let desfase = c
        .anunciar_camara(&anuncio, &|| {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64
        })
        .unwrap();
    assert!(desfase.abs() < 2_000, "{desfase}");
    c.adios();
    let _ = rx.recv_timeout(Duration::from_secs(10)).unwrap();
    let mut visto = None;
    while let Some(a) = siguiente_aviso_de_camara() {
        if a.pc_id == yo.id && !a.anuncio.grabacion.is_empty() {
            visto = Some(a);
        }
    }
    let a = visto.expect("el aviso del PC");
    assert_eq!(a.anuncio.titulo, "Clase 27-10 10h05");
    assert_eq!(a.anuncio.ms_actual, 754_000);
    assert!(a.anuncio.activa);
    assert!(a.llego_en > 0);

    // Caso negativo: sin grupo no se pregunta a nadie.
    let solo = t.nucleo("Solo");
    assert!(solo.preguntar_camara("127.0.0.1".into(), puerto).is_err());
    e.cerrar();
}
