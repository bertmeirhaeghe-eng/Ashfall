extends Mission
## Mission 4 — Salt and Thunder. Wadi Kharim, Algeria, scorching midday.
## Signature mechanic: you choose when the map changes. Capture the Kharim Dam,
## plant charges on its three pillars, then press BLOW THE DAM: the river fills
## the valley over 30 seconds, sweeps away ground units in the riverbed and
## leaves the Veil artillery stranded on islands. Afterwards only hover units,
## amphibious APCs and aircraft can cross.

const W := 112
const H := 84
const BASE := Vector2i(18, 40)
const DAM_CTRL := Vector2i(38, 6)
const PILLARS := [Vector2i(48, 7), Vector2i(55, 7), Vector2i(62, 7)]
const NOMADS := Vector2i(58, 50)
const EVAC := Vector2i(30, 50)
const RIVER := [Vector2i(55, 8), Vector2i(57, 28), Vector2i(52, 48), Vector2i(58, 68), Vector2i(56, 83)]
const ISLANDS := [Vector2i(56, 27), Vector2i(55, 60)]
const ARM_TIME := 8.0

var riverbed := {}           # Vector2i -> true (cells that flood)
var ctrl: Structure
var pillars: Array = []
var charge := {}             # pillar -> 0 none / time armed-at (float) / -1 armed
var flooded := false
var flood_t := -1.0
var nomads_saved := 0
var nomads_lost := 0
var retaken_t := -1.0
var _wave_t := 0.0
var _check_t := 0.0
var _pullback := false


func objective_preview() -> Array:
	return [
		["primary", "Build a base on the plateau and capture the Kharim Dam control building with an Engineer."],
		["primary", "Plant demolition charges on the dam's three support pillars."],
		["primary", "Destroy all Veil forces in the valley."],
		["secondary", "Keep the dam control building until the charges are ready."],
		["bonus", "Evacuate the nomad camp in the riverbed before the flood."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.28, 0.4, 0.58), "sky_horizon": Color(0.7, 0.6, 0.45),
		"ground_horizon": Color(0.5, 0.42, 0.3), "sun_rot": Vector3(-72, 40, 0),
		"sun_color": Color(1.0, 0.93, 0.8), "sun_energy": 1.1, "ambient": 0.35,
		"fog_color": Color(0.75, 0.65, 0.5), "fog_density": 0.002, "exposure": 0.9,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 4404, {
		"ground": Color(0.44, 0.35, 0.24), "rock": Color(0.36, 0.27, 0.19), "water": Color(0.12, 0.35, 0.42),
		"variation": 0.04, "hills": 1.0,
	})
	map.scatter(MapGrid.Terrain.ROCK, 16, 1.2, 2.6, [[BASE, 12], [DAM_CTRL, 5], [NOMADS, 6], [EVAC, 4], [Vector2i(56, 40), 14]])
	# the dry riverbed
	for i in range(RIVER.size() - 1):
		var a: Vector2i = RIVER[i]
		var b: Vector2i = RIVER[i + 1]
		var steps := int(Vector2(a).distance_to(Vector2(b)) * 2.0) + 1
		for k in steps + 1:
			var q := Vector2(a).lerp(Vector2(b), float(k) / steps)
			for x in range(int(q.x) - 8, int(q.x) + 9):
				for y in range(int(q.y) - 2, int(q.y) + 3):
					var c := Vector2i(x, y)
					if map.in_bounds(c) and Vector2(x, y).distance_to(q) <= 7.0 and y >= 8 and y < H - 1:
						riverbed[c] = true
	for isl in ISLANDS:
		for x in range(isl.x - 4, isl.x + 5):
			for y in range(isl.y - 4, isl.y + 5):
				if Vector2(x - isl.x, y - isl.y).length() <= 3.3:
					riverbed.erase(Vector2i(x, y))
	for c in riverbed.keys():
		map.set_terrain(c, MapGrid.Terrain.GROUND)
		map.mark_low(c)
		map.tints[c] = Color(0.4, 0.33, 0.23)
	for isl in ISLANDS:
		map.tint_blob(isl, 3.2, Color(0.56, 0.46, 0.32))
	# reservoir and dam wall
	map.fill_rect(Rect2i(36, 1, 40, 5), MapGrid.Terrain.WATER)
	map.fill_rect(Rect2i(44, 6, 22, 2), MapGrid.Terrain.ROCK)
	map.tint_line(Vector2i(42, 7), Vector2i(66, 7), 2.2, Color(0.6, 0.58, 0.52))
	# roads
	map.tint_polyline([BASE, Vector2i(30, 20), DAM_CTRL], 2.0, Color(0.55, 0.45, 0.33))
	map.tint_polyline([BASE, EVAC], 2.0, Color(0.55, 0.45, 0.33))
	# crystal: plateau (safe), riverbed (will flood), east bank (cut off after the flood)
	map.crystal_field(Vector2i(14, 26), 3.2, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(20, 62), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(50, 38), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(84, 62), 3.6, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(80, 22), 3.0, MapGrid.Crystal.GREEN)
	for c in [DAM_CTRL, EVAC, Vector2i(52, 40), Vector2i(80, 40), Vector2i(84, 62)]:
		map.carve(BASE, c, 3.0)
	map.carve(Vector2i(60, 40), Vector2i(100, 40), 3.0)
	map.clear_area(BASE, 9.0)


