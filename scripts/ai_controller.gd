class_name AIController
extends Node
## Mission AI: follows a build order, keeps power positive, replaces
## harvesters, trains a mixed army, defends its base and attacks in growing
## waves. Plays by the same economy rules as the human. Options (setup opts):
##   build: bool            build and rebuild structures (default true)
##   produce: bool          train units (default true)
##   build_order: Array     structure ids
##   units: Array           unit ids to train (default: everything buildable)
##   first_attack: float    seconds before the first wave
##   wave_interval: float   seconds between waves
##   wave_size / wave_max   units in the first wave / cap
##   income: float          free credits per second (mission difficulty)
##   defend_radius: float   react to enemies this close to the base
##   target: Vector2i       fixed attack goal (otherwise nearest enemy structure)
## Only units the AI trained itself (tag "ai_made") are commanded; pre-placed
## defenders keep guarding their posts and mission waves follow their own orders.

const DEFAULT_ORDER := ["power_plant", "refinery", "barracks", "power_plant", "war_factory",
	"guard_tower", "power_plant", "refinery", "guard_tower", "power_plant", "barracks", "guard_tower"]
const CORE := ["power_plant", "refinery", "barracks", "war_factory"]

var p: PlayerState
var base_center := Vector3.ZERO
var enemy_dir := Vector3.FORWARD
var wave_size := 5
var wave_max := 16
var wave_interval := 45.0
var build := true
var produce := true
var build_order: Array = DEFAULT_ORDER
var unit_pool: Array = []
var income := 0.0
var defend_radius := 16.0
var fixed_target := Vector2i(-9999, -9999)
var enabled := true
var order_i := 0
var _think_t := 2.0
var _attack_cooldown := 90.0
var rng := RandomNumberGenerator.new()


func setup(player: PlayerState, base_cell: Vector2i, enemy_cell: Vector2i, opts := {}) -> void:
	p = player
	base_center = G.map.cell_to_world(base_cell)
	enemy_dir = (G.map.cell_to_world(enemy_cell) - base_center).normalized()
	build = opts.get("build", true)
	produce = opts.get("produce", true)
	build_order = opts.get("build_order", DEFAULT_ORDER)
	unit_pool = opts.get("units", [])
	_attack_cooldown = float(opts.get("first_attack", 90.0))
	wave_interval = float(opts.get("wave_interval", 45.0))
	wave_size = int(opts.get("wave_size", 5))
	wave_max = int(opts.get("wave_max", 16))
	income = float(opts.get("income", 0.0))
	defend_radius = float(opts.get("defend_radius", 16.0))
	fixed_target = opts.get("target", Vector2i(-9999, -9999))
	rng.randomize()


func _physics_process(delta: float) -> void:
	if p == null or p.defeated or G.game_over or not enabled:
		return
	p.credits += income * delta
	_attack_cooldown -= delta
	_think_t -= delta
	if _think_t > 0.0:
		return
	_think_t = 1.0
	if build:
		_place_ready()
		_plan_structures()
	if produce:
		_plan_units()
	_command_army()


# ---------------------------------------------------------------- base building

func _place_ready() -> void:
	for cat in ["structure", "defense"]:
		var id: String = p.ready_structure[cat]
		if id == "":
			continue
		var spot := _find_spot(id)
		if spot.x > -999:
			G.place_structure(p.id, id, spot)
		else:
			p.cancel_item(id)


func _plan_structures() -> void:
	if not p.queues["structure"].is_empty() or p.ready_structure["structure"] != "":
		return
	if p.count_of("construction_yard") == 0:
		return
	var want := ""
	var surplus := p.power_produced - p.power_used
	if surplus < 20 and p.can_build("power_plant"):
		want = "power_plant"
	else:
		for c in CORE:
			if p.count_of(c) == 0 and p.can_build(c) and order_i > build_order.find(c) and build_order.has(c):
				want = c
				break
	if want == "" and order_i < build_order.size():
		var next: String = build_order[order_i]
		var cat: String = G.def_of(next).get("category", "structure")
		if cat == "defense":
			if p.queues["defense"].is_empty() and p.ready_structure["defense"] == "" and p.queue_item(next):
				order_i += 1
			elif not p.can_build(next):
				order_i += 1
			return
		want = next
		if not p.can_build(next) and p.missing_prereqs(next).is_empty():
			order_i += 1
			return
	if want != "" and p.queue_item(want):
		if order_i < build_order.size() and build_order[order_i] == want:
			order_i += 1


