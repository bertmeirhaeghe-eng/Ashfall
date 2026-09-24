class_name Structure
extends Entity
## A building on the grid: footprint, power, production role, defense weapon,
## repair and sell.

var cell := Vector2i.ZERO     # top-left footprint cell
var size := Vector2i(2, 2)
var power := 0
var produces: Array = []
var rally_cell := Vector2i(-1, -1)
var repairing := false
var _build_anim := 1.0
var _repair_t := 0.0
var _scan_t := 0.0


func setup_at(id: String, p_team: int, top_left: Vector2i) -> void:
	is_structure = true
	var d: Dictionary = G.def_of(id)
	size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	cell = top_left
	setup(id, p_team)
	power = int(def.get("power", 0))
	produces = def.get("produces", [])
	position = Vector3(cell.x + size.x * 0.5, 0.0, cell.y + size.y * 0.5)
	radius = maxf(size.x, size.y) * 0.5


func ring_radius() -> Vector2:
	return Vector2(size.x * 0.5 + 0.25, size.y * 0.5 + 0.25)


func on_placed(instant: bool) -> void:
	for c in footprint():
		G.map.set_occupant(c, self)
	if not instant:
		_build_anim = 0.0
		model.scale = Vector3(1, 0.05, 1)
		G.notify(team, "Building: %s" % display_name())
	if def.has("free_unit"):
		var u: Unit = G.spawn_unit(def["free_unit"], team, G.map.cell_to_world(dock_cell()))
		if u is Harvester:
			(u as Harvester).refinery = self


func footprint() -> Array:
	var out: Array = []
	for x in range(cell.x, cell.x + size.x):
		for y in range(cell.y, cell.y + size.y):
			out.append(Vector2i(x, y))
	return out


func edge_distance(from: Vector3) -> float:
	var dx := maxf(absf(from.x - position.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(from.z - position.z) - size.y * 0.5, 0.0)
	return sqrt(dx * dx + dz * dz)


func contains_point(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x - position.x) <= size.x * 0.5 + margin and absf(p.z - position.z) <= size.y * 0.5 + margin


## The walkable cell closest to `from` on the edge of this footprint.
func approach_cell(from: Vector3) -> Vector2i:
	var cx := clampi(floori(from.x), cell.x, cell.x + size.x - 1)
	var cy := clampi(floori(from.z), cell.y, cell.y + size.y - 1)
	return G.map.nearest_walkable(Vector2i(cx, cy), 6)


func exit_cell() -> Vector2i:
	return G.map.nearest_walkable(Vector2i(cell.x + size.x / 2, cell.y + size.y), 6)


func dock_cell() -> Vector2i:
	return G.map.nearest_walkable(Vector2i(cell.x + size.x, cell.y + size.y / 2), 6)


func hit_height() -> float:
	return 0.6


func is_factory_for(category: String) -> bool:
	return produces.has(category)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _build_anim < 1.0:
		_build_anim = minf(1.0, _build_anim + delta * 1.2)
		var k := _build_anim
		model.scale = Vector3(1.0, 0.05 + 0.95 * (1.0 - pow(1.0 - k, 3.0)), 1.0)
		return
	var p: PlayerState = G.players[team]
	if not weapon.is_empty():
		var rof := float(G.game_rule("low_power_defense_mult", 0.5)) if p.low_power() else 1.0
		weapon_cd = maxf(0.0, weapon_cd - delta)
		if not (is_instance_valid(target) and target.alive and in_range(target)):
			target = null
			_scan_t -= delta
			if _scan_t <= 0.0:
				_scan_t = 0.3
				target = G.find_target(self, weapon_range())
		if target:
			aim_and_fire(target, delta, rof)
	if repairing:
		_repair_t -= delta
		if _repair_t <= 0.0:
			_repair_t = 0.5
			if hp >= max_hp:
				repairing = false
			else:
				var heal := max_hp * 0.04
				var cost := heal / max_hp * float(def.get("cost", 0)) * float(G.game_rule("repair_cost_ratio", 0.5))
				if p.credits >= cost:
					p.credits -= cost
					hp = minf(max_hp, hp + heal)
				else:
					repairing = false
					G.notify(team, "Insufficient funds for repair")


func on_damaged() -> void:
	var p: PlayerState = G.players[team]
	if G.elapsed - p.last_attack_warning > 8.0:
		p.last_attack_warning = G.elapsed
		p.last_attack_pos = position
		G.notify(team, "Our base is under attack!")


func sell() -> void:
	if not alive:
		return
	var p: PlayerState = G.players[team]
	var refund := float(def.get("cost", 0)) * float(G.game_rule("sell_refund", 0.5)) * (hp / max_hp)
	p.credits += refund
	alive = false
	G.notify(team, "Structure sold (+$%d)" % int(refund))
	Fx.explosion(position + Vector3(0, 0.3, 0), 0.8)
	on_removed()
	G.unregister(self)
	queue_free()


func on_removed() -> void:
	for c in footprint():
		if G.map.occupant_at(c) == self:
			G.map.set_occupant(c, null)
	var p: PlayerState = G.players[team]
	p.recalc_power.call_deferred()