func setup() -> void:
	start_credits = 6000
	player().credits = 6000
	spawn_one("mcv", PLAYER, BASE)
	spawn(["rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "engineer", "engineer", "medic"], PLAYER, BASE + Vector2i(4, 4))
	spawn(["tempest", "tempest", "warden", "scout_mech"], PLAYER, BASE + Vector2i(5, -3))
	ctrl = building("dam_control", NEUTRAL, DAM_CTRL, "ctrl")
	for c in PILLARS:
		var p := building("dam_pillar", NEUTRAL, c, "pillar")
		pillars.append(p)
		charge[p] = 0.0
	# the Veil in the valley
	for isl in ISLANDS:
		building("artillery_nest", ENEMY, isl - Vector2i(1, 1), "valley")
		spawn(["rifleman", "rocket_trooper"], ENEMY, isl + Vector2i(2, 0), "valley")
	building("artillery_nest", ENEMY, Vector2i(72, 20), "valley")
	building("artillery_nest", ENEMY, Vector2i(74, 46), "valley")
	building("artillery_nest", ENEMY, Vector2i(40, 64), "valley")
	building("guard_tower", ENEMY, Vector2i(70, 30), "valley")
	building("guard_tower", ENEMY, Vector2i(66, 56), "valley")
	for c in [Vector2i(54, 18), Vector2i(52, 36), Vector2i(56, 46), Vector2i(58, 70)]:
		for u in spawn(["scorpion", "rifleman", "rifleman", "raider"], ENEMY, c, "valley"):
			u.tags["garrison"] = true
	spawn(["veil_artillery", "veil_artillery"], ENEMY, Vector2i(76, 36), "valley")
	# the nomad camp
	for off in [Vector2i(-2, -2), Vector2i(2, -1), Vector2i(-1, 2), Vector2i(3, 2)]:
		building("tent_civ", NEUTRAL, NOMADS + off)
	for i in 20:
		var cv := spawn_one("civilian", NEUTRAL, NOMADS + Vector2i(randi_range(-3, 3), randi_range(-3, 3)), "nomad")
		cv.hold_position = true
	add_marker("ctrl", ctrl.position, Color(0.4, 0.8, 1.0))
	add_marker("nomads", cell_pos(NOMADS), Color(1.0, 0.85, 0.3))


func begin() -> void:
	add_objective("base", "Build a base on the plateau (deploy the MCV) and capture the Kharim Dam control building with an Engineer.")
	add_objective("charges", "Plant demolition charges on the dam's three support pillars with Engineers (0/3).")
	add_objective("valley", "Destroy all Veil forces in the valley.")
	add_objective("hold", "Keep the dam control building until the charges are ready.", "secondary")
	add_objective("nomads", "Evacuate the nomad camp in the riverbed before the flood (0/20 safe).", "bonus")
	focus(BASE + Vector2i(4, 0))
	after(3.0, func(): say("rourke", "Deploy on the plateau, Commander. Their artillery covers the riverbed, so don't go strolling down there."))
	after(11.0, func(): say("havel", "There's a nomad camp in the riverbed, right in the flood path. Twenty people. If you can spare the time, get them up to the plateau."))


# ================================================================ frame

func tick(delta: float) -> void:
	if flood_t >= 0.0 and not flooded:
		_flood(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	_check_base()
	_check_charges()
	_check_nomads()
	_check_valley()
	_counterattack(0.4)
	if player().count_of("construction_yard") == 0 and is_done("base"):
		lose("Your Construction Yard was destroyed.")
	elif all_lost():
		lose("All forces lost.")


func _check_base() -> void:
	if is_done("base"):
		return
	var has_base := player().count_of("construction_yard") > 0
	var has_dam: bool = ctrl.team == PLAYER
	if has_base and has_dam:
		complete("base")
		remove_marker("ctrl")
		for i in pillars.size():
			add_marker("pillar%d" % i, pillars[i].position, Color(1.0, 0.6, 0.2))
		say("rourke", "The dam is ours. Now the charges: one on each of the three pillars. Engineers only.")
		say("havel", "The Veil can see what we're doing. Expect a counter-attack on the control building.")


func can_interact(u: Unit, t: Entity) -> bool:
	if u.is_engineer() and t.tags.has("pillar") and ctrl.team == PLAYER and float(charge.get(t, 0.0)) == 0.0:
		return true
	return super.can_interact(u, t)


func on_enter(u: Unit, t: Entity) -> bool:
	if t.tags.has("pillar"):
		if ctrl.team != PLAYER:
			G.notify(PLAYER, "Capture the dam control building first.")
			return true
		if float(charge.get(t, 0.0)) == 0.0:
			charge[t] = time + ARM_TIME
			u.hold_position = true
			u.set_meta("planting", t)
			G.notify(PLAYER, "Planting charge...")
		return true
	if t == ctrl and u.team == ENEMY and ctrl.team == PLAYER:
		ctrl.set_team(ENEMY)
		u.remove_silently()
		_retaken()
		return true
	return false


func on_captured(s: Entity, _old: int, new_team: int) -> void:
	if s == ctrl and new_team == PLAYER:
		if retaken_t >= 0.0:
			retaken_t = -1.0
			clear_timer("disarm")
			say("havel", "Control building back in our hands. Re-plant those charges, fast.")
		_wave_t = minf(_wave_t, 20.0)


func _retaken() -> void:
	for p in pillars:
		charge[p] = 0.0
	_update_charge_text()
	if is_active("hold") and not all_armed():
		fail("hold")
	retaken_t = time
	set_timer("disarm", "Veil disarming the dam", 45.0)
	G.hud.remove_special("blow")
	say("havel", "The Veil retook the control building! They're pulling our charges. Get an Engineer back in there!")


func all_armed() -> bool:
	for p in pillars:
		if float(charge[p]) != -1.0:
			return false
	return true


func _check_charges() -> void:
	if flood_t >= 0.0:
		return
	if retaken_t >= 0.0 and time - retaken_t > 45.0 and ctrl.team != PLAYER:
		lose("The Veil retook the dam and disarmed the charges.")
		return
	for i in pillars.size():
		var p: Structure = pillars[i]
		var c := float(charge[p])
		if c > 0.0:
			# the engineer must stay next to the pillar until the charge is armed
			var planter_ok := false
			for u in team_units(PLAYER):
				if u.has_meta("planting") and u.get_meta("planting") == p and G.flat_dist(u.position, p.position) < 2.5:
					planter_ok = true
			if not planter_ok:
				charge[p] = 0.0
				G.notify(PLAYER, "Charge planting interrupted.")
			elif time >= c:
				charge[p] = -1.0
				remove_marker("pillar%d" % i)
				for u in team_units(PLAYER):
					if u.has_meta("planting") and u.get_meta("planting") == p:
						u.remove_meta("planting")
						u.hold_position = false
				G.notify(PLAYER, "Charge armed on pillar %d." % (i + 1), true)
	_update_charge_text()
	if all_armed() and not flooded and flood_t < 0.0:
		if is_active("charges"):
			complete("charges")
			if is_active("hold"):
				complete("hold")
			say("rourke", "All three charges are live. The button is yours, Commander. Choose your moment.")
			_pullback_timer()
		G.hud.add_special("blow", "BLOW THE DAM")


func _update_charge_text() -> void:
	var n := 0
	for p in pillars:
		if float(charge[p]) == -1.0:
			n += 1
	if is_active("charges"):
		set_text("charges", "Plant demolition charges on the dam's three support pillars with Engineers (%d/3)." % n)


func _pullback_timer() -> void:
	after(60.0, func():
		if flooded or flood_t >= 0.0:
			return
		_pullback = true
		say("havel", "The riverbed garrison is pulling back to the high ground. They've worked out what the charges are for.")
		for u in tagged("garrison"):
			u.cmd_move(Vector2i(80, clampi(G.map.world_to_cell(u.position).y, 10, 74))))


func special_action(id: String) -> void:
	if id == "blow" and all_armed() and flood_t < 0.0:
		G.hud.remove_special("blow")
		flood_t = 0.0
		clear_timer("disarm")
		for i in 6:
			Fx.explosion(pillars[i % 3].position + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), 2.5)
		for p in pillars:
			p.invulnerable = false
			p.die(null)
		for x in range(44, 66):
			G.map.set_terrain(Vector2i(x, 6), MapGrid.Terrain.WATER)
			G.map.set_terrain(Vector2i(x, 7), MapGrid.Terrain.WATER)
		G.map.rebuild_static()
		say("rourke", "Let the river do the work.")
		if is_active("nomads"):
			var left := tagged("nomad").filter(func(c): return riverbed.has(G.map.world_to_cell(c.position)))
			if nomads_saved >= 15 and left.is_empty():
				_nomads_done()
			else:
				fail("nomads")
		set_timer("flood", "Flood", 30.0)


func _flood(delta: float) -> void:
	flood_t += delta
	var yf := 8.0 + (H - 8.0) * clampf(flood_t / 30.0, 0.0, 1.0)
	var swept := 0
	for c in riverbed.keys():
		if c.y <= yf and G.map.terrain_at(c) != MapGrid.Terrain.WATER:
			G.map.set_terrain(c, MapGrid.Terrain.WATER)
	for e in G.entities.duplicate():
		if not e.alive:
			continue
		var c: Vector2i = G.map.world_to_cell(e.position)
		if not riverbed.has(c) or c.y > yf:
			continue
		if e is Unit and (e.move_class == "hover" or e.is_air or (e.move_class == "jump" and e.is_moving())):
			continue
		if e is Structure and e.def.get("no_footprint", false):
			continue
		e.invulnerable = false
		e.die(null)
		swept += 1
	if swept > 0 and once("swept_line"):
		say("havel", "The water's hit the riverbed. Anything down there is being swept away!")
	if flood_t >= 30.0:
		flooded = true
		clear_timer("flood")
		say("rourke", "The valley is a lake. Their artillery is stranded on islands. Hovers, APCs and Kites only from here. Finish them.")
		say("havel", "Our harvesters can't reach the lower fields any more. Watch your credits.")


func _check_nomads() -> void:
	if not is_active("nomads"):
		return
	for cv in tagged("nomad"):
		if cv.team == NEUTRAL and team_near(cv.position, PLAYER, 6.0):
			for o in tagged("nomad"):
				if o.team == NEUTRAL and G.flat_dist(o.position, cv.position) < 8.0:
					o.set_team(PLAYER)
					o.hold_position = false
					o.cmd_move(EVAC + Vector2i(randi_range(-2, 2), randi_range(-2, 2)))
			say_once("nomad_line", "civilian", "Soldiers! You say the river is coming back? We're going, we're going!")
		elif cv.team == PLAYER:
			if G.flat_dist(cv.position, cell_pos(EVAC)) < 4.0:
				nomads_saved += 1
				cv.remove_silently()
			elif cv.order == Unit.Order.IDLE:
				cv.cmd_move(EVAC)
	set_text("nomads", "Evacuate the nomad camp in the riverbed before the flood (%d/20 safe)." % nomads_saved)
	if nomads_saved + nomads_lost >= 20 and nomads_saved >= 15:
		_nomads_done()


func _nomads_done() -> void:
	if not is_active("nomads"):
		return
	complete("nomads")
	remove_marker("nomads")
	spawn(["tempest", "tempest", "tempest"], PLAYER, BASE + Vector2i(6, 6))
	say("rourke", "Twenty civilians, safe. The quartermaster has sent you a Tempest squad for your trouble.")


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("nomad"):
		nomads_lost += 1


## Once the dam is ours, the Veil throws waves up the riverbed at it.
func _counterattack(dt: float) -> void:
	if not is_done("base") or flooded:
		return
	_wave_t -= dt
	if _wave_t > 0.0:
		return
	_wave_t = 50.0
	var wave := ["scorpion", "scorpion", "raider", "rifleman", "rifleman", "rocket_trooper"]
	if ctrl.team == PLAYER:
		wave.append("engineer")
	var us := spawn(wave, ENEMY, Vector2i(56, H - 4), "valley")
	for u in us:
		u.tags["scripted"] = true
		if u.def_id == "engineer":
			u.cmd_enter(ctrl)
		else:
			u.cmd_attack_move(DAM_CTRL + Vector2i(4, 4))
	send_wave(["raider", "raider", "rifleman"], ENEMY, Vector2i(W - 4, 40), DAM_CTRL + Vector2i(6, 6), "valley")
	say_once("counter", "havel", "Here comes the counter-attack, straight up the riverbed.")


func _check_valley() -> void:
	if not is_active("valley"):
		return
	for e in G.entities:
		if e.alive and e.team == ENEMY and (e.tags.has("valley") or (e.position.x > 36 and e.position.x < 90)):
			return
	complete("valley")
	say("rourke", "Valley's clear. Good. Now we go hunting for that train.")


func harvest_cell_ok(c: Vector2i) -> bool:
	return not (flooded and c.x > 40)


func placement_override(team: int, _id: String, cell: Vector2i) -> int:
	if team == PLAYER and riverbed.has(cell):
		return 0
	return -1
