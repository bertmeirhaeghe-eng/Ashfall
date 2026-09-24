class_name Harvester
extends Unit
## Automatic crystal harvester: find field -> harvest -> return to refinery -> unload.
## Retreats to the refinery when shot while carrying cargo.

enum HState { SEEK, TO_FIELD, HARVESTING, TO_REFINERY, UNLOADING, WAITING }

var hstate := HState.SEEK
var cargo := 0.0
var cargo_blue := 0.0
var capacity := 500.0
var harvest_rate := 100.0
var unload_rate := 250.0
var harvest_cell := Vector2i(-1, -1)
var refinery: Structure = null
var _tick := 0.0
var _warned_t := -100.0


func setup(id: String, p_team: int) -> void:
	super.setup(id, p_team)
	capacity = float(def.get("capacity", 500))
	harvest_rate = float(def.get("harvest_rate", 100))
	unload_rate = float(def.get("unload_rate", 250))


func state_text() -> String:
	match hstate:
		HState.HARVESTING: return "Harvesting"
		HState.TO_FIELD: return "Moving to field"
		HState.TO_REFINERY: return "Returning"
		HState.UNLOADING: return "Unloading"
		HState.WAITING: return "No crystal / refinery"
	return "Searching"


# ---------------------------------------------------------------- player orders

func cmd_harvest_at(c: Vector2i) -> void:
	order = Order.IDLE
	harvest_cell = c
	_set_path(c)
	hstate = HState.TO_FIELD


func cmd_dock(r: Structure) -> void:
	order = Order.IDLE
	refinery = r
	_set_path(r.dock_cell())
	hstate = HState.TO_REFINERY


func cmd_move(cell: Vector2i) -> void:
	super.cmd_move(cell)
	# after a manual move the harvester resumes its job
	hstate = HState.SEEK if cargo < capacity else HState.TO_REFINERY


func cmd_stop() -> void:
	super.cmd_stop()
	hstate = HState.WAITING
	_tick = 3.0


# ---------------------------------------------------------------- logic

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_moving = false
	if order == Order.MOVE:
		if follow_path(delta):
			order = Order.IDLE
			if hstate == HState.TO_REFINERY:
				_go_refinery()
	else:
		_run_job(delta)
	_animate(delta)
	_unstick()
	_last_pos = position


func _run_job(delta: float) -> void:
	match hstate:
		HState.SEEK:
			if cargo >= capacity:
				_go_refinery()
				return
			var from: Vector2i = G.map.world_to_cell(position)
			var c: Vector2i = G.map.nearest_crystal(from, harvest_cell)
			if c.x < 0:
				if cargo > 0.0:
					_go_refinery()
				else:
					hstate = HState.WAITING
					_tick = 3.0
				return
			harvest_cell = c
			_set_path(c)
			hstate = HState.TO_FIELD
		HState.TO_FIELD:
			if not G.map.harvestable(harvest_cell):
				hstate = HState.SEEK
				return
			if follow_path(delta):
				if G.map.world_to_cell(position) != harvest_cell:
					# couldn't reach exactly (crowded) - harvest whatever is under us or nearby
					var near: Vector2i = G.map.crystal_near(G.map.world_to_cell(position), 1)
					if near.x >= 0:
						harvest_cell = near
				hstate = HState.HARVESTING
				_tick = 0.0
		HState.HARVESTING:
			_tick += delta
			_moving = true  # keep the cutter spinning
			if _tick < 0.25:
				return
			_tick = 0.0
			var kind: int = G.map.crystal_kind_at(harvest_cell)
			var take: float = G.map.harvest(harvest_cell, minf(harvest_rate * 0.25, capacity - cargo))
			cargo += take
			if kind == MapGrid.Crystal.BLUE:
				cargo_blue += take
			if cargo >= capacity - 0.01:
				_go_refinery()
			elif take <= 0.0:
				var nc: Vector2i = G.map.crystal_near(G.map.world_to_cell(position), 2)
				if nc.x >= 0:
					harvest_cell = nc
					_set_path(nc)
					hstate = HState.TO_FIELD
				else:
					hstate = HState.WAITING
					_tick = 1.0
		HState.TO_REFINERY:
			if not _refinery_ok():
				_go_refinery()
				return
			if follow_path(delta):
				if G.flat_dist(position, G.map.cell_to_world(refinery.dock_cell())) < 1.6:
					hstate = HState.UNLOADING
					_tick = 0.0
				else:
					_set_path(refinery.dock_cell())
					if path.is_empty():
						hstate = HState.WAITING
						_tick = 2.0
		HState.UNLOADING:
			if not _refinery_ok():
				_go_refinery()
				return
			var amt := minf(cargo, unload_rate * delta)
			var blue_part := minf(cargo_blue, amt * cargo_blue / maxf(cargo, 0.01))
			cargo -= amt
			cargo_blue -= blue_part
			var p: PlayerState = G.players[team]
			p.credits += amt
			p.blue_refined += blue_part
			if cargo <= 0.01:
				cargo = 0.0
				cargo_blue = 0.0
				hstate = HState.SEEK
		HState.WAITING:
			_tick -= delta
			if _tick <= 0.0:
				hstate = HState.SEEK if cargo < capacity else HState.TO_REFINERY
				if hstate == HState.TO_REFINERY:
					_go_refinery()


func _refinery_ok() -> bool:
	return is_instance_valid(refinery) and refinery.alive


func _go_refinery() -> void:
	refinery = _nearest_refinery()
	if refinery == null:
		hstate = HState.WAITING
		_tick = 3.0
		return
	_set_path(refinery.dock_cell())
	hstate = HState.TO_REFINERY


func _nearest_refinery() -> Structure:
	var best: Structure = null
	var best_d := INF
	for e in G.entities:
		if e is Structure and e.team == team and e.alive and e.def_id == "refinery":
			var d := position.distance_squared_to(e.position)
			if d < best_d:
				best_d = d
				best = e
	return best


func on_damaged() -> void:
	if G.elapsed - _warned_t > 10.0:
		_warned_t = G.elapsed
		G.notify(team, "Harvester under attack", true)
	if order != Order.MOVE and cargo > 0.0 and (hstate == HState.HARVESTING or hstate == HState.TO_FIELD):
		_go_refinery()


func _animate(delta: float) -> void:
	if model.has_meta("cutter") and (_moving or hstate == HState.HARVESTING):
		var cutter: Node3D = model.get_meta("cutter")
		cutter.rotation.x += delta * 8.0
	if model.has_meta("bin"):
		var bin: Node3D = model.get_meta("bin")
		bin.scale.y = lerpf(bin.scale.y, 0.3 + 0.7 * cargo / capacity, minf(1.0, delta * 4.0))
