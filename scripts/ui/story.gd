extends Control
## Story screen: the prologue, every mission briefing and the epilogue.
## All lines are spoken by the text-to-speech Voice system; the transcript,
## speaker portrait and objectives are shown alongside.

const GOLD := Color(0.85, 0.66, 0.2)

var backdrop: SkyBackdrop
var portrait: Control
var speaker_label: Label
var transcript: RichTextLabel
var start_btn: Button
var skip_btn: Button
var lines: Array = []
var _spoken := 0
var _current_speaker := ""
var _finished := false


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	backdrop = SkyBackdrop.new()
	add_child(backdrop)
	Voice.stop_all()
	Voice.line_started.connect(_on_line_started)
	Voice.queue_empty.connect(_on_all_spoken)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 48)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	root.add_child(vb)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", GOLD)
	vb.add_child(header)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.65))
	vb.add_child(title)
	var place := Label.new()
	place.add_theme_font_size_override("font_size", 15)
	place.add_theme_color_override("font_color", Color(0.75, 0.8, 0.8))
	vb.add_child(place)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	vb.add_child(body)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	body.add_child(left)
	var lvb := VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 10)
	left.add_child(lvb)
	portrait = Control.new()
	portrait.custom_minimum_size = Vector2(230, 230)
	portrait.draw.connect(_draw_portrait)
	lvb.add_child(portrait)
	speaker_label = Label.new()
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speaker_label.add_theme_font_size_override("font_size", 18)
	lvb.add_child(speaker_label)

	var mid := PanelContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	transcript = RichTextLabel.new()
	transcript.bbcode_enabled = true
	transcript.scroll_following = true
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(transcript)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vb.add_child(buttons)
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(140, 42)
	menu_btn.pressed.connect(Campaign.to_menu)
	buttons.add_child(menu_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var replay := Button.new()
	replay.text = "Replay"
	replay.custom_minimum_size = Vector2(120, 42)
	replay.pressed.connect(_play)
	buttons.add_child(replay)
	skip_btn = Button.new()
	skip_btn.text = "Skip Line"
	skip_btn.custom_minimum_size = Vector2(120, 42)
	skip_btn.pressed.connect(func(): Voice.skip_current())
	buttons.add_child(skip_btn)
	start_btn = Button.new()
	start_btn.custom_minimum_size = Vector2(200, 42)
	start_btn.add_theme_font_size_override("font_size", 17)
	start_btn.pressed.connect(_on_start)
	buttons.add_child(start_btn)

	match Campaign.story_mode:
		"prologue":
			header.text = "PROLOGUE"
			title.text = "The Ashfall"
			place.text = "2031  -  Every continent"
			lines = Campaign.PROLOGUE
			start_btn.text = "Continue"
		"epilogue":
			header.text = "EPILOGUE"
			title.text = "The Heartbeat Stops"
			place.text = "2071  -  Coalition Council"
			lines = Campaign.epilogue_lines()
			start_btn.text = "Return to Main Menu"
			backdrop.tint = Color(0.75, 0.8, 0.85)
		_:
			var m: Dictionary = Campaign.mission_info()
			header.text = "%s   //   MISSION %d OF %d   //   BRIEFING: %s" % [m["act"].to_upper(), m["id"], Campaign.MISSIONS.size(), m["briefing_by"]]
			title.text = m["title"]
			place.text = "%s   -   %s" % [m["place"], m["time"]]
			lines = Campaign.briefing_lines()
			start_btn.text = "Begin Mission"
			backdrop.intensity = 0.35
			var objs := _objectives_preview(m)
			if not objs.is_empty():
				var op := PanelContainer.new()
				op.custom_minimum_size = Vector2(330, 0)
				body.add_child(op)
				var ol := RichTextLabel.new()
				ol.bbcode_enabled = true
				ol.fit_content = true
				ol.text = "[color=#d9a833][b]OBJECTIVES[/b][/color]\n\n" + "\n".join(PackedStringArray(objs))
				op.add_child(ol)
	start_btn.grab_focus()
	_play()
	if Campaign.debug_autotest != "":
		get_tree().create_timer(1.0).timeout.connect(_on_start)


func _objectives_preview(m: Dictionary) -> Array:
	var scr: Script = load(m["script"])
	if scr == null:
		return []
	var out: Array = []
	var inst: Object = scr.new()
	if inst.has_method("objective_preview"):
		for o in inst.objective_preview():
			var col := "#ffffff"
			match o[0]:
				"primary": col = "#9cf29f"
				"secondary": col = "#8ccff5"
				"bonus": col = "#f2d06b"
			out.append("[color=%s]%s:[/color] %s\n" % [col, str(o[0]).capitalize(), o[1]])
	if inst is Node:
		inst.free()
	return out


func _play() -> void:
	Voice.stop_all()
	transcript.clear()
	_spoken = 0
	_finished = false
	for l in lines:
		Voice.say(l[0], l[1])


func _on_line_started(speaker: String, speaker_name: String, text: String, color: Color) -> void:
	_current_speaker = speaker
	speaker_label.text = speaker_name
	speaker_label.add_theme_color_override("font_color", color)
	portrait.queue_redraw()
	transcript.append_text("[color=#%s][b]%s:[/b][/color] %s\n\n" % [color.to_html(false), speaker_name, text])
	_spoken += 1


func _on_all_spoken() -> void:
	_finished = true
	start_btn.grab_focus()


func _draw_portrait() -> void:
	var s := portrait.size
	var c := Voice.speaker_color(_current_speaker)
	portrait.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.04, 0.05))
	# scan lines of a video link
	for y in range(0, int(s.y), 4):
		portrait.draw_line(Vector2(0, y), Vector2(s.x, y), Color(c.r, c.g, c.b, 0.05))
	var center := s * 0.5
	portrait.draw_circle(center + Vector2(0, 88), 80, Color(c.r * 0.4, c.g * 0.4, c.b * 0.4))
	portrait.draw_circle(center - Vector2(0, 20), 52, Color(c.r * 0.55, c.g * 0.55, c.b * 0.55))
	if _current_speaker == "oriel":
		portrait.draw_circle(center - Vector2(0, 20), 44, Color(0.85, 0.9, 0.95))
		portrait.draw_line(center - Vector2(30, 20), center + Vector2(30, -20), Color(0.4, 0.4, 0.5), 2.0)
	elif _current_speaker == "sibyl":
		for k in 6:
			portrait.draw_arc(center - Vector2(0, 20), 20 + k * 8, 0, TAU, 32, Color(0.5, 1.0, 0.6, 0.5 - k * 0.07), 2.0)
	var initials := ""
	for part in Voice.speaker_name(_current_speaker).replace(".", "").split(" ", false):
		if part.length() > 0 and part[0] == part[0].to_upper():
			initials += part[0]
	var font := get_theme_default_font()
	portrait.draw_string(font, Vector2(0, s.y - 18), initials.right(2), HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, c)
	portrait.draw_rect(Rect2(Vector2.ZERO, s), GOLD.darkened(0.3), false, 1.0)


func _on_start() -> void:
	Voice.stop_all()
	match Campaign.story_mode:
		"prologue":
			Campaign.show_briefing()
		"epilogue":
			Campaign.completed = true
			Campaign.save_game()
			Campaign.to_menu()
		_:
			Campaign.start_mission()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_start()
