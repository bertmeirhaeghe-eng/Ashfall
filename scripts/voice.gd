extends Node
## Every in-game voice goes through here (autoload "Voice"): briefings,
## mission dialogue, the Bastion EVA and unit reactions.
##
## Every line is written in English and translated (tr) into the language
## chosen in Options before it is spoken and subtitled.
##
## English, in order of preference:
##  1. Kokoro TTS (neural voices) through the godot-kokoro GDExtension in
##     addons/godot_kokoro, when its model files are installed. Every character
##     and unit type has its own Kokoro voice.
##  2. The platform text-to-speech engine (DisplayServer.tts_*).
##  3. Subtitles only, paced by an estimated duration (headless, no engine).
## Dutch (Nederlands):
##  1. Piper voices trained on Dutch speech (PiperTTS, addons/godot_kokoro/
##     godot_piper.gdextension), when the voices are installed.
##  2. Kokoro reading Dutch phonemes (espeak-ng "nl"): understandable, accented.
##  3. The platform engine with a Dutch voice, then subtitles only.
## Rendered lines are cached in user://voice_cache so each is synthesised once.

signal line_started(speaker: String, speaker_name: String, text: String, color: Color)
signal line_finished(speaker: String)
signal queue_empty

enum Prio { ACK = 0, EVA = 1, DIALOG = 2 }

## Character voice profiles. gender picks from the installed voices (f/m/any).
const SPEAKERS := {
	"narrator": {"name": "Narrator", "gender": "m", "pitch": 0.85, "rate": 0.9, "color": Color(0.85, 0.8, 0.7)},
	"okafor": {"name": "General Okafor", "gender": "f", "pitch": 0.9, "rate": 0.92, "color": Color(0.95, 0.8, 0.35)},
	"havel": {"name": "Lt. Havel", "gender": "any", "pitch": 1.05, "rate": 1.08, "color": Color(0.5, 0.85, 1.0)},
	"lindqvist": {"name": "Dr. Lindqvist", "gender": "m", "pitch": 1.1, "rate": 1.12, "color": Color(0.6, 1.0, 0.7)},
	"rourke": {"name": "Colonel Rourke", "gender": "m", "pitch": 0.7, "rate": 0.95, "color": Color(1.0, 0.55, 0.3)},
	"oriel": {"name": "Mother Oriel", "gender": "f", "pitch": 1.0, "rate": 0.82, "color": Color(0.9, 0.5, 0.9)},
	"kestrel": {"name": "Kestrel Ruiz", "gender": "f", "pitch": 0.8, "rate": 1.05, "color": Color(1.0, 0.4, 0.35)},
	"sibyl": {"name": "SIBYL", "gender": "f", "pitch": 1.45, "rate": 0.78, "color": Color(0.5, 1.0, 0.6)},
	"tallow": {"name": "Tallow", "gender": "m", "pitch": 0.6, "rate": 0.88, "color": Color(0.7, 0.95, 0.5)},
	"eva": {"name": "Bastion EVA", "gender": "f", "pitch": 1.0, "rate": 1.1, "color": Color(0.6, 0.9, 1.0)},
	"veil_radio": {"name": "Veil Radio", "gender": "m", "pitch": 0.8, "rate": 1.0, "color": Color(1.0, 0.35, 0.3)},
	"pilot": {"name": "Kite Pilot", "gender": "m", "pitch": 1.0, "rate": 1.15, "color": Color(0.7, 0.8, 1.0)},
	"sergeant": {"name": "Garrison Sergeant", "gender": "m", "pitch": 0.85, "rate": 1.15, "color": Color(0.75, 0.85, 0.7)},
	"civilian": {"name": "Civilian", "gender": "f", "pitch": 1.15, "rate": 1.2, "color": Color(0.9, 0.85, 0.75)},
	"engineer": {"name": "Field Engineer", "gender": "m", "pitch": 1.1, "rate": 1.15, "color": Color(0.95, 0.85, 0.4)},
	"outcast": {"name": "Outcast Scout", "gender": "m", "pitch": 0.7, "rate": 0.95, "color": Color(0.6, 0.9, 0.5)},
}

