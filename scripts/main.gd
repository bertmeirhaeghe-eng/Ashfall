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
	Music.start()   # the player has control from here on
	if Campaign.debug_autotest != "":
		TestRunner.attach(mission)


func _setup_environment(th: Dictionary) -> void:
	# Tiberian Sun-style grading: filmic tone curve, heavy haze, cool fill light
	# and a vignette. Each mission's theme sets the sky, sun, fog and ambient.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = th.get("sky_top", Color(0.2, 0.17, 0.16))
	sm.sky_horizon_color = th.get("sky_horizon", Color(0.62, 0.4, 0.22))
	sm.sky_curve = 0.12
	sm.ground_bottom_color = th.get("ground_bottom", Color(0.1, 0.07, 0.05))
	sm.ground_horizon_color = th.get("ground_horizon", Color(0.5, 0.33, 0.18))
	sm.sun_angle_max = 40.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var sky_mix: Color = (sm.sky_top_color as Color).lerp(sm.sky_horizon_color, 0.5)
	env.ambient_light_color = th.get("ambient_color", Color(0.42, 0.42, 0.52).lerp(sky_mix, 0.35))
	env.ambient_light_energy = float(th.get("ambient", 0.55)) * 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = th.get("exposure", 1.05)
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = th.get("glow", 0.9)
	env.glow_strength = 1.1
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = th.get("fog_color", Color(0.5, 0.38, 0.27))
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.25
	env.fog_density = th.get("fog_density", 0.008)
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.6
	env.fog_height = 0.4
	env.fog_height_density = 0.06
	env.ssao_enabled = true
	env.ssao_intensity = 2.2
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.97
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = th.get("saturation", 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = th.get("sun_rot", Vector3(-34, 40, 0))
	sun.light_color = th.get("sun_color", Color(1.0, 0.7, 0.42))
	sun.light_energy = th.get("sun_energy", 1.45)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	# faint cold fill from the opposite side so shadows aren't flat black
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55, -140, 0)
	fill.light_color = Color(0.45, 0.5, 0.7)
	fill.light_energy = 0.25
	add_child(fill)

	# screen-edge vignette under the HUD
	var vl := CanvasLayer.new()
	vl.layer = -1
	var vr := ColorRect.new()
	vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vr.material = vm
	vl.add_child(vr)
	add_child(vl)


## Screen-space weather that follows the camera (rain, snow, ash, crystal spores).
func _setup_weather(kind: String, cam: RTSCamera) -> void:
	if kind == "none" or kind == "":
		return
	var p := GPUParticles3D.new()
	p.name = "Weather"
	p.amount = 900 if kind == "rain" or kind == "snow" else 350
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
			quad.size = Vector2(0.035, 0.035)
			qm.albedo_color = Color(0.5, 0.9, 0.55, 0.5)
		_:
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 60.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			pm.gravity = Vector3(0, 0.2, 0)
			pm.emission_box_extents = Vector3(30, 6, 30)
			quad.size = Vector2(0.04, 0.04)
			qm.albedo_color = Color(0.4, 1.0, 0.6, 0.7)
	if kind != "rain":
		qm.albedo_texture = _soft_dot()
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.5
		pm.turbulence_noise_scale = 6.0
		quad.size *= 1.8
	quad.material = qm
	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, 16 if kind != "spores" else 2, 0)
	cam.add_child(p)
	if kind == "ash":
		# a few glowing embers drifting through the ash
		var embers := p.duplicate() as GPUParticles3D
		embers.amount = 60
		var eq := QuadMesh.new()
		eq.size = Vector2(0.05, 0.05)
		var eqm := qm.duplicate() as StandardMaterial3D
		eqm.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
		eqm.emission_enabled = true
		eqm.emission = Color(1.0, 0.45, 0.1)
		eqm.emission_energy_multiplier = 3.0
		eq.material = eqm
		embers.draw_pass_1 = eq
		cam.add_child(embers)


func _soft_dot() -> Texture2D:
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	return dot


func _physics_process(delta: float) -> void:
	if G.game_over:
		return
	G.elapsed += delta
	for p in G.players:
		p.process(delta)
	G.separate_units(delta)
	G.update_visibility(delta)
