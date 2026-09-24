#!/usr/bin/env bash
# Downloads the Kokoro voice model used by Ashfall into addons/godot_kokoro/models/.
# Run from the project folder:  bash tools/get_kokoro_model.sh
set -euo pipefail
NAME=kokoro-int8-multi-lang-v1_0
URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$NAME.tar.bz2
DEST="$(cd "$(dirname "$0")/.." && pwd)/addons/godot_kokoro/models"
TMP="$(mktemp -d)"
echo "Downloading $NAME (~132 MB)..."
curl -fL --progress-bar -o "$TMP/$NAME.tar.bz2" "$URL"
echo "Extracting..."
tar -xjf "$TMP/$NAME.tar.bz2" -C "$TMP"
mkdir -p "$DEST"
cp -R "$TMP/$NAME/." "$DEST/"
rm -rf "$TMP"
echo "Kokoro model installed in $DEST"
