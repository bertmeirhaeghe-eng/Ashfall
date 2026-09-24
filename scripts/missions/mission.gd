class_name Mission
extends Node
## Base class for campaign missions. A mission builds its map, spawns its
## forces, tracks objectives and scripted events, speaks its dialogue through
## the Voice system and decides victory / defeat. Completing every primary
## objective wins the mission and moves the campaign on to the next briefing.

const PLAYER := 0
const ENEMY := 1
const NEUTRAL := 2
const ALLY := 3
const HOSTILE := 4

const BASTION_BLUE := Color(0.2, 0.5, 1.0)
const VEIL_RED := Color(0.9, 0.15, 0.1)

var number := 1
var objectives: Array = []       # [{id, text, kind, state, visible}]
var ended := false
var won := false
var auto_win := true             # win as soon as every primary objective is done
var pending_flags := {}          # campaign flags written only if the mission is won
var markers: Array = []          # [{pos, color, label, node}]
var timers := {}                 # key -> {"text": String, "t": float, "visible": bool}
var start_credits := 5000
var lance_single_use := false
var time := 0.0
var _events: Array = []          # [{t, f}]
var _once := {}
var _unit_lost_t := -100.0
var _win_t := -1.0
var _ai: Array = []


# ================================================================ overridables

## Objectives shown on the briefing screen: [[kind, text], ...]
func objective_preview() -> Array:
	return []


## Lighting / sky / weather for this mission.
func theme() -> Dictionary:
	return {}


func build_map(_map: MapGrid) -> void:
	pass


## Spawn bases, units and scripted objects.
func setup() -> void:
	pass


## Called once the HUD exists: intro dialogue, first objectives.
func begin() -> void:
	pass


func tick(_delta: float) -> void:
	pass


# hooks called by the engine
func on_entity_died(_e: Entity, _killer: Entity) -> void:
	pass


func on_damaged(_e: Entity, _attacker: Entity) -> void:
	pass


func modify_damage(_e: Entity, dmg: float, _attacker: Entity) -> float:
	return dmg


## A unit reached an entity it was ordered to enter. Return true if handled.
func on_enter(_u: Unit, _target: Entity) -> bool:
	return false


func on_captured(_s: Entity, _old_team: int, _new_team: int) -> void:
	pass


## D key on a unit. Return true if handled.
func on_deploy(_u: Unit) -> bool:
	return false


func on_deployed(_s: Structure) -> void:
	pass


func on_unit_built(_u: Unit) -> void:
	pass


## Campaign upgrades applied to every unit the player owns (called for spawns too).
func apply_upgrades(u: Unit) -> void:
	if u.team != PLAYER or u.has_meta("upgraded"):
		return
	u.set_meta("upgraded", true)
	if u.is_engineer() and number >= 5:
		u.speed *= 1.35   # Mission 5 unlock: Engineer upgrades (faster capture)


## -1 = default rules, 0 = forbid, 1 = allow (skips the build-radius rule).
func placement_override(_team: int, _id: String, _cell: Vector2i) -> int:
	return -1


## A projectile landed (blue crystal chain reactions, Maw agitation ...).
func on_impact(_pos: Vector3, _warhead: String, _src: Entity) -> void:
	pass


func harvest_cell_ok(_c: Vector2i) -> bool:
	return true


func crystal_allowed(_c: Vector2i) -> bool:
	return true


## Can this target be ordered as an "enter" interaction for the unit?
func can_interact(u: Unit, t: Entity) -> bool:
	if u.is_engineer() and t is Structure and t.def.get("capturable", false) and t.team != u.team:
		return true
	return false


## The player fired their Halo Lance uplink.
func fire_player_lance(up: Structure, pos: Vector3) -> void:
	up.sw_charge = 0.0
	if lance_single_use:
		up.sw_used = true
	var s := LanceStrike.fire(pos, 3.0, 3.0, 1800.0)
	s.struck.connect(on_lance_struck)
	Voice.say("pilot", "Halo Lance firing. Stand clear of the target area.")


func on_lance_struck(_pos: Vector3) -> void:
	pass


