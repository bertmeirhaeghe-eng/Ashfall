extends Mission
## Mission 6 — The Glass Garden. Tassili Plateau, green-lit night.
## Signature mechanic: the map is the enemy. A resonance bloom grows outward
## from its heart in real time, swallowing ground and crystallizing buildings.
## Powered Inhibitor Pylons push it back. Blue Vitrium is worth double but
## explodes in chain reactions when shot. After the last sample the bloom
## "notices" and grows three times faster until extraction.

const W := 100
const H := 92
const BASE := Vector2i(22, 70)
const HEART := Vector2i(66, 30)
const OUTPOST := Vector2i(86, 14)
const SAMPLE_SPOTS := [Vector2i(63, 31), Vector2i(69, 32), Vector2i(66, 26)]
const SAMPLE_TIME := 8.0

var lindqvist: Unit
var radius := 11.0
var growth := 0.075
var samples := 0
var sampling := {}           # spot index -> progress seconds
var extraction_t := -1.0
var cy_cells: Array = []
var _bloom_t := 0.0
var _hazard_t := 0.0
var _creature_t := 60.0
var _chain: Array = []       # [time, cell]
var _check_t := 0.0


func objective_preview() -> Array:
	return [
		["primary", "Build inhibitor pylons to push a safe path through the bloom (the crystal edge must not reach the Construction Yard)."],
		["primary", "Escort Dr. Lindqvist to the heart of the bloom and let him collect three resonance samples."],
		["primary", "Hold out until the extraction Kite arrives (3 minutes after the last sample)."],
		["secondary", "Destroy the Veil research outpost harvesting the bloom's blue crystal."],
		["bonus", "Collect $10,000 in Blue Vitrium from the bloom."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.02, 0.05, 0.05), "sky_horizon": Color(0.08, 0.2, 0.14),
		"ground_horizon": Color(0.05, 0.1, 0.07), "ground_bottom": Color(0.01, 0.03, 0.02),
		"sun_rot": Vector3(-50, 120, 0), "sun_color": Color(0.65, 0.95, 0.75), "sun_energy": 0.55,
		"ambient": 0.3, "fog_color": Color(0.08, 0.2, 0.13), "fog_density": 0.007, "glow": 1.2, "weather": "spores",
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 6606, {
		"ground": Color(0.28, 0.25, 0.22), "rock": Color(0.23, 0.2, 0.18), "variation": 0.04,
	})
	map.scatter(MapGrid.Terrain.ROCK, 20, 1.2, 2.8, [[BASE, 12], [HEART, 10], [OUTPOST, 7], [Vector2i(44, 50), 8]])
	map.crystal_field(Vector2i(12, 56), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(36, 82), 3.0, MapGrid.Crystal.GREEN)
	for c in [HEART, OUTPOST, Vector2i(44, 50), Vector2i(12, 56), Vector2i(36, 82)]:
		map.carve(BASE, c, 3.0)
	map.carve(HEART, OUTPOST, 3.0)
	map.clear_area(BASE, 10.0)
	map.clear_area(HEART, 6.0)
	map.spread_enabled = false
	map.redraw_interval = 1.0


