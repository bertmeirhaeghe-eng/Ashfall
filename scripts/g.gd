extends Node
## Global game state (autoload "G").
## Holds the rules data, the players, the live entity list and references
## to the main scene objects so every system can reach them.

const RULES_PATH := "res://data/rules.json"
const BUCKET := 2.0 # spatial-hash bucket size for unit separation

## Fixed team slots used by every mission.
const PLAYER := 0     # Bastion (you)
const ENEMY := 1      # the Veil / SIBYL / Rourke
const NEUTRAL := 2    # civilians, tech buildings, bridges, the Maw
const ALLY := 3       # Outcasts / Kestrel's AI-led fighters
const HOSTILE := 4    # crystal creatures, hostile raiders: enemies of everyone

var rules: Dictionary = {}
var map: MapGrid
var camera: RTSCamera
var controller: InputController
var hud: HUD
var world: Node3D
var fx_root: Node3D
var mission: Mission

var players: Array = []    # Array of PlayerState, index == team id
var entities: Array = []   # all live Entity nodes
var local_team := 0
var game_over := false
var elapsed := 0.0
var blue_allowed := true       # can harvesters refine Blue Vitrium
var air_grounded := false      # glass storm grounds aircraft
var radar_jammed := false      # glass storm knocks out radar
var _vis_t := 0.0


func _ready() -> void:
	load_rules()


