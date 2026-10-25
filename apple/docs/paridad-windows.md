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
| completo | 47 |
| parcial | 55 |
| falta | 54 |
| no aplica | 6 |
| interno | 7 |

**Los 10 huecos que más pesan**, de más a menos valor para el uso diario y la sincronización:

1. ~~**«¿Qué sincronizar?» y las lápidas de proyecto.**~~ Hecho (A1).
2. ~~**Recordatorios.**~~ Hecho (A4): `recuerdaEn` en los mensajes y `⏰` en las tareas suenan con el vigía (al arrancar, tras sincronizar y al cambiar algo aquí), con «Hecha», «+10 min» y «Abrir» (C4).
   - La llamada secreta, hecha (E5).
3. ~~**Sincronización automática incompleta.**~~ Hecho (A2): periodo de 10 min, tareas al instante, dos rondas, aviso al tercer fallo, `presencia=false` y `fusionados`.
   - Hecho también `direcciones.txt` (A3).
4. ~~**Los pines no se guardan ni se restauran** entre arranques.~~ Hecho (B1): el mismo `almacen/indice.json` que Windows, filtros, giros, negativo, modo texto, tamaños 1–3, flechas y ⌘T.
   - Quedan las marcas de texto guardadas (resaltar, subrayar) y su ⌘Z.
5. **El menú del mensaje del chat** ya es el de Windows (B2): etiquetas, responder, copiar, pinear, describir, reenviar, compartir, recordar, hacer lección, renombrar, fijar, abrir con, guardar del buzón y ver comentarios, con sus letras. Exportar e imprimir un lienzo ya van por la hoja común (D1). Faltan anotar encima de una foto, unir PDF y la letra de una voz. La caja de escribir ya es la isla de Windows, con su hoja del clip, la lupa (⌘F) y la escala (⌘+ / ⌘− / ⌘0) (B3).
6. **Tareas casi de solo lectura.**
   - Tareas: falta buscar, mover, editar, y borrar con deshacer.
   - ~~Timeline: no se puede apuntar nada.~~ Hecho (B5).
7. ~~**Compartir y exportar común**~~ Hecho (D1): la hoja de Windows (HTML, PDF, PNG, JPG, SVG, original, editable, `.pixpin`, texto) para mensajes, lo elegido, proyectos y pines, la ventanita «Salida» y «Abrir con…».
   - Quedan el PDF anotado y la web de un documento que se lee, Word, enlace y wifi.
8. ~~**Lectores sin búsqueda.**~~ Hecho (B7): buscar (⌘F, ⌘G / ⇧⌘G, F3), ⌘1…9 y el riel de marcadores, M con su cifra, N negativo, luna/sol oscuro, D avance solo, G ajustes, F2 renombrar, ⌘P, ⇧⌘S, F5 presentar y la tinta al día con el disco (`al_dia`).
   - ~~Falta escuchar en voz alta.~~ Hecho (D2): L, resaltar el trozo y la palabra, el 🟢 que se mueve, velocidad, voces del Mac y las teclas multimedia.
9. **Atajos globales configurables.** Hecho (C1): los 27 comandos del catálogo, regiones, silenciar y apps ignoradas, en Ajustes → Atajos. «Dejar pasar el clic» y «restaurar el último pin», hechos con B1. El esquema `pixpinmax://`, los pedidos y el menú del Dock, hechos en C2.
10. ~~**El núcleo `pixpin-ia` del Mac va muy por detrás de Windows**.~~ Hecho (A7, 16-oct): `pixpin-ia`, `pixpin-pdf` (letras), `pixpin-store` y `pixpin-motor2d` ya son los de Windows. La parte 1 del asistente en Swift, hecha (D6, 16-oct): usa `[asistente]`, la nube por URLSession, el modelo local bajado y el bucle, las herramientas y las acciones de Windows. La parte 2, en buena parte (E1, 16-oct): el asistente en el chat «Asistente» (y con `@asistente`), sus respuestas en el cuaderno que viajan, recetas, «ojos», editar el lienzo y figuras guardadas. Queda lo de documentos y del chat (ver la tabla).

---

## 1. Matriz de funciones

### 1.1 Módulos de `apps/pixpin/src` (a–l)

