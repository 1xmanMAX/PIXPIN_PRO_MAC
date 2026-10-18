# Plan de la sesión del 18-oct-2026 (secuencial, sin agentes)

Punto de partida: E4 (bandeja y grupos de ventanas) y E7 (visor reflujado)
estaban a medias; se terminaron, compilan y pasan las 540 pruebas de Swift y
las 405 del núcleo (commits `0651f69`, `ee681b5`). Windows avanzó 44 commits
(15-oct → 18-oct, `5c3c1a5..cf46430`).

Orden: primero lo que rompe la sincronización, después los crates comunes,
después las funciones nuevas de Windows, y al final los huecos viejos de
`paridad-windows.md`. Cada paso: compilar, probar, commit en `mac-desarrollo`.

## F. Ponerse al día con Windows (15→18 oct)

| # | Paso | Windows | Mac |
|---|---|---|---|
| F1 | **Galería que viaja con el texto de cada captura** (formato de sincro) | crates/pixpin-sincro/src/galeria.rs | nucleo/pixpin-sincro |
| F2 | Ajustes y textos nuevos (`[asistente]`, conexiones, horario, kanban…) | crates/pixpin-store | nucleo/pixpin-store |
| F3 | `pixpin-motor2d`: geometría exacta, texto rico, fórmulas, láminas, gestos | crates/pixpin-motor2d | nucleo/pixpin-motor2d |
| F4 | `pixpin-ia`: calcar por recuadros/diagramas, banco de documentos, conexiones (Drive), diagrama, herramientas de la nube | crates/pixpin-ia | nucleo/pixpin-ia |
| F5 | Tareas que se entienden al escribirlas (`tareas/frase.rs`) y vista Kanban | apps/pixpin/src/tareas/* | N/tareas.rs, K/Tareas |
| F6 | Pin de una tarea con su nota | pines/tarea.rs | K/Pines |
| F7 | Horario de clases que llama | horario.rs, llamada.rs | N/horario.rs, K/VozVentanas |
| F8 | Enviar a los aparatos del grupo sin escanear | sincronizar/enviar_wifi.rs | N/sincro, K/Sincro |
| F9 | Asistente: modelo en el chat, fechas al minuto, conversación nueva, banco de documentos, acciones sobre documentos (`documentos_acciones.rs`, ya portado sin enganchar), hoja→lienzo, crear y usar lienzos | asistente/* | N/asistente/*, K/Asistente |
| F10 | Visores de Markdown y HTML como pin | visor_html.rs, notas_md/lector_web.rs, lector_pin.rs | K/Documentos |
| F11 | Caja del chat: ⌥⌫ repetido, el texto largo se corre, enlaces pulsables | caja_texto.rs | K/Chat/CajaEscribir.swift |
| F12 | Notas: fotos en el sitio del cursor | pixpin-notas/editor/fotos | N/notas |
| F13 | Pinear lo copiado | pines/sacar.rs | K/Pines |
| F14 | Conexiones del asistente: Google Drive (OAuth PKCE) | asistente/conexiones.rs | K/Asistente (ASWebAuthenticationSession) |

### Estado (18-oct, fin del grupo F)

Hecho y probado: F1–F11 y F14. F12 en el Mac lo da la pagina nueva de la
nota (lo de Windows era su editor nativo). F13 era un fallo solo de Windows.
De F9 queda: hoja→lienzo, el banco de documentos (pruebas de Windows) y la
nota de archivos con su fecha. El aspecto de la tabla de una foto
(`tabla_aspecto`) queda para despues: pide el OCR de pixeles.

## G. Huecos viejos (de `paridad-windows.md`)

- G1 Tareas (ventana): buscar, «Mover a…», borrar con deshacer, F2, pegar imágenes.
- G2 Marcas de texto de los pines (resaltar, subrayar) con su ⌘Z.
- G3 Menú del mensaje: anotar encima de una foto, unir PDF.
- G4 Hoja «+»: crear página y proyecto; las 5 entradas apagadas.
- G5 Compartir desde los lectores, PDF anotado.
- G6 E8: MCP y extensión del navegador.

## Cómo se prueba

`cargo test -p <crate>` en `apple/`, `swift build` y `swift test` en
`apple/app`, y la app montada con `herramientas/app.sh spm` abriéndola de
verdad (con capturas de pantalla si hay permiso).
