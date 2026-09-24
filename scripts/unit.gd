class_name Unit
extends Entity
## Mobile unit: pathing for ground / hover / air / jump-jet movement, orders
## (move / attack / attack-move / enter / stop), auto-targeting with a leash,
## plus the special roles: engineer, medic, transport, MCV, burrowing drills.

enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, ENTER }

const LEASH := 5.0            # how far an idle unit chases before returning
const SCAN_INTERVAL := 0.35

var order := Order.IDLE
var speed := 2.0
var move_class := "ground"
var fly_height := 0.0
var path: Array = []          # Vector3 waypoints
var path_i := 0
var dest_cell := Vector2i.ZERO
var home := Vector3.ZERO
var is_infantry := false
var leash := LEASH
var passengers: Array = []    # [{id, hp, rank, kills}]
var enter_target: Entity = null
var burrowed := false
var speed_mult := 1.0         # missions (snow, crystal ...)
var hold_position := false    # never chase (scripted guards)

var _scan_t := 0.0
var _repath_t := 0.0
var _target_cell := Vector2i(-9999, -9999)
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _anim_t := 0.0
var _moving := false
var _heal_t := 0.0
var _heal_target: Unit = null


func setup(id: String, p_team: int) -> void:
	super.setup(id, p_team)
	speed = float(def.get("speed", 2.0))
	is_infantry = def.get("category", "") == "infantry"
	move_class = def.get("move", "ground")
	if move_class == "air":
		is_air = true
		fly_height = 2.2
	elif move_class == "jump":
		fly_height = 0.9
	bar_height += fly_height
	_scan_t = randf() * SCAN_INTERVAL


func _ready() -> void:
	home = position
	_last_pos = position


func is_moving() -> bool:
	return _moving


func hidden_underground() -> bool:
	return burrowed


func hit_height() -> float:
	return fly_height + (bar_height - fly_height) * 0.5


func is_engineer() -> bool:
	return def.get("engineer", false)


func transport_cap() -> int:
	return int(def.get("transport", 0))


# ---------------------------------------------------------------- commands

func cmd_move(cell: Vector2i) -> void:
	order = Order.MOVE
	target = null
	enter_target = null
	_set_path(cell)


func cmd_attack(t: Entity) -> void:
	if t == null or not t.alive or not can_target(t):
		return
	order = Order.ATTACK
	target = t
	enter_target = null
	_target_cell = Vector2i(-9999, -9999)
	_repath_t = 0.0


func cmd_attack_move(cell: Vector2i) -> void:
	if weapon.is_empty():
		cmd_move(cell)
		return
	order = Order.ATTACK_MOVE
	target = null
	enter_target = null
	_set_path(cell)


## Walk up to an entity and interact: capture, board, plant, reboot ...
func cmd_enter(t: Entity) -> void:
	if t == null or not t.alive:
		return
	order = Order.ENTER
	enter_target = t
	target = null
	_target_cell = Vector2i(-9999, -9999)
	_repath_t = 0.0


func cmd_stop() -> void:
	order = Order.IDLE
	target = null
	enter_target = null
	path.clear()
	path_i = 0
	home = position


## D key: MCV unpacks, transports unload, missions may add more.
func deploy() -> bool:
	if G.mission and G.mission.on_deploy(self):
		return true
	if def.has("deploys"):
		var sid: String = def["deploys"]
		var sd: Dictionary = G.def_of(sid)
		var sz := Vector2i(int(sd["size"][0]), int(sd["size"][1]))
		var c: Vector2i = G.map.world_to_cell(position) - sz / 2
		if _footprint_free(c, sz):
			var old_team := team
			remove_silently()
			var s: Structure = G.spawn_structure(sid, old_team, c)
			G.notify(old_team, "%s deployed" % s.display_name(), true)
			if G.mission:
				G.mission.on_deployed(s)
			return true
		G.notify(team, "Cannot deploy here")
		return false
	if transport_cap() > 0 and not passengers.is_empty():
		unload()
		return true
	return false


func _footprint_free(tl: Vector2i, sz: Vector2i) -> bool:
	for x in range(tl.x, tl.x + sz.x):
		for y in range(tl.y, tl.y + sz.y):
			var c := Vector2i(x, y)
			if not G.map.is_walkable(c) or G.map.crystal_at(c) > 0.0:
				return false
	for e in G.entities:
		if e != self and e is Unit and not e.is_air and Rect2i(tl, sz).has_point(G.map.world_to_cell(e.position)):
			return false
	return true


func board(u: Unit) -> bool:
	if passengers.size() >= transport_cap() or not u.is_infantry or u.team != team:
		return false
	passengers.append({"id": u.def_id, "hp": u.hp, "rank": u.rank, "kills": u.kills, "tags": u.tags})
	u.remove_silently()
	G.notify(team, "%s boarded (%d/%d)" % [u.display_name(), passengers.size(), transport_cap()])
	return true


