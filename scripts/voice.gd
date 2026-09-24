extends Node
## Every in-game voice goes through here (autoload "Voice"): briefings,
## mission dialogue, the Bastion EVA and unit reactions.
##
## Backends, in order of preference:
##  1. Kokoro TTS (neural voices) through the godot-kokoro GDExtension in
##     addons/godot_kokoro, when its model files are installed. Every character
##     and unit type has its own Kokoro voice; rendered lines are cached in
##     user://voice_cache so each line is only synthesised once.
##  2. The platform text-to-speech engine (DisplayServer.tts_*).
##  3. Subtitles only, paced by an estimated duration (headless, no engine).

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

## Voices processed through the "choir" effect chain (reverb + chorus).
const CHOIR_VOICES := ["spk_sibyl", "ack_cyborg"]

## Where the Kokoro model may live: in the project (editor), next to an exported
## executable, or in the user folder.
const KOKORO_DIRS := ["res://addons/godot_kokoro/models/", "@exe/kokoro_models/", "user://kokoro_models/"]
const CACHE_DIR := "user://voice_cache/"

enum Backend { NONE, SYSTEM, KOKORO }

var backend := Backend.NONE
var enabled := false              # a real voice engine is available
var volume := 80
var _voices: Array = []           # system TTS: [{id, name}]
var _voice_cache := {}            # system TTS: profile key -> voice id
var _queue: Array = []
var _current: Dictionary = {}
var _t := 0.0
var _eva_recent := {}
var _ack_last := -10.0
var _utt := 0

# Kokoro backend
var _kokoro: Node = null
var _model_tag := ""
var _player: AudioStreamPlayer
var _bus := -1
var _mem_cache := {}              # cache key -> AudioStreamWAV
var _gen_id := 0                  # outstanding request (one at a time, so dialogue never waits behind chatter)
var _gen_key := ""
var _gen_t := 0.0
var _prewarm: Array = []          # lines to render in the background while idle
var _failed := {}                 # cache keys the engine could not render


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var want := OS.get_environment("ASHFALL_VOICE")   # kokoro | system | none (for testing)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--voice="):
			want = a.get_slice("=", 1)
		elif a.begins_with("--test=") and want == "":
			want = "none"   # automated tests run silent unless asked
	if want != "none" and want != "system" and _init_kokoro():
		backend = Backend.KOKORO
	elif want != "none" and want != "kokoro" and _init_system():
		backend = Backend.SYSTEM
	enabled = backend != Backend.NONE
	print("Voice: using %s" % backend_name())


func backend_name() -> String:
	match backend:
		Backend.KOKORO: return "Kokoro TTS"
		Backend.SYSTEM: return "system text-to-speech"
	return "subtitles only"


func _init_system() -> bool:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	var all: Array = DisplayServer.tts_get_voices()
	for v in all:
		var lang: String = str(v.get("language", ""))
		if lang.begins_with("en") or lang == "":
			_voices.append({"id": v.get("id", ""), "name": str(v.get("name", "")).to_lower()})
	if _voices.is_empty():
		for v in all:
			_voices.append({"id": v.get("id", ""), "name": str(v.get("name", "")).to_lower()})
	return not _voices.is_empty()


# ---------------------------------------------------------------- Kokoro setup

func _find_kokoro_dir() -> String:
	for d in KOKORO_DIRS:
		var p: String = d
		if p.begins_with("@exe/"):
			p = OS.get_executable_path().get_base_dir().path_join(p.substr(5))
		else:
			p = ProjectSettings.globalize_path(p)
		if not p.ends_with("/"):
			p += "/"
		var has_model := FileAccess.file_exists(p + "model.int8.onnx") or FileAccess.file_exists(p + "model.onnx")
		if has_model and FileAccess.file_exists(p + "voices.bin") and FileAccess.file_exists(p + "tokens.txt") \
				and DirAccess.dir_exists_absolute(p + "espeak-ng-data"):
			return p
	return ""


