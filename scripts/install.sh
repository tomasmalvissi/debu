#!/bin/zsh
# Compila Debu en modo Release y lo copia a /Applications.
# Uso (desde la carpeta del repo):  ./scripts/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO/build"
APP_NAME="Debu.app"

# Usa el Xcode instalado aunque la terminal apunte a las Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "→ Compilando Debu (Release)…"
xcodebuild -project "$REPO/Debu.xcodeproj" -scheme Debu -configuration Release \
  -derivedDataPath "$BUILD_DIR" CODE_SIGN_IDENTITY=- -quiet build

# Si Debu está abierto, se cierra antes de reemplazarlo.
if pgrep -xq Debu; then
  echo "→ Cerrando Debu…"
  osascript -e 'tell application "Debu" to quit' || true
  sleep 2
fi

echo "→ Copiando a /Applications…"
rm -rf "/Applications/$APP_NAME"
cp -R "$BUILD_DIR/Build/Products/Release/$APP_NAME" "/Applications/$APP_NAME"

echo "✓ Listo. Abrilo desde Aplicaciones o con: open /Applications/Debu.app"
