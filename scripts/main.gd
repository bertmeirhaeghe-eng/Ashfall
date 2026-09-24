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
	_setup_ash(cam)

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
	# Post-apocalyptic dusk: low amber sun through a dust-choked sky, cool
	# bluish shadows, heavy haze and drifting ash.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.17, 0.16)
	sm.sky_horizon_color = Color(0.62, 0.4, 0.22)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.1, 0.07, 0.05)
	sm.ground_horizon_color = Color(0.5, 0.33, 0.18)
	sm.sun_angle_max = 40.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.42, 0.52)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.38, 0.27)
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.008
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.6
	env.fog_height = 0.4
	env.fog_height_density = 0.06
	env.ssao_enabled = true
	env.ssao_intensity = 2.2
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.97
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 40, 0)
	sun.light_color = Color(1.0, 0.7, 0.42)
	sun.light_energy = 1.45
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
	vr.set_anchors_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vr.material = vm
	vl.add_child(vr)
	add_child(vl)


## Ash and embers drifting through the air around the camera.
func _setup_ash(cam: Node3D) -> void:
	var ash := GPUParticles3D.new()
	ash.amount = 700
	ash.lifetime = 9.0
	ash.preprocess = 9.0
	ash.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 6, 28)
	pm.direction = Vector3(0.6, -1.0, 0.3)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.12, -0.08, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.7, 0.65, 0.0))
	ramp.set_color(1, Color(0.75, 0.7, 0.65, 0.0))
	ramp.add_point(0.15, Color(0.7, 0.66, 0.6, 0.75))
	ramp.add_point(0.85, Color(0.55, 0.5, 0.45, 0.6))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	ash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	var dot := GradientTexture2D.new()  # soft round flake
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	qm.albedo_texture = dot
	q.material = qm
	ash.draw_pass_1 = q
	ash.position = Vector3(0, 5, 0)
	cam.add_child(ash)
	# a few glowing embers
	var embers := ash.duplicate() as GPUParticles3D
	embers.amount = 60
	var em := pm.duplicate() as ParticleProcessMaterial
	var er := Gradient.new()
	er.set_color(0, Color(1.0, 0.45, 0.1, 0.0))
	er.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	er.add_point(0.2, Color(1.0, 0.55, 0.15, 1.0))
	var ert := GradientTexture1D.new()
	ert.gradient = er
	em.color_ramp = ert
	embers.process_material = em
	var eq := QuadMesh.new()
	eq.size = Vector2(0.05, 0.05)
	var eqm := qm.duplicate() as StandardMaterial3D
	eqm.emission_enabled = true
	eqm.emission = Color(1.0, 0.45, 0.1)
	eqm.emission_energy_multiplier = 3.0
	eq.material = eqm
	embers.draw_pass_1 = eq
	cam.add_child(embers)


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
