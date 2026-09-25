#!/usr/bin/env bash
# Downloads the six Dutch Piper voices used when Ashfall is played in Dutch
# (Nederlands) into addons/godot_kokoro/piper/.  ~390 MB on disk.
# Run from the project folder:  bash tools/get_piper_voices.sh
set -euo pipefail
VOICES="nl_BE-nathalie-medium nl_NL-dii-high nl_NL-pim-medium nl_NL-ronnie-medium nl_NL-miro-high nl_BE-rdh-medium"
BASE=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models
DEST="$(cd "$(dirname "$0")/.." && pwd)/addons/godot_kokoro/piper"
TMP="$(mktemp -d)"
mkdir -p "$DEST"
for V in $VOICES; do
  echo "Downloading $V..."
  curl -fL --progress-bar -o "$TMP/$V.tar.bz2" "$BASE/vits-piper-$V.tar.bz2"
  tar -xjf "$TMP/$V.tar.bz2" -C "$TMP"
  rm "$TMP/$V.tar.bz2"
  D="$TMP/vits-piper-$V"
  # one shared copy of the phoneme data is enough
  if [ ! -d "$DEST/espeak-ng-data" ]; then cp -R "$D/espeak-ng-data" "$DEST/"; fi
  rm -rf "$D/espeak-ng-data" "$DEST/vits-piper-$V"
  mv "$D" "$DEST/"
done
rm -rf "$TMP"
echo "Dutch voices installed in $DEST"
