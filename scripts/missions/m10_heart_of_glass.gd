extends Mission
## Mission 10 — Heart of Glass. The Impact Crater, Kazakhstan. Finale.
## Phase 1 (the Rim): base building with every mechanic at once: glass-storm
## surges, Maws, a SIBYL hijack relay, Kestrel's Veil units and (if you saved
## the refugees) Tallow's Outcasts, or hostile Outcast raiders if you didn't.
## Destroy the three Shaft Guardians and get the damper convoy to the shaft.
## Phase 2 (the Heart): a strike force of up to 30 units goes underground.
## Every 90 seconds the Seed pulses; any unit outside a resonance shelter is
## crystallized. Install the three dampers (90 s each), each one slowing the
## heartbeat, then destroy SIBYL's core. The Choir guards it and can only be
## hurt right after a pulse, when its shield drops.

const W := 150
const H := 96
const BASE := Vector2i(16, 80)
const SHAFT := Vector2i(74, 22)
const GUARDIANS := [Vector2i(66, 16), Vector2i(80, 16), Vector2i(73, 28)]
const RELAY := Vector2i(44, 34)
const MAWS := [Vector2i(52, 58), Vector2i(34, 24)]
const UNDER_START := Vector2i(104, 48)
const SEED := Vector2i(127, 48)
const CHAMBERS := [Vector2i(122, 16), Vector2i(144, 48), Vector2i(122, 80)]
const INSTALL_TIME := 90.0
const SURFACE := Rect2(4, 4, 88, 88)
const HEART := Rect2(102, 4, 44, 88)

var phase := 1
var kestrel: Unit
var lindqvist: Unit
var tallow: Unit
var dampers: Array = []
var choir: Unit
var core: Structure
var relay: Structure
var storm: GlassStorm
var chamber_state := [0, 0, 0]        # 0 empty, 1 installing, 2 running
var chamber_progress := [0.0, 0.0, 0.0]
var chamber_damper: Array = [null, null, null]
var pulse_interval := 90.0
var next_pulse := 90.0
var ring_t := -1.0
var ring_done := {}
var shield_down_until := -1.0
var shield_cracked := false
var heartbeat_stopped := false
var _check_t := 0.0
var _storm_t := 120.0
var _raid_t := 100.0
var _wave_t := 150.0
var _under_wave_t := 50.0
var _descend_offered := false
var _maw_t := 0.0