func setup() -> void:
	start_credits = 7000
	player().credits = 7000
	var cy := building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	cy_cells = cy.footprint()
	building("power_plant", PLAYER, BASE + Vector2i(-6, -2))
	building("power_plant", PLAYER, BASE + Vector2i(-6, 2))
	building("refinery", PLAYER, BASE + Vector2i(3, 3))
	building("barracks", PLAYER, BASE + Vector2i(-2, 4))
	building("war_factory", PLAYER, BASE + Vector2i(3, -4))
	building("inhibitor_pylon", PLAYER, BASE + Vector2i(5, -7))
	building("radar", PLAYER, BASE + Vector2i(-2, -6))
	spawn(["rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "medic", "engineer"], PLAYER, BASE + Vector2i(8, -2))
	spawn(["warden", "warden", "tempest", "resonator"], PLAYER, BASE + Vector2i(9, 2))
	lindqvist = spawn_one("lindqvist", PLAYER, BASE + Vector2i(6, 0), "lindqvist")
	# the Veil research outpost, harvesting blue crystal
	building("refinery", ENEMY, OUTPOST, "outpost")
	building("barracks", ENEMY, OUTPOST + Vector2i(5, 0), "outpost")
	building("power_plant", ENEMY, OUTPOST + Vector2i(0, 5), "outpost")
	building("guard_tower", ENEMY, OUTPOST + Vector2i(-3, 5), "outpost")
	building("guard_tower", ENEMY, OUTPOST + Vector2i(5, 5), "outpost")
	spawn(["shade_tank", "scorpion", "rifleman", "rifleman", "rocket_trooper"], ENEMY, OUTPOST + Vector2i(-4, 8))
	spawn(["scorpion", "rifleman", "rifleman"], ENEMY, HEART + Vector2i(-6, 8))
	enemy().credits = 2000
	add_ai(enemy(), OUTPOST, BASE, {"build": false, "first_attack": 240.0, "wave_interval": 90.0, "wave_size": 4,
		"wave_max": 8, "income": 4.0, "units": ["rifleman", "rocket_trooper"]})
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(0.4, 1.0, 0.55)
		l.light_energy = 4.0
		l.omni_range = 14.0
		l.position = cell_pos(HEART) + Vector3(i * 3 - 3, 2.5, 0)
		G.world.add_child(l)
	_grow_bloom(true)
	add_marker("heart", cell_pos(HEART), Color(0.5, 1.0, 0.6))


func begin() -> void:
	add_objective("pylons", "Build Inhibitor Pylons (Defense tab) to push a safe path through the bloom (1/3). Keep the crystal away from the Construction Yard.")
	add_objective("samples", "Escort Dr. Lindqvist to the heart of the bloom and collect three resonance samples (0/3).")
	add_objective("extract", "Hold out until the extraction Kite arrives.", "primary", false)
	add_objective("lindqvist", "Dr. Lindqvist must survive.", "primary", true, true)
	add_objective("outpost", "Destroy the Veil research outpost harvesting the bloom's blue crystal.", "secondary")
	add_objective("blue", "Collect $10,000 in Blue Vitrium from the bloom ($0).", "bonus")
	set_status("bloom", "Bloom radius %d", [int(radius)])
	focus(BASE + Vector2i(6, -2))
	after(3.0, func(): say("lindqvist", "There it is. Look at it grow. Inhibitor pylons can be built further out than normal buildings, Commander. Chain them towards the heart and keep them powered."))
	after(14.0, func(): say("havel", "Careful with the blue crystal. It's worth double, but one stray shell and the whole field goes up."))


# ================================================================ bloom

func _inhibitors() -> Array:
	var out: Array = []
	for e in G.entities:
		if e is Structure and e.alive and e.team == PLAYER and e.inhibitor_radius() > 0.0:
			out.append(e)
	return out


## Set of cells covered by powered pylons (rebuilt once per bloom update).
func _inhibit_set(inh: Array) -> Dictionary:
	var out := {}
	for s in inh:
		var r: float = s.inhibitor_radius()
		var c0: Vector2i = G.map.world_to_cell(s.position)
		var ri := ceili(r)
		for x in range(c0.x - ri, c0.x + ri + 1):
			for y in range(c0.y - ri, c0.y + ri + 1):
				if cell_pos(Vector2i(x, y)).distance_to(s.position) <= r:
					out[Vector2i(x, y)] = true
	return out


func _inhibited(c: Vector2i, inh: Array) -> bool:
	var p := cell_pos(c)
	for s in inh:
		if G.flat_dist(s.position, p) <= s.inhibitor_radius():
			return true
	return false


func _in_bloom(c: Vector2i) -> bool:
	var d := Vector2(c - HEART).length() + G.map._noise.get_noise_2d(c.x * 4.0, c.y * 4.0) * 5.0
	return d <= radius


func crystal_allowed(c: Vector2i) -> bool:
	return not _inhibited(c, _inhibitors())


func _grow_bloom(initial := false) -> void:
	var inh := _inhibit_set(_inhibitors())
	var r := int(radius + 6.0)
	var map := G.map
	for x in range(HEART.x - r, HEART.x + r + 1):
		for y in range(HEART.y - r, HEART.y + r + 1):
			var c := Vector2i(x, y)
			if not map.in_bounds(c):
				continue
			var inside := _in_bloom(c)
			var blocked := inh.has(c)
			if inside and not blocked:
				if map.crystal_at(c) <= 0.0 and map.is_walkable(c):
					var blue := absi(hash(c)) % 100 < (35 if Vector2(c - HEART).length() < 14.0 else 18)
					map.add_crystal(c, MapGrid.Crystal.BLUE if blue else MapGrid.Crystal.GREEN, 250.0 if initial else 120.0)
			elif blocked and map.crystal_at(c) > 0.0:
				map.remove_crystal(c)


## Buildings the bloom reaches are slowly crystallized; the CY must never be reached.
func _crystallize(dt: float) -> void:
	var inh := _inhibit_set(_inhibitors())
	for s in player().structures():
		var touched := false
		for c in s.footprint():
			if _in_bloom(c) and not inh.has(c):
				touched = true
				break
		if not touched:
			continue
		if s.def_id == "construction_yard":
			lose("The crystal reached the Construction Yard.")
			return
		s.take_damage(s.max_hp * 0.03 * dt, "laser", null)
		if randf() < 0.3:
			Fx.sparkle(s.position + Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)), Color(0.5, 1.5, 0.6))
		say_once("crystallize", "havel", "The bloom is eating one of our buildings! Get a pylon next to it.")


