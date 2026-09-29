class_name Vfx
extends Node3D
## Particle and light effects (one per mission, Vfx.inst): muzzle flashes, bullet
## sparks, fireballs, smoke columns, debris, shockwaves, scorch marks, energy
## beams, lightning bolts and short-lived flash lights.
##
## Everything is pooled: GPU particle emitters are restarted in place, flash
## lights / muzzle flashes / beams / scorch decals are reused round-robin, so
## a big battle never allocates nodes per shot. Effects far from the camera
## are skipped. The particle shaders live in shaders/fx/.

static var inst: Vfx = null

## Emitters per effect kind (round-robin).
const POOL := {
	"sparks": 24, "spark_burst": 10, "fireball": 12, "smoke": 14, "smoke_column": 8, "dust": 10,
	"debris": 10, "muzzle_smoke": 16, "flame_jet": 8, "embers": 8, "impact_dust": 16, "ion_sparks": 8,
	"splash": 1,
}

var quality := 2                 # Settings.graphics: 0 low, 1 medium, 2 high
var _pools := {}                 # kind -> {"nodes": Array, "next": int}
var _cfg := {}                   # kind -> emitter config
var _lights: Array = []          # [{"l": OmniLight3D, "t": float, "life": float, "e": float, "flicker": bool}]
var _flashes: Array = []         # [{"n": Node3D, "mis": Array, "t": float, "life": float}]
var _beams: Array = []           # [{"mi": MeshInstance3D, "t": float, "life": float}]
var _waves: Array = []           # [{"mi": MeshInstance3D, "t": float, "life": float, "size": float}]
var _decals: Array = []          # [{"d": Decal, "t": float, "life": float, "heat": float}]
var _bolts: Array = []           # [{"mi": MeshInstance3D, "t": float, "life": float, "strikes": Array}]
var _next_light := 0
var _next_flash := 0
var _next_beam := 0
var _next_wave := 0
var _next_decal := 0
var _mats := {}
var _petal_mesh: ArrayMesh
var _quad: QuadMesh
var _scorch_tex: Texture2D
var _ember_tex: Texture2D


func _ready() -> void:
	inst = self
	quality = Settings.graphics
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_define_effects()
	var nl: int = [8, 16, 28][quality]
	for i in nl:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		l.omni_attenuation = 1.6
		l.light_specular = 0.3
		add_child(l)
		_lights.append({"l": l, "t": 1.0, "life": 0.0, "e": 0.0, "flicker": false})
	for i in 24:
		_flashes.append(_make_flash())
	for i in 24:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		mi.material_override = _mat("beam")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = false
		add_child(mi)
		_beams.append({"mi": mi, "t": 1.0, "life": 0.0})
	for i in 10:
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		w.mesh = pm
		w.material_override = _mat("shockwave")
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.visible = false
		add_child(w)
		_waves.append({"mi": w, "t": 1.0, "life": 0.0, "size": 1.0})
	var nd: int = [10, 24, 40][quality]
	for i in nd:
		var d := Decal.new()
		d.texture_albedo = _scorch_texture()
		d.texture_emission = _ember_texture()
		d.cull_mask = 2            # only the ground (map_grid puts it on layer 2)
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		d.normal_fade = 0.3
		d.visible = false
		add_child(d)
		_decals.append({"d": d, "t": 1.0, "life": 0.0, "heat": 0.0})


func _exit_tree() -> void:
	if inst == self:
		inst = null
	LightRig.clear_cache()


# ================================================================ helpers

## Is this point near enough to the camera to be worth drawing effects for?
static func near_camera(p: Vector3, margin := 6.0) -> bool:
	if G.camera == null:
		return true
	var cp: Vector3 = G.camera.position
	return Vector2(p.x - cp.x, p.z - cp.z).length() < G.camera.zoom * 1.35 + margin


