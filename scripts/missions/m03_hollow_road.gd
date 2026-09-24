extends Mission
## Mission 3 — The Hollow Road. Black Forest crystal wastes, overcast afternoon.
## Signature mechanic: the environment as a weapon. No base, ~15 units.
## Crystal hurts Bastion troops but heals Tallow's Outcasts; three Maws grab
## anything on their veins (shoot them to agitate them); blossom trees burst
## into spore clouds when shot.

const W := 112
const H := 72
const START := Vector2i(6, 40)
const VILLAGE := Vector2i(40, 12)
const ROUTE_WP := [Vector2i(10, 40), Vector2i(24, 34), Vector2i(36, 44), Vector2i(52, 38), Vector2i(64, 40)]
const CONVOY_PATH := [Vector2i(76, 2), Vector2i(76, 12), Vector2i(72, 24), Vector2i(74, 38), Vector2i(82, 50), Vector2i(92, 60), Vector2i(94, 70)]
const MAWS := [Vector2i(69, 22), Vector2i(77, 43), Vector2i(40, 38)]
const BLOSSOMS := [Vector2i(30, 30), Vector2i(58, 44), Vector2i(71, 32), Vector2i(86, 54), Vector2i(48, 20)]

var tallow: Unit
var supply: Unit
var wp_i := 0
var convoy_started := false
var trucks: Array = []
var truck_wp := {}        # truck -> index
var escaped := 0
var destroyed := 0
var caches: Array = []    # [pos, marker key]
var maw_kills := 0
var maw_agitated := {}    # maw -> time until
var maws: Array = []
var _check_t := 0.0
var _maw_t := 0.0
var _hazard_t := 0.0
var _escort: Array = []


func objective_preview() -> Array:
	return [
		["primary", "Follow Tallow's Outcasts through the glass fields to the Veil convoy route."],
		["primary", "Stop the Veil convoy before it leaves the map (5 trucks)."],
		["primary", "Recover the convoy's navigation data."],
		["secondary", "Deliver the medical supply truck to Tallow's village intact."],
		["bonus", "Lure a Veil patrol into the Maw."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.3, 0.33, 0.36), "sky_horizon": Color(0.5, 0.55, 0.52),
		"ground_horizon": Color(0.3, 0.35, 0.32), "sun_rot": Vector3(-55, 20, 0),
		"sun_color": Color(0.85, 0.9, 0.9), "sun_energy": 0.7, "ambient": 0.75,
		"fog_color": Color(0.45, 0.52, 0.5), "fog_density": 0.009, "weather": "spores",
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 3303, {
		"ground": Color(0.24, 0.27, 0.24), "rock": Color(0.22, 0.3, 0.26), "forest": Color(0.1, 0.16, 0.12),
		"tree": Color(0.1, 0.22, 0.14),
	})
	# dense forest, glass fields, and the winding road
	for i in 26:
		var c := Vector2i(map.rng.randi_range(4, W - 5), map.rng.randi_range(4, H - 5))
		map.blob(c, map.rng.randf_range(2.0, 5.0), MapGrid.Terrain.FOREST, 1.5)
	map.scatter(MapGrid.Terrain.ROCK, 14, 1.0, 2.2, [])
	var path_pts: Array = ROUTE_WP.duplicate()
	path_pts.push_front(START)
	for i in range(path_pts.size() - 1):
		map.carve(path_pts[i], path_pts[i + 1], 4.0)
	for i in range(CONVOY_PATH.size() - 1):
		map.carve(CONVOY_PATH[i], CONVOY_PATH[i + 1], 4.0)
	map.tint_polyline(CONVOY_PATH, 2.0, Color(0.3, 0.29, 0.26))
	map.carve(Vector2i(24, 34), VILLAGE, 3.0)
	map.carve(VILLAGE, Vector2i(52, 38), 3.0)
	map.carve(Vector2i(64, 40), Vector2i(74, 38), 4.0)
	map.clear_area(VILLAGE, 6.0)
	map.clear_area(START, 5.0)
	for mw in MAWS:
		map.clear_area(mw, 5.0)
		map.tint_blob(mw, 4.0, Color(0.2, 0.3, 0.16))
	# glass fields everywhere: they hurt Bastion troops and heal Outcasts
	for c in [Vector2i(18, 38), Vector2i(30, 40), Vector2i(44, 44), Vector2i(58, 36), Vector2i(66, 44),
			Vector2i(78, 30), Vector2i(86, 56), Vector2i(50, 20), Vector2i(30, 20), Vector2i(62, 58), Vector2i(90, 20)]:
		map.crystal_field(c, map.rng.randf_range(2.2, 3.4), MapGrid.Crystal.GREEN)
	map.growth_enabled = true
	map.spread_enabled = false


