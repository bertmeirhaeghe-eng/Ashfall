class_name InputController
extends Node
## Mouse & keyboard command layer (RA2 style):
##  LMB click/drag  select (Shift adds), double-click selects all of that type on screen
##  RMB             context order: move / attack / capture / board / harvest / dock / rally
##  Ctrl+RMB        force-attack anything that isn't yours
##  A + LMB         attack-move        S  stop        D  deploy / unload
##  Ctrl+1..9       make group         1..9  recall group
##  Esc             cancel mode / deselect / game menu
## Selected units answer with a spoken reaction (Voice.unit_ack).

enum Mode { NONE, PLACE, SELL, REPAIR, ATTACK_MOVE, TARGET }

var selection: Array = []
var groups := {}
var mode := Mode.NONE
var place_id := ""
var target_label := ""
var target_callback: Callable
var drag_start := Vector2.ZERO
var dragging := false
var _pressed_left := false
var _ghost: MeshInstance3D
var _ghost_cell := Vector2i.ZERO
var _last_click_t := -10.0
var _last_click_def := ""
var _last_group := -1
var _last_group_t := -10.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func forget(e: Entity) -> void:
	if selection.has(e):
		e.set_selected(false)
	selection.erase(e)
	for k in groups.keys():
		groups[k].erase(e)


func me() -> PlayerState:
	return G.players[G.local_team]


# ================================================================ modes

func begin_place(id: String) -> void:
	cancel_mode()
	mode = Mode.PLACE
	place_id = id
	var d: Dictionary = G.def_of(id)
	_ghost = MeshFactory.ghost(Vector2i(int(d["size"][0]), int(d["size"][1])))
	G.world.add_child(_ghost)


## Superweapon / ability targeting: next LMB on the ground calls cb(world_pos).
func begin_target(label: String, cb: Callable) -> void:
	cancel_mode()
	mode = Mode.TARGET
	target_label = label
	target_callback = cb


func set_mode(m: Mode) -> void:
	var same := mode == m
	cancel_mode()
	if not same:
		mode = m


func cancel_mode() -> void:
	mode = Mode.NONE
	place_id = ""
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func mode_label() -> String:
	match mode:
		Mode.PLACE: return "PLACE: LMB to build, RMB to cancel"
		Mode.SELL: return "SELL"
		Mode.REPAIR: return "REPAIR"
		Mode.ATTACK_MOVE: return "ATTACK-MOVE"
		Mode.TARGET: return target_label
	return ""


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if G.game_over:
		return
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if _pressed_left and not dragging and event.position.distance_to(drag_start) > 6.0:
			dragging = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			match mode:
				Mode.PLACE:
					_try_place()
					return
				Mode.SELL, Mode.REPAIR:
					_structure_action(mb.position, mb.shift_pressed)
					return
				Mode.ATTACK_MOVE:
					_order_attack_move(mb.position)
					mode = Mode.NONE
					return
				Mode.TARGET:
					var gp: Vector3 = G.camera.screen_to_ground(mb.position)
					var cb := target_callback
					cancel_mode()
					if cb.is_valid():
						cb.call(gp)
					return
			_pressed_left = true
			dragging = false
			drag_start = mb.position
		elif _pressed_left:
			_pressed_left = false
			if dragging:
				_box_select(drag_start, mb.position, mb.shift_pressed)
			else:
				_click_select(mb.position, mb.shift_pressed, mb.double_click)
			dragging = false
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if mode != Mode.NONE:
			cancel_mode()
			return
		_context_order(mb.position, mb.ctrl_pressed)