func _hazard(dt: float) -> void:
	for u in G.entities:
		if not (u is Unit) or not u.alive or u.is_air:
			continue
		var on := G.map.crystal_at(G.map.world_to_cell(u.position)) > 0.0
		if not on:
			continue
		if u.team == ENEMY or u.team == HOSTILE:
			u.heal(6.0 * dt)
		elif u.team == PLAYER and not (u is Harvester):
			u.take_damage((4.0 if u.is_infantry else 6.0) * dt, "claw", null)


# ================================================================ Blue Vitrium chain reactions

func on_impact(pos: Vector3, warhead: String, _src: Entity) -> void:
	if warhead == "bullet" or warhead == "flak":
		return
	var c := G.map.world_to_cell(pos)
	for off in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cc: Vector2i = c + off
		if G.map.crystal_kind_at(cc) == MapGrid.Crystal.BLUE and G.map.crystal_at(cc) > 0.0:
			_chain.append([time, cc])
			say_once("chain", "havel", "Blue crystal detonation! Keep your units off those fields when you shoot!")
			return


func _run_chain() -> void:
	var n := 0
	while not _chain.is_empty() and n < 40:
		var item: Array = _chain[0]
		if float(item[0]) > time:
			break
		_chain.pop_front()
		var c: Vector2i = item[1]
		if G.map.crystal_kind_at(c) != MapGrid.Crystal.BLUE or G.map.crystal_at(c) <= 0.0:
			continue
		G.map.remove_crystal(c)
		n += 1
		var p := cell_pos(c)
		Fx.explosion(p + Vector3(0, 0.3, 0), 0.9)
		G.damage_area(p, 1.4, 90.0, "cannon", null)
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + off
			if G.map.crystal_kind_at(nc) == MapGrid.Crystal.BLUE and G.map.crystal_at(nc) > 0.0:
				_chain.append([time + 0.12, nc])


# ================================================================ frame

