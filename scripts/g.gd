extends Node
## Global game state (autoload "G").
## Holds the rules data, the players, the live entity list and references
## to the main scene objects so every system can reach them.

const RULES_PATH := "res://data/rules.json"
const BUCKET := 2.0 # spatial-hash bucket size for unit separation

var rules: Dictionary = {}
var map: MapGrid
var camera: RTSCamera
var controller: InputController
var hud: HUD
var world: Node3D
var fx_root: Node3D

var players: Array = []    # Array of PlayerState, index == team id
var entities: Array = []   # all live Entity nodes
var local_team := 0
var game_over := false
var elapsed := 0.0


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


## All buildable ids of a category for a faction, in rules-file order.
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
	u.position = Vector3(pos.x, 0.0, pos.z)
	world.add_child(u)
	register(u)
	return u


func spawn_structure(id: String, team: int, top_left: Vector2i, instant := false) -> Structure:
	var s := Structure.new()
	s.setup_at(id, team, top_left)
	world.add_child(s)
	register(s)
	s.on_placed(instant)
	players[team].recalc_power()
	return s


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
	# no units standing on the footprint
	for e in entities:
		if e is Unit and rect.has_point(map.world_to_cell(e.position)):
			return false
	# adjacency rule: must be within build_radius of an own structure
	var r := int(game_rule("build_radius", 4))
	var grown := rect.grow(r)
	for e in entities:
		if e is Structure and e.team == team and e.alive:
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
		if e.team == from.team or not e.alive:
			continue
		var d: float = e.edge_distance(from.position)
		if d > max_range:
			continue
		# prefer things that shoot back, then closest
		var score := d
		if e.weapon.is_empty():
			score += 3.0
		if score < best_score:
			best_score = score
			best = e
	return best


# ---------------------------------------------------------------- unit separation

func separate_units(delta: float) -> void:
	var buckets := {}
	for e in entities:
		if e is Unit and e.alive:
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
						# moving units yield less to stationary ones
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


func notify(team: int, msg: String) -> void:
	if team == local_team and hud:
		hud.notify(msg)