func _mat(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	match kind:
		"fire":
			m.shader = load("res://shaders/fx/fire.gdshader")
		"fire_soft":
			m.shader = load("res://shaders/fx/fire.gdshader")
			m.set_shader_parameter("intensity", 2.2)
			m.set_shader_parameter("softness", 0.5)
			m.set_shader_parameter("noise_scale", 2.4)
		"smoke":
			m.shader = load("res://shaders/fx/smoke.gdshader")
		"smoke_hot":
			m.shader = load("res://shaders/fx/smoke.gdshader")
			m.set_shader_parameter("emission_from_color", 2.5)
		"dust":
			m.shader = load("res://shaders/fx/smoke.gdshader")
			m.set_shader_parameter("noise_scale", 3.0)
			m.set_shader_parameter("density", 0.8)
		"spark":
			m.shader = load("res://shaders/fx/spark.gdshader")
		"spark_fat":
			m.shader = load("res://shaders/fx/spark.gdshader")
			m.set_shader_parameter("width", 0.06)
			m.set_shader_parameter("intensity", 3.0)
		"rain":
			m.shader = load("res://shaders/fx/spark.gdshader")
			m.set_shader_parameter("width", 0.012)
			m.set_shader_parameter("intensity", 0.9)
		"beam":
			m.shader = load("res://shaders/fx/energy_beam.gdshader")
		"bolt":
			m.shader = load("res://shaders/fx/energy_beam.gdshader")
			m.set_shader_parameter("axis_billboard", false)
			m.set_shader_parameter("intensity", 5.0)
			m.set_shader_parameter("core_width", 0.22)
			m.set_shader_parameter("crawl", 0.3)
		"petals":
			m.shader = load("res://shaders/fx/muzzle_flash.gdshader")
		"star":
			m.shader = load("res://shaders/fx/muzzle_flash.gdshader")
			m.set_shader_parameter("star", true)
			m.set_shader_parameter("intensity", 4.0)
		"shockwave":
			m.shader = load("res://shaders/fx/shockwave.gdshader")
	# draw order among transparent effects: dust, smoke, then fire and sparks on top
	if kind.begins_with("fire") or kind == "petals" or kind == "star":
		m.render_priority = 2
	elif kind.begins_with("spark") or kind == "beam" or kind == "bolt":
		m.render_priority = 3
	elif kind == "dust":
		m.render_priority = -1
	_mats[kind] = m
	return m


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	return t


static func _ramp(colors: Array, offsets: Array = []) -> GradientTexture1D:
	var g := Gradient.new()
	var offs: PackedFloat32Array = PackedFloat32Array()
	var cols: PackedColorArray = PackedColorArray()
	for i in colors.size():
		offs.append(offsets[i] if i < offsets.size() else float(i) / maxf(1.0, colors.size() - 1.0))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


# ================================================================ emitters

## Effect recipes. "dir" is along the emitter's +Y, which burst() points
## where the effect should go (up for explosions, back along a shot ...).
func _define_effects() -> void:
	var hot := Color(1.0, 0.85, 0.5)
	_cfg = {
		# bullet ricochets: fast, short, falling
		"sparks": {"mat": "spark", "amount": 10, "life": 0.45, "dir": Vector3.UP, "spread": 70.0,
			"vel": [3.0, 8.0], "gravity": Vector3(0, -14, 0), "damp": [2.0, 4.0], "scale": [0.12, 0.3],
			"align": true, "ramp": [Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.2, 0.05, 0.0)],
			"scale_curve": [[0.0, 1.0], [1.0, 0.3]], "aabb": 5.0},
		# explosion shrapnel: bigger, longer, bouncing debris sparks
		"spark_burst": {"mat": "spark", "amount": 36, "life": 1.0, "dir": Vector3.UP, "spread": 95.0,
			"vel": [4.0, 13.0], "gravity": Vector3(0, -12, 0), "damp": [0.5, 1.5], "scale": [0.15, 0.45],
			"align": true, "radius": 0.2, "ramp": [Color(1.0, 0.95, 0.75, 1.0), hot, Color(1.0, 0.35, 0.05, 0.9), Color(0.5, 0.1, 0.0, 0.0)],
			"scale_curve": [[0.0, 1.0], [1.0, 0.2]], "aabb": 12.0},
		# fireball: billowing flame balls that swell, rise and burn out
		"fireball": {"mat": "fire", "amount": 14, "life": 0.9, "dir": Vector3.UP, "spread": 180.0,
			"vel": [0.8, 3.0], "gravity": Vector3(0, 2.5, 0), "damp": [3.0, 5.0], "scale": [0.9, 1.6],
			"radius": 0.35, "angle": true, "ramp": [Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.55, 0.15, 1.0), Color(0.7, 0.18, 0.04, 0.8), Color(0.2, 0.04, 0.0, 0.0)],
			"offsets": [0.0, 0.25, 0.6, 1.0], "scale_curve": [[0.0, 0.45], [0.25, 1.0], [1.0, 1.35]], "aabb": 8.0},
		# thick dark smoke that rolls upward and spreads
		"smoke": {"mat": "smoke_hot", "amount": 14, "life": 3.2, "dir": Vector3.UP, "spread": 35.0,
			"vel": [0.6, 1.8], "gravity": Vector3(0.25, 0.9, 0.1), "damp": [0.6, 1.2], "scale": [0.9, 1.6],
			"radius": 0.45, "angle": true, "spin": 25.0, "ramp": [Color(0.18, 0.15, 0.13, 0.0), Color(0.16, 0.14, 0.13, 0.85), Color(0.22, 0.21, 0.2, 0.55), Color(0.3, 0.29, 0.28, 0.0)],
			"offsets": [0.0, 0.08, 0.5, 1.0], "scale_curve": [[0.0, 0.5], [1.0, 2.6]], "aabb": 14.0},
		# long-lived pillar over a destroyed building
		"smoke_column": {"mat": "smoke", "amount": 30, "life": 7.0, "dir": Vector3.UP, "spread": 12.0,
			"vel": [1.0, 2.2], "gravity": Vector3(0.4, 0.5, 0.15), "damp": [0.3, 0.6], "scale": [1.0, 1.8],
			"radius": 0.8, "angle": true, "spin": 15.0, "explosive": 0.0, "ramp": [Color(0.1, 0.09, 0.08, 0.0), Color(0.12, 0.11, 0.1, 0.8), Color(0.25, 0.24, 0.23, 0.4), Color(0.3, 0.3, 0.3, 0.0)],
			"offsets": [0.0, 0.06, 0.55, 1.0], "scale_curve": [[0.0, 0.6], [1.0, 3.5]], "aabb": 24.0, "emit_time": 5.0},
		# ground dust ring kicked out by blasts
		"dust": {"mat": "dust", "amount": 16, "life": 1.8, "dir": Vector3.UP, "spread": 90.0, "flat": 0.85,
			"vel": [2.5, 5.0], "gravity": Vector3(0, 0.3, 0), "damp": [2.5, 3.5], "scale": [0.8, 1.4],
			"radius": 0.3, "angle": true, "ramp": [Color(0.5, 0.42, 0.33, 0.0), Color(0.45, 0.38, 0.3, 0.42), Color(0.45, 0.4, 0.34, 0.0)],
			"offsets": [0.0, 0.15, 1.0], "scale_curve": [[0.0, 0.4], [1.0, 1.5]], "aabb": 10.0},
		# glowing chunks arcing out of an explosion
		"debris": {"mat": "spark_fat", "amount": 14, "life": 1.6, "dir": Vector3.UP, "spread": 55.0,
			"vel": [4.0, 9.0], "gravity": Vector3(0, -15, 0), "damp": [0.0, 0.3], "scale": [0.1, 0.2],
			"align": true, "ramp": [Color(1.0, 0.7, 0.3, 1.0), Color(0.9, 0.3, 0.05, 1.0), Color(0.3, 0.08, 0.02, 0.0)],
			"aabb": 12.0},
		# a whiff of gun smoke drifting from the barrel
		"muzzle_smoke": {"mat": "smoke", "amount": 5, "life": 1.1, "dir": Vector3.UP, "spread": 20.0,
			"vel": [0.8, 2.2], "gravity": Vector3(0, 0.6, 0), "damp": [2.0, 3.0], "scale": [0.25, 0.45],
			"angle": true, "ramp": [Color(0.55, 0.52, 0.5, 0.0), Color(0.5, 0.48, 0.46, 0.45), Color(0.6, 0.58, 0.56, 0.0)],
			"offsets": [0.0, 0.1, 1.0], "scale_curve": [[0.0, 0.4], [1.0, 1.8]], "aabb": 5.0},
		# flamethrower tongue
		"flame_jet": {"mat": "fire_soft", "amount": 18, "life": 0.5, "dir": Vector3.UP, "spread": 7.0,
			"vel": [6.0, 9.5], "gravity": Vector3(0, 1.5, 0), "damp": [4.0, 7.0], "scale": [0.3, 0.55],
			"angle": true, "explosive": 0.7, "ramp": [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.45, 0.1, 1.0), Color(0.5, 0.1, 0.02, 0.0)],
			"scale_curve": [[0.0, 0.3], [1.0, 1.6]], "aabb": 8.0},
		# drifting glowing embers after fire
		"embers": {"mat": "spark", "amount": 16, "life": 2.2, "dir": Vector3.UP, "spread": 50.0,
			"vel": [1.0, 3.0], "gravity": Vector3(0, 0.8, 0), "damp": [0.8, 1.5], "scale": [0.06, 0.12],
			"align": true, "radius": 0.5, "turb": 1.2, "ramp": [Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.4, 0.08, 0.8), Color(0.6, 0.1, 0.0, 0.0)],
			"aabb": 10.0},
		# puff of dirt where a bullet hits the ground
		"impact_dust": {"mat": "dust", "amount": 4, "life": 0.9, "dir": Vector3.UP, "spread": 30.0,
			"vel": [0.8, 2.0], "gravity": Vector3(0, -1.0, 0), "damp": [2.0, 3.0], "scale": [0.2, 0.35],
			"angle": true, "ramp": [Color(0.45, 0.38, 0.3, 0.0), Color(0.42, 0.36, 0.28, 0.6), Color(0.45, 0.4, 0.34, 0.0)],
			"offsets": [0.0, 0.1, 1.0], "scale_curve": [[0.0, 0.5], [1.0, 1.7]], "aabb": 4.0},
		# ion storm discharge crackle
		"ion_sparks": {"mat": "spark", "amount": 28, "life": 0.7, "dir": Vector3.UP, "spread": 90.0,
			"vel": [3.0, 10.0], "gravity": Vector3(0, -6, 0), "damp": [2.0, 4.0], "scale": [0.2, 0.5],
			"align": true, "radius": 0.3, "ramp": [Color(1.0, 1.0, 1.0, 1.0), Color(0.6, 0.8, 1.0, 1.0), Color(0.3, 0.3, 1.0, 0.0)],
			"aabb": 10.0},
	}


