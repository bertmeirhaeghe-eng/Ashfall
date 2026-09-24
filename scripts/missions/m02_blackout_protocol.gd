extends Mission
## Mission 2 — Blackout Protocol. Ruhr Industrial Zone, night.
## Signature mechanic: follow the power. The Veil base hides under a stealth
## field; cutting pylons, substations and power plants weakens it:
## 75% power = slower defenses, 50% = the cloak flickers, 0% = it fails.

const W := 100
const H := 80
const BASE := Vector2i(14, 64)
const VEIL := Vector2i(74, 20)
const FIELD_R := 15.0
const COAL := Vector2i(36, 22)

var gen: Structure
var veil_cy: Structure
var power_start := 1
var gen_found := false
var base_found := false
var gen_down := false
var cables: Array = []   # [a, b, MeshInstance3D]
var _check_t := 0.0
var _flicker_t := 0.0
var _hunt_t := 150.0
var _last_ratio := 1.0


func objective_preview() -> Array:
	return [
		["primary", "Find the Veil base hidden in the industrial zone."],
		["primary", "Destroy the Stealth Generator that hides it."],
		["primary", "Destroy the Veil Construction Yard."],
		["secondary", "Keep the Mobile Sensor Array alive."],
		["bonus", "Capture the old coal power station with an Engineer."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.02, 0.03, 0.06), "sky_horizon": Color(0.2, 0.12, 0.08),
		"ground_horizon": Color(0.1, 0.08, 0.07), "ground_bottom": Color(0.02, 0.02, 0.02),
		"sun_rot": Vector3(-60, -30, 0), "sun_color": Color(0.55, 0.65, 0.95), "sun_energy": 0.35,
		"ambient": 0.3, "fog_color": Color(0.12, 0.1, 0.1), "fog_density": 0.01, "exposure": 1.1, "glow": 1.0,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 2202, {
		"ground": Color(0.2, 0.19, 0.18), "rock": Color(0.16, 0.15, 0.15), "building": Color(0.12, 0.12, 0.13),
		"block": Color(0.24, 0.22, 0.22), "variation": 0.03,
	})
	var road := Color(0.13, 0.13, 0.14)
	for y in [16, 36, 56]:
		map.tint_line(Vector2i(2, y), Vector2i(W - 3, y), 2.5, road)
	for x in [24, 50, 90]:
		map.tint_line(Vector2i(x, 2), Vector2i(x, H - 3), 2.5, road)
	# abandoned factory blocks
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	for bx in range(4, W - 6, 13):
		for by in range(4, H - 6, 11):
			var c := Vector2i(bx + rng.randi_range(0, 4), by + rng.randi_range(0, 3))
			if Vector2(c).distance_to(Vector2(BASE)) < 16 or Vector2(c).distance_to(Vector2(VEIL)) < 15 or Vector2(c).distance_to(Vector2(COAL)) < 6:
				continue
			if rng.randf() < 0.6:
				map.fill_rect(Rect2i(c, Vector2i(rng.randi_range(3, 6), rng.randi_range(3, 5))), MapGrid.Terrain.BUILDING)
	map.scatter(MapGrid.Terrain.ROCK, 6, 1.0, 1.8, [[BASE, 14], [VEIL, 16], [COAL, 6]])
	map.crystal_field(Vector2i(28, 70), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(8, 44), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(46, 64), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(88, 36), 3.0, MapGrid.Crystal.GREEN)
	for c in [VEIL, COAL, Vector2i(40, 50), Vector2i(88, 58), Vector2i(60, 5), Vector2i(88, 5), Vector2i(46, 64)]:
		map.carve(BASE, c, 2.0)
	map.clear_area(VEIL, 12.0)
	map.clear_area(BASE, 9.0)


