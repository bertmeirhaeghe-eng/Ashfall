# Dutch Piper voices (not in git)

When Ashfall is played in Dutch (Options > Language > Nederlands) the characters speak with six
Piper voices trained on Dutch speech: `nl_BE-nathalie-medium`, `nl_NL-dii-high`, `nl_NL-pim-medium`,
`nl_NL-ronnie-medium`, `nl_NL-miro-high` and `nl_BE-rdh-medium` (MIT / CC licensed, see each
voice's `MODEL_CARD`). Run `tools/get_piper_voices.ps1` (Windows) or `tools/get_piper_voices.sh`
(Linux / macOS) from the project folder, or download the `vits-piper-<voice>.tar.bz2` archives from

https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models

and extract them here. This folder should then contain one `vits-piper-<voice>/` folder per voice
(with `<voice>.onnx` and `tokens.txt`) and an `espeak-ng-data/` folder (one shared copy is enough).
The `.gdignore` keeps Godot from importing them.

The voices are played through `godot_piper.gdextension` (the PiperTTS class, built for Windows and
Linux; source in `../piper_src`). Without them, Dutch is spoken by Kokoro with Dutch pronunciation.
For exported builds, put the same files in a `piper_voices/` folder next to the game executable.