## Unit reaction sets (C&C style): what a unit says when selected, moved and ordered to attack.
const ACKS := {
	"infantry": {"gender": "m", "pitch": 1.0, "rate": 1.2,
		"select": ["Reporting.", "Yes, Commander?", "Standing by.", "Orders?"],
		"move": ["Moving out.", "On our way.", "Double time!", "Acknowledged."],
		"attack": ["Engaging!", "Open fire!", "Target sighted.", "Taking them down."]},
	"engineer": {"gender": "m", "pitch": 1.15, "rate": 1.2,
		"select": ["Engineer here.", "Toolkit ready.", "What needs fixing?"],
		"move": ["On it.", "Heading over.", "Mind the wiring."],
		"attack": ["I'm not a soldier!", "Leave that to the grunts."]},
	"medic": {"gender": "f", "pitch": 1.1, "rate": 1.15,
		"select": ["Medic.", "Who's hurt?", "Field kit ready."],
		"move": ["Coming through.", "On my way.", "Keep your heads down."],
		"attack": ["I patch them up, I don't shoot them."]},
	"skyjumper": {"gender": "m", "pitch": 1.05, "rate": 1.25,
		"select": ["Skyjumper ready.", "Jets hot.", "Where to?"],
		"move": ["Going up!", "Airborne.", "Jumping!"],
		"attack": ["Dropping in!", "From above!", "Hit them hard!"]},
	"harvester": {"gender": "m", "pitch": 0.85, "rate": 1.0,
		"select": ["Harvester.", "Ready to harvest.", "Hauling crystal."],
		"move": ["Rolling.", "Heading out.", "Moving the load."],
		"attack": ["No weapons on this rig."]},
	"mcv": {"gender": "m", "pitch": 0.8, "rate": 0.95,
		"select": ["M C V ready.", "Mobile construction standing by.", "Where do we set up?"],
		"move": ["Relocating.", "Moving the M C V.", "Rolling out, slowly."],
		"attack": ["We build, not fight."]},
	"pathfinder": {"gender": "f", "pitch": 1.15, "rate": 1.25,
		"select": ["Pathfinder online.", "Eyes forward.", "Scout ready."],
		"move": ["Scouting ahead.", "Moving fast.", "On the trail."],
		"attack": ["Guns hot!", "Target locked!", "Light them up!"]},
	"walker": {"gender": "m", "pitch": 0.7, "rate": 0.95,
		"select": ["Warden walker.", "Heavy armor ready.", "Systems green."],
		"move": ["Advancing.", "Walker moving.", "Stomping forward."],
		"attack": ["Main gun ready!", "Firing!", "Target destroyed soon."]},
	"sensor": {"gender": "f", "pitch": 1.2, "rate": 1.15,
		"select": ["Sensor array online.", "Scanning.", "I see what they hide."],
		"move": ["Repositioning sensors.", "Moving the array.", "Keep me covered."],
		"attack": ["No weapons, Commander."]},
	"hover": {"gender": "m", "pitch": 1.05, "rate": 1.2,
		"select": ["Tempest ready.", "Hover skirts up.", "Rockets loaded."],
		"move": ["Skimming out.", "Hovering over.", "Water's no problem."],
		"attack": ["Rockets away!", "Salvo!", "Target painted."]},
	"apc": {"gender": "m", "pitch": 0.9, "rate": 1.1,
		"select": ["A P C here.", "Room for five.", "All aboard?"],
		"move": ["Transporting.", "Rolling out.", "Hold on back there."],
		"attack": ["Gunner, engage!", "Covering fire!"]},
	"resonator": {"gender": "f", "pitch": 0.85, "rate": 1.0,
		"select": ["Resonator tuned.", "Frequency set.", "Ready to sing."],
		"move": ["Moving the emitter.", "Repositioning.", "Advancing."],
		"attack": ["Shatter them!", "Resonance rising!", "Full volume!"]},
	"bulwark": {"gender": "m", "pitch": 0.55, "rate": 0.85,
		"select": ["Bulwark standing.", "Nothing gets past me.", "Heavy guns ready."],
		"move": ["The Bulwark advances.", "Clear the road.", "Moving."],
		"attack": ["Crush them!", "Main battery, fire!", "Break their line!"]},
	"kite": {"gender": "f", "pitch": 1.1, "rate": 1.25,
		"select": ["Kite pilot here.", "Rotors spinning.", "Airborne and ready."],
		"move": ["Vectoring.", "In flight.", "Changing course."],
		"attack": ["Attack run!", "Missiles away!", "Diving in!"]},
	"veil_vehicle": {"gender": "m", "pitch": 0.9, "rate": 1.1,
		"select": ["For Kestrel.", "Veil crew ready.", "What now?"],
		"move": ["Moving.", "On the road.", "Fast and quiet."],
		"attack": ["Hit them!", "For the fallen!", "Engaging."]},
	"shade": {"gender": "f", "pitch": 0.9, "rate": 1.0,
		"select": ["Shade tank. Unseen.", "In the dark.", "Waiting."],
		"move": ["Slipping away.", "Cloaked and moving.", "Silent running."],
		"attack": ["Out of the shadows!", "They never saw us.", "Strike!"]},
	"drill": {"gender": "m", "pitch": 0.75, "rate": 1.05,
		"select": ["Cinder Drill.", "Burners lit.", "Ready to dig."],
		"move": ["Going under.", "Tunneling.", "Beneath their feet."],
		"attack": ["Burn it!", "Surfacing!", "Fire in the hole!"]},
	"mole": {"gender": "m", "pitch": 0.85, "rate": 1.05,
		"select": ["Mole here.", "Shelter ready.", "Room below."],
		"move": ["Digging.", "Underground route.", "Moving."],
		"attack": ["We don't fight, we dig."]},
	"cyborg": {"gender": "f", "pitch": 1.3, "rate": 0.95,
		"select": ["Unit ready.", "Awaiting input.", "Linked."],
		"move": ["Relocating.", "Path computed.", "Moving."],
		"attack": ["Hostile marked.", "Eliminating.", "Engaging."]},
	"kestrel": {"gender": "f", "pitch": 0.8, "rate": 1.05,
		"select": ["Kestrel.", "Talk to me, Commander.", "I'm listening."],
		"move": ["Moving.", "Let's go.", "Right behind you."],
		"attack": ["For Oriel!", "Die, machine!", "Take them!"]},
	"outcast": {"gender": "m", "pitch": 0.75, "rate": 0.95,
		"select": ["The glass hears you.", "Outcast.", "What do you want?"],
		"move": ["Through the crystal.", "We know the way.", "Moving."],
		"attack": ["Break them!", "For the village!", "Hunt!"]},
	"brute": {"gender": "m", "pitch": 0.5, "rate": 0.85,
		"select": ["Brute.", "Hmm?", "Strong."],
		"move": ["Walking.", "Going.", "Heavy steps."],
		"attack": ["Smash!", "Crush!", "Break!"]},
	"tallow": {"gender": "m", "pitch": 0.6, "rate": 0.88,
		"select": ["Tallow.", "Speak, Bastion.", "I'm here."],
		"move": ["Follow me.", "This way.", "Watch the crystal."],
		"attack": ["They'll bleed glass!", "Now!", "For my people!"]},
	"lindqvist": {"gender": "m", "pitch": 1.1, "rate": 1.15,
		"select": ["Lindqvist here.", "Fascinating.", "Yes, Commander?"],
		"move": ["Right, moving.", "Please keep me covered.", "Heading over."],
		"attack": ["I'm a scientist!", "Surely someone else can do that."]},
	"truck": {"gender": "m", "pitch": 0.95, "rate": 1.1,
		"select": ["Supply truck.", "Cargo secure.", "Ready."],
		"move": ["Driving.", "On the way.", "Rolling."],
		"attack": ["Unarmed, Commander!"]},
	"bus": {"gender": "f", "pitch": 1.05, "rate": 1.15,
		"select": ["Please get us out!", "We're ready.", "Driver here."],
		"move": ["Going!", "Hold on, everyone.", "Driving."],
		"attack": ["We're civilians!"]},
	"damper": {"gender": "m", "pitch": 1.0, "rate": 1.05,
		"select": ["Damper unit.", "Resonance stable.", "Payload ready."],
		"move": ["Moving the damper.", "Careful now.", "Advancing."],
		"attack": ["No weapons on board."]},
	"civilian": {"gender": "any", "pitch": 1.1, "rate": 1.2,
		"select": ["Help us!", "Yes?", "Please!"],
		"move": ["Running!", "Okay, okay!", "Going!"],
		"attack": ["I can't!"]},
}

