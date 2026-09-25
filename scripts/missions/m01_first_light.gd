extends Mission
## Mission 1 — First Light. Rhine Clear Zone outskirts, dawn.
## Signature mechanic: a glass-storm front sweeping west to east across the map.
## Gather the scattered garrison, save the towns' buses, deploy the MCV before
## the front reaches the rail yard, then destroy the Veil raiding camp.

const W := 104
const H := 64
const START := Vector2i(8, 33)
const RAIL_YARD := Vector2i(80, 32)
const EVAC := Vector2i(84, 42)
const CAMP := Vector2i(92, 11)
const CHURCH := Vector2i(44, 24)
const TOWNS := {
	"Hollerdorf": Vector2i(20, 42),
	"Weissbach": Vector2i(38, 14),
	"Lenz": Vector2i(58, 48),
}
const SQUADS := [
	[Vector2i(12, 18), ["rifleman", "rifleman", "rocket_trooper"]],
	[Vector2i(28, 56), ["rifleman", "rifleman", "rifleman"]],
	[Vector2i(48, 34), ["rocket_trooper", "rifleman", "rifleman"]],
	[Vector2i(66, 14), ["rifleman", "rocket_trooper", "rifleman"]],
]

var storm: GlassStorm
var mcv: Unit
var squads_found := 0
var squads_lost := 0
var buses := {}          # town -> Unit
var bus_state := {}      # town -> "waiting" | "moving" | "saved" | "lost"
var deployed := false
var _raid_t := 60.0
var _check_t := 0.0


func objective_preview() -> Array:
	return [
		["primary", "Gather the scattered garrison squads (4) and reach the MCV."],
		["primary", "Deploy the MCV before the storm front reaches the rail yard."],
		["primary", "Destroy the Veil raiding camp."],
		["secondary", "Escort civilian buses out of Hollerdorf, Weissbach and Lenz before the storm hits each town ($1,000 per saved town)."],
		["bonus", "Rescue the stranded Pathfinder Mech pilot in the collapsed church."],
	]


func theme() -> Dictionary:
	return {
		"sky_top": Color(0.22, 0.26, 0.3), "sky_horizon": Color(0.75, 0.55, 0.4),
		"ground_horizon": Color(0.35, 0.33, 0.28), "sun_rot": Vector3(-22, 70, 0),
		"sun_color": Color(1.0, 0.75, 0.55), "sun_energy": 1.0, "ambient": 0.6,
		"fog_color": Color(0.55, 0.5, 0.45), "fog_density": 0.006, "weather": "ash", "lights": 0.45,
	}


func build_map(map: MapGrid) -> void:
	map.init_blank(W, H, 1101, {
		"ground": Color(0.3, 0.33, 0.23), "rock": Color(0.3, 0.29, 0.27),
		"forest": Color(0.12, 0.18, 0.1), "tree": Color(0.12, 0.24, 0.12),
	})
	# roads between the towns and the rail yard
	var road := Color(0.36, 0.33, 0.28)
	map.tint_polyline([START, TOWNS["Hollerdorf"], Vector2i(32, 32), TOWNS["Weissbach"]], 2.0, road)
	map.tint_polyline([Vector2i(32, 32), Vector2i(48, 34), TOWNS["Lenz"], Vector2i(70, 40), EVAC, RAIL_YARD], 2.0, road)
	map.tint_polyline([Vector2i(48, 34), Vector2i(64, 26), RAIL_YARD], 2.0, road)
	# rail line through the yard
	map.tint_line(Vector2i(74, 1), Vector2i(74, 62), 1.2, Color(0.24, 0.2, 0.18))
	map.tint_blob(RAIL_YARD, 5.0, Color(0.33, 0.31, 0.29))
	# Black-green forest around the Veil camp, with a way in from the south-west
	map.blob(Vector2i(92, 16), 11.0, MapGrid.Terrain.FOREST, 2.0)
	map.blob(Vector2i(22, 6), 5.0, MapGrid.Terrain.FOREST)
	map.blob(Vector2i(8, 56), 5.0, MapGrid.Terrain.FOREST)
	map.blob(Vector2i(46, 58), 4.0, MapGrid.Terrain.FOREST)
	map.blob(Vector2i(62, 4), 4.0, MapGrid.Terrain.FOREST)
	map.clear_area(CAMP, 6.0)
	map.carve(CAMP, Vector2i(80, 22), 4.0)
	map.carve(CAMP, Vector2i(100, 30), 3.0)
	# rocky outcrops
	var keep := [[START, 5], [RAIL_YARD, 9], [EVAC, 4], [CHURCH, 4], [CAMP, 7]]
	for t in TOWNS.values():
		keep.append([t, 6])
	for s in SQUADS:
		keep.append([s[0], 3])
	map.scatter(MapGrid.Terrain.ROCK, 12, 1.2, 2.4, keep)
	# crystal around the rail yard (economy once the base is up)
	map.crystal_field(Vector2i(88, 50), 3.4, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(68, 56), 3.0, MapGrid.Crystal.GREEN)
	map.crystal_field(Vector2i(86, 26), 2.4, MapGrid.Crystal.GREEN)
	for c in [START, RAIL_YARD, EVAC, CAMP, CHURCH] + TOWNS.values():
		map.carve(START, c, 2.0)