func setup() -> void:
	start_credits = 5000
	player().credits = 5000
	building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	building("power_plant", PLAYER, BASE + Vector2i(4, -2))
	building("barracks", PLAYER, BASE + Vector2i(4, 2))
	spawn(["rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "engineer"], PLAYER, BASE + Vector2i(6, -6))
	spawn(["scout_mech", "warden"], PLAYER, BASE + Vector2i(8, -3))
	var sensor := spawn_one("mobile_sensor", PLAYER, BASE + Vector2i(9, -7), "sensor")
	sensor.tags["sensor"] = true

	# --- the Veil base (inside the stealth field)
	veil_cy = building("construction_yard", ENEMY, VEIL + Vector2i(3, -4), "base")
	gen = building("stealth_generator", ENEMY, VEIL + Vector2i(-4, 1), "base")
	gen.tags["gen"] = true
	building("war_factory", ENEMY, VEIL + Vector2i(-2, -6), "base")
	building("barracks", ENEMY, VEIL + Vector2i(6, 1), "base")
	building("refinery", ENEMY, VEIL + Vector2i(1, 4), "base")
	building("power_plant", ENEMY, VEIL + Vector2i(8, -5), "base")
	for off in [Vector2i(-7, 6), Vector2i(-8, -2), Vector2i(5, 8), Vector2i(10, 4)]:
		building("guard_tower", ENEMY, VEIL + off, "base")
	# northern sector: power plants fed through the Veil grid
	for c in [Vector2i(58, 4), Vector2i(86, 4)]:
		building("power_plant", ENEMY, c, "north")
	building("veil_pylon", ENEMY, Vector2i(66, 8), "north")
	building("veil_pylon", ENEMY, Vector2i(82, 9), "north")
	# grid spurs that run out of the cloak (visible, follow them!)
	var s1 := building("veil_substation", ENEMY, Vector2i(40, 49), "grid")
	var s2 := building("veil_substation", ENEMY, Vector2i(88, 58), "grid")
	var chain1: Array = [s1]
	for c in [Vector2i(47, 44), Vector2i(54, 39), Vector2i(60, 34), Vector2i(66, 29)]:
		chain1.append(building("veil_pylon", ENEMY, c, "grid"))
	var chain2: Array = [s2]
	for c in [Vector2i(87, 49), Vector2i(85, 41), Vector2i(82, 33)]:
		chain2.append(building("veil_pylon", ENEMY, c, "grid"))
	chain1.append(gen)
	chain2.append(veil_cy)
	for ch in [chain1, chain2]:
		for i in range(ch.size() - 1):
			_cable(ch[i], ch[i + 1])
	var north := tagged("north")
	_cable(north[0], north[2])
	_cable(north[2], gen)
	_cable(north[1], north[3])
	_cable(north[3], veil_cy)
	# defenders
	spawn(["scorpion", "scorpion", "rifleman", "rifleman", "rocket_trooper"], ENEMY, VEIL + Vector2i(-6, 8))
	spawn(["raider", "raider", "rifleman", "rifleman"], ENEMY, Vector2i(56, 36))
	spawn(["rifleman", "rocket_trooper", "rifleman"], ENEMY, Vector2i(44, 46))
	enemy().credits = 3000
	add_ai(enemy(), VEIL, BASE, {"first_attack": 300.0, "wave_interval": 80.0, "wave_size": 5, "wave_max": 12,
		"income": 5.0, "units": ["rifleman", "rocket_trooper", "raider", "scorpion"],
		"build_order": ["power_plant", "guard_tower", "power_plant", "guard_tower"]})
	# the coal power station (neutral)
	building("tech_power_station", NEUTRAL, COAL, "coal")
	add_marker("coal", cell_pos(COAL) + Vector3(1.5, 0, 1.5), Color(1.0, 0.85, 0.3))
	enemy().recalc_power()
	power_start = maxi(enemy().power_produced, 1)
	_lights()
	_apply_field(0.0)


func _cable(a: Structure, b: Structure) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.25, 0.15)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pa := a.position + Vector3(0, 1.7, 0)
	var pb := b.position + Vector3(0, 1.7, 0)
	var up := (pb - pa).normalized()
	var side := up.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	mi.transform = Transform3D(Basis(side, up * pa.distance_to(pb), side.cross(up)), (pa + pb) * 0.5)
	G.world.add_child(mi)
	cables.append([a, b, mi])
	G.map.tint_line(G.map.world_to_cell(a.position), G.map.world_to_cell(b.position), 1.0, Color(0.35, 0.1, 0.07))


func _lights() -> void:
	# burning barrels and Veil searchlights
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var c := Vector2i(rng.randi_range(6, W - 7), rng.randi_range(6, H - 7))
		if not G.map.is_walkable(c):
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 2.2
		l.omni_range = 5.0
		l.position = cell_pos(c) + Vector3(0, 0.8, 0)
		G.world.add_child(l)
		var barrel := MeshFactory.build("", Color(0.3, 0.2, 0.1), "neutral")
		barrel.position = cell_pos(c)
		barrel.scale = Vector3(0.5, 0.8, 0.5)
		G.world.add_child(barrel)
		Fx.sparkle(cell_pos(c) + Vector3(0, 0.5, 0), Color(2, 1, 0.3))
	for c in [BASE, BASE + Vector2i(6, -6)]:
		var l2 := OmniLight3D.new()
		l2.light_color = Color(0.7, 0.8, 1.0)
		l2.light_energy = 2.0
		l2.omni_range = 9.0
		l2.position = cell_pos(c) + Vector3(0, 3, 0)
		G.world.add_child(l2)
	for off in [Vector2i(-12, 10), Vector2i(12, 10), Vector2i(-14, -4)]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.9, 0.75)
		sp.light_energy = 6.0
		sp.spot_range = 22.0
		sp.spot_angle = 12.0
		sp.position = cell_pos(VEIL + off) + Vector3(0, 6, 0)
		sp.rotation_degrees = Vector3(-35, randf() * 360.0, 0)
		sp.set_meta("searchlight", true)
		G.world.add_child(sp)
		_searchlights.append(sp)