## EVA messages that get spoken; keys are matched as prefixes of the on-screen text.
const EVA_SPEECH := {
	"Construction complete": "Construction complete.",
	"Unit ready": "Unit ready.",
	"Our base is under attack": "Our base is under attack.",
	"Low power": "Low power.",
	"Insufficient funds": "Insufficient funds.",
	"Harvester under attack": "Harvester under attack.",
	"Unit promoted": "Unit promoted.",
	"Unit lost": "Unit lost.",
	"Building captured": "Building captured.",
	"Objective complete": "Objective complete.",
	"Objective failed": "Objective failed.",
	"New objective": "New objective.",
	"Mission accomplished": "Mission accomplished.",
	"Mission failed": "Mission failed.",
	"Reinforcements have arrived": "Reinforcements have arrived.",
	"Radar offline": "Radar offline.",
	"Radar online": "Radar online.",
	"Halo Lance ready": "Halo Lance ready.",
	"Warning": "Warning.",
}

## Kokoro voices (kokoro-multi-lang v1.0 speaker IDs, English voices only).
const KOKORO_IDS := {
	"af_alloy": 0, "af_aoede": 1, "af_bella": 2, "af_heart": 3, "af_jessica": 4, "af_kore": 5, "af_nicole": 6,
	"af_nova": 7, "af_river": 8, "af_sarah": 9, "af_sky": 10, "am_adam": 11, "am_echo": 12, "am_eric": 13,
	"am_fenrir": 14, "am_liam": 15, "am_michael": 16, "am_onyx": 17, "am_puck": 18, "am_santa": 19,
	"bf_alice": 20, "bf_emma": 21, "bf_isabella": 22, "bf_lily": 23, "bm_daniel": 24, "bm_fable": 25,
	"bm_george": 26, "bm_lewis": 27,
}

## Which Kokoro voice plays each character and each unit reaction set.
const KOKORO_CAST := {
	"spk_narrator": "bm_george", "spk_okafor": "af_kore", "spk_havel": "am_liam", "spk_lindqvist": "bm_fable",
	"spk_rourke": "am_onyx", "spk_oriel": "af_heart", "spk_kestrel": "bf_alice", "spk_sibyl": "af_sky",
	"spk_tallow": "am_fenrir", "spk_eva": "af_alloy", "spk_veil_radio": "am_eric", "spk_pilot": "am_adam",
	"spk_sergeant": "bm_daniel", "spk_civilian": "af_bella", "spk_engineer": "am_puck", "spk_outcast": "am_echo",
	"ack_infantry": "am_adam", "ack_engineer": "am_puck", "ack_medic": "af_sarah", "ack_skyjumper": "am_liam",
	"ack_harvester": "am_eric", "ack_mcv": "bm_lewis", "ack_pathfinder": "af_nova", "ack_walker": "am_onyx",
	"ack_sensor": "af_river", "ack_hover": "am_echo", "ack_apc": "bm_daniel", "ack_resonator": "af_kore",
	"ack_bulwark": "am_fenrir", "ack_kite": "af_jessica", "ack_veil_vehicle": "am_eric", "ack_shade": "bf_lily",
	"ack_drill": "am_fenrir", "ack_mole": "bm_lewis", "ack_cyborg": "af_nicole", "ack_kestrel": "bf_alice",
	"ack_outcast": "am_echo", "ack_brute": "am_onyx", "ack_tallow": "am_fenrir", "ack_lindqvist": "bm_fable",
	"ack_truck": "am_eric", "ack_bus": "af_river", "ack_damper": "bm_daniel", "ack_civilian": "af_bella",
}

## Dutch through Kokoro: the multi-lang voices that read Dutch phonemes most
## clearly (measured with a speech recogniser), by gender.
const KOKORO_NL_F := [35, 28, 42, 5]   # if_sara, ef_dora, pf_dora, af_kore
const KOKORO_NL_M := [36, 43, 29, 26]  # im_nicola, pm_alex, em_alex, bm_george
const KOKORO_NL_CAST := {"spk_narrator": 26, "spk_okafor": 28, "spk_havel": 43, "spk_lindqvist": 29,
	"spk_rourke": 36, "spk_oriel": 42, "spk_kestrel": 35, "spk_sibyl": 35, "spk_tallow": 36, "spk_eva": 28}