func _build_emitter(kind: String) -> GPUParticles3D:
	var c: Dictionary = _cfg[kind]
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.local_coords = false
	p.amount = int(c["amount"])
	p.lifetime = float(c["life"])
	p.explosiveness = float(c.get("explosive", 1.0))
	p.randomness = 0.3
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount_ratio = [0.5, 0.8, 1.0][quality]
	var a := float(c.get("aabb", 6.0))
	p.visibility_aabb = AABB(Vector3(-a, -a * 0.5, -a), Vector3(a * 2, a * 2, a * 2))
	var pm := ParticleProcessMaterial.new()
	pm.direction = c.get("dir", Vector3.UP)
	pm.spread = float(c.get("spread", 45.0))
	pm.flatness = float(c.get("flat", 0.0))
	var v: Array = c.get("vel", [1.0, 2.0])
	pm.initial_velocity_min = v[0]
	pm.initial_velocity_max = v[1]
	pm.gravity = c.get("gravity", Vector3.ZERO)
	var d: Array = c.get("damp", [0.0, 0.0])
	pm.damping_min = d[0]
	pm.damping_max = d[1]
	var s: Array = c.get("scale", [1.0, 1.0])
	pm.scale_min = s[0]
	pm.scale_max = s[1]
	if c.has("radius"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = float(c["radius"])
	if c.get("align", false):
		pm.particle_flag_align_y = true
	if c.get("angle", false):
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	if c.has("spin"):
		pm.angular_velocity_min = -float(c["spin"])
		pm.angular_velocity_max = float(c["spin"])
	if c.has("turb"):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(c["turb"])
		pm.turbulence_noise_scale = 3.0
	pm.color_ramp = _ramp(c["ramp"], c.get("offsets", []))
	if c.has("scale_curve"):
		pm.scale_curve = _curve(c["scale_curve"])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _mat(c["mat"])
	p.draw_pass_1 = q
	add_child(p)
	return p


func _take(kind: String) -> GPUParticles3D:
	if not _cfg.has(kind):
		return null
	if not _pools.has(kind):
		var n := int(POOL.get(kind, 8))
		if quality == 0:
			n = maxi(2, n / 2)
		_pools[kind] = {"nodes": [], "next": 0, "size": n}
	var pool: Dictionary = _pools[kind]
	var nodes: Array = pool["nodes"]
	var p: GPUParticles3D
	if nodes.size() < int(pool["size"]):
		p = _build_emitter(kind)
		nodes.append(p)
	else:
		p = nodes[pool["next"]]
		pool["next"] = (int(pool["next"]) + 1) % nodes.size()
	return p


## Fires a one-shot particle effect. `dir` is where it sprays; `size` scales
## the whole effect; `tint` multiplies the colour ramp.
func burst(kind: String, pos: Vector3, dir := Vector3.UP, size := 1.0, tint := Color(1, 1, 1, 1)) -> void:
	var p := _take(kind)
	if p == null:
		return
	var up := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var b := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	p.global_transform = Transform3D(b.scaled(Vector3.ONE * size), pos)
	p.set_instance_shader_parameter("tint", tint)
	p.restart()


## A continuous emitter that follows `parent` (rocket trails, burning wrecks).
func make_trail(kind: String, parent: Node3D, amount := 20, life := 0.8) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var base: Dictionary = {
		"rocket": {"mat": "smoke", "vel": [0.2, 0.6], "gravity": Vector3(0, 0.5, 0), "scale": [0.18, 0.3], "spread": 180.0,
			"ramp": [Color(1.0, 0.7, 0.4, 0.0), Color(0.55, 0.52, 0.5, 0.6), Color(0.6, 0.58, 0.56, 0.0)], "offsets": [0.0, 0.08, 1.0],
			"scale_curve": [[0.0, 0.4], [1.0, 2.0]]},
		"rocket_fire": {"mat": "fire", "vel": [0.0, 0.2], "gravity": Vector3.ZERO, "scale": [0.2, 0.3], "spread": 180.0,
			"ramp": [Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0)], "scale_curve": [[0.0, 1.0], [1.0, 0.2]]},
		"burn_smoke": {"mat": "smoke", "vel": [0.6, 1.4], "gravity": Vector3(0.3, 0.8, 0.1), "scale": [0.5, 0.9], "spread": 15.0,
			"ramp": [Color(0.12, 0.1, 0.09, 0.0), Color(0.12, 0.11, 0.1, 0.75), Color(0.25, 0.24, 0.23, 0.0)], "offsets": [0.0, 0.1, 1.0],
			"scale_curve": [[0.0, 0.5], [1.0, 2.5]]},
		"burn_fire": {"mat": "fire_soft", "vel": [0.4, 1.2], "gravity": Vector3(0, 1.5, 0), "scale": [0.35, 0.6], "spread": 20.0,
			"ramp": [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.4, 0.08, 0.9), Color(0.4, 0.08, 0.0, 0.0)],
			"scale_curve": [[0.0, 0.6], [0.3, 1.0], [1.0, 0.3]], "radius": 0.25},
		"engine": {"mat": "fire_soft", "vel": [0.3, 0.8], "gravity": Vector3(0, -0.5, 0), "scale": [0.12, 0.2], "spread": 25.0,
			"ramp": [Color(0.6, 0.85, 1.0, 1.0), Color(0.2, 0.4, 1.0, 0.0)], "scale_curve": [[0.0, 1.0], [1.0, 0.2]]},
	}.get(kind, {})
	if base.is_empty():
		return null
	p.amount = maxi(4, int(amount * [0.5, 0.8, 1.0][quality]))
	p.lifetime = life
	p.local_coords = false
	p.explosiveness = 0.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = float(base["spread"])
	pm.initial_velocity_min = base["vel"][0]
	pm.initial_velocity_max = base["vel"][1]
	pm.gravity = base["gravity"]
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = base["scale"][0]
	pm.scale_max = base["scale"][1]
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	if base.has("radius"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = float(base["radius"])
	pm.color_ramp = _ramp(base["ramp"], base.get("offsets", []))
	pm.scale_curve = _curve(base["scale_curve"])
	p.process_material = pm
	var q := QuadMesh.new()
	q.material = _mat(base["mat"])
	p.draw_pass_1 = q
	parent.add_child(p)
	p.emitting = true
	return p


## Detaches a trail so its particles live out their life after the parent is gone.
func release_trail(p: GPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	var xf := p.global_transform
	if p.get_parent():
		p.get_parent().remove_child(p)
	add_child(p)
	p.global_transform = xf
	p.emitting = false
	get_tree().create_timer(p.lifetime + 0.2, false).timeout.connect(p.queue_free)


# ================================================================ lights

## A short burst of light (muzzle flash, explosion, lightning).
func flash_light(pos: Vector3, color: Color, energy: float, light_range: float, life: float, flicker := false) -> void:
	if _lights.is_empty():
		return
	# take a free light, or the one closest to finishing
	var best := -1
	var best_left := INF
	for k in _lights.size():
		var i := (_next_light + k) % _lights.size()
		var e: Dictionary = _lights[i]
		var left: float = float(e["life"]) - float(e["t"])
		if left <= 0.0:
			best = i
			break
		if left < best_left and float(e["e"]) <= energy * 1.5:
			best_left = left
			best = i
	if best < 0:
		return
	_next_light = (best + 1) % _lights.size()
	var en: Dictionary = _lights[best]
	var l: OmniLight3D = en["l"]
	l.global_position = pos
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	l.visible = true
	en["t"] = 0.0
	en["life"] = life
	en["e"] = energy
	en["flicker"] = flicker


# ================================================================ muzzle flashes

func _petals() -> ArrayMesh:
	if _petal_mesh:
		return _petal_mesh
	# two crossed quads along +Z (horizontal and vertical), UV.y = 0 at the muzzle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in 2:
		var side := Vector3(0.5, 0, 0) if plane == 0 else Vector3(0, 0.5, 0)
		var v := [-side, side, side + Vector3(0, 0, 1), -side + Vector3(0, 0, 1)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[i])
	_petal_mesh = st.commit()
	return _petal_mesh


func _make_flash() -> Dictionary:
	var n := Node3D.new()
	n.visible = false
	add_child(n)
	var petals := MeshInstance3D.new()
	petals.mesh = _petals()
	petals.material_override = _mat("petals")
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(petals)
	var star := MeshInstance3D.new()
	star.mesh = _quad
	star.material_override = _mat("star")
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.scale = Vector3.ONE * 0.8
	n.add_child(star)
	return {"n": n, "mis": [petals, star], "t": 1.0, "life": 0.0}


func muzzle_flash(pos: Vector3, dir: Vector3, size: float, tint: Color, life := 0.07) -> void:
	var f: Dictionary = _flashes[_next_flash]
	_next_flash = (_next_flash + 1) % _flashes.size()
	var n: Node3D = f["n"]
	var fwd := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(-fwd, up)    # looking_at points -Z; the petals run along +Z
	b = b.rotated(fwd, randf() * TAU)
	n.global_transform = Transform3D(b * Basis.from_scale(Vector3(size * 0.6, size * 0.6, size * randf_range(0.8, 1.3))), pos)
	n.visible = true
	var seed_v := randf() * 100.0
	for mi in f["mis"]:
		(mi as MeshInstance3D).set_instance_shader_parameter("seed", seed_v)
		(mi as MeshInstance3D).set_instance_shader_parameter("tint", tint)
		(mi as MeshInstance3D).set_instance_shader_parameter("fade", 1.0)
	f["t"] = 0.0
	f["life"] = life


# ================================================================ beams, rings, scorch

## Camera-facing energy ribbon from a to b.
func beam(a: Vector3, b: Vector3, color: Color, width: float, life: float) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var e: Dictionary = _beams[_next_beam]
	_next_beam = (_next_beam + 1) % _beams.size()
	var mi: MeshInstance3D = e["mi"]
	var axis := (b - a)
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized() * width * 5.0     # the corona is wider than the core
	var third := side.cross(axis).normalized() * 0.01
	mi.global_transform = Transform3D(Basis(side, axis, third), (a + b) * 0.5)
	mi.set_instance_shader_parameter("beam_color", color)
	mi.set_instance_shader_parameter("fade", 1.0)
	mi.set_instance_shader_parameter("seed", randf() * 50.0)
	mi.visible = true
	e["t"] = 0.0
	e["life"] = life


## Expanding ring on the ground.
func shockwave(pos: Vector3, radius: float, color: Color, life := 0.6) -> void:
	var e: Dictionary = _waves[_next_wave]
	_next_wave = (_next_wave + 1) % _waves.size()
	var mi: MeshInstance3D = e["mi"]
	var gy: float = G.map.height_at(pos) if G.map else pos.y
	mi.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1, radius)), Vector3(pos.x, gy + 0.12, pos.z))
	mi.set_instance_shader_parameter("ring_color", color)
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.visible = true
	e["t"] = 0.0
	e["life"] = life