func unload() -> void:
	if passengers.is_empty():
		return
	var cells: Array = G.map.spread_cells(G.map.world_to_cell(position), passengers.size() + 1)
	for i in passengers.size():
		var p: Dictionary = passengers[i]
		var u: Unit = G.spawn_unit(p["id"], team, G.map.cell_to_world(cells[i + 1]))
		if u:
			u.set_rank(int(p["rank"]))
			u.hp = minf(float(p["hp"]), u.max_hp)
			u.kills = int(p["kills"])
			u.tags = p.get("tags", {})
	passengers.clear()
	G.notify(team, "Passengers unloaded")


func on_removed() -> void:
	# a transport that dies takes its passengers with it (they bail out if it is sold / removed)
	passengers.clear()


func on_team_changed(_old: int) -> void:
	cmd_stop()


# ---------------------------------------------------------------- movement

func _set_path(cell: Vector2i) -> void:
	dest_cell = cell
	path = G.map.find_path(position, cell, move_class)
	path_i = 0
	_stuck_t = 0.0


func has_path() -> bool:
	return path_i < path.size()


func _can_move() -> bool:
	return not (is_air and G.air_grounded)


func remaining_path() -> float:
	if path_i >= path.size():
		return 0.0
	var d := G.flat_dist(position, path[path_i])
	for i in range(path_i, path.size() - 1):
		d += (path[i] as Vector3).distance_to(path[i + 1])
	return d


## Moves along the current path. Returns true when the path is finished.
func follow_path(delta: float) -> bool:
	if path_i >= path.size():
		return true
	if not _can_move():
		return false
	var wp: Vector3 = path[path_i]
	var to := Vector3(wp.x - position.x, 0.0, wp.z - position.z)
	var dist := to.length()
	var spd := speed * speed_mult * (1.3 if burrowed else 1.0)
	var step := spd * delta
	if dist <= step:
		position = Vector3(wp.x, position.y, wp.z)
		path_i += 1
	else:
		var np := position + to / dist * step
		var here: Vector2i = G.map.world_to_cell(position)
		if not G.map.passable(G.map.world_to_cell(np), move_class) and G.map.passable(here, move_class):
			# something (a new building?) blocked the way
			_repath_t -= delta
			if _repath_t <= 0.0:
				_repath_t = 0.5
				_set_path(dest_cell)
			return false
		position = np
		face(to, delta)
	_moving = true
	var goal: Vector3 = path[path.size() - 1]
	if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.3:
		if G.flat_dist(position, _last_pos) < spd * delta * 0.3:
			_stuck_t += delta
			if _stuck_t > 0.5:
				path_i = path.size()
				return true
		else:
			_stuck_t = 0.0
	return path_i >= path.size()


func face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 10.0))


func nudge(v: Vector3) -> void:
	var np := position + v
	var c: Vector2i = G.map.world_to_cell(np)
	if G.map.passable(c, move_class):
		position = Vector3(np.x, position.y, np.z)


func _chase(t: Entity, delta: float) -> void:
	var tc: Vector2i
	if t is Structure:
		tc = (t as Structure).approach_cell(position)
	else:
		tc = G.map.world_to_cell(t.position)
	_repath_t -= delta
	if tc != _target_cell or (_repath_t <= 0.0 and not has_path()):
		if _repath_t <= 0.0 or tc != _target_cell:
			_target_cell = tc
			_repath_t = 0.6
			_set_path(tc)
	follow_path(delta)


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	super._process(delta)
	position.y = G.map.height_at(position)  # ride the terrain

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_moving = false
	weapon_cd = maxf(0.0, weapon_cd - delta)
	match order:
		Order.IDLE:
			_do_idle(delta)
		Order.MOVE:
			if follow_path(delta):
				order = Order.IDLE
				home = position
		Order.ATTACK:
			_do_attack(delta)
		Order.ATTACK_MOVE:
			_do_attack_move(delta)
		Order.ENTER:
			_do_enter(delta)
	_update_burrow()
	_passive_heal(delta)
	_animate(delta)
	_unstick()
	_last_pos = position


func _update_burrow() -> void:
	if not def.get("burrow", false):
		return
	var want := order != Order.ATTACK and _moving and remaining_path() > 3.0 and target == null
	if want != burrowed:
		burrowed = want
		Fx.dust(position)
		detected_mask = -2
		refresh_visibility()


func _passive_heal(delta: float) -> void:
	_heal_t -= delta
	if _heal_t > 0.0:
		return
	_heal_t = 0.5
	if def.get("outcast", false) and G.map.crystal_at(G.map.world_to_cell(position)) > 0.0:
		heal(5.0)


func _target_ok(t) -> bool:
	return is_instance_valid(t) and t.alive and can_target(t)


