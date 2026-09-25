extends Mission
## Mission 7 — Judgment Hour. The Sanctum, Ahaggar Mountains, storm-dark afternoon.
## Signature mechanic: a timed three-point defense with a real moral choice.
## Place three Halo Lance beacons around the Sanctum and hold them for the
## 4-minute lock. Optionally send an Engineer to open the old mine exit so 400
## refugees can escape: +2 minutes on the lock, a massive counter-attack, and
## Rourke's public reprimand, but the Outcasts will remember.

const W := 100
const H := 100
const BASE := Vector2i(50, 86)
const SANCTUM := Vector2i(47, 12)
const CENTER := Vector2i(50, 18)
const SITES := [Vector2i(35, 24), Vector2i(65, 24), Vector2i(50, 31)]
const MINE := Vector2i(78, 12)
const GAPS := [Vector2i(33, 36), Vector2i(66, 36)]
const LOCK_TIME := 240.0

var sanctum: Structure
var lock_started := false
var lock_left := LOCK_TIME
var grace := -1.0
var refugees := false
var mine: Structure
var _check_t := 0.0
var _gas_t := 40.0
var _drill_t := 30.0
var _refugee_t := 0.0
var _refugees_left := 0
var _fired := false


func objective_preview() -> Array:
	return [
		["primary", "Break through the Sanctum's outer defenses."],
		["primary", "Place three Halo Lance targeting beacons around the Sanctum."],
		["primary", "Defend all three beacons for 4 minutes until the Lance fires."],
		["optional", "Send an Engineer into the lower caves and open the old mine exit so the refugees can evacuate (+2 minutes to the lock, massive counter-attack)."],
		["bonus", "Destroy the Sanctum's three Spires of Judgment before placing beacons."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.12, 0.12, 0.16), "sky_horizon": Color(0.35, 0.3, 0.3),
		"ground_horizon": Color(0.25, 0.2, 0.18), "sun_rot": Vector3(-40, 150, 0),
		"sun_color": Color(0.85, 0.8, 0.9), "sun_energy": 0.75, "ambient": 0.55,
		"fog_color": Color(0.3, 0.27, 0.28), "fog_density": 0.008, "weather": "ash",
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 7707, {
		"ground": Color(0.42, 0.33, 0.27), "rock": Color(0.32, 0.24, 0.2), "variation": 0.05,
	})
	# the mountain ring around the Sanctum, with two passes
	for a in range(0, 360, 2):
		var rad := deg_to_rad(a)
		var p := Vector2(CENTER) + Vector2(cos(rad) * 24.0, sin(rad) * 19.0)
		var gap := false
		for g in GAPS:
			if p.distance_to(Vector2(g)) < 4.5:
				gap = true
		if not gap:
			map.blob(Vector2i(p), 1.8, MapGrid.Terrain.ROCK, 0.6)
	map.fill_rect(Rect2i(0, 0, W, 3), MapGrid.Terrain.ROCK)
	map.scatter(MapGrid.Terrain.ROCK, 22, 1.4, 3.0, [[BASE, 13], [Vector2i(50, 18), 26], [Vector2i(33, 50), 8], [Vector2i(66, 50), 8], [MINE, 5]])
	for g in GAPS:
		map.carve(BASE, g, 4.0)
		map.carve(g, CENTER, 4.0)
	map.carve(CENTER, MINE, 3.0)
	for s in SITES:
		map.clear_area(s, 2.5)
	map.clear_area(CENTER, 8.0)
	map.tint_blob(MINE, 3.0, Color(0.25, 0.2, 0.17))
	map.crystal_field(Vector2i(30, 80), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(72, 78), 3.2, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(50, 60), 3.0, MapGrid.Crystal.BLUE)
	for c in [Vector2i(30, 80), Vector2i(72, 78), Vector2i(50, 60)]:
		map.carve(BASE, c, 3.0)
	map.clear_area(BASE, 10.0)


