class_name Weather
extends Node3D
## Mission weather (G.weather), set by the theme's "weather" and "storm" keys:
##   weather  "rain" | "snow" | "ash" | "spores" | "none"
##   storm    "ion"   ion storm: rain, blue-violet lightning strikes, sheet
##                    lightning in the clouds, thunder, St. Elmo's fire
##                    crackling on tall buildings and the whole battlefield
##                    lit up by each flash
##            "dry"   distant lightning and thunder only (no strikes)
## Lightning here is cosmetic; the glass storm's damaging bolts come through
## strike(). Precipitation follows the camera.

var kind := "none"
var storm := ""
var env: Environment
var sun: DirectionalLight3D
var cam: RTSCamera

var _flash := 0.0               # 0..1 how lit the scene is by the current flash
var _flash_color := Color(0.75, 0.8, 1.0)
var _flash_light: DirectionalLight3D
var _base_ambient := 0.0
var _base_fog := 0.0
var _base_sun := 0.0
var _next_bolt := 4.0
var _next_arc := 2.0
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _ground_mat: ShaderMaterial
var _pulses: Array = []         # pending flicker pulses [time, strength]
var _mist: MultiMeshInstance3D


func setup(p_kind: String, p_storm: String, p_env: Environment, p_sun: DirectionalLight3D, p_cam: RTSCamera) -> void:
	kind = p_kind
	storm = p_storm
	env = p_env
	sun = p_sun
	cam = p_cam
	_base_ambient = env.ambient_light_energy
	_base_fog = env.fog_light_energy
	_base_sun = sun.light_energy
	if storm == "ion" and (kind == "none" or kind == ""):
		kind = "rain"
	_build_precipitation()
	_build_mist()
	Settings.changed.connect(_on_settings)
	if storm != "":
		# a cold light from overhead that only shines during a flash
		_flash_light = DirectionalLight3D.new()
		_flash_light.rotation_degrees = Vector3(-75, 20, 0)
		_flash_light.light_color = _flash_color
		_flash_light.light_energy = 0.0
		_flash_light.shadow_enabled = Settings.graphics >= 2
		_flash_light.visible = false
		add_child(_flash_light)
		_next_bolt = randf_range(2.0, 5.0)
		Sfx.prepare(["thunder_near", "thunder_far"])
	if kind == "rain":
		Sfx.prepare(["rain_loop"])
		Sfx.ambience("rain", -12.0 if storm == "" else -9.0)
		_set_wet(1.0)


func _exit_tree() -> void:
	Sfx.ambience("")


func _set_wet(w: float) -> void:
	if G.map == null:
		return
	var g := G.map.get_node_or_null("Ground") as MeshInstance3D
	if g and g.material_override is ShaderMaterial:
		_ground_mat = g.material_override
		_ground_mat.set_shader_parameter("wetness", w)


# ================================================================ mist

## Soft white mist banks hovering low over the whole map, drifting with the
## wind (Options: Battlefield mist). Tinted a little by the mission's fog.
func _build_mist() -> void:
	if G.map == null:
		return
	var w := float(G.map.w)
	var h := float(G.map.h)
	var count := clampi(int(w * h / [70.0, 45.0, 30.0][Settings.graphics]), 40, 420)
	var quad := PlaneMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fx/mist.gdshader")
	var tint: Color = env.fog_light_color if env else Color(0.9, 0.9, 0.9)
	mat.set_shader_parameter("mist_color", Color(0.93, 0.94, 0.97).lerp(tint, 0.2))
	mat.set_shader_parameter("map_size", Vector2(w, h))
	mat.set_shader_parameter("wind", Vector2(randf_range(0.2, 0.45), randf_range(-0.2, 0.2)))
	mat.set_shader_parameter("glow", 0.08 + 0.12 * G.darkness)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in count:
		var p := Vector3(rng.randf_range(0, w), 0, rng.randf_range(0, h))
		p.y = G.map.height_at(p) + rng.randf_range(0.9, 3.2)
		var s := rng.randf_range(6.0, 13.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, 1, s * rng.randf_range(0.6, 1.0)))
		mm.set_instance_transform(i, Transform3D(b, p))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
	_mist = MultiMeshInstance3D.new()
	_mist.name = "Mist"
	_mist.multimesh = mm
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.custom_aabb = AABB(Vector3(-20, -10, -20), Vector3(w + 40, 40, h + 40))
	_mist.visible = Settings.mist
	add_child(_mist)


