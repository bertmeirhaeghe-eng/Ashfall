extends Mission
## Mission 9 — Dead Man's Switch. Halo Lance Control Station "Aurora",
## Ural Mountains, blizzard at pale dawn.
## Signature mechanic: fighting your own army and your own superweapon.
## Rourke fields everything Bastion has, the Halo Lance fires at your base every
## four minutes (reticle 20 seconds early), and a 40:00 salvo countdown is
## always on screen. Destroying a power relay adds 5:00. Inflatable Decoy
## Structures bait the Lance. The blizzard hides enemy units beyond sight range.

const W := 112
const H := 100
const BASE := Vector2i(56, 88)
const CORE := Vector2i(54, 8)
const BUNKER := Vector2i(80, 10)
const HQ_A := Vector2i(26, 20)
const HQ_B := Vector2i(84, 30)
const RELAYS := [Vector2i(18, 32), Vector2i(54, 36), Vector2i(94, 22)]
const ENTRANCE := Vector2i(56, 54)
const SIGHT := 10.0
const ROURKE_ORANGE := Color(1.0, 0.5, 0.12)

var core: Structure
var bunker: Structure
var salvo_left := 2400.0
var lance_t := 240.0
var lance_strike: LanceStrike = null
var arrested := false
var captured_core := false
var _check_t := 0.0
var _fog_t := 0.0
var _brigade_flip := 0


func objective_preview() -> Array:
	return [
		["primary", "Break into the control station's fortified valley."],
		["primary", "Capture the Lance Control Core with an Engineer before the salvo counter reaches zero (40:00)."],
		["primary", "Destroy the three Lance power relays to buy time. Each one adds 5 minutes."],
		["secondary", "Arrest Colonel Rourke: capture his command bunker with infantry instead of destroying it."],
		["bonus", "Capture one brigade's field HQ intact so its units stand down and join you."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.55, 0.6, 0.68), "sky_horizon": Color(0.85, 0.87, 0.9),
		"ground_horizon": Color(0.8, 0.82, 0.86), "sun_rot": Vector3(-18, -120, 0),
		"sun_color": Color(0.9, 0.93, 1.0), "sun_energy": 0.8, "ambient": 0.9,
		"fog_color": Color(0.85, 0.88, 0.93), "fog_density": 0.025, "weather": "snow",
	}


func setup_players() -> void:
	super.setup_players()
	var r: PlayerState = G.players[ENEMY]
	r.faction = "bastion"
	r.color = ROURKE_ORANGE
	r.display = "Rourke's Brigades"


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 9909, {
		"ground": Color(0.8, 0.82, 0.85), "rock": Color(0.45, 0.47, 0.5), "variation": 0.04,
		"forest": Color(0.55, 0.6, 0.6), "tree": Color(0.15, 0.25, 0.2),
	})
	# the station valley walls, with a fortified main entrance and a narrow western pass
	map.polyline([Vector2i(1, 56), Vector2i(30, 52), Vector2i(50, 56)], 4.0, MapGrid.Terrain.ROCK, 0.8)
	map.polyline([Vector2i(62, 56), Vector2i(84, 50), Vector2i(110, 54)], 4.0, MapGrid.Terrain.ROCK, 0.8)
	map.carve(Vector2i(12, 60), Vector2i(14, 46), 2.0)
	map.scatter(MapGrid.Terrain.ROCK, 14, 1.2, 2.6, [[BASE, 14], [CORE, 7], [BUNKER, 6], [HQ_A, 6], [HQ_B, 6], [ENTRANCE, 7], [RELAYS[0], 4], [RELAYS[1], 4], [RELAYS[2], 4]])
	for i in 8:
		map.blob(Vector2i(map.rng.randi_range(4, W - 5), map.rng.randi_range(60, H - 5)), 2.2, MapGrid.Terrain.FOREST)
	map.clear_area(BASE, 10.0)
	map.clear_area(ENTRANCE, 4.0)
	for c in [CORE, BUNKER, HQ_A, HQ_B] + RELAYS:
		map.carve(ENTRANCE, c, 3.0)
	map.carve(BASE, ENTRANCE, 4.0)
	map.tint_polyline([BASE, ENTRANCE, Vector2i(56, 36), CORE], 2.5, Color(0.6, 0.62, 0.66))
	map.crystal_field(Vector2i(34, 80), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(82, 82), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(56, 66), 3.0, MapGrid.Crystal.BLUE)
	map.crystal_field(Vector2i(40, 30), 3.0, MapGrid.Crystal.GREEN)
	for c in [Vector2i(34, 80), Vector2i(82, 82)]:
		map.carve(BASE, c, 3.0)


