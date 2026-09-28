#!/usr/bin/env bash
# Construit « Ollama Chat.app » dans OllamaChat/build/.
#
#   ./scripts/build-app.sh               pour l’architecture de ce Mac
#   UNIVERSAL=1 ./scripts/build-app.sh   Apple Silicon + Intel (nécessite Xcode complet)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Ollama Chat"
EXECUTABLE="OllamaChat"
APP_DIR="build/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compilation…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assemblage de $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/fr.lproj"
cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

make_icon() {
  local work
  work="$(mktemp -d)"
  local iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset" || return 1
  swift scripts/make-icon.swift "$work/icon.png" || return 1
  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null || return 1
    sips -z "$((size * 2))" "$((size * 2))" "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null || return 1
  done
  iconutil -c icns "$iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns" || return 1
  rm -rf "$work"
}

echo "==> Icône…"
make_icon || echo "    Icône non générée : l’application utilisera l’icône par défaut."

echo "==> Signature ad hoc…"
codesign --force --sign - "$APP_DIR"

echo
echo "Terminé : $PWD/$APP_DIR"
echo "Glissez l’application dans le dossier Applications, ou lancez-la avec : open \"$APP_DIR\""