func setup() -> void:
	start_credits = 3000
	player().credits = 3000
	player().free_radar = true   # Kessler Station's radar net, until the storm jams it
	# your starting column
	spawn(["scout_mech", "rifleman", "rifleman", "rocket_trooper"], PLAYER, START)
	# scattered garrison squads, waiting to be found
	for i in SQUADS.size():
		for u in spawn(SQUADS[i][1], NEUTRAL, SQUADS[i][0], "squad%d" % i):
			u.hold_position = true
	# the MCV and its crew at the rail yard
	mcv = spawn_one("mcv", NEUTRAL, RAIL_YARD, "mcv")
	# towns, buses and the church
	for town in TOWNS.keys():
		var c: Vector2i = TOWNS[town]
		for off in [Vector2i(-4, -3), Vector2i(2, -4), Vector2i(-3, 3), Vector2i(3, 2)]:
			building("house", NEUTRAL, c + off)
		var bus := spawn_one("bus", NEUTRAL, c, "bus")
		buses[town] = bus
		bus_state[town] = "waiting"
	building("church", NEUTRAL, CHURCH, "church")
	# the Veil camp in the forest
	building("veil_camp", ENEMY, CAMP + Vector2i(-3, -2), "camp")
	building("veil_camp", ENEMY, CAMP + Vector2i(2, 1), "camp")
	building("power_plant", ENEMY, CAMP + Vector2i(-2, 3), "camp")
	building("guard_tower", ENEMY, CAMP + Vector2i(-5, 3), "camp")
	building("guard_tower", ENEMY, CAMP + Vector2i(1, 5), "camp")
	spawn(["raider", "rifleman", "rifleman", "rocket_trooper"], ENEMY, CAMP + Vector2i(-4, 7))
	# raiding parties still in the towns
	spawn(["raider", "rifleman", "rifleman"], ENEMY, TOWNS["Weissbach"] + Vector2i(6, 4))
	spawn(["raider", "raider", "rifleman", "rocket_trooper"], ENEMY, TOWNS["Lenz"] + Vector2i(6, -5))
	spawn(["rifleman", "rifleman"], ENEMY, Vector2i(52, 30))
	enemy().credits = 1500
	add_ai(enemy(), CAMP, RAIL_YARD, {"build": false, "first_attack": 420.0, "wave_interval": 70.0,
		"wave_size": 5, "wave_max": 10, "income": 6.0, "units": ["rifleman", "rocket_trooper"]})
	# the storm front, coming from the west
	storm = GlassStorm.new()
	storm.front = -12.0
	storm.width = 24.0
	storm.speed = 0.19
	storm.map_h = H
	storm.immune_teams = [ENEMY]
	G.world.add_child(storm)
	add_marker("mcv", cell_pos(RAIL_YARD), Color(0.4, 0.8, 1.0), "MCV")
	for i in SQUADS.size():
		add_marker("squad%d" % i, cell_pos(SQUADS[i][0]), Color(0.5, 1.0, 0.5))
	add_marker("church", cell_pos(CHURCH), Color(1.0, 0.85, 0.3))