## Dutch Piper voices (sherpa-onnx "vits-piper-<name>" packages).
const PIPER_VOICES := {"dii": "nl_NL-dii-high", "nathalie": "nl_BE-nathalie-medium", "pim": "nl_NL-pim-medium",
	"ronnie": "nl_NL-ronnie-medium", "miro": "nl_NL-miro-high", "rdh": "nl_BE-rdh-medium"}
const PIPER_F := ["dii", "nathalie"]
const PIPER_M := ["pim", "ronnie", "miro", "rdh"]
## Character -> [Piper voice, pitch]. Six voices play the whole cast, so the
## pitch shift keeps characters that share a voice apart.
const PIPER_CAST := {
	"spk_narrator": ["ronnie", 0.93], "spk_okafor": ["nathalie", 0.96], "spk_havel": ["pim", 1.0],
	"spk_lindqvist": ["ronnie", 1.06], "spk_rourke": ["miro", 0.9], "spk_oriel": ["dii", 0.94],
	"spk_kestrel": ["nathalie", 0.88], "spk_sibyl": ["dii", 1.08], "spk_tallow": ["rdh", 0.88],
	"spk_eva": ["dii", 1.0], "spk_veil_radio": ["miro", 1.0], "spk_pilot": ["ronnie", 1.0],
	"spk_sergeant": ["pim", 0.92], "spk_civilian": ["nathalie", 1.08], "spk_engineer": ["ronnie", 1.08],
	"spk_outcast": ["rdh", 0.94],
}

## Voices processed through the "choir" effect chain (reverb + chorus).
const CHOIR_VOICES := ["spk_sibyl", "ack_cyborg"]

## Where the Kokoro model may live: in the project (editor), next to an exported
## executable, or in the user folder.
const KOKORO_DIRS := ["res://addons/godot_kokoro/models/", "@exe/kokoro_models/", "user://kokoro_models/"]
const PIPER_DIRS := ["res://addons/godot_kokoro/piper/", "@exe/piper_voices/", "user://piper_voices/"]
const CACHE_DIR := "user://voice_cache/"

enum Backend { NONE, SYSTEM, KOKORO }

var backend := Backend.NONE       # English voice engine
var enabled := false              # a real voice engine is available
var volume := 100                 # the Voice bus carries the player's speech volume
var _voices: Array = []           # system TTS: [{id, name, lang}]
var _voice_cache := {}            # system TTS: profile key -> voice id
var _queue: Array = []
var _current: Dictionary = {}
var _t := 0.0
var _eva_recent := {}
var _ack_last := -10.0
var _utt := 0
var _want := ""

# rendered audio (Kokoro / Piper)
var _kokoro: Node = null
var _kokoro_nl: Node = null       # a second Kokoro engine set up for Dutch phonemes
var _kokoro_dir := ""
var _model_tag := ""
var _piper_dir := ""
var _piper: Dictionary = {}       # voice -> PiperTTS
var _player: AudioStreamPlayer
var _bus := -1
var _mem_cache := {}              # cache key -> AudioStreamWAV
var _gen_busy := false            # one line renders at a time, so dialogue never waits behind chatter
var _gen_src := ""
var _gen_id := 0
var _gen_key := ""
var _gen_ms := 0
var _gen_voice := ""
var _thread: Thread = null
var _prewarm: Array = []          # lines to render in the background while idle
var _failed := {}                 # cache keys the engine could not render


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_want = OS.get_environment("ASHFALL_VOICE")   # kokoro | system | none (for testing)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--voice="):
			_want = a.get_slice("=", 1)
		elif a.begins_with("--test=") and _want == "":
			_want = "none"   # automated tests run silent unless asked
	if _want != "none" and _want != "system" and _init_kokoro():
		backend = Backend.KOKORO
	elif _want != "none" and _want != "kokoro" and _init_system():
		backend = Backend.SYSTEM
	if _want != "none" and _want != "system":
		_init_piper()
	enabled = backend != Backend.NONE or _piper_dir != ""
	if _kokoro or _piper_dir != "":
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		if engine_for(Settings.language) == "kokoro_nl":
			_kokoro_nl_engine()
		_queue_prewarm()
	Settings.language_changed.connect(_on_language_changed)
	print("Voice: using %s (Dutch: %s)" % [backend_name("en"), backend_name("nl")])


func _on_language_changed() -> void:
	stop_all()
	if engine_for(Settings.language) == "kokoro_nl":
		_kokoro_nl_engine()
	_queue_prewarm()


## The engine that speaks a language: kokoro | kokoro_nl | piper | system | none
func engine_for(lang: String) -> String:
	if lang == "nl":
		if _piper_dir != "":
			return "piper"
		if _kokoro:
			return "kokoro_nl"
	elif _kokoro:
		return "kokoro"
	if backend != Backend.NONE:
		return "system"
	return "none"


func backend_name(lang := "") -> String:
	if lang == "":
		lang = Settings.language
	match engine_for(lang):
		"kokoro": return "Kokoro TTS"
		"kokoro_nl": return "Kokoro TTS (Dutch pronunciation)"
		"piper": return "Piper TTS (Dutch voices)"
		"system": return "system text-to-speech"
	return "subtitles only"


