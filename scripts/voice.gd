extends Node
## Every in-game voice goes through here (autoload "Voice"): briefings,
## mission dialogue, the Bastion EVA and unit reactions. Lines are spoken with
## the platform text-to-speech engine (DisplayServer.tts_*). Each character has
## a voice profile (voice pick, pitch, rate). When no TTS engine is available
## (headless, missing speech-dispatcher) lines are paced by an estimated
## duration so subtitles and scripted sequences still work.

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

var enabled := false
var volume := 80
var _voices: Array = []        # [{id, name}]
var _voice_cache := {}         # profile key -> voice id
var _queue: Array = []
var _current: Dictionary = {}
var _t := 0.0
var _eva_recent := {}
var _ack_last := -10.0
var _utt := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)) \
			and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	if enabled:
		for v in DisplayServer.tts_get_voices():
			var lang: String = str(v.get("language", ""))
			if lang.begins_with("en") or lang == "":
				_voices.append({"id": v.get("id", ""), "name": str(v.get("name", "")).to_lower()})
		if _voices.is_empty():
			for v in DisplayServer.tts_get_voices():
				_voices.append({"id": v.get("id", ""), "name": str(v.get("name", "")).to_lower()})
		if _voices.is_empty():
			enabled = false


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
	if not enabled:
		return ""
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


## Queue a dialogue line (briefings, mission radio chatter). Interrupts EVA / unit chatter.
func say(speaker: String, text: String) -> void:
	var prof: Dictionary = SPEAKERS.get(speaker, SPEAKERS["narrator"])
	_enqueue({"speaker": speaker, "name": prof["name"], "text": text, "prio": Prio.DIALOG,
		"voice_key": "spk_" + speaker, "gender": prof["gender"], "pitch": prof["pitch"],
		"rate": prof["rate"], "color": prof["color"], "subtitle": true})


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
	var prof: Dictionary = SPEAKERS["eva"]
	_enqueue({"speaker": "eva", "name": prof["name"], "text": spoken, "prio": Prio.EVA,
		"voice_key": "spk_eva", "gender": prof["gender"], "pitch": prof["pitch"], "rate": prof["rate"],
		"color": prof["color"], "subtitle": false})


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
		if enabled:
			DisplayServer.tts_stop()
		_current = {}
	var line: String = lines[randi() % lines.size()]
	_enqueue({"speaker": "unit", "name": "", "text": line, "prio": Prio.ACK,
		"voice_key": "ack_" + set_key, "gender": s["gender"], "pitch": s["pitch"], "rate": s["rate"],
		"color": Color.WHITE, "subtitle": false})


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
	if enabled:
		DisplayServer.tts_stop()


## Skip the line being spoken (briefing "next" button).
func skip_current() -> void:
	if _current.is_empty():
		return
	if enabled:
		DisplayServer.tts_stop()
	_finish_current()


# ---------------------------------------------------------------- queue

func _enqueue(item: Dictionary) -> void:
	item["text"] = _clean(item["text"])
	if not _current.is_empty() and _current["prio"] < item["prio"]:
		# more important speech cuts off chatter
		if enabled:
			DisplayServer.tts_stop()
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
	if enabled:
		_utt += 1
		var vid := _voice_for(_current["voice_key"], _current["gender"])
		DisplayServer.tts_speak(_current["text"], vid, volume, _current["pitch"], _current["rate"], _utt, false)
	if _current["subtitle"]:
		line_started.emit(_current["speaker"], _current["name"], _current["text"], _current["color"])


func _finish_current() -> void:
	var spk: String = _current.get("speaker", "")
	var was_sub: bool = _current.get("subtitle", false)
	_current = {}
	if was_sub:
		line_finished.emit(spk)
	_next()


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_t += delta
	var est: float = _current["est"]
	var done := false
	if enabled:
		if _t > 0.4 and not DisplayServer.tts_is_speaking():
			done = true
		elif _t > est * 2.5 + 3.0:
			done = true
	else:
		done = _t >= est
	if done:
		_finish_current()