func _find_spot(id: String) -> Vector2i:
	var d: Dictionary = G.def_of(id)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var origin := base_center
	if d.get("category", "") == "defense":
		origin = base_center + enemy_dir * 7.0
	var oc: Vector2i = G.map.world_to_cell(origin)
	for r in range(2, 16):
		var cands: Array = []
		for x in range(oc.x - r, oc.x + r + 1):
			for y in range(oc.y - r, oc.y + r + 1):
				if absi(x - oc.x) != r and absi(y - oc.y) != r:
					continue
				cands.append(Vector2i(x, y))
		cands.shuffle()
		for c in cands:
			if G.can_place(p.id, id, c) and _keeps_gap(c, size):
				return c
	return Vector2i(-9999, -9999)


## Leave a one-cell lane around AI buildings so units can path through the base.
func _keeps_gap(top_left: Vector2i, size: Vector2i) -> bool:
	var ring := Rect2i(top_left - Vector2i(1, 1), size + Vector2i(2, 2))
	for x in range(ring.position.x, ring.end.x):
		for y in range(ring.position.y, ring.end.y):
			var c := Vector2i(x, y)
			if G.map.occupant_at(c) != null:
				return false
	return true


# ---------------------------------------------------------------- production

func _pool(cat: String) -> Array:
	var opts: Array = []
	var src: Array = unit_pool if not unit_pool.is_empty() else G.buildables(cat, p.faction)
	for id in src:
		if id == "harvester" or G.def_of(id).get("category", "") != cat:
			continue
		if p.can_build(id):
			opts.append(id)
	return opts


func _plan_units() -> void:
	var harvesters := p.count_of("harvester")
	var refineries := p.count_of("refinery")
	if harvesters < refineries and p.can_build("harvester") and p.queue_count("harvester") == 0:
		p.queue_item("harvester")
		return
	if p.credits > 250 and p.queues["infantry"].size() < 2:
		var inf := _pool("infantry")
		if not inf.is_empty():
			p.queue_item(inf[rng.randi() % inf.size()])
	if p.credits > 700 and p.queues["vehicle"].size() < 2:
		var veh := _pool("vehicle")
		if not veh.is_empty():
			p.queue_item(veh[rng.randi() % veh.size()])


# ---------------------------------------------------------------- army

func _army() -> Array:
	var out: Array = []
	for u in p.units():
		if not (u is Harvester) and u.tags.has("ai_made") and not u.tags.has("scripted") and not u.weapon.is_empty():
			out.append(u)
	return out


func _command_army() -> void:
	var army := _army()
	var threat: Entity = null
	var best := defend_radius
	for e in G.entities:
		if e.alive and e is Unit and G.is_enemy(p.id, e.team) and e.visible_to(p.id):
			var d: float = e.position.distance_to(base_center)
			if d < best:
				best = d
				threat = e
	if threat:
		var tc: Vector2i = G.map.world_to_cell(threat.position)
		for u in army:
			if u.order == Unit.Order.IDLE or (u.order == Unit.Order.ATTACK_MOVE and u.position.distance_to(base_center) < defend_radius + 4.0):
				u.cmd_attack_move(tc)
		return
	var idle: Array = army.filter(func(u): return u.order == Unit.Order.IDLE)
	var forward: Array = idle.filter(func(u): return u.position.distance_to(base_center) > 22.0)
	if not forward.is_empty():
		var next_goal := _attack_goal()
		if next_goal.x > -999:
			var fcells: Array = G.map.spread_cells(next_goal, forward.size())
			for i in forward.size():
				forward[i].cmd_attack_move(fcells[i])
		idle = idle.filter(func(u): return not forward.has(u))
	if idle.size() >= wave_size and _attack_cooldown <= 0.0:
		var goal := _attack_goal()
		if goal.x > -999:
			var cells: Array = G.map.spread_cells(goal, idle.size())
			for i in idle.size():
				idle[i].cmd_attack_move(cells[i])
			wave_size = mini(wave_size + 2, wave_max)
			_attack_cooldown = wave_interval
	elif not idle.is_empty():
		var rally: Vector2i = G.map.world_to_cell(base_center + enemy_dir * 9.0)
		for u in idle:
			if u.position.distance_to(G.map.cell_to_world(rally)) > 5.0 and not u.has_path():
				u.cmd_move(G.map.spread_cells(rally, 1)[0] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2)))


func _attack_goal() -> Vector2i:
	if fixed_target.x > -999:
		return fixed_target
	var best: Entity = null
	var best_d := INF
	for e in G.entities:
		if e.alive and G.is_enemy(p.id, e.team) and e.visible_to(p.id) and not e.def.get("decor", false):
			var d: float = e.position.distance_to(base_center)
			if e is Structure:
				d *= 0.7
			if d < best_d:
				best_d = d
				best = e
	if best == null:
		return Vector2i(-9999, -9999)
	return G.map.world_to_cell(best.position)