func tick(delta: float) -> void:
	radius += growth * delta
	_run_chain()
	_bloom_t -= delta
	if _bloom_t <= 0.0:
		_bloom_t = 1.0
		_grow_bloom()
		_crystallize(1.0)
		set_status("bloom", "Bloom radius %d%s", [int(radius), ("  " + tr("(ACCELERATING)")) if samples >= 3 else ""])
	_hazard_t -= delta
	if _hazard_t <= 0.0:
		_hazard_t = 0.5
		_hazard(0.5)
	_creature_t -= delta
	if _creature_t <= 0.0:
		_creature_t = maxf(25.0, 70.0 - radius)
		_spawn_creatures()
	_sampling(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.5
	var n := 0
	for s in _inhibitors():
		n += 1
	if is_active("pylons"):
		set_text("pylons", "Build Inhibitor Pylons (Defense tab) to push a safe path through the bloom (%d/3). Keep the crystal away from the Construction Yard.", [mini(n, 3)])
		if n >= 3:
			complete("pylons")
			say("lindqvist", "The pylons are holding it! Now make me a road to the centre.")
	if is_active("outpost") and count_tagged("outpost") == 0:
		complete("outpost")
		say("havel", "The Veil outpost is gone. Nobody else is mining this bloom tonight.")
	var blue := player().blue_refined
	if is_active("blue"):
		set_text("blue", "Collect $10,000 in Blue Vitrium from the bloom ($%d).", [int(blue)])
		if blue >= 10000.0:
			complete("blue")
			pending_flags["resonator_x"] = true
			say("lindqvist", "That's enough blue crystal. Give me a day and I'll build you an experimental Resonator with twice the range.")
	if extraction_t >= 0.0 and time >= extraction_t:
		_extract()
	if not (is_instance_valid(lindqvist) and lindqvist.alive):
		lose("Dr. Lindqvist was killed.")


func _sampling(delta: float) -> void:
	if samples >= 3 or not (is_instance_valid(lindqvist) and lindqvist.alive):
		return
	for i in SAMPLE_SPOTS.size():
		if sampling.get(i, 0.0) < 0.0:
			continue
		var spot := cell_pos(SAMPLE_SPOTS[i])
		if G.flat_dist(lindqvist.position, spot) <= 1.8:
			sampling[i] = float(sampling.get(i, 0.0)) + delta
			if randf() < delta * 4.0:
				Fx.sparkle(spot + Vector3(0, 0.4, 0), Color(0.6, 1.5, 1.0))
			if float(sampling[i]) >= SAMPLE_TIME:
				sampling[i] = -1.0
				samples += 1
				remove_marker("spot%d" % i)
				set_text("samples", "Escort Dr. Lindqvist to the heart of the bloom and collect three resonance samples (%d/3).", [samples])
				if samples < 3:
					say("lindqvist", ["Sample one. It's warm, Commander. Crystal shouldn't be warm.", "Sample two. The resonance is off every chart I have."][samples - 1])
				else:
					_last_sample()
			return
		if samples == 0 and not _once.has("spots") and G.flat_dist(lindqvist.position, cell_pos(HEART)) < 12.0:
			_once["spots"] = true
			for k in SAMPLE_SPOTS.size():
				add_marker("spot%d" % k, cell_pos(SAMPLE_SPOTS[k]), Color(0.6, 0.9, 1.0))
			remove_marker("heart")
			say("lindqvist", "Three resonance points, marked. I need a few seconds at each one.")


func _last_sample() -> void:
	complete("samples")
	growth *= 3.0
	extraction_t = time + 180.0
	reveal("extract")
	set_timer("extract", "Extraction Kite", 180.0)
	say("lindqvist", "Third sample. I have it! Commander, something is wrong. The resonance changed the moment I took it.")
	say("havel", "The bloom's growth just tripled. It noticed us. Extraction Kite is three minutes out. Hold on!")
	_creature_t = 5.0


func _extract() -> void:
	if not is_active("extract"):
		return
	clear_timer("extract")
	if is_instance_valid(lindqvist) and lindqvist.alive:
		Fx.ring(lindqvist.position, Color(0.8, 0.9, 1.0), 3.0, 1.2)
		say("pilot", "Kite on station. Doctor, get aboard. We're leaving!")
		complete("extract")


func _spawn_creatures() -> void:
	var n := 1 + int(radius / 18.0) + (2 if samples >= 3 else 0)
	var goal := BASE
	if is_instance_valid(lindqvist) and lindqvist.alive and randf() < 0.5:
		goal = G.map.world_to_cell(lindqvist.position)
	for i in n:
		var a := randf() * TAU
		var c := HEART + Vector2i(int(cos(a) * radius * 0.8), int(sin(a) * radius * 0.8))
		c = G.map.nearest_walkable(c)
		var u := spawn_one("fiend" if randf() < 0.6 else "floater", HOSTILE, c)
		if u:
			u.cmd_attack_move(goal)
	say_once("creatures", "havel", "Movement in the bloom. Crystal creatures, Floaters and Fiends, waking up as it grows.")


func placement_override(team: int, id: String, cell: Vector2i) -> int:
	if team != PLAYER or id != "inhibitor_pylon":
		return -1
	for e in G.entities:
		if e is Structure and e.team == PLAYER and e.alive and e.edge_distance(cell_pos(cell)) <= 7.0:
			return 1
	return 0


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e == lindqvist:
		lose("Dr. Lindqvist was killed.")
