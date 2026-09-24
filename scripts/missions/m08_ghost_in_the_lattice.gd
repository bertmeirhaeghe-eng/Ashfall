extends Mission
## Mission 8 — Ghost in the Lattice. Istanbul Clear Zone, rain at night.
## Signature mechanic: shared command and hijack fields. You command your
## Bastion base plus Kestrel Ruiz's loyal Veil units (second sidebar tab).
## Each SIBYL relay tower projects a hijack field: networked units inside
## (walkers, hovers, Kites, cyborgs) slowly fall under SIBYL's control; analog
## units (infantry, Kestrel's machines, Outcasts) are immune. Destroying a
## tower returns every unit it stole.

const W := 112
const H := 92
const BASE := Vector2i(56, 84)
const GATE := Vector2i(54, 72)
const TOWERS := [Vector2i(16, 30), Vector2i(42, 14), Vector2i(72, 16), Vector2i(98, 34)]
const BAZAAR := Vector2i(30, 50)
const FIELD_R := 8.5
const HIJACK_TIME := 6.0

var gate: Structure
var kestrel: Unit
var towers: Array = []
var tower_rings: Array = []
var reboots := 0
var node: Structure
var harden_ready_t := 0.0
var _check_t := 0.0
var _wave_t := 100.0
var _twist := false


func objective_preview() -> Array:
	return [
		["primary", "Destroy the four SIBYL relay towers around the city."],
		["primary", "Keep Kestrel Ruiz alive."],
		["primary", "Protect the Istanbul Clear Zone's main gate."],
		["secondary", "Recapture hijacked Bastion units using Engineers (\"reboot\" them) instead of destroying them."],
		["bonus", "Find the hidden SIBYL data node under the Grand Bazaar."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.03, 0.04, 0.07), "sky_horizon": Color(0.16, 0.14, 0.18),
		"ground_horizon": Color(0.08, 0.08, 0.1), "ground_bottom": Color(0.02, 0.02, 0.03),
		"sun_rot": Vector3(-55, 30, 0), "sun_color": Color(0.6, 0.7, 1.0), "sun_energy": 0.35,
		"ambient": 0.35, "fog_color": Color(0.12, 0.12, 0.16), "fog_density": 0.012, "weather": "rain", "glow": 1.0,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 8808, {
		"ground": Color(0.17, 0.17, 0.19), "rock": Color(0.2, 0.19, 0.2), "building": Color(0.1, 0.1, 0.11),
		"block": Color(0.3, 0.28, 0.3), "variation": 0.03, "water": Color(0.06, 0.1, 0.16),
	})
	# the Bosphorus on the east edge
	map.fill_rect(Rect2i(W - 6, 1, 5, H - 2), MapGrid.Terrain.WATER)
	# city blocks with streets every 11 cells
	for bx in range(3, W - 8, 11):
		for by in range(3, 66, 11):
			var rect := Rect2i(bx + 2, by + 2, 7, 7)
			var c := rect.get_center()
			var skip := false
			for t in TOWERS + [BAZAAR]:
				if Vector2(c).distance_to(Vector2(t)) < 7.0:
					skip = true
			if not skip:
				map.fill_rect(Rect2i(rect.position, Vector2i(map.rng.randi_range(4, 7), map.rng.randi_range(4, 7))), MapGrid.Terrain.BUILDING)
	# the Clear Zone wall with the main gate and two sally ports
	map.fill_rect(Rect2i(1, 72, W - 2, 2), MapGrid.Terrain.BUILDING)
	map.fill_rect(Rect2i(GATE.x, 72, 4, 2), MapGrid.Terrain.GROUND)
	map.fill_rect(Rect2i(GATE.x - 3, 72, 2, 2), MapGrid.Terrain.GROUND)
	map.fill_rect(Rect2i(GATE.x + 5, 72, 2, 2), MapGrid.Terrain.GROUND)
	map.fill_rect(Rect2i(20, 72, 2, 2), MapGrid.Terrain.GROUND)
	map.fill_rect(Rect2i(88, 72, 2, 2), MapGrid.Terrain.GROUND)
	map.tint_blob(BAZAAR, 5.0, Color(0.32, 0.22, 0.14))
	for t in TOWERS:
		map.clear_area(t, 4.0)
	map.clear_area(BASE, 8.0)
	map.crystal_field(Vector2i(20, 84), 3.2, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(90, 84), 3.2, MapGrid.Crystal.GREEN)


