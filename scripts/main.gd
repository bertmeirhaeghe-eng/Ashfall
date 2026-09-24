extends Node3D
## Milestone 1 entry point: builds the whole match in code
## (environment, map, players, starting bases, camera, HUD, AI).

const PLAYER_COLOR := Color(0.2, 0.5, 1.0)   # Bastion blue
const AI_COLOR := Color(0.9, 0.15, 0.1)      # Veil red

var _check_t := 0.0


func _ready() -> void:
	G.reset()
	if G.rules.is_empty():
		G.load_rules()
	_setup_environment()

	var map := MapGrid.new()
	map.name = "Map"
	add_child(map)
	G.map = map
	map.generate(randi())

	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	G.world = world
	var fx := Node3D.new()
	fx.name = "Fx"
	add_child(fx)
	G.fx_root = fx

	G.players = [
		PlayerState.new(0, "bastion", PLAYER_COLOR, false, "Bastion (You)"),
		PlayerState.new(1, "veil", AI_COLOR, true, "The Veil (AI)"),
	]
	G.local_team = 0

	var cam := RTSCamera.new()
	cam.name = "Camera"
	cam.bounds = Rect2(4, 4, map.w - 8, map.h - 8)
	add_child(cam)
	G.camera = cam

	var ctl := InputController.new()
	ctl.name = "Input"
	add_child(ctl)
	G.controller = ctl

	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	G.hud = hud

	# starting bases: Construction Yard + a small escort
	for p in G.players:
		var bc: Vector2i = map.base_cells[p.id]
		G.spawn_structure("construction_yard", p.id, bc - Vector2i(1, 1), true)
		var escort: Array = ["rifleman", "rifleman", "rifleman", "rocket_trooper"]
		escort.append("scout_mech" if p.faction == "bastion" else "raider")
		var cells: Array = map.spread_cells(bc + Vector2i(3, -3) if p.id == 0 else bc + Vector2i(-3, 3), escort.size())
		for i in escort.size():
			G.spawn_unit(escort[i], p.id, map.cell_to_world(cells[i]))
		p.recalc_power()

	var ai := AIController.new()
	ai.name = "AI"
	add_child(ai)
	ai.setup(G.players[1], map.base_cells[1], map.base_cells[0])

	cam.focus_on(map.cell_to_world(map.base_cells[0]) + Vector3(4, 0, -3))
	hud.notify("Commander, establish the base: Power Plant, then a Refinery.")
	hud.notify("Destroy every Veil structure and unit to win.")


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.18, 0.2, 0.24)
	sm.sky_horizon_color = Color(0.55, 0.45, 0.35)
	sm.ground_bottom_color = Color(0.08, 0.07, 0.06)
	sm.ground_horizon_color = Color(0.45, 0.38, 0.3)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.42, 0.34)
	env.fog_density = 0.004
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _physics_process(delta: float) -> void:
	if G.game_over:
		return
	G.elapsed += delta
	for p in G.players:
		p.process(delta)
	G.separate_units(delta)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.0
		_check_victory()


func _check_victory() -> void:
	for p in G.players:
		if not p.defeated and p.structures().is_empty() and p.units().is_empty():
			p.defeated = true
			if p.id != G.local_team:
				G.hud.notify("%s has been eliminated" % p.display)
	var me: PlayerState = G.players[G.local_team]
	if me.defeated:
		_end(false)
		return
	var others_alive := false
	for p in G.players:
		if p.id != G.local_team and not p.defeated:
			others_alive = true
	if not others_alive:
		_end(true)


func _end(victory: bool) -> void:
	G.game_over = true
	G.controller.cancel_mode()
	G.hud.show_game_over(victory)
