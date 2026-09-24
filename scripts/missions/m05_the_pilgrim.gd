extends Mission
## Mission 5 — The Pilgrim. Trans-Saharan Railway, Niger, sunset to dusk.
## Signature mechanic: a moving boss base. The Pilgrim fortress-train runs
## south along the rail. Every car has a job (flak, artillery, troops, repair,
## command) and can be targeted on its own. Wrecking the engine stops it for
## 60 seconds (for good once the repair car is gone). Water stations are timed
## stops; capturing one denies the train fuel and troops and slows it by 20%.
## Blow a bridge on the eastern line and the train takes the western branch,
## right past your base.

const W := 100
const H := 104
const BASE := Vector2i(20, 44)
const TRUNK_A := [Vector2(60.5, -3), Vector2(60.5, 22.5)]
const EAST := [Vector2(60.5, 22.5), Vector2(68.5, 28.5), Vector2(76.5, 34.5), Vector2(76.5, 52.5), Vector2(66.5, 60.5), Vector2(58.5, 64.5)]
const WEST := [Vector2(60.5, 22.5), Vector2(50.5, 28.5), Vector2(40.5, 34.5), Vector2(40.5, 52.5), Vector2(50.5, 60.5), Vector2(58.5, 64.5)]
const TRUNK_B := [Vector2(58.5, 64.5), Vector2(58.5, 80.5), Vector2(56.5, 92.5), Vector2(56.5, 108)]
const STATIONS := [Vector2i(62, 11), Vector2i(60, 73), Vector2i(58, 86)]
const BRIDGES := [Vector2i(75, 39), Vector2i(75, 46)]
const RAVINE_Y := [40, 47]
const SPACING := 2.4
const ROLES := ["engine", "flak", "troop", "artillery", "flak", "repair", "flak", "command"]

var route: Array = []          # Vector2 points
var route_len: Array = []      # cumulative lengths
var branch := ""               # "" (undecided) | "east" | "west"
var head := 0.0
var state := "waiting"         # waiting | moving | station | wrecked | stopped
var state_t := 0.0
var cars: Array = []
var engine: TrainCar
var stations: Array = []
var station_d: Array = []
var next_station := 0
var bridges: Array = []
var codex := false
var ever_held := {}
var station_lost := false
var _repair_t := 0.0
var _check_t := 0.0
var _retake_t := 90.0
var _sun: DirectionalLight3D


func objective_preview() -> Array:
	return [
		["primary", "Stop the Pilgrim before it reaches the southern edge of the map."],
		["primary", "Board the command car with Engineers and recover the Lattice Codex."],
		["secondary", "Destroy the Pilgrim's three flak cars so your Kites can attack it."],
		["secondary", "Protect the water stations you capture (each one slows the train by 20%)."],
		["bonus", "Capture (rather than destroy) the Pilgrim's artillery car."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.25, 0.3, 0.5), "sky_horizon": Color(1.0, 0.55, 0.3),
		"ground_horizon": Color(0.7, 0.45, 0.3), "sun_rot": Vector3(-14, -60, 0),
		"sun_color": Color(1.0, 0.65, 0.4), "sun_energy": 1.3, "ambient": 0.65,
		"fog_color": Color(0.85, 0.55, 0.4), "fog_density": 0.004,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 5505, {
		"ground": Color(0.62, 0.47, 0.32), "rock": Color(0.45, 0.32, 0.22), "water": Color(0.08, 0.1, 0.12),
		"variation": 0.05,
	})
	map.scatter(MapGrid.Terrain.ROCK, 18, 1.2, 2.6, [[BASE, 12], [Vector2i(60, 12), 6], [Vector2i(76, 44), 12], [Vector2i(40, 44), 10], [Vector2i(58, 80), 12]])
	# ravines on the eastern side, crossed by the rail bridges
	for y in RAVINE_Y:
		map.line(Vector2i(66, y), Vector2i(98, y), 2.0, MapGrid.Terrain.WATER)
		map.fill_rect(Rect2i(64, y - 1, 2, 3), MapGrid.Terrain.ROCK)
	var rail := Color(0.28, 0.22, 0.18)
	for seg in [TRUNK_A, EAST, WEST, TRUNK_B]:
		var pts: Array = []
		for p in seg:
			pts.append(Vector2i(p))
		map.tint_polyline(pts, 1.3, rail)
		for i in range(pts.size() - 1):
			map.carve(pts[i], pts[i + 1], 3.0)
	for b in BRIDGES:
		for x in range(b.x, b.x + 3):
			for y in range(b.y, b.y + 3):
				if map.terrain_at(Vector2i(x, y)) == MapGrid.Terrain.WATER:
					map.set_terrain(Vector2i(x, y), MapGrid.Terrain.BRIDGE)
	map.crystal_field(Vector2i(14, 30), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(14, 60), 3.2, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(30, 76), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(86, 20), 3.0, MapGrid.Crystal.BLUE)
	for c in STATIONS + [Vector2i(40, 44), Vector2i(76, 30), Vector2i(76, 56), Vector2i(30, 76)]:
		map.carve(BASE, c, 3.0)
	map.clear_area(BASE, 9.0)