func setup() -> void:
	start_credits = 8000
	player().credits = 8000
	player().extra_factions = ["veil"]
	building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	building("power_plant", PLAYER, BASE + Vector2i(-7, -1))
	building("power_plant", PLAYER, BASE + Vector2i(-7, 3))
	building("power_plant", PLAYER, BASE + Vector2i(10, 3))
	building("refinery", PLAYER, BASE + Vector2i(-13, 1))
	building("barracks", PLAYER, BASE + Vector2i(4, -3))
	building("war_factory", PLAYER, BASE + Vector2i(4, 2))
	building("radar", PLAYER, BASE + Vector2i(-4, 3))
	building("helipad", PLAYER, BASE + Vector2i(9, -2))
	building("veil_foundry", PLAYER, BASE + Vector2i(-12, -5), "foundry")
	gate = building("clear_zone_gate", PLAYER, GATE, "gate")
	gate.max_hp = 8000.0
	gate.hp = 8000.0
	var gt := building("guard_tower", PLAYER, GATE + Vector2i(-5, 3), "gate_tower")
	gt.tags["gate_tower"] = true
	building("guard_tower", PLAYER, GATE + Vector2i(8, 3))
	spawn(["warden", "warden", "warden", "tempest", "tempest", "scout_mech"], PLAYER, GATE + Vector2i(2, -6))
	building("guard_tower", PLAYER, GATE + Vector2i(-2, -3))
	building("guard_tower", PLAYER, GATE + Vector2i(6, -3))
	spawn(["kite", "kite"], PLAYER, BASE + Vector2i(10, -5))
	spawn(["rifleman", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper"], PLAYER, GATE + Vector2i(-2, -6))
	spawn(["engineer", "engineer", "engineer", "medic"], PLAYER, BASE + Vector2i(-4, -7))
	# Kestrel's loyal Veil fighters (analog: SIBYL can't touch them)
	kestrel = spawn_one("kestrel", PLAYER, BASE + Vector2i(-10, -9), "kestrel")
	spawn(["shade_tank", "shade_tank", "cinder_drill", "cinder_drill", "mole_apc", "raider", "raider", "raider"], PLAYER, BASE + Vector2i(-14, -10), "kestrel_unit")
	spawn(["rifleman", "rifleman", "rocket_trooper", "rocket_trooper"], PLAYER, BASE + Vector2i(-12, -12))
	# SIBYL's relay towers and forces in the city
	for i in TOWERS.size():
		var t := building("sibyl_relay", ENEMY, TOWERS[i] - Vector2i(1, 1), "relay")
		t.tags["relay_id"] = i
		towers.append(t)
		var ring := _field_ring()
		ring.position = t.position
		G.world.add_child(ring)
		tower_rings.append(ring)
		spawn(["cyborg", "cyborg", "rifleman", "rocket_trooper", "scorpion"], ENEMY, TOWERS[i] + Vector2i(0, 5))
		building("guard_tower", ENEMY, TOWERS[i] + Vector2i(3, 3))
	node = building("data_node", ENEMY, BAZAAR, "node")
	node.force_hidden = true
	spawn(["cyborg", "cyborg", "cyborg", "scorpion", "scorpion"], ENEMY, Vector2i(56, 40))
	enemy().credits = 0
	_city_lights()


func _field_ring() -> Node3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.96
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 4
	mi.mesh = tm
	mi.scale = Vector3(FIELD_R, 0.4, FIELD_R)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.5, 1.0, 0.6, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.1
	return mi


func _city_lights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for i in 22:
		var c := Vector2i(rng.randi_range(4, W - 10), rng.randi_range(4, 70))
		if not G.map.is_walkable(c):
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.6
		l.omni_range = 6.0
		l.position = cell_pos(c) + Vector3(0, 2.5, 0)
		G.world.add_child(l)


func begin() -> void:
	add_objective("relays", "Destroy the four SIBYL relay towers around the city (0/4).")
	add_objective("kestrel", "Keep Kestrel Ruiz alive.", "primary", true, true)
	add_objective("gate", "Protect the Istanbul Clear Zone's main gate.", "primary", true, true)
	add_objective("reboot", "Recapture hijacked Bastion units with Engineers instead of destroying them (0/3).", "secondary")
	add_objective("node", "Find the hidden SIBYL data node under the Grand Bazaar.", "bonus")
	G.hud.add_special("harden", "Harden network (30s)")
	for i in towers.size():
		add_marker("relay%d" % i, towers[i].position, Color(0.5, 1.0, 0.6))
	focus(BASE + Vector2i(0, -8))
	after(3.0, func(): say("kestrel", "My Shade Tanks and drills are on your Veil tab now, Commander. The green rings are SIBYL's hijack fields. Send in anything without a network link: infantry, my machines."))
	after(13.0, func(): say("havel", "Keep the walkers, hovers and Kites out of those rings, or they'll turn on us. The Harden button buys networked units thirty seconds of immunity."))
	after(40.0, func(): say("havel", "One more thing. Street rumours say the Veil ran something out of the Grand Bazaar, west of the centre. Worth a look."))
	after(6.0, func(): say("sibyl", "Commander. You are fighting the tide with buckets. Every machine you own already listens to me."))


# ================================================================ frame

func tick(delta: float) -> void:
	_hijack(delta)
	for r in tower_rings:
		if is_instance_valid(r):
			var m := r.material_override as StandardMaterial3D
			m.albedo_color.a = 0.35 + 0.3 * absf(sin(time * 2.0))
	var cd := harden_ready_t - time
	G.hud.set_special("harden", "Harden network (30s)" if cd <= 0.0 else "Harden recharging %ds" % int(cd), cd <= 0.0)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	var alive_towers := 0
	for t in towers:
		if is_instance_valid(t) and t.alive:
			alive_towers += 1
	set_text("relays", "Destroy the four SIBYL relay towers around the city (%d/4)." % (4 - alive_towers))
	if alive_towers == 0 and is_active("relays"):
		complete("relays")
	if not _twist and (alive_towers <= 2 or time > 720.0):
		_twist = true
		for gt in tagged("gate_tower"):
			if gt.team == PLAYER:
				gt.set_team(ENEMY)
		say("sibyl", "Your walls are made of machines too, Commander.")
		say("havel", "SIBYL just took one of the gate's own defense towers! It's firing on us!")
	if is_active("node") and node.force_hidden and team_near(node.position, PLAYER, 3.5):
		node.force_hidden = false
		node.detected_mask = -2
		complete("node")
		pending_flags["seed_core_known"] = true
		say("havel", "There it is, under the Bazaar: a SIBYL data node. Downloading. Commander, this has coordinates in it. The Seed's core chambers.")
	_waves(0.4)
	if not (is_instance_valid(kestrel) and kestrel.alive):
		lose("Kestrel Ruiz was killed.")
	elif not (is_instance_valid(gate) and gate.alive):
		lose("The Clear Zone's main gate was destroyed.")
	elif player().count_of("construction_yard") == 0:
		lose("Your Construction Yard was destroyed.")


func _hijack(delta: float) -> void:
	for e in G.entities:
		if not (e is Unit) or not e.alive or not e.def.get("networked", false):
			continue
		if e.team != PLAYER:
			continue
		var hardened: bool = time < float(e.tags.get("hardened_until", -1.0))
		var in_field := -1
		if not hardened:
			for i in towers.size():
				var t = towers[i]
				if is_instance_valid(t) and t.alive and e.position.distance_to(t.position) <= FIELD_R:
					in_field = i
					break
		if in_field >= 0:
			e.hijack = minf(1.0, e.hijack + delta / HIJACK_TIME)
			if e.hijack >= 1.0:
				e.hijack = 0.0
				e.orig_team = PLAYER
				e.tags["hijacked_by"] = in_field
				e.set_team(ENEMY)
				e.cmd_attack_move(BASE)
				say_once("first_hijack", "havel", "We just lost control of a unit! SIBYL has it. Get it back with an Engineer, or kill that tower.")
		else:
			e.hijack = maxf(0.0, e.hijack - delta / HIJACK_TIME)


func special_action(id: String) -> void:
	if id == "harden" and time >= harden_ready_t:
		harden_ready_t = time + 120.0
		for u in team_units(PLAYER):
			if u.def.get("networked", false):
				u.tags["hardened_until"] = time + 30.0
				u.hijack = 0.0
				Fx.ring(u.position, Color(0.5, 0.8, 1.0), 1.2, 0.6)
		G.notify(PLAYER, "Networked units hardened for 30 seconds.")


func can_interact(u: Unit, t: Entity) -> bool:
	if u.is_engineer() and t is Unit and t.orig_team == PLAYER and t.team == ENEMY:
		return true
	return super.can_interact(u, t)


func on_enter(u: Unit, t: Entity) -> bool:
	if t is Unit and t.orig_team == PLAYER and t.team == ENEMY and u.team == PLAYER:
		t.set_team(PLAYER)
		t.tags.erase("hijacked_by")
		t.tags["hardened_until"] = time + 20.0
		u.remove_silently()
		reboots += 1
		set_text("reboot", "Recapture hijacked Bastion units with Engineers instead of destroying them (%d/3)." % mini(reboots, 3))
		if reboots >= 3 and is_active("reboot"):
			complete("reboot")
		say_once("reboot_line", "engineer", "Rebooted. She's ours again, Commander, and SIBYL is out of her head.")
		return true
	return false


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("relay"):
		var id: int = e.tags["relay_id"]
		remove_marker("relay%d" % id)
		if is_instance_valid(tower_rings[id]):
			tower_rings[id].queue_free()
		var back := 0
		for u in G.entities:
			if u is Unit and u.alive and int(u.tags.get("hijacked_by", -1)) == id and u.orig_team == PLAYER:
				u.set_team(PLAYER)
				u.tags.erase("hijacked_by")
				back += 1
		say("kestrel", "Tower down!" + (" %d of your machines just woke up on our side." % back if back > 0 else ""))
		if once("sibyl_tower"):
			say("sibyl", "A tower is a thought, Commander. I have many thoughts.")


func _waves(dt: float) -> void:
	_wave_t -= dt
	if _wave_t > 0.0:
		return
	_wave_t = 70.0
	var from := Vector2i(randi_range(10, W - 16), 3)
	send_wave(["cyborg", "cyborg", "cyborg", "scorpion", "raider", "rifleman", "rocket_trooper"], ENEMY, from, GATE + Vector2i(1, -2))
	say_once("waves", "havel", "SIBYL is pushing a column down the avenues towards the gate.")