## Burn mark on the ground that glows, cools and fades.
func scorch(pos: Vector3, radius: float, life := 25.0, heat := 1.0) -> void:
	if _decals.is_empty():
		return
	var e: Dictionary = _decals[_next_decal]
	_next_decal = (_next_decal + 1) % _decals.size()
	var d: Decal = e["d"]
	d.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	d.global_position = Vector3(pos.x, (G.map.height_at(pos) if G.map else pos.y), pos.z)
	d.rotation = Vector3(0, randf() * TAU, 0)
	d.modulate = Color(1, 1, 1, 1)
	d.emission_energy = heat * 3.0
	d.visible = true
	e["t"] = 0.0
	e["life"] = life
	e["heat"] = heat


func _scorch_texture() -> Texture2D:
	if _scorch_tex:
		return _scorch_tex
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 404
	n.frequency = 0.045
	n.fractal_octaves = 4
	for y in sz:
		for x in sz:
			var c := Vector2(x, y) / (sz - 1) * 2.0 - Vector2.ONE
			var r := c.length()
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - smoothstep(0.35, 1.0, r + (v - 0.5) * 0.7)) * 1.1, 0.0, 1.0)
			var g := 0.03 + 0.06 * v
			img.set_pixel(x, y, Color(g, g * 0.9, g * 0.8, a * 0.9))
	img.generate_mipmaps()
	_scorch_tex = ImageTexture.create_from_image(img)
	return _scorch_tex


