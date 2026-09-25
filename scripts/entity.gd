class_name Entity
extends Node3D
## Base for everything that belongs to a team and can be shot:
## units, structures and train cars. Owns health, armor, weapon, veterancy,
## stealth / detection state and team changes (capture, hijack).

var def_id := ""
var def: Dictionary = {}
var team := 0
var hp := 100.0
var max_hp := 100.0
var armor := "light"
var alive := true
var selected := false
var is_structure := false
var is_air := false
var radius := 0.4
var bar_height := 1.0

var weapon: Dictionary = {}
var weapon_cd := 0.0
var target: Entity = null

var kills := 0
var rank := 0                 # 0 rookie, 1 veteran, 2 elite
var last_attacker: Entity = null
var last_hit_time := -100.0

var invulnerable := false     # hp never drops below 1 (mission objects)
var damage_mult := 1.0        # 0 = shielded
var tags := {}                # free-form mission tags
var detected_mask := -1       # -1: visible to everyone, else bitmask of teams that see it
var decloak_until := -100.0
var force_hidden := false     # inside a stealth field
var force_reveal := false
var hijack := 0.0             # SIBYL hijack meter (0..1)
var orig_team := -1

var model: Node3D
var turret: Node3D            # optional rotating part
var muzzle_height := 0.5
var sel_ring: MeshInstance3D
var _alpha := 0.0


func setup(id: String, p_team: int) -> void:
	def_id = id
	def = G.def_of(id)
	team = p_team
	max_hp = float(def.get("hp", 100))
	hp = max_hp
	armor = def.get("armor", "light")
	radius = float(def.get("radius", 0.4))
	bar_height = float(def.get("height", 1.0))
	invulnerable = def.get("invulnerable", false)
	if def.has("weapon"):
		weapon = G.weapon_def(def["weapon"])
	_build_model()
	_make_ring()


func model_faction() -> String:
	var fac: String = def.get("faction", "any")
	if fac == "any" or fac == "":
		fac = (G.players[team] as PlayerState).faction
	return fac


func _build_model() -> void:
	var p: PlayerState = G.players[team]
	model = MeshFactory.build(def.get("model", ""), p.color, model_faction())
	add_child(model)
	turret = model.get_meta("turret") if model.has_meta("turret") else null
	muzzle_height = float(model.get_meta("muzzle_height", bar_height * 0.6))
	_alpha = 0.0


func _process(delta: float) -> void:
	if model and model.has_meta("spin"):
		var sp: Node3D = model.get_meta("spin")
		if is_instance_valid(sp):
			sp.rotate_y(delta * 1.6)


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
	sel_ring.material_override = m
	sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sel_ring.visible = false
	add_child(sel_ring)
	_color_ring()


func _color_ring() -> void:
	var m := sel_ring.material_override as StandardMaterial3D
	if team == G.local_team:
		m.albedo_color = Color(0.4, 1.0, 0.4)
	elif G.is_friend(team, G.local_team):
		m.albedo_color = Color(0.4, 0.8, 1.0)
	elif G.is_enemy(team, G.local_team):
		m.albedo_color = Color(1.0, 0.35, 0.3)
	else:
		m.albedo_color = Color(0.9, 0.9, 0.6)


func ring_radius() -> Vector2:
	return Vector2(radius + 0.12, radius + 0.12)


func set_selected(v: bool) -> void:
	selected = v
	if sel_ring:
		sel_ring.visible = v


func display_name() -> String:
	return tr(def.get("name", def_id))


## Distance from a point to this entity's outer edge (ground plane).
func edge_distance(from: Vector3) -> float:
	var d := Vector2(from.x - position.x, from.z - position.z).length()
	return maxf(0.0, d - radius)


func weapon_range() -> float:
	return float(weapon.get("range", 0.0))


func min_range() -> float:
	return float(weapon.get("min_range", 0.0))


func in_range(t: Entity) -> bool:
	var d := t.edge_distance(position)
	return d <= weapon_range() and d >= min_range()


func hit_height() -> float:
	return bar_height * 0.5


func rank_value(key: String) -> float:
	var arr: Array = G.game_rule(key, [1.0, 1.0, 1.0])
	return float(arr[clampi(rank, 0, arr.size() - 1)])


# ---------------------------------------------------------------- stealth

func detector_radius() -> float:
	return float(def.get("detector", 0.0))


func can_hide() -> bool:
	return def.get("cloak", false) or def.get("burrow", false) or force_hidden


func hidden_underground() -> bool:
	return false


func hidden_now() -> bool:
	if hidden_underground():
		return true
	if force_reveal or G.elapsed < decloak_until:
		return false
	return def.get("cloak", false) or force_hidden


func visible_to(t: int) -> bool:
	if detected_mask == -1 or G.is_friend(team, t):
		return true
	return (detected_mask >> t) & 1 == 1