func setup() -> void:
	start_credits = 9000
	player().credits = 9000
	auto_win = false
	building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	building("power_plant", PLAYER, BASE + Vector2i(-6, -1))
	building("power_plant", PLAYER, BASE + Vector2i(-6, 3))
	building("power_plant", PLAYER, BASE + Vector2i(6, 4))
	building("refinery", PLAYER, BASE + Vector2i(4, -4))
	building("barracks", PLAYER, BASE + Vector2i(-3, 4))
	building("war_factory", PLAYER, BASE + Vector2i(1, 4))
	building("radar", PLAYER, BASE + Vector2i(-6, -5))
	spawn(["engineer", "engineer", "engineer", "rifleman", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "medic"], PLAYER, BASE + Vector2i(0, -7))
	spawn(["warden", "warden", "warden", "tempest", "tempest", "resonator"], PLAYER, BASE + Vector2i(5, -7))
	if Campaign.flag("resonator_x"):
		spawn(["resonator_x"], PLAYER, BASE + Vector2i(8, -6))
	# the Sanctum and its defenses
	sanctum = building("sanctum", ENEMY, SANCTUM, "sanctum")
	for g in GAPS:
		building("veil_gate", ENEMY, g + Vector2i(-1, -5), "outer")
		building("guard_tower", ENEMY, g + Vector2i(-4, -2), "outer")
		building("guard_tower", ENEMY, g + Vector2i(3, -2), "outer")
	for c in [Vector2i(38, 18), Vector2i(62, 18), Vector2i(50, 24)]:
		building("spire", ENEMY, c, "spire")
	building("war_factory", ENEMY, Vector2i(38, 8), "inner")
	building("barracks", ENEMY, Vector2i(58, 7), "inner")
	building("power_plant", ENEMY, Vector2i(62, 11), "inner")
	building("power_plant", ENEMY, Vector2i(34, 13), "inner")
	building("flak_nest", ENEMY, Vector2i(44, 20), "inner")
	building("flak_nest", ENEMY, Vector2i(56, 20), "inner")
	spawn(["scorpion", "scorpion", "rifleman", "rifleman", "rocket_trooper", "cyborg"], ENEMY, Vector2i(42, 28))
	spawn(["scorpion", "shade_tank", "rifleman", "rifleman", "rocket_trooper"], ENEMY, Vector2i(58, 28))
	spawn(["raider", "raider", "rifleman", "rifleman"], ENEMY, Vector2i(50, 48))
	enemy().credits = 4000
	add_ai(enemy(), CENTER, BASE, {"build": false, "first_attack": 200.0, "wave_interval": 75.0, "wave_size": 6,
		"wave_max": 12, "income": 8.0, "units": ["rifleman", "rocket_trooper", "cyborg", "scorpion", "raider", "shade_tank"]})
	mine = building("mine_exit", NEUTRAL, MINE, "mine")
	for i in SITES.size():
		add_marker("site%d" % i, cell_pos(SITES[i]), Color(1.0, 0.95, 0.6))


func begin() -> void:
	add_objective("outer", "Break through the Sanctum's outer defenses (both gatehouses and their towers).")
	add_objective("beacons", "Place three Halo Lance targeting beacons (Defense tab) on the marked sites around the Sanctum (0/3).")
	add_objective("hold", "Defend all three beacons until the Lance locks on.")
	add_objective("refugees", "OPTIONAL: Send an Engineer to open the old mine exit so the refugees can evacuate (+2 minutes to the lock, massive counter-attack).", "secondary", false)
	add_objective("spires", "Destroy the Sanctum's three Spires of Judgment before placing beacons.", "bonus")
	focus(BASE + Vector2i(0, -6))
	after(3.0, func(): say("rourke", "Two passes into the valley, Commander, both gated. Break them, then plant my beacons."))
	after(25.0, _havel_private)


