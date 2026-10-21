#!/bin/zsh
# **Sube la rama y la release a GitHub** (1xmanMAX/PIXPIN_PRO_MAC).
#
#   herramientas/subir-release.sh            # la version de abajo, como pre-release
#   PIXPIN_VERSION=0.3.0 PIXPIN_ESTABLE=1 herramientas/subir-release.sh
#
# Necesita la sesion de GitHub iniciada una vez:
#   ~/bin/gh auth login -h github.com -p https -w
# Monta la app con esa version (app.sh), sube `mac-desarrollo`, crea el tag
# `v<version>` y la release con el instalador PixPin-Mac-<version>.dmg y las notas de
# docs/releases/v<version>.md.
set -euo pipefail

VERSION="${PIXPIN_VERSION:-0.2.0}"
REPO="1xmanMAX/PIXPIN_PRO_MAC"
RAMA="mac-desarrollo"
GH="${GH:-$(command -v gh || echo "$HOME/bin/gh")}"
APPLE="$(cd "$(dirname "$0")/.." && pwd)"
RAIZ="$(cd "$APPLE/.." && pwd)"
NOTAS="$RAIZ/docs/releases/v$VERSION.md"
ZIP="$APPLE/app/dist/PixPin-mac.zip"
DMG="$APPLE/app/dist/PixPin-Mac-$VERSION.dmg"

[[ -x "$GH" ]] || { echo "Falta gh: descargalo en ~/bin/gh (ver README)"; exit 1; }
"$GH" auth status -h github.com >/dev/null 2>&1 || {
    echo "Primero inicia sesion: $GH auth login -h github.com -p https -w"; exit 1; }
[[ -f "$NOTAS" ]] || { echo "Faltan las notas: $NOTAS"; exit 1; }

cd "$RAIZ"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Hay cambios sin guardar en git: haz commit antes."; git status --short; exit 1
fi

echo "==> Montando PixPin $VERSION"
(cd "$APPLE" && PIXPIN_VERSION="$VERSION" herramientas/app.sh spm)
[[ -d "$APPLE/app/dist/PixPin.app" ]] || { echo "No salio PixPin.app"; exit 1; }

# **El instalador**: un .dmg con PixPin y un acceso a Aplicaciones (se
# arrastra), no un comprimido.
echo "==> Instalador $DMG"
DIR="$(mktemp -d)/PixPin"
mkdir -p "$DIR"
ditto "$APPLE/app/dist/PixPin.app" "$DIR/PixPin.app"
ln -s /Applications "$DIR/Aplicaciones"
rm -f "$DMG"
hdiutil create -volname "PixPin $VERSION" -srcfolder "$DIR" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$(dirname "$DIR")"

echo "==> Subiendo $RAMA"
"$GH" auth setup-git -h github.com
git push -u origin "$RAMA"

TAG="v$VERSION"
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "PixPin Max Pro para Mac $VERSION"
fi
git push origin "$TAG"

echo "==> Release $TAG"
EXTRA=(--prerelease)
[[ -n "${PIXPIN_ESTABLE:-}" ]] && EXTRA=()
if "$GH" release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    "$GH" release upload "$TAG" "$DMG" -R "$REPO" --clobber
    "$GH" release edit "$TAG" -R "$REPO" --notes-file "$NOTAS"
else
    "$GH" release create "$TAG" "$DMG" -R "$REPO" --target "$RAMA" \
        --title "PixPin Max Pro para Mac $VERSION" --notes-file "$NOTAS" "${EXTRA[@]}"
fi
echo "==> Listo: https://github.com/$REPO/releases/tag/$TAG"