func refresh_visibility() -> void:
	if model == null:
		return
	if hidden_underground():
		model.visible = false
		return
	var vis := visible_to(G.local_team)
	model.visible = vis
	# own / allied cloaked units shimmer instead of vanishing
	_set_alpha(0.6 if (vis and detected_mask != -1 and G.is_friend(team, G.local_team)) else 0.0)
	if not vis and selected and G.controller:
		G.controller.forget(self)


func _set_alpha(a: float) -> void:
	if is_equal_approx(a, _alpha):
		return
	_alpha = a
	for n in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = a


## Can this entity's weapon engage t at all (air/ground, visibility)?
func can_target(t: Entity) -> bool:
	if weapon.is_empty() or t == null or not t.alive:
		return false
	if t.hidden_underground() or not t.visible_to(team):
		return false
	var tg: String = weapon.get("targets", "ground")
	if t.is_air:
		return tg == "air" or tg == "both"
	return tg == "ground" or tg == "both"


# ---------------------------------------------------------------- combat

## Rotates turret (or the whole model) toward t and fires when ready.
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
	var dmg := float(weapon.get("damage", 10)) * rank_value("rank_damage_mult")
	if def.get("cloak", false):
		decloak_until = G.elapsed + 1.5
	var kind: String = weapon.get("projectile", "tracer")
	Sfx.weapon(kind, from, dmg)
	if kind == "laser" or kind == "none":
		var hit := t.position + Vector3(0, t.hit_height(), 0)
		if kind == "laser":
			Fx.beam(from, hit, Color(1.0, 0.3, 0.9) if model_faction() == "veil" else Color(0.5, 0.9, 1.0))
		else:
			Fx.impact(hit, "tracer")
		var splash := float(weapon.get("splash", 0.0))
		if splash > 0.0:
			G.damage_area(hit, splash, dmg, weapon.get("warhead", "bullet"), self, team)
		else:
			t.take_damage(dmg, weapon.get("warhead", "bullet"), self)
		return
	var p := Projectile.new()
	G.fx_root.add_child(p)
	p.launch(from, t, weapon, dmg, self)
	Fx.flash(from)


func take_damage(amount: float, warhead: String, attacker: Entity) -> void:
	if not alive:
		return
	var dmg := amount * G.warhead_mult(warhead, armor) * damage_mult
	if G.mission:
		dmg = G.mission.modify_damage(self, dmg, attacker)
	if dmg <= 0.0:
		return
	hp -= dmg
	last_hit_time = G.elapsed
	if is_instance_valid(attacker) and attacker.alive:
		last_attacker = attacker
	if invulnerable and hp < 1.0:
		hp = 1.0
	on_damaged()
	if G.mission:
		G.mission.on_damaged(self, attacker)
	if hp <= 0.0:
		die(attacker)


func heal(amount: float) -> void:
	if alive:
		hp = minf(max_hp, hp + amount)


func on_damaged() -> void:
	pass


func die(killer: Entity = null) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	if is_instance_valid(killer) and killer.alive and G.is_enemy(killer.team, team):
		killer.add_kill()
	var boom := 1.6 if is_structure else (0.6 if armor == "infantry" else 1.0)
	Fx.explosion(position + Vector3(0, 0.3, 0), boom)
	Sfx.explosion(position, boom)
	if G.mission:
		G.mission._entity_died(self, killer)
	on_removed()
	G.unregister(self)
	queue_free()


## Leaves play without an explosion (engineer used up, boarded a transport ...).
func remove_silently() -> void:
	if not alive:
		return
	alive = false
	on_removed()
	G.unregister(self)
	queue_free()


## Called when the entity leaves play (death, sale, boarding).
func on_removed() -> void:
	pass


## Changes owner: capture, SIBYL hijack, defection. Rebuilds the team colours.
func set_team(t: int) -> void:
	if t == team:
		return
	if G.controller:
		G.controller.forget(self)
	var old := team
	team = t
	target = null
	var rot := model.rotation
	model.queue_free()
	_build_model()
	model.rotation = rot
	_color_ring()
	detected_mask = -2  # force a visibility refresh
	on_team_changed(old)


func on_team_changed(_old: int) -> void:
	pass


func add_kill() -> void:
	kills += 1
	var new_rank := rank
	if kills >= int(G.game_rule("elite_kills", 6)):
		new_rank = 2
	elif kills >= int(G.game_rule("veteran_kills", 3)):
		new_rank = 1
	if new_rank > rank:
		set_rank(new_rank)
		var rank_names: Array = ["Rookie", "Veteran", "Elite"]
		G.notify(team, tr("Unit promoted: %s") % tr(rank_names[rank]))
		if team == G.local_team:
			Voice.eva("Unit promoted")


func set_rank(r: int) -> void:
	var old_mult := rank_value("rank_hp_mult")
	rank = clampi(r, 0, 2)
	var ratio := rank_value("rank_hp_mult") / old_mult
	max_hp *= ratio
	hp = minf(max_hp, hp * ratio)
