# Paridad Windows → Mac (15-oct-2026)

Qué tiene PixPin para Windows que el Mac aún no tiene, y en qué orden hacerlo.

- **Windows (referencia):** `ref/PIXPIN_PRO_WINDOWS` (`apps/pixpin/src`, `crates/`)
- **Mac:** `apple/app/Sources/PixPinKit` (en las tablas, `K/`), `apple/nucleo/pixpin-nucleo/src` (`N/`), `apple/app/Sources/PixPin/PixPinApp.swift` (`APP`), `apple/xcode/` (`XC/`)

Estados posibles:
- **completo**: hace lo mismo que Windows.
- **parcial**: existe, pero le falta lo que dice la nota.
- **falta**: no existe.
- **no aplica**: en Mac no tiene sentido o lo hace el sistema.
- **interno**: fontanería; la nota dice si el Mac necesita algo equivalente.

## Resumen

Lo cuenta la matriz §1: hay 169 filas. Algunos módulos grandes salen en varias filas (`ventana_chat`, `ventana_ajustes`, `ventana_editor`, `notas_md`, `pines`, `sincronizar`, `timeline`, `plano_cad`).

| Estado | Filas |
|---|---|
| completo | 23 |
| parcial | 61 |
| falta | 72 |
| no aplica | 6 |
| interno | 7 |

**Los 10 huecos que más pesan**, de más a menos valor para el uso diario y la sincronización:

1. ~~**«¿Qué sincronizar?» y las lápidas de proyecto.**~~ Hecho (A1).
2. ~~**Recordatorios.**~~ Hecho (A4): `recuerdaEn` en los mensajes y `⏰` en las tareas suenan con el vigía (al arrancar, tras sincronizar y al cambiar algo aquí), con «Hecha», «+10 min» y «Abrir» (C4).
   - Queda la llamada secreta (E5).
3. ~~**Sincronización automática incompleta.**~~ Hecho (A2): periodo de 10 min, tareas al instante, dos rondas, aviso al tercer fallo, `presencia=false` y `fusionados`.
   - Queda `direcciones.txt` (A3).
4. ~~**Los pines no se guardan ni se restauran** entre arranques.~~ Hecho (B1): el mismo `almacen/indice.json` que Windows, filtros, giros, negativo, modo texto, tamaños 1–3, flechas y ⌘T.
   - Quedan las marcas de texto guardadas (resaltar, subrayar) y su ⌘Z.
5. **El menú del mensaje del chat** ya es el de Windows (B2): etiquetas, responder, copiar, pinear, describir, reenviar, compartir, recordar, hacer lección, renombrar, fijar, abrir con, guardar del buzón y ver comentarios, con sus letras. Faltan anotar encima de una foto, exportar e imprimir un lienzo, unir PDF y la letra de una voz. Tampoco hay buscar dentro del chat ni la hoja «+».
6. **Tareas y Timeline casi de solo lectura.**
   - Tareas: falta buscar, mover, editar, y borrar con deshacer.
   - Timeline: no se puede apuntar nada.
7. **Compartir y exportar común**: PDF, PNG, SVG y web, más la ventanita «Salida». No existe.
8. **Lectores sin búsqueda.**
   - Faltan buscar (⌘F/⌘G), ir al marcador con ⌘1…9, el negativo, el avance solo y renombrar.
   - Falta escuchar en voz alta (`leer_en_voz`).
   - Falta recargar la tinta si cambia en el disco (`al_dia`).
9. **Atajos globales configurables.** Hecho (C1): los 27 comandos del catálogo, regiones, silenciar y apps ignoradas, en Ajustes → Atajos. «Dejar pasar el clic» y «restaurar el último pin», hechos con B1. Faltan el esquema `pixpinmax://`, los pedidos y el menú del Dock.
10. **El núcleo `pixpin-ia` del Mac va muy por detrás de Windows**: le faltan 10 módulos. También van detrás `pixpin-motor2d` y las letras de `pixpin-pdf`. Por eso el asistente del Mac no hace lo que hace el de Windows.

---

## 1. Matriz de funciones

### 1.1 Módulos de `apps/pixpin/src` (a–l)