func setup() -> void:
	start_credits = 7000
	player().credits = 7000
	building("construction_yard", PLAYER, BASE - Vector2i(1, 1))
	building("power_plant", PLAYER, BASE + Vector2i(-5, -1))
	building("power_plant", PLAYER, BASE + Vector2i(-5, 3))
	building("refinery", PLAYER, BASE + Vector2i(3, -5))
	building("barracks", PLAYER, BASE + Vector2i(3, 2))
	building("war_factory", PLAYER, BASE + Vector2i(-1, 5))
	spawn(["engineer", "engineer", "engineer", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "medic"], PLAYER, BASE + Vector2i(7, 0))
	spawn(["tempest", "tempest", "warden", "warden", "apc"], PLAYER, BASE + Vector2i(8, -4))
	for c in STATIONS:
		var s := building("water_station", NEUTRAL, c, "station")
		stations.append(s)
	for b in BRIDGES:
		var br := building("bridge", NEUTRAL, b, "bridge")
		bridges.append(br)
	# Veil outriders on the eastern flats
	spawn(["raider", "raider", "scorpion", "rifleman", "rifleman"], ENEMY, Vector2i(84, 28))
	spawn(["raider", "scorpion", "rocket_trooper", "rifleman"], ENEMY, Vector2i(70, 70))
	spawn(["rifleman", "rifleman", "rocket_trooper"], ENEMY, Vector2i(66, 14))
	# the train
	_build_route("")
	for i in ROLES.size():
		var car := TrainCar.new()
		car.setup_car(ROLES[i], ENEMY)
		car.slot = i
		car.tags["train"] = true
		G.world.add_child(car)
		G.register(car)
		cars.append(car)
		if ROLES[i] == "engine":
			engine = car
	head = 0.0
	_place_cars()
	for i in STATIONS.size():
		station_d.append(_closest_d(cell_pos(STATIONS[i]) + Vector3(1, 0, 1)))
	for i in stations.size():
		add_marker("st%d" % i, stations[i].position, Color(0.4, 0.8, 1.0))
	for s in get_tree().current_scene.get_children():
		if s is DirectionalLight3D:
			_sun = s


func begin() -> void:
	add_objective("stop", "Stop the Pilgrim before it reaches the southern edge of the map.")
	add_objective("codex", "Board the command car (last car) with an Engineer and recover the Lattice Codex.")
	add_objective("flak", "Destroy the Pilgrim's three flak cars so your Kites can attack it (0/3).", "secondary")
	add_objective("stations", "Capture water stations with Engineers and protect them. Each one slows the train by 20%.", "secondary")
	obj("stations")["survive"] = true
	add_objective("artillery", "Capture the Pilgrim's artillery car with an Engineer.", "bonus")
	set_timer("depart", "Pilgrim departs in", 90.0)
	focus(BASE + Vector2i(6, 0))
	after(3.0, func(): say("havel", "The Pilgrim is ninety seconds out. Capture a water station before it gets there and it can't refuel or unload troops."))
	after(12.0, func(): say("havel", "If the eastern line loses a bridge, the train has to take the western branch, right past us. Wreck the engine and it stops for a minute. Kill the repair car and it won't get back up."))


# ================================================================ route

func _build_route(b: String) -> void:
	route = TRUNK_A.duplicate()
	var mid: Array = EAST if b != "west" else WEST
	for i in range(1, mid.size()):
		route.append(mid[i])
	for i in range(1, TRUNK_B.size()):
		route.append(TRUNK_B[i])
	route_len = [0.0]
	for i in range(1, route.size()):
		route_len.append(route_len[i - 1] + (route[i] as Vector2).distance_to(route[i - 1]))


func total_len() -> float:
	return route_len[route_len.size() - 1]


