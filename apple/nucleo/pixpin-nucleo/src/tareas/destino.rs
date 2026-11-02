//! **Adonde va lo apuntado en la caja de Tareas** (Windows 71bf70f,
//! `tareas/destino.rs`, 1-nov-2026): lo puro del desplegable de la caja.
//!
//! El usuario: «en las listas de tareas quiero ver tambien mis asignaturas y
//! poder añadirles tareas; ahora no puedo». El desplegable es el de
//! **todas** las listas: el Inbox (lo de siempre, sin elegir nada), las
//! asignaturas del horario (con su lista, aunque aun no exista: se crea al
//! apuntar) y detras las demas listas de todos los chats. Y cada lista tiene
//! ademas su «＋» en el encabezado, que la deja elegida ([`destino_de_la_lista`]).

use pindesk_ia::acciones::normalizar;

use super::ListaTareas;
use crate::horario::asignaturas::NOMBRE_CHAT;

/// Lo que se puede elegir.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum DestinoTarea {
    /// El Inbox de «Mensajes guardados» (sin elegir nada).
    Inbox,
    /// La lista de la asignatura de ese nombre.
    Asignatura { nombre: String },
    /// Una lista cualquiera, por su clave (`chat/mensaje`).
    Lista { clave: String },
}

/// Una entrada del desplegable, con su rotulo (y la marca ✓ si es la
/// elegida).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpcionDeDestino {
    pub destino: DestinoTarea,
    pub rotulo: String,
}

fn mismo(a: &str, b: &str) -> bool {
    normalizar(a.trim()) == normalizar(b.trim())
}

fn clave(l: &ListaTareas) -> String {
    super::tablero::clave(l)
}

/// Si una lista es la de una asignatura de `asignaturas`.
fn de_asignatura(l: &ListaTareas, asignaturas: &[String]) -> bool {
    l.asignatura.is_some() || (l.nombre_chat == NOMBRE_CHAT && asignaturas.iter().any(|n| mismo(n, &l.titulo)))
}

/// **Las entradas del desplegable**, en orden (`opciones` de Windows): el
/// Inbox (`inbox`, ya traducido), cada asignatura de `asignaturas` (con su
/// libro delante) y despues las demas listas de `listas` que no son ni el
/// Inbox ni la de una asignatura, cada una con su chat. `elegido` lleva la
/// marca ✓.
#[uniffi::export]
pub fn destinos_de_tareas(
    inbox: String,
    asignaturas: Vec<String>,
    listas: Vec<ListaTareas>,
    elegido: DestinoTarea,
) -> Vec<OpcionDeDestino> {
    let marca = |d: &DestinoTarea| if *d == elegido { "✓ " } else { "" };
    let mut v = vec![OpcionDeDestino {
        rotulo: format!("{}{inbox}", marca(&DestinoTarea::Inbox)),
        destino: DestinoTarea::Inbox,
    }];
    for n in &asignaturas {
        let d = DestinoTarea::Asignatura { nombre: n.clone() };
        v.push(OpcionDeDestino {
            rotulo: format!("{}📘 {n}", marca(&d)),
            destino: d,
        });
    }
    for l in listas.iter().filter(|l| !l.es_inbox && !de_asignatura(l, &asignaturas)) {
        let d = DestinoTarea::Lista { clave: clave(l) };
        let titulo = if l.titulo.trim().is_empty() { "Tareas" } else { l.titulo.as_str() };
        let chat = if l.guardados { "Mensajes guardados" } else { l.nombre_chat.as_str() };
        v.push(OpcionDeDestino {
            rotulo: format!("{}{titulo} · {chat}", marca(&d)),
            destino: d,
        });
    }
    v
}

