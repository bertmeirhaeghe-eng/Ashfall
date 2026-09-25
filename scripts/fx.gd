class_name Fx
extends Node3D
## Visual effects API used by the game code: muzzle flashes, impacts,
## explosions, beams, lightning, rings and order markers. The heavy lifting
## (GPU particles, pooled lights, scorch marks) is done by Vfx (scripts/vfx.gd);
## an Fx node itself is a tiny self-destructing mesh effect (markers, rings).

var life := 0.3
var grow := 1.0
var rise := 0.0
var base_scale := 1.0
var light_energy := 0.0
var _t := 0.0
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _base_alpha := 1.0
var flat := false


static func _spawn(pos: Vector3, mesh: Mesh, color: Color, size: float, p_life: float, p_grow: float, shaded := false) -> Fx:
	if G.fx_root == null:
		return null
	var f := Fx.new()
	f.life = p_life
	f.grow = p_grow
	f.base_scale = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	if not shaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f._mat = m
	f._base_alpha = color.a
	f.add_child(mi)
	f.scale = Vector3.ONE * size
	G.fx_root.add_child(f)
	f.position = pos
	return f


static var _sphere_mesh: SphereMesh


static func _sphere() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 12
		_sphere_mesh.rings = 6
	return _sphere_mesh


static func flash(pos: Vector3, dir := Vector3.ZERO, kind := "tracer", damage := 10.0, tint := Color(1, 0.6, 0.2)) -> void:
	if Vfx.inst:
		Vfx.inst.muzzle(pos, dir if dir != Vector3.ZERO else Vector3.FORWARD, kind, damage, tint)
		return
	_spawn(pos, _sphere(), Color(3.0, 2.2, 1.0, 0.9), 0.14, 0.06, 0.5)


static func puff(pos: Vector3) -> void:
	if Vfx.inst:
		Vfx.inst.burst("muzzle_smoke", pos, Vector3.UP, 0.6)
		return
	var f := _spawn(pos, _sphere(), Color(0.5, 0.5, 0.5, 0.35), 0.1, 0.5, 2.0, true)
	if f:
		f.rise = 0.3


static func impact(pos: Vector3, kind: String, tint := Color(1, 1, 1, 1)) -> void:
	if Vfx.inst:
		Vfx.inst.impact(pos, kind, tint)
		return
	match kind:
		"tracer":
			_spawn(pos, _sphere(), Color(2.5, 2.0, 1.0, 0.8), 0.08, 0.08, 1.0)
		_:
			_spawn(pos, _sphere(), Color(3.0, 1.4, 0.4, 0.9), 0.3, 0.2, 1.5)


static func explosion(pos: Vector3, size: float) -> void:
	if Vfx.inst:
		Vfx.inst.explosion(pos, size)
		return
	_spawn(pos, _sphere(), Color(3.5, 1.6, 0.4, 0.95), size * 0.8, 0.45, 1.6)


static func dust(pos: Vector3) -> void:
	if Vfx.inst:
		Vfx.inst.burst("dust", Vector3(pos.x, G.map.height_at(pos) if G.map else pos.y, pos.z), Vector3.UP, 0.6)
		return
	for i in 4:
		var off := Vector3(randf_range(-0.4, 0.4), 0.05, randf_range(-0.4, 0.4))
		var d := _spawn(pos + off, _sphere(), Color(0.45, 0.38, 0.3, 0.6), 0.35, 0.9, 1.4, true)
		if d:
			d.rise = 0.25


static func sparkle(pos: Vector3, color: Color) -> void:
	var f := _spawn(pos + Vector3(randf_range(-0.2, 0.2), randf_range(0, 0.3), randf_range(-0.2, 0.2)), _sphere(), color, 0.08, 0.5, 0.5)
	if f:
		f.rise = 0.8


## Straight energy beam (lasers, Halo Lance, beams between things).
static func beam(a: Vector3, b: Vector3, color: Color, width := 0.06, life := 0.18) -> void:
	if Vfx.inst:
		Vfx.inst.beam(a, b, color, width, life)
		if width >= 0.3:
			# the Halo Lance and friends light up everything around them
			Vfx.inst.flash_light(b + Vector3(0, 2.0, 0), color, 10.0, width * 12.0 + 6.0, life, true)
		return
	if G.fx_root == null:
		return
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var cm := CylinderMesh.new()
	cm.top_radius = width
	cm.bottom_radius = width
	cm.height = 1.0
	var f := _spawn((a + b) * 0.5, cm, Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 0.9), 1.0, life, 0.0)
	if f:
		var up := (b - a).normalized()
		var side := up.cross(Vector3.RIGHT)
		if side.length() < 0.01:
			side = up.cross(Vector3.FORWARD)
		side = side.normalized()
		var fwd := side.cross(up).normalized()
		f.transform.basis = Basis(side, up * len, fwd)
		f.base_scale = -1.0


## Jagged, branching lightning bolt from the sky with thunder and a flash
## that lights up the whole battlefield.
static func lightning(pos: Vector3, color := Color(0.6, 1.0, 0.7)) -> void:
	if G.weather:
		G.weather.strike(pos, color)
		return
	if Vfx.inst:
		Vfx.inst.lightning(pos, color)


## Flat expanding ring on the ground (pulses, shockwaves).
static func ring(pos: Vector3, color: Color, radius: float, life := 1.0) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	var gy: float = G.map.height_at(pos) if G.map else 0.0
	var f := _spawn(Vector3(pos.x, gy + 0.15, pos.z), tm, color, 0.2, life, radius / 0.2 - 1.0)
	if f:
		f.flat = true
	if Vfx.inst and radius <= 30.0:
		Vfx.inst.shockwave(pos, radius, color, life * 0.8)


static func marker(pos: Vector3, color: Color) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.ring_segments = 4
	_spawn(Vector3(pos.x, pos.y + 0.05, pos.z), tm, color, 0.6, 0.35, -0.6)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / life, 0.0, 1.0)
	if base_scale > 0.0:
		var s := base_scale * maxf(0.05, 1.0 + grow * k)
		scale = Vector3(s, 0.3 if flat else s, s)
	position.y += rise * delta
	if _mat:
		var c := _mat.albedo_color
		c.a = _base_alpha * (1.0 - k)
		_mat.albedo_color = c
	if _light:
		_light.light_energy = light_energy * (1.0 - k)
	if _t >= life:
		queue_free()