func _on_settings() -> void:
	if _mist:
		_mist.visible = Settings.mist


# ================================================================ precipitation

func _build_precipitation() -> void:
	if kind == "none" or kind == "":
		return
	var q: int = Settings.graphics
	var p := GPUParticles3D.new()
	p.name = "Precipitation"
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	var quad := QuadMesh.new()
	match kind:
		"rain":
			var heavy := storm == "ion"
			p.amount = int([900, 1800, 3000][q] * (1.4 if heavy else 1.0))
			p.lifetime = 1.1
			p.local_coords = false
			pm.direction = Vector3(0.18 if heavy else 0.08, -1, 0.05)
			pm.spread = 3.0
			pm.initial_velocity_min = 26.0
			pm.initial_velocity_max = 32.0
			pm.gravity = Vector3(0, -12, 0)
			pm.particle_flag_align_y = true
			pm.scale_min = 0.45
			pm.scale_max = 0.8
			pm.color = Color(0.62, 0.7, 0.85, 0.5)
			quad.material = Vfx.inst._mat("rain") if Vfx.inst else null
			p.position = Vector3(0, 18, 0)
			_rain = p
			_build_splashes(q, heavy)
		"snow":
			p.amount = [500, 900, 1400][q]
			p.lifetime = 5.0
			pm.direction = Vector3(0.6, -1, 0.2)
			pm.spread = 25.0
			pm.initial_velocity_min = 5.0
			pm.initial_velocity_max = 9.0
			pm.gravity = Vector3(1.5, -2, 0)
			quad.size = Vector2(0.2, 0.2)
			quad.material = _dot_material(Color(0.95, 0.97, 1.0, 0.85))
			p.position = Vector3(0, 16, 0)
		"ash":
			p.amount = [200, 350, 600][q]
			p.lifetime = 5.0
			pm.direction = Vector3(0.3, -1, 0.1)
			pm.spread = 30.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0.5, -1, 0)
			quad.size = Vector2(0.065, 0.065)
			quad.material = _dot_material(Color(0.5, 0.9, 0.55, 0.5))
			p.position = Vector3(0, 16, 0)
		_:
			p.amount = [200, 350, 600][q]
			p.lifetime = 5.0
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 60.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			pm.gravity = Vector3(0, 0.2, 0)
			pm.emission_box_extents = Vector3(30, 6, 30)
			quad.size = Vector2(0.07, 0.07)
			quad.material = _dot_material(Color(0.4, 1.0, 0.6, 0.7), 2.0)
			p.position = Vector3(0, 2, 0)
	if kind != "rain":
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.5
		pm.turbulence_noise_scale = 6.0
	p.process_material = pm
	p.draw_pass_1 = quad
	cam.add_child(p)
	if kind == "ash":
		# glowing embers drifting through the ash
		var embers := p.duplicate() as GPUParticles3D
		embers.amount = [40, 60, 100][q]
		var eq := QuadMesh.new()
		eq.size = Vector2(0.06, 0.06)
		eq.material = _dot_material(Color(1.0, 0.55, 0.15, 0.9), 3.0)
		embers.draw_pass_1 = eq
		cam.add_child(embers)