func _point_at(d: float) -> Array:
	d = clampf(d, 0.0, total_len())
	for i in range(1, route.size()):
		if d <= route_len[i]:
			var a: Vector2 = route[i - 1]
			var b: Vector2 = route[i]
			var k: float = (d - route_len[i - 1]) / maxf(route_len[i] - route_len[i - 1], 0.001)
			var p := a.lerp(b, k)
			var dir := (b - a).normalized()
			return [Vector3(p.x, 0, p.y), Vector3(dir.x, 0, dir.y)]
	var last: Vector2 = route[route.size() - 1]
	return [Vector3(last.x, 0, last.y), Vector3(0, 0, 1)]


func _closest_d(pos: Vector3) -> float:
	var best := 0.0
	var best_dist := INF
	var d := 0.0
	while d < total_len():
		var p: Vector3 = _point_at(d)[0]
		var dd := p.distance_to(pos)
		if dd < best_dist:
			best_dist = dd
			best = d
		d += 0.5
	return best


func _junction_d() -> float:
	return (TRUNK_A[1] as Vector2).distance_to(TRUNK_A[0])


func _place_cars() -> void:
	for c in cars:
		if is_instance_valid(c) and c.alive and c.attached:
			var pd: Array = _point_at(head - c.slot * SPACING)
			c.place(pd[0], pd[1])


# ================================================================ frame

