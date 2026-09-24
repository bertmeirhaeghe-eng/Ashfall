class_name HUD
extends CanvasLayer
## RA2-style sidebar (radar, credits, power, tabbed build cameos, special
## actions, sell/repair), objectives panel, EVA message feed, spoken-dialogue
## subtitles, mission timers, selection info, game menu and the mission end panel.

const SIDEBAR_W := 272
const GOLD := Color(0.85, 0.66, 0.2)
const TABS := [["structure", "Base"], ["defense", "Def"], ["infantry", "Inf"], ["vehicle", "Veh"], ["aircraft", "Air"], ["veil", "Veil"]]
const TAB_COLORS := {"structure": Color(0.35, 0.6, 1.0), "defense": Color(1.0, 0.55, 0.25), "infantry": Color(0.45, 0.9, 0.45),
	"vehicle": Color(0.9, 0.8, 0.3), "aircraft": Color(0.6, 0.85, 1.0), "veil": Color(0.9, 0.3, 0.3)}

var root: Control
var overlay: Overlay
var minimap: Minimap
var credits_label: Label
var power_label: Label
var power_bar: ProgressBar
var tab_buttons := {}
var grid: GridContainer
var cameos := {}
var current_tab := "structure"
var msg_box: VBoxContainer
var messages: Array = []        # [Label, time_created]
var info_label: Label
var help_panel: PanelContainer
var obj_panel: PanelContainer
var obj_label: RichTextLabel
var timer_label: Label
var sub_panel: PanelContainer
var sub_label: RichTextLabel
var special_box: VBoxContainer
var specials := {}              # id -> Button
var menu_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_body: RichTextLabel
var end_buttons: HBoxContainer
var pause_label: Label
var sell_btn: Button
var repair_btn: Button
var _refresh_t := 0.0
var _lance_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)

	overlay = Overlay.new()
	root.add_child(overlay)

	_build_sidebar()
	_build_objectives()
	_build_feed()
	_build_info()
	_build_help()
	_build_subtitles()
	_build_menu()
	_build_end()
	_rebuild_grid()
	Voice.line_started.connect(_on_line_started)
	Voice.line_finished.connect(_on_line_finished)


# ================================================================ construction

func _build_sidebar() -> void:
	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -SIDEBAR_W
	side.offset_right = 0
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(side)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	side.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := Label.new()
	title.text = "BASTION COMMAND"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(toggle_menu)
	top.add_child(menu_btn)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(SIDEBAR_W - 16, SIDEBAR_W - 40)
	vb.add_child(minimap)

	var row := HBoxContainer.new()
	vb.add_child(row)
	credits_label = Label.new()
	credits_label.add_theme_font_size_override("font_size", 18)
	credits_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(credits_label)
	power_label = Label.new()
	row.add_child(power_label)

	power_bar = ProgressBar.new()
	power_bar.show_percentage = false
	power_bar.custom_minimum_size = Vector2(0, 6)
	power_bar.max_value = 1.0
	power_bar.step = 0.0
	vb.add_child(power_bar)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	vb.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_tab.bind(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	var p: PlayerState = G.players[G.local_team]
	tab_buttons["veil"].visible = p.extra_factions.has("veil")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	special_box = VBoxContainer.new()
	special_box.add_theme_constant_override("separation", 3)
	vb.add_child(special_box)
	_lance_btn = add_special("_lance", "Halo Lance")
	_lance_btn.visible = false

	var tools := HBoxContainer.new()
	vb.add_child(tools)
	sell_btn = Button.new()
	sell_btn.text = "$ Sell"
	sell_btn.toggle_mode = true
	sell_btn.focus_mode = Control.FOCUS_NONE
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(func(): G.controller.set_mode(InputController.Mode.SELL))
	tools.add_child(sell_btn)
	repair_btn = Button.new()
	repair_btn.text = "+ Repair"
	repair_btn.toggle_mode = true
	repair_btn.focus_mode = Control.FOCUS_NONE
	repair_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_btn.pressed.connect(func(): G.controller.set_mode(InputController.Mode.REPAIR))
	tools.add_child(repair_btn)


func _build_objectives() -> void:
	obj_panel = PanelContainer.new()
	obj_panel.position = Vector2(12, 12)
	obj_panel.custom_minimum_size = Vector2(430, 0)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(obj_panel)
	obj_label = RichTextLabel.new()
	obj_label.bbcode_enabled = true
	obj_label.fit_content = true
	obj_label.scroll_active = false
	obj_label.custom_minimum_size = Vector2(414, 0)
	obj_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_label.add_theme_font_size_override("normal_font_size", 13)
	obj_label.add_theme_font_size_override("bold_font_size", 13)
	obj_panel.add_child(obj_label)

	timer_label = Label.new()
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_left = -300 - SIDEBAR_W / 2.0
	timer_label.offset_right = 300 - SIDEBAR_W / 2.0
	timer_label.offset_top = 10
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 22)
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root.add_child(timer_label)


