class_name LanceStrike
extends Node3D
## Halo Lance orbital strike: a targeting reticle on the ground for `delay`
## seconds, then a white beam from orbit that wrecks everything in the radius.

signal struck(pos: Vector3)

var delay := 3.0
var radius := 3.0
var damage := 1800.0
var visual := "lance"      # lance | gas
var _t := 0.0
var _fired := false
var _reticle: MeshInstance3D
var _mat: StandardMaterial3D


static func fire(pos: Vector3, p_delay := 3.0, p_radius := 3.0, p_damage := 1800.0) -> LanceStrike:
	var s := LanceStrike.new()
	s.delay = p_delay
	s.radius = p_radius
	s.damage = p_damage
	G.fx_root.add_child(s)
	s.position = Vector3(pos.x, G.map.height_at(pos), pos.z)
	return s


func _ready() -> void:
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	_reticle.mesh = tm
	_reticle.scale = Vector3(radius, 0.3, radius)
	_reticle.position.y = 0.1
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.8)
	_reticle.material_override = _mat
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_reticle)
	var cross := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(radius * 2.0, 0.02, 0.08)
	cross.mesh = bm
	cross.material_override = _mat
	cross.position.y = 0.1
	_reticle.add_child(cross)


func time_left() -> float:
	return maxf(0.0, delay - _t)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _fired:
		_reticle.rotate_y(delta * 1.5)
		var k := clampf(_t / maxf(delay, 0.01), 0.0, 1.0)
		var s := radius * (1.0 - 0.2 * k)
		_reticle.scale = Vector3(s, 0.3, s)
		_mat.albedo_color.a = 0.4 + 0.5 * absf(sin(_t * (4.0 + 10.0 * k)))
		if _t >= delay:
			_strike()
	elif _t > delay + 1.2:
		queue_free()


func _strike() -> void:
	_fired = true
	_reticle.visible = false
	if visual == "gas":
		Fx.explosion(position + Vector3(0, 0.3, 0), 1.0)
		Fx.ring(position, Color(0.8, 1.0, 0.2, 0.7), radius * 1.2, 1.5)
	else:
		var top := position + Vector3(0, 40, 0)
		Fx.beam(top, position, Color(1.0, 1.0, 0.95), radius * 0.35, 0.9)
		Fx.beam(top, position, Color(0.7, 0.85, 1.0), radius * 0.6, 0.5)
		Fx.explosion(position + Vector3(0, 0.5, 0), radius * 1.4)
		Fx.ring(position, Color(1.0, 0.9, 0.7, 0.8), radius * 2.2, 0.8)
	if damage > 0.0:
		G.damage_area(position, radius, damage, "laser", null, -1, true)
	struck.emit(position)
