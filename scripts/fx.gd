class_name Fx
extends Node3D
## Tiny self-destructing visual effects: flashes, explosions, smoke, order markers.

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


static func flash(pos: Vector3) -> void:
	_spawn(pos, _sphere(), Color(3.0, 2.2, 1.0, 0.9), 0.14, 0.06, 0.5)


static func puff(pos: Vector3) -> void:
	var f := _spawn(pos, _sphere(), Color(0.5, 0.5, 0.5, 0.35), 0.1, 0.5, 2.0, true)
	if f:
		f.rise = 0.3


static func impact(pos: Vector3, kind: String) -> void:
	match kind:
		"tracer":
			_spawn(pos, _sphere(), Color(2.5, 2.0, 1.0, 0.8), 0.08, 0.08, 1.0)
		_:
			_spawn(pos, _sphere(), Color(3.0, 1.4, 0.4, 0.9), 0.3, 0.2, 1.5)
			var s := _spawn(pos, _sphere(), Color(0.25, 0.22, 0.2, 0.5), 0.3, 0.7, 1.8, true)
			if s:
				s.rise = 0.5


static func explosion(pos: Vector3, size: float) -> void:
	var f := _spawn(pos, _sphere(), Color(3.5, 1.6, 0.4, 0.95), size * 0.8, 0.45, 1.6)
	if f:
		f.light_energy = 4.0 * size
		f._light = OmniLight3D.new()
		f._light.light_color = Color(1.0, 0.6, 0.25)
		f._light.omni_range = 4.0 * size
		f._light.light_energy = f.light_energy
		f.add_child(f._light)
	for i in 3:
		var off := Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3)) * size
		var s := _spawn(pos + off, _sphere(), Color(0.18, 0.16, 0.15, 0.6), size * 0.7, 1.4 + randf() * 0.6, 1.5, true)
		if s:
			s.rise = 0.6


static func dust(pos: Vector3) -> void:
	for i in 4:
		var off := Vector3(randf_range(-0.4, 0.4), 0.05, randf_range(-0.4, 0.4))
		var d := _spawn(pos + off, _sphere(), Color(0.45, 0.38, 0.3, 0.6), 0.35, 0.9, 1.4, true)
		if d:
			d.rise = 0.25


static func sparkle(pos: Vector3, color: Color) -> void:
	var f := _spawn(pos + Vector3(randf_range(-0.2, 0.2), randf_range(0, 0.3), randf_range(-0.2, 0.2)), _sphere(), color, 0.08, 0.5, 0.5)
	if f:
		f.rise = 0.8


## Straight energy beam (lasers, Halo Lance, lightning).
static func beam(a: Vector3, b: Vector3, color: Color, width := 0.06, life := 0.18) -> void:
	if G.fx_root == null:
		return
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var cm := CylinderMesh.new()
	cm.top_radius = width
	cm.bottom_radius = width
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
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


## Jagged lightning bolt from the sky.
static func lightning(pos: Vector3, color := Color(0.6, 1.0, 0.7)) -> void:
	var top := pos + Vector3(randf_range(-2, 2), 14.0, randf_range(-2, 2))
	var prev := top
	for i in range(1, 7):
		var k := float(i) / 6.0
		var p := top.lerp(pos, k) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) * (1.0 - k)
		beam(prev, p, color, 0.08, 0.25)
		prev = p
	var f := _spawn(pos + Vector3(0, 0.3, 0), _sphere(), Color(color.r * 3, color.g * 3, color.b * 3, 0.9), 1.2, 0.3, 1.2)
	if f:
		f.light_energy = 6.0
		f._light = OmniLight3D.new()
		f._light.light_color = color
		f._light.omni_range = 8.0
		f._light.light_energy = 6.0
		f.add_child(f._light)


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