func _do_idle(delta: float) -> void:
	if def.has("heal"):
		_do_medic(delta)
		return
	if weapon.is_empty():
		if has_path():
			follow_path(delta)
		return
	if not _target_ok(target):
		target = null
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = SCAN_INTERVAL
			target = G.find_target(self, weapon_range() + (0.0 if hold_position else 1.5))
			# retaliate against whoever is shooting us
			if target == null and not hold_position and _target_ok(last_attacker) and G.elapsed - last_hit_time < 3.0:
				if last_attacker.edge_distance(home) < leash + weapon_range():
					target = last_attacker
		if target == null and has_path():
			follow_path(delta)  # walking back home after a chase
		return
	if in_range(target):
		path.clear()
		path_i = 0
		aim_and_fire(target, delta)
	elif not hold_position and Vector2(position.x - home.x, position.z - home.z).length() < leash:
		_chase(target, delta)
	else:
		target = null
		if not hold_position:
			_set_path(G.map.world_to_cell(home))


func _do_medic(delta: float) -> void:
	if not (is_instance_valid(_heal_target) and _heal_target.alive and _heal_target.hp < _heal_target.max_hp):
		_heal_target = null
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = SCAN_INTERVAL * 2.0
			var best_d := 6.0
			for e in G.entities:
				if e is Unit and e != self and e.alive and e.is_infantry and G.is_friend(team, e.team) and e.hp < e.max_hp - 1.0:
					var d: float = G.flat_dist(e.position, position)
					if d < best_d:
						best_d = d
						_heal_target = e
		if _heal_target == null and has_path():
			follow_path(delta)
		return
	if G.flat_dist(_heal_target.position, position) < 1.4:
		path.clear()
		path_i = 0
		_heal_target.heal(float(def["heal"]) * delta)
		face(_heal_target.position - position, delta)
		if randf() < delta * 3.0:
			Fx.sparkle(_heal_target.position + Vector3(0, 0.5, 0), Color(0.4, 1.0, 0.5))
	else:
		_chase(_heal_target, delta)


func _do_attack(delta: float) -> void:
	if not _target_ok(target):
		target = null
		order = Order.IDLE
		home = position
		path.clear()
		return
	if in_range(target):
		path.clear()
		path_i = 0
		aim_and_fire(target, delta)
	else:
		_chase(target, delta)


func _do_attack_move(delta: float) -> void:
	if _target_ok(target):
		if in_range(target):
			aim_and_fire(target, delta)
			return
		if target.edge_distance(position) < weapon_range() + 3.0:
			var saved_dest := dest_cell
			_chase(target, delta)
			dest_cell = saved_dest
			return
		target = null
		_set_path(dest_cell)
	else:
		target = null
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var t: Entity = G.find_target(self, weapon_range() + 2.0)
		if t:
			target = t
			return
	if target == null:
		if _target_cell != Vector2i(-9999, -9999):
			_target_cell = Vector2i(-9999, -9999)
			_set_path(dest_cell)
		if follow_path(delta):
			order = Order.IDLE
			home = position


func _do_enter(delta: float) -> void:
	var t := enter_target
	if not (is_instance_valid(t) and t.alive):
		cmd_stop()
		return
	if t.edge_distance(position) <= 0.7 + (0.4 if t is Unit else 0.0):
		enter_target = null
		order = Order.IDLE
		home = position
		path.clear()
		if t is Unit and t.transport_cap() > 0 and t.team == team:
			t.board(self)
		else:
			G.engineer_enter(self, t)
		return
	_chase(t, delta)


func _unstick() -> void:
	# never remain inside a blocked cell (e.g. pushed into rock)
	if move_class == "air" or move_class == "jump":
		return
	var c: Vector2i = G.map.world_to_cell(position)
	if not G.map.passable(c, move_class):
		var free: Vector2i = G.map.nearest_passable(c, move_class, 4)
		var p: Vector3 = G.map.cell_to_world(free)
		position = position.move_toward(p, 0.1)


func _animate(delta: float) -> void:
	_anim_t += delta
	if is_air:
		var h := fly_height if _can_move() else 0.25
		model.position.y = lerpf(model.position.y, h + sin(_anim_t * 2.0) * 0.08, minf(1.0, delta * 2.0))
		return
	if move_class == "jump":
		var jh := fly_height if _moving else 0.0
		model.position.y = lerpf(model.position.y, jh, minf(1.0, delta * 5.0))
		return
	if move_class == "hover":
		model.position.y = 0.15 + sin(_anim_t * 3.0) * 0.04
		return
	if not _moving:
		model.position.y = move_toward(model.position.y, 0.0, delta)
		return
	if is_infantry:
		model.position.y = absf(sin(_anim_t * 11.0)) * 0.05
	elif model.has_meta("walker"):
		model.position.y = absf(sin(_anim_t * 6.0)) * 0.06
		var legs: Array = model.get_meta("legs", [])
		var swing := float(model.get_meta("leg_swing", 0.4))
		for i in legs.size():
			legs[i].rotation.x = sin(_anim_t * 6.0 + PI * i) * swing