var _searchlights: Array = []


func begin() -> void:
	add_objective("find", "Find the Veil base hidden in the industrial zone. Follow the red power lines.")
	add_objective("gen", "Destroy the Stealth Generator that hides the base.")
	add_objective("cy", "Destroy the Veil Construction Yard.")
	add_objective("sensor", "Keep the Mobile Sensor Array alive.", "secondary", true, true)
	add_objective("coal", "Capture the old coal power station with an Engineer.", "bonus")
	focus(BASE + Vector2i(6, -4))
	set_status("power", "Veil power 100%")
	after(3.0, func(): say("havel", "Those glowing red cables are Veil power lines, Commander. Follow them. Every pylon and substation you cut drains the field."))
	after(12.0, func(): say("havel", "The Sensor Array sees through the cloak, but only up close. Don't lose it before we've found their generator."))


# ================================================================ frame

func tick(delta: float) -> void:
	for sp in _searchlights:
		if is_instance_valid(sp):
			sp.rotate_y(delta * 0.35)
	_check_t -= delta
	_flicker_t -= delta
	_hunt_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.3
		_update_power()
		_apply_field(delta)
		_check_found()
		_check_cables()
		if not (is_instance_valid(veil_cy) and veil_cy.alive) and is_active("cy"):
			complete("cy")
			say("havel", "Their Construction Yard is down. The Ruhr is ours again.")
		if player().count_of("construction_yard") == 0:
			lose("Your Construction Yard was destroyed.")
	if _hunt_t <= 0.0:
		_hunt_t = 110.0
		_shade_hunt()


func power_ratio() -> float:
	enemy().recalc_power()
	return clampf(float(enemy().power_produced) / float(power_start), 0.0, 1.0)