## Little crowns of water where the rain hits the ground around the camera.
func _build_splashes(q: int, heavy: bool) -> void:
	if q == 0 or Vfx.inst == null:
		return
	var s := GPUParticles3D.new()
	s.name = "Splashes"
	s.amount = int((300 if q == 1 else 600) * (1.5 if heavy else 1.0))
	s.lifetime = 0.3
	s.local_coords = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.visibility_aabb = AABB(Vector3(-30, -4, -30), Vector3(60, 8, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.05, 24)
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, -12, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.08
	pm.scale_max = 0.16
	pm.color = Color(0.7, 0.78, 0.9, 0.55)
	s.process_material = pm
	var quad := QuadMesh.new()
	quad.material = Vfx.inst._mat("rain")
	s.draw_pass_1 = quad
	s.position = Vector3(0, 0.08, 0)
	cam.add_child(s)
	_splash = s


func _dot_material(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	m.albedo_texture = _soft_dot()
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = glow
	return m


static func _soft_dot() -> Texture2D:
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


# ================================================================ lightning

## A lightning strike at `pos` (the glass storm's bolts, scripted strikes):
## the bolt, a flash over the whole battlefield and thunder.
func strike(pos: Vector3, color := Color(0.6, 0.75, 1.0)) -> void:
	if Vfx.inst and Vfx.near_camera(pos, 20.0):
		Vfx.inst.lightning(pos, color)
		if cam:
			cam.shake(0.25, pos)
	flash(color, 1.0 if Vfx.near_camera(pos, 20.0) else 0.5)
	Sfx.thunder(pos)


## Lights up the scene: a quick double or triple flicker, as real lightning does.
func flash(color: Color, strength := 1.0) -> void:
	_flash_color = color.lerp(Color(0.85, 0.9, 1.0), 0.5)
	var t := 0.0
	for i in randi_range(2, 3):
		_pulses.append([t, strength * randf_range(0.6, 1.0)])
		t += randf_range(0.06, 0.16)


func _process(delta: float) -> void:
	# flicker pulses decay into the scene lighting
	for i in range(_pulses.size() - 1, -1, -1):
		_pulses[i][0] = float(_pulses[i][0]) - delta
		if float(_pulses[i][0]) <= 0.0:
			_flash = maxf(_flash, float(_pulses[i][1]))
			_pulses.remove_at(i)
	_flash = maxf(0.0, _flash - delta * (3.5 + _flash * 2.0))
	if env:
		env.ambient_light_energy = _base_ambient + _flash * 1.4
		env.fog_light_energy = _base_fog + _flash * 1.8
	if _flash_light:
		_flash_light.visible = _flash > 0.01
		_flash_light.light_color = _flash_color
		_flash_light.light_energy = _flash * 2.6
	if _rain:
		_rain.set_instance_shader_parameter("tint", Color(1, 1, 1, 1).lerp(Color(3, 3, 3.5, 1), _flash))
	if storm == "" or G.game_over:
		return
	_next_bolt -= delta
	if _next_bolt <= 0.0:
		_next_bolt = randf_range(3.0, 8.0) if storm == "ion" else randf_range(7.0, 16.0)
		_random_bolt()
	if storm == "ion":
		_next_arc -= delta
		if _next_arc <= 0.0:
			_next_arc = randf_range(1.2, 3.5)
			_st_elmo()


func _storm_color() -> Color:
	var c := [Color(0.55, 0.65, 1.0), Color(0.7, 0.55, 1.0), Color(0.5, 0.85, 1.0), Color(0.85, 0.8, 1.0)]
	return c[randi() % c.size()]


func _random_bolt() -> void:
	var color := _storm_color()
	if storm == "dry" or randf() < 0.35:
		# sheet lightning inside the clouds: the sky lights up, thunder rolls in later
		flash(color, randf_range(0.35, 0.7))
		var far := cam.position + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
		Sfx.thunder(far + Vector3(0, 0, 70))
		return
	# a ground strike somewhere on screen
	var r := cam.zoom * 0.9
	var p := cam.position + Vector3(randf_range(-r, r), 0, randf_range(-r * 0.8, r * 0.5))
	if G.map:
		p.x = clampf(p.x, 1.0, G.map.w - 1.0)
		p.z = clampf(p.z, 1.0, G.map.h - 1.0)
		p.y = G.map.height_at(p)
	# lightning likes tall things
	for e in G.entities:
		if e is Structure and e.alive and G.flat_dist(e.position, p) < 5.0 and float(e.bar_height) > 1.4:
			p = e.position + Vector3(0, float(e.bar_height), 0)
			break
	strike(p, color)


## Ion discharge: little arcs crackling between the tops of tall structures.
func _st_elmo() -> void:
	if Vfx.inst == null:
		return
	var tall: Array = []
	for e in G.entities:
		if e is Structure and e.alive and not e.def.get("decor", false) and Vfx.near_camera(e.position):
			tall.append(e)
	if tall.is_empty():
		return
	var s: Structure = tall[randi() % tall.size()]
	var top := s.position + Vector3(randf_range(-0.4, 0.4) * s.size.x, float(s.bar_height) + 0.2, randf_range(-0.4, 0.4) * s.size.y)
	var col := _storm_color()
	var prev := top
	for i in randi_range(2, 4):
		var nxt := prev + Vector3(randf_range(-0.7, 0.7), randf_range(-0.2, 0.5), randf_range(-0.7, 0.7))
		Vfx.inst.beam(prev, nxt, col, 0.025, randf_range(0.08, 0.2))
		prev = nxt
	Vfx.inst.burst("sparks", top, Vector3.UP, 0.6, Color(col.r * 1.4, col.g * 1.4, col.b * 1.6, 1.0))
	Vfx.inst.flash_light(top, col, 2.5, 4.0, 0.2, true)