func _ember_texture() -> Texture2D:
	if _ember_tex:
		return _ember_tex
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 77
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.09
	for y in sz:
		for x in sz:
			var c := Vector2(x, y) / (sz - 1) * 2.0 - Vector2.ONE
			var r := c.length()
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var k := smoothstep(0.55, 0.85, v) * (1.0 - smoothstep(0.2, 0.75, r))
			img.set_pixel(x, y, Color(1.0 * k, 0.38 * k, 0.08 * k, 1.0))
	img.generate_mipmaps()
	_ember_tex = ImageTexture.create_from_image(img)
	return _ember_tex


# ================================================================ lightning

## Branching lightning bolt from the sky to `pos`. Strikes flicker a few times.
func lightning(pos: Vector3, color: Color, height := 22.0, width := 0.11) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else pos + Vector3(0, 30, 20)
	var top := pos + Vector3(randf_range(-4, 4), height, randf_range(-4, 4))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _bolt_path(top, pos, 14, 1.4)
	_ribbon(st, main, width, cam_pos)
	# forks peel off the main channel and die out in the air
	var forks := randi_range(2, 4)
	for f in forks:
		var i := randi_range(2, main.size() - 5)
		var a: Vector3 = main[i]
		var dir: Vector3 = ((main[i + 1] as Vector3) - a).normalized()
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-0.2, 0.3), randf_range(-1, 1)) * 0.9).normalized()
		var b := a + dir * randf_range(3.0, 7.0)
		_ribbon(st, _bolt_path(a, b, 7, 0.8), width * 0.55, cam_pos)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat("bolt")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("beam_color", color)
	mi.set_instance_shader_parameter("seed", randf() * 50.0)
	add_child(mi)
	# a strike is a few quick pulses of the return stroke
	var strikes: Array = [0.0, randf_range(0.07, 0.12), randf_range(0.18, 0.3)]
	if randf() < 0.5:
		strikes.append(randf_range(0.35, 0.45))
	_bolts.append({"mi": mi, "t": 0.0, "life": 0.6, "strikes": strikes})
	# ground impact
	flash_light(pos + Vector3(0, 2.5, 0), color.lerp(Color.WHITE, 0.4), 14.0, 22.0, 0.55, true)
	burst("ion_sparks", pos + Vector3(0, 0.2, 0), Vector3.UP, 1.2, Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, 1.0))
	burst("dust", pos, Vector3.UP, 1.0)
	burst("smoke", pos + Vector3(0, 0.3, 0), Vector3.UP, 0.7)
	shockwave(pos, 3.5, color.lerp(Color.WHITE, 0.5), 0.5)
	scorch(pos, 1.4, 30.0, 1.0)