func objective_preview() -> Array:
	return [
		["primary", "Phase 1: Establish a base on the crater rim."],
		["primary", "Phase 1: Destroy SIBYL's three Shaft Guardians to open the path to the underground."],
		["secondary", "Phase 1: Protect Lindqvist's damper convoy as it drives to the shaft entrance."],
		["bonus", "Use the Halo Lance uplink once to crack the Core Defender's shield (one shot only)."],
		["primary", "Phase 2: Escort the three dampers to the three heart-chambers and defend each one while it installs (90 seconds each)."],
		["primary", "Phase 2: Destroy SIBYL's core once all three dampers are running."],
		["secondary", "Phase 2: Keep Kestrel Ruiz and Dr. Lindqvist alive for the ending."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.04, 0.16, 0.08), "sky_horizon": Color(0.2, 0.42, 0.24),
		"ground_horizon": Color(0.12, 0.22, 0.14), "sun_rot": Vector3(-50, 60, 0),
		"sun_color": Color(0.75, 1.0, 0.8), "sun_energy": 0.9, "ambient": 0.4,
		"fog_color": Color(0.2, 0.38, 0.25), "fog_density": 0.005, "weather": "ash", "glow": 1.1,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 10010, {
		"ground": Color(0.25, 0.26, 0.23), "rock": Color(0.18, 0.22, 0.19), "variation": 0.05,
	})
	# the rock band between surface and underground
	map.fill_rect(Rect2i(94, 0, 7, H), MapGrid.Terrain.ROCK)
	# the crater rim ring (surface)
	for a in range(0, 360, 3):
		var rad := deg_to_rad(a)
		var p := Vector2(56, 44) + Vector2(cos(rad) * 30.0, sin(rad) * 26.0)
		if absf(angle_difference(rad, deg_to_rad(135))) > 0.35 and absf(angle_difference(rad, deg_to_rad(20))) > 0.25 and absf(angle_difference(rad, deg_to_rad(250))) > 0.25:
			map.blob(Vector2i(p), 1.6, MapGrid.Terrain.ROCK, 0.5)
	map.scatter(MapGrid.Terrain.ROCK, 10, 1.0, 2.2, [[BASE, 12], [SHAFT, 10], [RELAY, 5], [Vector2i(56, 44), 12]])
	map.carve(BASE, Vector2i(56, 44), 4.0)
	map.carve(Vector2i(56, 44), SHAFT, 4.0)
	map.carve(BASE, Vector2i(24, 40), 3.0)
	map.carve(Vector2i(24, 40), SHAFT, 3.0)
	map.clear_area(SHAFT, 5.0)
	map.clear_area(BASE, 10.0)
	for mw in MAWS:
		map.clear_area(mw, 4.0)
		map.tint_blob(mw, 3.5, Color(0.15, 0.3, 0.15))
	for c in [Vector2i(56, 44), Vector2i(62, 52), Vector2i(48, 40), Vector2i(26, 64), Vector2i(36, 84), Vector2i(80, 60)]:
		map.crystal_field(c, map.rng.randf_range(2.6, 3.8), MapGrid.Crystal.GREEN if randf() < 0.7 else MapGrid.Crystal.BLUE)
	# the underground: caverns of glass around the Seed
	map.fill_rect(Rect2i(101, 1, W - 102, H - 2), MapGrid.Terrain.ROCK)
	for c in CHAMBERS + [SEED, UNDER_START]:
		map.clear_area(c, 6.0 if c != SEED else 8.0)
	map.carve(UNDER_START, SEED, 5.0)
	for ch in CHAMBERS:
		map.carve(SEED, ch, 5.0)
		map.carve(UNDER_START, ch, 3.0)
	for x in range(101, W - 1):
		for y in range(1, H - 1):
			if map.terrain_at(Vector2i(x, y)) == MapGrid.Terrain.GROUND:
				map.tints[Vector2i(x, y)] = Color(0.12, 0.22, 0.15)
	for c in [Vector2i(114, 30), Vector2i(136, 32), Vector2i(114, 66), Vector2i(136, 64)]:
		map.clear_area(c, 3.0)
		map.crystal_field(c, 2.5, MapGrid.Crystal.GREEN)
	map.spread_enabled = false


