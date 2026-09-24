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


# ---------------------------------------------------------------- M5

func solve_m5() -> void:
	var engs: Array = units().filter(func(u): return u.def_id == "engineer")
	for e in engs:
		e.invulnerable = true
	put(engs[0], G.map.world_to_cell(m.stations[0].position) + Vector2i(-3, 0))
	engs[0].cmd_enter(m.stations[0])
	await until(func(): return m.stations[0].team == 0, 20.0)
	log_msg("station0 held, speed %.2f" % m.speed())
	kill([m.bridges[0]])
	await until(func(): return m.state == "moving", 120.0)
	await until(func(): return m.branch != "", 120.0)
	log_msg("branch=%s" % m.branch)
	for c in m.cars:
		if is_instance_valid(c) and c.alive and (c.role == "flak" or c.role == "repair"):
			kill([c])
	await wait(1.0)
	var art: TrainCar = m._car("artillery")
	put(engs[1], G.map.world_to_cell(art.position) + Vector2i(-2, 0))
	engs[1].cmd_enter(art)
	await until(func(): return m.is_done("artillery"), 20.0)
	var cmd: TrainCar = m._car("command")
	put(engs[2], G.map.world_to_cell(cmd.position) + Vector2i(-2, 0))
	engs[2].cmd_enter(cmd)
	await until(func(): return m.codex, 20.0)
	log_msg("codex=%s artillery=%s" % [m.codex, m.obj("artillery")["state"]])
	m.engine.take_damage(99999.0, "laser", null)
	await until(func(): return m.state == "stopped", 70.0)
	log_msg("state=%s" % m.state)


# ---------------------------------------------------------------- M6

func solve_m6() -> void:
	m.lindqvist.invulnerable = true
	m.building("inhibitor_pylon", 0, m.BASE + Vector2i(8, -9))
	m.building("inhibitor_pylon", 0, m.BASE + Vector2i(11, -12))
	m.building("power_plant", 0, m.BASE + Vector2i(-9, -6))
	await until(func(): return m.is_done("pylons"), 10.0)
	log_msg("pylons=%s radius=%.1f" % [m.obj("pylons")["state"], m.radius])
	for i in m.SAMPLE_SPOTS.size():
		put(m.lindqvist, m.SAMPLE_SPOTS[i])
		m.lindqvist.hold_position = true
		await until(func(): return m.samples > i, 15.0)
	log_msg("samples=%d" % m.samples)
	# a shell into the blue field triggers a chain reaction
	for c in G.map.crystal_cells.keys():
		if G.map.crystal_kind_at(c) == MapGrid.Crystal.BLUE:
			m.on_impact(G.map.cell_to_world(c), "cannon", null)
			break
	await wait(2.0)
	kill_tag("outpost")
	(G.players[0] as PlayerState).blue_refined = 10000.0
	put(m.lindqvist, m.BASE + Vector2i(6, 0))
	await until(func(): return m.ended or m.is_done("extract"), 200.0)


# ---------------------------------------------------------------- M7

func solve_m7() -> void:
	kill_tag("outer")
	kill_tag("spire")
	await wait(1.0)
	log_msg("outer=%s spires=%s" % [m.obj("outer")["state"], m.obj("spires")["state"]])
	await until(func(): return m.obj("refugees")["visible"], 40.0)
	var eng := first(0, "engineer")
	put(eng, G.map.world_to_cell(m.mine.position) + Vector2i(0, 3))
	eng.cmd_enter(m.mine)
	await until(func(): return m.refugees, 20.0)
	log_msg("refugees saved, lock_left %.0f" % m.lock_left)
	var p: PlayerState = G.players[0]
	for i in 3:
		# queue a beacon through the real production queue and place it on its site
		p.credits += 1000
		p.queue_item("lance_beacon")
		await until(func(): return p.ready_structure["defense"] == "lance_beacon", 20.0)
		var ok := G.place_structure(0, "lance_beacon", m.SITES[i])
		log_msg("beacon %d placed=%s" % [i, ok])
		for b in m._beacons():
			b.invulnerable = true
		await wait(1.0)
	for b in m._beacons():
		b.invulnerable = true
	await until(func(): return m.lock_started, 10.0)
	# lose a beacon briefly and rebuild it within the grace window
	var b0: Structure = m._beacons()[0]
	var cell := b0.cell
	b0.invulnerable = false
	kill([b0])
	await wait(5.0)
	log_msg("grace=%.1f" % m.grace)
	m.building("lance_beacon", 0, cell)
	for b in m._beacons():
		b.invulnerable = true
	await until(func(): return m._fired, 420.0)
	log_msg("lance fired")


# ---------------------------------------------------------------- M8

func solve_m8() -> void:
	m.kestrel.invulnerable = true
	m.gate.invulnerable = true
	var wardens: Array = units().filter(func(u): return u.def_id == "warden")
	var tower_cell: Vector2i = m.TOWERS[1]
	for w in wardens:
		w.invulnerable = true
		put(w, tower_cell + Vector2i(0, 4))
	await until(func(): return wardens.all(func(w): return w.team == 1), 15.0)
	log_msg("hijacked: %d" % wardens.filter(func(w): return w.team == 1).size())
	var engs: Array = units().filter(func(u): return u.def_id == "engineer")
	for i in 3:
		engs[i].invulnerable = true
		put(engs[i], tower_cell + Vector2i(1, 6))
		engs[i].cmd_enter(wardens[i])
		await until(func(): return wardens[i].team == 0, 15.0)
	log_msg("reboots=%d" % m.reboots)
	# hardened units are immune
	m.special_action("harden")
	var tp := first(0, "tempest")
	tp.invulnerable = true
	put(tp, tower_cell + Vector2i(0, 3))
	await wait(8.0)
	log_msg("hardened tempest team=%d" % tp.team)
	put(first(0, "rifleman"), m.BAZAAR + Vector2i(0, 2))
	await wait(1.0)
	log_msg("node=%s" % m.obj("node")["state"])
	# a hijacked unit comes back when its tower falls
	var kite := first(0, "kite")
	kite.invulnerable = true
	put(kite, m.TOWERS[0] + Vector2i(0, 2))
	await until(func(): return kite.team == 1, 15.0)
	for t in m.towers:
		kill([t])
		await wait(0.5)
	log_msg("kite back: team=%d" % kite.team)