func _bolt_path(a: Vector3, b: Vector3, segments: int, jag: float) -> Array:
	var pts: Array = [a]
	var len := a.distance_to(b)
	for i in range(1, segments):
		var k := float(i) / segments
		var off := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * jag * (len / 12.0) * sin(k * PI)
		pts.append(a.lerp(b, k) + off)
	pts.append(b)
	return pts


func _ribbon(st: SurfaceTool, pts: Array, width: float, cam_pos: Vector3) -> void:
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var axis := (p1 - p0).normalized()
		var side := axis.cross((cam_pos - p0).normalized()).normalized()
		var w0 := width * lerpf(1.0, 0.6, float(i) / n) * 3.0
		var w1 := width * lerpf(1.0, 0.6, float(i + 1) / n) * 3.0
		var v0 := float(i) / (n - 1)
		var v1 := float(i + 1) / (n - 1)
		var quad := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
		var uv := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[j])
			st.add_vertex(quad[j])


# ================================================================ composite effects

## Shot leaving a barrel: flash petals, a star, a light and a wisp of smoke.
func muzzle(from: Vector3, dir: Vector3, kind: String, damage: float, tint: Color) -> void:
	if not near_camera(from):
		return
	match kind:
		"tracer":
			var heavy := damage >= 20.0
			muzzle_flash(from, dir, 0.5 if heavy else 0.34, Color(1.0, 0.62, 0.22), 0.06)
			flash_light(from + dir * 0.2, Color(1.0, 0.72, 0.4), 2.2 if heavy else 1.4, 3.8 if heavy else 2.8, 0.07)
			if heavy and quality > 0 and randf() < 0.5:
				burst("muzzle_smoke", from + dir * 0.2, dir + Vector3.UP * 0.6, 0.7)
		"shell":
			var big := damage >= 60.0
			var s := 1.3 if big else 0.95
			muzzle_flash(from, dir, s, Color(1.0, 0.55, 0.18), 0.1)
			flash_light(from + dir * 0.4, Color(1.0, 0.65, 0.35), 5.0 if big else 3.5, 7.0 if big else 5.0, 0.13)
			burst("muzzle_smoke", from + dir * 0.3, dir + Vector3.UP * 0.4, 1.6 if big else 1.2)
			burst("sparks", from + dir * 0.2, dir, 0.6)
			if big and G.camera:
				G.camera.shake(0.08, from)
		"rocket":
			muzzle_flash(from, dir, 0.55, Color(1.0, 0.5, 0.15), 0.08)
			flash_light(from, Color(1.0, 0.6, 0.3), 3.0, 4.5, 0.12)
			burst("muzzle_smoke", from - dir * 0.3, -dir + Vector3.UP * 0.3, 1.3)
		"laser":
			muzzle_flash(from, dir, 0.45, tint, 0.12)
			flash_light(from, tint, 3.5, 4.5, 0.18)
		"sonic":
			flash_light(from, Color(0.5, 0.8, 1.0), 2.5, 4.0, 0.25)
			shockwave(from, 1.2, Color(0.5, 0.85, 1.0), 0.35)
		"flame":
			burst("flame_jet", from, dir, 1.0)
			flash_light(from + dir * 1.2, Color(1.0, 0.5, 0.15), 4.0, 5.0, 0.45, true)