## Sidebar special button pressed.
func special_action(id: String) -> void:
	if id == "harden":
		harden()


# ---------------------------------------------------------------- Hardened upgrade (Mission 8 on)

var harden_ready_t := 0.0


func enable_harden() -> void:
	G.hud.add_special("harden", "Harden network (30s)")


func update_harden() -> void:
	var cd := harden_ready_t - time
	G.hud.set_special("harden", "Harden network (30s)" if cd <= 0.0 else "Harden recharging %ds" % int(cd), cd <= 0.0)


## Networked units become immune to SIBYL hijacking for 30 seconds.
func harden() -> void:
	if time < harden_ready_t:
		return
	harden_ready_t = time + 120.0
	for u in team_units(PLAYER):
		if u.def.get("networked", false):
			u.tags["hardened_until"] = time + 30.0
			u.hijack = 0.0
			Fx.ring(u.position, Color(0.5, 0.8, 1.0), 1.2, 0.6)
	G.notify(PLAYER, "Networked units hardened for 30 seconds.")


# ================================================================ players

func setup_players() -> void:
	var me := PlayerState.new(PLAYER, "bastion", BASTION_BLUE, false, "Bastion (You)")
	var enemy := PlayerState.new(ENEMY, "veil", VEIL_RED, true, "The Veil")
	var neutral := PlayerState.new(NEUTRAL, "neutral", Color(0.75, 0.72, 0.62), false, "Civilians")
	neutral.passive = true
	var ally := PlayerState.new(ALLY, "outcast", Color(0.45, 0.75, 0.35), true, "Outcasts")
	var hostile := PlayerState.new(HOSTILE, "creature", Color(0.4, 1.0, 0.6), true, "Crystal Creatures")
	me.allies = [ALLY]
	ally.allies = [PLAYER]
	G.players = [me, enemy, neutral, ally, hostile]
	G.local_team = PLAYER
	me.allowed = Campaign.tech_for(number)
	if number >= 8:
		me.extra_factions = ["veil"]   # Kestrel's Veil units, from Mission 8 on
	me.credits = start_credits
	G.blue_allowed = number >= 6
	for p in G.players:
		if p.id != PLAYER:
			p.credits = 0


func player() -> PlayerState:
	return G.players[PLAYER]


func enemy() -> PlayerState:
	return G.players[ENEMY]


# ================================================================ objectives

## survive = "keep X alive" style objective: completes automatically on victory.
func add_objective(id: String, text: String, kind := "primary", visible := true, survive := false) -> void:
	objectives.append({"id": id, "text": text, "kind": kind, "state": "active", "visible": visible, "survive": survive})
	if visible and G.hud:
		G.hud.refresh_objectives()
		if time > 1.0:
			G.notify(PLAYER, "New objective: " + text, true)


func obj(id: String) -> Dictionary:
	for o in objectives:
		if o["id"] == id:
			return o
	return {}


func reveal(id: String) -> void:
	var o := obj(id)
	if not o.is_empty() and not o["visible"]:
		o["visible"] = true
		G.notify(PLAYER, "New objective: " + o["text"], true)
		G.hud.refresh_objectives()


func set_text(id: String, text: String) -> void:
	var o := obj(id)
	if not o.is_empty() and o["text"] != text:
		o["text"] = text
		if G.hud:
			G.hud.refresh_objectives()


func is_done(id: String) -> bool:
	return obj(id).get("state", "") == "done"


func is_failed(id: String) -> bool:
	return obj(id).get("state", "") == "failed"


func is_active(id: String) -> bool:
	return obj(id).get("state", "") == "active"


func complete(id: String) -> void:
	var o := obj(id)
	if o.is_empty() or o["state"] != "active" or ended:
		return
	o["state"] = "done"
	o["visible"] = true
	var label := "Bonus objective complete" if o["kind"] == "bonus" else "Objective complete"
	G.notify(PLAYER, "%s: %s" % [label, o["text"]])
	Voice.eva("Objective complete")
	G.hud.refresh_objectives()


func fail(id: String) -> void:
	var o := obj(id)
	if o.is_empty() or o["state"] != "active" or ended:
		return
	o["state"] = "failed"
	G.notify(PLAYER, "Objective failed: %s" % o["text"])
	Voice.eva("Objective failed")
	G.hud.refresh_objectives()