| Módulo Windows | Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|---|
| abrir_con | «Abrir con…» (elegir app) en pines, chat, buscador | completo | K/Compartir/AbrirCon.swift | D1: las apps del formato (la predeterminada primero, con su icono) y «Otra app…»; si falta el archivo lo dice con su nombre. En el chat, el pin y la Salida |
| abrir_hoja | Abrir una hoja de proyecto por referencia, sin el chat | parcial | K/Almacen.swift, K/Pedidos/HacerPedidos.swift | Desde fuera ya abre (`pixpinmax://abrir?tipo=hoja&referencia=…`, C2); faltan los grupos |
| abrir_imagen | Doble clic en una imagen → pin rápido | completo | K/Pines/GestorPines.swift, K/Pedidos/DelegadoApp.swift | C2: imágenes, vídeos y audios en `CFBundleDocumentTypes` (`public.image`, `public.movie`, `public.audio`, «Alternate»): «Abrir con» y soltarlos en el icono del Dock dan un pin (o el reproductor flotante, un audio), como las asociaciones de Windows |
| al_frente | Qué chat o lienzo está delante para recibir «Enviar a» | parcial | K/Sincro/EnviarA.swift, N/envio.rs | El lienzo nunca se apunta como frente (`FrenteMac::Lienzo`) |
| aligerar | Comprimir los PDF que entran (pdfsqueeze) | completo | K/Documentos/AligerarPdf.swift, N/aligerar.rs | — |
| anotado_del_adjunto | Tinta, marcas y espacios `anot-<uid>…` de los lectores | parcial | N/documentos.rs, K/Documentos/LectorDocumento.swift | Word y EPUB reflujados (`.maqueta`) |
| anotador_al_chat | Lo anotado en la pantalla va al chat con su lienzo editable | completo | K/Captura/AnotadorPantalla.swift, N/anotador_al_chat.rs | Hecho (E3): al salir con tinta nueva (o con «Guardar» de la pastilla) la foto de debajo entra en «Mensajes guardados» como IMAGEN con su lienzo `foto-<id>` (foto bloqueada, tinta editable); lo dibujado después pone al día EL MISMO lienzo; solo las pantallas donde se dibujó, a su tamaño. Falta: las imágenes pegadas no entran en la foto (`componer` de Windows) |
| asistente (chat, motor, nube, descarga, turno) | IA local o en la nube | parcial | K/Asistente/*, N/asistente.rs, N/asistente/{turno,transporte,local}.rs, N/llavero.rs | Hecho (D6): el motor de `[asistente]` (Claude Haiku 5.5 o DeepSeek V4.1 Flash por URLSession con respaldo local; el modelo bajado; Apple Intelligence; el `llama-server` del usuario), el turno de Windows (`agente::turno_con`: pensar en automático, plan, hoja de trabajo, reinicio al 70 %, camino rápido, todas las herramientas que el Mac sabe hacer), bajar el motor de llama.cpp para macOS (b11580, Metal) y los GGUF con su huella, un `llama-server` por proceso que se cierra a los 5 min, al salir y el huérfano de una PixPin que murió (`llama-server.pid`). La ventana: conversaciones guardadas (`<datos>/asistente/`, no viajan), adjuntos (clip, arrastrar, pegar), lo pensado plegable, abrir lo dibujado en el lienzo. Hecho (E1): **en el chat** — el chat fijo «Asistente» (detrás de «Mensajes guardados») y `@asistente` en cualquier otro; la respuesta es una nota del cuaderno con `aparato = "IA"` (`#48·IA`) que nace al enviar, crece en vivo (en el disco cada 2 s) y viaja como cualquier otra; en otro chat cuelga de la pregunta; una foto sola en su chat se contesta. Con Apple Intelligence la respuesta se escribe al acabar (N/asistente/{chat,en_la_conversacion}.rs, K/Asistente/AsistenteEnElChat.swift). La ventana del asistente sigue con sus conversaciones locales |
| asistente (recetas, pensado, permiso) | Recetas, lo pensado, permisos Sí/No | parcial | K/Asistente/{ModeloAsistente,ManosDelAsistente,VistaAsistente}.swift, N/asistente/turno.rs | Hecho (D6): lo pensado (plegable, «Pensó N s») y la hoja de trabajo por conversación; lo que borra o sale del Mac pregunta en la burbuja con «Sí»/«No» (parar o 10 min es un no). Hecho (E1): en el chat, lo pensado, la petición mejorada y «Contexto renovado» se guardan con su nota (`anot-<código>.asistente.json`, viajan con ella) y la hoja pasa al turno siguiente (el reinicio apunta desde qué nota sigue); la pregunta contestada queda escrita (`❓ … → ✅ Sí`); **recetas**: automatizaciones `a_mano` con `boton: true` del chat «Asistente», botones encima de la caja, «Guardar como receta» en el menú del mensaje, cambiar/icono/mover/borrar (N/asistente/recetas.rs) |
| asistente (ojos, hoja_a_lienzo, anotar_inteligente, al_lienzo, documentos) | El asistente mira el lienzo, pasa una hoja al lienzo, anota documentos | parcial | N/asistente/documentos.rs, K/Asistente/ManosDelAsistente.swift | Hecho (D6): `buscar_en_mis_cosas` (chats, PDF, Office y notas; con la nube pregunta la primera vez y queda en `documentos_a_la_nube`; las citas abren el documento), leer un PDF o una foto adjunta (PDFKit, Vision) y calcar una imagen. Hecho (E1), en una conversación: lo dibujado va al lienzo abierto al frente (centrado, un paso de deshacer, la ventana repinta), al nombrado con `@lienzo:` o al propio del asistente (a la derecha de lo que había), con «Abrir lienzo» (`lienzoIa`) y «…y ábrelo»; **editar el lienzo** (`pixpin_ia::edicion`, con su resumen al empezar); **figuras guardadas** (la biblioteca del lienzo); **«ojos»** (`ver_lienzo`, la vista al empezar con «revisa/corrige» y una revisión con la nube: la zona con rejilla y `#id`, pintada con `PintorLienzo`); lo leído queda en el chat (nota y `.txt`). Falta: hoja→lienzo, anotar documentos (`anotar_inteligente`), las acciones sobre documentos (`documentos_acciones`), las del chat (`leer_en_voz_alta`, `comprimir_pdf`, `transcribir_audio`, `leer_excel`, `resumen_de_actividad`), pegar imágenes con `imagen_en_lienzo` y ver un documento anotado |
| asistente (en_el_chat, externa/MCP) | Asistente dentro de cualquier chat; servidor MCP | falta | K/Asistente (es una ventana aparte) | Asistente en el chat; MCP para Mac |
| audio | Un reproductor para toda la app: barra, saltos, velocidad | completo | K/Voz/ReproductorVoz.swift, VistasVoz.swift, MandosSistema.swift | Hecho (D3): uno solo para todo, las 5 velocidades del móvil (sobreviven a parar), ±10 s, ir a un punto, la fila, «Está sonando» y teclas multimedia; la barra de lo que suena encima de la caja del chat y en la biblioteca; pausa la voz que lee. Falta la pantalla de la letra sincronizada |
| automatizaciones (cola, encargo, motor) | Disparadores con pasos; cola de encargos | parcial | N/automatizaciones.rs, K/Automatizaciones/{MotorAutomatizaciones,VentanaAutomatizaciones,EditorAutomatizacion}.swift | Hecho (E6): el mismo `automatizaciones.json` del chat «Asistente» con su mensaje `auto-automatizaciones` (viaja a los aparatos propios; lo que no se entiende se guarda tal cual), las recetas del asistente, la validación y los bucles, los disparos (al capturar —la carpeta de capturas—, a la hora cada 30 s con recuperar hasta 6 h, al sincronizar, a mano), la guardia de 30 por hora, los pasos encadenados con sus variables (acciones por el camino del asistente, lo que borra pregunta; «pedido al asistente» es un turno sin ventana), el estado que no viaja y el aviso al empezar y al acabar. Además del Mac: el editor y el historial de las últimas vueltas (no viaja). Falta la cola de encargos (`asistente-encargos.json`, `p ia` de Flow) |
| biblioteca_audio | Música y notas de voz de todos los chats | completo | K/Voz/BibliotecaAudio.swift | Hecho (D3): clic derecho en «Mensajes guardados» → «Biblioteca de audio»; todos los chats, música (`estadoDelTexto = letra`, leído del cuaderno) y notas, lo más nuevo arriba, color si tiene letra, apagada si el fichero no está; clic o ↩ suena, ⌥↩ en flotante, «Grabar» con el micrófono flotante |
| biblioteca_figuras | Figuras del lienzo (`figuras.json`, viaja) | parcial | K/Lienzo/FigurasLienzo.swift, N/editor_figuras.rs | Hechos: gráfica, tabla en blanco y pegada, plano/recta/espacio, guardar, estampar y quitar (en el chat «Asistente», con su mensaje `auto-figuras`). Faltan editar una tabla ya dibujada, meter en su celda y las tablas de coordenadas |
| buscador | Ctrl+F en los lectores, «3 de 12», F3 | completo | K/Documentos/BuscadorLector.swift | — (en el visor reflujado, con E7) |
| buscar_todo | «Buscar en PixPin»: pestañas, recientes, acciones | completo | K/Buscar/*, N/buscar.rs, N/buscar/* | Hecho (D8): busca en chats, mensajes y notas, ficheros por nombre y por dentro (PDF con PDFKit; Office, EPUB, HTML, texto en Rust, `cache/textos`), tareas, lecciones, capturas (nombre, fecha, OCR) y timeline; puntos y resaltado del plugin; pestañas con cuenta (+Timeline), mejor resultado y grupos, recientes y abierto hace poco, letras t n l g c u a, vista previa, botones y menú →. Queda: pegar imagen como `[img NN]` (Ctrl+V), «a» abre el Asistente sin el texto y la lección se abre en su ventana sin ir a su ficha (Lecciones es de otro) |
| cabecera | Barra común de Galería, Lecciones, Tareas y Timeline | no aplica | SwiftUI | — (unificar su aspecto) |
| caducidad_capturas | Capturas que se borran solas | completo | K/Caducidad/BarrenderoCapturas.swift, N/galeria.rs | — (el aviso «se van en 24 h», con «Conservar» y «Abrir», hecho en C4) |
| caja_dibujo | Barra de herramientas estilo Excalidraw, la misma en todas partes | parcial | K/Lienzo/* | La del lienzo ya es la de Windows (los diez grupos, figuras, dos filas si no cabe). La captura anota con ella y con el panel de estilo (B8: K/Captura/AnotadorCaptura.swift, BarrasCaptura.swift). Lector y pin siguen con barras propias |
| caja_texto | Caja de texto propia | no aplica | NSTextField | — |
| capa | Anotar sobre la pantalla (viva o congelada, varios monitores) | completo | K/Captura/AnotadorPantalla.swift, GestosAlt.swift | Hecho (E3): el lienzo entero sobre todas las pantallas (un panel por pantalla, un solo editor), viva con papel transparente o congelada sobre la foto; barra y panel de estilo del lienzo; pastilla (clic a través, limpiar con ⌘Z, copiar, guardar, salir); Espacio y ⌘ mantenido (el Ctrl de Windows) dejan pasar el clic; ⌥ + doble clic central abre y alterna; dos entradas en el menú. Falta la lupa viva (Q mira la pantalla en vivo) |
| captura2 | Captura v2: modos, medidas, lupa, «Al chat», anotar | completo | K/Captura/* | Falta verla en verde en la CI |
| centro_bandeja | Panel rico de la bandeja: estado de sincro, buscador, favoritos, últimas capturas | parcial | APP (MenuBarExtra en forma de menú) | El panel entero |
| cielo | Fondo cósmico | falta | — | Es un adorno |
| compartir (ventana, pdf, pdf_anotado, word, web, enlace, exportable) | Hoja de compartir: PDF, PNG, SVG, web, Word, enlace; menú Exportar | parcial | K/Compartir/*, N/compartir.rs, K/Lienzo/SacarLienzo.swift | Hecho (D1): la hoja común con las reglas de Windows (formatos de una página que se esconden, «Qué incluir», el peso de verdad), HTML (la página del móvil, con el `.excalidraw` dentro), PDF, PNG, JPG, SVG, Original(es), Editable, `.pixpin` y Texto; de mensajes (dibujo y cada marco, foto, PDF solo, voz, nota), lo elegido, proyectos, pines y ficheros; salidas Compartir (a la Salida), Más… (la hoja del Mac), Guardar como… y Copiar. Falta: el PDF anotado y la web de un documento que se lee (`pdf_anotado`, `documento_web`), las páginas de un Word o un libro, tablas que calculan, Word de una nota, enlace y wifi, lo pixelado tapado en un dibujo del chat, y engancharla en los lectores (`Documentos/*`: `HojaCompartir.abrir(.documento(url), …)`) |
| conversacion | Grabar una conversación por turnos (teclas 1–9) | completo | K/VozVentanas/Conversacion.swift, N/turnos.rs | Hecho (E5): 2 a 9 personas con nombre, se graba sin parar, 1–9 y 0 (o la ficha), «N turnos»; entra con `turnos` del móvil y se pasa a texto con los nombres (`[0:12] **Pepe:** …`). En el Mac el reconocedor pasa la nota entera y cada trozo va al turno en que empieza (Windows pasa cada turno aparte) |
| croquis3d | Ver los croquis 3D del móvil | completo | K/Chat/BurbujasQueLlegan.swift, K/Planos/VisorModelo3D.swift, N/modelos3d.rs | Hecho (B9): burbuja `CROQUIS` («aún no ha llegado» si falta su `.croquis.gz`), doble clic al visor 3D con sus fotos, su fondo, su tema y su encuadre de fábrica. Solo se ve, como en Windows. Sus vistas guardadas con 1–9 (y en el menú «Vistas») y ⌘E exporta lo que se ve con el `.croquis.gz` como original (E2) |
| cuenta_atras | Captura con retardo | completo | K/Captura/CuentaAtras.swift, K/Captura/AjustesCaptura.swift | — (Esc la para aunque el foco este en otra app; los segundos de `retardo_captura_s`) |
| diapositivas | Presentar un PPTX (orador, notas, negro); PPTX → proyecto | parcial | K/Documentos/Diapositivas.swift, N/diapositivas.rs | Hecho (D9): pase a pantalla completa con la pastilla, teclas de PowerPoint, clic por tercios, rueda, B/. negro, N notas abajo, T transiciones (las capas de Rust), pase solo (`advTm`), videos y audios, y la vista del orador en la otra pantalla; lo abren el botón y F5 del lector, el pin de Office y el menú de la burbuja. Faltan PPTX → proyecto y `.ppt`/`.odp` (Windows los pasa por PowerPoint); doble clic en la burbuja sigue abriendo el pin (en Windows presenta) |
| dibujo/ | Herramientas comunes: construir, grupos, lupa, copiar y pegar | parcial | K/Lienzo/*, N/editor*.rs | Hechas todas las herramientas de la barra (zona, láser, lupa, foco, pixelar, marco, copiar estilo, bolita, soldar vértices: N/editor_herramientas.rs, N/editor_tapado.rs). Faltan copiar y pegar elementos, agrupar y los atajos de §2.5 |
| dispositivo_perdido | Recuperarse si se pierde la GPU | interno | — | Solo para Metal en Planos, si se quita la GPU |
| editor | Revisar la grabación antes de guardarla | completo | K/Grabar/EditorGrabacion.swift, K/Grabar/EdicionGrabacion.swift | Hecho (D7): al parar se abre andando y en bucle; Espacio, ←→ (⇧ un segundo), velocidad ¼×–4× y formato MP4/GIF; «Guardar…», «Guardar» (↩, a `capturas/`), «Copiar» (el fichero) y «Descartar» (Esc o cerrar). Del Mac: recortar (I/O y asas), dividir (S) y quitar o devolver el tramo (⌫), zoom (Z, clic elige dónde) y ⌘Z. La velocidad y el zoom se guardan; sin cambios se mueve el MP4 sin recodificar. El GIF grabado (`GrabadorGif`) aún se guarda directo |
| fondo_lienzo | Un pin o una página PDF como fondo del lienzo | parcial | K/Lienzo/FondoLienzo.swift, K/Pines/Anotar.swift | El lienzo ya sabe llevar fondo (imagen o página de PDF a 1400 de ancho, dentro de lupas, zona y lo exportado): `VentanasDeLienzo.abrir(…, fondo:)`. Ya lo abre la hoja-página del chat (B9); falta el pin |
| foto_anotada | Ver el lienzo que el móvil dibujó sobre una foto | completo | K/Chat/Adjuntos.swift, K/Chat/BurbujasQueLlegan.swift, N/burbujas.rs | Hecho (B9): la burbuja pinta `lienzos/<referencia o foto-<id>>.excalidraw` recortado a la foto (o entero con `soloLaFoto: false`); doble clic y «Anotar encima» abren ese mismo lienzo (estrenándolo con la foto dentro, `lienzo_de_la_foto::asegurar`, si no lo tiene) |
| fusionar_paginas | Varias páginas de un PDF → un lienzo | falta | — | Todo |
| galeria_capturas | Galería con buscador (también OCR), grupos por día, teclado, detalle | completo | K/Galeria/*, N/galeria.rs | Hecho (B6): buscador en la barra (nombre, fecha y el texto de dentro leído con Vision en `cache/galeria/`), grupos por día con «Elegir todo el día», chapa por colores, elegir varias con su barra, el menú de Windows (pinear, copiar, compartir, «Guardar como…», mostrar en el Finder, conservar, 7 días más, borrar con deshacer) más «Mandar a un proyecto» y «Anotar en un lienzo», y las teclas. El panel de detalle lo quitó Windows el 5-oct |
| gif | GIF en dos fases: marco y luego barra | parcial | K/Captura/GrabadorGif.swift | Hecho (B8): marco azul con el ritmo (−/+, `[gif]`), ↩ empieza y para, Esc global, retardo con cuenta atrás; (D7) el marco se mueve y se estira antes de grabar. Falta pausar y pasar por el editor |
| grabador | Grabación en dos fases | completo | K/Grabar/{GrabadorPantalla,SesionGrabacion}.swift, K/Captura/CapturaConScroll.swift (`MarcoDeZona` ajustable) | Hecho (D7): zona, ventana o pantalla con la captura; marco azul que se mueve y se estira (el centro deja pasar los clics), micrófono y sonido del Mac, «Grabar ↩» con la cuenta atrás de `[gif] retardo_s`, rojo grabando con reloj, Pausar/Seguir (sin hueco en el vídeo) y Parar ↩; Esc cierra antes y para después; ⌃⌥R empieza y para. Al parar, el editor |
| grupos_ventanas | Guardar y reabrir grupos de ventanas | falta | — | Todo |
| hoja_pin | Excel como pin, ver y editar en el mismo sitio; libro de varias hojas | completo | K/Documentos/HojaCalculo.swift, N/hojas.rs, N/hojas/{editor,libro}.rs | — (D5: un Excel, ODS o CSV del chat se edita como libro con sus hojas en pestañas y pasa al chat como tablas sin tocar el archivo; rango, formato, deshacer, copiar y pegar con Excel. Ver sigue siendo el pin de Vista Rápida, no el mismo visor) |
| imagenes_lienzo | Imágenes pegadas en el lienzo | completo | K/Lienzo/ImagenPegadaLienzo.swift | — |
| instancia_de_prueba | Instancia aislada para desarrollar | no aplica | — | — |
| lecciones | Ficha, etiquetas, repaso, dictado, fotos y audios, exportar | parcial | K/Lecciones/*, N/lecciones.rs | Dictado, poner fotos y audios desde el Mac, exportar. Las del móvil ya se ven en la ficha (B9: «Fotos y audios», doble clic con Vista Rápida) |
| lector | Lo común a los lectores: papel, riel de marcadores | completo | K/Documentos/LectorDocumento.swift, AvanceLector.swift, TonoLector.swift | — (riel a la derecha con ⌘1…9, tira de M con su cifra, negativo) |
| lector_pdf | Lector PDF, Word y PPTX | parcial | K/Documentos/LectorDocumento.swift, BuscadorLector.swift, AvanceLector.swift, AlDiaLector.swift, N/documentos/lector.rs | Hechos (B7) buscar, D, N, G, imprimir, compartir, F5, ⌘1…9, F2 y `al_dia` (releer y juntar al guardar); escuchar (D2, K/Documentos/VozDelLector.swift). Faltan «Ver como texto», exportar el PDF anotado (D1) y quitar lo anotado |
| lector_pdf_proyecto | Dónde va la tinta de un PDF | completo | N/documentos.rs | — |
| lector_pin | Los lectores como pin | completo | K/Documentos/LectorDocumento.swift | La barra flotante de los pines |
| lector_tinta | Capa de tinta sin desfase | parcial | N/documentos.rs | Word y EPUB reflujados |
| leer_en_voz | Escuchar un documento resaltando por dónde va, con teclas multimedia | completo | K/Voz/LeerEnVoz.swift, VozAlta.swift, MandosSistema.swift, K/Documentos/VozDelLector.swift, VozDeLaNota.swift | Hecho (D2): una voz para la app (`AVSpeechSynthesizer`) que sigue con el lector cerrado y se engancha al volver a abrirlo; trozos de frases por hoja (`voz_alta::cortes`), idioma adivinado, ambar en el trozo y en la palabra, la vista lo sigue, el 🟢 se mueve (y se quita al acabar) aunque el lector esté cerrado; ⏮ ⏯ ⏭, velocidad 0,75–2×, ✕; «Voz para leer» en G (se recuerda por lengua); «Está sonando» y teclas multimedia (`MPRemoteCommandCenter`); barra flotante sin lector. Notas: clic derecho «Escuchar desde aquí» en el editor anterior. En vez de las voces de Microsoft, las del Mac (mejoradas/premium). Falta: el editor web de notas (gancho `VozDeLaNota.escuchar`). El pedido `leer_en_voz` (texto, `.txt`/`.md`, `parar`), hecho en C2 |
| letras_que_viajan | Las letras SHX viajan entre aparatos | parcial | nucleo/pixpin-cad (las lee) | No crea `auto-letra-*` |
| lista_del_icono | Jump List | completo | K/Pedidos/DelegadoApp.swift | C2: el menú del Dock (`applicationDockMenu`) con las entradas de la Jump List (Capturar, Mensajes guardados, Proyectos, Sincronizar y los 3 últimos proyectos tocados), cada una un pedido, más Tareas, Buscar, Galería y Pinear la última captura. El icono del Dock sale mientras hay una ventana de PixPin abierta (el botón de la barra de tareas) y se va con la última |
| llamada | «Llamada secreta» (VOZ con `recuerdaEn`) | completo | K/VozVentanas/LlamadaSecreta.swift, N/llamada.rs, K/Recordatorios/Vigia.swift | Hecho (E5): al vencer una nota de voz con su audio suena «Llamada entrante» abajo a la derecha con un tono del Mac en bucle, Contestar/Colgar, reloj, cuelga sola al acabar, perdida a los 45 s («Llamada perdida · quien» con +10 min y Abrir), «Volver a llamar en» 5/15/30 min, 1 y 2 h. «Quién llama» en el menú de la hora (fichero `llamada_secreta.json`, no viaja). El Mac no tiene salida de llamadas aparte: contestada suena bajita y «Altavoz» la sube. Lo vencido hace más de 10 min con la app cerrada sale como aviso normal |

### 1.2 Módulos m–z y `main.rs`

| Módulo Windows | Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|---|
| main (bandeja) | Menú de la bandeja con 27 comandos | parcial | APP, K/Ajustes/ComandosApp.swift | Faltan: clic a través y restaurar el último pin (salen solos cuando los pines los den) |
| main (arranque) | Restaurar pines, vigía de recordatorios, automatizaciones, línea de órdenes, avisos de caducidad | parcial | APP, K/Pines/GestorPines.swift | Recordatorios (las automatizaciones arrancan con la app: E6) |
| marco_de_la_tinta | Migrar la tinta vieja al marco `.hoja` | interno | N/documentos.rs (lee el marco) | Pasada `tras_sincronizar`; solo hace falta con datos viejos |
| medir_fotogramas | Medir fotogramas | interno | — | No hace falta (Instruments) |
| mini_panel | Mini-apps: tareas, contador, ruleta, gastos, relojes | completo | K/Pines/Herramientas.swift, RelojesPin.swift, N/miniapps.rs | Su teclado (F2, Supr, «25»+↩) |
| miniaturas | Fotos del proyecto en el panel de información | falta | — | Todo |
| modelo_bim | IFC, Revit, LandXML en 3D | completo | K/Planos/VisorModelo3D.swift, N/modelos3d.rs | Hecho (E2): la caché `cache/bim/<clave>.px3d` de Windows (16), las teclas de Windows y ⌘E (la foto de la vista y el original). Las vistas 1–9 son las de un croquis (un IFC no tiene, como en Windows). Se lee en el mismo proceso, no en uno aparte; probar IFC grandes en un Mac real |
| navegacion | Cámara del lienzo | parcial | K/Lienzo/EditorLienzoView.swift | Espacio + arrastrar (lo lleva el agente del lienzo) |
| notas_md (editor, guardar) | Editor de notas Markdown | completo | K/Documentos/EditorNotaWeb.swift, N/notas/web.rs | — (D4: la misma página de Windows, `lector-md.html`, en un `WKWebView`: formato vivo, barra flotante, menú `/`, tablas, fórmulas, casillas, letra y tamaño en `vista-de-notas.txt`, copia `.md`, Word, compartir, lo de fuera al día; el editor de AppKit queda como «anterior»; un `.md` del chat o del Finder se abre aquí) |
| notas_md/adjuntos | Fotos dentro de la nota | completo | N/notas/adjuntos.rs, K/Documentos/EditorNotaWeb.swift | — (elegir, pegar o soltar fotos, documentos y audios; se copian a `notas/` como `pixpin:files/…` y viajan; la página los pide por `pixpin-nota://`) |
| notas_md/comentarios | Comentarios (`anot-<uid>.comentarios.json`, viajan) | completo | N/notas/comentarios.rs | — (los de Windows: hilos, responder, editar, borrar, resolver; se juntan con lo que llega al disco) |
| notas_md/incrustados | Documentos o mensajes dentro de la nota | parcial | N/notas/web.rs | Hechos documentos y audios (los pinta la página) y «Del chat» (enlace `pixpin:mensaje=` o el audio de una voz). Faltan saltar al mensaje en su chat al tocarlo y la transcripción bajo el audio |
| notas_md/paginas_vivas | Páginas vivas y enlaces a hojas | falta | — | La página ya las pinta; falta pintar la hoja a PNG y la lista de hojas (`paginas_vivas.rs`); de momento salen apagadas |
| notas_md/lector_web | Modo lector de la nota | completo | K/Documentos/EditorNotaWeb.swift, N/notas/web.rs | — (es el editor que se abre, D4) |
| notificaciones | Notificaciones con botones: «Hecha», «+10 min», «Abrir», «Conservar» | completo | K/Avisos/CentroAvisos.swift, K/Pines/AvisosMini.swift | Sin permiso del sistema, lo urgente sale en una ventanita de la app con los mismos botones |
| orden | Línea de órdenes y `pixpinmax://` | parcial | K/Pedidos/{Pedido,Verbos,Enlaces}.swift | C2: `CFBundleURLTypes` (`pixpinmax`) y la tabla de verbos de `orden.rs` entera (mismos nombres, alias y campos; `pixpin://atajo/…` de Android también, y `pixpinmax:pedido?json=`); la lista blanca (`seguridad`), el cuadro de confirmar con «No» por defecto, lo prohibido (rutas de red: `//…`, `/net`, `/Network`, `smb:`, `file:`, relativas) y la firma HMAC-SHA256 (`enlaces.clave` en la carpeta de datos). El Mac no reclama `pixpin://` (es también del PixPin de DepthPixel). Falta la línea de órdenes (`pixpinmax <verbo>` en Terminal): `Verbos.deArgumentos` ya la entiende, falta el ejecutable |
| oscuro | Modo oscuro de los visores (luna/sol) | parcial | K/Documentos/TonoLector.swift, N/documentos/lector.rs | Hecho en el lector (luna/sol en su barra, `lectores_oscuros` del estado, la tinta se adapta) y en el visor de planos (E2: luna/sol y B, el mismo `lectores_oscuros`; el 3D cambia el suyo con B, como Windows). Faltan el pin de Office y la hoja de cálculo |
| overlay | Overlay de captura | completo | K/Captura/* | — (B8: ⌘A, flechas, Espacio en vivo, ⇧ HEX/RGB, ⇧⌘S, ⌫, cuentagotas; la barra de acciones de Windows) |
| panel_dibujo | Panel de estilo del lienzo | parcial | K/Lienzo/BarraEstiloLienzo.swift | **Lo lleva el agente del lienzo** |
| pdf_del_proyecto | Rehacer un PDF roto desde `pdfLimpio` | falta | — | Todo |
| pdf_en_chat | El PDF como un mensaje con vista; unir páginas | parcial | K/Chat/Adjuntos.swift, K/Documentos/AccionesDocumento.swift | Unir PDF, «como imágenes», devolver |
| pedidos | Pedidos de otros programas | parcial | K/Pedidos/HacerPedidos.swift, XC/App/Intenciones.swift (9 intents) | C2: los hace `HacerPedidos` (abrir proyecto, mensaje, hoja, nota y fichero; chat con fotos y ficheros; nota, lienzo y lista nuevos; tareas: añadir, marcar, quitar, corregir, borrar lista; ventana; capturar con sus modos; pinear, pinear la última, conservar, copiar imagen; grabar; sincronizar y al móvil; asistente (también con `automatizacion`); `automatizacion` (E6: crear, activar, desactivar, borrar, ejecutar); pines; timeline; leer en voz; OCR; reproducir). Intents nuevos: Nueva tarea, Nuevo lienzo, Grabar nota de voz, Abrir proyecto, Mandar al móvil. Faltan `soltar`, `iconos`, `mover_tarea`, `borrar_captura`, `tabla_nueva`, `posponer`, `herramienta`, la ficha de lección nueva y la búsqueda de lecciones ya escrita, `abrir` con `pagina`/`buscar`, tareas con imágenes y el nombre de la grabación |
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
| plano_cad (visor) | DWG/DXF como pin | completo | K/Planos/VisorPlano.swift, N/planos.rs, N/planos/cache.rs | Hecho (E2): la caché `cache/cad/<clave>-l1[-huella].pxcad` (24, la clave y la huella de letras de Windows; guarda el plano por capas), las letras del plano (L: las que faltan, añadir y quitar las de `fuentes-shx`, se relee con ellas), siempre encima (T) y todas sus teclas. Diferencias: se lee en el mismo proceso (Windows usa uno aparte por si un DWG roto lo tumba) y las letras del usuario aún no viajan (`letras_que_viajan`) |
| plano_cad/anotar | Anotar el plano a mano | completo | K/Planos/AnotarPlano.swift, N/planos/anotar.rs | Hecho (E2): A o el lápiz de la barra pone el lienzo de verdad encima (su barra, su panel y sus teclas) con la cámara del plano, en la capa `anot-<uid>` (viaja) o la de la caché, con su `.hoja` detrás. ⎋ sin nada elegido termina. Diferencia: la capa se edita en las unidades de su fichero (Windows la lleva en memoria en las de la letra del plano); una capa nueva queda igual |
| plano_cad/exportar | Exportar el plano | completo | K/Planos/ExportarPlano.swift, N/planos/exportar.rs | Hecho (E2): ⌘E abre la hoja común con HTML (la página de Windows, `pixpin_cad::web`, con las capas como se ven), PDF en vectores (una hoja por marco, A3), PNG y JPG (3200 px), DXF de un DWG y el original; las cotas y lo anotado van encima (también al imprimir) |
| plano_cad/imprimir | Imprimir | completo | K/Planos/ImpresionPlano.swift | — |
| plano_cad/textos | Buscar en los textos del plano | completo | K/Planos/VisorPlano.swift (⌘F), N/planos/textos.rs | Hecho (E2): los textos con su sitio en `cache/cad/<clave>-textos.json` (el JSON de Windows), sin mirar mayúsculas, tildes ni puntos, los más grandes antes; ⌘F los busca y lleva a cada uno con una marca. Que el asistente abra el plano en un texto (`abrir_en`) es de E1 |
| pronunciar | Practicar la pronunciación | completo | K/VozVentanas/Pronunciar.swift | Hecho (E5): Espacio (o el micrófono) mantenido graba y al soltar se oye; R, ⌘G/⌃G guarda en el chat y se pasa a texto en el idioma practicado (8 idiomas del móvil); guía de texto, `.md`/`.txt`, imagen o PDF (páginas ←→) del Mac o del chat; «Oír el texto» con la voz del Mac |
| punto_de_proyecto | Punto verde o rojo en la burbuja | completo | K/Chat/BurbujasQueLlegan.swift, N/burbujas.rs | Hecho (B9): `MensajeChat.punto` (las señas de los `proyecto.json`, en caché por fechas), junto a la hora |
| recibir | Recibir del móvil con QR; lienzo suelto | completo | K/Sincro/EnvioPorCodigo.swift, N/envio.rs, N/recepcion.rs, N/lienzo_suelto.rs | — |
| recibir_de_windows | «Imprimir a PixPin» y Compartir | parcial | XC/Compartir | PDF Services («Guardar en PixPin» del diálogo de imprimir) |
| recordatorios | «Recuérdame a las 10» y el vigía | completo | N/recordatorios.rs, K/Recordatorios/{Vigia,Avisos}.swift | Sin hilo en Rust: el vigía es de Swift (temporizador de pared + notificación del sistema para la app cerrada). La llamada secreta (E5) sale del vigía: `Recordatorios.llamada(de:)` |
| renombrar_doc | F2 para renombrar en el lector | completo | K/Documentos/LectorDocumento.swift, N/documentos/lector.rs | — (el nombre del mensaje si es de un chat; el fichero con sus hermanos si es suelto) |
| reproductor | Editor de grabaciones | completo | K/Grabar/EdicionGrabacion.swift | Hecho (D7): el reloj del editor en segundos del MP4 (salta lo quitado, da la vuelta, paso a fotograma) y lo que se exporta (tramos, velocidad, zoom, momentos del GIF) |
| salida | Ventanita «Salida» para arrastrar lo exportado | completo | K/Compartir/Salida.swift | D1: flotante abajo a la derecha sin robar el foco, una sola que suma arriba, tarjetas con miniatura, tipo y peso, arrastrar una o todas, Copiar, Abrir, Carpeta, Pinear y «Abrir con…»; la usan la hoja y el exportar del lienzo |
| salto_por_enlace | Abrir el sublienzo de una zona | falta | — | Depende de zona_al_chat (lienzo) |
| scroll | Captura con scroll | completo | K/Captura/CapturaConScroll.swift | — |
| sincronizar (pantalla) | Este aparato, tus aparatos, añadir | completo | K/Sincro/VistaSincro.swift, K/Sincro/VistaAparatos.swift, N/aparatos.rs | — |
| sincronizar/al_dia | Llegar aunque cambie la IP | completo | K/Sincro/Sincronizador.swift (`llegar`, `mirarRecordadas`), N/aparatos.rs | Las direcciones recordadas se prueban al refrescar y al abrir la ventana, no cada 4 s (en Mac nada sondea) |
| sincronizar/al_movil | Foto al lienzo abierto del móvil | parcial | K/Sincro/EnviarA.swift | Recibirla en el lienzo del Mac |
| sincronizar/automatica | Sincronizar solo | completo | K/Sincro/Sincronizador.swift, N/sincro_auto.rs | — |
| sincronizar/compartidos_ui | Chats compartidos con personas | completo | K/Sincro/Compartidos.swift | — |
| sincronizar/copias_ui | Ver y restaurar copias; proyectos borrados | completo | K/Sincro/VistaCopias.swift, N/copias.rs | — |
| sincronizar/elegir | «¿Qué sincronizar?», lápidas, «Lo mío manda» | completo | K/Sincro/ElegirSincro.swift, N/sincro.rs | «Lo mío manda» por defecto, en Ajustes → Sincronizar (C3) |
| sincronizar/en_fondo | Sincronizar sin ventana | completo | Intent `SincronizarAhora` | — |
| sincronizar/enviar_wifi, recibir_wifi | Enviar y recibir con código | completo | K/Sincro/EnvioPorCodigo.swift, N/envio.rs, N/recepcion.rs, N/lienzo_suelto.rs | Sin cámara: el QR del otro se pega como texto (como Windows) |
| sincronizar/galeria | La galería viaja | completo | N/galeria_sincro.rs | — |
| sincronizar/presencia | Localizable mientras está abierta | completo | K/Sincro/Anunciador.swift, Sincronizador.swift | Interruptor «Dejarse encontrar» en Ajustes → Sincronizar (C3): abre o cierra la puerta al momento |
| tareas (ventana) | Tareas de todos los chats | parcial | K/Tareas/Tareas.swift, N/tareas.rs | Buscar, «Mover a…», borrar y deshacer, F2, pegar imágenes (el `⏰`, hecho en A4: se ve y se pone desde el menú de la fila) |
| tareas/rejilla, tarjetas, emoticonos | Vista de tarjetas y etiquetas | falta | — | Todo |
| teleprompter | Telepronter | completo | K/VozVentanas/Telepronter.swift | Hecho (E5): en la otra pantalla a pantalla completa, franja de lectura, ensayar, 3-2-1, grabar con pausa y tirar, A−/A+, velocidad con palabras y la rueda, raya de lo leído; la nota entra con su texto `[m:ss]` ya puesto (`bien`). Se elige el texto: lo escrito en la caja, notas o `.txt`/`.md` del chat. Falta abrirla luego en «Letra» (no hay Letra en el Mac) |
| tema_cosmos | Tema Cosmos | falta | — | Es un adorno |
| timeline (ventana) | Hoy, Momentos, Estado, Lecciones; apuntar | completo | K/Timeline/*, N/timeline.rs | Hecho (B5): apuntar texto, fotos (elegir, pegar, soltar) y voz; corregir (↑), borrar con deshacer, a «Momentos», la bombilla de lección; buscar en todo; el detalle con sus flechas, pinear y anotar en un lienzo |
| timeline/dictar, exportar, tarjetas, estado_mes, compartir | Dictar; exportar a HTML o PDF; vista por mes | parcial | K/Timeline/DictadoTimeline.swift, K/Timeline/PestanasTimeline.swift, N/timeline.rs | Hechos: dictar (Speech en el aparato, con su audio), «Momentos», «Calendario» con ⌘clic para elegir días, exportar lo que se ve a HTML o PDF (WebKit), compartir una tarjeta como imagen o página. Falta la hoja común de exportar (D1) y el `.pixpin` de lo exportado. Las fotos y la voz de un momento no pasan a su lección |
| turno_pesado | Un trabajo pesado cada vez | interno | — | Solo si llega Whisper |
| v2/ | Aviso con Deshacer, pista, pegar | interno | SwiftUI | Un aviso «Deshacer» común |
| ventanita | Base de las ventanitas de voz | completo | K/VozVentanas/Ventanita.swift | Hecho (E5): colores de papel oscuro, botón plano, ventana lisa con su teclado y el micrófono a un `.m4a` suelto |
| visor | Word, EPUB y páginas reflujados | parcial | K/Documentos/LectorDocumento.swift (paginado) | Reflujo, letra (+/−, T, B), índice, «PDF como texto», tinta del EPUB |
| visor/como_texto, imagenes, tablas, maqueta_movil | — | falta | — | La maqueta del móvil (para que la tinta caiga igual) |
| visor_hoja | `.xlsx` entero como pin | parcial | K/Documentos/PinOffice.swift, K/Documentos/HojaCalculo.swift | Las pestañas y ⌘flechas están en el editor (D5); el pin de ver (Vista Rápida) no tiene enlaces ni capa de tinta |
| visor_html | `.html` a pantalla completa | completo | K/Documentos/VisorHtml.swift | — (D9: `WKWebView` liso del tamaño del área de trabajo con la barra de los lectores; `PixPinVisor.guardar` y la descarga del `.html` se guardan encima del mismo fichero con el filtro de Android, lo demás a Descargas; ⎋ cierra, ⌘E exporta, sigue luna/sol) |
| vista_rapida | Espacio en el Explorador | no aplica | XC/VistaPrevia | Quick Look del Finder |
| voz | Nota de voz → texto | completo | K/Voz/* | — |
| voz_en_chat | Corregir la letra, Pronunciar, turnos | parcial | K/VozVentanas/VozEnElChat.swift | Hecho (E5): Pronunciar y la conversación desde el chat, lo grabado entra y se pasa a texto. Falta corregir la letra (no hay Letra en el Mac) |
| zona_al_chat | La zona del lienzo al chat como sublienzo | falta | — | Depende del lienzo |

### 1.3 Ventana del chat (`ventana_chat.rs` y `ventana_chat/`)

| Función | Estado Mac | Archivo(s) Mac | Qué falta |
|---|---|---|---|
| Lista de proyectos; chat por páginas; burbujas por tipo | completo | K/Vistas.swift, K/Chat/* | — |
| proyectos/ (tarjeta rica, «universo», teclado) | parcial | K/Vistas.swift | Tarjeta y universo |
| logo del proyecto; «Guardar en…» al crearlo | falta | — | Todo |
| Caja de escribir | completo | K/Chat/CajaEscribir.swift | Hecho (B3): la isla (radio 22 y filete), el campo en pastilla con el clip dentro (se retira al escribir) y el micrófono o enviar fuera; ↩ envía, ⇧↩ o ⌥↩ saltan de línea, Esc suelta lo seleccionado, luego limpia y, vacía, deja de responder; grabando, el cronómetro en su sitio. Hecho (E1): la lista de `@` encima de la caja (el asistente fuera de su chat y los lienzos y hojas de la conversación). Falta el dictado |
| Hoja «+» (captura, lienzo, tabla, tareas, página, nota, móvil…) | parcial | K/Chat/HojaAdjuntar.swift | Hecho (B3): las 19 entradas de Windows con su buscador (sin tildes, con sinónimos), 1–8, flechas, ↩ y Esc. Hacen lo suyo: foto o vídeo, archivo, lienzo, nota (nace «# Nota nueva» y se abre en el editor), lista de tareas y las seis mini-apps (en el chat y como pin), tabla, captura (la de siempre; «Al chat» propone este proyecto) y traer del móvil. Conversación, Teleprónter y Pronunciar abren sus ventanitas (E5). Salen apagadas y lo dicen: Página de un proyecto y Proyecto entero (**B9**) |
| Enviar fotos con descripción | falta | — | Todo |
| Caja de soltar flotante | parcial | K/Vistas.swift | Hay soltar sobre el chat |
| Tarjetas de enlace | falta | — | Todo |
| Menú del mensaje (menu_v2) | parcial | K/Chat/MenuMensaje.swift, K/Chat/BorrarMensajes.swift, N/chats.rs | Hecho (B2): etiquetas ⭐✅⏳💡💰📍, Responder (con la cita en la burbuja y la barra encima de la caja), Copiar, Pinear (fichero o lista de tareas), Añadir/editar descripción, Abrir en el editor de notas, Pasar a texto, Reenviar, Compartir, Recordármelo (horas de Windows y «Elegir la hora…»), Hacer lección (con `deMensaje`), Cambiar el nombre, Fijar arriba (y la barra «Mensaje fijado»), Abrir con… (el común), Exportar… e Imprimir… de un lienzo (la hoja común, D1), Aligerar el PDF, Guardar esto, Ver comentarios, Elegir varios, Borrar; la barra de elegidos con Copiar, Compartir, Fijar, Reenviar y Borrar. Anotar encima de una foto (en su lienzo propio, B9). Falta: Unir/Devolver al proyecto y «como imágenes» (PDF en el chat), Insertar en nota, Letra, Ver el dibujo entero, Guardar receta (asistente). «Quién llama» de una nota de voz, en «Recordármelo» (E5) |
| Elegir varios y marcar un tramo | completo | K/Chat/BorrarMensajes.swift | — |
| Buscar dentro del chat (Ctrl+F) | completo | K/Chat/BuscarEnChat.swift | Hecho (B3): ⌘F con un chat abierto (sin chat, sigue «Buscar en todo»); en todo el chat, no solo lo cargado; filtra las burbujas (texto o lo dicho y nombre del fichero, sin tildes), resalta en las notas, chips de etiqueta, «N resultados · Ver en contexto», ↑/↓ o ⌘G/⇧⌘G entre resultados («3 de 12»), ↩ lo ve en su sitio, Esc apaga |
| Escala (Ctrl + / − / 0) | parcial | K/Chat/EscalaChat.swift | Hecho (B3): ⌘+ / ⌘− / ⌘0 con los escalones de Windows (75–250 %), su aviso, y se recuerda. Crece el chat (letra, burbujas, fotos, dibujos y la caja); la lista de proyectos y la franja no. Falta la entrada «Escala de la interfaz» del menú de la cabecera (el Mac aún no tiene cabecera del chat) |
| Fondos del chat | falta | — | Todo |
| Micrófono flotante con hora | completo | K/Voz/FlotantesVoz.swift | Hecho (D3): siempre encima, aro que late y tiempo; clic o ↩ guarda, ⎋ tira; «Convertir en llamada» con la hora (nace una hora después y en punto, «En 15 min», «En 1 hora», «Mañana 9:00», ↑↓ de 5 en 5, teclearla) que pone `recuerdaEn`; se va sola. Se abre con clic derecho en el micrófono del chat o «Grabar» de la biblioteca (el pedido «grabar» es C2); al poner la hora apunta «quién llama» (E5) |
| Reproductor flotante | completo | K/Voz/FlotantesVoz.swift | Hecho (D3): «Escuchar en flotante» (burbuja y biblioteca), Espacio, ←/→, ⎋, la fila y se va al acabar (el pedido «reproducir» es C2) |
| Chat «Asistente» del sistema; aviso y voz del asistente | parcial | K/Asistente/{VistaAsistente,DictadoAsistente}.swift | Hecho (D6) en la ventana del asistente: el altavoz de cada respuesta, «Leer siempre las respuestas» y dictar con «Ver lo dicho antes de enviarlo». Hecho (E1): el chat «Asistente» del sistema, su barra («Contestando… Parar», el aviso sin motor o sin clave) y «Leer siempre las respuestas» también en el chat. Falta la tarjeta de bajar el modelo dentro del chat (está en la ventana del asistente) |

### 1.4 Ajustes (`ventana_ajustes.rs`)

| Sección | Estado Mac | Qué falta (Mac: K/Ajustes/*) |
|---|---|---|
| Interfaz (buscador, restablecer, ⌘Z) | completo | C3: columna con buscador (⌘F, sin tildes, en todas las secciones) y secciones, tarjetas oscuras planas, punto azul + volver a fábrica por fila, «Restablecer <sección>», «Deshacer» (⌘Z, 100 pasos). K/Ajustes/VistaAjustes.swift, FilasAjustes.swift. Se guarda al momento (no hay «Listo») |
| General | completo | Abrir al iniciar sesión (`SMAppService`, de este Mac), idioma (`idioma` del TOML + `AppleLanguages`; la app aún solo está en español), PDF (`[pdf]`) |
| Captura | parcial | Retardo, formato del color, alto máx. con scroll, GIF (fps y cortesía), carpeta (Abrir), días hasta borrar, pila y gestos; programas ignorados y regiones están en Atajos. Falta: que `CapturaConScroll` y `GrabadorGif` lean `limite_scroll_px` y `[gif]` (hoy topes fijos; agente de captura: `nucleo.ajustes()`), y esquina/tiempo de la pila |
| Pinear | falta | Palabras mágicas (depende de las mini apps del pin) |
| Lienzo (imán, suavizado) | falta | Depende del lienzo |
| Voz | parcial | Segundo idioma y modo se guardan en `[voz]`; el dictado del Mac (`SFSpeechRecognizer`) usa uno solo |
| Asistente (modelo, pensar, claves) | parcial | Motor, modelo, pensar, respaldo, mejor vista, documentos a la nube, voz del asistente y claves (Llavero: pegar, ver enmascarada, «Probar» —y se prueba sola al guardarla—, borrar). El asistente del Mac ya los usa todos (D6). Las automatizaciones tienen su ventana («Automatizaciones…» del menú, E6) en vez de una sección de Ajustes |
| Atajos | completo | K/Ajustes/SeccionAtajos.swift (sección «Atajos»); UserDefaults, no el TOML (no viaja) |
| Sincro | completo | Dejarse encontrar, sincronizar sola y «Lo mío manda» (`[sincro]`) |
| Apps (abrir con, predeterminada) | no aplica | En macOS lo dan el Info.plist y «Abrir con» del Finder (C2, hecho: imágenes, vídeos y audios además de PDF, Office y planos) |
| Apariencia (Cosmos) | parcial | Aspecto (claro/oscuro/sistema, de este Mac). Falta Cosmos |
| Avanzado | completo | Abrir `pixpinmax.toml` y la carpeta de datos; rendimiento y filtro del lápiz de Windows no aplican |

### 1.5 Editor del lienzo (`ventana_editor/`)

**Todo esto lo lleva el agente del lienzo; aquí solo consta para que se sepa.**

| Función | Estado Mac |
|---|---|
| Base, deshacer, cota y cajetín | completo |
| modo_ventana (F11) | completo (⌃⌘F, se recuerda en `estado.toml`; nunca tocado abre en ventana) |
| Exportar, imprimir y compartir; tapado; figuras y gráficas; lupas | completo (figuras: parcial, ver `biblioteca_figuras`) |
| Hojita; marcas; presentar; referencia; zona al chat | falta |
| Anotador de pantalla | completo (E3, K/Captura/AnotadorPantalla.swift) |
| congelar, medir | interno |

### 1.6 Fuera de `apps/pixpin`

| Pieza Windows | Estado Mac | Nota |
|---|---|---|
| `apps/pixpin-mcp` (servidor MCP para Claude) | falta | Se podría hacer en Mac con el mismo protocolo (stdio) |
| `apps/pixpin-puente` y `extensiones/navegador` | falta | Native Messaging de Chrome/Edge; en Mac también hay Safari |
| `apps/pixpin-lanzador` (buscar) | parcial | Está en `por-adaptar/`, igual que Windows (A7); falta adaptarlo |
| `apps/pixpin-aligerar` | completo | Igual que Windows; el Mac usa N/aligerar.rs |
| Integraciones: CLI, PowerShell, AutoHotkey, menú del Explorador | parcial | C2: el esquema `pixpinmax://` (Stream Deck, Raycast, Alfred, `open` en Terminal), 9 App Intents y los Servicios del Finder (PixPin ▸ Al chat, Pinear, Copiar texto (OCR), Enviar al móvil, Preguntar al asistente; varios ficheros en una llamada). Falta la línea de órdenes |
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
| 25 comandos sin tecla de fábrica, que el usuario puede atar | Capturar y copiar, scroll, anotar, GIF, última región, cuentagotas, pinear, en vivo, portapapeles, selección, retardo, silenciar, clic a través, restaurar o cerrar pines, OCR, ventana encima, chat, ajustes, recibir, sincronizar, buscar, salir | sin tecla de fábrica; se atan en Ajustes → Atajos (mejor ⌃⌥+tecla) | completo salvo clic a través y restaurar el último pin (esperan a los pines). Cuentagotas = `NSColorSampler`; ventana encima = pin en vivo de la ventana (macOS no deja subir ventanas ajenas); anotar = el anotador de pantalla (vivo o congelado, E3) |
| Atajo por región (Ctrl+Alt+1…) | Capturar una región fija | ⌃⌥1… (Ajustes → Atajos → Regiones, «Guardar la última zona») | completo |
| Silenciar atajos · programas ignorados | Soltarlos todos · no actuar delante de una app | menú de la barra y Ajustes · lista de apps en Ajustes | completo (los gestos con ⌥ aún no miran la lista) |
| Choques | Dos comandos con el mismo atajo | Se rechazan; también los de macOS (⇧⌘3/4/5/6, ⌘+tecla, ⌥⌘H/M/D, ⌃⌘Q/F) y se avisa de ⌃1…9, ⌃F1…F8 y ⌃⌘D | completo |
| Alt + arrastrar (izquierdo, derecho, central) | Copiar, pinear, pin en vivo | ⌥ + arrastrar | completo (apagado de fábrica; pide Accesibilidad) |
| Alt + doble clic central | Anotar la pantalla; abierto, alterna el clic a través | ⌥ + doble clic central | completo (E3) |
| Anotador: Esc, Espacio, Ctrl mantenido, Ctrl+Z / Ctrl+Y | Salir (guarda solo), clic a través, clic a través mientras dure, deshacer / rehacer | ⎋, Espacio, ⌘ mantenido (⌃+clic sería el derecho), ⌘Z / ⇧⌘Z / ⌘Y | completo (E3) |
| Menú: — | Proyectos, Buscar | ⌥⌘P, ⌥⌘F (solo con el menú) | solo Mac |

### 2.2 Captura (overlay)

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Z V P S G L T | Modos | igual | completo |
| R | Repetir la última zona | R | completo |
| C | Copiar el color (y cerrar) | C | completo (HEX, RGB o HSL de `formato_color`) |
| Mayús sola | HEX ↔ RGB | ⇧ | completo |
| Ctrl+A | Pantalla entera | ⌘A | completo |
| Intro / Ctrl+C | Copiar | ↩ / ⌘C | completo |
| Ctrl+P · Ctrl+M · Ctrl+T · Ctrl+S | Pinear, al chat, OCR, guardar | ⌘P · ⌘M (choca, se lo queda el overlay) · ⌘T · ⌘S | completo |
| Ctrl+Mayús+S | Guardar como | ⇧⌘S | completo |
| — | Grabar la zona | ⌘G | solo Mac |
| Esc | Descartar | ⎋ | completo |
| Ctrl+Z / Ctrl+Y | Deshacer / rehacer la anotación | ⌘Z / ⇧⌘Z | completo |
| 1–5 | Herramientas de anotar | 1–5 (y las letras del lienzo mientras se anota) | completo |
| Supr | Borrar la anotación elegida | ⌫ | completo |
| Flechas (Mayús ×10) · Espacio | Mover la selección · en vivo | igual | completo |
| Texto: ← → Inicio Fin Supr | Editar el texto | igual (el texto del lienzo) | completo |
| Medidas: Tab · Selector de proyecto: ↑↓, Tab al comentario | — | ⇥ · 1–6, ↩ | parcial |
| Cuentagotas: Intro/C · Cuenta atrás: Esc | — | clic, ↩ o C · ⎋ | completo |
| GIF: Intro empieza y para, Esc global | — | ↩ · ⎋ (global) | completo |

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
| Intro / Mayús+Intro | Enviar / salto de línea | ↩ / ⇧↩ (o ⌥↩) | completo |
| Ctrl+V | Pegar adjunto | ⌘V | completo |
| Ctrl+F | Buscar en el chat | ⌘F con un chat abierto; ↑↓, ⌘G/⇧⌘G, ↩, Esc | completo |
| Ctrl + / − / 0 | Escala | ⌘+ / ⌘− / ⌘0 | completo |
| Esc en cascada | — | ⎋ | parcial |
| Menú: R, Ctrl+C, P, A, E, N, T, F, L, F2, Supr | Acciones del mensaje | R, ⌘C, P, E, N, T, F, L, F2 (en «Más»), ⌫ con el menú abierto; falta A (anotar encima) | parcial |
| Ctrl+clic, Mayús+clic | Elegir varios | ⌘-clic, ⇧-clic | completo |
| Hoja «+»: flechas, Intro · Reproductor: Espacio, ←→ · Micrófono: Esc, Intro, ↑↓ | — | Hoja: 1–8, flechas, ↩, Esc (B3); reproductor flotante: espacio, ←→, ⎋; micrófono: ⎋, ↩, ↑↓, ⌫ y las cifras (D3) | completo |
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
- ⇧⌘N (hojita), F5 (presentar), ⌥R (solo mirar). (Las del anotador de pantalla, hechas en E3: §1.6.)

Ya están: ⌘Z / ⇧⌘Z, ⌘A, ⌫, ⎋, ⌘V de imagen, ⌘ + rueda, 1 / 2 / 3, ⇧⌘E (exportar), ⇧⌘C (copiar como PNG), ⌘P, ⇧⌘S y ⌃⌘F (pantalla completa, que se recuerda).

### 2.6 Lectores (PDF, Word, PPTX, visor)

| Windows | Acción | Mac | Estado |
|---|---|---|---|
| Moverse, Ctrl+C | — | nativo de PDFView | completo |
| Ctrl+rueda, + / −, Ctrl+0 | Zoom | pellizco, + / −, ⌘+ / ⌘−, ⌘0 | completo |
| Ctrl+[ / Ctrl+] | Espacio para anotar | ⌘[ / ⌘] | completo |
| A, y dentro P R E 1–5 | Anotar | A, P H E | parcial (letras y colores distintos) |
| Ctrl+Z / Ctrl+Y | Deshacer y rehacer la tinta | ⌘Z / ⇧⌘Z | completo |
| Ctrl+S | Guardar | se guarda solo | no aplica |
| M · Ctrl+1…9 | Marcador (con su cifra) · ir a él | M · ⌘1…9 | completo |
| G D N L I | Ajustes, avance solo, negativo, escuchar, índice | igual | parcial (G D N L hechas; I es del visor, E7) |
| + / −, T, B (visor) | Letra | igual | falta |
| F11 | Pantalla completa | ⌃⌘F / F11 | completo |
| Esc en cascada | — | ⎋ (cajas, presentar, lo elegido, marcador, avance, anotar, pantalla completa, cerrar) | completo |
| Ctrl+F, F3 / Mayús+F3 | Buscar | ⌘F, ⌘G / ⇧⌘G, F3 / ⇧F3, ↩ / ⇧↩ | completo |
| F2 | Renombrar | F2 o un clic en el nombre | completo |
| Ctrl+Mayús+S · Ctrl+P · F5 | Compartir · imprimir · presentar | ⇧⌘S · ⌘P · F5 | completo |
| Inicio / Fin · Ctrl+S | Principio y final · guardar | ↖ / ↘ · ⌘S (guarda ya) | completo |

### 2.7 Notas (Markdown)

| Windows | Mac | Estado |
|---|---|---|
| Ctrl+B / I, Ctrl+Mayús+X, Ctrl+E / K | ⌘B / I, ⇧⌘X, ⌘E / K | completo |
| Ctrl+M (fórmula), Ctrl+Alt+M (comentario) | ⌘M (la página la toma antes que el menú) y ⌥⌘M | completo |
| Ctrl+1/2/3, Ctrl+Mayús+8/7/9, Ctrl+Intro, Ctrl+Mayús+. / C / T / D | ⌘1/2/3, ⇧⌘8/7/9, ⌘↩, ⇧⌘. / C / T / D | completo |
| Ctrl+V de fotos | ⌘V (y soltar) | completo |
| Ctrl+S / Ctrl+Mayús+S | ⌘S (y solo a los 0,8 s) / ⇧⌘S | completo |
| Ctrl+W, F11, Ctrl+Z / Y, menú contextual | ⌘W, F11, ⌘Z / ⌘Y, el de la página | completo |
| Intro sigue la lista o la tabla | ↩, ⇥ / ⇧⇥ en la tabla | completo |
| Ctrl + / − / 0, Ctrl+clic en un enlace, comentarios, título | ⌘ + / −, ⌘-clic, ⌥⌘M, la flecha del título | completo |

### 2.8 Otras ventanas

| Ventana (Windows) | Atajos Windows | Mac | Estado |
|---|---|---|---|
| Buscar en PixPin | ↑↓, RePág/AvPág, Tab (pestañas), →, Intro, Ctrl+Intro, Alt+Intro, Supr, Ctrl+C/V/Z, Esc | ↑↓, RePág/AvPág, Tab/⇧Tab y ⌘1…7, → / ←, ↩, ⌘↩, ⌥↩ (abrir con), Supr o ⌘⌫ (captura), ⌘C, ⌘V (texto), ⌘Z, Esc por capas | completo salvo pegar imagen |
| Tareas | Ctrl+F, Ctrl+L, Ctrl+T, F2, Supr, Tab, Espacio, Intro, Ctrl+Z, Ctrl+V, Esc | ↩, ⌘R | parcial |
| Timeline | Ctrl+1…4, Ctrl+F, Ctrl+M (en Mac, otra tecla), Ctrl+Z, Intro, Ctrl+V, ↑ corrige | ⌘1…4, ⌘F, ⌘⇧M, ⌘Z, ↩ / ⇧↩, ⌘V (imagen), ↑, Esc por capas; en el detalle ←/→ y ↑/↓ | completo |
| Lecciones (ficha) | Esc guarda, Ctrl+Intro, Ctrl+E, Tab | ⌘S | parcial |
| Galería | flechas, Espacio, Intro, Supr, Ctrl+C/S/A/Z, Esc, escribir busca | flechas, Inicio/Fin, Espacio, ↩, ⌫, ⌘C/S/A/Z, ⌘F, ⌘Y, Esc, escribir busca | completo |
| Hoja de cálculo (editar) | Ctrl+N/B, Ctrl+K/I, Ctrl+S/U, Ctrl+5, Ctrl+Mayús+L/E/R, F2, Ctrl+Z/Y/C/X/V | ⌘B/I/U, ⌘5 (y ⇧⌘X), ⇧⌘L/E/R, F2, ⌘Z/⇧⌘Z/⌘Y, ⌘C/X/V, ⌫, ⇧+flechas (⌘N, ⌘K y ⌘S no: son de macOS) | completo |
| Visor de hoja | Ctrl+flechas, Ctrl+Intro, Ctrl+RePág/AvPág, Ctrl+Inicio/Fin, zoom, F11 | en el editor: ⌘flechas, ⌃⇟ / ⌃⇞ y ⌥⌘→ / ⌥⌘← (hojas), ⌘A; faltan Ctrl+Intro (enlace), zoom y F11 | parcial |
| Plano CAD | Esc, Supr, Ctrl+P, Ctrl+E, I, A, L, F, B, M, T, 3, +/−, flechas | ⎋ (por capas; si no, cierra), ↩, ⌫ (punto o marco), Supr (fn ⌫), ⌘P, ⌘E, ⌘F, I, A, L, F o Inicio, B, M, T, 3, +/−, flechas | completo |
| Modelo 3D | F, B, C, I, L, A, P, T, 1–9, +/−, flechas | ⎋ (aislado, elegido, cierra), F o Inicio, B, C, I, L, A, P, T, 1–9, +/−, flechas, ⌘E | completo |
| Diapositivas y presentar | → ↓ AvPág Intro Espacio / ← ↑ RePág Retroceso P, Inicio/Fin, B o «.», N, T, J L R E M, Esc | las mismas (⇟ ⇞ ↩ ⌫ ↖ ↘), ⇧Espacio atrás, ⌘W/⌘. salir | parcial (faltan J L R E M) |
| Telepronter | Esc, Espacio, Intro, ←→, ↑↓, + / −, RePág/AvPág | igual, y la rueda | hecho (E5) |
| Pronunciar | Espacio mantenido, R, Ctrl+G, ←→, + / −, Esc | igual (⌘G o ⌃G) | hecho (E5) |
| Conversación | Intro, 1–9, 0, Tab, Esc | igual | hecho (E5) |
| Editor de la grabación | Espacio, ←→, Intro, Esc | Espacio, ←→ (⇧ ±1 s), ↩, ⎋; I, O, S, ⌫, Z, V, F, ⌘Z, ⌘S, ⌘C | completo |
| Salida | Esc, Ctrl+C, Intro, ↑↓ | ⎋, ⌘C, ↩, ↑↓ | completo |
| Llamada secreta | Intro contesta, Esc cuelga | igual | hecho (E5) |
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
| `anot-<uid>.comentarios.json` (comentarios de notas) | sí | sí | completo | N/notas/comentarios.rs (D4) |
| `anot-<uid>.asistente.json` | no | no | falta | Se conserva |
| `<dibujo>.marcas` (marcadores del lienzo) | no | no | falta | Es cosa del agente del lienzo |
| `recuerdaEn` (recordatorio en un mensaje) y la llamada secreta | sí (B2) | sí (B2) | parcial | N/chats.rs (`CambioMensaje::Recordar`; quitarla borra la clave). El aviso del sistema se pone al ponerla desde este Mac; el vigía que los vuelve a poner al arrancar y tras sincronizar es A4; la llamada secreta, E5 (hecha: `quién llama` se queda en el Mac, como en el móvil) |
| MINIAPP tareas con `⏰ AAAA-MM-DD HH:MM` | parcial | no | parcial | N/tareas.rs |
| PAGINA, PROYECTO | sí | no | completo | K/Chat/BurbujasQueLlegan.swift, N/burbujas.rs (B9): la página con lo dibujado encima (al abrirla estrena su dibujo en el `proyecto.json` y en el mensaje, como Windows); el proyecto como puerta. Crearlos desde la hoja «+» sigue apagado |
| CROQUIS (`croquis3d/*.croquis.gz`) | sí | no | completo | N/modelos3d.rs, K/Planos/VisorModelo3D.swift (B9). Solo se ve, como en Windows |
| Lecciones (`.leccion`, fotos `respondeA: lec-<id>`) | sí | sí | completo | Las fotos y audios se ven en la ficha (B9, `adjuntos_de_leccion`); ponerlos desde el Mac es de la ficha |
| Lápidas de proyecto (`LapidaDeChat`, `borrarchat`) | sí (preguntando) | sí | completo | N/sincro.rs `sincronizar_preguntando`, `borrar_proyecto`; sin preguntar no se borra nada, como Windows |
| `auto-automatizaciones` | sí | sí | completo | N/automatizaciones.rs (E6): el mismo fichero y el mismo mensaje ARCHIVO que Windows; lo que no se entiende se guarda tal cual |
| `auto-figuras` | no | no | falta | Se conservan |
| `auto-letra-*` (letras SHX) | sí | no | parcial | nucleo/pixpin-cad |
| `sincro/direcciones.txt` | sí | sí | completo | N/aparatos.rs; lo visto en Bonjour se apunta y se prueba antes que el anuncio |
| `sincro/elegidos/<id>` | sí | sí | completo | crate |
| `copias/` | sí | el crate las hace | completo | K/Sincro/VistaCopias.swift, N/copias.rs |
| Ajustes `[sincro]` presencia, automatica, lo_mio_manda | sí | sí | completo | Los tres en Ajustes → Sincronizar (C3) |
| Vuelta automática: al aparecer, 30 s de calma, periodo de 10 min | sí | — | completo | N/sincro_auto.rs (`RelojSincro`), Sincronizador.swift |
| Tareas al instante (`solo_estos`, 600 ms) | sí | — | completo | `Nucleo::sincronizar_tareas`; avisa K/Tareas/Tareas.swift (`pixpinTareasCambiadas`) |
| «Con todos» en 2 rondas | 2 rondas con 3 o más aparatos | — | completo | `rondas_con_todos`, Sincronizador.swift `conTodos` |
| Qué cuenta como «trajo algo» | `trajo`: traídos, fusionados, archivos o borrados | — | completo | `ResumenSincro.trajo` |
| `avisos_de_lo_hecho` | sí | — | completo | Van en `ResumenSincro.avisos` |
| Renombrar el aparato, salir del grupo | sí | sí | completo | N/aparatos.rs (`Disco.renombrar`, `Disco.salirDelGrupo`) |
| Envío por código: archivo, proyecto, lienzo | sí | sí | completo | N/envio.rs, N/recepcion.rs (actualizar o crear, lo que vuelve), N/lienzo_suelto.rs |
| `suelto` / «Enviar a» | sí | sí | parcial | Nunca va al lienzo (`FrenteMac::Lienzo`) |
| Chats compartidos con personas | sí | sí | completo | N/compartidos.rs |
| Timeline | — | — | no aplica | No viaja ni en Windows |
| Pedidos (WM_COPYDATA, `pixpinmax://`, CLI, MCP) | — | — | parcial | Es local, no sincroniza. C2: `pixpinmax://` con el mismo protocolo v1; faltan la CLI y MCP (E8) |

### 3.2 Crates de `nucleo/` frente a `crates/` (diff fichero a fichero)

«Adaptación» quiere decir que el cambio es para el Mac (`cfg(windows)`, `pixpin_sistema` en lugar de `pixpin_shell`, clippy). **«Mac detrás»** quiere decir que Windows ha seguido avanzando y el Mac no lo tiene.

| Crate | Ficheros distintos | Veredicto |
|---|---|---|
| pdfsqueeze-core, pixpin-geom, pixpin-hojas, pixpin-lecciones, pixpin-model, pixpin-nivel, pixpin-office, **pixpin-sincro**, pixpin-timeline, pixpin-tinta, pixpin-ui | 0 | iguales |
| pixpin-bim | `civil.rs`, `examples/ver3d.rs` | adaptación (clippy) |
| pixpin-cad | 19 cambiados, y `enganche.rs` y `orbita.rs` nuevos | adaptación: `ventana`, `gpu3d` y `texto` tras `cfg(windows)`; la órbita sale de `ventana3d`; búferes `#[repr(C)]` para Metal; `letras.rs` por hilo |
| pixpin-codec | `imagen.rs`, `vista.rs`, `wic.rs`, `portapapeles*.rs`, `lib.rs`, `Cargo.toml`; `portapapeles/fuera_de_windows.rs` nuevo | adaptación |
| pixpin-docs | `lib.rs`; `formulas.rs` nuevo | adaptación: `formulas.rs` es copia exacta del de `crates/pixpin-notas` de Windows (A7), sacado aquí porque `pixpin-notas` es de RichEdit; `pixpin-ia` lo usa con el nombre `pixpin-notas` |
| pixpin-proyecto | `almacen.rs` (NFC), `ubicacion.rs`, `formula*.rs`, `mini.rs` (comentarios), `Cargo.toml` | adaptación. **El NFC de `almacen::nombre_seguro` es un arreglo que Windows también necesita** |
| pixpin-store | `ajustes.rs`, `comandos.rs`, `idioma.rs`, `regiones.rs` | adaptación (`pixpin_sistema`) |
| pixpin-store | — | Igual que Windows (A7, 16-oct): traducciones y comentario de `ajustes.rs` |
| pixpin-pdf | `lib.rs`, `aligerar.rs`, `png.rs`, `union.rs`, `Cargo.toml` | adaptación (`cfg(windows)`) |
| pixpin-pdf | `escribir.rs` (una prueba), `letra.rs`, `tests/escribir.rs` | Igual que Windows (A7, 16-oct) salvo la adaptación: sin DirectWrite, `del_sistema` da `None` y las reservas del sistema no encuentran ninguna (Swift pasará las letras de Core Text a `Letra::desde_tablas` y `Reservas::de_letras`) |
| pixpin-motor2d | `tests/asignaciones.rs` | Igual que Windows (16-oct). Solo la prueba de asignaciones cuenta por hilo en el Mac (`cargo test` en paralelo) |
| pixpin-ia | `Cargo.toml`, `lib.rs` (cabecera y `puente`), `nube/claves.rs`, `nube/http.rs`, `servidor.rs`, `descarga.rs`, `acciones.rs` (ruta de `docs/`), `tests/banco.rs` y `tests/calcar_medida.rs` (sin pintor de PDF ni OCR); `puente.rs` nuevo | Igual que Windows (A7, 16-oct) salvo esas adaptaciones. Los arreglos de clippy que tenía el Mac en `fechas`, `svg`, `tareas` e `instrucciones` se dejaron como en Windows |
| por-adaptar/pixpin-voz | `Cargo.toml` | adaptación |
| por-adaptar/pixpin-pila, pixpin-aligerar | 0 | iguales |
| por-adaptar/pixpin-lanzador | 0 | igual (A7, 16-oct) |
| por-traducir/pixpin (la app de referencia) | 54 entradas | **La copia de referencia está vieja**. Le faltan, por ejemplo, `notificaciones.rs`, `orden.rs`, `recibir_de_windows.rs`, `asistente/{ojos,externa,en_el_chat,hoja_a_lienzo,anotar_inteligente}`, `automatizaciones/cola.rs`, `ventana_editor/modo_ventana.rs` y `visor_hoja/capa.rs`. Al traducir, leer siempre `ref/PIXPIN_PRO_WINDOWS` |
| por-traducir/pixpin-shell | 16 (faltan `atajo`, `orden`, `notificacion`, `juntar`, `union`, `impresora`, `compartido`, `consola`) | Una parte se movió a `nucleo/pixpin-sistema` (`atajo`, `union`, `entorno`); lo demás, Mac detrás |
| por-traducir/pixpin-notas | `lib.rs`; falta `formulas.rs` | se movió a pixpin-docs |
| por-traducir/pixpin-render | `superficie.rs` | sin importancia (solo referencia) |

### 3.3 Cambios menores de Windows 43c61a1..8dc471f (fuera del asistente, figuras, carpetas, grabar, Anki y lienzo)

Revisados el 25-oct. Los visores (`lector_pin`, `lector_pdf*`, `visor_hoja*`, `visor_html*`, riel), `plano_cad*`, `compartir/exportable`, `tareas/ventana`, `horario*`, `diapositivas`, `timeline/ventana/historia`, `lecciones/ficha`, `marco_imprimir`, `marcos_doc`, `sincronizar/compartidos_ui`, `pedidos`, `ventana_ajustes`, `hoja_pin*`, `notas_md/lector_web` y `crates/pixpin-hojas` solo cambian por `cargo fmt` (abd763e) y clippy (99f6bb4, d30e8e2, 3255a38): nada que portar. `lector-md.html` es igual al de Windows.

| Commit | Qué | En el Mac |
|---|---|---|
| 98b2a49, db56655 | Hoja: dos fracciones lado a lado no son una tabla sin rayas; la raya fundida con los iguales también es fracción | ya estaba (`nucleo/pixpin-ia`, ad598dd) |
| 5296d45 | Traza `PIXPIN_DIAGRAMA_DEPURAR` de las tablas sin rayas | ya estaba (`nucleo/pixpin-ia`); lo del corrector, no aplica (RichEdit) |
| d447f28, 661b06b | Corrector de RichEdit y prueba de tablas de `pixpin-notas` | no aplica (solo Windows) |
| ed02110, ca887f9, a45a1d1 | Pruebas y CI (asignaciones por hilo, voz SAPI calentada, capas) | no aplica |
| a6593ce | «Figuras…» en la bandeja, detrás de Sincronizar | falta: la bandeja del Mac aún no tiene «Figuras…»; va con la ventana de figuras |
| 1fb6514, ead5ca3 | El panel de propiedades del pin con las medidas del panel compacto (168 × 60) | no aplica: el pin del Mac no tiene panel de propiedades al lado (sigue al panel del lienzo) |
| ba59dd6 (`lector_pin`) | `quitar_barra`: el lienzo sin barra mientras se edita | va con «el lienzo abre mirando» (lienzo) |

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
| A3 ✅ | **Aparatos**: `sincro/direcciones.txt` (recordar y probar antes que Bonjour), renombrar este aparato, salir del grupo, miembros con «hace X» | nuevo N/aparatos.rs, K/Sincro/BuscarPuerta.swift, K/Sincro/Vecinos.swift, nuevo K/Sincro/VistaAparatos.swift (se enlaza desde VistaSincro **después de A1**) |
| A4 ✅ | **Recordatorios**: `recuerdaEn` en el mensaje, el vigía (reprogramar al arrancar y tras sincronizar), notificaciones con «Hecha», «+10 min» y «Abrir»; el `⏰` de las tareas en el núcleo | nuevo N/recordatorios.rs, nuevo K/Recordatorios/{Vigia,Avisos}.swift, N/tareas.rs (solo parsear `⏰`) |
| A5 ✅ | **Copias**: listar y restaurar `copias/`, recuperar proyectos borrados | nuevo N/copias.rs, nuevo K/Sincro/VistaCopias.swift |
| A6 ✅ | **Envío por código completo**: mandar proyectos y lienzos, poner el lienzo suelto en su proyecto, «actualizar o crear», reconocer un archivo que vuelve | N/envio.rs, K/Sincro/EnvioPorCodigo.swift |
| A7 ✅ | ~~**Poner el núcleo al día con Windows (sin el lienzo)**~~ **hecho** (16-oct): `pixpin-ia` (los 10 módulos y lo demás), `pixpin-pdf` (`escribir.rs`, `letra.rs`), `pixpin-store` (traducciones), `pixpin-docs/formulas.rs` y `por-adaptar/pixpin-lanzador`, con sus pruebas (ver §3.2). Queda avisar a Windows del NFC de `almacen::nombre_seguro` | nucleo/pixpin-ia/**, nucleo/pixpin-pdf/src/{escribir,letra}.rs, nucleo/pixpin-store/src/estado.rs, por-adaptar/pixpin-lanzador/** |
| A7b | ~~`pixpin-motor2d` al día~~ **hecho** (16-oct) | nucleo/pixpin-motor2d/** |

### Grupo B: uso diario

| # | Tanda | Ficheros |
|---|---|---|
| B1 ✅ | **Pines persistentes y sus teclas**: guardar y restaurar al arrancar, «restaurar el último», «cerrar todos» en el menú; 1–3, 5–8, 0, N, R/⇧R, H/V, flechas que mueven, ⌘T clic a través, T y ⇧C del OCR | K/Pines/GestorPines.swift, K/Pines/Pin.swift, K/Pines/BarraPin.swift, nuevo K/Pines/AlmacenPines.swift, APP (menú) |
| B2 | ✅ **Menú del mensaje** (hecho): etiquetas, Responder, Copiar, Pinear, Describir, Reenviar, Compartir, Fijar, Renombrar, Hacer lección, Recordar, Abrir con, Guardar esto, Ver comentarios; letras R, ⌘C, P, E, N, T, F, L, F2. Queda Anotar encima (dep. lienzo), Unir PDF, Letra (Exportar/Imprimir un lienzo, hecho en D1) | K/Chat/MenuMensaje.swift, K/Chat/BorrarMensajes.swift, N/chats.rs (`cambiar_mensaje`, `reenviar_mensajes`), N/lecciones.rs (`leccion_de_mensaje`) |
| B3 | ✅ **Caja del chat y la hoja «+»** (hecho; quedan las 5 entradas apagadas de la hoja y la escala de la lista): ⇧↩ para el salto de línea, Esc limpia, hoja «+» con todas las entradas, buscar dentro del chat (⌘F), escala ⌘+ / − / 0 | K/Vistas.swift, K/Chat/CajaEscribir.swift, K/Chat/HojaAdjuntar.swift, K/Chat/BuscarEnChat.swift, K/Chat/EscalaChat.swift |
| B4 | **Tareas editables**: buscar, «Mover a…», borrar con deshacer, F2 para editar, pegar imágenes, ver y poner `⏰`, teclado | K/Tareas/Tareas.swift, N/tareas.rs (**después de A4** o junto a él en `⏰`) |
| B5 | ~~**Timeline editable**~~ Hecho: apuntar texto, foto y voz; pestañas ⌘1…4; ↑ corrige el último; buscar; «Momentos», «Calendario», lecciones; exportar HTML/PDF | K/Timeline/*, N/timeline.rs |
| B6 | ~~**Galería completa**~~ Hecho: buscador (también OCR con Vision), grupos por día, elegir varias, teclado, «Guardar como», mandar a un proyecto, anotar en un lienzo | K/Galeria/*, N/galeria.rs |
| B7 | ~~**Lectores, parte 1**~~ **hecho**: buscar (⌘F, ⌘G / ⇧⌘G), ⌘1…9 para ir al marcador, N negativo, D avance solo, ⌘P imprimir, F2 renombrar, `al_dia` (recargar la tinta) | K/Documentos/LectorDocumento.swift, nuevo K/Documentos/BuscadorLector.swift, N/documentos.rs |
| B8 ✅ | **Captura que falta** (hecho; queda mover el marco del GIF): ⌘A, flechas y Espacio, ⇧ HEX/RGB, ⇧⌘S, ⌫ de la anotación, captura con retardo (cuenta atrás), cuentagotas suelto, ↩ y Esc del GIF | K/Captura/Capturador.swift, K/Captura/VistaCaptura.swift, K/Captura/AnotacionCaptura.swift, K/Captura/GrabadorGif.swift, nuevo K/Captura/CuentaAtras.swift |
| B9 ✅ | ~~**Datos que llegan y no se ven**~~ **hecho** (16-oct): foto anotada del móvil en la burbuja, croquis 3D, fotos de las lecciones, punto de proyecto, PAGINA y PROYECTO con su burbuja; además `vieneDe`, `recibidoDe` y `lienzoIa` debajo de la burbuja. Queda crear página y proyecto desde la hoja «+» | K/Chat/BurbujasQueLlegan.swift, K/Chat/Adjuntos.swift, N/burbujas.rs, N/modelos3d.rs, K/Lecciones/VistaLecciones.swift |

### Grupo C: atajos, integración y ajustes

| # | Tanda | Ficheros |
|---|---|---|
| C1 | ✅ **Atajos globales configurables**: el catálogo de `pixpin-store/comandos.rs` entero, regiones, silenciar atajos, programas ignorados; sección «Atajos» con ⌫ para quitar uno. Hecho (faltan clic a través y restaurar el último pin: los ata el agente de pines con `GestorAtajos.poner`) | K/Captura/AtajoGlobal.swift, K/Ajustes/AtajoDeCaptura.swift, nuevo K/Ajustes/SeccionAtajos.swift, APP |
| C2 ✅ | **Integración con macOS** (hecho, 16-oct; queda la CLI y los pedidos que dice `pedidos`): esquema `pixpinmax://` con los verbos de `docs/integraciones.md` y la firma, más App Intents (tarea, lienzo, grabar, abrir proyecto, al móvil), menú del Dock, imágenes en `CFBundleDocumentTypes`, Servicios del Finder | nuevo K/Pedidos/{Enlaces,Verbos}.swift, XC/App/Intenciones.swift, XC/project.yml, app/Recursos/Info.plist (**APP: después de C1**) |
| C3 ✅ | **Ajustes que faltan**: idioma, Captura (retardo, color, carpeta, GIF y scroll), Voz, pantalla de claves del asistente, Sincro (presencia, «Lo mío manda»), buscador y restablecer. Hecho (16-oct): ventana como la de Windows; faltan Pinear, Lienzo, Cosmos y que scroll/GIF lean su ajuste (§1.4) | K/Ajustes/VistaAjustes.swift, K/Ajustes/ModeloAjustes.swift, nuevo K/Ajustes/FilasAjustes.swift, N/ajustes.rs |
| C4 ✅ | **Notificaciones comunes**: categorías y acciones (`UNNotificationAction`), aviso «se van en 24 h» de la caducidad; que AvisosMini las use | nuevo K/Avisos/CentroAvisos.swift, K/Pines/AvisosMini.swift, K/Caducidad/BarrenderoCapturas.swift (**coordinar con A4**: A4 usa CentroAvisos si ya existe) |

### Grupo D: documentos, compartir y voz

| # | Tanda | Ficheros |
|---|---|---|
| D1 | ✅ **Compartir y exportar común** (hecho): la hoja (HTML, PDF, PNG, JPG, SVG, original, editable, `.pixpin`, texto) con la hoja del Mac en «Más…», la ventanita «Salida» y «Abrir con…»; enganchada al chat (mensaje, lo elegido, Exportar/Imprimir de un lienzo), a los proyectos, al pin y al exportar del lienzo. Queda engancharla en los lectores (`Documentos/*`), el PDF anotado y la web de un documento, Word, enlace y wifi | K/Compartir/{Compartible,PreparadoCompartir,PrepararCompartir,HojaCompartir,Salida,AbrirCon}.swift, N/compartir.rs |
| D2 | ✅ **Leer en voz** (hecho): `AVSpeechSynthesizer`, resaltar el trozo y la palabra, el 🟢, `MPRemoteCommandCenter`, L en el lector, notas (clic derecho) | K/Voz/{LeerEnVoz,VozAlta,MandosSistema}.swift, K/Documentos/{VozDelLector,VozDeLaNota}.swift, K/Documentos/LectorDocumento.swift |
| D3 | ✅ **Audio** (hecho): reproductor global (velocidad, ±saltos, barra de lo que suena, fila, «Está sonando»), biblioteca de audio, reproductor y micrófono flotantes con la hora | K/Voz/{ReproductorVoz,VistasVoz,BibliotecaAudio,FlotantesVoz,GrabadoraVoz}.swift, K/Vistas.swift (la barra y la entrada del menú) |
| D4 ✅ | **Notas Markdown** (hecho, 16-oct): el editor de Windows (su página en un `WKWebView`) con sus atajos, fotos, documentos y audios en la nota, «Del chat», comentarios (`.comentarios.json`, viajan), copia `.md`, Word y compartir. Quedan las páginas vivas y los enlaces a hojas, y saltar al mensaje de un incrustado | K/Documentos/EditorNotaWeb.swift, K/Documentos/EditorNota.swift, N/notas.rs, N/notas/{web,adjuntos,comentarios,vista}.rs |
| D5 ✅ | **Hojas** (hecho, 16-oct): un `.xlsx`, `.ods` o `.csv` del chat se edita como libro con pestañas (todas sus hojas, también las viejas del móvil) y pasa al chat como tablas; rango, formato de lo elegido, deshacer, copiar y pegar, y los atajos de Windows (sin ⌘N, ⌘K ni ⌘S). Queda ver y editar en el mismo pin (Windows) | K/Documentos/HojaCalculo.swift, N/hojas.rs, N/hojas/{editor,libro}.rs |
| D6 ✅ | **Asistente, parte 1** (hecho, 16-oct): los ajustes `[asistente]`, la nube con URLSession (`TransporteApp`), «Probar» la clave, bajar el motor de llama.cpp para macOS y los GGUF, que no quede `llama-server` huérfano, el bucle del agente con pensar, plan, hoja y camino rápido, las acciones de la app (tareas aquí; lo demás por `HacerPedidos`) con «¿seguro?», `buscar_en_mis_cosas` y leer adjuntos; la ventana con conversaciones, adjuntos, lo pensado, el lienzo, la voz y el dictado. Queda E1 | K/Asistente/*, N/asistente.rs, N/asistente/{turno,transporte,local,documentos}.rs, pixpin-ia `nube/http.rs` (el transporte) |
| D7 ✅ | **Grabación** (hecho): marco movible en dos fases con pausa, micrófono y sonido; editor para revisar (bucle, recortar, cortar, velocidad, zoom, MP4/GIF, guardar, copiar o descartar) | K/Grabar/*, nuevo K/Grabar/EditorGrabacion.swift |
| D8 ✅ | ~~**Buscar en todo completo**~~ **hecho**: pestañas, recientes, lecciones y capturas, acciones por fila y su teclado | K/Buscar/Buscar.swift, N/buscar.rs |
| D9 ✅ | **Presentar un PPTX y el visor HTML** (hecho, 16-oct): pase a pantalla completa con pastilla, teclas, negro, notas, transiciones, pase solo, medios y vista del orador en la segunda pantalla; `.html` en `WKWebView` liso que guarda encima. Quedan PPTX → proyecto y `.ppt`/`.odp` | K/Documentos/{Diapositivas,VisorHtml}.swift, N/diapositivas.rs |

### Grupo E: después (menos uso o dependen de otros)

| # | Tanda | Ficheros |
|---|---|---|
| E1 ◐ | Asistente, parte 2 (16-oct): **hecho** en el chat (y viaja), lo pensado con su nota, recetas, «ojos», editar el lienzo abierto o del chat, figuras guardadas, la lista de `@`. **Queda**: hoja→lienzo, anotar documentos, las acciones sobre documentos y las del chat (`en_el_chat`) | K/Asistente/*, K/Vistas.swift, N/asistente/* |
| E2 ✅ | ~~**Planos**~~ **hecho** (16-oct): anotar a mano con el lienzo, exportar (HTML, PDF, PNG, JPG, DXF), buscar en los textos (⌘F), caché `.pxcad` y la de los modelos, letras del plano, luna/sol, vistas 3D guardadas y exportar la vista, y todas las teclas de los dos visores. Quedan: leer en un proceso aparte, que las letras viajen y probarlo con planos y modelos grandes en un Mac real | K/Planos/*, N/planos.rs, N/planos/*, N/modelos3d.rs |
| E3 ✅ | **Anotar la pantalla** (hecho, 16-oct): viva y congelada sobre todas las pantallas con las herramientas del lienzo, pastilla, clic a través (Espacio, ⌘ mantenido, ⌥ + doble clic central), limpiar con deshacer, copiar, y al salir a «Mensajes guardados» con su lienzo editable (puesto al día si se guardó antes). Quedan la lupa viva y meter las imágenes pegadas en la foto | K/Captura/Capturador.swift, nuevo K/Captura/AnotadorPantalla.swift, nuevo N/anotador_al_chat.rs, K/Lienzo/EditorLienzoView.swift (`origenFijo`, `papelTransparente`) |
| E4 | Centro de la barra de menús (panel rico) y grupos de ventanas (**dep. ventanas**) | APP, nuevo K/Bandeja/* |
| E5 ✅ | ~~**Telepronter, Pronunciar, conversación por turnos y llamada secreta**~~ **hecho** (16-oct): las cuatro ventanitas de Windows con su teclado, lo grabado al chat (`adjuntarGrabacion`), la conversación pasada a texto con nombres y la llamada desde el vigía con «quién llama» y «Volver a llamar en». Queda la Letra (abrir la lectura y corregirla) y una salida de llamadas aparte en el Mac | K/VozVentanas/*, N/{llamada,turnos,voz}.rs |
| E6 ✅ | **Automatizaciones** (hecho, 16-oct): el fichero `auto-automatizaciones` de Windows (viaja), los cuatro disparadores, los pasos con variables, sin bucles y con su tope, el pedido `automatizacion`, y una ventana con la lista de Windows, un editor y el historial. Queda la cola de encargos del asistente | N/automatizaciones.rs, K/Automatizaciones/*, K/Pedidos/HacerPedidos.swift, APP |
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