func setup() -> void:
	start_credits = 12000
	player().credits = 12000
	player().extra_factions = ["veil"]
	lance_single_use = true
	spawn_one("mcv", PLAYER, BASE)
	building("veil_foundry", PLAYER, BASE + Vector2i(-9, -9), "foundry")
	spawn(["warden", "warden", "warden", "resonator", "resonator", "tempest", "tempest", "kite", "kite"], PLAYER, BASE + Vector2i(8, -6))
	spawn(["rifleman", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "rocket_trooper", "engineer", "engineer", "engineer", "engineer", "medic", "skyjumper", "skyjumper"], PLAYER, BASE + Vector2i(4, -10))
	if Campaign.flag("resonator_x"):
		spawn(["resonator_x"], PLAYER, BASE + Vector2i(10, -2))
	kestrel = spawn_one("kestrel", PLAYER, BASE + Vector2i(-2, -12), "kestrel")
	spawn(["shade_tank", "shade_tank", "cinder_drill", "cinder_drill", "mole_apc", "mole_apc", "raider", "raider"], PLAYER, BASE + Vector2i(-6, -14))
	lindqvist = spawn_one("lindqvist", PLAYER, BASE + Vector2i(6, 2), "lindqvist")
	for i in 3:
		var d := spawn_one("damper", PLAYER, BASE + Vector2i(8 + i * 2, 4), "damper")
		dampers.append(d)
	if Campaign.flag("refugees_saved"):
		tallow = spawn_one("tallow", PLAYER, BASE + Vector2i(-10, -4), "tallow")
		spawn(["outcast_fighter", "outcast_fighter", "outcast_fighter", "outcast_fighter", "outcast_brute", "outcast_brute"], PLAYER, BASE + Vector2i(-12, -2))
	# SIBYL on the surface
	for c in GUARDIANS:
		building("shaft_guardian", ENEMY, c - Vector2i(1, 1), "guardian")
	relay = building("sibyl_relay", ENEMY, RELAY - Vector2i(1, 1), "relay")
	building("guard_tower", ENEMY, SHAFT + Vector2i(-8, 6))
	building("guard_tower", ENEMY, SHAFT + Vector2i(8, 6))
	building("flak_nest", ENEMY, SHAFT + Vector2i(-3, 8))
	building("flak_nest", ENEMY, SHAFT + Vector2i(4, 8))
	spawn(["cyborg", "cyborg", "cyborg", "cyborg", "scorpion", "scorpion", "rocket_trooper"], ENEMY, SHAFT + Vector2i(0, 10))
	spawn(["cyborg", "cyborg", "scorpion", "shade_tank", "rifleman"], ENEMY, Vector2i(56, 44))
	spawn(["cyborg", "cyborg", "raider", "raider"], ENEMY, RELAY + Vector2i(3, 4))
	for c in MAWS:
		building("maw", NEUTRAL, c, "maw")
	storm = GlassStorm.new()
	storm.front = -30.0
	storm.width = 16.0
	storm.speed = 0.0
	storm.map_h = H
	storm.immune_teams = [ENEMY]
	storm.active = false
	G.world.add_child(storm)
	# SIBYL underground
	core = building("sibyl_core", ENEMY, SEED - Vector2i(1, 1), "core")
	core.invulnerable = true
	choir = spawn_one("choir", ENEMY, SEED + Vector2i(-5, 0), "choir")
	choir.hold_position = true
	choir.leash = 6.0
	if Campaign.flag("seed_core_known"):
		choir.max_hp *= 0.7
		choir.hp = choir.max_hp
	choir.damage_mult = 0.0
	for ch in CHAMBERS:
		spawn(["cyborg", "cyborg", "fiend", "fiend"], ENEMY, ch + Vector2i(0, 3))
	spawn(["cyborg", "cyborg", "cyborg", "floater", "floater"], ENEMY, SEED + Vector2i(3, 6))
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.5)
	l.light_energy = 6.0
	l.omni_range = 26.0
	l.position = cell_pos(SEED) + Vector3(0, 5, 0)
	G.world.add_child(l)
	add_marker("shaft", cell_pos(SHAFT), Color(0.5, 1.0, 0.6))


func begin() -> void:
	G.camera.bounds = SURFACE
	enable_harden()
	add_objective("base", "Establish a base on the crater rim (deploy the MCV).")
	add_objective("guardians", "Destroy SIBYL's three Shaft Guardians to open the path to the underground (0/3).")
	add_objective("convoy", "Protect Lindqvist's damper convoy and get all three dampers to the shaft entrance.", "secondary")
	add_objective("lance", "Use the Halo Lance uplink once to crack the Core Defender's shield (one shot only).", "bonus")
	add_objective("dampers", "Escort the three dampers to the heart-chambers and defend each while it installs (0/3).", "primary", false)
	add_objective("core", "Destroy SIBYL's core once all three dampers are running.", "primary", false)
	add_objective("allies", "Keep Kestrel Ruiz and Dr. Lindqvist alive.", "secondary", true, true)
	focus(BASE + Vector2i(4, -6))
	after(3.0, func(): say("kestrel", "My people are on your Veil tab one last time, Commander. Let's finish it."))
	if is_instance_valid(tallow):
		after(10.0, func(): say("tallow", "The Outcasts are here, Bastion. All of us who walked out of that mine."))
	else:
		after(10.0, func(): say("havel", "No word from Tallow. And there are Outcast raiders on the rim, Commander. They're not on our side any more."))
	after(20.0, func(): say("sibyl", "Welcome home, Commander. Everything here is already glass. You will be too."))


