class_name MissionSolver
extends Node
## Scripted "solutions" for each mission, used by the test harness. They use
## shortcuts (teleporting, removing targets) but drive every objective through
## the mission's real trigger logic.

var m: Mission
var runner: Node


# ---------------------------------------------------------------- helpers

func wait(secs: float) -> void:
	var t0 := m.time
	while is_instance_valid(m) and not m.ended and m.time - t0 < secs:
		await get_tree().physics_frame


func until(cond: Callable, timeout := 120.0) -> bool:
	var t0 := m.time
	while is_instance_valid(m) and not m.ended and m.time - t0 < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
	return false


func units(team := 0) -> Array:
	return (G.players[team] as PlayerState).units()


func first(team := 0, def_id := "") -> Unit:
	for u in units(team):
		if def_id == "" or u.def_id == def_id:
			return u
	return null


func put(u: Entity, cell: Vector2i) -> void:
	if is_instance_valid(u) and u.alive:
		var c: Vector2i = G.map.nearest_passable(cell, u.move_class if u is Unit else "ground")
		u.position = G.map.cell_to_world(c)
		if u is Unit:
			u.cmd_stop()


func kill(list: Array) -> void:
	for e in list:
		if is_instance_valid(e) and e.alive:
			e.invulnerable = false
			e.die(null)


func kill_tag(tag: String) -> void:
	kill(m.tagged(tag))


func kill_team(team: int, structures := true) -> void:
	for e in G.entities.duplicate():
		if e.team == team and (structures or e is Unit):
			kill([e])


func engineer_into(target: Entity, team := 0) -> Unit:
	var cell: Vector2i = G.map.world_to_cell(target.position) + Vector2i(0, 3)
	var e: Unit = G.spawn_unit("engineer", team, G.map.cell_to_world(G.map.nearest_walkable(cell)))
	G.engineer_enter(e, target)
	return e


func log_msg(s: String) -> void:
	print("  [solver m%d t=%.0f] %s" % [m.number, m.time, s])


# ---------------------------------------------------------------- M1

func solve_m1() -> void:
	var scout := first(0, "scout_mech")
	scout.invulnerable = true
	for i in 4:
		put(scout, m.SQUADS[i][0] + Vector2i(2, 0))
		await wait(1.0)
	log_msg("squads found %d" % m.squads_found)
	put(scout, m.CHURCH + Vector2i(3, 1))
	await wait(1.0)
	for town in m.TOWNS.keys():
		put(scout, m.TOWNS[town] + Vector2i(0, 3))
		await wait(1.0)
		put(m.buses[town], m.EVAC)
		await wait(1.0)
	put(scout, m.RAIL_YARD + Vector2i(3, 0))
	await wait(1.0)
	var ok: bool = m.mcv.deploy()
	log_msg("deployed %s" % ok)
	await wait(2.0)
	kill_tag("camp")
	await wait(1.0)


# ---------------------------------------------------------------- M2

func solve_m2() -> void:
	var sensor: Unit = m.tagged("sensor")[0]
	sensor.invulnerable = true
	# cut the grid spurs first and watch the ratio fall
	for e in m.tagged("grid"):
		kill([e])
		await wait(0.5)
	log_msg("power ratio after grid cut: %.2f" % m.power_ratio())
	var eng := first(0, "engineer")
	put(eng, m.COAL + Vector2i(1, 4))
	eng.cmd_enter(G.map.occupant_at(m.COAL))
	await until(func(): return m.is_done("coal"), 30.0)
	log_msg("coal captured: %s, ratio %.2f" % [m.is_done("coal"), m.power_ratio()])
	put(sensor, G.map.world_to_cell(m.gen.position) + Vector2i(0, 5))
	await until(func(): return m.is_done("find"), 10.0)
	log_msg("found=%s gen_found=%s" % [m.is_done("find"), m.gen_found])
	kill([m.gen])
	await wait(1.0)
	kill([m.veil_cy])
	await wait(1.0)


# ---------------------------------------------------------------- M3

func solve_m3() -> void:
	m.tallow.invulnerable = true
	var scout := first(0, "scout_mech")
	scout.invulnerable = true
	put(m.supply, m.VILLAGE + Vector2i(0, 2))
	await wait(1.0)
	for i in m.ROUTE_WP.size():
		put(m.tallow, m.ROUTE_WP[i])
		put(scout, m.ROUTE_WP[i] + Vector2i(1, 1))
		await until(func(): return m.wp_i > i, 5.0)
	log_msg("follow=%s supply=%s" % [m.obj("follow")["state"], m.obj("supply")["state"]])
	# lure the patrol into the southern Maw and agitate it
	var maw: Entity = m.maws[2]
	for u in m.tagged("patrol"):
		put(u, G.map.world_to_cell(maw.position) + Vector2i(1, 2))
	maw.take_damage(10.0, "bullet", scout)
	await until(func(): return m.is_done("maw"), 20.0)
	log_msg("maw kills %d" % m.maw_kills)
	await until(func(): return m.trucks.size() > 0, 30.0)
	var killed := 0
	while killed < 5 and not m.ended:
		await wait(0.5)
		for t in m.trucks.duplicate():
			if is_instance_valid(t) and t.alive:
				kill([t])
				killed += 1
	await wait(1.0)
	put(scout, G.map.world_to_cell(m.caches[0][0]))
	await wait(1.0)


# ---------------------------------------------------------------- M4

func solve_m4() -> void:
	first(0, "mcv").deploy()
	await wait(1.0)
	var eng := first(0, "engineer")
	eng.invulnerable = true
	put(eng, m.DAM_CTRL + Vector2i(0, 3))
	eng.cmd_enter(m.ctrl)
	await until(func(): return m.is_done("base"), 20.0)
	log_msg("base=%s" % m.obj("base")["state"])
	var eng2: Unit = null
	for u in units():
		if u.def_id == "engineer" and u != eng:
			eng2 = u
	if eng2 == null:
		eng2 = G.spawn_unit("engineer", 0, m.cell_pos(m.PILLARS[0] + Vector2i(0, 2)))
	eng2.invulnerable = true
	for p in m.pillars:
		put(eng2, G.map.world_to_cell(p.position) + Vector2i(0, 2))
		eng2.cmd_enter(p)
		await until(func(): return float(m.charge[p]) == -1.0, 20.0)
	log_msg("charges=%s" % m.obj("charges")["state"])
	var scout := first(0, "scout_mech")
	put(scout, m.NOMADS + Vector2i(0, 4))
	await wait(1.0)
	for c in m.tagged("nomad"):
		put(c, m.EVAC)
	await until(func(): return m.is_done("nomads"), 10.0)
	log_msg("nomads=%s saved=%d" % [m.obj("nomads")["state"], m.nomads_saved])
	m.special_action("blow")
	await until(func(): return m.flooded, 40.0)
	log_msg("flooded")
	kill_team(1)
	await wait(1.0)