| Módulo Windows | Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|---|
| abrir_con | «Abrir con…» (elegir app) en pines, chat, buscador | falta | K/Chat/Adjuntos.swift (solo app por defecto) | Selector de app con `NSWorkspace` y un aviso claro si falla |
| abrir_hoja | Abrir una hoja de proyecto por referencia, sin el chat | parcial | K/Almacen.swift | Abrir desde fuera (intents, grupos, pedidos) |
| abrir_imagen | Doble clic en una imagen → pin rápido | parcial | K/Pines/GestorPines.swift | Las imágenes no están en `CFBundleDocumentTypes` |
| al_frente | Qué chat o lienzo está delante para recibir «Enviar a» | parcial | K/Sincro/EnviarA.swift, N/envio.rs | El lienzo nunca se apunta como frente (`FrenteMac::Lienzo`) |
| aligerar | Comprimir los PDF que entran (pdfsqueeze) | completo | K/Documentos/AligerarPdf.swift, N/aligerar.rs | — |
| anotado_del_adjunto | Tinta, marcas y espacios `anot-<uid>…` de los lectores | parcial | N/documentos.rs, K/Documentos/LectorDocumento.swift | Word y EPUB reflujados (`.maqueta`) |
| anotador_al_chat | Lo anotado en la pantalla va al chat con su lienzo editable | falta | K/Captura/Capturador.swift (lo quema en la imagen) | Foto con `.excalidraw` en «Mensajes guardados» |
| asistente (chat, motor, nube, descarga, turno) | IA local o en la nube | parcial | K/Asistente/*, N/asistente.rs, N/llavero.rs | Nube por URLSession; descargar el modelo; catálogo del motor para Mac |
| asistente (recetas, pensado, permiso) | Recetas, lo pensado, permisos Sí/No | falta | — | Todo |
| asistente (ojos, hoja_a_lienzo, anotar_inteligente, al_lienzo, documentos) | El asistente mira el lienzo, pasa una hoja al lienzo, anota documentos | falta | — | Todo; hace falta antes el `pixpin-ia` al día (§3.2) |
| asistente (en_el_chat, externa/MCP) | Asistente dentro de cualquier chat; servidor MCP | falta | K/Asistente (es una ventana aparte) | Asistente en el chat; MCP para Mac |
| audio | Un reproductor para toda la app: barra, saltos, velocidad | parcial | K/Voz/ReproductorVoz.swift | Velocidad, saltos ±, barra global de «lo que suena» |
| automatizaciones (cola, encargo, motor) | Disparadores con pasos; cola de encargos | falta | — | Todo; `auto-automatizaciones` llega y no se usa |
| biblioteca_audio | Música y notas de voz de todos los chats | falta | — | Todo |
| biblioteca_figuras | Figuras del lienzo (`figuras.json`, viaja) | parcial | K/Lienzo/FigurasLienzo.swift, N/editor_figuras.rs | Hechos: gráfica, tabla en blanco y pegada, plano/recta/espacio, guardar, estampar y quitar (en el chat «Asistente», con su mensaje `auto-figuras`). Faltan editar una tabla ya dibujada, meter en su celda y las tablas de coordenadas |
| buscador | Ctrl+F en los lectores, «3 de 12», F3 | falta | K/Documentos/LectorDocumento.swift | `PDFDocument.findString` con siguiente y anterior |
| buscar_todo | «Buscar en PixPin»: pestañas, recientes, acciones | parcial | K/Buscar/Buscar.swift, N/buscar.rs | Pestañas; recientes; lecciones y capturas; botones por fila; usar `pixpin-lanzador` |
| cabecera | Barra común de Galería, Lecciones, Tareas y Timeline | no aplica | SwiftUI | — (unificar su aspecto) |
| caducidad_capturas | Capturas que se borran solas | completo | K/Caducidad/BarrenderoCapturas.swift, N/galeria.rs | — (el aviso «se van en 24 h», con «Conservar» y «Abrir», hecho en C4) |
| caja_dibujo | Barra de herramientas estilo Excalidraw, la misma en todas partes | parcial | K/Lienzo/* | La del lienzo ya es la de Windows (los diez grupos, figuras, dos filas si no cabe). Lector, pin y captura siguen con barras propias |
| caja_texto | Caja de texto propia | no aplica | NSTextField | — |
| capa | Anotar sobre la pantalla (viva o congelada, varios monitores) | parcial | K/Captura/Capturador.swift, GestosAlt.swift | Modo vivo, varios monitores, herramientas del lienzo, entrada en el menú |
| captura2 | Captura v2: modos, medidas, lupa, «Al chat», anotar | completo | K/Captura/* | Falta verla en verde en la CI |
| centro_bandeja | Panel rico de la bandeja: estado de sincro, buscador, favoritos, últimas capturas | parcial | APP (MenuBarExtra en forma de menú) | El panel entero |
| cielo | Fondo cósmico | falta | — | Es un adorno |
| compartir (ventana, pdf, pdf_anotado, word, web, enlace, exportable) | Hoja de compartir: PDF, PNG, SVG, web, Word, enlace; menú Exportar | parcial | K/Lienzo/SacarLienzo.swift, N/editor_exportar.rs | Solo el lienzo: exportar PNG, SVG y PDF (todo, lo elegido o cada marco), copiar como PNG, imprimir con «qué imprimir» y compartir con la hoja del Mac. Falta la hoja común (D1), la página web y lo demás |
| conversacion | Grabar una conversación por turnos (teclas 1–9) | falta | K/Voz/* | Todo |
| croquis3d | Ver los croquis 3D del móvil | falta | K/Planos/VisorModelo3D.swift | Abrir `.croquis.gz` en N/modelos3d.rs |
| cuenta_atras | Captura con retardo | parcial | K/Captura/CapturaDirecta.swift (`CuentaAtras`, 3 s) | Esc para cancelar; los segundos de `retardo_captura_s` |
| diapositivas | Presentar un PPTX (orador, notas, negro); PPTX → proyecto | falta | K/Documentos/LectorDocumento.swift (solo verlo) | Todo |
| dibujo/ | Herramientas comunes: construir, grupos, lupa, copiar y pegar | parcial | K/Lienzo/*, N/editor*.rs | Hechas todas las herramientas de la barra (zona, láser, lupa, foco, pixelar, marco, copiar estilo, bolita, soldar vértices: N/editor_herramientas.rs, N/editor_tapado.rs). Faltan copiar y pegar elementos, agrupar y los atajos de §2.5 |
| dispositivo_perdido | Recuperarse si se pierde la GPU | interno | — | Solo para Metal en Planos, si se quita la GPU |
| editor | Revisar la grabación antes de guardarla | falta | K/Grabar/GrabadorPantalla.swift (guarda directamente) | Todo |
| fondo_lienzo | Un pin o una página PDF como fondo del lienzo | parcial | K/Lienzo/FondoLienzo.swift, K/Pines/Anotar.swift | El lienzo ya sabe llevar fondo (imagen o página de PDF a 1400 de ancho, dentro de lupas, zona y lo exportado): `VentanasDeLienzo.abrir(…, fondo:)`. Falta quien lo abra así (la hoja-página del chat, B9; el pin) |
| foto_anotada | Ver el lienzo que el móvil dibujó sobre una foto | falta | K/Chat/Adjuntos.swift | Leer `lienzos/foto-<id>.excalidraw` y pintarlo encima |
| fusionar_paginas | Varias páginas de un PDF → un lienzo | falta | — | Todo |
| galeria_capturas | Galería con buscador (también OCR), grupos por día, teclado, detalle | parcial | K/Galeria/*, N/galeria.rs | Buscador, grupos por día, teclado, «Guardar como», panel de detalle |
| gif | GIF en dos fases: marco y luego barra | parcial | K/Captura/GrabadorGif.swift | Marco movible, ajustes, ↩ para empezar y parar |
| grabador | Grabación en dos fases | parcial | K/Grabar/* | Marco ajustable antes de grabar |
| grupos_ventanas | Guardar y reabrir grupos de ventanas | falta | — | Todo |
| hoja_pin | Excel como pin, ver y editar en el mismo sitio; libro de varias hojas | parcial | K/Documentos/HojaCalculo.swift, N/hojas*.rs | Editar un `.xlsx` como libro; todas las hojas del móvil |
| imagenes_lienzo | Imágenes pegadas en el lienzo | completo | K/Lienzo/ImagenPegadaLienzo.swift | — |
| instancia_de_prueba | Instancia aislada para desarrollar | no aplica | — | — |
| lecciones | Ficha, etiquetas, repaso, dictado, fotos y audios, exportar | parcial | K/Lecciones/*, N/lecciones.rs | Dictado, adjuntos (foto o voz; las del móvil no se ven), exportar |
| lector | Lo común a los lectores: papel, riel de marcadores | parcial | K/Documentos/LectorDocumento.swift | Riel de marcadores, negativo |
| lector_pdf | Lector PDF, Word y PPTX | parcial | K/Documentos/LectorDocumento.swift, PintorOffice.swift | Buscar, escuchar, D, N, imprimir, F5, ⌘1…9, `al_dia`, texto de Office |
| lector_pdf_proyecto | Dónde va la tinta de un PDF | completo | N/documentos.rs | — |
| lector_pin | Los lectores como pin | completo | K/Documentos/LectorDocumento.swift | La barra flotante de los pines |
| lector_tinta | Capa de tinta sin desfase | parcial | N/documentos.rs | Word y EPUB reflujados |
| leer_en_voz | Escuchar un documento resaltando por dónde va, con teclas multimedia | falta | — | `AVSpeechSynthesizer` y `MPRemoteCommandCenter` |
| letras_que_viajan | Las letras SHX viajan entre aparatos | parcial | nucleo/pixpin-cad (las lee) | No crea `auto-letra-*` |
| lista_del_icono | Jump List | falta | — | En Mac, el menú del Dock (`applicationDockMenu`) |
| llamada | «Llamada secreta» (VOZ con `recuerdaEn`) | falta | — | Depende de los recordatorios |

### 1.2 Módulos m–z y `main.rs`

| Módulo Windows | Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|---|
| main (bandeja) | Menú de la bandeja con 27 comandos | parcial | APP, K/Ajustes/ComandosApp.swift | Faltan: clic a través y restaurar el último pin (salen solos cuando los pines los den) |
| main (arranque) | Restaurar pines, vigía de recordatorios, automatizaciones, línea de órdenes, avisos de caducidad | parcial | APP, K/Pines/GestorPines.swift | Recordatorios, automatizaciones |
| marco_de_la_tinta | Migrar la tinta vieja al marco `.hoja` | interno | N/documentos.rs (lee el marco) | Pasada `tras_sincronizar`; solo hace falta con datos viejos |
| medir_fotogramas | Medir fotogramas | interno | — | No hace falta (Instruments) |
| mini_panel | Mini-apps: tareas, contador, ruleta, gastos, relojes | completo | K/Pines/Herramientas.swift, RelojesPin.swift, N/miniapps.rs | Su teclado (F2, Supr, «25»+↩) |
| miniaturas | Fotos del proyecto en el panel de información | falta | — | Todo |
| modelo_bim | IFC, Revit, LandXML en 3D | parcial | K/Planos/VisorModelo3D.swift, N/modelos3d.rs | Vistas guardadas, caché; probarlo en un Mac real |
| navegacion | Cámara del lienzo | parcial | K/Lienzo/EditorLienzoView.swift | Espacio + arrastrar (lo lleva el agente del lienzo) |
| notas_md (editor, guardar) | Editor de notas Markdown | parcial | K/Documentos/EditorNota.swift, N/notas.rs | Atajos de formato |
| notas_md/adjuntos | Fotos dentro de la nota | falta | — | Todo |
| notas_md/comentarios | Comentarios (`anot-<uid>.comentarios.json`, viajan) | falta | — | Leer, escribir y sincronizar |
| notas_md/incrustados | Documentos o mensajes dentro de la nota | falta | — | Todo |
| notas_md/paginas_vivas | Páginas vivas y enlaces a hojas | falta | — | Todo |
| notas_md/lector_web | Modo lector de la nota | falta | — | Todo |
| notificaciones | Notificaciones con botones: «Hecha», «+10 min», «Abrir», «Conservar» | completo | K/Avisos/CentroAvisos.swift, K/Pines/AvisosMini.swift | Sin permiso del sistema, lo urgente sale en una ventanita de la app con los mismos botones |
| orden | Línea de órdenes y `pixpinmax://` | falta | — | `CFBundleURLTypes` y los verbos |
| oscuro | Modo oscuro de los visores (luna/sol) | parcial | K/Ajustes/ModeloAjustes.swift | Botón en los pines-lector |
| overlay | Overlay de captura | parcial | K/Captura/* | ⌘A, flechas, Espacio, ⇧ HEX/RGB, ⇧⌘S, Supr; comandos sin barra |
| panel_dibujo | Panel de estilo del lienzo | parcial | K/Lienzo/BarraEstiloLienzo.swift | **Lo lleva el agente del lienzo** |
| pdf_del_proyecto | Rehacer un PDF roto desde `pdfLimpio` | falta | — | Todo |
| pdf_en_chat | El PDF como un mensaje con vista; unir páginas | parcial | K/Chat/Adjuntos.swift, K/Documentos/AccionesDocumento.swift | Unir PDF, «como imágenes», devolver |
| pedidos | Pedidos de otros programas | parcial | XC/App/Intenciones.swift (4 intents) | Tarea, lienzo, grabar, abrir proyecto, al móvil… |
| pegar_en_flow | Pegar en Flow Launcher | no aplica | — | — |
| pila_capturas | Pila de capturas | completo | K/Captura/PilaCapturas.swift | — |
| pin_office | Office como pin con la vista previa del sistema | completo | K/Documentos/PinOffice.swift | Su F11 (⌃⌘F) |
| pin_vivo | Pin en vivo | completo | K/Pines/PinEnVivo.swift | — |
| pines (gestor) | Guardar y restaurar pines, restaurar el último | completo | K/Pines/GestorPines.swift, K/Pines/AlmacenPines.swift | El mismo `almacen/indice.json` (en puntos del Mac). Los lectores, hojas, Office y planos (otras tandas) aún no se guardan; ocultar un grupo entero no existe en Mac |
| pines (ventana) | Filtros 5–8 y 0, negativo, girar, voltear, tamaños 1–3, flechas, clic a través | completo | K/Pines/Pin.swift, K/Pines/FiltrosPin.swift | Filtros, giro y volteos solo en fotos (en Windows, en todo pin con imagen); el negativo, en todos |
| pines/abiertos | Panel «Pines abiertos» | completo | K/Pines/PanelAbiertos.swift | ⎋ |
| pines/dispositivo | Pines tras perder la GPU | no aplica | — | — |
| pines/extras | Pegatina de la esquina | parcial | K/Pines/RelojesPin.swift | La pegatina para cualquier pin |
| pines/marcas_texto | Resaltar o subrayar el OCR del pin; modo T | parcial | K/Pines/Pin.swift (Live Text) | Marcas guardadas y su ⌘Z |
| pines/panel | Panel de anotar | completo | K/Pines/Anotar.swift | — |
| pines/pizarra | Pines pizarra y hoja | falta | — | Todo |
| pines/herramienta, sacar | Mini-app en un pin; sacarla escribiendo su nombre | parcial | K/Pines/Herramientas.swift | Sacarla por la palabra |
| plano_cad (visor) | DWG/DXF como pin | parcial | K/Planos/VisorPlano.swift, N/planos.rs | Caché `.pxcad`; probarlo en un Mac real |
| plano_cad/anotar | Anotar el plano a mano | falta | — | Depende del lienzo |
| plano_cad/exportar | Exportar el plano | falta | — | Todo |
| plano_cad/imprimir | Imprimir | completo | K/Planos/ImpresionPlano.swift | — |
| plano_cad/textos | Buscar en los textos del plano | falta | — | Todo |
| pronunciar | Practicar la pronunciación | falta | — | Todo |
| punto_de_proyecto | Punto verde o rojo en la burbuja | falta | — | Todo |
| recibir | Recibir del móvil con QR; lienzo suelto | parcial | K/Sincro/EnvioPorCodigo.swift, N/envio.rs | El lienzo suelto llega como fichero, no a su proyecto |
| recibir_de_windows | «Imprimir a PixPin» y Compartir | parcial | XC/Compartir | PDF Services («Guardar en PixPin» del diálogo de imprimir) |
| recordatorios | «Recuérdame a las 10» y el vigía | completo | N/recordatorios.rs, K/Recordatorios/{Vigia,Avisos}.swift | Sin hilo en Rust: el vigía es de Swift (temporizador de pared + notificación del sistema para la app cerrada). La llamada secreta es E5 |
| renombrar_doc | F2 para renombrar en el lector | falta | — | Todo |
| reproductor | Editor de grabaciones | falta | — | Todo |
| salida | Ventanita «Salida» para arrastrar lo exportado | falta | — | Todo |
| salto_por_enlace | Abrir el sublienzo de una zona | falta | — | Depende de zona_al_chat (lienzo) |
| scroll | Captura con scroll | completo | K/Captura/CapturaConScroll.swift | — |
| sincronizar (pantalla) | Este aparato, tus aparatos, añadir | parcial | K/Sincro/VistaSincro.swift | Renombrar el aparato, salir del grupo, miembros que no están en la red («hace X») |
| sincronizar/al_dia | Llegar aunque cambie la IP | parcial | K/Sincro/Bonjour.swift, BuscarPuerta.swift | `sincro/direcciones.txt` |
| sincronizar/al_movil | Foto al lienzo abierto del móvil | parcial | K/Sincro/EnviarA.swift | Recibirla en el lienzo del Mac |
| sincronizar/automatica | Sincronizar solo | completo | K/Sincro/Sincronizador.swift, N/sincro_auto.rs | — |
| sincronizar/compartidos_ui | Chats compartidos con personas | completo | K/Sincro/Compartidos.swift | — |
| sincronizar/copias_ui | Ver y restaurar copias; proyectos borrados | falta | — | El crate hace las copias; no hay pantalla |
| sincronizar/elegir | «¿Qué sincronizar?», lápidas, «Lo mío manda» | completo | K/Sincro/ElegirSincro.swift, N/sincro.rs | «Lo mío manda» por defecto (el TOML) aún no sale en Ajustes (C3) |
| sincronizar/en_fondo | Sincronizar sin ventana | completo | Intent `SincronizarAhora` | — |
| sincronizar/enviar_wifi, recibir_wifi | Enviar y recibir con código | parcial | K/Sincro/EnvioPorCodigo.swift | Mandar proyectos y lienzos; «actualizar o crear» |
| sincronizar/galeria | La galería viaja | completo | N/galeria_sincro.rs | — |
| sincronizar/presencia | Localizable mientras está abierta | completo | K/Sincro/Anunciador.swift, Sincronizador.swift | El interruptor en Ajustes es C3 |
| tareas (ventana) | Tareas de todos los chats | parcial | K/Tareas/Tareas.swift, N/tareas.rs | Buscar, «Mover a…», borrar y deshacer, F2, pegar imágenes (el `⏰`, hecho en A4: se ve y se pone desde el menú de la fila) |
| tareas/rejilla, tarjetas, emoticonos | Vista de tarjetas y etiquetas | falta | — | Todo |
| teleprompter | Telepronter | falta | — | Todo |
| tema_cosmos | Tema Cosmos | falta | — | Es un adorno |
| timeline (ventana) | Hoy, Momentos, Estado, Lecciones; apuntar | parcial | K/Timeline/Timeline.swift, N/timeline.rs | Es de solo lectura: no se apunta |
| timeline/dictar, exportar, tarjetas, estado_mes, compartir | Dictar; exportar a HTML o PDF; vista por mes | falta | — | Todo |
| turno_pesado | Un trabajo pesado cada vez | interno | — | Solo si llega Whisper |
| v2/ | Aviso con Deshacer, pista, pegar | interno | SwiftUI | Un aviso «Deshacer» común |
| ventanita | Base de las ventanitas de voz | interno | — | Hará falta con el telepronter y Pronunciar |
| visor | Word, EPUB y páginas reflujados | parcial | K/Documentos/LectorDocumento.swift (paginado) | Reflujo, letra (+/−, T, B), índice, «PDF como texto», tinta del EPUB |
| visor/como_texto, imagenes, tablas, maqueta_movil | — | falta | — | La maqueta del móvil (para que la tinta caiga igual) |
| visor_hoja | `.xlsx` entero como pin | parcial | K/Documentos/HojaCalculo.swift | Pestañas, ⌘flechas, enlaces, capa de tinta |
| visor_html | `.html` a pantalla completa | falta | — | `WKWebView` sin marco |
| vista_rapida | Espacio en el Explorador | no aplica | XC/VistaPrevia | Quick Look del Finder |
| voz | Nota de voz → texto | completo | K/Voz/* | — |
| voz_en_chat | Corregir la letra, Pronunciar, turnos | falta | — | Todo |
| zona_al_chat | La zona del lienzo al chat como sublienzo | falta | — | Depende del lienzo |

### 1.3 Ventana del chat (`ventana_chat.rs` y `ventana_chat/`)

| Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|
| Lista de proyectos; chat por páginas; burbujas por tipo | completo | K/Vistas.swift, K/Chat/* | — |
| proyectos/ (tarjeta rica, «universo», teclado) | parcial | K/Vistas.swift | Tarjeta y universo |
| logo del proyecto; «Guardar en…» al crearlo | falta | — | Todo |
| Caja de escribir | parcial | K/Vistas.swift | Salto de línea con ⇧↩; Esc limpia |
| Hoja «+» (captura, lienzo, tabla, tareas, página, nota, móvil…) | parcial | K/Vistas.swift | Solo están «Lienzo nuevo» y el micrófono |
| Enviar fotos con descripción | falta | — | Todo |
| Caja de soltar flotante | parcial | K/Vistas.swift | Hay soltar sobre el chat |
| Tarjetas de enlace | falta | — | Todo |
| Menú del mensaje (menu_v2) | parcial | K/Chat/MenuMensaje.swift, K/Chat/BorrarMensajes.swift, N/chats.rs | Hecho (B2): etiquetas ⭐✅⏳💡💰📍, Responder (con la cita en la burbuja y la barra encima de la caja), Copiar, Pinear (fichero o lista de tareas), Añadir/editar descripción, Abrir en el editor de notas, Pasar a texto, Reenviar, Compartir, Recordármelo (horas de Windows y «Elegir la hora…»), Hacer lección (con `deMensaje`), Cambiar el nombre, Fijar arriba (y la barra «Mensaje fijado»), Abrir con…, Aligerar el PDF, Guardar esto, Ver comentarios, Elegir varios, Borrar; la barra de elegidos con Copiar, Compartir, Fijar, Reenviar y Borrar. Falta: Anotar encima y Abrir en lienzo de una foto (**dep. lienzo**, foto anotada), Exportar e Imprimir un lienzo (**D1**), Unir/Devolver al proyecto y «como imágenes» (PDF en el chat), Insertar en nota, Letra, Ver el dibujo entero, Guardar receta (asistente) y la llamada secreta de una voz (**E5**) |
| Elegir varios y marcar un tramo | completo | K/Chat/BorrarMensajes.swift | — |
| Buscar dentro del chat (Ctrl+F) | falta | — | ⌘F hoy abre «Buscar en todo» |
| Escala (Ctrl + / − / 0) | falta | — | Todo |
| Fondos del chat | falta | — | Todo |
| Micrófono flotante con hora | falta | — | Todo |
| Reproductor flotante | parcial | K/Voz/VistasVoz.swift | Espacio, ←/→, barra |
| Chat «Asistente» del sistema; aviso y voz del asistente | falta | — | Todo |

### 1.4 Ajustes (`ventana_ajustes.rs`)

| Sección | Estado Mac | Qué falta (Mac: K/Ajustes/*) |
|---|---|---|
| Interfaz (buscador, restablecer, ⌘Z) | falta | Todo |
| General | parcial | Idioma |
| Captura | parcial | Retardo, formato del color, ajustes de scroll y GIF, carpeta, programas ignorados |
| Pinear | falta | Todo |
| Lienzo (imán, suavizado) | falta | Depende del lienzo |
| Voz | falta | Segundo idioma, modo |
| Asistente (modelo, pensar, claves) | falta | Pantalla de claves; el Llavero ya está |
| Atajos | completo | K/Ajustes/SeccionAtajos.swift (pestaña «Atajos»); UserDefaults, no el TOML (no viaja) |
| Sincro | parcial | Los interruptores de presencia y «Lo mío manda» (el Mac ya los respeta) |
| Apps (abrir con, predeterminada) | falta | Todo |
| Apariencia (Cosmos) | parcial | Cosmos |
| Avanzado | falta | Todo; casi nada aplica en Mac |

### 1.5 Editor del lienzo (`ventana_editor/`)

**Todo esto lo lleva el agente del lienzo; aquí solo consta para que se sepa.**

| Función | Estado Mac |
|---|---|
| Base, deshacer, cota y cajetín | completo |
| modo_ventana (F11) | completo (⌃⌘F, se recuerda en `estado.toml`; nunca tocado abre en ventana) |
| Exportar, imprimir y compartir; tapado; figuras y gráficas; lupas | completo (figuras: parcial, ver `biblioteca_figuras`) |
| Hojita; marcas; presentar; referencia; anotador de pantalla; zona al chat | falta |
| congelar, medir | interno |

### 1.6 Fuera de `apps/pixpin`

| Pieza Windows | Estado Mac | Nota |
|---|---|---|
| `apps/pixpin-mcp` (servidor MCP para Claude) | falta | Se podría hacer en Mac con el mismo protocolo (stdio) |
| `apps/pixpin-puente` y `extensiones/navegador` | falta | Native Messaging de Chrome/Edge; en Mac también hay Safari |
| `apps/pixpin-lanzador` (buscar) | parcial | Está en `por-adaptar/` y va por detrás de Windows (6 ficheros distintos) |
| `apps/pixpin-aligerar` | completo | Igual que Windows; el Mac usa N/aligerar.rs |
| Integraciones: CLI, PowerShell, AutoHotkey, menú del Explorador | falta | En Mac: el esquema de URL, App Intents (4 hechos), Servicios del Finder |
| Extensión Compartir y Quick Look | completo | Solo en Mac (XC/Compartir, XC/VistaPrevia) |

---

## 2. Atajos de teclado

Cómo se pasan las teclas al Mac: Ctrl→⌘ y Alt→⌥. **La excepción son los globales: Ctrl+Alt→⌃⌥**, para no pisar ⌘⇧3/4/5 ni los atajos de cada app.

Choques con macOS que hay que esquivar:
- ⌘M minimiza y ⌘⌥M minimiza todas.
- ⌘H oculta la app.
- ⌘G es «buscar siguiente».
- F11 muestra el escritorio; usar ⌃⌘F.
- ⌃2 es «Escritorio 2».
- ⌃-clic abre el menú contextual.
- ⌥N y ⌥R componen letras, así que hay que leerlos por keyCode.
- F2, F3 y F5 necesitan fn.

### 2.1 Globales

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Ctrl+Alt+X | Capturar zona | ⌃⌥X (se puede cambiar) | completo |
| Ctrl+2 | Mostrar u ocultar los pines | ⌃2 | completo |
| — | Grabar pantalla | ⌃⌥R | solo Mac |
| 25 comandos sin tecla de fábrica, que el usuario puede atar | Capturar y copiar, scroll, anotar, GIF, última región, cuentagotas, pinear, en vivo, portapapeles, selección, retardo, silenciar, clic a través, restaurar o cerrar pines, OCR, ventana encima, chat, ajustes, recibir, sincronizar, buscar, salir | sin tecla de fábrica; se atan en Ajustes → Atajos (mejor ⌃⌥+tecla) | completo salvo clic a través y restaurar el último pin (esperan a los pines). Cuentagotas = `NSColorSampler`; ventana encima = pin en vivo de la ventana (macOS no deja subir ventanas ajenas); anotar = sobre la foto congelada |
| Atajo por región (Ctrl+Alt+1…) | Capturar una región fija | ⌃⌥1… (Ajustes → Atajos → Regiones, «Guardar la última zona») | completo |
| Silenciar atajos · programas ignorados | Soltarlos todos · no actuar delante de una app | menú de la barra y Ajustes · lista de apps en Ajustes | completo (los gestos con ⌥ aún no miran la lista) |
| Choques | Dos comandos con el mismo atajo | Se rechazan; también los de macOS (⇧⌘3/4/5/6, ⌘+tecla, ⌥⌘H/M/D, ⌃⌘Q/F) y se avisa de ⌃1…9, ⌃F1…F8 y ⌃⌘D | completo |
| Alt + arrastrar (izquierdo, derecho, central) | Copiar, pinear, pin en vivo | ⌥ + arrastrar | completo (apagado de fábrica; pide Accesibilidad) |
| Alt + doble clic central | Anotar la pantalla | ⌥ + doble clic central | parcial (abre la captura) |
| Menú: — | Proyectos, Buscar | ⌥⌘P, ⌥⌘F (solo con el menú) | solo Mac |

### 2.2 Captura (overlay)

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Z V P S G L T | Modos | igual | completo |
| R | Repetir la última zona | R | completo |
| C | Copiar el color | C | parcial (solo HEX) |
| Mayús sola | HEX ↔ RGB | ⇧ | falta |
| Ctrl+A | Pantalla entera | ⌘A | falta |
| Intro / Ctrl+C | Copiar | ↩ / ⌘C | completo |
| Ctrl+P · Ctrl+M · Ctrl+T · Ctrl+S | Pinear, al chat, OCR, guardar | ⌘P · ⌘M (choca, se lo queda el overlay) · ⌘T · ⌘S | completo |
| Ctrl+Mayús+S | Guardar como | ⇧⌘S | falta |
| — | Grabar la zona | ⌘G | solo Mac |
| Esc | Descartar | ⎋ | completo |
| Ctrl+Z / Ctrl+Y | Deshacer / rehacer la anotación | ⌘Z / ⇧⌘Z | completo |
| 1–5 | Herramientas de anotar | 1–5 | completo |
| Supr | Borrar la anotación elegida | ⌫ | falta |
| Flechas (Mayús ×10) · Espacio | Mover la selección | igual | falta |
| Texto: ← → Inicio Fin Supr | Editar el texto | — | parcial |
| Medidas: Tab · Selector de proyecto: ↑↓, Tab al comentario | — | ⇥ · 1–6, ↩ | parcial |
| Cuentagotas: Intro/C · Cuenta atrás: Esc | — | — | falta |
| GIF: Intro empieza y para, Esc global | — | ⎋ solo con el foco | parcial |

### 2.3 Pines

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Ctrl+C | Copiar la imagen o el texto marcado | ⌘C | completo |
| Mayús+C · T | Copiar todo el OCR · modo texto | ⇧C · T | completo |
| A | Anotar | A | completo |
| Ctrl+0 | Tamaño original | ⌘0 (y ⌘+/⌘− solo en Mac) | completo |
| 1 2 3 · 5 6 7 8 0 · N | Tamaños · gris, invertir, brillo, restaurar · negativo | igual (⌥N en una nota o mini-app) | completo |
| R / Mayús+R · H / V | Girar · voltear | igual (sin ⌘) | completo |
| Ctrl+T | Dejar pasar el clic | ⌘T (vuelta: menú «Pines: dejar pasar el clic» o su atajo) | completo |
| Ctrl+Z (sin anotar) | Deshacer la marca de texto | ⌘Z | parcial |
| Esc por capas | — | ⎋ | completo |
| Flechas (Mayús ×10) | Mover el pin | igual | completo |
| RePág / AvPág | Página | Fn+↑ / Fn+↓ (RePág / AvPág) | completo |
| Espacio · M | Reproducir · silenciar | igual | completo |
| ← → ↑ ↓ en vídeo | ±5 s, volumen | igual (⇧ + flechas mueve) | completo |
| Rueda · Mayús+rueda · Ctrl+rueda | Tamaño · opacidad · zoom de dentro | igual, ⌥+rueda · ⌘+rueda | completo / parcial |
| Ctrl + arrastrar · Alt al arrastrar | Sacar arrastrando · sin imán | ⌘ + arrastrar · ⌥ | parcial · completo |
| Mini-apps: Intro, ↑↓, Alt+↑↓, F2, Supr, Espacio, RePág/AvPág | — | Espacio, V, ↩ | parcial |
| Pin de Office: F11, Esc | — | ⌃⌘F | parcial |

### 2.4 Chat

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Intro / Mayús+Intro | Enviar / salto de línea | ↩ y ⌘↩ / ⌥↩ | completo (otro salto) |
| Ctrl+V | Pegar adjunto | ⌘V | completo |
| Ctrl+F | Buscar en el chat | ⌘F (abre Buscar en todo) | parcial |
| Ctrl + / − / 0 | Escala | ⌘+ / ⌘− / ⌘0 | falta |
| Esc en cascada | — | ⎋ | parcial |
| Menú: R, Ctrl+C, P, A, E, N, T, F, L, F2, Supr | Acciones del mensaje | R, ⌘C, P, E, N, T, F, L, F2 (en «Más»), ⌫ con el menú abierto; falta A (anotar encima) | parcial |
| Ctrl+clic, Mayús+clic | Elegir varios | ⌘-clic, ⇧-clic | completo |
| Hoja «+»: flechas, Intro · Reproductor: Espacio, ←→ · Micrófono: Esc, Intro, ↑↓ | — | — | falta |
| Renombrar o describir: Intro, Esc | — | Intro guarda, Esc lo deja (hoja de una línea; también «Elegir la hora…») | completo |

### 2.5 Lienzo

Las letras de herramienta son ya las de Windows (M L R T B A E G P F Q C Z J); S O D X W N, las de Excalidraw que allí no se usan.

Lo que falta en el lienzo:
- ⌘C / ⌘X de elementos, ⌘D, ⌘G / ⇧⌘G y ⇧⌘L.
- ⌘⌥C / ⌘⌥V (copiar y pegar el estilo).
- ⇧H / ⇧V (voltear), ⌘] / ⌘[ y ⇧⌘] / ⇧⌘[ (orden).
- ⌥S (imán) y V (plumas).
- Espacio + arrastrar.
- Marcas: hay que elegir otra tecla que no sea ⌘M, y ⌘1…9 para ir a ellas.
- ⇧⌘N (hojita), F5 (presentar), ⌥R (solo mirar), y las del anotador de pantalla.

Ya están: ⌘Z / ⇧⌘Z, ⌘A, ⌫, ⎋, ⌘V de imagen, ⌘ + rueda, 1 / 2 / 3, ⇧⌘E (exportar), ⇧⌘C (copiar como PNG), ⌘P, ⇧⌘S y ⌃⌘F (pantalla completa, que se recuerda).

### 2.6 Lectores (PDF, Word, PPTX, visor)

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Moverse, Ctrl+C | — | nativo de PDFView | completo |
| Ctrl+rueda, + / −, Ctrl+0 | Zoom | pellizco, ⌘+ / ⌘− | parcial |
| Ctrl+[ / Ctrl+] | Espacio para anotar | ⌘[ / ⌘] | completo |
| A, y dentro P R E 1–5 | Anotar | A, P H E | parcial (letras y colores distintos) |
| Ctrl+Z / Ctrl+Y | Deshacer y rehacer la tinta | ⌘Z / ⇧⌘Z | completo |
| Ctrl+S | Guardar | se guarda solo | no aplica |
| M · Ctrl+1…9 | Marcador · ir a él | M · ⌘1…9 | parcial · falta |
| G D N L I | Ajustes, avance solo, negativo, escuchar, índice | igual | falta |
| + / −, T, B (visor) | Letra | igual | falta |
| F11 | Pantalla completa | ⌃⌘F / F11 | completo |
| Esc en cascada | — | ⎋ | parcial |
| Ctrl+F, F3 / Mayús+F3 | Buscar | ⌘F, ⌘G / ⇧⌘G | falta |
| F2 | Renombrar | F2 o ↩ | falta |
| Ctrl+Mayús+S · Ctrl+P · F5 | Compartir · imprimir · presentar | ⇧⌘S · ⌘P · F5 o ⌘↩ | falta |

### 2.7 Notas (Markdown)

| Windows | Mac | Estado |
|---|---|---|
| Ctrl+B / I, Ctrl+Mayús+X, Ctrl+E / K | ⌘B / I, ⇧⌘X, ⌘E / K | falta |
| Ctrl+M (fórmula), Ctrl+Alt+M (comentario) | Otra tecla: ⌘M y ⌘⌥M chocan con macOS | falta |
| Ctrl+1/2/3, Ctrl+Mayús+8/7/9, Ctrl+Intro, Ctrl+Mayús+. / C / T / D | ⌘1/2/3, ⇧⌘8/7/9, ⌘↩, ⇧⌘. / C / T / D | falta |
| Ctrl+V de fotos | ⌘V | parcial (solo texto) |
| Ctrl+S / Ctrl+Mayús+S | se guarda solo / ⇧⌘S | parcial |
| Ctrl+W, F11, Ctrl+Z / Y, menú contextual | nativos | completo |
| Intro sigue la lista o la tabla | ↩ | parcial (sin tablas) |
| Ctrl + / − / 0, Ctrl+clic en un enlace, comentarios, título | ⌘ + / − / 0, ⌘-clic | falta |

### 2.8 Otras ventanas

| Ventana (Windows) | Atajos Windows | Mac | Estado |
|---|---|---|---|
| Buscar en PixPin | ↑↓, RePág/AvPág, Tab (pestañas), →, Intro, Ctrl+Intro, Alt+Intro, Supr, Ctrl+C/V/Z, Esc | ↑↓ nativo | parcial |
| Tareas | Ctrl+F, Ctrl+L, Ctrl+T, F2, Supr, Tab, Espacio, Intro, Ctrl+Z, Ctrl+V, Esc | ↩, ⌘R | parcial |
| Timeline | Ctrl+1…4, Ctrl+F, Ctrl+M (en Mac, otra tecla), Ctrl+Z, Intro, Ctrl+V, ↑ corrige | ⌘R | parcial |
| Lecciones (ficha) | Esc guarda, Ctrl+Intro, Ctrl+E, Tab | ⌘S | parcial |
| Galería | flechas, Espacio, Intro, Supr, Ctrl+C/S/A/Z, Esc, escribir busca | ⌘Y, ⌘Z, ⌫ | parcial |
| Hoja de cálculo (editar) | Ctrl+N/B, Ctrl+K/I, Ctrl+S/U, Ctrl+5, Ctrl+Mayús+L/E/R, F2, Ctrl+Z/Y/C/X/V | ⌘B/I/U, ⌫ (⌘N, ⌘K y ⌘S no: son de macOS) | parcial |
| Visor de hoja | Ctrl+flechas, Ctrl+Intro, Ctrl+RePág/AvPág, Ctrl+Inicio/Fin, zoom, F11 | flechas, ⇥ | parcial |
| Plano CAD | Esc, Supr, Ctrl+P, Ctrl+E, I, A, L, F, B, M, T, 3, +/−, flechas | ⎋, ↩, ⌫, F, M, +/−, ⌘P | parcial |
| Modelo 3D | F, B, C, I, L, A, P, T, 1–9, +/−, flechas | ⎋, flechas, F, +/− | parcial |
| Diapositivas y presentar | → ↓ AvPág Intro Espacio / ← ↑ RePág Retroceso P, Inicio/Fin, B o «.», N, T, J L R E M, Esc | — | falta |
| Telepronter | Esc, Espacio, Intro, ←→, ↑↓, + / −, RePág/AvPág | — | falta |
| Pronunciar | Espacio mantenido, R, Ctrl+G, ←→, + / −, Esc | — | falta |
| Conversación | Intro, 1–9, 0, Tab, Esc | — | falta |
| Editor de la grabación | Espacio, ←→, Intro, Esc | — | falta |
| Salida | Esc, Ctrl+C, Intro, ↑↓ | — | falta |
| Llamada secreta | Intro contesta, Esc cuelga | — | falta |
| Ajustes | Ctrl+Z; al grabar un atajo, Supr lo quita | ⎋ | parcial |

---

## 3. Compatibilidad de la sincronización

**El cable es idéntico.** `nucleo/pixpin-sincro` es igual byte a byte que `crates/pixpin-sincro`:
- Protocolo 4 estricto, puerto 47474.
- Servicios `_pixpin._tcp`, `_pixpinenvio._tcp`, `_pixpinrecibe._tcp` y `_pixpinchat._tcp`.
- Prefijos `PXS1`, `PXC1` y `PXI1`; PBKDF2 y AES-256-GCM.
- Personas con P-256 en `sincro/persona.json`.

Android espera lo mismo (`Protocolo.kt`: VERSION 4). Todo lo que viaja se transporta y se fusiona igual. Los huecos están en la capa de la app y en los datos que llegan pero el Mac no usa.

### 3.1 Datos y comportamiento

| Qué sincroniza Windows | Mac lee | Mac escribe | Estado | Archivo(s) Mac / nota |
|---|---|---|---|---|
| NOTA, IMAGEN, ARCHIVO, VOZ, DIBUJO, TABLA, MINIAPP (tabla, contador, relojes…) | sí | sí | completo | N/chats.rs, adjuntos.rs, voz.rs, editor.rs, hojas.rs, miniapps.rs |
| Borrado de mensajes (`sincro/borrados.jsonl`) | sí | sí | completo | N/chats.rs |
| Galería (`galeria`, `galeriajunta`, `damecaptura`, `poncaptura`) | sí | sí | completo | N/galeria_sincro.rs |
| Anotado `anot-<uid>`: tinta, `.hoja`, `.marcas`, `.espacios`, `.maqueta`, `.voz`, `.sitio` | sí | sí | completo | N/documentos.rs (falta la pasada `marco_de_la_tinta::tras_sincronizar`) |
| `anot-<uid>.comentarios.json` (comentarios de notas) | no | no | falta | Android también los espera |
| `anot-<uid>.asistente.json` | no | no | falta | Se conserva |
| `<dibujo>.marcas` (marcadores del lienzo) | no | no | falta | Es cosa del agente del lienzo |
| `recuerdaEn` (recordatorio en un mensaje) y la llamada secreta | sí (B2) | sí (B2) | parcial | N/chats.rs (`CambioMensaje::Recordar`; quitarla borra la clave). El aviso del sistema se pone al ponerla desde este Mac; el vigía que los vuelve a poner al arrancar y tras sincronizar es A4; la llamada secreta, E5 |
| MINIAPP tareas con `⏰ AAAA-MM-DD HH:MM` | parcial | no | parcial | N/tareas.rs |
| PAGINA, PROYECTO | etiqueta genérica | no | parcial | K/Vistas.swift |
| CROQUIS (`croquis3d/*.croquis.gz`) | no | no | falta | — |
| Lecciones (`.leccion`, fotos `respondeA: lec-<id>`) | sí | sí | parcial | Las fotos de la lección no se ven |
| Lápidas de proyecto (`LapidaDeChat`, `borrarchat`) | sí (preguntando) | sí | completo | N/sincro.rs `sincronizar_preguntando`, `borrar_proyecto`; sin preguntar no se borra nada, como Windows |
| `auto-automatizaciones`, `auto-figuras` | no | no | falta | Se conservan |
| `auto-letra-*` (letras SHX) | sí | no | parcial | nucleo/pixpin-cad |
| `sincro/direcciones.txt` | no | no | falta | Solo Bonjour |
| `sincro/elegidos/<id>` | sí | sí | completo | crate |
| `copias/` | el crate las hace | — | parcial | No hay pantalla para restaurar |
| Ajustes `[sincro]` presencia, automatica, lo_mio_manda | sí | automatica y presencia | parcial | Se respetan los tres; «Lo mío manda» se elige en «¿Qué sincronizar?», pero el valor por defecto no sale en Ajustes (C3) |
| Vuelta automática: al aparecer, 30 s de calma, periodo de 10 min | sí | — | completo | N/sincro_auto.rs (`RelojSincro`), Sincronizador.swift |
| Tareas al instante (`solo_estos`, 600 ms) | sí | — | completo | `Nucleo::sincronizar_tareas`; avisa K/Tareas/Tareas.swift (`pixpinTareasCambiadas`) |
| «Con todos» en 2 rondas | 2 rondas con 3 o más aparatos | — | completo | `rondas_con_todos`, Sincronizador.swift `conTodos` |
| Qué cuenta como «trajo algo» | `trajo`: traídos, fusionados, archivos o borrados | — | completo | `ResumenSincro.trajo` |
| `avisos_de_lo_hecho` | sí | — | completo | Van en `ResumenSincro.avisos` |
| Renombrar el aparato, salir del grupo | no | no | falta | — |
| Envío por código: archivo, proyecto, lienzo | solo archivo | solo archivo | parcial | N/envio.rs |
| `suelto` / «Enviar a» | sí | sí | parcial | Nunca va al lienzo (`FrenteMac::Lienzo`) |
| Chats compartidos con personas | sí | sí | completo | N/compartidos.rs |
| Timeline | — | — | no aplica | No viaja ni en Windows |
| Pedidos (WM_COPYDATA, `pixpinmax://`, CLI, MCP) | — | — | falta | Es local, no sincroniza; en Mac haría falta un esquema de URL |

### 3.2 Crates de `nucleo/` frente a `crates/` (diff fichero a fichero)

«Adaptación» quiere decir que el cambio es para el Mac (`cfg(windows)`, `pixpin_sistema` en lugar de `pixpin_shell`, clippy). **«Mac detrás»** quiere decir que Windows ha seguido avanzando y el Mac no lo tiene.

| Crate | Ficheros distintos | Veredicto |
|---|---|---|
| pdfsqueeze-core, pixpin-geom, pixpin-hojas, pixpin-lecciones, pixpin-model, pixpin-nivel, pixpin-office, **pixpin-sincro**, pixpin-timeline, pixpin-tinta, pixpin-ui | 0 | iguales |
| pixpin-bim | `civil.rs`, `examples/ver3d.rs` | adaptación (clippy) |
| pixpin-cad | 19 cambiados, y `enganche.rs` y `orbita.rs` nuevos | adaptación: `ventana`, `gpu3d` y `texto` tras `cfg(windows)`; la órbita sale de `ventana3d`; búferes `#[repr(C)]` para Metal; `letras.rs` por hilo |
| pixpin-codec | `imagen.rs`, `vista.rs`, `wic.rs`, `portapapeles*.rs`, `lib.rs`, `Cargo.toml`; `portapapeles/fuera_de_windows.rs` nuevo | adaptación |
| pixpin-docs | `lib.rs`; `formulas.rs` nuevo | Mac por delante (se sacó de `pixpin-notas`); llevarlo a Windows |
| pixpin-proyecto | `almacen.rs` (NFC), `ubicacion.rs`, `formula*.rs`, `mini.rs` (comentarios), `Cargo.toml` | adaptación. **El NFC de `almacen::nombre_seguro` es un arreglo que Windows también necesita** |
| pixpin-store | `ajustes.rs`, `comandos.rs`, `idioma.rs`, `regiones.rs` | adaptación (`pixpin_sistema`) |
| pixpin-store | comentario de `ajustes.rs` | `estado.rs` ya igual (16-oct) |
| pixpin-pdf | `lib.rs`, `aligerar.rs`, `png.rs`, `union.rs`, `Cargo.toml` | adaptación (`cfg(windows)`) |
| pixpin-pdf | `escribir.rs` (291 líneas solo en Windows), `letra.rs` (289), ejemplos y pruebas | **Mac detrás**: varias letras incrustadas por página y letras de reserva (θ, ≤, emoji) |
| pixpin-motor2d | `tests/asignaciones.rs` | Igual que Windows (16-oct). Solo la prueba de asignaciones cuenta por hilo en el Mac (`cargo test` en paralelo) |
| pixpin-ia | Faltan `anotacion`, `calculo`, `complejidad`, `edicion`, `fisica`, `hoja`, `ojos`, `pizarra`, `problema` y `rotulos`. Muy por detrás: `agente.rs` (324), `acciones.rs` (264), `rapido.rs` (245), `calcar.rs` (488), `lienzo.rs`, `seleccion.rs`, `funciones.rs`, `herramientas.rs`, `ecuacion.rs`, `nube/mod.rs`, `acciones_documentos.rs` | **Mac muy detrás**. Adaptación solo en `nube/claves.rs`, `nube/http.rs`, `servidor.rs`, `descarga.rs` y `puente.rs` (nuevo) |
| por-adaptar/pixpin-voz | `Cargo.toml` | adaptación |
| por-adaptar/pixpin-pila, pixpin-aligerar | 0 | iguales |
| por-adaptar/pixpin-lanzador | `asistente`, `consulta`, `lecciones`, `pruebas`, `resultados`, `rpc` | Mac detrás |
| por-traducir/pixpin (la app de referencia) | 54 entradas | **La copia de referencia está vieja**. Le faltan, por ejemplo, `notificaciones.rs`, `orden.rs`, `recibir_de_windows.rs`, `asistente/{ojos,externa,en_el_chat,hoja_a_lienzo,anotar_inteligente}`, `automatizaciones/cola.rs`, `ventana_editor/modo_ventana.rs` y `visor_hoja/capa.rs`. Al traducir, leer siempre `ref/PIXPIN_PRO_WINDOWS` |
| por-traducir/pixpin-shell | 16 (faltan `atajo`, `orden`, `notificacion`, `juntar`, `union`, `impresora`, `compartido`, `consola`) | Una parte se movió a `nucleo/pixpin-sistema` (`atajo`, `union`, `entorno`); lo demás, Mac detrás |
| por-traducir/pixpin-notas | `lib.rs`; falta `formulas.rs` | se movió a pixpin-docs |
| por-traducir/pixpin-render | `superficie.rs` | sin importancia (solo referencia) |

---

## 4. Plan de trabajo por tandas

Cómo está hecho:
- Cada tanda es para **un agente, de 1 a 3 horas**.
- Van ordenadas por valor: primero el uso diario y la sincronización.
- Las tandas de un mismo grupo se pueden hacer **a la vez**: no tocan los mismos ficheros.

Hay tres ficheros compartidos:
- `N/lib.rs`: solo se le añade una línea `mod …`; la fusión es trivial.
- `APP` (PixPinApp.swift): solo se le añade una entrada de menú.
- `K/Ajustes/VistaAjustes.swift`: solo se le añade una línea para la sección nueva.

Si dos tandas del mismo grupo tocan otro fichero a la vez, se dice en la tabla.

**Fuera del plan**, porque ya lo llevan dos agentes:
- (a) El estilo de las ventanas sin marco.
- (b) Las herramientas del lienzo (`K/Lienzo/*`, `N/editor*.rs`).

Las tandas que dependen de ellos lo marcan como **dep. lienzo** o **dep. ventanas**.

### Grupo A: sincronización y datos (primero)

| # | Tanda | Ficheros |
|---|---|---|
| A1 ✅ | **«¿Qué sincronizar?» y lápidas de proyecto**: `Alcance::Preguntar`, elegir chats, aplicar o rechazar borrados, «Lo mío manda»; `fusionados` y `avisos_de_lo_hecho` en `ResumenSincro` | N/sincro.rs, K/Sincro/VistaSincro.swift, nuevo K/Sincro/ElegirSincro.swift |
| A2 ✅ | **Sincronización automática como Windows**: periodo de 10 min, tareas al instante (`vuelta::solo_estos`), 2 rondas con 3 o más aparatos, aviso tras 3 fallos, respetar `presencia=false` | K/Sincro/Sincronizador.swift, K/Sincro/Anunciador.swift, nuevo N/sincro_auto.rs (+ `N/lib.rs`) |
| A3 | **Aparatos**: `sincro/direcciones.txt` (recordar y probar antes que Bonjour), renombrar este aparato, salir del grupo, miembros con «hace X» | nuevo N/aparatos.rs, K/Sincro/BuscarPuerta.swift, K/Sincro/Vecinos.swift, nuevo K/Sincro/VistaAparatos.swift (se enlaza desde VistaSincro **después de A1**) |
| A4 ✅ | **Recordatorios**: `recuerdaEn` en el mensaje, el vigía (reprogramar al arrancar y tras sincronizar), notificaciones con «Hecha», «+10 min» y «Abrir»; el `⏰` de las tareas en el núcleo | nuevo N/recordatorios.rs, nuevo K/Recordatorios/{Vigia,Avisos}.swift, N/tareas.rs (solo parsear `⏰`) |
| A5 | **Copias**: listar y restaurar `copias/`, recuperar proyectos borrados | nuevo N/copias.rs, nuevo K/Sincro/VistaCopias.swift |
| A6 | **Envío por código completo**: mandar proyectos y lienzos, poner el lienzo suelto en su proyecto, «actualizar o crear», reconocer un archivo que vuelve | N/envio.rs, K/Sincro/EnvioPorCodigo.swift |
| A7 | **Poner el núcleo al día con Windows (sin el lienzo)**: copiar `pixpin-ia` (los 10 módulos que faltan, sin tocar la parte de `cfg`), `pixpin-pdf` `escribir.rs` y `letra.rs`, `pixpin-store/estado.rs`, `pixpin-lanzador`; pasar `cargo test --workspace`. Avisar a Windows del NFC y de `formulas.rs` | nucleo/pixpin-ia/**, nucleo/pixpin-pdf/src/{escribir,letra}.rs, nucleo/pixpin-store/src/estado.rs, por-adaptar/pixpin-lanzador/** |
| A7b | ~~`pixpin-motor2d` al día~~ **hecho** (16-oct) | nucleo/pixpin-motor2d/** |

### Grupo B: uso diario

| # | Tanda | Ficheros |
|---|---|---|
| B1 ✅ | **Pines persistentes y sus teclas**: guardar y restaurar al arrancar, «restaurar el último», «cerrar todos» en el menú; 1–3, 5–8, 0, N, R/⇧R, H/V, flechas que mueven, ⌘T clic a través, T y ⇧C del OCR | K/Pines/GestorPines.swift, K/Pines/Pin.swift, K/Pines/BarraPin.swift, nuevo K/Pines/AlmacenPines.swift, APP (menú) |
| B2 | ✅ **Menú del mensaje** (hecho): etiquetas, Responder, Copiar, Pinear, Describir, Reenviar, Compartir, Fijar, Renombrar, Hacer lección, Recordar, Abrir con, Guardar esto, Ver comentarios; letras R, ⌘C, P, E, N, T, F, L, F2. Queda Anotar encima (dep. lienzo), Exportar/Imprimir un lienzo (D1), Unir PDF, Letra | K/Chat/MenuMensaje.swift, K/Chat/BorrarMensajes.swift, N/chats.rs (`cambiar_mensaje`, `reenviar_mensajes`), N/lecciones.rs (`leccion_de_mensaje`) |
| B3 | **Caja del chat y la hoja «+»**: ⇧↩ para el salto de línea, Esc limpia, hoja «+» con todas las entradas, buscar dentro del chat (⌘F), escala ⌘+ / − / 0 | K/Vistas.swift, nuevo K/Chat/HojaAdjuntar.swift, nuevo K/Chat/BuscarEnChat.swift (**no a la vez que B2 si B2 tiene que tocar Vistas.swift**: B2 solo engancha su menú con una línea) |
| B4 | **Tareas editables**: buscar, «Mover a…», borrar con deshacer, F2 para editar, pegar imágenes, ver y poner `⏰`, teclado | K/Tareas/Tareas.swift, N/tareas.rs (**después de A4** o junto a él en `⏰`) |
| B5 | **Timeline editable**: apuntar texto, foto y voz; pestañas ⌘1…4; ↑ corrige el último; buscar | K/Timeline/Timeline.swift, N/timeline.rs |
| B6 | **Galería completa**: buscador (también OCR con Vision), grupos por día, teclado, «Guardar como», panel de detalle | K/Galeria/Galeria.swift, K/Galeria/Comun.swift, N/galeria.rs |
| B7 | **Lectores, parte 1**: buscar (⌘F, ⌘G / ⇧⌘G), ⌘1…9 para ir al marcador, N negativo, D avance solo, ⌘P imprimir, F2 renombrar, `al_dia` (recargar la tinta) | K/Documentos/LectorDocumento.swift, nuevo K/Documentos/BuscadorLector.swift, N/documentos.rs |
| B8 | **Captura que falta**: ⌘A, flechas y Espacio, ⇧ HEX/RGB, ⇧⌘S, ⌫ de la anotación, captura con retardo (cuenta atrás), cuentagotas suelto, ↩ y Esc del GIF | K/Captura/Capturador.swift, K/Captura/VistaCaptura.swift, K/Captura/AnotacionCaptura.swift, K/Captura/GrabadorGif.swift, nuevo K/Captura/CuentaAtras.swift |
| B9 | **Datos que llegan y no se ven**: foto anotada del móvil en la burbuja, croquis 3D, fotos de las lecciones, punto de proyecto, PAGINA y PROYECTO con su burbuja | K/Chat/Adjuntos.swift, N/modelos3d.rs, K/Lecciones/VistaLecciones.swift (usa `PintorLienzo.swift` sin cambiarlo) |

### Grupo C: atajos, integración y ajustes

| # | Tanda | Ficheros |
|---|---|---|
| C1 | ✅ **Atajos globales configurables**: el catálogo de `pixpin-store/comandos.rs` entero, regiones, silenciar atajos, programas ignorados; sección «Atajos» con ⌫ para quitar uno. Hecho (faltan clic a través y restaurar el último pin: los ata el agente de pines con `GestorAtajos.poner`) | K/Captura/AtajoGlobal.swift, K/Ajustes/AtajoDeCaptura.swift, nuevo K/Ajustes/SeccionAtajos.swift, APP |
| C2 | **Integración con macOS**: esquema `pixpinmax://` con los verbos de `docs/integraciones.md` y la firma, más App Intents (tarea, lienzo, grabar, abrir proyecto, al móvil), menú del Dock, imágenes en `CFBundleDocumentTypes`, Servicios del Finder | nuevo K/Pedidos/{Enlaces,Verbos}.swift, XC/App/Intenciones.swift, XC/project.yml, app/Recursos/Info.plist (**APP: después de C1**) |
| C3 | **Ajustes que faltan**: idioma, Captura (retardo, color, carpeta, GIF y scroll), Voz, pantalla de claves del asistente, Sincro (presencia, «Lo mío manda»), buscador y restablecer | K/Ajustes/VistaAjustes.swift, K/Ajustes/ModeloAjustes.swift, N/ajustes.rs |
| C4 ✅ | **Notificaciones comunes**: categorías y acciones (`UNNotificationAction`), aviso «se van en 24 h» de la caducidad; que AvisosMini las use | nuevo K/Avisos/CentroAvisos.swift, K/Pines/AvisosMini.swift, K/Caducidad/BarrenderoCapturas.swift (**coordinar con A4**: A4 usa CentroAvisos si ya existe) |

### Grupo D: documentos, compartir y voz

| # | Tanda | Ficheros |
|---|---|---|
| D1 | **Compartir y exportar común**: hoja (PDF, PNG, JPG, SVG, HTML) con `NSSharingServicePicker`, ventanita «Salida», «Abrir con…»; engancharla al pin, al lector y al chat (el lienzo, **dep. lienzo**) | nuevo K/Compartir/{HojaCompartir,Salida,AbrirCon}.swift, N/compartir.rs (si hace falta `pixpin-pdf`) |
| D2 | **Leer en voz**: `AVSpeechSynthesizer`, resaltar por dónde va, `MPRemoteCommandCenter`, L en el lector | nuevo K/Voz/LeerEnVoz.swift, K/Documentos/LectorDocumento.swift (solo la tecla L, **después de B7**) |
| D3 | **Audio**: reproductor global (velocidad, ±saltos, barra de lo que suena), biblioteca de audio, micrófono flotante con hora | K/Voz/ReproductorVoz.swift, K/Voz/VistasVoz.swift, nuevo K/Voz/BibliotecaAudio.swift |
| D4 | **Notas Markdown**: atajos de formato, fotos en la nota, comentarios (`.comentarios.json`, viajan) | K/Documentos/EditorNota.swift, N/notas.rs |
| D5 | **Hojas**: editar un `.xlsx` como libro con pestañas, todas las hojas del móvil, los atajos de Windows (sin ⌘N, ⌘K ni ⌘S) | K/Documentos/HojaCalculo.swift, N/hojas.rs, N/hojas/libro.rs |
| D6 | **Asistente, parte 1**: nube con URLSession, bajar el modelo y su catálogo para Mac, que no quede `llama-server` huérfano | K/Asistente/*, N/asistente.rs (**después de A7**) |
| D7 | **Grabación**: marco movible en dos fases, editor para revisar (bucle, recortar, guardar o descartar) | K/Grabar/*, nuevo K/Grabar/EditorGrabacion.swift |
| D8 | **Buscar en todo completo**: pestañas, recientes, lecciones y capturas, acciones por fila y su teclado | K/Buscar/Buscar.swift, N/buscar.rs |
| D9 | **Presentar un PPTX y el visor HTML**: diapositivas a pantalla completa (notas, negro), `.html` en `WKWebView` | nuevo K/Documentos/{Diapositivas,VisorHtml}.swift (**dep. ventanas**) |

### Grupo E: después (menos uso o dependen de otros)

| # | Tanda | Ficheros |
|---|---|---|
| E1 | Asistente, parte 2: en el chat, recetas, permisos, «ojos», hoja→lienzo (**después de A7 y D6; dep. lienzo**) | K/Asistente/*, K/Vistas.swift |
| E2 | Planos: anotar a mano (**dep. lienzo**), exportar, buscar textos, caché `.pxcad`, vistas 3D guardadas | K/Planos/*, N/planos.rs, N/modelos3d.rs (**no a la vez que B9** en modelos3d.rs) |
| E3 | Anotar la pantalla (vivo, varios monitores) y anotador al chat (**dep. lienzo**) | K/Captura/Capturador.swift (**después de B8**), nuevo K/Captura/AnotadorPantalla.swift |
| E4 | Centro de la barra de menús (panel rico) y grupos de ventanas (**dep. ventanas**) | APP, nuevo K/Bandeja/* |
| E5 | Telepronter, Pronunciar, conversación por turnos y llamada secreta (**después de A4**) | nuevo K/VozVentanas/* |
| E6 | Automatizaciones (`auto-automatizaciones`) | nuevo N/automatizaciones.rs, nuevo K/Automatizaciones/* |
| E7 | Visor reflujado de Word y EPUB con su tinta (`.maqueta`) | nuevo K/Documentos/VisorReflujo.swift, N/documentos.rs (**después de B7**) |
| E8 | MCP y extensión del navegador para Mac | nuevo `apple/herramientas/` o un binario aparte |
| E9 | Lo que lleva el agente del lienzo (aquí solo consta): exportar, marcas, presentar, hojita, figuras, zona al chat, salto por enlace, fondo del lienzo, letras de herramienta, F11 | K/Lienzo/*, N/editor*.rs |

Tandas que se pueden hacer **a la vez desde ya**: A1, A2, A4, A5, A6, A7, B1, B2, B5, B6, B7, B8, C1, C3, D3, D4, D5, D7 y D8.

Las demás esperan a la tanda que dice su nota:
- A3 espera a A1.
- B3 espera a B2.
- B4 espera a A4.
- C2 espera a C1.
- C4 se coordina con A4.
- D2 espera a B7.
- D6 espera a A7.