func _build_feed() -> void:
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(14, 200)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_box)
	pause_label = Label.new()
	pause_label.text = "PAUSED  (P to resume)"
	pause_label.add_theme_font_size_override("font_size", 28)
	pause_label.add_theme_color_override("font_color", GOLD)
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.position = Vector2(-150 - SIDEBAR_W / 2.0, 60)
	pause_label.visible = false
	root.add_child(pause_label)


func _build_info() -> void:
	var p := PanelContainer.new()
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 12
	p.offset_top = -100
	p.offset_bottom = -12
	p.offset_right = 380
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(info_label)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.anchor_top = 1.0
	help_panel.anchor_bottom = 1.0
	help_panel.offset_left = 12
	help_panel.offset_top = -300
	help_panel.offset_bottom = -110
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.visible = G.mission != null and G.mission.number == 1
	root.add_child(help_panel)
	var l := Label.new()
	l.text = """CONTROLS  (F1 to hide)
LMB  select / drag box  •  Shift adds  •  double-click: all of type
RMB  move / attack / capture (Engineer) / board transport / rally
Ctrl+RMB  force attack  •  A+LMB  attack-move  •  S stop  •  D deploy / unload
Ctrl+1..9  group  •  1..9  recall (tap twice to jump)
Arrows / screen edge / MMB drag  pan  •  Wheel  zoom  •  Q/E  rotate
H  home base  •  Space  last alert  •  O  objectives  •  P  pause  •  Esc  menu
M  mute music  •  N  next track"""
	help_panel.add_child(l)


func _build_subtitles() -> void:
	sub_panel = PanelContainer.new()
	sub_panel.anchor_left = 0.5
	sub_panel.anchor_right = 0.5
	sub_panel.anchor_top = 1.0
	sub_panel.anchor_bottom = 1.0
	sub_panel.offset_left = -360 - SIDEBAR_W / 2.0 + 200
	sub_panel.offset_right = 360 - SIDEBAR_W / 2.0 + 200
	sub_panel.offset_top = -140
	sub_panel.offset_bottom = -110
	sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.visible = false
	root.add_child(sub_panel)
	sub_label = RichTextLabel.new()
	sub_label.bbcode_enabled = true
	sub_label.fit_content = true
	sub_label.scroll_active = false
	sub_label.custom_minimum_size = Vector2(700, 0)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_label.add_theme_font_size_override("normal_font_size", 16)
	sub_label.add_theme_font_size_override("bold_font_size", 16)
	sub_panel.add_child(sub_label)


func _centered_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -w * 0.5 - SIDEBAR_W / 2.0
	p.offset_right = w * 0.5 - SIDEBAR_W / 2.0
	p.offset_top = -h * 0.5
	p.offset_bottom = h * 0.5
	p.visible = false
	root.add_child(p)
	return p


