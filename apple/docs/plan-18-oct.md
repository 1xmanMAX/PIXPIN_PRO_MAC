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

### Estado (18-oct, fin del grupo G)

- G1: hecho con F5 (buscar, mover, borrar con deshacer, F2). Falta pegar
  imagenes en la tarea.
- G2: hecho (marcar lo elegido con Live Text: resaltar, subrayar, tachar,
  tapar).
- G3: «Unir PDF» hecho («Anotar encima» ya estaba).
- G4: «Proyecto entero» hecho; falta «Página de un proyecto» (`paginas`).
- G5: Compartir (hoja comun) en el lector y el visor reflujado. Falta el PDF
  con la tinta quemada.
- G6: MCP hecho (`nucleo/pixpin-mcp`, dentro de la app, `docs/mcp.md`). La
  extension del navegador queda.

Pruebas al acabar: 551 de Swift, 429 del nucleo, 447 de pixpin-ia, 17 del
MCP, todas en verde; la app montada, instalada en /Applications y arrancada.

### Estado (noche del 18-oct, segunda tanda)

Windows avanzo otros 18 commits (hasta `0de0eef`); ya en el Mac:
`pixpin-frase` (urgencia en vez de prioridad, mismos emoticonos), el horario
nuevo (ventana semanal, «avisar N», asignaturas como listas de tareas),
Google Calendar (avisos y `ver_calendario`) y la pagina nueva de la nota.
Ademas: imagenes en una tarea, el PDF con la tinta quemada al compartir,
el aspecto de la tabla de una foto y la extension del navegador
(`nucleo/pixpin-puente`, `extension-navegador/`,
`herramientas/registrar-navegador.sh`).

Queda: **hoja → lienzo** del asistente (`hoja_a_lienzo.rs` de Windows, unas
1.500 lineas): hace falta llevar al lienzo del chat las fotos recortadas de
cada zona y pintar lo hecho para compararlo; con PDFKit y Vision ya hay
con que leer la hoja.

## Cómo se prueba

`cargo test -p <crate>` en `apple/`, `swift build` y `swift test` en
`apple/app`, y la app montada con `herramientas/app.sh spm` abriéndola de
verdad (con capturas de pantalla si hay permiso).