func load_rules() -> void:
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		push_error("Ashfall: cannot open %s" % RULES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Ashfall: rules.json is not valid JSON")
		return
	rules = parsed


func reset() -> void:
	players.clear()
	entities.clear()
	game_over = false
	elapsed = 0.0
	map = null
	camera = null
	controller = null
	hud = null
	world = null
	fx_root = null
	mission = null
	blue_allowed = true
	air_grounded = false
	radar_jammed = false


# ---------------------------------------------------------------- rules access

func game_rule(key: String, default: Variant = null) -> Variant:
	return rules.get("game", {}).get(key, default)


func def_of(id: String) -> Dictionary:
	if rules.get("units", {}).has(id):
		return rules["units"][id]
	if rules.get("structures", {}).has(id):
		return rules["structures"][id]
	return {}


func is_structure_def(id: String) -> bool:
	return rules.get("structures", {}).has(id)


func weapon_def(id: String) -> Dictionary:
	return rules.get("weapons", {}).get(id, {})


func warhead_mult(warhead: String, armor: String) -> float:
	return float(rules.get("warheads", {}).get(warhead, {}).get(armor, 1.0))


func def_name(id: String) -> String:
	return def_of(id).get("name", id)


## All ids of a category for a faction, in rules-file order.
func buildables(category: String, faction: String) -> Array:
	var out: Array = []
	for group in ["structures", "units"]:
		var dict: Dictionary = rules.get(group, {})
		for id in dict.keys():
			var d: Dictionary = dict[id]
			if d.get("category", "") != category:
				continue
			if not d.get("buildable", true):
				continue
			var fac: String = d.get("faction", "any")
			if fac != "any" and fac != faction:
				continue
			out.append(id)
	return out


# ---------------------------------------------------------------- teams

func is_enemy(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= players.size() or b >= players.size():
		return false
	var pa: PlayerState = players[a]
	var pb: PlayerState = players[b]
	if pa.passive or pb.passive:
		return false
	return not pa.allies.has(b)


func is_friend(a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or b < 0 or a >= players.size():
		return false
	return (players[a] as PlayerState).allies.has(b)


# ---------------------------------------------------------------- entities

func register(e: Entity) -> void:
	entities.append(e)


func unregister(e: Entity) -> void:
	entities.erase(e)
	if controller:
		controller.forget(e)


func spawn_unit(id: String, team: int, pos: Vector3) -> Unit:
	var d := def_of(id)
	if d.is_empty():
		push_error("Unknown unit id: " + id)
		return null
	var u: Unit
	if d.has("capacity"):
		u = Harvester.new()
	else:
		u = Unit.new()
	u.setup(id, team)
	u.position = Vector3(pos.x, map.height_at(pos), pos.z)
	world.add_child(u)
	register(u)
	if mission:
		mission.apply_upgrades(u)
	return u


func spawn_structure(id: String, team: int, top_left: Vector2i, instant := false) -> Structure:
	var s := Structure.new()
	s.setup_at(id, team, top_left)
	world.add_child(s)
	register(s)
	s.on_placed(instant)
	players[team].recalc_power()
	return s


## Spawns a group of units spread around a cell. Returns the units.
func spawn_group(ids: Array, team: int, cell: Vector2i) -> Array:
	var out: Array = []
	var mc := "ground"
	if not ids.is_empty():
		mc = def_of(ids[0]).get("move", "ground")
		if mc == "jump" or mc == "air":
			mc = "ground"
	var cells: Array = map.spread_cells(cell, ids.size(), mc)
	for i in ids.size():
		var u := spawn_unit(ids[i], team, map.cell_to_world(cells[i]))
		if u:
			out.append(u)
	return out


## Validate a structure placement for a team (footprint free + near own base).
func can_place(team: int, id: String, top_left: Vector2i) -> bool:
	var d := def_of(id)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var rect := Rect2i(top_left, size)
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if not map.in_bounds(c) or not map.is_walkable(c):
				return false
			if map.crystal_at(c) > 0.0:
				return false
	for e in entities:
		if e is Unit and not e.is_air and rect.has_point(map.world_to_cell(e.position)):
			return false
	if mission:
		var o: int = mission.placement_override(team, id, top_left)
		if o >= 0:
			return o == 1
	var r := int(game_rule("build_radius", 4))
	var grown := rect.grow(r)
	for e in entities:
		if e is Structure and e.team == team and e.alive and not e.def.get("decoy", false):
			if grown.intersects(Rect2i(e.cell, e.size)):
				return true
	return false


func place_structure(team: int, id: String, top_left: Vector2i) -> bool:
	if not can_place(team, id, top_left):
		return false
	var p: PlayerState = players[team]
	var cat: String = def_of(id).get("category", "structure")
	if p.ready_structure.get(cat, "") != id:
		return false
	p.ready_structure[cat] = ""
	spawn_structure(id, team, top_left)
	return true


func find_target(from: Entity, max_range: float) -> Entity:
	var best: Entity = null
	var best_score := INF
	for e in entities:
		if not e.alive or not is_enemy(from.team, e.team):
			continue
		if not from.can_target(e):
			continue
		var d: float = e.edge_distance(from.position)
		if d > max_range:
			continue
		if d < from.min_range():
			continue
		# prefer things that shoot back, then closest
		var score := d
		if e.weapon.is_empty():
			score += 3.0
		if e.def.get("civilian", false):
			score += 4.0
		if score < best_score:
			best_score = score
			best = e
	return best


func entities_in_radius(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for e in entities:
		if e.alive and e.edge_distance(pos) <= r:
			out.append(e)
	return out


## Area damage (splash, lance strikes, lightning ...).
func damage_area(pos: Vector3, radius: float, dmg: float, warhead: String, attacker: Entity = null, spare_team := -1, hit_air := false) -> void:
	for e in entities_in_radius(pos, radius):
		if e.team == spare_team:
			continue
		if e.is_air and not hit_air:
			continue
		var d: float = e.edge_distance(pos)
		var k := 1.0 - 0.5 * clampf(d / maxf(radius, 0.01), 0.0, 1.0)
		e.take_damage(dmg * k, warhead, attacker)


## Engineer (or capturing infantry) reached its target.
func engineer_enter(eng: Unit, target: Entity) -> void:
	if not (is_instance_valid(target) and target.alive and eng.alive):
		return
	if mission and mission.on_enter(eng, target):
		return
	if target is Structure and target.def.get("capturable", false) and target.team != eng.team:
		var old := target.team
		target.set_team(eng.team)
		notify(eng.team, tr("Building captured: %s") % target.display_name())
		if eng.team == local_team:
			Voice.eva("Building captured")
		if mission:
			mission.on_captured(target, old, eng.team)
		eng.remove_silently()
		return
	if target is Structure and target.team == eng.team and target.hp < target.max_hp:
		target.hp = target.max_hp
		notify(eng.team, "Structure repaired")
		eng.remove_silently()


# ---------------------------------------------------------------- visibility / detection

## Recomputes which cloaked / burrowed entities each side can see.
func update_visibility(delta: float) -> void:
	_vis_t -= delta
	if _vis_t > 0.0:
		return
	_vis_t = 0.2
	var detectors: Array = []
	for e in entities:
		if e.alive and e.detector_radius() > 0.0:
			detectors.append(e)
	for e in entities:
		if not e.alive:
			continue
		if not e.can_hide():
			if e.detected_mask != -1:
				e.detected_mask = -1
				e.refresh_visibility()
			continue
		var mask := 0
		if e.hidden_now():
			for d in detectors:
				var r: float = d.detector_radius()
				if G.flat_dist(e.position, d.position) <= r + e.radius:
					mask |= _team_mask(d.team)
		else:
			mask = -1
		if mask != e.detected_mask:
			e.detected_mask = mask
			e.refresh_visibility()


func _team_mask(t: int) -> int:
	var m := 1 << t
	if t < players.size():
		for a in (players[t] as PlayerState).allies:
			m |= 1 << a
	return m


# ---------------------------------------------------------------- unit separation

func separate_units(delta: float) -> void:
	var buckets := {}
	for e in entities:
		if e is Unit and e.alive and not e.is_air and not e.hidden_underground():
			var k := Vector2i(floori(e.position.x / BUCKET), floori(e.position.z / BUCKET))
			if not buckets.has(k):
				buckets[k] = []
			buckets[k].append(e)
	for k in buckets.keys():
		for a in buckets[k]:
			for ox in range(-1, 2):
				for oz in range(-1, 2):
					var nk: Vector2i = k + Vector2i(ox, oz)
					if not buckets.has(nk):
						continue
					for b in buckets[nk]:
						if b.get_instance_id() <= a.get_instance_id():
							continue
						var dx: float = a.position.x - b.position.x
						var dz: float = a.position.z - b.position.z
						var min_d: float = (a.radius + b.radius) * 0.9
						var d2 := dx * dx + dz * dz
						if d2 >= min_d * min_d:
							continue
						var d := sqrt(d2)
						var dir := Vector3(dx, 0, dz)
						if d < 0.001:
							dir = Vector3(randf() - 0.5, 0, randf() - 0.5)
							d = 0.001
						dir = dir.normalized()
						var push: float = minf((min_d - d) * 0.5, 3.0 * delta)
						var wa := 0.5
						var wb := 0.5
						if a.is_moving() and not b.is_moving():
							wa = 0.8
							wb = 0.2
						elif b.is_moving() and not a.is_moving():
							wa = 0.2
							wb = 0.8
						a.nudge(dir * push * 2.0 * wa)
						b.nudge(-dir * push * 2.0 * wb)


## On-screen message; `speak` also has the Bastion EVA say it.
func notify(team: int, msg: String, speak := false) -> void:
	if team != local_team:
		return
	if hud:
		hud.notify(msg)   # translated there; formatted messages come pre-translated
	if speak:
		Voice.eva(msg)    # EVA speech is looked up from the English message


## Distance on the ground plane (ignores terrain height).
func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