## Projectile or beam arriving.
func impact(pos: Vector3, kind: String, tint := Color(1, 1, 1, 1)) -> void:
	if not near_camera(pos):
		return
	match kind:
		"tracer":
			burst("sparks", pos, Vector3.UP, 0.8)
			if quality > 0:
				burst("impact_dust", pos, Vector3.UP, 1.0)
		"laser":
			burst("sparks", pos, Vector3.UP, 1.1, Color(tint.r * 1.5, tint.g * 1.5, tint.b * 1.5, 1.0))
			flash_light(pos + Vector3(0, 0.4, 0), tint, 3.0, 4.0, 0.2)
			scorch(pos, 0.5, 10.0, 1.0)
		"flame":
			burst("fireball", pos, Vector3.UP, 0.45)
			burst("embers", pos, Vector3.UP, 0.6)
			flash_light(pos + Vector3(0, 0.5, 0), Color(1.0, 0.5, 0.15), 3.0, 4.0, 0.4, true)
		"sonic":
			shockwave(pos, 1.8, Color(0.5, 0.85, 1.0), 0.45)
			burst("impact_dust", pos, Vector3.UP, 1.6)
		_:
			# shells and rockets: a small blast
			burst("fireball", pos + Vector3(0, 0.15, 0), Vector3.UP, 0.45)
			burst("sparks", pos, Vector3.UP, 1.1)
			burst("impact_dust", pos, Vector3.UP, 1.8)
			if quality > 0:
				burst("smoke", pos, Vector3.UP, 0.35)
			flash_light(pos + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.3), 4.0, 5.0, 0.22)
			scorch(pos, 0.55, 12.0, 0.6)


