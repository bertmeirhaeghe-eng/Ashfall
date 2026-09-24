class_name Entity
extends Node3D
## Base for everything that belongs to a team and can be shot:
## units and structures. Owns health, armor, weapon and veterancy.

var def_id := ""
var def: Dictionary = {}
var team := 0
var hp := 100.0
var max_hp := 100.0
var armor := "light"
var alive := true
var selected := false
var is_structure := false
var radius := 0.4
var bar_height := 1.0

var weapon: Dictionary = {}
var weapon_cd := 0.0
var target: Entity = null

var kills := 0
var rank := 0                 # 0 rookie, 1 veteran, 2 elite
var last_attacker: Entity = null
var last_hit_time := -100.0

var model: Node3D
var turret: Node3D            # optional rotating part
var muzzle_height := 0.5
var sel_ring: MeshInstance3D


func setup(id: String, p_team: int) -> void:
	def_id = id
	def = G.def_of(id)
	team = p_team
	max_hp = float(def.get("hp", 100))
	hp = max_hp
	armor = def.get("armor", "light")
	radius = float(def.get("radius", 0.4))
	bar_height = float(def.get("height", 1.0))
	if def.has("weapon"):
		weapon = G.weapon_def(def["weapon"])
	var p: PlayerState = G.players[team]
	model = MeshFactory.build(def.get("model", ""), p.color, p.faction)
	add_child(model)
	if model.has_meta("turret"):
		turret = model.get_meta("turret")
	muzzle_height = float(model.get_meta("muzzle_height", bar_height * 0.6))
	_make_ring()


func _make_ring() -> void:
	sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	sel_ring.mesh = tm
	var r := ring_radius()
	sel_ring.scale = Vector3(r.x, 0.3, r.y)
	sel_ring.position.y = 0.04
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.4, 1.0, 0.4) if team == G.local_team else Color(1.0, 0.35, 0.3)
	sel_ring.material_override = m
	sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sel_ring.visible = false
	add_child(sel_ring)


func ring_radius() -> Vector2:
	return Vector2(radius + 0.12, radius + 0.12)


func set_selected(v: bool) -> void:
	selected = v
	if sel_ring:
		sel_ring.visible = v


func display_name() -> String:
	return def.get("name", def_id)


## Distance from a point to this entity's outer edge (ground plane).
func edge_distance(from: Vector3) -> float:
	var d := Vector2(from.x - position.x, from.z - position.z).length()
	return maxf(0.0, d - radius)


func weapon_range() -> float:
	return float(weapon.get("range", 0.0))


func in_range(t: Entity) -> bool:
	return t.edge_distance(position) <= weapon_range()


func hit_height() -> float:
	return bar_height * 0.5


func rank_value(key: String) -> float:
	var arr: Array = G.game_rule(key, [1.0, 1.0, 1.0])
	return float(arr[clampi(rank, 0, arr.size() - 1)])


## Rotates turret (or the whole model) toward t and fires when ready.
## Returns true while the target is still being engaged.
func aim_and_fire(t: Entity, delta: float, rof_mult := 1.0) -> void:
	var dir := t.position - position
	var yaw := atan2(dir.x, dir.z)
	var aimed := true
	if turret:
		var local_yaw := yaw - model.rotation.y
		turret.rotation.y = lerp_angle(turret.rotation.y, local_yaw, minf(1.0, delta * 8.0))
		aimed = absf(angle_difference(turret.rotation.y, local_yaw)) < 0.25
	elif not is_structure:
		model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, delta * 10.0))
		aimed = absf(angle_difference(model.rotation.y, yaw)) < 0.3
	if aimed and weapon_cd <= 0.0:
		fire(t)
		weapon_cd = float(weapon.get("cooldown", 1.0)) * rank_value("rank_rof_mult") / maxf(rof_mult, 0.05)


func fire(t: Entity) -> void:
	var yaw := atan2(t.position.x - position.x, t.position.z - position.z)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var from := position + Vector3(0, muzzle_height, 0) + fwd * (radius * 0.8)
	var p := Projectile.new()
	G.fx_root.add_child(p)
	p.launch(from, t, weapon, float(weapon.get("damage", 10)) * rank_value("rank_damage_mult"), self)
	Fx.flash(from)


func take_damage(amount: float, warhead: String, attacker: Entity) -> void:
	if not alive:
		return
	hp -= amount * G.warhead_mult(warhead, armor)
	last_hit_time = G.elapsed
	if is_instance_valid(attacker) and attacker.alive:
		last_attacker = attacker
	on_damaged()
	if hp <= 0.0:
		die(attacker)


func on_damaged() -> void:
	pass


func die(killer: Entity = null) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	if is_instance_valid(killer) and killer.alive and killer.team != team:
		killer.add_kill()
	Fx.explosion(position + Vector3(0, 0.3, 0), 1.6 if is_structure else (0.6 if armor == "infantry" else 1.0))
	on_removed()
	G.unregister(self)
	queue_free()


## Called when the entity leaves play (death or sale).
func on_removed() -> void:
	pass


func add_kill() -> void:
	kills += 1
	var new_rank := rank
	if kills >= int(G.game_rule("elite_kills", 6)):
		new_rank = 2
	elif kills >= int(G.game_rule("veteran_kills", 3)):
		new_rank = 1
	if new_rank > rank:
		var old_mult := rank_value("rank_hp_mult")
		rank = new_rank
		var ratio := rank_value("rank_hp_mult") / old_mult
		max_hp *= ratio
		hp = minf(max_hp, hp * ratio)
		var rank_names: Array = ["Rookie", "Veteran", "Elite"]
		G.notify(team, "Unit promoted: %s" % rank_names[rank])
