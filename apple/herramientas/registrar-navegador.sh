#!/usr/bin/env bash
# Registra el puente de la extension del navegador (`pindesk-puente`, dentro
# de PinDesk.app, o de la PixPin.app de antes) como «host» de mensajeria nativa de Chrome, Edge, Brave y
# Chromium, solo para este usuario (el `registrar-navegador.ps1` de
# Windows). La extension es `apple/extension-navegador` (la misma de
# Windows; su id es fijo porque su manifest.json lleva "key").
#
#     apple/herramientas/registrar-navegador.sh            # registrar
#     apple/herramientas/registrar-navegador.sh --quitar   # quitarlo
#
# Para cargar la extension: chrome://extensions → «Modo de desarrollador» →
# «Cargar descomprimida» → la carpeta apple/extension-navegador.
set -euo pipefail

HOST=com.pixpinmax.puente
ID=hcbhbfnjmdofjkdgeljognmjgppdiflo
# PinDesk.app y, si no esta, la PixPin.app de antes (como Windows prueba
# pindesk.exe y luego pixpinmax.exe). El HOST no cambia: lo lleva la extension.
PUENTE="${PINDESK_PUENTE:-${PIXPIN_PUENTE:-}}"
if [ -z "$PUENTE" ]; then
    for p in /Applications/PinDesk.app/Contents/MacOS/pindesk-puente \
             /Applications/PinDesk.app/Contents/MacOS/pixpin-puente \
             /Applications/PixPin.app/Contents/MacOS/pixpin-puente; do
        if [ -x "$p" ]; then PUENTE="$p"; break; fi
    done
    PUENTE="${PUENTE:-/Applications/PinDesk.app/Contents/MacOS/pindesk-puente}"
fi
CARPETAS=(
    "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
)

if [ "${1:-}" = "--quitar" ]; then
    for c in "${CARPETAS[@]}"; do rm -f "$c/$HOST.json"; done
    echo "Quitado."
    exit 0
fi

[ -x "$PUENTE" ] || { echo "No esta el puente en $PUENTE (instala PinDesk.app)" >&2; exit 1; }
for c in "${CARPETAS[@]}"; do
    # Solo en los navegadores que estan instalados (su carpeta de datos).
    [ -d "$(dirname "$c")" ] || continue
    mkdir -p "$c"
    cat > "$c/$HOST.json" <<JSON
{
  "name": "$HOST",
  "description": "PinDesk: la extension del navegador habla con la app",
  "path": "$PUENTE",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$ID/"]
}
JSON
    echo "Registrado en $c"
done