func _init_kokoro() -> bool:
	if not ClassDB.class_exists("TextToSpeech"):
		return false
	var dir := _find_kokoro_dir()
	if dir == "":
		print("Voice: godot-kokoro is installed but no Kokoro model was found (see tools/get_kokoro_model).")
		return false
	var model := dir + ("model.int8.onnx" if FileAccess.file_exists(dir + "model.int8.onnx") else "model.onnx")
	var lexicon := dir + "lexicon-us-en.txt" if FileAccess.file_exists(dir + "lexicon-us-en.txt") else ""
	var dict := dir + "dict" if DirAccess.dir_exists_absolute(dir + "dict") else ""
	var tts: Node = ClassDB.instantiate("TextToSpeech")
	tts.name = "Kokoro"
	add_child(tts)
	tts.set("max_sentences", 1)   # Kokoro renders one sentence batch at a time anyway
	tts.call("load_model", model, dir + "voices.bin", dir + "tokens.txt", dir + "espeak-ng-data", lexicon, dict, "en-us" if lexicon != "" else "")
	if not tts.call("is_model_loaded"):
		tts.queue_free()
		return false
	if int(tts.call("get_speaker_count")) < 28:
		push_warning("Voice: this Kokoro model has only %d voices; use kokoro-multi-lang v1.0 for the full cast." % int(tts.call("get_speaker_count")))
	_kokoro = tts
	_model_tag = model.get_file() + str(int(tts.call("get_speaker_count")))
	tts.connect("generation_completed", _on_generated)
	tts.connect("generation_failed", _on_generation_failed)
	_setup_audio()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_queue_prewarm()
	return true


## A "Voice" bus: pitch shift for character colour, reverb + chorus for SIBYL.
func _setup_audio() -> void:
	_bus = AudioServer.get_bus_index("Voice")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Voice")
		AudioServer.set_bus_send(_bus, "Master")
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
	for k in EVA_SPEECH.keys():
		_prewarm.append(_make_item("eva", EVA_SPEECH[k], Prio.EVA, "spk_eva", SPEAKERS["eva"], false))
	for set_key in ACKS.keys():
		var s: Dictionary = ACKS[set_key]
		for kind in ["select", "move", "attack"]:
			for line in s.get(kind, []):
				_prewarm.append(_make_item("unit", line, Prio.ACK, "ack_" + set_key, s, false))


func _kokoro_voice(voice_key: String, gender: String) -> int:
	var name: String = KOKORO_CAST.get(voice_key, "")
	if name == "":
		name = "af_sarah" if gender == "f" else "am_michael"
	return int(KOKORO_IDS.get(name, 0))


func _cache_key(item: Dictionary) -> String:
	return "%s|%d|%.2f|%s" % [_model_tag, item["sid"], item["speed"], item["text"]]


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


func _on_generated(request_id: int, audio: AudioStreamWAV) -> void:
	if request_id != _gen_id:
		return
	_gen_id = 0
	if audio == null:
		_failed[_gen_key] = true
		return
	_mem_cache[_gen_key] = audio
	audio.save_to_wav(_cache_path(_gen_key))


func _on_generation_failed(request_id: int, error: String) -> void:
	if request_id == _gen_id:
		push_warning("Voice: Kokoro could not render a line: " + error)
		_failed[_gen_key] = true
		_gen_id = 0


## Keeps exactly one line rendering: the line being played first, then the queue
## in speaking order, then background pre-rendering.
func _pump_generation(delta: float) -> void:
	if _kokoro == null:
		return
	if _gen_id != 0:
		_gen_t += delta
		if _gen_t > 30.0:   # engine stuck: give up on this line
			_failed[_gen_key] = true
			_gen_id = 0
		return
	var wants: Array = []
	if not _current.is_empty():
		wants.append(_current)
	wants.append_array(_queue)
	var pick: Dictionary = {}
	for it in wants:
		if it.get("audio") == null and not _failed.has(it["key"]):
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
	if pick.is_empty():
		return
	_kokoro.set("speaker_id", pick["sid"])
	_kokoro.set("speed", pick["speed"])
	_gen_key = pick["key"]
	_gen_t = 0.0
	_gen_id = int(_kokoro.call("speak_async", pick["text"]))
	if _gen_id == 0:
		_failed[_gen_key] = true


# ---------------------------------------------------------------- system TTS voice pick

const FEMALE_HINTS := ["zira", "hazel", "susan", "samantha", "karen", "victoria", "moira", "tessa", "fiona",
	"female", "woman", "eva", "catherine", "jenny", "aria", "linda", "heather", "helena", "ava", "allison",
	"serena", "kate", "libby", "sonia", "michelle", "emma", "+f"]
const MALE_HINTS := ["david", "mark", "george", "alex", "daniel", "fred", "tom", "male", "guy", "ryan", "james",
	"richard", "sean", "oliver", "arthur", "aaron", "ralph", "william", "brian", "+m"]


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


