# PiperTTS GDExtension (source)

A tiny GDExtension (`PiperTTS`, a RefCounted) that renders speech with Piper / VITS voices through
the sherpa-onnx C API that godot-kokoro already ships in `../bin`. Ashfall uses it for the Dutch
voices. API: `load_model(model, tokens, espeak_data_dir, threads) -> bool`, `generate(text, speed,
speaker_id) -> PackedByteArray` (16-bit mono PCM), `get_sample_rate()`, `is_loaded()`, `unload()`.
`generate` is synchronous; `scripts/voice.gd` calls it on a worker thread.

To rebuild: put a godot-cpp checkout (built for your platform) in `godot-cpp/`, the sherpa-onnx
`include/` and libraries in `sherpa-onnx/` (Linux: `lib/libsherpa-onnx-c-api.so`, Windows:
`lib/win/sherpa-onnx-c-api.dll`), then run `build.sh` (Linux host, mingw-w64 for the Windows DLL).
Copy `bin/*` to `addons/godot_kokoro/bin/`.
