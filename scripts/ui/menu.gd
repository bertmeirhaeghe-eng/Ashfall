extends Control
## Main menu: New game, Continue game, Quit game.
## Command-line hooks for automated tests (after "--"):
##   --mission=N      start mission N directly
##   --test=NAME      run the scripted test harness (see scripts/dev/test_runner.gd)

const GOLD := Color(0.85, 0.66, 0.2)

var continue_btn: Button


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	var quit_btn := _button("Quit Game")
	quit_btn.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit_btn)

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.75))
	vb.add_child(info)
	if Campaign.has_save():
		var m: Dictionary = Campaign.mission_info()
		info.text = "Saved: Mission %d  -  %s" % [m["id"], m["title"]]
	else:
		continue_btn.disabled = true
		info.text = "No campaign in progress"
	if not Voice.enabled:
		var warn := Label.new()
		warn.text = "Text-to-speech is unavailable on this system: voices are shown as subtitles."
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 12)
		warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		vb.add_child(warn)
	new_btn.grab_focus()
	Voice.stop_all()
	Voice.say("eva", "Welcome back, Commander.")


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
