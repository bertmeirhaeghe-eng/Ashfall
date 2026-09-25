extends Node3D
## Game scene entry point: loads the current campaign mission, then builds the
## environment, map, players, camera, HUD and hands control to the mission.

var mission: Mission
var env: Environment
var sun: DirectionalLight3D


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
	var vfx := Vfx.new()
	vfx.name = "Vfx"
	fx.add_child(vfx)

	var cam := RTSCamera.new()
	cam.name = "Camera"
	cam.bounds = Rect2(4, 4, map.w - 8, map.h - 8)
	add_child(cam)
	G.camera = cam
	var weather := Weather.new()
	weather.name = "Weather"
	add_child(weather)
	G.weather = weather
	weather.setup(th.get("weather", "none"), th.get("storm", ""), env, sun, cam)

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
	var cursor := Cursor3D.new()
	cursor.name = "Cursor3D"
	add_child(cursor)
	mission.begin()
	hud.refresh_objectives()
	Music.start()   # the player has control from here on
	if Campaign.debug_autotest != "":
		TestRunner.attach(mission)


## How dark the mission is (0 day .. 1 night): the theme's "lights" key, else
## guessed from the sun and ambient light. Drives unit and building lights.
static func darkness_of(th: Dictionary) -> float:
	if th.has("lights"):
		return clampf(float(th["lights"]), 0.0, 1.0)
	var sun_e := float(th.get("sun_energy", 1.45))
	var amb := float(th.get("ambient", 0.55))
	return clampf((1.15 - sun_e) * 1.1 + (0.6 - amb) * 0.8, 0.0, 1.0)


func _setup_environment(th: Dictionary) -> void:
	# Tiberian Sun-style grading: filmic tone curve, heavy haze, cool fill light
	# and a vignette. Each mission's theme sets the sky, sun, fog and ambient.
	G.darkness = darkness_of(th)
	var q: int = Settings.graphics
	env = Environment.new()
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
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 2.2
	LightRig.use_cones = true
	if q >= 2 and G.darkness >= 0.5:
		LightRig.use_cones = false
		# at night the lights hang in the air: headlight and searchlight shafts,
		# glowing halos round the floodlights, lightning filling the haze
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = (th.get("fog_color", Color(0.5, 0.38, 0.27)) as Color).lerp(Color(0.8, 0.8, 0.85), 0.5)
		env.volumetric_fog_length = 70.0
		env.volumetric_fog_detail_spread = 1.5
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_ambient_inject = 0.15
		env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.97
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = th.get("saturation", 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = th.get("sun_rot", Vector3(-34, 40, 0))
	sun.light_color = th.get("sun_color", Color(1.0, 0.7, 0.42))
	sun.light_energy = th.get("sun_energy", 1.45)
	sun.shadow_enabled = q >= 1 or G.darkness < 0.5
	sun.shadow_blur = 1.5
	sun.light_volumetric_fog_energy = 0.15
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	# cool fill from the opposite side so shadows (and units standing in
	# them) aren't flat black
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55, -140, 0)
	fill.light_color = Color(0.45, 0.5, 0.7)
	fill.light_energy = 0.4
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


func _physics_process(delta: float) -> void:
	if G.game_over:
		return
	G.elapsed += delta
	for p in G.players:
		p.process(delta)
	G.separate_units(delta)
	G.update_visibility(delta)