func _update_power() -> void:
	var r := power_ratio()
	if gen_down:
		r = 0.0
	set_status("power", "Veil power %d%%" % int(r * 100.0))
	enemy().defense_rof_mult = 0.5 if r <= 0.75 else 1.0
	if r <= 0.75 and _last_ratio > 0.75:
		say("havel", "Veil power is under seventy-five percent. Their defenses are running slow. We're starving them.")
	if r <= 0.5 and _last_ratio > 0.5:
		say("havel", "Their cloak is flickering! Sections of the base keep showing up. Watch for the generator.")
	if r <= 0.001 and _last_ratio > 0.001 and not gen_down:
		gen_down = true
		say("havel", "Zero power! The Stealth Generator just failed. The whole base is out in the open.")
	_last_ratio = r


func _gen_alive() -> bool:
	return is_instance_valid(gen) and gen.alive


## Every Veil entity inside the field is cloaked while the generator runs.
func _apply_field(_dt: float) -> void:
	var active := _gen_alive() and not gen_down
	var r := power_ratio()
	var flicker := active and r <= 0.5 and _flicker_t <= 0.0
	if flicker:
		_flicker_t = 3.0
	for e in G.entities:
		if e.team != ENEMY or not e.alive:
			continue
		var inside: bool = active and e.position.distance_to(gen.position) <= FIELD_R
		if e.force_hidden != inside:
			e.force_hidden = inside
			e.detected_mask = -2
		if flicker and inside and e is Structure:
			e.force_reveal = randf() < 0.45
		elif not flicker and _flicker_t < 1.5:
			e.force_reveal = false


func _check_found() -> void:
	for e in tagged("base"):
		if e.visible_to(PLAYER):
			if not base_found:
				base_found = true
				complete("find")
				say("havel", "Contact! Veil structures, right where the power was going. We've found their base.")
			if e == gen and not gen_found:
				gen_found = true
				add_marker("gen", gen.position, Color(0.8, 0.4, 1.0))
				say("havel", "That's the Stealth Generator. Take it out and the whole field collapses.")
	if not _gen_alive() and is_active("gen"):
		gen_found = true
		remove_marker("gen")
		complete("gen")
		if not base_found:
			base_found = true
			complete("find")
		say("havel", "Generator destroyed! The field is down, the whole base is exposed.")


func _check_cables() -> void:
	for i in range(cables.size() - 1, -1, -1):
		var c: Array = cables[i]
		if not (is_instance_valid(c[0]) and c[0].alive) or not (is_instance_valid(c[1]) and c[1].alive):
			if is_instance_valid(c[2]):
				c[2].queue_free()
			cables.remove_at(i)


func _shade_hunt() -> void:
	if not (is_instance_valid(veil_cy) and veil_cy.alive):
		return
	var harvs: Array = team_units(PLAYER).filter(func(u): return u is Harvester)
	if harvs.is_empty():
		return
	var tgt: Unit = harvs[randi() % harvs.size()]
	var hunters := spawn(["shade_tank", "shade_tank"], ENEMY, VEIL + Vector2i(-8, 8), "scripted")
	for h in hunters:
		h.tags["scripted"] = true
		h.cmd_attack(tgt)
	if once("shade_line"):
		after(25.0, func(): say("havel", "Something is hitting our harvesters and we can't see it. Shade Tanks! Put Sensor Towers by the crystal fields."))


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("sensor"):
		if not gen_found:
			lose("The Mobile Sensor Array was destroyed before the Stealth Generator was found.")
		else:
			fail("sensor")
	if (e.tags.has("grid") or e.tags.has("north")) and once("first_pylon"):
		say("havel", "That's one. Their power draw just dropped. Keep cutting.")


func on_captured(s: Entity, _old: int, new_team: int) -> void:
	if s.tags.has("coal") and new_team == PLAYER:
		remove_marker("coal")
		complete("coal")
		for e in tagged("north"):
			if e.power > 0:
				e.power = 0
		enemy().recalc_power()
		say("engineer", "Coal station's ours, Commander. Rerouting the grid: our base gets the power, and their northern sector goes dark.")

