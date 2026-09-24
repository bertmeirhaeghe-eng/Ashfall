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


static func marker(pos: Vector3, color: Color) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.ring_segments = 4
	_spawn(Vector3(pos.x, pos.y + 0.05, pos.z), tm, color, 0.6, 0.35, -0.6)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / life, 0.0, 1.0)
	var s := base_scale * maxf(0.05, 1.0 + grow * k)
	scale = Vector3.ONE * s
	position.y += rise * delta
	if _mat:
		var c := _mat.albedo_color
		c.a = _base_alpha * (1.0 - k)
		_mat.albedo_color = c
	if _light:
		_light.light_energy = light_energy * (1.0 - k)
	if _t >= life:
		queue_free()
