extends Node
## Player options (autoload "Settings", loaded first): music / sound-effect /
## speech volume and the game language. Saved in user://ashfall_settings.cfg.
##
## Language: every user-facing string in the game is written in English and
## goes through Godot's tr(). Dutch comes from data/lang/nl.json, a flat
## {"English text": "Nederlandse tekst"} table, registered with the
## TranslationServer. Controls translate their text automatically.

signal changed
signal language_changed

const PATH := "user://ashfall_settings.cfg"
const LANGUAGES := [["en", "English"], ["nl", "Nederlands"]]
const LANG_FILES := {"nl": "res://data/lang/nl.json"}
## Audio buses: name -> default volume (0..100)
const BUSES := {"Music": 70, "Sfx": 80, "Voice": 90}

var volumes := {"Music": 70, "Sfx": 80, "Voice": 90}
var language := "en"
var _tables := {}   # locale -> Translation


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES.keys():
		_ensure_bus(b)
	var check := OS.get_cmdline_user_args().has("--langcheck")
	for loc in LANG_FILES.keys():
		# the coverage test uses a scripted table that records missing strings
		var t: Translation = LangTable.new() if check else Translation.new()
		t.locale = loc
		if _load_table(t, LANG_FILES[loc]):
			TranslationServer.add_translation(t)
			_tables[loc] = t
	_load()
	# tests and screenshots can force a language
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			language = a.get_slice("=", 1)
	var env := OS.get_environment("ASHFALL_LANG")
	if env != "":
		language = env
	_apply()


func _load_table(t: Translation, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Settings: no translation file " + path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("Settings: could not parse " + path)
		return false
	for k in data.keys():
		if not str(k).begins_with("@"):   # "@comment" style metadata
			if t is LangTable:
				t.table[StringName(str(k))] = StringName(str(data[k]))
			else:
				t.add_message(str(k), str(data[k]))
	return true


## Translations must leave the TranslationServer before the script engine shuts down.
func _exit_tree() -> void:
	for t in _tables.values():
		TranslationServer.remove_translation(t)
	_tables.clear()


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for b in BUSES.keys():
		volumes[b] = clampi(int(cf.get_value("audio", b.to_lower(), BUSES[b])), 0, 100)
	language = str(cf.get_value("game", "language", "en"))


func save() -> void:
	if Campaign.debug_autotest != "":
		return
	var cf := ConfigFile.new()
	for b in BUSES.keys():
		cf.set_value("audio", b.to_lower(), volumes[b])
	cf.set_value("game", "language", language)
	cf.save(PATH)


func _apply() -> void:
	for b in BUSES.keys():
		var idx := _ensure_bus(b)
		var v: float = volumes[b] / 100.0
		AudioServer.set_bus_mute(idx, v <= 0.001)
		# a gentle curve so the slider feels even across its range
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v * v, 0.0001)))
	if not has_language(language):
		language = "en"
	TranslationServer.set_locale(language)


func has_language(code: String) -> bool:
	return code == "en" or _tables.has(code)


func set_volume(bus_name: String, value: int) -> void:
	volumes[bus_name] = clampi(value, 0, 100)
	_apply()
	changed.emit()


func set_language(code: String) -> void:
	if code == language or not has_language(code):
		return
	language = code
	_apply()
	changed.emit()
	language_changed.emit()


func is_dutch() -> bool:
	return language == "nl"


## Strings that asked for a translation that nl.json does not have (for the
## translation coverage test).
func missing_translations() -> Array:
	var t = _tables.get(language)
	return t.misses.keys() if t is LangTable else []