func _voice_for(key: String, gender: String) -> String:
	if _voice_cache.has(key):
		return _voice_cache[key]
	var cands: Array = []
	for v in _voices:
		if (gender == "f" and _is_female(v["name"])) or (gender == "m" and _is_male(v["name"])):
			cands.append(v["id"])
	if cands.is_empty():
		for v in _voices:
			cands.append(v["id"])
	var id: String = cands[absi(hash(key)) % cands.size()]
	_voice_cache[key] = id
	return id


# ---------------------------------------------------------------- public API

func speaker_name(key: String) -> String:
	return SPEAKERS.get(key, {}).get("name", key.capitalize())


func speaker_color(key: String) -> Color:
	return SPEAKERS.get(key, {}).get("color", Color(0.85, 0.9, 1.0))


func _make_item(speaker: String, text: String, prio: int, voice_key: String, prof: Dictionary, subtitle: bool) -> Dictionary:
	var item := {"speaker": speaker, "name": prof.get("name", ""), "text": _clean(text), "prio": prio,
		"voice_key": voice_key, "gender": prof["gender"], "pitch": prof["pitch"], "rate": prof["rate"],
		"color": prof.get("color", Color.WHITE), "subtitle": subtitle, "audio": null}
	item["sid"] = _kokoro_voice(voice_key, prof["gender"])
	item["speed"] = clampf(float(prof["rate"]), 0.8, 1.25)
	item["key"] = _cache_key(item)
	return item


## Queue a dialogue line (briefings, mission radio chatter). Interrupts EVA / unit chatter.
func say(speaker: String, text: String) -> void:
	var prof: Dictionary = SPEAKERS.get(speaker, SPEAKERS["narrator"])
	_enqueue(_make_item(speaker, text, Prio.DIALOG, "spk_" + speaker, prof, true))


## EVA announcement; dropped while dialogue is playing and de-duplicated.
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
	match backend:
		Backend.SYSTEM:
			DisplayServer.tts_stop()
		Backend.KOKORO:
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
	if backend == Backend.KOKORO:
		if _current.get("audio") == null:
			var c := _cached(_current["key"])
			if c:
				_current["audio"] = c
		_try_start_kokoro()
		return
	if backend == Backend.SYSTEM:
		_utt += 1
		var vid := _voice_for(_current["voice_key"], _current["gender"])
		DisplayServer.tts_speak(_current["text"], vid, volume, _current["pitch"], _current["rate"], _utt, false)
	_begin_line()


func _begin_line() -> void:
	_current["started"] = true
	_t = 0.0
	if _current["subtitle"]:
		line_started.emit(_current["speaker"], _current["name"], _current["text"], _current["color"])


## Plays the current line once Kokoro has rendered it.
func _try_start_kokoro() -> void:
	var audio = _current.get("audio")
	if audio == null:
		return
	var choir: bool = CHOIR_VOICES.has(_current["voice_key"])
	var shift := AudioServer.get_bus_effect(_bus, 0) as AudioEffectPitchShift
	shift.pitch_scale = clampf(1.0 + (float(_current["pitch"]) - 1.0) * 0.25, 0.85, 1.15)
	AudioServer.set_bus_effect_enabled(_bus, 0, absf(shift.pitch_scale - 1.0) > 0.01)
	AudioServer.set_bus_effect_enabled(_bus, 1, choir)
	AudioServer.set_bus_effect_enabled(_bus, 2, choir)
	_player.volume_db = linear_to_db(volume / 100.0)
	_player.stream = audio
	_player.play()
	_begin_line()


func _finish_current() -> void:
	var spk: String = _current.get("speaker", "")
	var was_sub: bool = _current.get("subtitle", false) and _current.get("started", false)
	_current = {}
	if was_sub:
		line_finished.emit(spk)
	_next()


func _process(delta: float) -> void:
	_pump_generation(delta)
	if _current.is_empty():
		return
	_t += delta
	var est: float = _current["est"]
	var done := false
	match backend:
		Backend.KOKORO:
			if not _current["started"]:
				if _current.get("audio") != null:
					_try_start_kokoro()
				elif _failed.has(_current["key"]) or _t > (1.5 if _current["prio"] == Prio.ACK else 12.0):
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
		Backend.SYSTEM:
			if _t > 0.4 and not DisplayServer.tts_is_speaking():
				done = true
			elif _t > est * 2.5 + 3.0:
				done = true
		_:
			done = _t >= est
	if done:
		_finish_current()
