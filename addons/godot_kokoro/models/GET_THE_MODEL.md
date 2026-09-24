# Kokoro model files (not in git)

Ashfall's voices use **kokoro-int8-multi-lang-v1_0** (Kokoro v1.0, 54 voices, ~132 MB download).
Run `tools/get_kokoro_model.ps1` (Windows) or `tools/get_kokoro_model.sh` (Linux / macOS) from the
project folder, or download and extract it here by hand:

https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2

This folder should then contain `model.int8.onnx`, `voices.bin`, `tokens.txt`, `lexicon-us-en.txt`,
`espeak-ng-data/` and `dict/`. The `.gdignore` keeps Godot from importing them.

For exported builds, put the same files in a `kokoro_models/` folder next to the game executable.
