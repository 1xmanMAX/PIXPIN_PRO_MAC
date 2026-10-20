# PixPin Max Pro para Mac

## ¿Qué es PixPin?

**PixPin Max** es una app para **capturar, anotar y organizar** todo lo que haces en la
pantalla. Las capturas se convierten en **pines flotantes** encima de las demás ventanas.
Cada proyecto es un **chat** donde se guardan fotos, notas, documentos, planos, lienzos y
notas de voz. Todo funciona **sin cuentas ni servidores**: los aparatos se sincronizan
directamente por la red Wi‑Fi de casa.

### La familia PixPin

| Versión | Repositorio | Estado |
|---|---|---|
| 🪟 **Windows** | [PIXPIN_PRO_WINDOWS](https://github.com/1xmanMAX/PIXPIN_PRO_WINDOWS) | La versión de referencia (Rust). |
| 🤖 **Android** | [PIXPIN_PRO_ANDROID](https://github.com/1xmanMAX/PIXPIN_PRO_ANDROID) | Captura, anota y fija notas flotantes en el móvil. |
| 🍎 **Mac** | este repositorio | Port nativo (Rust + Swift), sincronizado con los otros dos. |

Las tres usan **el mismo protocolo de sincronización y el mismo formato de carpetas**. Un
proyecto, una nota, una tinta o un marcador hecho en un aparato aparece en los demás.

### Funciones principales

- **Captura y pines**: captura de zona o de ventana, pines flotantes siempre encima, OCR
  (texto de la imagen), lupa, regla, colores y anotar encima.
- **Proyectos como chats**: fotos, archivos, notas con formato, listas de tareas, tablas,
  notas de voz con transcripción, croquis y lienzos, con búsqueda en todo.
- **Lienzo** (estilo Excalidraw): lápiz, marcador, formas, flechas, texto, fórmulas, capas
  e imágenes, con las mismas herramientas en todos los visores.
- **Visores sin bordes**, con una barra flotante común y un **riel lateral** con lápiz,
  marcadores y marcos numerados para imprimir:
  - PDF, Word, PowerPoint y EPUB, con **lectura en voz alta**.
  - Excel y CSV, con fórmulas y formato.
  - HTML y Markdown.
  - **Planos CAD** (DWG/DXF) y **modelos BIM/IFC** en 3D.
- **Tareas** con urgencia, etiquetas, fechas escritas a mano, Kanban y avisos; **horario de
  clases** que te llama.
- **Asistente de IA**: herramientas sobre tus documentos, tablas desde una foto y la
  **hoja → lienzo** que calca una hoja escrita a mano.
- **Galería y Timeline** de todo lo capturado; **modo noche** común a todos los visores.
- **Sincronización local** con Windows y Android por Wi‑Fi, sin la nube.

## Esta versión (Mac)

La versión de **Mac** de PixPin Max: capturas, pines flotantes, chats de proyecto, lienzo,
notas, documentos, planos y modelos 3D, sincronizada con **Windows y Android** por la red
local con el mismo protocolo y el mismo formato de carpetas. Después vendrán iPad e iPhone.

- Núcleo en **Rust** (`apple/nucleo/`): el mismo código que la versión de Windows
  ([PIXPIN_PRO_WINDOWS](https://github.com/1xmanMAX/PIXPIN_PRO_WINDOWS)), compilado como
  `PixPinCoreFFI.xcframework` y llamado desde Swift con UniFFI.
- App nativa en **Swift** (`apple/app/`): SwiftUI y AppKit, ScreenCaptureKit, Vision, PDFKit,
  AVFoundation, Metal, Bonjour. macOS 15 o posterior, Apple Silicon e Intel.
- Extensiones (`apple/xcode/`): Siri y Atajos (App Intents), Compartir y Quick Look.

## Descargar y probar

**Lo más fácil: Releases.** En [Releases](https://github.com/1xmanMAX/PIXPIN_PRO_MAC/releases)
está la última versión, **PixPin-mac.zip** (Apple Silicon e Intel). Se descomprime, se mueve
**PixPin.app** a **Aplicaciones** y se sigue desde el paso 3 de abajo. Lo nuevo de cada versión
está en [`docs/releases/`](docs/releases).

También, cada cambio compila la app en un Mac de GitHub (`.github/workflows/apple.yml`), pasa las
pruebas, comprueba que arranca y deja la app para descargar:

1. **Actions** > la última ejecución verde de **Apple** > **Artifacts** >
   **PixPin-mac-extensiones** (la app completa). Hay que tener la sesión de GitHub iniciada.
2. Descomprimir dos veces hasta tener **PixPin.app** y moverla a **Aplicaciones**.
3. Abrirla con doble clic. macOS la bloquea la primera vez (aún no está firmada con cuenta
   de Apple Developer): **Ajustes del Sistema > Privacidad y seguridad**, bajar hasta
   **Seguridad** y pulsar **Abrir igualmente**. O, en el Terminal:
   `xattr -dr com.apple.quarantine /Applications/PixPin.app`
4. Al capturar por primera vez, dar el permiso de **Grabación de pantalla** y volver a
   abrir PixPin.

PixPin vive también en la **barra de menús** (arriba a la derecha), como la bandeja de
Windows; al abrirla sale la ventana de Proyectos.

## Qué hay aquí

| Carpeta | Qué es |
|---|---|
| [`apple/`](apple) | Todo lo de Apple; su [README](apple/README.md) explica las zonas, las reglas y lo que falta. |
| [`apple/nucleo/`](apple/nucleo) | Los crates de Rust que compilan fuera de Windows y el puente `pixpin-nucleo`. |
| [`apple/app/`](apple/app) | La app de Mac (SwiftPM) y sus 555 pruebas. |
| [`apple/xcode/`](apple/xcode) | El proyecto de Xcode (XcodeGen) con las extensiones. |
| [`apple/herramientas/`](apple/herramientas) | `xcframework.sh` (núcleo → xcframework), `app.sh` (monta y firma la app), `registrar-navegador.sh` (extensión del navegador) y `subir-release.sh` (sube la rama y la release). |
| [`apple/extension-navegador/`](apple/extension-navegador) | La extensión de Chrome que habla con PixPin por `pixpin-puente`. |
| [`docs/releases/`](docs/releases) | Las notas de cada versión. |
| [`apple/por-adaptar/`, `apple/por-traducir/`](apple) | Referencia de Windows aún sin pasar (no se compila aquí). |
| [`docs/investigacion/`](docs/investigacion) | El plan: evaluación, herramientas de Apple, sincronización y fases. |

## Compilar en un Mac

```sh
cd apple
herramientas/xcframework.sh        # núcleo de Rust -> PixPinCore (necesita Xcode y rustup)
cd app && swift test && cd ..      # pruebas de la app
herramientas/app.sh                # PixPin.app (con extensiones si hay xcodegen)
```

## Qué trae (resumen)

- **Capturas y pines**: zona, ventana, pantalla, texto (Live Text), en vivo, anotar encima;
  pines flotantes con su barra, marcas sobre el texto, Live Text.
- **Visores como pin**, todos con la misma barra que en Windows (asa, tipo y nombre, botones
  propios, luna/sol, pantalla completa, fijar y cerrar), sin bordes, y **⎋**: a pantalla
  completa sale de ella, si no cierra:
  - **PDF, Word y PowerPoint** (paginados), **EPUB y Word reflujados**: abren para leer; el
    **lápiz** pasa a anotar con **las herramientas del lienzo** (su barra y su panel de
    estilo); **leer en voz alta** con la palabra resaltada, marcadores, desplazar sola.
  - **Excel/CSV**: abre para ver; el lápiz trae la barra de fórmulas y el formato.
  - **Markdown**: leer o escribir (lápiz/ojo), comentarios, buscar, voz.
  - **HTML**, **planos CAD** (DXF, DWG…) con medir, marcos y anotar, **modelos BIM/IFC** en 3D,
    el **pin de Office** (Quick Look) y el **lienzo**.
- **Chats de proyecto** con lienzo, notas, tareas (urgencia, etiquetas, Kanban), horario de
  clases que llama, asignaturas como listas, Google Calendar (solo ver), galería, timeline,
  lecciones y búsqueda.
- **Asistente** con Claude o DeepSeek: herramientas sobre documentos, hoja → lienzo con
  supervisor, tablas desde una foto, conexiones (Google Drive, Calendar).
- **MCP** (`docs/mcp.md`) y **extensión del navegador**.
- **Sincronización** por la red local con Windows y Android, y envío a los aparatos del grupo.

## Subir una versión

Con la sesión de GitHub iniciada (`~/bin/gh auth login -h github.com -p https -w`):

```sh
cd apple
herramientas/subir-release.sh          # sube mac-desarrollo, crea el tag y la release con el .zip
```

## Sincronizar con Windows y Android

El formato de proyectos y el protocolo de sincronización tienen que seguir siendo idénticos a
los de Windows y Android: un arreglo en `pixpin-sincro` o `pixpin-proyecto` se lleva también al
repositorio de Windows. Lo que no se puede sincronizar está en el plan (§5).
