class_name HUD
extends CanvasLayer
## RA2-style sidebar (radar, credits, power, tabbed build cameos, sell/repair),
## EVA message feed, selection info, help and end-of-match panels.

const SIDEBAR_W := 272
const GOLD := Color(0.85, 0.66, 0.2)
const PANEL_BG := Color(0.055, 0.065, 0.08, 0.95)
const TABS := [["structure", "Base"], ["defense", "Defense"], ["infantry", "Infantry"], ["vehicle", "Vehicles"]]
const TAB_COLORS := {"structure": Color(0.35, 0.6, 1.0), "defense": Color(1.0, 0.55, 0.25), "infantry": Color(0.45, 0.9, 0.45), "vehicle": Color(0.9, 0.8, 0.3)}

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
var over_panel: PanelContainer
var over_label: Label
var pause_label: Label
var sell_btn: Button
var repair_btn: Button
var _refresh_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	overlay = Overlay.new()
	root.add_child(overlay)

	_build_sidebar()
	_build_feed()
	_build_info()
	_build_help()
	_build_game_over()
	_rebuild_grid()


# ================================================================ construction

func _make_theme() -> Theme:
	var th := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.border_color = GOLD.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(8)
	th.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.12, 0.15)
	normal.border_color = Color(0.3, 0.3, 0.34)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.17, 0.21)
	hover.border_color = GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.2, 0.12)
	pressed.border_color = GOLD
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.08, 0.09)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("hover_pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.9, 0.9, 0.88))
	th.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_font_size("font_size", "Button", 13)
	th.set_color("font_color", "Label", Color(0.9, 0.9, 0.88))
	th.set_font_size("font_size", "Label", 13)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.12)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.3, 0.85, 0.4)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fg)
	return th


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
	vb.add_theme_constant_override("separation", 6)
	side.add_child(vb)

	var title := Label.new()
	title.text = "ASHFALL  //  BASTION COMMAND"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(SIDEBAR_W - 16, SIDEBAR_W - 16)
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
	tabs.add_theme_constant_override("separation", 3)
	vb.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_tab.bind(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

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


func _build_feed() -> void:
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(14, 12)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_box)
	pause_label = Label.new()
	pause_label.text = "PAUSED  (P to resume)"
	pause_label.add_theme_font_size_override("font_size", 28)
	pause_label.add_theme_color_override("font_color", GOLD)
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.position = Vector2(-150, 60)
	pause_label.visible = false
	root.add_child(pause_label)


func _build_info() -> void:
	var p := PanelContainer.new()
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 12
	p.offset_top = -96
	p.offset_bottom = -12
	p.offset_right = 380
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	info_label = Label.new()
	info_label.text = ""
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(info_label)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.position = Vector2(14, 150)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)
	var l := Label.new()
	l.text = """CONTROLS  (F1 to hide)
LMB  select / drag box  •  Shift adds  •  double-click: all of type
RMB  move / attack / harvest / set rally (factory selected)
A + LMB  attack-move   •   S  stop   •   Esc  cancel / deselect
Ctrl+1..9  group   •   1..9  recall (tap twice to jump)
Arrows / screen edge / MMB drag  pan   •   Wheel  zoom   •   Q/E  rotate
H  home base   •   Space  last alert   •   P  pause
M  mute music   •   N  next track
Sidebar: LMB queue / place  •  RMB cancel (refund)"""
	help_panel.add_child(l)


