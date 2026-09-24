class_name GlassStorm
extends Node3D
## A glass storm: a band of crystal-laden wind moving along the X axis.
## Units inside take damage (unless sheltered near their own buildings or
## immune), lightning strikes at random, radar is jammed and aircraft are
## grounded while it is on the map.

var front := 0.0              # world X of the leading edge
var width := 22.0             # band thickness behind the front
var speed := 0.2              # cells per second (positive = eastward)
var damage := 7.0             # hp per second to exposed units
var lightning_every := 1.6
var immune_teams: Array = [] # teams used to the storm
var shelter_radius := 3.0     # distance from own structures that counts as cover
var map_h := 64.0
var active := true
var _wall: MeshInstance3D
var _haze: MeshInstance3D
var _tick := 0.0
var _bolt := 0.0


func _ready() -> void:
	_wall = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	_wall.mesh = bm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.25, 0.4, 0.3, 0.38)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.6, 0.35)
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wall.material_override = m
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	_haze = MeshInstance3D.new()
	_haze.mesh = bm
	var hm := m.duplicate() as StandardMaterial3D
	hm.albedo_color = Color(0.3, 0.5, 0.35, 0.55)
	_haze.material_override = hm
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_haze)
	_update_visual()


func band_min() -> float:
	return minf(front, front - width * signf(speed if speed != 0.0 else 1.0))


func band_max() -> float:
	return maxf(front, front - width * signf(speed if speed != 0.0 else 1.0))


func contains(p: Vector3) -> bool:
	return active and p.x >= band_min() and p.x <= band_max()


func on_map(map_w: float) -> bool:
	return active and band_max() > 0.0 and band_min() < map_w


func sheltered(e: Entity) -> bool:
	for s in G.entities:
		if s is Structure and s.alive and s.team == e.team and s.edge_distance(e.position) <= shelter_radius:
			return true
	return false


func _update_visual() -> void:
	var cx := (band_min() + band_max()) * 0.5
	_wall.position = Vector3(cx, 3.5, map_h * 0.5)
	_wall.scale = Vector3(width, 7.0, map_h + 8.0)
	_haze.position = Vector3(front, 4.0, map_h * 0.5)
	_haze.scale = Vector3(1.2, 8.0, map_h + 8.0)
	visible = active


func _physics_process(delta: float) -> void:
	if not active:
		visible = false
		return
	front += speed * delta
	_update_visual()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for e in G.entities.duplicate():
			if not (e is Unit) or not e.alive or immune_teams.has(e.team):
				continue
			if contains(e.position) and not sheltered(e):
				e.take_damage(damage * 0.5, "claw", null)
	_bolt -= delta
	if _bolt <= 0.0:
		_bolt = lightning_every * randf_range(0.6, 1.4)
		var p := Vector3(randf_range(band_min(), band_max()), 0, randf_range(2.0, map_h - 2.0))
		if G.map and p.x > 0 and p.x < G.map.w:
			Fx.lightning(p)
			G.damage_area(p, 1.2, 50.0, "laser", null, -1, true)
