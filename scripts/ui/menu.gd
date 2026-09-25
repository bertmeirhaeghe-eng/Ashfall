extends Control
## Main menu: New game, Continue game, Options and Quit game.
## Command-line hooks for automated tests (after "--"):
##   --mission=N      start mission N directly
##   --test=NAME      run the scripted test harness (see scripts/dev/test_runner.gd)

const GOLD := Color(0.85, 0.66, 0.2)

var continue_btn: Button
var menu_box: VBoxContainer
var info: Label
var voice_label: Label
var options: OptionsPanel


func _ready() -> void:
	get_tree().paused = false
	Music.stop()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _handle_cmdline():
		return
	add_child(SkyBackdrop.new())
	theme = UiTheme.make()

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.offset_left = -220
	vb.offset_right = 220
	vb.offset_top = -210
	vb.offset_bottom = 230
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)

	var title := Label.new()
	title.text = "ASHFALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "A BASTION COALITION CAMPAIGN"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", GOLD)
	vb.add_child(sub)
	vb.add_child(_spacer(26))

	var new_btn := _button("New Game")
	new_btn.pressed.connect(_on_new)
	vb.add_child(new_btn)
	continue_btn = _button("Continue Game")
	continue_btn.pressed.connect(_on_continue)
	vb.add_child(continue_btn)
	var opt_btn := _button("Options")
	opt_btn.pressed.connect(_on_options)
	vb.add_child(opt_btn)
	var quit_btn := _button("Quit Game")
	quit_btn.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit_btn)

	info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.75))
	vb.add_child(info)
	voice_label = Label.new()
	voice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(voice_label)
	menu_box = vb
	continue_btn.disabled = not Campaign.has_save()
	_refresh_texts()
	Settings.language_changed.connect(_refresh_texts)
	new_btn.grab_focus()
	Voice.stop_all()
	Voice.say("eva", "Welcome back, Commander.")


## The lines built from data; static button and label texts translate themselves.
func _refresh_texts() -> void:
	if Campaign.has_save():
		var m: Dictionary = Campaign.mission_info()
		info.text = tr("Saved: Mission %d  -  %s") % [m["id"], tr(m["title"])]
	else:
		info.text = tr("No campaign in progress")
	var col := Color(1.0, 0.7, 0.4)
	match Voice.engine_for(Settings.language):
		"kokoro", "piper":
			voice_label.text = tr("Voices: %s") % tr(Voice.backend_name())
			col = Color(0.6, 0.85, 0.65)
		"kokoro_nl":
			voice_label.text = tr("Voices: %s") % tr(Voice.backend_name()) + "\n" \
				+ tr("Install the Dutch Piper voices for natural Dutch speech (see README).")
			col = Color(0.8, 0.85, 0.6)
		"system":
			voice_label.text = tr("Voices: system text-to-speech. Install the Kokoro model for neural voices (see README).")
			col = Color(0.8, 0.8, 0.7)
		_:
			voice_label.text = tr("No text-to-speech available: voices are shown as subtitles. Install the Kokoro model (see README).")
	voice_label.add_theme_color_override("font_color", col)


func _on_options() -> void:
	if options:
		return
	menu_box.visible = false
	options = OptionsPanel.new()
	options.set_anchors_preset(Control.PRESET_CENTER)
	options.grow_horizontal = Control.GROW_DIRECTION_BOTH
	options.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(options)
	options.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	options = null
	menu_box.visible = true
	_refresh_texts()


func _spacer(hgt: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, hgt)
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _on_new() -> void:
	Voice.stop_all()
	Campaign.new_game()


func _on_continue() -> void:
	Voice.stop_all()
	Campaign.continue_game()


func _handle_cmdline() -> bool:
	if Campaign.cmdline_handled:
		return false
	Campaign.cmdline_handled = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			Campaign.mission_index = clampi(int(a.get_slice("=", 1)), 1, Campaign.MISSIONS.size())
			Campaign.start_mission.call_deferred()
			return true
		if a.begins_with("--test="):
			Campaign.debug_autotest = a.get_slice("=", 1)
			TestRunner.begin.call_deferred(Campaign.debug_autotest)
			return true
		if a.begins_with("--story="):
			Campaign.story_mode = a.get_slice("=", 1)
			get_tree().change_scene_to_file.call_deferred(Campaign.STORY_SCENE)
			return true
	return false