/// **El «＋» del encabezado de la lista `l`** (`de_la_lista` de Windows): lo
/// que queda elegido en la caja. La de una asignatura, como su asignatura
/// (asi lo apuntado sigue a su enlace aunque la lista se renombre); el
/// Inbox, el Inbox; las demas, como esa lista.
#[uniffi::export]
pub fn destino_de_la_lista(l: ListaTareas, asignaturas: Vec<String>) -> DestinoTarea {
    if l.nombre_chat == NOMBRE_CHAT
        && let Some(n) = asignaturas.iter().find(|n| mismo(n, &l.titulo))
    {
        return DestinoTarea::Asignatura { nombre: n.clone() };
    }
    if l.es_inbox {
        return DestinoTarea::Inbox;
    }
    DestinoTarea::Lista { clave: clave(&l) }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn lista(chat: &str, titulo: &str, guardados: bool) -> ListaTareas {
        ListaTareas {
            chat: chat.to_lowercase(),
            nombre_chat: chat.into(),
            guardados,
            mensaje: format!("m-{}", titulo.to_lowercase()),
            titulo: titulo.into(),
            cuando: 1,
            es_inbox: guardados && titulo == "Inbox",
            tareas: Vec::new(),
            pendientes: 0,
            asignatura: None,
        }
    }

    fn muestra() -> Vec<ListaTareas> {
        let mut geo = lista("Asignaturas", "Geometría", false);
        geo.asignatura = Some(0x0A84FF);
        vec![
            lista("Mensajes guardados", "Inbox", true),
            geo,
            lista("Asignaturas", "Física", false),
            lista("Casa", "Compra", false),
        ]
    }

    fn destinos(v: &[OpcionDeDestino]) -> Vec<DestinoTarea> {
        v.iter().map(|o| o.destino.clone()).collect()
    }

    #[test]
    fn todas_las_listas_se_pueden_elegir_y_las_asignaturas_primero() {
        let asig = vec!["Geometría".to_string(), "Física".to_string(), "Arte".to_string()];
        let v = destinos_de_tareas("Inbox".into(), asig.clone(), muestra(), DestinoTarea::Inbox);
        assert_eq!(
            destinos(&v),
            [
                DestinoTarea::Inbox,
                DestinoTarea::Asignatura { nombre: "Geometría".into() },
                DestinoTarea::Asignatura { nombre: "Física".into() },
                // Sin lista aun: se crea al apuntar.
                DestinoTarea::Asignatura { nombre: "Arte".into() },
                DestinoTarea::Lista { clave: "casa/m-compra".into() },
            ]
        );
        assert_eq!(v[0].rotulo, "✓ Inbox");
        assert_eq!(v[1].rotulo, "📘 Geometría");
        assert_eq!(v[4].rotulo, "Compra · Casa");
        // La elegida lleva la marca.
        let v = destinos_de_tareas("Inbox".into(), asig, muestra(), DestinoTarea::Lista { clave: "casa/m-compra".into() });
        assert_eq!(v[0].rotulo, "Inbox");
        assert_eq!(v[4].rotulo, "✓ Compra · Casa");
    }

    #[test]
    fn el_mas_de_una_lista_elige_su_asignatura_o_esa_lista() {
        let ls = muestra();
        let asig = vec!["geometria".to_string(), "Física".to_string()];
        assert_eq!(destino_de_la_lista(ls[1].clone(), asig.clone()), DestinoTarea::Asignatura { nombre: "geometria".into() });
        assert_eq!(destino_de_la_lista(ls[0].clone(), asig.clone()), DestinoTarea::Inbox);
        assert_eq!(destino_de_la_lista(ls[3].clone(), asig), DestinoTarea::Lista { clave: "casa/m-compra".into() });
        // Caso negativo: una lista del chat «Asignaturas» que ya no es de
        // ninguna asignatura es una lista mas.
        assert_eq!(
            destino_de_la_lista(ls[2].clone(), vec!["Geometría".to_string()]),
            DestinoTarea::Lista { clave: "asignaturas/m-física".into() }
        );
    }
}