## Fireball, shrapnel, debris, rolling smoke, dust ring, shockwave, light,
## scorch mark and a camera jolt. `size` 0.5 (infantry) .. 3 (big buildings).
func explosion(pos: Vector3, size: float) -> void:
	if G.camera:
		G.camera.shake(clampf(size * 0.12, 0.03, 0.45), pos)
	if not near_camera(pos, 10.0 + size * 4.0):
		return
	var ground := Vector3(pos.x, G.map.height_at(pos) if G.map else pos.y, pos.z)
	burst("fireball", pos, Vector3.UP, size)
	burst("spark_burst", pos, Vector3.UP, clampf(size * 0.8, 0.5, 2.0))
	burst("smoke", pos + Vector3(0, 0.3 * size, 0), Vector3.UP, size)
	burst("dust", ground, Vector3.UP, size)
	if size >= 0.8:
		burst("debris", pos, Vector3.UP, clampf(size * 0.7, 0.6, 1.8))
		burst("embers", pos, Vector3.UP, size)
	shockwave(ground, 2.2 * size, Color(1.0, 0.65, 0.35), 0.5 + size * 0.1)
	flash_light(pos + Vector3(0, 1.0 * size, 0), Color(1.0, 0.58, 0.25), 6.0 * size + 2.0, 5.0 + size * 5.0, 0.5 + size * 0.2, true)
	scorch(ground, 0.8 * size + 0.3, 30.0, 1.0)
	if size >= 1.3:
		# big blasts: a lingering pillar of smoke and a couple of secondary pops
		burst("smoke_column", ground + Vector3(0, 0.5, 0), Vector3.UP, clampf(size * 0.6, 0.8, 2.0))
		for i in 2:
			var off := Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.8), randf_range(-0.6, 0.6)) * size
			get_tree().create_timer(0.15 + i * 0.2, false).timeout.connect(func():
				if is_inside_tree():
					burst("fireball", pos + off, Vector3.UP, size * 0.55)
					flash_light(pos + off, Color(1.0, 0.55, 0.2), 3.0 * size, 3.0 * size, 0.3))


# ================================================================ per-frame

func _process(delta: float) -> void:
	for e in _lights:
		if float(e["t"]) >= float(e["life"]):
			continue
		e["t"] = float(e["t"]) + delta
		var l: OmniLight3D = e["l"]
		var k := clampf(float(e["t"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		var en := float(e["e"]) * (1.0 - k) * (1.0 - k)
		if e["flicker"]:
			en *= 0.7 + 0.3 * randf()
		l.light_energy = en
		if k >= 1.0:
			l.visible = false
	for f in _flashes:
		if float(f["t"]) >= float(f["life"]):
			continue
		f["t"] = float(f["t"]) + delta
		var k := clampf(float(f["t"]) / maxf(float(f["life"]), 0.001), 0.0, 1.0)
		for mi in f["mis"]:
			(mi as MeshInstance3D).set_instance_shader_parameter("fade", 1.0 - k * k)
		if k >= 1.0:
			(f["n"] as Node3D).visible = false
	for e in _beams:
		if float(e["t"]) >= float(e["life"]):
			continue
		e["t"] = float(e["t"]) + delta
		var k := clampf(float(e["t"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		var mi: MeshInstance3D = e["mi"]
		mi.set_instance_shader_parameter("fade", (1.0 - k) * (0.85 + 0.15 * randf()))
		if k >= 1.0:
			mi.visible = false
	for e in _waves:
		if float(e["t"]) >= float(e["life"]):
			continue
		e["t"] = float(e["t"]) + delta
		var k := clampf(float(e["t"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		var mi: MeshInstance3D = e["mi"]
		mi.set_instance_shader_parameter("progress", 1.0 - pow(1.0 - k, 2.2))
		if k >= 1.0:
			mi.visible = false
	for e in _decals:
		if float(e["t"]) >= float(e["life"]):
			continue
		e["t"] = float(e["t"]) + delta
		var t := float(e["t"])
		var d: Decal = e["d"]
		d.emission_energy = float(e["heat"]) * 3.0 * exp(-t / 2.5)
		var fade := clampf((float(e["life"]) - t) / 5.0, 0.0, 1.0)
		d.modulate = Color(1, 1, 1, fade)
		if t >= float(e["life"]):
			d.visible = false
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		b["t"] = float(b["t"]) + delta
		var t := float(b["t"])
		var mi: MeshInstance3D = b["mi"]
		var f := 0.0
		for s in b["strikes"]:
			var dt := t - float(s)
			if dt >= 0.0:
				f = maxf(f, exp(-dt * 18.0))
		mi.set_instance_shader_parameter("fade", clampf(f * 1.2 + 0.15 * (1.0 - t / float(b["life"])), 0.0, 1.2))
		if t >= float(b["life"]):
			mi.queue_free()
			_bolts.remove_at(i)