func _build_menu() -> void:
	menu_panel = _centered_panel(320, 300)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	menu_panel.add_child(vb)
	var t := Label.new()
	t.text = "GAME MENU"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", GOLD)
	vb.add_child(t)
	for pair in [["Resume", toggle_menu], ["Restart Mission", _restart], ["Main Menu", Campaign.to_menu], ["Quit Game", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(pair[1])
		vb.add_child(b)


func _build_end() -> void:
	end_panel = _centered_panel(560, 420)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	end_panel.add_child(vb)
	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 36)
	vb.add_child(end_title)
	end_body = RichTextLabel.new()
	end_body.bbcode_enabled = true
	end_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(end_body)
	end_buttons = HBoxContainer.new()
	end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	end_buttons.add_theme_constant_override("separation", 12)
	vb.add_child(end_buttons)


func _restart() -> void:
	Voice.stop_all()
	get_tree().paused = false
	get_tree().reload_current_scene()


func toggle_menu() -> void:
	if G.game_over and not menu_panel.visible:
		return
	menu_panel.visible = not menu_panel.visible
	get_tree().paused = menu_panel.visible
	pause_label.visible = false


# ================================================================ specials

func add_special(id: String, text: String) -> Button:
	if specials.has(id):
		return specials[id]
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	b.pressed.connect(_on_special.bind(id))
	special_box.add_child(b)
	specials[id] = b
	return b


func set_special(id: String, text: String, enabled := true) -> void:
	if specials.has(id):
		var b: Button = specials[id]
		b.text = text
		b.disabled = not enabled
		b.visible = true


func remove_special(id: String) -> void:
	if specials.has(id):
		specials[id].queue_free()
		specials.erase(id)


func _on_special(id: String) -> void:
	if id == "_lance":
		var up := _uplink()
		if up and up.sw_charge >= 1.0 and not up.sw_used:
			G.controller.begin_target("HALO LANCE: LMB to fire, RMB to cancel", func(pos): G.mission.fire_player_lance(up, pos))
		return
	if G.mission:
		G.mission.special_action(id)


func _uplink() -> Structure:
	for e in G.entities:
		if e is Structure and e.alive and e.team == G.local_team and e.def.has("superweapon"):
			return e
	return null


# ================================================================ cameos

func _on_tab(tab: String) -> void:
	current_tab = tab
	_rebuild_grid()


func _tab_ids(tab: String) -> Array:
	var p: PlayerState = G.players[G.local_team]
	var out: Array = []
	if tab == "veil":
		for cat in ["infantry", "vehicle"]:
			for id in G.buildables(cat, "veil"):
				if p.is_allowed(id) and p.queue_cat(id) == "veil":
					out.append(id)
		return out
	for id in G.buildables(tab, p.faction):
		if p.is_allowed(id):
			out.append(id)
	return out


func _rebuild_grid() -> void:
	for c in grid.get_children():
		c.queue_free()
	cameos.clear()
	for t in tab_buttons.keys():
		tab_buttons[t].set_pressed_no_signal(t == current_tab)
	for id in _tab_ids(current_tab):
		var d: Dictionary = G.def_of(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(124, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = _tooltip(id)
		b.pressed.connect(_on_cameo_left.bind(id))
		b.gui_input.connect(_on_cameo_input.bind(id))
		var strip := ColorRect.new()
		strip.color = TAB_COLORS.get(current_tab, GOLD)
		strip.position = Vector2(1, 1)
		strip.size = Vector2(122, 3)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(strip)
		b.add_child(_cameo_label(d.get("name", id), Vector2(7, 5), 12, Color(0.95, 0.95, 0.9)))
		b.add_child(_cameo_label("$%d" % int(d.get("cost", 0)), Vector2(7, 21), 12, Color(0.5, 1.0, 0.55)))
		var status_l := _cameo_label("", Vector2(7, 37), 12, GOLD)
		b.add_child(status_l)
		var prog := ColorRect.new()
		prog.color = Color(0.3, 0.8, 1.0, 0.85)
		prog.position = Vector2(1, 53)
		prog.size = Vector2(0, 4)
		prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(prog)
		grid.add_child(b)
		cameos[id] = {"button": b, "status": status_l, "prog": prog}
	_refresh()


func _cameo_label(text: String, pos: Vector2, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	return l


func _tooltip(id: String) -> String:
	var d: Dictionary = G.def_of(id)
	var lines: Array = []
	lines.append("%s  —  $%d, %ds" % [d.get("name", id), int(d.get("cost", 0)), int(d.get("build_time", 0))])
	lines.append("HP %d   Armor: %s" % [int(d.get("hp", 0)), d.get("armor", "-")])
	if d.has("power"):
		lines.append("Power: %+d" % int(d["power"]))
	if d.has("weapon"):
		var w: Dictionary = G.weapon_def(d["weapon"])
		lines.append("Weapon: %s dmg, range %.1f, every %.1fs (%s targets)" % [int(w.get("damage", 0)), float(w.get("range", 0)), float(w.get("cooldown", 0)), w.get("targets", "ground")])
		var wh: Dictionary = G.rules.get("warheads", {}).get(w.get("warhead", ""), {})
		lines.append("Effective vs:  Inf %d%%  Light %d%%  Heavy %d%%  Bldg %d%%" % [
			int(wh.get("infantry", 1) * 100), int(wh.get("light", 1) * 100),
			int(wh.get("heavy", 1) * 100), int(wh.get("structure", 1) * 100)])
	var notes := {"engineer": "Captures buildings (RMB on them)", "heal": "Heals nearby infantry",
		"transport": "Carries infantry: RMB it with infantry, D to unload", "detector": "Reveals cloaked units nearby",
		"cloak": "Cloaked while not firing", "burrow": "Tunnels underground when travelling", "networked": "Networked: SIBYL can hijack it",
		"deploys": "D: deploy into a Construction Yard", "inhibitor": "Pushes back crystal growth while powered",
		"shelter": "Resonance shelter bubble", "superweapon": "Superweapon", "decoy": "Inflatable decoy: draws Halo Lance fire",
		"repair_vehicles": "Repairs nearby vehicles", "radar": "Enables the radar minimap", "limit": "Limit one"}
	for k in notes.keys():
		if d.has(k) and d[k]:
			lines.append(notes[k])
	if d.get("move", "") == "hover":
		lines.append("Hover: crosses water")
	elif d.get("move", "") == "air":
		lines.append("Aircraft: grounded by glass storms")
	elif d.get("move", "") == "jump":
		lines.append("Jump-jet: crosses any terrain")
	if d.has("capacity"):
		lines.append("Carries $%d of crystal per trip" % int(d["capacity"]))
	var pre: Array = d.get("prereq", [])
	if not pre.is_empty() and G.players[G.local_team].queue_cat(id) != "veil":
		var names: Array = []
		for r in pre:
			names.append(G.def_of(r).get("name", r))
		lines.append("Requires: " + ", ".join(PackedStringArray(names)))
	lines.append("LMB: build / place    RMB: cancel")
	return "\n".join(PackedStringArray(lines))


func _on_cameo_left(id: String) -> void:
	var p: PlayerState = G.players[G.local_team]
	var cat := p.queue_cat(id)
	var is_bldg := cat == "structure" or cat == "defense"
	if is_bldg and p.ready_structure[cat] == id:
		G.controller.begin_place(id)
		return
	if is_bldg and (p.ready_structure[cat] != "" or not p.queues[cat].is_empty()):
		notify("Already building")
		return
	if not p.can_build(id):
		var missing := p.missing_prereqs(id)
		if G.def_of(id).has("limit") and p.count_of(id) >= int(G.def_of(id)["limit"]):
			notify("Limit reached")
		elif missing.is_empty():
			notify("Cannot build that now")
		else:
			notify("Requires: " + ", ".join(PackedStringArray(missing)))
		return
	if not p.queue_item(id):
		notify("Queue full")


func _on_cameo_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		G.players[G.local_team].cancel_item(id)
		get_viewport().set_input_as_handled()


# ================================================================ runtime

func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.1
		_refresh()
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(messages.size() - 1, -1, -1):
		var age: float = now - messages[i][1]
		var l: Label = messages[i][0]
		if age > 7.0:
			l.queue_free()
			messages.remove_at(i)
		elif age > 6.0:
			l.modulate.a = 7.0 - age
	msg_box.position.y = obj_panel.position.y + obj_panel.size.y + 8 if obj_panel.visible else 12.0


func _refresh() -> void:
	if G.players.is_empty():
		return
	var p: PlayerState = G.players[G.local_team]
	credits_label.text = "$ %d" % int(p.credits)
	power_label.text = "Power %d / %d" % [p.power_used, p.power_produced]
	power_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if p.low_power() else Color(0.8, 0.85, 0.8))
	power_bar.value = clampf(float(p.power_used) / maxf(p.power_produced, 1.0), 0.0, 1.0)
	var blink := int(Time.get_ticks_msec() / 350) % 2 == 0
	for t in tab_buttons.keys():
		var label: String = ""
		for tt in TABS:
			if tt[0] == t:
				label = tt[1]
		if p.ready_structure.get(t, "") != "":
			label += "!"
		tab_buttons[t].text = label
	for id in cameos.keys():
		var c: Dictionary = cameos[id]
		var b: Button = c["button"]
		var status: Label = c["status"]
		var prog: ColorRect = c["prog"]
		var cat := p.queue_cat(id)
		var is_ready: bool = p.ready_structure.get(cat, "") == id
		var progress := p.progress_of(id)
		var count := p.queue_count(id)
		var can := p.can_build(id)
		b.modulate = Color.WHITE if (can or is_ready or count > 0) else Color(0.45, 0.45, 0.45)
		if is_ready:
			status.text = "READY" if blink else ""
			prog.size.x = 122
		elif progress >= 0.0:
			status.text = "%d%%%s" % [int(progress * 100), (" x%d" % count) if count > 1 else ""]
			prog.size.x = 122 * progress
		elif count > 0:
			status.text = "x%d queued" % count
			prog.size.x = 0
		else:
			status.text = "" if can else "locked"
			prog.size.x = 0
	var up := _uplink()
	if up:
		if up.sw_used:
			set_special("_lance", "Halo Lance: spent", false)
		elif up.sw_charge >= 1.0:
			set_special("_lance", "HALO LANCE READY" if blink else "Halo Lance ready", true)
		else:
			set_special("_lance", "Halo Lance charging %d%%" % int(up.sw_charge * 100), false)
	else:
		_lance_btn.visible = false
	var ctl: InputController = G.controller
	if ctl:
		sell_btn.set_pressed_no_signal(ctl.mode == InputController.Mode.SELL)
		repair_btn.set_pressed_no_signal(ctl.mode == InputController.Mode.REPAIR)
		info_label.text = _selection_text(ctl.selection)
		(info_label.get_parent() as Control).visible = info_label.text != ""
	if G.mission:
		var parts: Array = []
		for k in G.mission.timers.keys():
			var tm: Dictionary = G.mission.timers[k]
			if float(tm["t"]) < 0.0:
				parts.append(tm["text"])
				continue
			var secs := int(ceil(float(tm["t"])))
			parts.append("%s  %d:%02d" % [tm["text"], secs / 60, secs % 60])
		timer_label.text = "     ".join(PackedStringArray(parts))


func refresh_objectives() -> void:
	if G.mission == null:
		return
	var lines: Array = ["[color=#d9a833][b]OBJECTIVES[/b][/color]  [color=#777777](O to hide)[/color]"]
	for o in G.mission.objectives:
		if not o["visible"]:
			continue
		var mark := "[ ]"
		var col := "#e6e6e0"
		match o["state"]:
			"done":
				mark = "[x]"
				col = "#7fdc85"
			"failed":
				mark = "[-]"
				col = "#e05a4c"
		var kind := ""
		match o["kind"]:
			"secondary": kind = "[color=#8ccff5]Secondary:[/color] "
			"bonus": kind = "[color=#f2d06b]Bonus:[/color] "
		lines.append("[color=%s]%s[/color] %s[color=%s]%s[/color]" % [col, mark, kind, col, o["text"]])
	obj_label.text = "\n".join(PackedStringArray(lines))


func _selection_text(sel: Array) -> String:
	var valid: Array = []
	for e in sel:
		if is_instance_valid(e) and e.alive:
			valid.append(e)
	if valid.is_empty():
		return ""
	if valid.size() == 1:
		var e = valid[0]
		var owner_name: String = G.players[e.team].display
		var s := "%s  [%s]\nHP %d / %d" % [e.display_name(), owner_name, int(e.hp), int(e.max_hp)]
		if e.rank > 0:
			var rank_names: Array = ["", "Veteran", "Elite"]
			s += "   %s" % rank_names[e.rank]
		if e is Harvester:
			s += "\nCargo $%d / %d  —  %s" % [int(e.cargo), int(e.capacity), e.state_text()]
		elif e is Structure:
			s += "   Power %+d" % e.power
			if not e.produces.is_empty() and e.team == G.local_team:
				s += "\nRMB on the ground sets the rally point"
		elif e is Unit:
			if e.kills > 0:
				s += "   Kills %d" % e.kills
			if e.transport_cap() > 0:
				s += "\nPassengers %d / %d  (D to unload)" % [e.passengers.size(), e.transport_cap()]
			if e.def.has("deploys") and e.team == G.local_team:
				s += "\nD: deploy"
			if e.is_engineer() and e.team == G.local_team:
				s += "\nRMB a building to capture it"
			if e.def.get("networked", false):
				s += "\nNetworked (can be hijacked)"
		return s
	var counts := {}
	for e in valid:
		var n: String = e.display_name()
		counts[n] = counts.get(n, 0) + 1
	var parts: Array = []
	for n in counts.keys():
		parts.append("%d× %s" % [counts[n], n])
	return "%d selected\n%s" % [valid.size(), ",  ".join(PackedStringArray(parts))]


func notify(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	l.add_theme_font_size_override("font_size", 15)
	msg_box.add_child(l)
	messages.append([l, Time.get_ticks_msec() / 1000.0])
	while messages.size() > 6:
		var old: Label = messages[0][0]
		old.queue_free()
		messages.remove_at(0)


# ================================================================ subtitles

func _on_line_started(_speaker: String, speaker_name: String, text: String, color: Color) -> void:
	sub_label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), speaker_name, text]
	sub_panel.visible = true


func _on_line_finished(_speaker: String) -> void:
	if not Voice.dialog_active():
		sub_panel.visible = false


# ================================================================ mission end

func show_mission_end(victory: bool, reason: String) -> void:
	for c in end_buttons.get_children():
		c.queue_free()
	end_title.text = "MISSION ACCOMPLISHED" if victory else "MISSION FAILED"
	end_title.add_theme_color_override("font_color", GOLD if victory else Color(1, 0.3, 0.25))
	var lines: Array = []
	var m: Dictionary = Campaign.mission_info(G.mission.number)
	lines.append("[color=#d9a833]Mission %d: %s[/color]\n" % [m["id"], m["title"]])
	if not victory and reason != "":
		lines.append("[color=#ff8070]%s[/color]\n" % reason)
	for o in G.mission.objectives:
		if not o["visible"]:
			continue
		var st := "Complete" if o["state"] == "done" else ("Failed" if o["state"] == "failed" else "Incomplete")
		var col := "#7fdc85" if o["state"] == "done" else ("#e05a4c" if o["state"] == "failed" else "#aaaaaa")
		lines.append("[color=%s]%s[/color]  %s (%s)" % [col, st, o["text"], o["kind"]])
	end_body.text = "\n".join(PackedStringArray(lines))
	if victory:
		var b := Button.new()
		b.text = "Continue" if Campaign.mission_index <= Campaign.MISSIONS.size() and not Campaign.completed else "Epilogue"
		b.custom_minimum_size = Vector2(170, 42)
		b.pressed.connect(Campaign.advance)
		end_buttons.add_child(b)
		b.grab_focus()
	else:
		var r := Button.new()
		r.text = "Retry Mission"
		r.custom_minimum_size = Vector2(170, 42)
		r.pressed.connect(_restart)
		end_buttons.add_child(r)
		r.grab_focus()
	var mm := Button.new()
	mm.text = "Main Menu"
	mm.custom_minimum_size = Vector2(140, 42)
	mm.pressed.connect(Campaign.to_menu)
	end_buttons.add_child(mm)
	end_panel.visible = true
	menu_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P and not G.game_over and not menu_panel.visible:
			get_tree().paused = not get_tree().paused
			pause_label.visible = get_tree().paused
		elif event.keycode == KEY_F1:
			help_panel.visible = not help_panel.visible
		elif event.keycode == KEY_O:
			obj_panel.visible = not obj_panel.visible
		elif event.keycode == KEY_F10:
			toggle_menu()
		elif event.keycode == KEY_M:
			Music.toggle_mute()
		elif event.keycode == KEY_N:
			Music.skip()
		elif event.keycode == KEY_ESCAPE and menu_panel.visible:
			toggle_menu()
			get_viewport().set_input_as_handled()