func has_dutch_voices() -> bool:
	return _piper_dir != ""


func _init_system() -> bool:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	for v in DisplayServer.tts_get_voices():
		_voices.append({"id": v.get("id", ""), "name": str(v.get("name", "")).to_lower(), "lang": str(v.get("language", "")).to_lower()})
	return not _voices.is_empty()


# ---------------------------------------------------------------- Kokoro / Piper setup

func _abs_dir(d: String) -> String:
	var p := d
	if p.begins_with("@exe/"):
		p = OS.get_executable_path().get_base_dir().path_join(p.substr(5))
	else:
		p = ProjectSettings.globalize_path(p)
	return p if p.ends_with("/") else p + "/"


func _find_kokoro_dir() -> String:
	for d in KOKORO_DIRS:
		var p := _abs_dir(d)
		var has_model := FileAccess.file_exists(p + "model.int8.onnx") or FileAccess.file_exists(p + "model.onnx")
		if has_model and FileAccess.file_exists(p + "voices.bin") and FileAccess.file_exists(p + "tokens.txt") \
				and DirAccess.dir_exists_absolute(p + "espeak-ng-data"):
			return p
	return ""


func _load_kokoro(dir: String, lang: String) -> Node:
	var model := dir + ("model.int8.onnx" if FileAccess.file_exists(dir + "model.int8.onnx") else "model.onnx")
	var lexicon := ""
	if lang == "en" and FileAccess.file_exists(dir + "lexicon-us-en.txt"):
		lexicon = dir + "lexicon-us-en.txt"
	var dict := dir + "dict" if DirAccess.dir_exists_absolute(dir + "dict") else ""
	var tts: Node = ClassDB.instantiate("TextToSpeech")
	tts.name = "Kokoro_" + lang
	add_child(tts)
	tts.set("max_sentences", 1)   # Kokoro renders one sentence batch at a time anyway
	var code := "nl" if lang == "nl" else ("en-us" if lexicon != "" else "")
	tts.call("load_model", model, dir + "voices.bin", dir + "tokens.txt", dir + "espeak-ng-data", lexicon, dict, code)
	if not tts.call("is_model_loaded"):
		tts.queue_free()
		return null
	tts.connect("generation_completed", _on_generated.bind(tts.name))
	tts.connect("generation_failed", _on_generation_failed.bind(tts.name))
	return tts


func _init_kokoro() -> bool:
	if not ClassDB.class_exists("TextToSpeech"):
		return false
	_kokoro_dir = _find_kokoro_dir()
	if _kokoro_dir == "":
		print("Voice: godot-kokoro is installed but no Kokoro model was found (see tools/get_kokoro_model).")
		return false
	var tts := _load_kokoro(_kokoro_dir, "en")
	if tts == null:
		return false
	if int(tts.call("get_speaker_count")) < 28:
		push_warning("Voice: this Kokoro model has only %d voices; use kokoro-multi-lang v1.0 for the full cast." % int(tts.call("get_speaker_count")))
	_kokoro = tts
	_model_tag = _kokoro_dir.get_base_dir().get_file() + str(int(tts.call("get_speaker_count")))
	_setup_audio()
	return true


## Kokoro reading Dutch needs its own engine (Dutch phonemes, no English lexicon);
## it is only loaded when Dutch is spoken without the Piper voices.
func _kokoro_nl_engine() -> Node:
	if _kokoro_nl == null and _kokoro_dir != "":
		_kokoro_nl = _load_kokoro(_kokoro_dir, "nl")
		if _kokoro_nl == null:
			_kokoro_dir = ""
	return _kokoro_nl


func _piper_model(dir: String, voice: String) -> PackedStringArray:
	var n: String = PIPER_VOICES[voice]
	for sub in ["vits-piper-" + n + "/", n + "/"]:
		if FileAccess.file_exists(dir + sub + n + ".onnx") and FileAccess.file_exists(dir + sub + "tokens.txt"):
			var data := dir + "espeak-ng-data"
			if not DirAccess.dir_exists_absolute(data):
				data = dir + sub + "espeak-ng-data"
			if DirAccess.dir_exists_absolute(data):
				return PackedStringArray([dir + sub + n + ".onnx", dir + sub + "tokens.txt", data])
	return PackedStringArray()


func _init_piper() -> void:
	if not ClassDB.class_exists("PiperTTS"):
		return
	for d in PIPER_DIRS:
		var p := _abs_dir(d)
		var found := 0
		for v in PIPER_VOICES.keys():
			if not _piper_model(p, v).is_empty():
				found += 1
		if found > 0:
			_piper_dir = p
			break
	if _piper_dir != "":
		_setup_audio()


func _piper_available(voice: String) -> bool:
	return not _piper_model(_piper_dir, voice).is_empty()


## A "Voice" bus: pitch shift for character colour, reverb + chorus for SIBYL.
func _setup_audio() -> void:
	if _player:
		return
	_bus = AudioServer.get_bus_index("Voice")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Voice")
		AudioServer.set_bus_send(_bus, "Master")
	if AudioServer.get_bus_effect_count(_bus) < 3:
		AudioServer.add_bus_effect(_bus, AudioEffectPitchShift.new(), 0)
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.7
		rev.wet = 0.35
		AudioServer.add_bus_effect(_bus, rev, 1)
		var ch := AudioEffectChorus.new()
		ch.wet = 0.5
		AudioServer.add_bus_effect(_bus, ch, 2)
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)