func setup() -> void:
	start_credits = 0
	player().credits = 0
	player().allowed = {}
	player().free_radar = true   # Havel's field uplink
	var team := spawn(["rifleman", "rifleman", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper", "rocket_trooper",
		"medic", "skyjumper", "skyjumper", "scout_mech", "scout_mech"], PLAYER, START + Vector2i(0, 2))
	supply = spawn_one("supply_truck", PLAYER, START + Vector2i(-2, -3), "supply")
	# Tallow's Outcasts, leading the way
	tallow = spawn_one("tallow", ALLY, START + Vector2i(5, 0), "tallow")
	var guides := spawn(["outcast_fighter", "outcast_fighter", "outcast_fighter", "outcast_fighter", "outcast_brute"], ALLY, START + Vector2i(6, -2), "guides")
	for g in guides + [tallow]:
		g.leash = 8.0
	# Tallow's village
	for off in [Vector2i(-3, -2), Vector2i(2, -3), Vector2i(-2, 2), Vector2i(3, 2), Vector2i(0, -5)]:
		building("hut", NEUTRAL, VILLAGE + off)
	spawn(["outcast_fighter", "outcast_fighter"], ALLY, VILLAGE + Vector2i(0, 3))
	# Maws and blossom trees
	for c in MAWS:
		var mw := building("maw", NEUTRAL, c, "maw")
		maws.append(mw)
		maw_agitated[mw] = 0.0
	for c in BLOSSOMS:
		building("blossom_tree", NEUTRAL, c, "blossom")
		G.map.blossoms.append(c)
	# Veil pickets in the glass, and the patrol that walks past the Maw
	spawn(["rifleman", "rifleman", "rocket_trooper"], ENEMY, Vector2i(28, 46))
	spawn(["raider", "rifleman", "rifleman"], ENEMY, Vector2i(52, 30))
	spawn(["scorpion", "rifleman", "rocket_trooper"], ENEMY, Vector2i(60, 50))
	var patrol := spawn(["rifleman", "rifleman", "rifleman", "rocket_trooper"], ENEMY, Vector2i(46, 44), "patrol")
	for u in patrol:
		u.tags["scripted"] = true
	add_marker("village", cell_pos(VILLAGE), Color(0.5, 1.0, 0.5))
	add_marker("wp", cell_pos(ROUTE_WP[0]), Color(0.9, 0.9, 0.5))


func begin() -> void:
	add_objective("follow", "Follow Tallow's Outcasts through the glass fields to the Veil convoy route.")
	add_objective("convoy", "Stop the Veil convoy before it leaves the map (0/5 trucks stopped, 0 escaped).")
	add_objective("data", "Recover the convoy's navigation data.")
	add_objective("tallow", "Tallow must survive.", "primary", true, true)
	add_objective("supply", "Deliver the medical supply truck to Tallow's village intact.", "secondary")
	add_objective("maw", "Lure a Veil patrol into the Maw (0/3).", "bonus")
	focus(START + Vector2i(4, 0))
	after(2.0, func(): say("tallow", "Keep up, Bastion. Stay off the crystal: it eats your people. It feeds mine."))
	after(9.0, func(): say("havel", "Your troops take damage standing on the glass, Commander. Tallow's people heal on it. Let them lead."))


# ================================================================ frame

func tick(delta: float) -> void:
	_check_t -= delta
	_maw_t -= delta
	_hazard_t -= delta
	if _maw_t <= 0.0:
		_maw_t = 0.25
		_update_maws(0.25)
	if _hazard_t <= 0.0:
		_hazard_t = 0.5
		_crystal_hazard()
	if _check_t > 0.0:
		return
	_check_t = 0.4
	_lead()
	_patrol()
	if convoy_started:
		_drive_convoy()
	elif time > 420.0:
		_start_convoy()
	_check_supply()
	_check_caches()
	if not (is_instance_valid(tallow) and tallow.alive):
		lose("Tallow was killed. Without a guide, the strike team is lost in the glass.")
		return
	var bastion: Array = team_units(PLAYER).filter(func(u): return u.def.get("faction", "") != "outcast")
	if bastion.is_empty():
		lose("The Bastion strike team was wiped out.")


