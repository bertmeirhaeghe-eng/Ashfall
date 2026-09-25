class_name OptionsPanel
extends PanelContainer
## Options: music / sound effects / speech volume and the game language.
## Used by the main menu and by the in-game menu.

signal closed

const GOLD := Color(0.85, 0.66, 0.2)

var _value_labels := {}
var _lang_btn: OptionButton
var _gfx_btn: OptionButton


func _ready() -> void:
	custom_minimum_size = Vector2(480, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	add_child(vb)
	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for row in [["Music", "Music volume"], ["Sfx", "Sound effects volume"], ["Voice", "Speech volume"]]:
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size = Vector2(190, 0)
		grid.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 5
		s.value = Settings.volumes[row[0]]
		s.custom_minimum_size = Vector2(190, 24)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_volume.bind(row[0]))
		s.drag_ended.connect(_on_volume_released.bind(row[0]))
		grid.add_child(s)
		var v := Label.new()
		v.custom_minimum_size = Vector2(46, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.text = "%d%%" % int(s.value)
		grid.add_child(v)
		_value_labels[row[0]] = v

	var ll := Label.new()
	ll.text = "Language"
	grid.add_child(ll)
	_lang_btn = OptionButton.new()
	_lang_btn.custom_minimum_size = Vector2(190, 0)
	# language names are always shown in their own language
	_lang_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for i in Settings.LANGUAGES.size():
		var lang: Array = Settings.LANGUAGES[i]
		_lang_btn.add_item(lang[1], i)
		_lang_btn.set_item_disabled(i, not Settings.has_language(lang[0]))
		if lang[0] == Settings.language:
			_lang_btn.select(i)
	_lang_btn.item_selected.connect(_on_language)
	grid.add_child(_lang_btn)
	grid.add_child(Control.new())

	var gl := Label.new()
	gl.text = "Graphics quality"
	grid.add_child(gl)
	_gfx_btn = OptionButton.new()
	_gfx_btn.custom_minimum_size = Vector2(190, 0)
	for i in Settings.GRAPHICS_LEVELS.size():
		_gfx_btn.add_item(tr(Settings.GRAPHICS_LEVELS[i]), i)
	_gfx_btn.select(Settings.graphics)
	_gfx_btn.item_selected.connect(_on_graphics)
	grid.add_child(_gfx_btn)
	grid.add_child(Control.new())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(close)
	vb.add_child(back)
	back.grab_focus.call_deferred()


func _on_volume(value: float, bus_name: String) -> void:
	Settings.set_volume(bus_name, int(value))
	(_value_labels[bus_name] as Label).text = "%d%%" % int(value)


## Let the player hear the level they picked.
func _on_volume_released(_changed: bool, bus_name: String) -> void:
	match bus_name:
		"Sfx":
			Sfx.ui("confirm")
		"Voice":
			Voice.stop_all()
			Voice.say("eva", "Welcome back, Commander.")


func _on_graphics(index: int) -> void:
	Settings.set_graphics(index)
	Sfx.ui("confirm")


func _on_language(index: int) -> void:
	Settings.set_language(Settings.LANGUAGES[index][0])
	Voice.stop_all()
	Voice.say("eva", "Welcome back, Commander.")


func close() -> void:
	Settings.save()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
