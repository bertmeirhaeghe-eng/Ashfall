extends Node3D
## Game scene entry point: loads the current campaign mission, then builds the
## environment, map, players, camera, HUD and hands control to the mission.

var mission: Mission


func _ready() -> void:
	get_tree().paused = false
	G.reset()
	if G.rules.is_empty():
		G.load_rules()
	var info: Dictionary = Campaign.mission_info()
	var scr: Script = load(info["script"])
	mission = scr.new()
	mission.name = "Mission"
	mission.number = int(info["id"])
	G.mission = mission
	mission.setup_players()

	var th: Dictionary = mission.theme()
	_setup_environment(th)

	var map := MapGrid.new()
	map.name = "Map"
	add_child(map)
	G.map = map
	mission.build_map(map)
	map.finalize()

	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	G.world = world
	var fx := Node3D.new()
	fx.name = "Fx"
	add_child(fx)
	G.fx_root = fx

	var cam := RTSCamera.new()
	cam.name = "Camera"
	cam.bounds = Rect2(4, 4, map.w - 8, map.h - 8)
	add_child(cam)
	G.camera = cam
	_setup_weather(th.get("weather", "none"), cam)

	var ctl := InputController.new()
	ctl.name = "Input"
	add_child(ctl)
	G.controller = ctl

	add_child(mission)
	mission.setup()
	map.rebuild_static()
	for p in G.players:
		p.recalc_power()

	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	G.hud = hud
	mission.begin()
	hud.refresh_objectives()
	if Campaign.debug_autotest != "":
		TestRunner.attach(mission)


func _setup_environment(th: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = th.get("sky_top", Color(0.18, 0.2, 0.24))
	sm.sky_horizon_color = th.get("sky_horizon", Color(0.55, 0.45, 0.35))
	sm.ground_bottom_color = th.get("ground_bottom", Color(0.08, 0.07, 0.06))
	sm.ground_horizon_color = th.get("ground_horizon", Color(0.45, 0.38, 0.3))
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = th.get("ambient", 0.7)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = th.get("exposure", 1.0)
	env.glow_enabled = true
	env.glow_intensity = th.get("glow", 0.7)
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = th.get("fog_color", Color(0.5, 0.42, 0.34))
	env.fog_density = th.get("fog_density", 0.004)
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = th.get("sun_rot", Vector3(-48, 35, 0))
	sun.light_color = th.get("sun_color", Color(1.0, 0.86, 0.7))
	sun.light_energy = th.get("sun_energy", 1.25)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


## Screen-space weather that follows the camera (rain, snow, ash, crystal spores).
func _setup_weather(kind: String, cam: RTSCamera) -> void:
	if kind == "none" or kind == "":
		return
	var p := GPUParticles3D.new()
	p.name = "Weather"
	p.amount = 900 if kind != "spores" else 300
	p.lifetime = 2.0 if kind == "rain" else 5.0
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	var quad := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	match kind:
		"rain":
			pm.direction = Vector3(0.1, -1, 0)
			pm.spread = 2.0
			pm.initial_velocity_min = 22.0
			pm.initial_velocity_max = 26.0
			pm.gravity = Vector3(0, -10, 0)
			quad.size = Vector2(0.03, 0.6)
			qm.albedo_color = Color(0.6, 0.7, 0.85, 0.45)
		"snow":
			pm.direction = Vector3(0.6, -1, 0.2)
			pm.spread = 25.0
			pm.initial_velocity_min = 5.0
			pm.initial_velocity_max = 9.0
			pm.gravity = Vector3(1.5, -2, 0)
			quad.size = Vector2(0.12, 0.12)
			qm.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
		"ash":
			pm.direction = Vector3(0.3, -1, 0.1)
			pm.spread = 30.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0.5, -1, 0)
			quad.size = Vector2(0.08, 0.08)
			qm.albedo_color = Color(0.5, 0.9, 0.55, 0.6)
		_:
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 60.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			pm.gravity = Vector3(0, 0.2, 0)
			pm.emission_box_extents = Vector3(30, 6, 30)
			quad.size = Vector2(0.07, 0.07)
			qm.albedo_color = Color(0.4, 1.0, 0.6, 0.8)
	quad.material = qm
	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, 16 if kind != "spores" else 2, 0)
	cam.add_child(p)


func _physics_process(delta: float) -> void:
	if G.game_over:
		return
	G.elapsed += delta
	for p in G.players:
		p.process(delta)
	G.separate_units(delta)
	G.update_visibility(delta)