## Unit reactions and EVA lines are rendered in the background once and cached,
## so they play instantly when you click.
func _queue_prewarm() -> void:
	_prewarm.clear()
	var eng := engine_for(Settings.language)
	if eng == "system" or eng == "none":
		return
	for k in EVA_SPEECH.keys():
		_prewarm.append(_make_item("eva", EVA_SPEECH[k], Prio.EVA, "spk_eva", SPEAKERS["eva"], false))
	for set_key in ACKS.keys():
		var s: Dictionary = ACKS[set_key]
		for kind in ["select", "move", "attack"]:
			for line in s.get(kind, []):
				_prewarm.append(_make_item("unit", line, Prio.ACK, "ack_" + set_key, s, false))


func _kokoro_voice(voice_key: String, gender: String) -> int:
	var vname: String = KOKORO_CAST.get(voice_key, "")
	if vname == "":
		vname = "af_sarah" if gender == "f" else "am_michael"
	return int(KOKORO_IDS.get(vname, 0))


func _kokoro_nl_voice(voice_key: String, gender: String) -> int:
	if KOKORO_NL_CAST.has(voice_key):
		return KOKORO_NL_CAST[voice_key]
	var pool: Array = KOKORO_NL_F if gender == "f" else KOKORO_NL_M
	return pool[absi(hash(voice_key)) % pool.size()]


## [voice, pitch] for a character or unit set in Dutch.
func _piper_voice(voice_key: String, gender: String, pitch: float) -> Array:
	var pick: Array = PIPER_CAST.get(voice_key, [])
	if pick.is_empty():
		var pool: Array = PIPER_F if gender == "f" else PIPER_M
		pick = [pool[absi(hash(voice_key)) % pool.size()], clampf(1.0 + (pitch - 1.0) * 0.3, 0.88, 1.12)]
	var v: String = pick[0]
	if not _piper_available(v):
		# fall back to any installed voice of the same gender, then any voice
		var pool: Array = (PIPER_F if PIPER_F.has(v) else PIPER_M) + PIPER_F + PIPER_M
		for alt in pool:
			if _piper_available(alt):
				v = alt
				break
	return [v, pick[1]]


func _cache_key(item: Dictionary) -> String:
	return "%s|%s|%.2f|%s" % [item["engine_tag"], str(item["sid"]), item["speed"], item["text"]]


func _cache_path(key: String) -> String:
	return CACHE_DIR + key.md5_text() + ".wav"


func _cached(key: String) -> AudioStreamWAV:
	if _mem_cache.has(key):
		return _mem_cache[key]
	var path := _cache_path(key)
	if FileAccess.file_exists(path):
		var wav := AudioStreamWAV.load_from_file(path)
		if wav:
			_mem_cache[key] = wav
			return wav
	return null


func _store(audio: AudioStreamWAV) -> void:
	_mem_cache[_gen_key] = audio
	audio.save_to_wav(_cache_path(_gen_key))


func _on_generated(request_id: int, audio: AudioStreamWAV, src: String) -> void:
	if not _gen_busy or src != _gen_src or request_id != _gen_id:
		return
	_gen_busy = false
	if audio == null:
		_failed[_gen_key] = true
		return
	_store(audio)


func _on_generation_failed(request_id: int, error: String, src: String) -> void:
	if _gen_busy and src == _gen_src and request_id == _gen_id:
		push_warning("Voice: Kokoro could not render a line: " + error)
		_failed[_gen_key] = true
		_gen_busy = false


## Runs on a worker thread: loads the Piper voice on first use, renders the line.
func _piper_job(tts: RefCounted, paths: PackedStringArray, text: String, speed: float) -> PackedByteArray:
	if not tts.call("is_loaded"):
		if not tts.call("load_model", paths[0], paths[1], paths[2], 2):
			return PackedByteArray()
	return tts.call("generate", text, speed, 0)


func _finish_piper() -> void:
	var bytes: PackedByteArray = _thread.wait_to_finish()
	_thread = null
	_gen_busy = false
	if bytes.is_empty():
		_failed[_gen_key] = true
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(_piper[_gen_voice].call("get_sample_rate"))
	wav.stereo = false
	wav.data = bytes
	_store(wav)


func _start_render(pick: Dictionary) -> void:
	_gen_key = pick["key"]
	_gen_ms = Time.get_ticks_msec()
	_gen_src = ""
	match pick["engine"]:
		"piper":
			var v: String = pick["sid"]
			if not _piper.has(v):
				_piper[v] = ClassDB.instantiate("PiperTTS")
			_gen_voice = v
			_gen_busy = true
			_gen_src = "piper"
			_thread = Thread.new()
			_thread.start(_piper_job.bind(_piper[v], _piper_model(_piper_dir, v), pick["text"], pick["speed"]))
		"kokoro", "kokoro_nl":
			var tts: Node = _kokoro if pick["engine"] == "kokoro" else _kokoro_nl_engine()
			if tts == null:
				_failed[_gen_key] = true
				return
			tts.set("speaker_id", pick["sid"])
			tts.set("speed", pick["speed"])
			_gen_src = tts.name
			_gen_id = int(tts.call("speak_async", pick["text"]))
			_gen_busy = _gen_id != 0
			if not _gen_busy:
				_failed[_gen_key] = true


