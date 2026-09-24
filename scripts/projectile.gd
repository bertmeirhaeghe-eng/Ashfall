class_name Projectile
extends Node3D
## Homing projectile. Damage is applied on arrival.

var target: Entity = null
var target_pos := Vector3.ZERO
var speed := 30.0
var damage := 10.0
var warhead := "bullet"
var kind := "tracer"
var shooter: Entity = null
var weapon_splash := 0.0
var _life := 4.0


func launch(from: Vector3, t: Entity, w: Dictionary, dmg: float, src: Entity) -> void:
	position = from
	target = t
	target_pos = t.position + Vector3(0, t.hit_height(), 0)
	speed = float(w.get("speed", 30))
	damage = dmg
	warhead = w.get("warhead", "bullet")
	kind = w.get("projectile", "tracer")
	shooter = src
	weapon_splash = float(w.get("splash", 0.0))
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match kind:
		"rocket":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cm.height = 0.3
			mi.mesh = cm
			mi.rotation.x = PI / 2.0
			m.albedo_color = Color(2.5, 1.2, 0.4)
		"sonic":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.1
			tm.outer_radius = 0.16
			mi.mesh = tm
			mi.rotation.x = PI / 2.0
			m.albedo_color = Color(0.6, 1.4, 2.5)
		"flame":
			var fm := SphereMesh.new()
			fm.radius = 0.12
			fm.height = 0.24
			mi.mesh = fm
			m.albedo_color = Color(3.0, 1.2, 0.2)
		"shell":
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			mi.mesh = sm
			m.albedo_color = Color(2.5, 1.8, 0.8)
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.025, 0.025, 0.4)
			mi.mesh = bm
			m.albedo_color = Color(3.0, 2.6, 1.2)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	_life -= delta
	if is_instance_valid(target) and target.alive:
		target_pos = target.position + Vector3(0, target.hit_height(), 0)
	var to := target_pos - position
	var d := to.length()
	var step := speed * delta
	if d <= step or _life <= 0.0:
		_impact()
		return
	var dir := to / d
	position += dir * step
	if absf(dir.y) < 0.99:
		look_at(position + dir, Vector3.UP)
	if kind == "rocket" and randf() < 0.6:
		Fx.puff(position - dir * 0.15)


func _impact() -> void:
	var src: Entity = shooter if is_instance_valid(shooter) else null
	var splash := float(weapon_splash)
	if splash > 0.0:
		var spare := src.team if src else -1
		G.damage_area(target_pos, splash, damage, warhead, src, spare, is_instance_valid(target) and target.is_air)
	elif is_instance_valid(target) and target.alive:
		target.take_damage(damage, warhead, src)
	Fx.impact(target_pos, kind)
	if G.mission:
		G.mission.on_impact(target_pos, warhead, src)
	queue_free()