## Tallow's group moves waypoint to waypoint, waiting for the Bastion team.
func _lead() -> void:
	if wp_i >= ROUTE_WP.size() or not (is_instance_valid(tallow) and tallow.alive):
		return
	var group: Array = tagged("guides") + ([tallow] if is_instance_valid(tallow) and tallow.alive else [])
	var target: Vector2i = ROUTE_WP[wp_i]
	var there := G.flat_dist(tallow.position, cell_pos(target)) < 4.0
	var bastion_close := team_near(tallow.position, PLAYER, 10.0)
	if there and bastion_close:
		wp_i += 1
		if wp_i >= ROUTE_WP.size():
			remove_marker("wp")
			complete("follow")
			say("tallow", "There. That's their road. The convoy comes down from the north. Pick your spot, Bastion.")
			_start_convoy()
			return
		add_marker("wp", cell_pos(ROUTE_WP[wp_i]), Color(0.9, 0.9, 0.5))
		target = ROUTE_WP[wp_i]
		match wp_i:
			2: say("tallow", "The village is north of here. If you brought the medicine, send the truck up that trail.")
			3: say("tallow", "That's the Maw ahead. Don't walk on its veins. Anything that does, it keeps.")
		attack_move(group, target)
	elif not there:
		for g in group:
			if g.order == Unit.Order.IDLE and G.flat_dist(g.position, cell_pos(target)) > 4.0:
				g.cmd_attack_move(G.map.spread_cells(target, 1)[0] + Vector2i(randi_range(-2, 2), randi_range(-2, 2)))
	elif once("wait_line_%d" % wp_i):
		say("tallow", "We're waiting, Bastion. The glass doesn't.")


func _patrol() -> void:
	# a Veil patrol walking a loop that passes the southern Maw
	var loop := [Vector2i(46, 44), Vector2i(36, 38), Vector2i(34, 30), Vector2i(46, 30)]
	for u in tagged("patrol"):
		if u.order == Unit.Order.IDLE and u.target == null:
			var i: int = int(u.get_meta("wp", 0))
			u.set_meta("wp", (i + 1) % loop.size())
			u.cmd_attack_move(loop[(i + 1) % loop.size()])


func _crystal_hazard() -> void:
	for u in team_units(PLAYER):
		if u.def.get("outcast", false) or u.is_air:
			continue
		if G.map.crystal_at(G.map.world_to_cell(u.position)) > 0.0:
			u.take_damage(3.0 if u.is_infantry else 5.0, "claw", null)


# ================================================================ Maws

func _update_maws(dt: float) -> void:
	for mw in maws:
		if not is_instance_valid(mw):
			continue
		var agitated: bool = time < float(maw_agitated.get(mw, 0.0))
		var r := 5.5 if agitated else 3.2
		var dps := 70.0 if agitated else 14.0
		for e in G.entities.duplicate():
			if not (e is Unit) or not e.alive or e.is_air or e.move_class == "jump" and e.is_moving():
				continue
			if G.flat_dist(e.position, mw.position) <= r:
				e.tags["maw_hit"] = time
				e.take_damage(dps * dt, "claw", null)
				if randf() < 0.3:
					Fx.beam(mw.position + Vector3(0, 0.4, 0), e.position + Vector3(0, 0.3, 0), Color(0.5, 1.0, 0.3), 0.05, 0.15)
		if agitated and randf() < 0.3:
			Fx.ring(mw.position, Color(0.5, 1.0, 0.3, 0.6), r, 0.6)


func on_damaged(e: Entity, attacker: Entity) -> void:
	if e.tags.has("maw"):
		if float(maw_agitated.get(e, 0.0)) < time:
			say_once("maw_agitated", "tallow", "You woke it! Get your people back!")
		maw_agitated[e] = time + 12.0
		e.hp = e.max_hp


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e.tags.has("blossom"):
		G.map.blossoms.erase(G.map.world_to_cell(e.position))
		G.damage_area(e.position, 3.2, 90.0, "spore", null)
		for i in 8:
			Fx.sparkle(e.position + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), Color(0.5, 1.5, 0.5))
		Fx.ring(e.position, Color(0.4, 1.0, 0.5, 0.7), 3.2, 1.2)
		say_once("spores", "havel", "Spore cloud! Anyone on foot near those trees is choking on glass.")
	if e.team == ENEMY and e.tags.has("maw_hit") and time - float(e.tags["maw_hit"]) < 2.0:
		maw_kills += 1
		set_text("maw", "Lure a Veil patrol into the Maw (%d/3)." % mini(maw_kills, 3))
		if maw_kills >= 3 and is_active("maw"):
			complete("maw")
			spawn(["outcast_brute", "outcast_brute"], PLAYER, ROUTE_WP[mini(wp_i, ROUTE_WP.size() - 1)])
			say("tallow", "Ha! You fed the Maw a whole patrol. My brutes want to fight beside you, Bastion. They're yours.")
	if trucks.has(e):
		trucks.erase(e)
		destroyed += 1
		_update_convoy_text()
		var key := "cache%d" % caches.size()
		caches.append([e.position, key])
		add_marker(key, e.position, Color(0.4, 0.9, 1.0))
		say_once("cache", "havel", "Truck down! There's a data cache in the wreck. Get someone over there to grab it.")


