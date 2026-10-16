# PixPin Max Pro para Mac

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

Cada cambio compila la app en un Mac de GitHub (`.github/workflows/apple.yml`), pasa las
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
| [`apple/app/`](apple/app) | La app de Mac (SwiftPM) y sus 190 pruebas. |
| [`apple/xcode/`](apple/xcode) | El proyecto de Xcode (XcodeGen) con las extensiones. |
| [`apple/herramientas/`](apple/herramientas) | `xcframework.sh` (núcleo → xcframework) y `app.sh` (monta y firma la app). |
| [`apple/por-adaptar/`, `apple/por-traducir/`](apple) | Referencia de Windows aún sin pasar (no se compila aquí). |
| [`docs/investigacion/`](docs/investigacion) | El plan: evaluación, herramientas de Apple, sincronización y fases. |

## Compilar en un Mac

```sh
cd apple
herramientas/xcframework.sh        # núcleo de Rust -> PixPinCore (necesita Xcode y rustup)
cd app && swift test && cd ..      # pruebas de la app
herramientas/app.sh                # PixPin.app (con extensiones si hay xcodegen)
```

## Sincronizar con Windows y Android

El formato de proyectos y el protocolo de sincronización tienen que seguir siendo idénticos a
los de Windows y Android: un arreglo en `pixpin-sincro` o `pixpin-proyecto` se lleva también al
repositorio de Windows. Lo que no se puede sincronizar está en el plan (§5).