## Keeps exactly one line rendering: the line being played first, then the queue
## in speaking order, then background pre-rendering.
func _pump_generation() -> void:
	if _thread and not _thread.is_alive():
		_finish_piper()
	if _gen_busy:
		if Time.get_ticks_msec() - _gen_ms > 30000 and _gen_src != "piper":   # engine stuck: give up on this line
			_failed[_gen_key] = true
			_gen_busy = false
		return
	var wants: Array = []
	if not _current.is_empty():
		wants.append(_current)
	wants.append_array(_queue)
	var pick: Dictionary = {}
	for it in wants:
		if it.get("rendered", false) and it.get("audio") == null and not _failed.has(it["key"]):
			if _cached(it["key"]):
				it["audio"] = _cached(it["key"])
			else:
				pick = it
				break
	if pick.is_empty():
		while not _prewarm.is_empty():
			var pw: Dictionary = _prewarm.pop_front()
			if _cached(pw["key"]) == null and not _failed.has(pw["key"]):
				pick = pw
				break
	if not pick.is_empty():
		_start_render(pick)


func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()


# ---------------------------------------------------------------- system TTS voice pick

const FEMALE_HINTS := ["zira", "hazel", "susan", "samantha", "karen", "victoria", "moira", "tessa", "fiona",
	"female", "woman", "eva", "catherine", "jenny", "aria", "linda", "heather", "helena", "ava", "allison",
	"serena", "kate", "libby", "sonia", "michelle", "emma", "colette", "fenna", "claire", "ellen", "+f"]
const MALE_HINTS := ["david", "mark", "george", "alex", "daniel", "fred", "tom", "male", "guy", "ryan", "james",
	"richard", "sean", "oliver", "arthur", "aaron", "ralph", "william", "brian", "frank", "maarten", "arnaud", "+m"]


func _is_female(n: String) -> bool:
	for h in FEMALE_HINTS:
		if n.contains(h):
			return true
	return false


func _is_male(n: String) -> bool:
	if _is_female(n):
		return false
	for h in MALE_HINTS:
		if n.contains(h):
			return true
	return false


func _voice_for(key: String, gender: String, lang: String) -> String:
	var ck := lang + "|" + key
	if _voice_cache.has(ck):
		return _voice_cache[ck]
	var langs: Array = []
	for v in _voices:
		if v["lang"].begins_with(lang):
			langs.append(v)
	if langs.is_empty() and lang != "en":
		for v in _voices:
			if v["lang"].begins_with("en") or v["lang"] == "":
				langs.append(v)
	if langs.is_empty():
		langs = _voices
	var cands: Array = []
	for v in langs:
		if (gender == "f" and _is_female(v["name"])) or (gender == "m" and _is_male(v["name"])):
			cands.append(v["id"])
	if cands.is_empty():
		for v in langs:
			cands.append(v["id"])
	var id: String = cands[absi(hash(key)) % cands.size()]
	_voice_cache[ck] = id
	return id


# ---------------------------------------------------------------- public API

func speaker_name(key: String) -> String:
	return tr(SPEAKERS.get(key, {}).get("name", key.capitalize()))


func speaker_color(key: String) -> Color:
	return SPEAKERS.get(key, {}).get("color", Color(0.85, 0.9, 1.0))


func _make_item(speaker: String, text: String, prio: int, voice_key: String, prof: Dictionary, subtitle: bool) -> Dictionary:
	var lang: String = Settings.language
	var engine := engine_for(lang)
	var item := {"speaker": speaker, "name": tr(prof.get("name", "")), "text": _clean(tr(text)), "prio": prio,
		"voice_key": voice_key, "gender": prof["gender"], "pitch": prof["pitch"], "rate": prof["rate"],
		"color": prof.get("color", Color.WHITE), "subtitle": subtitle, "audio": null, "lang": lang,
		"engine": engine, "rendered": engine == "kokoro" or engine == "kokoro_nl" or engine == "piper"}
	item["speed"] = clampf(float(prof["rate"]), 0.8, 1.25)
	item["shift"] = clampf(1.0 + (float(prof["pitch"]) - 1.0) * 0.25, 0.85, 1.15)
	match engine:
		"piper":
			var pv := _piper_voice(voice_key, prof["gender"], float(prof["pitch"]))
			item["sid"] = pv[0]
			item["shift"] = pv[1]
			item["speed"] = clampf(float(prof["rate"]), 0.85, 1.15)
			item["engine_tag"] = "piper-" + PIPER_VOICES[pv[0]]
		"kokoro_nl":
			item["sid"] = _kokoro_nl_voice(voice_key, prof["gender"])
			item["engine_tag"] = _model_tag + "-nl"
		_:
			item["sid"] = _kokoro_voice(voice_key, prof["gender"])
			item["engine_tag"] = _model_tag
	item["key"] = _cache_key(item)
	return item


## Queue a dialogue line (briefings, mission radio chatter). Interrupts EVA / unit chatter.
func say(speaker: String, text: String) -> void:
	var prof: Dictionary = SPEAKERS.get(speaker, SPEAKERS["narrator"])
	_enqueue(_make_item(speaker, text, Prio.DIALOG, "spk_" + speaker, prof, true))


## EVA announcement; dropped while dialogue is playing and de-duplicated.
## `msg` is the English message (see EVA_SPEECH); what is spoken is translated.
func eva(msg: String) -> void:
	var spoken := ""
	for k in EVA_SPEECH.keys():
		if msg.begins_with(k):
			spoken = EVA_SPEECH[k]
			break
	if spoken == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_eva_recent.get(spoken, -100.0)) < 6.0:
		return
	if dialog_active():
		return
	var pending := 0
	for q in _queue:
		if q["prio"] == Prio.EVA:
			pending += 1
	if pending >= 2:
		return
	_eva_recent[spoken] = now
	_enqueue(_make_item("eva", spoken, Prio.EVA, "spk_eva", SPEAKERS["eva"], false))