func _key(k: InputEventKey) -> void:
	var num: int = int(k.keycode) - int(KEY_0)
	if num >= 1 and num <= 9:
		if k.ctrl_pressed or k.meta_pressed:
			groups[num] = _own_units(selection)
			G.hud.notify(tr("Group %d set (%d)") % [num, groups[num].size()])
		else:
			var g: Array = groups.get(num, [])
			var valid: Array = []
			for e in g:
				if is_instance_valid(e) and e.alive and e.team == G.local_team:
					valid.append(e)
			if not valid.is_empty():
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_group_t < 0.4 and _last_group == num:
					G.camera.focus_on(valid[0].position)
				_last_group_t = now
				_last_group = num
				_set_selection(valid)
				_ack(valid, "select")
		return
	match k.keycode:
		KEY_S:
			for u in _own_units(selection):
				u.cmd_stop()
		KEY_A:
			if not _own_units(selection).is_empty():
				set_mode(Mode.ATTACK_MOVE)
		KEY_D:
			var done := false
			for u in _own_units(selection):
				if u.deploy():
					done = true
			if not done and not _own_units(selection).is_empty():
				G.hud.notify("Nothing to deploy")
		KEY_ESCAPE:
			if mode != Mode.NONE:
				cancel_mode()
			elif not selection.is_empty():
				_set_selection([])
			else:
				G.hud.toggle_menu()
				get_viewport().set_input_as_handled()
		KEY_H:
			var cy := _first_structure("construction_yard")
			if cy:
				G.camera.focus_on(cy.position)
		KEY_SPACE:
			if me().last_attack_warning > 0:
				G.camera.focus_on(me().last_attack_pos)