func _build_game_over() -> void:
	over_panel = PanelContainer.new()
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	over_panel.offset_left = -200
	over_panel.offset_right = 200 - SIDEBAR_W
	over_panel.offset_top = -80
	over_panel.offset_bottom = 80
	over_panel.visible = false
	root.add_child(over_panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	over_panel.add_child(vb)
	over_label = Label.new()
	over_label.add_theme_font_size_override("font_size", 40)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(over_label)
	var again := Button.new()
	again.text = "Play again (new map)"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(_on_play_again)
	vb.add_child(again)


func _on_play_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ================================================================ cameos

func _on_tab(tab: String) -> void:
	current_tab = tab
	_rebuild_grid()


func _rebuild_grid() -> void:
	for c in grid.get_children():
		c.queue_free()
	cameos.clear()
	for t in tab_buttons.keys():
		tab_buttons[t].set_pressed_no_signal(t == current_tab)
	var p: PlayerState = G.players[G.local_team]
	for id in G.buildables(current_tab, p.faction):
		var d: Dictionary = G.def_of(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(124, 64)
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
		var name_l := _cameo_label(d.get("name", id), Vector2(7, 6), 13, Color(0.95, 0.95, 0.9))
		b.add_child(name_l)
		var cost_l := _cameo_label("$%d" % int(d.get("cost", 0)), Vector2(7, 24), 12, Color(0.5, 1.0, 0.55))
		b.add_child(cost_l)
		var status_l := _cameo_label("", Vector2(7, 41), 12, GOLD)
		b.add_child(status_l)
		var prog := ColorRect.new()
		prog.color = Color(0.3, 0.8, 1.0, 0.85)
		prog.position = Vector2(1, 59)
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
		lines.append("Weapon: %s dmg, range %.1f, every %.1fs" % [int(w.get("damage", 0)), float(w.get("range", 0)), float(w.get("cooldown", 0))])
		var wh: Dictionary = G.rules.get("warheads", {}).get(w.get("warhead", ""), {})
		lines.append("Effective vs:  Inf %d%%  Light %d%%  Heavy %d%%  Bldg %d%%" % [
			int(wh.get("infantry", 1) * 100), int(wh.get("light", 1) * 100),
			int(wh.get("heavy", 1) * 100), int(wh.get("structure", 1) * 100)])
	if d.has("capacity"):
		lines.append("Carries $%d of crystal per trip" % int(d["capacity"]))
	var pre: Array = d.get("prereq", [])
	if not pre.is_empty():
		var names: Array = []
		for r in pre:
			names.append(G.def_of(r).get("name", r))
		lines.append("Requires: " + ", ".join(PackedStringArray(names)))
	lines.append("LMB: build / place    RMB: cancel")
	return "\n".join(PackedStringArray(lines))


func _on_cameo_left(id: String) -> void:
	var p: PlayerState = G.players[G.local_team]
	var d: Dictionary = G.def_of(id)
	var cat: String = d.get("category", "")
	var is_bldg := cat == "structure" or cat == "defense"
	if is_bldg and p.ready_structure[cat] == id:
		G.controller.begin_place(id)
		return
	if is_bldg and (p.ready_structure[cat] != "" or not p.queues[cat].is_empty()):
		notify("Already building")
		return
	if not p.can_build(id):
		var missing := p.missing_prereqs(id)
		if missing.is_empty():
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
	# expire messages
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(messages.size() - 1, -1, -1):
		var age: float = now - messages[i][1]
		var l: Label = messages[i][0]
		if age > 6.0:
			l.queue_free()
			messages.remove_at(i)
		elif age > 5.0:
			l.modulate.a = 6.0 - age


func _refresh() -> void:
	if G.players.is_empty():
		return
	var p: PlayerState = G.players[G.local_team]
	credits_label.text = "$ %d" % int(p.credits)
	power_label.text = "Power %d / %d" % [p.power_used, p.power_produced]
	power_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if p.low_power() else Color(0.8, 0.85, 0.8))
	power_bar.value = clampf(float(p.power_used) / maxf(p.power_produced, 1.0), 0.0, 1.0)
	var fill := power_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = Color(1, 0.3, 0.25) if p.low_power() else Color(0.3, 0.85, 0.4)
	var blink := int(Time.get_ticks_msec() / 350) % 2 == 0
	for t in tab_buttons.keys():
		var label: String = ""
		for tt in TABS:
			if tt[0] == t:
				label = tt[1]
		if p.ready_structure.get(t, "") != "":
			label += " !"
		tab_buttons[t].text = label
	for id in cameos.keys():
		var c: Dictionary = cameos[id]
		var b: Button = c["button"]
		var status: Label = c["status"]
		var prog: ColorRect = c["prog"]
		var d: Dictionary = G.def_of(id)
		var cat: String = d.get("category", "")
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
	var ctl: InputController = G.controller
	if ctl:
		sell_btn.set_pressed_no_signal(ctl.mode == InputController.Mode.SELL)
		repair_btn.set_pressed_no_signal(ctl.mode == InputController.Mode.REPAIR)
		info_label.text = _selection_text(ctl.selection)
		(info_label.get_parent() as Control).visible = info_label.text != ""


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
		elif e.kills > 0:
			s += "   Kills %d" % e.kills
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


func show_game_over(victory: bool) -> void:
	over_label.text = "VICTORY" if victory else "DEFEAT"
	over_label.add_theme_color_override("font_color", GOLD if victory else Color(1, 0.3, 0.25))
	over_panel.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P and not G.game_over:
			get_tree().paused = not get_tree().paused
			pause_label.visible = get_tree().paused
		elif event.keycode == KEY_F1:
			help_panel.visible = not help_panel.visible
		elif event.keycode == KEY_M:
			Music.toggle_mute()
		elif event.keycode == KEY_N:
			Music.skip()
