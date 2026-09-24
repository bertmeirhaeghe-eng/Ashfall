class_name Unit
extends Entity
## Mobile unit: pathing, orders (move / attack / attack-move / stop),
## auto-targeting with a leash while idle.

enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE }

const LEASH := 5.0            # how far an idle unit chases before returning
const SCAN_INTERVAL := 0.35

var order := Order.IDLE
var speed := 2.0
var path: Array = []          # Vector3 waypoints
var path_i := 0
var dest_cell := Vector2i.ZERO
var home := Vector3.ZERO
var is_infantry := false

var _scan_t := 0.0
var _repath_t := 0.0
var _target_cell := Vector2i(-9999, -9999)
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _anim_t := 0.0
var _moving := false


func setup(id: String, p_team: int) -> void:
	super.setup(id, p_team)
	speed = float(def.get("speed", 2.0))
	is_infantry = def.get("category", "") == "infantry"
	_scan_t = randf() * SCAN_INTERVAL


func _ready() -> void:
	home = position
	_last_pos = position


func is_moving() -> bool:
	return _moving


# ---------------------------------------------------------------- commands

func cmd_move(cell: Vector2i) -> void:
	order = Order.MOVE
	target = null
	_set_path(cell)


func cmd_attack(t: Entity) -> void:
	if weapon.is_empty() or t == null or not t.alive:
		return
	order = Order.ATTACK
	target = t
	_target_cell = Vector2i(-9999, -9999)
	_repath_t = 0.0


func cmd_attack_move(cell: Vector2i) -> void:
	if weapon.is_empty():
		cmd_move(cell)
		return
	order = Order.ATTACK_MOVE
	target = null
	_set_path(cell)


func cmd_stop() -> void:
	order = Order.IDLE
	target = null
	path.clear()
	path_i = 0
	home = position


# ---------------------------------------------------------------- movement

func _set_path(cell: Vector2i) -> void:
	dest_cell = cell
	path = G.map.find_path(position, cell)
	path_i = 0
	_stuck_t = 0.0


func has_path() -> bool:
	return path_i < path.size()


## Moves along the current path. Returns true when the path is finished.
func follow_path(delta: float) -> bool:
	if path_i >= path.size():
		return true
	var wp: Vector3 = path[path_i]
	var to := Vector3(wp.x - position.x, 0.0, wp.z - position.z)
	var dist := to.length()
	var step := speed * delta
	if dist <= step:
		position = Vector3(wp.x, 0.0, wp.z)
		path_i += 1
	else:
		var np := position + to / dist * step
		if not G.map.is_walkable(G.map.world_to_cell(np)) and G.map.is_walkable(G.map.world_to_cell(position)):
			# something (a new building?) blocked the way
			_repath_t -= delta
			if _repath_t <= 0.0:
				_repath_t = 0.5
				_set_path(dest_cell)
			return false
		position = np
		face(to, delta)
	_moving = true
	# crowding: if we're close to the goal but can't get there, call it done
	var goal: Vector3 = path[path.size() - 1]
	if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.3:
		if position.distance_to(_last_pos) < speed * delta * 0.3:
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
	if G.map.is_walkable(c):
		position = Vector3(np.x, 0.0, np.z)


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
	_animate(delta)
	_unstick()
	_last_pos = position


func _target_ok(t) -> bool:  # untyped: t may already be freed
	return is_instance_valid(t) and t.alive


func _do_idle(delta: float) -> void:
	if weapon.is_empty():
		if has_path():
			follow_path(delta)
		return
	if not _target_ok(target):
		target = null
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = SCAN_INTERVAL
			target = G.find_target(self, weapon_range() + 1.5)
			# retaliate against whoever is shooting us
			if target == null and _target_ok(last_attacker) and G.elapsed - last_hit_time < 3.0:
				if last_attacker.edge_distance(home) < LEASH + weapon_range():
					target = last_attacker
		if target == null and has_path():
			follow_path(delta)  # walking back home after a chase
		return
	if in_range(target):
		path.clear()
		path_i = 0
		aim_and_fire(target, delta)
	elif Vector2(position.x - home.x, position.z - home.z).length() < LEASH:
		_chase(target, delta)
	else:
		target = null
		_set_path(G.map.world_to_cell(home))


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
		# chase only a little off the route
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
			# we were chasing: resume the route
			_target_cell = Vector2i(-9999, -9999)
			_set_path(dest_cell)
		if follow_path(delta):
			order = Order.IDLE
			home = position


func _unstick() -> void:
	# never remain inside a blocked cell (e.g. pushed into rock)
	var c: Vector2i = G.map.world_to_cell(position)
	if not G.map.is_walkable(c):
		var free: Vector2i = G.map.nearest_walkable(c, 4)
		var p: Vector3 = G.map.cell_to_world(free)
		position = position.move_toward(p, 0.1)


func _animate(delta: float) -> void:
	if not _moving:
		model.position.y = move_toward(model.position.y, 0.0, delta)
		return
	_anim_t += delta
	if is_infantry:
		model.position.y = absf(sin(_anim_t * 11.0)) * 0.05
	elif model.has_meta("walker"):
		model.position.y = absf(sin(_anim_t * 6.0)) * 0.06
		var legs: Array = model.get_meta("legs", [])
		var swing := float(model.get_meta("leg_swing", 0.4))
		for i in legs.size():
			legs[i].rotation.x = sin(_anim_t * 6.0 + PI * i) * swing