func _process(_delta: float) -> void:
	if _pressed_left and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pressed_left = false
		if dragging:
			_box_select(drag_start, get_viewport().get_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
		dragging = false
	if mode == Mode.PLACE and _ghost:
		var gp: Vector3 = G.camera.screen_to_ground(get_viewport().get_mouse_position())
		var d: Dictionary = G.def_of(place_id)
		var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
		_ghost_cell = Vector2i(floori(gp.x - size.x * 0.5 + 0.5), floori(gp.z - size.y * 0.5 + 0.5))
		var gh: Vector2 = G.map.footprint_height(_ghost_cell, size)
		_ghost.position = Vector3(_ghost_cell.x + size.x * 0.5, gh.y + 0.3, _ghost_cell.y + size.y * 0.5)
		var ok: bool = G.can_place(G.local_team, place_id, _ghost_cell)
		var m := _ghost.material_override as StandardMaterial3D
		m.albedo_color = Color(0.2, 1.0, 0.3, 0.35) if ok else Color(1.0, 0.2, 0.2, 0.35)
		if me().ready_structure.get(G.def_of(place_id).get("category", ""), "") != place_id:
			cancel_mode()


# ================================================================ selection

func _set_selection(arr: Array) -> void:
	for e in selection:
		if is_instance_valid(e):
			e.set_selected(false)
	selection = arr.duplicate()
	for e in selection:
		e.set_selected(true)


func _own_units(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		if is_instance_valid(e) and e.alive and e is Unit and e.team == G.local_team:
			out.append(e)
	return out


func _ack(units: Array, kind: String) -> void:
	var own := _own_units(units)
	if own.is_empty():
		return
	Voice.unit_ack(own[0].def.get("voice", "infantry"), kind)


func entity_at(screen_pos: Vector2) -> Entity:
	var cam: Camera3D = G.camera.cam
	var best: Entity = null
	var best_d := 22.0
	for e in G.entities:
		if not e.alive or e is Structure or not e.visible_to(G.local_team) or e.hidden_underground() and e.team != G.local_team:
			continue
		var wp: Vector3 = e.position + Vector3(0, e.bar_height * 0.4, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen_pos)
		var lim: float = 14.0 + e.radius * 18.0
		if d < lim and d < best_d:
			best_d = d
			best = e
	if best:
		return best
	var gp: Vector3 = G.camera.screen_to_ground(screen_pos)
	for e in G.entities:
		if e.alive and e is Structure and e.visible_to(G.local_team) and e.contains_point(gp, 0.1):
			return e
	return null


func _click_select(pos: Vector2, shift: bool, dbl: bool) -> void:
	var e := entity_at(pos)
	if e == null:
		if not shift:
			_set_selection([])
		return
	var now := Time.get_ticks_msec() / 1000.0
	if e.team == G.local_team and e is Unit and (dbl or (now - _last_click_t < 0.35 and _last_click_def == e.def_id)):
		var all: Array = []
		var vp := get_viewport().get_visible_rect()
		for o in G.entities:
			if o.alive and o is Unit and o.team == G.local_team and o.def_id == e.def_id:
				if not G.camera.cam.is_position_behind(o.position) and vp.has_point(G.camera.cam.unproject_position(o.position)):
					all.append(o)
		_set_selection(all)
	elif shift and e.team == G.local_team and e is Unit:
		var arr := selection.duplicate()
		if arr.has(e):
			arr.erase(e)
		else:
			arr.append(e)
		_set_selection(_own_units(arr))
	else:
		_set_selection([e])
	_ack([e], "select")
	_last_click_t = now
	_last_click_def = e.def_id


func _box_select(a: Vector2, b: Vector2, shift: bool) -> void:
	var r := Rect2(a, b - a).abs()
	var cam: Camera3D = G.camera.cam
	var picked: Array = selection.duplicate() if shift else []
	for e in G.entities:
		if not (e.alive and e is Unit and e.team == G.local_team):
			continue
		if cam.is_position_behind(e.position):
			continue
		if r.has_point(cam.unproject_position(e.position + Vector3(0, 0.3, 0))) and not picked.has(e):
			picked.append(e)
	var combat: Array = picked.filter(func(u): return not (u is Harvester))
	if not combat.is_empty() and combat.size() != picked.size() and not shift:
		picked = combat
	_set_selection(_own_units(picked))
	_ack(selection, "select")


func drag_rect() -> Rect2:
	if not dragging:
		return Rect2()
	return Rect2(drag_start, get_viewport().get_mouse_position() - drag_start).abs()


# ================================================================ orders

func _context_order(pos: Vector2, force := false) -> void:
	var units := _own_units(selection)
	var gp: Vector3 = G.camera.screen_to_ground(pos)
	var cell: Vector2i = G.map.world_to_cell(gp)
	if units.is_empty():
		if selection.size() == 1 and is_instance_valid(selection[0]) and selection[0] is Structure \
				and selection[0].team == G.local_team and not selection[0].produces.is_empty():
			selection[0].rally_cell = cell
			Fx.marker(gp, Color(1.0, 0.9, 0.3, 0.9))
			G.hud.notify("Rally point set")
		return
	var t := entity_at(pos)
	if t and t.team != G.local_team:
		# engineers and other specialists interact instead of shooting
		var enterers: Array = units.filter(func(u): return G.mission and G.mission.can_interact(u, t))
		var shooters: Array = units.filter(func(u): return not enterers.has(u))
		for u in enterers:
			u.cmd_enter(t)
		var attackable: bool = G.is_enemy(G.local_team, t.team) or force or t.def.get("targetable", false)
		var attacked := false
		if attackable:
			for u in shooters:
				if u.can_target(t):
					u.cmd_attack(t)
					attacked = true
		if not enterers.is_empty() or attacked:
			Fx.marker(t.position, Color(1.0, 0.25, 0.2, 0.9) if attacked else Color(0.4, 0.8, 1.0, 0.9))
			_ack(enterers if enterers.size() > 0 and not attacked else shooters, "attack" if attacked else "move")
			return
	# board an own transport
	if t and t is Unit and t.team == G.local_team and t.transport_cap() > 0 and not units.has(t):
		var inf: Array = units.filter(func(u): return u.is_infantry)
		if not inf.is_empty():
			for u in inf:
				u.cmd_enter(t)
			_ack(inf, "move")
			return
	# own-side interactions defined by the mission (repairs, plants ...)
	if t and t.team == G.local_team and G.mission:
		var ent: Array = units.filter(func(u): return G.mission.can_interact(u, t))
		if not ent.is_empty():
			for u in ent:
				u.cmd_enter(t)
			_ack(ent, "move")
			return
	var harvesters: Array = units.filter(func(u): return u is Harvester)
	var others: Array = units.filter(func(u): return not (u is Harvester))
	if t and t is Structure and t.def_id == "refinery" and t.team == G.local_team:
		for hv in harvesters:
			hv.cmd_dock(t)
		harvesters = []
	elif G.map.harvestable(cell):
		for hv in harvesters:
			hv.cmd_harvest_at(cell)
		harvesters = []
	_group_move(others + harvesters, cell)
	Fx.marker(G.map.cell_to_world(cell), Color(0.4, 1.0, 0.4, 0.9))
	_ack(units, "move")


func _group_move(units: Array, cell: Vector2i, attack_move := false) -> void:
	if units.is_empty():
		return
	var mc: String = units[0].move_class
	if mc == "air" or mc == "jump":
		mc = "ground"
	var cells: Array = G.map.spread_cells(cell, units.size(), mc)
	var center: Vector3 = G.map.cell_to_world(cell)
	units.sort_custom(func(a, b): return a.position.distance_squared_to(center) < b.position.distance_squared_to(center))
	for i in units.size():
		if attack_move:
			units[i].cmd_attack_move(cells[i])
		else:
			units[i].cmd_move(cells[i])


func _order_attack_move(pos: Vector2) -> void:
	var gp: Vector3 = G.camera.screen_to_ground(pos)
	_group_move(_own_units(selection), G.map.world_to_cell(gp), true)
	Fx.marker(gp, Color(1.0, 0.6, 0.2, 0.9))
	_ack(selection, "attack")


func _try_place() -> void:
	if G.place_structure(G.local_team, place_id, _ghost_cell):
		Sfx.ui("place", 0.0)
		cancel_mode()
	else:
		Sfx.ui("error")
		G.hud.notify("Cannot place there")


func _structure_action(pos: Vector2, keep_mode: bool) -> void:
	var e = entity_at(pos)
	if e == null or not (e is Structure) or e.team != G.local_team:
		return
	if mode == Mode.SELL:
		if e.def.get("invulnerable", false):
			G.hud.notify("That cannot be sold")
		else:
			Sfx.ui("sell")
			e.sell()
	elif mode == Mode.REPAIR:
		e.repairing = not e.repairing
		G.hud.notify("Repairing" if e.repairing else "Repair stopped")
	if not keep_mode:
		cancel_mode()


func _first_structure(def_id: String) -> Structure:
	for e in G.entities:
		if e.alive and e is Structure and e.team == G.local_team and e.def_id == def_id:
			return e
	return null


# ================================================================ cursor

## Which 3D cursor icon (Cursor3D) fits the current mode / hover target:
## "arrow" default select, "move", "attack", "sell", "repair", "target"
## (ability targeting) or "place" (structure ghost, tinted by place_ok()).
func cursor_kind(pos: Vector2) -> String:
	match mode:
		Mode.SELL: return "sell"
		Mode.REPAIR: return "repair"
		Mode.ATTACK_MOVE: return "attack"
		Mode.TARGET: return "target"
		Mode.PLACE: return "place"
	var units := _own_units(selection)
	if units.is_empty():
		if selection.size() == 1 and is_instance_valid(selection[0]) and selection[0] is Structure \
				and selection[0].team == G.local_team and not selection[0].produces.is_empty():
			return "move"   # setting a rally point
		return "arrow"
	var t := entity_at(pos)
	if t == null:
		return "move"
	if t.team == G.local_team:
		return "move"
	if G.is_enemy(G.local_team, t.team) or t.def.get("targetable", false):
		return "attack"
	return "move"


## Whether the structure ghost could be placed at its current cell.
func place_ok() -> bool:
	return _ghost != null and G.can_place(G.local_team, place_id, _ghost_cell)