# ================================================================ frame

func tick(delta: float) -> void:
	if phase == 1:
		_surface(delta)
	else:
		_heart(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	_checks()


func _checks() -> void:
	var alive_dampers := dampers.filter(func(d): return is_instance_valid(d) and d.alive)
	if alive_dampers.is_empty():
		lose("All three resonance dampers were destroyed.")
		return
	if not (is_instance_valid(lindqvist) and lindqvist.alive):
		lose("Dr. Lindqvist was killed.")
		return
	if not (is_instance_valid(kestrel) and kestrel.alive) and is_active("allies"):
		fail("allies")
	if phase == 1:
		if is_active("base") and player().count_of("construction_yard") > 0:
			complete("base")
			say("okafor", "Base is up on the rim. Break those Guardians and get the dampers to the shaft.")
		var g := count_tagged("guardian")
		if is_active("guardians"):
			set_text("guardians", "Destroy SIBYL's three Shaft Guardians to open the path to the underground (%d/3).", [(3 - g)])
			if g == 0:
				complete("guardians")
				say("lindqvist", "The shaft is open! Bring the dampers to the entrance, Commander.")
		if alive_dampers.size() < 3 and is_active("convoy"):
			fail("convoy")
		var at_shaft := alive_dampers.filter(func(d): return G.flat_dist(d.position, cell_pos(SHAFT)) < 7.0)
		if is_done("guardians") and at_shaft.size() == alive_dampers.size() and not _descend_offered:
			_descend_offered = true
			if alive_dampers.size() == 3 and is_active("convoy"):
				complete("convoy")
			G.hud.add_special("descend", "DESCEND (strike force of 30)")
			say("havel", "Dampers are at the shaft. Gather your strike force around the entrance and give the word. Thirty units, no more.")
			after(90.0, func():
				if phase == 1:
					_descend())
	else:
		var under := team_units(PLAYER).filter(func(u): return HEART.has_point(Vector2(u.position.x, u.position.z)))
		if under.is_empty():
			lose("The strike force was crystallized.")


# ================================================================ phase 1

func _surface(delta: float) -> void:
	update_harden()
	_maw_t -= delta
	if _maw_t <= 0.0:
		_maw_t = 0.25
		for mw in tagged("maw"):
			for e in G.entities:
				if e is Unit and e.alive and not e.is_air and G.flat_dist(e.position, mw.position) <= 3.0:
					e.take_damage(14.0 * 0.25, "claw", null)
	# glass-storm surges: radar down, aircraft grounded, lightning
	_storm_t -= delta
	if not storm.active and _storm_t <= 0.0:
		storm.active = true
		storm.front = -2.0
		storm.speed = 0.55
		say_once("storm", "havel", "Glass storm surge rolling across the crater! Radar's going, and the Kites are grounded until it passes.")
	if storm.active and storm.band_min() > SURFACE.end.x + 4:
		storm.active = false
		_storm_t = 150.0
	G.radar_jammed = storm.active and storm.on_map(SURFACE.end.x)
	G.air_grounded = G.radar_jammed
	_hijack(delta)
	_raid_t -= delta
	if _raid_t <= 0.0:
		_raid_t = 110.0
		if not is_instance_valid(tallow) and not Campaign.flag("refugees_saved"):
			var from: Vector2i = [Vector2i(4, 30), Vector2i(40, 90), Vector2i(88, 70)][randi() % 3]
			send_wave(["outcast_fighter", "outcast_fighter", "outcast_fighter", "outcast_brute"], HOSTILE, from, BASE)
			say_once("raiders", "havel", "Outcast raiders coming over the rim! They're hitting everyone: us and SIBYL.")
	_wave_t -= delta
	if _wave_t <= 0.0:
		_wave_t = 100.0
		send_wave(["cyborg", "cyborg", "cyborg", "scorpion", "scorpion", "rocket_trooper", "floater"], ENEMY, SHAFT + Vector2i(0, 4), BASE)


func _hijack(delta: float) -> void:
	if not (is_instance_valid(relay) and relay.alive):
		return
	for e in G.entities:
		if not (e is Unit) or not e.alive or e.team != PLAYER or not e.def.get("networked", false):
			continue
		if G.flat_dist(e.position, relay.position) <= 8.0 and time >= float(e.tags.get("hardened_until", -1.0)):
			e.hijack = minf(1.0, e.hijack + delta / 6.0)
			if e.hijack >= 1.0:
				e.hijack = 0.0
				e.orig_team = PLAYER
				e.tags["hijacked_by"] = 0
				e.set_team(ENEMY)
				say_once("hijack", "havel", "SIBYL's relay in the crater is hijacking our machines again. Take it down.")
		else:
			e.hijack = maxf(0.0, e.hijack - delta / 6.0)


func special_action(id: String) -> void:
	if id == "descend" and phase == 1:
		_descend()
	else:
		super.special_action(id)


func _descend() -> void:
	if phase != 1:
		return
	phase = 2
	G.hud.remove_special("descend")
	remove_marker("shaft")
	storm.active = false
	G.radar_jammed = false
	G.air_grounded = false
	# the strike force: dampers and heroes, then the closest combat units
	var force: Array = []
	for d in dampers:
		if is_instance_valid(d) and d.alive:
			force.append(d)
	for h in [lindqvist, kestrel, tallow]:
		if is_instance_valid(h) and h.alive:
			force.append(h)
	var rest := team_units(PLAYER).filter(func(u): return not force.has(u) and not (u is Harvester) and u.def_id != "mcv")
	rest.sort_custom(func(a, b): return G.flat_dist(a.position, cell_pos(SHAFT)) < G.flat_dist(b.position, cell_pos(SHAFT)))
	for u in rest:
		if force.size() >= 30:
			break
		force.append(u)
	var cells: Array = G.map.spread_cells(UNDER_START, force.size())
	for i in force.size():
		force[i].position = cell_pos(cells[i])
		force[i].cmd_stop()
		force[i].hijack = 0.0
	player().allowed = {}
	player().free_radar = true   # the dampers map the caverns
	G.hud._rebuild_grid()
	G.camera.bounds = HEART
	focus(UNDER_START + Vector2i(4, 0))
	next_pulse = time + 60.0
	reveal("dampers")
	reveal("core")
	set_timer("pulse", "Seed pulse", next_pulse - time)
	if Campaign.flag("seed_core_known"):
		for i in CHAMBERS.size():
			add_marker("ch%d" % i, cell_pos(CHAMBERS[i]), Color(0.6, 0.9, 1.0))
		say("havel", "The Bazaar data mapped the heart-chambers for us. They're marked.")
	say("havel", "You're down. The Seed pulses every ninety seconds. When the counter hits zero, be inside a damper's bubble, a stopped Mole APC's shelter, or a Resonance Shelter. Engineers can deploy shelters with D.")
	say("sibyl", "You came all the way down. How kind.")


# ================================================================ phase 2

func _heart(delta: float) -> void:
	_install(delta)
	_reveal_chambers()
	if heartbeat_stopped:
		return
	var left := next_pulse - time
	set_timer("pulse", "Seed pulse", maxf(left, 0.0))
	if left <= 6.0 and left > 5.9 - delta:
		say("havel", "Pulse incoming! Get into shelter!")
		Fx.ring(cell_pos(SEED), Color(0.5, 1.0, 0.6, 0.5), 4.0, 5.0)
	if left <= 0.0 and ring_t < 0.0:
		ring_t = 0.0
		ring_done.clear()
		Fx.ring(cell_pos(SEED), Color(0.4, 1.0, 0.5, 0.9), 48.0, 3.0)
	if ring_t >= 0.0:
		ring_t += delta
		var r := ring_t / 3.0 * 48.0
		for u in team_units(PLAYER).duplicate():
			if ring_done.has(u) or not HEART.has_point(Vector2(u.position.x, u.position.z)):
				continue
			if G.flat_dist(u.position, cell_pos(SEED)) <= r:
				ring_done[u] = true
				if not _sheltered(u) and not u.tags.has("damper"):
					Fx.sparkle(u.position + Vector3(0, 0.5, 0), Color(0.5, 1.6, 0.6))
					Fx.explosion(u.position, 0.5)
					u.invulnerable = false
					u.die(null)
		if ring_t >= 3.0:
			ring_t = -1.0
			next_pulse = time + pulse_interval
			shield_down_until = time + 12.0
			say_once("shield", "havel", "The Choir's shield just dropped! Hit it now, it only lasts a few seconds after each pulse!")
			if time > 0.0:
				_under_wave()
	var down := shield_cracked or time < shield_down_until
	if is_instance_valid(choir) and choir.alive:
		choir.damage_mult = 1.0 if down else 0.0
		var sh: Node3D = choir.model.get_meta("shield", null)
		if sh:
			sh.visible = not down
	_under_wave_t -= delta
	if _under_wave_t <= 0.0:
		_under_wave_t = 70.0
		_under_wave()


func _sheltered(u: Unit) -> bool:
	for e in G.entities:
		if not e.alive or e.team != PLAYER:
			continue
		if e is Unit and e.tags.has("damper") and G.flat_dist(e.position, u.position) <= 3.5:
			return true
		if e is Unit and e.def_id == "mole_apc" and not e.is_moving() and G.flat_dist(e.position, u.position) <= 3.0:
			return true
		if e is Structure and e.shelter_radius() > 0.0 and G.flat_dist(e.position, u.position) <= e.shelter_radius():
			return true
	return false


func _under_wave() -> void:
	var targets := dampers.filter(func(d): return is_instance_valid(d) and d.alive)
	if targets.is_empty():
		return
	var d: Unit = targets[randi() % targets.size()]
	send_wave(["cyborg", "cyborg", "fiend", "fiend", "floater"], ENEMY, SEED + Vector2i(randi_range(-4, 4), randi_range(-4, 4)), G.map.world_to_cell(d.position))


func _reveal_chambers() -> void:
	for i in CHAMBERS.size():
		if chamber_state[i] == 0 and not _once.has("ch%d" % i) and team_near(cell_pos(CHAMBERS[i]), PLAYER, 12.0):
			_once["ch%d" % i] = true
			add_marker("ch%d" % i, cell_pos(CHAMBERS[i]), Color(0.6, 0.9, 1.0))
			say("lindqvist", "That's a heart-chamber. Park a damper in the middle and deploy it.")


func on_deploy(u: Unit) -> bool:
	if u.tags.has("damper"):
		for i in CHAMBERS.size():
			if chamber_state[i] == 0 and G.flat_dist(u.position, cell_pos(CHAMBERS[i])) <= 4.0:
				_start_install(i, u)
				return true
		G.notify(PLAYER, "Dampers must be deployed inside a heart-chamber.")
		return true
	if phase == 2 and u.is_engineer():
		var c: Vector2i = G.map.world_to_cell(u.position)
		for tl in [c, c - Vector2i(1, 0), c - Vector2i(0, 1), c - Vector2i(1, 1)]:
			if u._footprint_free(tl, Vector2i(2, 2)):
				u.remove_silently()
				var s := building("resonance_shelter", PLAYER, tl)
				s.power = 0
				G.notify(PLAYER, "Resonance Shelter deployed.")
				return true
		G.notify(PLAYER, "No room to deploy a shelter here.")
		return true
	return false


func _start_install(i: int, d: Unit) -> void:
	chamber_state[i] = 1
	chamber_progress[i] = 0.0
	chamber_damper[i] = d
	d.cmd_stop()
	d.speed_mult = 0.0
	remove_marker("ch%d" % i)
	say("lindqvist", "Damper deploying. Ninety seconds, Commander. Nothing touches it.")


func _install(delta: float) -> void:
	# a damper parked in a chamber starts installing on its own
	for d in dampers:
		if not (is_instance_valid(d) and d.alive) or d.speed_mult == 0.0:
			continue
		for i in CHAMBERS.size():
			if chamber_state[i] == 0 and d.order == Unit.Order.IDLE and G.flat_dist(d.position, cell_pos(CHAMBERS[i])) <= 3.0:
				_start_install(i, d)
	var running := 0
	for i in CHAMBERS.size():
		if chamber_state[i] == 1:
			var d = chamber_damper[i]
			if not (is_instance_valid(d) and d.alive):
				chamber_state[i] = 0
				chamber_damper[i] = null
				say("havel", "We lost the damper in chamber %d!", [(i + 1)])
				continue
			chamber_progress[i] += delta
			set_timer("ch%d" % i, "Damper %d installing", INSTALL_TIME - chamber_progress[i], [i + 1])
			if chamber_progress[i] >= INSTALL_TIME:
				chamber_state[i] = 2
				d.invulnerable = true
				clear_timer("ch%d" % i)
				pulse_interval += 30.0
				next_pulse += 30.0
				Fx.ring(d.position, Color(0.6, 0.9, 1.0), 8.0, 2.0)
				say("lindqvist", ["One damper running. The heartbeat is slowing.", "Two running. It's fighting us, Commander, I can feel it."][mini(_count_running(), 2) - 1] if _count_running() < 3 else "All three dampers are running!")
		if chamber_state[i] == 2:
			running += 1
	set_text("dampers", "Escort the three dampers to the heart-chambers and defend each while it installs (%d/3).", [running])
	if running >= 3 and not heartbeat_stopped:
		_sleep()


func _count_running() -> int:
	var n := 0
	for s in chamber_state:
		if s == 2:
			n += 1
	return n


func _sleep() -> void:
	heartbeat_stopped = true
	complete("dampers")
	clear_timer("pulse")
	ring_t = -1.0
	core.invulnerable = false
	shield_cracked = true
	say("lindqvist", "The heartbeat's stopped. It's asleep. It's actually asleep.")
	say("kestrel", "Then SIBYL is blind. The core is open, Commander. Break it.")
	say("sibyl", "No. No. I can still hear the song. I can still")
	add_marker("core", core.position, Color(1.0, 0.4, 0.4))


func fire_player_lance(up: Structure, pos: Vector3) -> void:
	super.fire_player_lance(up, pos)
	if is_active("lance") and not (is_instance_valid(choir) and choir.alive and G.flat_dist(pos, choir.position) <= 5.0):
		after(3.5, func():
			if is_active("lance"):
				fail("lance"))


func on_lance_struck(pos: Vector3) -> void:
	if is_instance_valid(choir) and choir.alive and G.flat_dist(pos, choir.position) <= 5.0 and is_active("lance"):
		shield_cracked = true
		complete("lance")
		say("havel", "Direct hit! The Choir's shield is cracked for good!")


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e == core:
		complete("core")
		say("kestrel", "This is for Oriel.")
		say("narrator", "Kestrel Ruiz smashes the last node by hand. SIBYL's core goes dark. Above the crater, the green sky begins to fade to grey.")
	if e == relay:
		for u in G.entities:
			if u is Unit and u.alive and u.orig_team == PLAYER and u.team == ENEMY and u.tags.has("hijacked_by"):
				u.set_team(PLAYER)
	if e == choir:
		say("havel", "The Choir is down!")


func modify_damage(e: Entity, dmg: float, _attacker: Entity) -> float:
	if e == core and not heartbeat_stopped:
		return 0.0
	return dmg