func primaries_done() -> bool:
	var any := false
	for o in objectives:
		if o["kind"] == "primary" and not o.get("survive", false):
			any = true
			if o["state"] != "done":
				return false
	return any


# ================================================================ dialogue & events

func say(speaker: String, text: String) -> void:
	Voice.say(speaker, text)


func say_once(key: String, speaker: String, text: String) -> void:
	if _once.has(key):
		return
	_once[key] = true
	say(speaker, text)


func once(key: String) -> bool:
	if _once.has(key):
		return false
	_once[key] = true
	return true


func after(sec: float, f: Callable) -> void:
	_events.append({"t": time + sec, "f": f})


func set_timer(key: String, text: String, secs: float) -> void:
	timers[key] = {"text": text, "t": secs}


## A status line in the timer bar without a clock.
func set_status(key: String, text: String) -> void:
	timers[key] = {"text": text, "t": -1.0}


func clear_timer(key: String) -> void:
	timers.erase(key)


func timer_left(key: String) -> float:
	return float(timers.get(key, {}).get("t", 0.0))


# ================================================================ spawning helpers

func spawn(ids: Array, team: int, cell: Vector2i, tag := "") -> Array:
	var us: Array = G.spawn_group(ids, team, cell)
	for u in us:
		if tag != "":
			u.tags[tag] = true
	return us


func spawn_one(id: String, team: int, cell: Vector2i, tag := "") -> Unit:
	var us := spawn([id], team, cell, tag)
	return us[0] if not us.is_empty() else null


func building(id: String, team: int, cell: Vector2i, tag := "") -> Structure:
	var d: Dictionary = G.def_of(id)
	var sz := Vector2i(int(d["size"][0]), int(d["size"][1]))
	if not d.get("no_footprint", false):
		for x in range(cell.x - 1, cell.x + sz.x + 1):
			for y in range(cell.y - 1, cell.y + sz.y + 1):
				var c := Vector2i(x, y)
				if G.map.in_bounds(c):
					G.map.remove_crystal(c)
				if x >= cell.x and x < cell.x + sz.x and y >= cell.y and y < cell.y + sz.y:
					var t := G.map.terrain_at(c)
					if t != MapGrid.Terrain.GROUND and t != MapGrid.Terrain.BRIDGE:
						G.map.set_terrain(c, MapGrid.Terrain.GROUND)
	var s: Structure = G.spawn_structure(id, team, cell, true)
	if tag != "":
		s.tags[tag] = true
	return s


func tagged(tag: String, alive_only := true) -> Array:
	var out: Array = []
	for e in G.entities:
		if e.tags.has(tag) and (e.alive or not alive_only):
			out.append(e)
	return out


func count_tagged(tag: String) -> int:
	return tagged(tag).size()


func team_units(team: int) -> Array:
	return (G.players[team] as PlayerState).units()


func combat_units(team: int) -> Array:
	return team_units(team).filter(func(u): return not u.weapon.is_empty())


## Is any entity of `team` (or its allies when allies=true) within r of pos?
func team_near(pos: Vector3, team: int, r: float, allies := false, units_only := true) -> bool:
	for e in G.entities:
		if not e.alive or (units_only and not (e is Unit)):
			continue
		if e.team == team or (allies and G.is_friend(team, e.team)):
			if Vector2(e.position.x - pos.x, e.position.z - pos.z).length() <= r:
				return true
	return false


func units_near(pos: Vector3, team: int, r: float) -> Array:
	var out: Array = []
	for e in G.entities:
		if e.alive and e is Unit and e.team == team and Vector2(e.position.x - pos.x, e.position.z - pos.z).length() <= r:
			out.append(e)
	return out


func cell_pos(c: Vector2i) -> Vector3:
	return G.map.cell_to_world(c)


## Sends units on an attack-move to a cell.
func attack_move(units: Array, cell: Vector2i) -> void:
	var cells: Array = G.map.spread_cells(cell, units.size())
	for i in units.size():
		if is_instance_valid(units[i]) and units[i].alive:
			units[i].cmd_attack_move(cells[i])