func tick(delta: float) -> void:
	_dusk()
	_run_train(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.5
	_repair()
	_check_flak()
	_check_stations(0.5)
	var pct := int(clampf(head / total_len(), 0.0, 1.0) * 100.0)
	if state != "waiting":
		set_status("dist", "Pilgrim %d%% of the way%s" % [pct, "  (STOPPED)" if state == "stopped" else ("  (WRECKED)" if state == "wrecked" else "")])
	if player().count_of("construction_yard") == 0 and all_lost():
		lose("All forces lost.")


func speed() -> float:
	var held := 0
	for s in stations:
		if s.team == PLAYER:
			held += 1
	return 0.45 * pow(0.8, held)


func _run_train(delta: float) -> void:
	match state:
		"waiting":
			if time >= 90.0:
				state = "moving"
				clear_timer("depart")
				say("oriel", "Children of the glass: we ride home.")
				say("havel", "The Pilgrim is rolling. Here it comes.")
		"moving":
			var next_head := head + speed() * delta
			# the junction: east unless a bridge on the east line is gone
			if branch == "" and next_head >= _junction_d():
				var east_ok := true
				for br in bridges:
					if not (is_instance_valid(br) and br.alive):
						east_ok = false
				branch = "east" if east_ok else "west"
				_build_route(branch)
				if branch == "west":
					say("havel", "The Pilgrim switched to the western branch! It's coming right past the base.")
			# a blown bridge ahead stops the train for good
			if branch == "east":
				for i in bridges.size():
					if not (is_instance_valid(bridges[i]) and bridges[i].alive):
						var bd := _closest_d(cell_pos(BRIDGES[i]) + Vector3(1.5, 0, 1.5)) - 2.0
						if head < bd and next_head >= bd:
							next_head = bd
							_stop_for_good("The Pilgrim ran out of track at the broken bridge. It's stranded!")
			if state != "moving":
				return
			head = next_head
			if next_station < station_d.size() and head >= station_d[next_station]:
				var st: Structure = stations[next_station]
				if st.team == PLAYER:
					say("havel", "The Pilgrim is blowing straight through station %d. No fuel, no reinforcements." % (next_station + 1))
				else:
					state = "station"
					state_t = 20.0
					_drop_troops()
				next_station += 1
			if head - (cars.size() - 1) * SPACING >= total_len() - 1.0 or head >= total_len():
				lose("The Pilgrim reached the Veil temple with the Codex.")
			_place_cars()
		"station":
			state_t -= delta
			if state_t <= 0.0:
				state = "moving"
		"wrecked":
			state_t -= delta
			if state_t <= 0.0:
				if _car("repair") != null:
					engine.hp = engine.max_hp * 0.5
					state = "moving"
					say("havel", "Their repair crew got the engine running again!")
				else:
					_stop_for_good("The engine's dead and there's no repair car left to fix it. The Pilgrim is stopped!")


func _stop_for_good(line: String) -> void:
	if state == "stopped":
		return
	state = "stopped"
	say("havel", line)
	complete("stop")


func _car(role: String) -> TrainCar:
	for c in cars:
		if is_instance_valid(c) and c.alive and c.role == role and c.attached and c.team == ENEMY:
			return c
	return null


func _repair() -> void:
	var rc := _car("repair")
	if rc == null:
		return
	for c in cars:
		if is_instance_valid(c) and c.alive and c.attached and c.team == ENEMY:
			if c == engine and state == "wrecked":
				continue
			c.heal(c.max_hp * 0.008)


func _drop_troops() -> void:
	var tc := _car("troop")
	if tc == null:
		return
	var cell: Vector2i = G.map.world_to_cell(tc.position) + Vector2i(-3, 0)
	var goal := BASE
	var us := spawn(["rifleman", "rifleman", "rocket_trooper", "raider", "scorpion"], ENEMY, cell)
	attack_move(us, goal)
	say_once("drop", "havel", "The troop car is unloading at the station. Incoming!")


func on_damaged(e: Entity, _attacker: Entity) -> void:
	if e == engine and engine.hp <= 1.5 and state != "wrecked" and state != "stopped" and state != "waiting":
		state = "wrecked"
		state_t = 60.0
		Fx.explosion(engine.position + Vector3(0, 1, 0), 2.0)
		if _car("repair") != null:
			say("havel", "Engine wrecked! The train is dead in the water for a minute. Take out that repair car!")
		else:
			say("havel", "Engine wrecked, and there's no repair car to fix it.")


func can_interact(u: Unit, t: Entity) -> bool:
	if u.is_engineer() and t is TrainCar and t.team == ENEMY and (t.role == "command" or t.role == "artillery"):
		return true
	return super.can_interact(u, t)


func on_enter(u: Unit, t: Entity) -> bool:
	if t is TrainCar and u.team == PLAYER:
		if t.role == "command" and not codex:
			codex = true
			t.attached = false
			t.set_team(PLAYER)
			u.remove_silently()
			complete("codex")
			say("engineer", "We're in the command car! Drive's secured, Commander. We have the Lattice Codex.")
			return true
		if t.role == "artillery":
			t.attached = false
			t.set_team(PLAYER)
			u.remove_silently()
			complete("artillery")
			say("engineer", "Artillery car uncoupled and she's ours. One very large gun, parked on our side of the war.")
			return true
	if t.tags.has("station") and u.team == ENEMY and t.team == PLAYER:
		t.set_team(ENEMY)
		u.remove_silently()
		return true
	return false


func on_captured(s: Entity, _old: int, new_team: int) -> void:
	if s.tags.has("station") and new_team == PLAYER:
		ever_held[s] = true
		var i := stations.find(s)
		remove_marker("st%d" % i)
		say("havel", "Water station %d is ours. The Pilgrim won't refuel there, and it'll run twenty percent slower." % (i + 1))


func _check_stations(dt: float) -> void:
	for s in stations:
		if ever_held.has(s) and s.team != PLAYER and not station_lost:
			station_lost = true
			fail("stations")
			say("havel", "We lost a water station to a Veil team.")
	if ever_held.is_empty():
		return
	_retake_t -= dt
	if _retake_t <= 0.0:
		_retake_t = 100.0
		for s in stations:
			if s.team == PLAYER:
				var us := spawn(["raider", "rifleman", "rifleman", "engineer"], ENEMY, G.map.world_to_cell(s.position) + Vector2i(14, randi_range(-4, 4)))
				for u in us:
					u.tags["scripted"] = true
					if u.def_id == "engineer":
						u.cmd_enter(s)
					else:
						u.cmd_attack_move(G.map.world_to_cell(s.position))
				say_once("retake", "havel", "A Veil squad with an engineer is going for one of our water stations.")
				break


func _check_flak() -> void:
	var dead := 0
	for i in cars.size():
		if ROLES[i] == "flak" and not (is_instance_valid(cars[i]) and cars[i].alive):
			dead += 1
	set_text("flak", "Destroy the Pilgrim's three flak cars so your Kites can attack it (%d/3)." % dead)
	if dead >= 3 and is_active("flak"):
		complete("flak")
		say("havel", "All three flak cars are scrap. The sky over that train is ours.")


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e is TrainCar and e.role == "command" and not codex:
		lose("The command car was destroyed, and the Lattice Codex with it.")
	if e is TrainCar and e.role == "repair":
		say("havel", "Repair car destroyed. Nothing's patching that train now.")
		if state == "wrecked":
			state_t = minf(state_t, 1.0)
	if e.tags.has("bridge") and branch == "":
		say("havel", "Bridge down! The Pilgrim will have to take the western branch.")


func _dusk() -> void:
	if _sun == null:
		return
	var k := clampf(time / 900.0, 0.0, 1.0)
	_sun.light_energy = lerpf(1.3, 0.35, k)
	_sun.light_color = Color(1.0, 0.65, 0.4).lerp(Color(0.55, 0.45, 0.8), k)
	_sun.rotation_degrees.x = lerpf(-14.0, -4.0, k)