func setup() -> void:
	start_credits = 10000
	player().credits = 10000
	building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	building("power_plant", PLAYER, BASE + Vector2i(-7, -1))
	building("power_plant", PLAYER, BASE + Vector2i(-7, 3))
	building("power_plant", PLAYER, BASE + Vector2i(8, 3))
	building("refinery", PLAYER, BASE + Vector2i(-12, -4))
	building("barracks", PLAYER, BASE + Vector2i(4, -3))
	building("war_factory", PLAYER, BASE + Vector2i(4, 2))
	building("radar", PLAYER, BASE + Vector2i(-3, 4))
	building("veil_foundry", PLAYER, BASE + Vector2i(-13, 2))
	spawn(["warden", "warden", "warden", "resonator", "resonator", "tempest", "tempest"], PLAYER, BASE + Vector2i(0, -9))
	spawn(["rifleman", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "skyjumper", "skyjumper", "medic"], PLAYER, BASE + Vector2i(-6, -9))
	spawn(["engineer", "engineer", "engineer", "engineer"], PLAYER, BASE + Vector2i(6, -8))
	# Rourke's station
	core = building("lance_control", ENEMY, CORE, "core")
	bunker = building("command_bunker", ENEMY, BUNKER, "bunker")
	building("construction_yard", ENEMY, Vector2i(62, 16), "station")
	building("war_factory", ENEMY, Vector2i(44, 16), "station")
	building("barracks", ENEMY, Vector2i(68, 22), "station")
	building("power_plant", ENEMY, Vector2i(38, 10), "station")
	building("power_plant", ENEMY, Vector2i(70, 6), "station")
	building("refinery", ENEMY, Vector2i(36, 26), "station")
	building("radar", ENEMY, Vector2i(48, 24), "station")
	var hqa := building("brigade_hq", ENEMY, HQ_A, "hq")
	hqa.tags["brigade"] = "a"
	var hqb := building("brigade_hq", ENEMY, HQ_B, "hq")
	hqb.tags["brigade"] = "b"
	for i in RELAYS.size():
		building("lance_relay", ENEMY, RELAYS[i], "relay")
	# the fortified entrance
	building("guard_tower", ENEMY, ENTRANCE + Vector2i(-5, -3), "valley_gate")
	building("guard_tower", ENEMY, ENTRANCE + Vector2i(5, -3), "valley_gate")
	building("guard_tower", ENEMY, ENTRANCE + Vector2i(-2, -6), "valley_gate")
	building("guard_tower", ENEMY, ENTRANCE + Vector2i(3, -6), "valley_gate")
	building("guard_tower", ENEMY, Vector2i(14, 42), "valley_gate")
	# two brigades
	for u in spawn(["warden", "warden", "resonator", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper"], ENEMY, HQ_A + Vector2i(4, 6)):
		u.tags["brigade"] = "a"
	for u in spawn(["warden", "bulwark", "tempest", "tempest", "rifleman", "rifleman", "rocket_trooper"], ENEMY, HQ_B + Vector2i(-4, 6)):
		u.tags["brigade"] = "b"
	for u in spawn(["warden", "warden", "rocket_trooper", "rocket_trooper"], ENEMY, ENTRANCE + Vector2i(0, -9)):
		u.tags["brigade"] = "a"
	enemy().credits = 5000
	add_ai(enemy(), Vector2i(56, 18), BASE, {"first_attack": 210.0, "wave_interval": 90.0, "wave_size": 6, "wave_max": 14,
		"income": 10.0, "units": ["rifleman", "rocket_trooper", "warden", "resonator", "tempest", "scout_mech"],
		"build_order": ["power_plant", "guard_tower", "power_plant", "guard_tower", "barracks", "guard_tower"]})
	add_marker("core", core.position, Color(0.4, 0.8, 1.0))
	add_marker("bunker", bunker.position, Color(1.0, 0.85, 0.3))


func begin() -> void:
	add_objective("valley", "Break into the control station's fortified valley (destroy the entrance defenses).")
	add_objective("core", "Capture the Lance Control Core with an Engineer before the salvo counter reaches zero.")
	add_objective("relays", "Destroy the three Lance power relays to buy time. Each one adds 5 minutes (0/3).")
	add_objective("rourke", "Arrest Colonel Rourke: capture his command bunker with infantry instead of destroying it.", "secondary")
	add_objective("brigade", "Capture one brigade's field HQ intact with an Engineer so its units stand down and join you.", "bonus")
	set_timer("salvo", "SALVO", salvo_left)
	set_timer("lance", "Next Lance strike", lance_t)
	focus(BASE + Vector2i(0, -8))
	after(3.0, func(): say("havel", "The blizzard's killing our sensors, Commander. You'll only see his units when you're close. Scout ahead."))
	after(12.0, func(): say("havel", "The Lance will hit us every four minutes. The reticle shows twenty seconds early. Inflatable Decoys on the Base tab will draw its fire, or keep the army moving."))
	after(30.0, func(): say("rourke", "I taught you everything you're about to try, Commander."))


# ================================================================ frame

func tick(delta: float) -> void:
	if not captured_core:
		salvo_left -= delta
		set_timer("salvo", "SALVO", salvo_left)
		if salvo_left <= 0.0:
			lose("The salvo counter reached zero. Every Halo Lance satellite fired at the crater, and the Seed woke.")
			return
		_lance(delta)
	_fog_t -= delta
	if _fog_t <= 0.0:
		_fog_t = 0.3
		_blizzard()
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	if is_active("valley") and count_tagged("valley_gate") == 0:
		complete("valley")
		say("okafor", "You're inside the valley. The Control Core is at the north end. Get an Engineer to it.")
	var relays_left := count_tagged("relay")
	if is_active("relays"):
		set_text("relays", "Destroy the three Lance power relays to buy time. Each one adds 5 minutes (%d/3)." % (3 - relays_left))
		if relays_left == 0:
			complete("relays")
	if player().count_of("construction_yard") == 0:
		lose("Your Construction Yard was destroyed.")


## Enemy units are hidden by the blizzard unless one of ours is close.
func _blizzard() -> void:
	var ours: Array = []
	for e in G.entities:
		if e.alive and e.team == PLAYER:
			ours.append(e.position)
	for e in G.entities:
		if not e.alive or e.team != ENEMY or not (e is Unit):
			continue
		var seen := false
		for p in ours:
			if Vector2(p.x - e.position.x, p.z - e.position.z).length() <= SIGHT:
				seen = true
				break
		if e.force_hidden == seen:
			e.force_hidden = not seen
			e.detected_mask = -2


func _lance(delta: float) -> void:
	if lance_strike != null:
		return
	lance_t -= delta
	set_timer("lance", "Next Lance strike", maxf(lance_t, 0.0))
	if lance_t > 20.0:
		return
	lance_t = 240.0
	var pos := _lance_target()
	lance_strike = LanceStrike.fire(pos, 20.0, 3.5, 1200.0)
	lance_strike.struck.connect(func(_p): lance_strike = null)
	say("havel", "Lance reticle on the ground! Twenty seconds! Move!")
	if once("rourke_lance"):
		say("rourke", "You know how this works, Commander. You've called it down yourself.")


func _lance_target() -> Vector3:
	var decoys := player().structures().filter(func(s): return s.def.get("decoy", false))
	if not decoys.is_empty() and randf() < 0.85:
		return decoys[randi() % decoys.size()].position
	var best := cell_pos(BASE)
	var best_n := -1.0
	var mine := player().structures() + player().units()
	for a in mine:
		var n := 0.0
		for b in mine:
			if G.flat_dist(a.position, b.position) <= 4.0:
				n += 2.0 if b is Structure else 1.0
				if b.def_id == "construction_yard":
					n += 2.0
		if n > best_n:
			best_n = n
			best = a.position
	return best


# ================================================================ interactions

func can_interact(u: Unit, t: Entity) -> bool:
	if t == bunker and t.team == ENEMY and u.is_infantry and not u.def.get("hero", false):
		return true
	return super.can_interact(u, t)


func on_enter(u: Unit, t: Entity) -> bool:
	if t == bunker and u.team == PLAYER and bunker.team == ENEMY:
		arrested = true
		bunker.set_team(PLAYER)
		u.remove_silently()
		remove_marker("bunker")
		complete("rourke")
		pending_flags["rourke_arrested"] = true
		say("havel", "We're in the bunker. Colonel Rourke is in custody.")
		return true
	return false


func on_captured(s: Entity, _old: int, new_team: int) -> void:
	if new_team != PLAYER:
		return
	if s == core:
		_core_taken()
	elif s.tags.has("hq"):
		var b: String = s.tags["brigade"]
		var n := 0
		for u in G.entities.duplicate():
			if u is Unit and u.alive and u.team == ENEMY and u.tags.get("brigade", "") == b:
				u.set_team(PLAYER)
				n += 1
		if is_active("brigade"):
			complete("brigade")
		say("okafor", "Brigade %s's HQ is ours. Their commander just ordered %d units to stand down and report to you." % [b.to_upper(), n])


func on_unit_built(u: Unit) -> void:
	if u.team == ENEMY:
		_brigade_flip += 1
		u.tags["brigade"] = "a" if _brigade_flip % 2 == 0 else "b"


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("relay"):
		salvo_left += 300.0
		set_timer("salvo", "SALVO", salvo_left)
		say("havel", "Relay destroyed! That's five more minutes on the salvo clock.")
	if e == bunker and not arrested:
		fail("rourke")
		remove_marker("bunker")
		say("havel", "The command bunker is down. No word from Rourke.")


func _core_taken() -> void:
	if captured_core:
		return
	captured_core = true
	auto_win = false
	clear_timer("salvo")
	clear_timer("lance")
	remove_marker("core")
	complete("core")
	if is_active("relays"):
		complete("relays")
	if is_active("valley"):
		complete("valley")
	say("okafor", "The Control Core is ours. Salvo aborted. The Lance is silent.")
	if arrested:
		say("narrator", "Colonel Rourke is marched past the Commander in the snow. He stops, just for a moment.")
		say("rourke", "You'll see I was right.")
	else:
		if is_instance_valid(bunker) and bunker.alive:
			if is_active("rourke"):
				fail("rourke")
			bunker.invulnerable = false
			bunker.die(null)
		say("havel", "We found Colonel Rourke in the ruins of his bunker. He was still holding the firing key. He never used it.")
	# his brigades stand down
	for u in G.entities.duplicate():
		if u is Unit and u.alive and u.team == ENEMY:
			u.cmd_stop()
	enemy().defeated = true
	for ai in _ai:
		ai.enabled = false
	after(8.0, func(): auto_win = true)