func move_units(units: Array, cell: Vector2i) -> void:
	var cells: Array = G.map.spread_cells(cell, units.size())
	for i in units.size():
		if is_instance_valid(units[i]) and units[i].alive:
			units[i].cmd_move(cells[i])


## A wave of enemies that enters at `from` and attack-moves to `to`.
func send_wave(ids: Array, team: int, from: Vector2i, to: Vector2i, tag := "") -> Array:
	var us := spawn(ids, team, from, tag)
	attack_move(us, to)
	return us


func add_ai(p: PlayerState, base_cell: Vector2i, enemy_cell: Vector2i, opts := {}) -> AIController:
	var ai := AIController.new()
	ai.name = "AI_%d" % p.id
	add_child(ai)
	ai.setup(p, base_cell, enemy_cell, opts)
	_ai.append(ai)
	return ai


func focus(cell: Vector2i) -> void:
	if G.camera:
		G.camera.focus_on(cell_pos(cell))


# ================================================================ markers

## Objective marker: a light pillar in the world plus a blip on the radar.
func add_marker(key: String, pos: Vector3, color: Color, label := "") -> void:
	remove_marker(key)
	var n := MeshFactory.marker_pillar(color)
	n.position = Vector3(pos.x, 0, pos.z)
	G.world.add_child(n)
	markers.append({"key": key, "pos": pos, "color": color, "label": label, "node": n})


func remove_marker(key: String) -> void:
	for i in range(markers.size() - 1, -1, -1):
		if markers[i]["key"] == key:
			if is_instance_valid(markers[i]["node"]):
				markers[i]["node"].queue_free()
			markers.remove_at(i)


# ================================================================ win / lose

func win() -> void:
	if ended:
		return
	for o in objectives:
		if o.get("survive", false) and o["state"] == "active":
			o["state"] = "done"
	ended = true
	won = true
	G.game_over = true
	for k in pending_flags.keys():
		Campaign.set_flag(k, pending_flags[k])
	Campaign.mission_won()
	if G.controller:
		G.controller.cancel_mode()
	Voice.stop_all()
	Voice.say("eva", "Mission accomplished.")
	print("Mission %d accomplished at t=%.0f" % [number, time])
	for l in Campaign.mission_info(number).get("debrief", []):
		Voice.say(l[0], l[1])
	G.hud.show_mission_end(true, "")


func lose(reason: String) -> void:
	if ended:
		return
	ended = true
	G.game_over = true
	if G.controller:
		G.controller.cancel_mode()
	Voice.stop_all()
	Voice.say("eva", "Mission failed.")
	print("Mission %d failed at t=%.0f: %s" % [number, time, reason])
	G.hud.show_mission_end(false, reason)


## Standard loss: nothing of yours is left.
func all_lost() -> bool:
	return player().units().is_empty() and player().structures().is_empty()


# ================================================================ frame

func _physics_process(delta: float) -> void:
	if ended or G.game_over:
		return
	time += delta
	for k in timers.keys():
		if float(timers[k]["t"]) >= 0.0:
			timers[k]["t"] = maxf(0.0, float(timers[k]["t"]) - delta)
	var due: Array = []
	for ev in _events:
		if ev["t"] <= time:
			due.append(ev)
	for ev in due:
		_events.erase(ev)
		(ev["f"] as Callable).call()
		if ended:
			return
	tick(delta)
	if ended:
		return
	if auto_win and primaries_done():
		if _win_t < 0.0:
			_win_t = time + 2.0
		elif time >= _win_t:
			win()


func _entity_died(e: Entity, killer: Entity) -> void:
	report_unit_lost(e)
	on_entity_died(e, killer)


func report_unit_lost(e: Entity) -> void:
	if e.team == PLAYER and e is Unit and not ended and time - _unit_lost_t > 12.0:
		_unit_lost_t = time
		Voice.eva("Unit lost")


## Debug / test helper: complete every primary objective.
func debug_win() -> void:
	for o in objectives:
		if o["kind"] == "primary" and o["state"] == "active":
			complete(o["id"])
	win()