# ================================================================ convoy

func _start_convoy() -> void:
	if convoy_started:
		return
	convoy_started = true
	say("havel", "Convoy's moving! Five trucks and a heavy escort, coming south down the road. Three of them get away and the Codex trail goes cold.")
	for i in 5:
		after(i * 7.0, _spawn_truck.bind(i))
	_escort = spawn(["scorpion", "scorpion", "raider", "raider", "rifleman", "rifleman", "rocket_trooper", "rocket_trooper"], ENEMY, CONVOY_PATH[0] + Vector2i(0, 2), "scripted")
	for u in _escort:
		u.set_meta("wp", 1)


func _spawn_truck(_i: int) -> void:
	var t := spawn_one("convoy_truck", ENEMY, CONVOY_PATH[0], "truck")
	t.tags["scripted"] = true
	trucks.append(t)
	truck_wp[t] = 1
	t.cmd_move(CONVOY_PATH[1])


func _drive_convoy() -> void:
	for t in trucks.duplicate():
		if not (is_instance_valid(t) and t.alive):
			continue
		var i: int = truck_wp.get(t, 1)
		if t.position.z > H - 4.0:
			trucks.erase(t)
			t.remove_silently()
			escaped += 1
			_update_convoy_text()
			say("havel", "A truck got through! That's %d." % escaped)
			if escaped >= 3:
				lose("Three convoy trucks escaped with the Codex data.")
				return
			continue
		if G.flat_dist(t.position, cell_pos(CONVOY_PATH[i])) < 2.0 and i < CONVOY_PATH.size() - 1:
			truck_wp[t] = i + 1
			t.cmd_move(CONVOY_PATH[i + 1])
		elif t.order == Unit.Order.IDLE:
			t.cmd_move(CONVOY_PATH[i])
	# the escort shadows the lead truck
	var lead: Variant = null
	for t in trucks:
		if is_instance_valid(t) and t.alive:
			lead = t
			break
	for u in _escort:
		if not (is_instance_valid(u) and u.alive):
			continue
		if lead and u.order == Unit.Order.IDLE and G.flat_dist(u.position, lead.position) > 5.0:
			u.cmd_attack_move(G.map.world_to_cell(lead.position) + Vector2i(randi_range(-2, 2), randi_range(-2, 2)))
	if trucks.is_empty() and destroyed + escaped >= 5 and is_active("convoy"):
		complete("convoy")


func _update_convoy_text() -> void:
	set_text("convoy", "Stop the Veil convoy before it leaves the map (%d/5 trucks stopped, %d escaped)." % [destroyed, escaped])


func _check_caches() -> void:
	for c in caches.duplicate():
		for u in team_units(PLAYER):
			if G.flat_dist(u.position, c[0]) < 1.8:
				caches.erase(c)
				remove_marker(c[1])
				if is_active("data"):
					complete("data")
					say("havel", "Got it: navigation data. Let's see where they were going.")
				break


func _check_supply() -> void:
	if not is_active("supply"):
		return
	if not (is_instance_valid(supply) and supply.alive):
		fail("supply")
		say("tallow", "Your medicine burned in the glass. Words are cheap, Bastion.")
		return
	if G.flat_dist(supply.position, cell_pos(VILLAGE)) < 5.0:
		complete("supply")
		remove_marker("village")
		pending_flags["tallow_friendly"] = true
		supply.remove_silently()
		say("tallow", "Medicine. Real medicine. The children will live through the winter. I won't forget this, Bastion.")


func harvest_cell_ok(_c: Vector2i) -> bool:
	return false