func begin() -> void:
	add_objective("gather", "Gather the scattered garrison squads (0/4) and reach the MCV at the rail yard.")
	add_objective("deploy", "Deploy the MCV (D) before the storm front reaches the rail yard.")
	add_objective("camp", "Destroy the Veil raiding camp in the forest.", "primary", false)
	add_objective("buses", "Escort the civilian buses out of Hollerdorf, Weissbach and Lenz (0/3 saved).", "secondary")
	add_objective("pilot", "Rescue the stranded Pathfinder pilot in the collapsed church.", "bonus")
	focus(START + Vector2i(6, 0))
	after(2.0, func(): say("havel", "Commander, Havel here. The storm front is moving east at walking pace, and it's right behind you. Hollerdorf is first in line."))
	after(9.0, func(): say("havel", "Radio chatter puts garrison squads north, south and in the fields ahead. Get close and they'll fall in with you."))


# ================================================================ frame

func tick(delta: float) -> void:
	G.radar_jammed = storm.on_map(W)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	_check_squads()
	_check_mcv()
	_check_buses()
	_check_pilot()
	_check_storm_warnings()
	_check_camp()
	if deployed:
		_storm_raids(0.4)
	if all_lost():
		lose("All Bastion forces in the valley have been lost.")


func _check_squads() -> void:
	for i in SQUADS.size():
		var tag := "squad%d" % i
		var members := tagged(tag)
		if members.is_empty():
			if not _once.has(tag + "_done"):
				_once[tag + "_done"] = true
				squads_lost += 1
				remove_marker(tag)
				G.notify(PLAYER, "A garrison squad was lost in the storm.")
			continue
		if members[0].team != NEUTRAL:
			continue
		var c: Vector3 = members[0].position
		if team_near(c, PLAYER, 5.0):
			for u in members:
				u.set_team(PLAYER)
				u.hold_position = false
				u.tags.erase(tag)
			_once[tag + "_done"] = true
			squads_found += 1
			remove_marker(tag)
			say("sergeant", ["Bastion garrison, reporting! We thought we were done for.", "About time, Commander. We're with you.",
				"Squad three, falling in. The storm's coming, sir!", "Last squad reporting. Let's get out of this weather."][mini(squads_found - 1, 3)])
	_update_gather()


func _update_gather() -> void:
	var resolved := squads_found + squads_lost
	set_text("gather", "Gather the scattered garrison squads (%d/4) and reach the MCV at the rail yard.", [squads_found])
	var mcv_ours: bool = is_instance_valid(mcv) and mcv.alive and mcv.team == PLAYER
	if resolved >= 4 and (mcv_ours or deployed):
		complete("gather")


func _check_mcv() -> void:
	if deployed:
		return
	if not (is_instance_valid(mcv) and mcv.alive):
		lose("The MCV was destroyed.")
		return
	if mcv.team == NEUTRAL:
		for u in team_units(PLAYER):
			if u != mcv and G.flat_dist(u.position, mcv.position) < 6.0:
				mcv.set_team(PLAYER)
				remove_marker("mcv")
				say("sergeant", "MCV crew here! Get us deployed, Commander, before that storm reaches the yard.")
				break
	if storm.contains(mcv.position):
		lose("The MCV was caught in the glass storm.")
		return
	var dist: float = RAIL_YARD.x - storm.front
	if dist < 30.0 and once("mcv_warn1"):
		say("havel", "The front is two minutes from the rail yard. Deploy that MCV!")
	elif dist < 12.0 and once("mcv_warn2"):
		say("havel", "Commander, the storm is almost on the yard!")