## Unit reaction (select / move / attack). Only when nothing more important is talking.
func unit_ack(set_key: String, kind: String) -> void:
	var s: Dictionary = ACKS.get(set_key, ACKS["infantry"])
	var lines: Array = s.get(kind, [])
	if lines.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _ack_last < 0.35:
		return
	if not _current.is_empty() and _current["prio"] > Prio.ACK:
		return
	for q in _queue:
		if q["prio"] > Prio.ACK:
			return
	_ack_last = now
	_queue = _queue.filter(func(q): return q["prio"] > Prio.ACK)
	if not _current.is_empty() and _current["prio"] == Prio.ACK:
		_stop_audio()
		_current = {}
	var line: String = lines[randi() % lines.size()]
	_enqueue(_make_item("unit", line, Prio.ACK, "ack_" + set_key, s, false))


func dialog_active() -> bool:
	if not _current.is_empty() and _current["prio"] == Prio.DIALOG:
		return true
	for q in _queue:
		if q["prio"] == Prio.DIALOG:
			return true
	return false


func busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


func stop_all() -> void:
	_queue.clear()
	_current = {}
	_stop_audio()


## Skip the line being spoken (briefing "next" button).
func skip_current() -> void:
	if _current.is_empty():
		return
	_stop_audio()
	_finish_current()


func _stop_audio() -> void:
	if backend == Backend.SYSTEM:
		DisplayServer.tts_stop()
	if _player:
		_player.stop()


# ---------------------------------------------------------------- queue

func _enqueue(item: Dictionary) -> void:
	if not _current.is_empty() and _current["prio"] < item["prio"]:
		# more important speech cuts off chatter
		_stop_audio()
		_current = {}
	_queue.append(item)
	# higher priority first, stable within a priority
	var dialog: Array = _queue.filter(func(q): return q["prio"] == Prio.DIALOG)
	var eva_q: Array = _queue.filter(func(q): return q["prio"] == Prio.EVA)
	var ack_q: Array = _queue.filter(func(q): return q["prio"] == Prio.ACK)
	_queue = dialog + eva_q + ack_q
	if _current.is_empty():
		_next()


func _clean(t: String) -> String:
	return t.replace("*", "").replace("\"", "").replace("_", " ").strip_edges()


func estimate(text: String, rate := 1.0) -> float:
	var words := text.split(" ", false).size()
	return 0.5 + float(words) / (2.7 * maxf(rate, 0.3))


func _next() -> void:
	if _queue.is_empty():
		_current = {}
		queue_empty.emit()
		return
	_current = _queue.pop_front()
	_t = 0.0
	_current["est"] = estimate(_current["text"], _current["rate"])
	_current["started"] = false
	_current["queued_ms"] = Time.get_ticks_msec()
	if _current["rendered"]:
		if _current.get("audio") == null:
			var c := _cached(_current["key"])
			if c:
				_current["audio"] = c
		_try_start_audio()
		return
	if _current["engine"] == "system":
		_utt += 1
		var vid := _voice_for(_current["voice_key"], _current["gender"], _current["lang"])
		DisplayServer.tts_speak(_current["text"], vid, int(Settings.volumes["Voice"]), _current["pitch"], _current["rate"], _utt, false)
	_begin_line()


func _begin_line() -> void:
	_current["started"] = true
	_t = 0.0
	if _current["subtitle"]:
		line_started.emit(_current["speaker"], _current["name"], _current["text"], _current["color"])


## Plays the current line once Kokoro / Piper has rendered it.
func _try_start_audio() -> void:
	var audio = _current.get("audio")
	if audio == null:
		return
	var choir: bool = CHOIR_VOICES.has(_current["voice_key"])
	var shift := AudioServer.get_bus_effect(_bus, 0) as AudioEffectPitchShift
	shift.pitch_scale = float(_current["shift"])
	AudioServer.set_bus_effect_enabled(_bus, 0, absf(shift.pitch_scale - 1.0) > 0.01)
	AudioServer.set_bus_effect_enabled(_bus, 1, choir)
	AudioServer.set_bus_effect_enabled(_bus, 2, choir)
	_player.volume_db = linear_to_db(volume / 100.0)
	_player.stream = audio
	_player.play()
	_begin_line()


## Real seconds the current line has been waiting for its audio (rendering runs
## in real time, whatever the game clock does).
func _waited() -> float:
	return (Time.get_ticks_msec() - int(_current.get("queued_ms", 0))) / 1000.0


func _finish_current() -> void:
	var spk: String = _current.get("speaker", "")
	var was_sub: bool = _current.get("subtitle", false) and _current.get("started", false)
	_current = {}
	if was_sub:
		line_finished.emit(spk)
	_next()


func _process(delta: float) -> void:
	_pump_generation()
	if _current.is_empty():
		return
	_t += delta
	var est: float = _current["est"]
	var done := false
	if _current["rendered"]:
		if not _current["started"]:
			if _current.get("audio") != null:
				_try_start_audio()
			elif _failed.has(_current["key"]) or _waited() > (1.5 if _current["prio"] == Prio.ACK else 15.0):
				# could not render in time: chatter is dropped, dialogue falls back to subtitles
				if _current["prio"] == Prio.ACK:
					_current = {}
					_next()
					return
				_current["audio"] = null
				_begin_line()
				_current["silent"] = true
		elif _current.get("silent", false):
			done = _t >= est
		else:
			done = _t > 0.1 and not _player.playing
	elif _current["engine"] == "system":
		if _t > 0.4 and not DisplayServer.tts_is_speaking():
			done = true
		elif _t > est * 2.5 + 3.0:
			done = true
	else:
		done = _t >= est
	if done:
		_finish_current()