func _havel_private() -> void:
	reveal("refugees")
	add_marker("mine", mine.position, Color(0.5, 1.0, 0.5))
	say("havel", "Commander, it's Havel. Private channel. Those heat signatures in the lower caves: there's an old mine exit on the east side of the valley. Send an Engineer to open it and they can get out. It'll cost time. Your call.")


# ================================================================ frame

func tick(delta: float) -> void:
	if lock_started and not _fired:
		_run_lock(delta)
	_refugee_stream(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	if is_active("outer") and count_tagged("outer") == 0:
		complete("outer")
		say("rourke", "Outer defenses are down. Beacons, Commander. Now.")
	if is_active("spires") and count_tagged("spire") == 0:
		complete("spires")
		say("havel", "All three Spires are down. That's going to make holding those beacons a lot easier.")
	var n := _beacons().size()
	if is_active("spires") and n > 0 and count_tagged("spire") > 0:
		fail("spires")
	if is_active("beacons"):
		set_text("beacons", "Place three Halo Lance targeting beacons (Defense tab) on the marked sites around the Sanctum (%d/3).", [n])
		if n >= 3:
			complete("beacons")
			_start_lock()
	if player().count_of("construction_yard") == 0:
		lose("Your Construction Yard fell.")


func _beacons() -> Array:
	return player().structures().filter(func(s): return s.def_id == "lance_beacon" and s.is_built())


func _start_lock() -> void:
	if lock_started:
		return
	lock_started = true
	set_timer("lock", "Halo Lance lock", lock_left)
	say("rourke", "All three beacons are transmitting. The Lance is locking on. Four minutes, Commander. Hold them.")


func _run_lock(delta: float) -> void:
	var n := _beacons().size()
	if n >= 3:
		grace = -1.0
		clear_timer("grace")
		lock_left -= delta
		set_timer("lock", "Halo Lance lock", lock_left)
		if lock_left <= 0.0:
			_fire_lance()
			return
	else:
		set_timer("lock", "Lock PAUSED", lock_left)
		if grace < 0.0:
			grace = 30.0
			say("rourke", "We lost a beacon! Rebuild it in thirty seconds or the lock is gone!")
		grace -= delta
		set_timer("grace", "Rebuild beacon", grace)
		if grace <= 0.0:
			lose("A beacon was lost and not rebuilt in time. The Halo Lance lost its lock.")
			return
	_gas_t -= delta
	if _gas_t <= 0.0:
		_gas_t = 45.0
		_gas_strike()
	_drill_t -= delta
	if _drill_t <= 0.0:
		_drill_t = 55.0
		_cinder_drills()


func _gas_strike() -> void:
	var bs := _beacons()
	if bs.is_empty():
		return
	var b: Structure = bs[randi() % bs.size()]
	var pos: Vector3 = b.position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	var s := LanceStrike.fire(pos, 4.0, 2.6, 0.0)
	s.visual = "gas"
	s.struck.connect(func(p):
		G.damage_area(p, 2.8, 160.0, "spore", null)
		for i in 10:
			Fx.sparkle(p + Vector3(randf_range(-2.5, 2.5), 0.3, randf_range(-2.5, 2.5)), Color(1.2, 1.4, 0.3)))
	say_once("gas", "havel", "Gas missiles inbound on the beacons! Pull your infantry out of the red circle!")


func _cinder_drills() -> void:
	var bs := _beacons()
	if bs.is_empty():
		return
	var b: Structure = bs[randi() % bs.size()]
	var c: Vector2i = G.map.world_to_cell(b.position) + Vector2i(randi_range(-6, 6), randi_range(-6, -3))
	var us := spawn(["cinder_drill", "cinder_drill"], ENEMY, c)
	for u in us:
		u.tags["scripted"] = true
		Fx.dust(u.position)
		u.cmd_attack(b)
	say_once("drills", "havel", "Cinder Drills, surfacing right under the beacons!")


func _fire_lance() -> void:
	_fired = true
	clear_timer("lock")
	clear_timer("grace")
	complete("hold")
	if is_active("refugees"):
		fail("refugees")
	say("rourke", "Lock complete. Firing.")
	var s := LanceStrike.fire(sanctum.position, 3.0, 14.0, 0.0)
	s.struck.connect(_sanctum_destroyed)
	G.camera.focus_on(sanctum.position + Vector3(0, 0, 10))


func _sanctum_destroyed(_p: Vector3) -> void:
	for i in 12:
		Fx.explosion(sanctum.position + Vector3(randf_range(-8, 8), randf_range(0, 4), randf_range(-6, 6)), 3.0)
	Fx.ring(sanctum.position, Color(1, 1, 0.95), 26.0, 2.0)
	for e in G.entities.duplicate():
		if e.alive and e.team == ENEMY and G.flat_dist(e.position, sanctum.position) < 20.0:
			e.invulnerable = false
			e.die(null)
	say("rourke", "The Sanctum is gone. Mother Oriel is dead. It's over.")
	auto_win = true


# ================================================================ refugees

func can_interact(u: Unit, t: Entity) -> bool:
	if u.is_engineer() and t == mine and not refugees:
		return true
	return super.can_interact(u, t)


func on_enter(u: Unit, t: Entity) -> bool:
	if t == mine and not refugees and u.team == PLAYER:
		if _fired:
			return true
		refugees = true
		u.remove_silently()
		remove_marker("mine")
		complete("refugees")
		pending_flags["refugees_saved"] = true
		lock_left += 120.0
		if lock_started:
			set_timer("lock", "Halo Lance lock", lock_left)
		_refugees_left = 40
		say("engineer", "Mine exit is open! They're coming out, hundreds of them.")
		say("rourke", "Commander! You paused a beacon for a pack of Outcasts? That is a direct breach of orders, on an open channel. It will be in my report.")
		say("havel", "And here comes the Veil. Everything they have.")
		_massive_counterattack()
		return true
	return false


func _refugee_stream(delta: float) -> void:
	if _refugees_left <= 0:
		return
	_refugee_t -= delta
	if _refugee_t > 0.0:
		return
	_refugee_t = 0.6
	_refugees_left -= 1
	var cv := spawn_one("civilian", NEUTRAL, MINE + Vector2i(1, 3))
	if cv:
		cv.tags["refugee"] = true
		cv.cmd_move(Vector2i(W - 3, 30 + randi_range(-4, 4)))


func _massive_counterattack() -> void:
	var goals := _beacons()
	var goal := BASE if goals.is_empty() else G.map.world_to_cell(goals[0].position)
	send_wave(["scorpion", "scorpion", "shade_tank", "cyborg", "cyborg", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper"], ENEMY, Vector2i(40, 8), goal)
	send_wave(["cinder_drill", "cinder_drill", "raider", "raider", "cyborg", "rifleman"], ENEMY, Vector2i(62, 8), goal)
	after(40.0, func(): send_wave(["scorpion", "scorpion", "cyborg", "cyborg", "rocket_trooper", "rifleman"], ENEMY, Vector2i(50, 6), goal))


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("refugee"):
		return


func _process(_delta: float) -> void:
	# refugees who reach the edge of the map are safe
	for cv in tagged("refugee"):
		if cv.position.x > W - 5:
			cv.remove_silently()


# ================================================================ beacon placement

func placement_override(team: int, id: String, cell: Vector2i) -> int:
	if team != PLAYER or id != "lance_beacon":
		return -1
	for i in SITES.size():
		if Vector2(cell).distance_to(Vector2(SITES[i])) <= 1.5:
			for s in player().structures():
				if s.def_id == "lance_beacon" and Vector2(s.cell).distance_to(Vector2(SITES[i])) <= 2.0:
					return 0
			return 1
	return 0