func on_deployed(s: Structure) -> void:
	if s.def_id != "construction_yard" or deployed:
		return
	deployed = true
	complete("deploy")
	_update_gather()
	reveal("camp")
	add_marker("camp", cell_pos(CAMP), Color(1.0, 0.3, 0.25))
	say("okafor", "Good. You have a base. Power first, then a refinery. When you're ready, find that camp in the forest.")
	say("havel", "Stay close to your buildings while the storm passes. The walls will shelter anyone standing next to them.")


func _check_buses() -> void:
	var saved := 0
	var lost := 0
	for town in TOWNS.keys():
		var st: String = bus_state[town]
		var bus = buses[town]
		if st == "saved":
			saved += 1
			continue
		if st == "lost":
			lost += 1
			continue
		if not (is_instance_valid(bus) and bus.alive):
			bus_state[town] = "lost"
			lost += 1
			G.notify(PLAYER, tr("The %s bus was lost.") % town)
			continue
		if st == "waiting":
			if team_near(bus.position, PLAYER, 7.0):
				bus.set_team(PLAYER)
				bus.cmd_move(EVAC)
				bus_state[town] = "moving"
				say("civilian", "Bastion! Thank God. We're heading for the rail yard, please cover us!")
		elif st == "moving":
			if G.flat_dist(bus.position, cell_pos(EVAC)) < 4.0:
				bus_state[town] = "saved"
				bus.remove_silently()
				player().credits += 1000
				saved += 1
				G.notify(PLAYER, tr("Civilians from %s are safe (+$1,000).") % town)
			elif bus.order == Unit.Order.IDLE:
				bus.cmd_move(EVAC)
	set_text("buses", "Escort the civilian buses out of Hollerdorf, Weissbach and Lenz (%d/3 saved).", [saved])
	if saved == 3:
		complete("buses")
	elif lost > 0:
		fail("buses")


func _check_pilot() -> void:
	if not is_active("pilot"):
		return
	if team_near(cell_pos(CHURCH) + Vector3(1, 0, 1.5), PLAYER, 4.5):
		var mech := spawn_one("scout_mech", PLAYER, CHURCH + Vector2i(3, 1))
		mech.set_rank(1)
		remove_marker("church")
		complete("pilot")
		say("sergeant", "Pilot's out, and she's walked her Pathfinder out of the rubble with her. Veteran crew, Commander.")


func _check_storm_warnings() -> void:
	for town in TOWNS.keys():
		var tx: float = TOWNS[town].x
		if tx - storm.front < 20.0 and tx - storm.front > 0.0 and bus_state[town] == "waiting" and once("warn_" + town):
			say("havel", "The storm will hit %s in about a minute and a half. Those civilians need an escort.", [town])
		if storm.front > tx + 2.0 and bus_state[town] == "waiting" and is_instance_valid(buses[town]) and buses[town].alive:
			buses[town].take_damage(40.0, "laser", null)


func _check_camp() -> void:
	if not deployed:
		return
	if count_tagged("camp") == 0 and is_active("camp"):
		complete("camp")
		remove_marker("camp")
		say("okafor", "The camp is burning. They'll think twice before hiding in our weather again.")


## Once the base is up, Veil raiders use the storm as cover to hit it.
func _storm_raids(dt: float) -> void:
	_raid_t -= dt
	if _raid_t > 0.0 or storm.band_max() < 40.0 or not storm.on_map(W):
		return
	_raid_t = 55.0
	var from := Vector2i(clampi(int(storm.front) - 4, 4, W - 5), randi_range(10, H - 10))
	var base := RAIL_YARD
	for s in player().structures():
		base = s.cell
		break
	send_wave(["raider", "rifleman", "rifleman", "rocket_trooper"], ENEMY, from, base)
	if once("raid_line"):
		say("havel", "Contacts coming out of the storm! The Veil are using it as cover.")


func on_entity_died(e: Entity, _killer: Entity) -> void:
	if e == mcv and not deployed and not ended:
		lose("The MCV was destroyed.")
