class_name TrainCar
extends Entity
## One car of the Pilgrim fortress-train. Positioned along the rail by the
## mission (distance along the track); has its own weapon and can be targeted,
## destroyed or boarded individually. A detached car stays where it is.

var role := ""            # engine | flak | artillery | troop | repair | command
var slot := 0             # index behind the engine
var attached := true
var _scan_t := 0.0


func setup_car(p_role: String, team_id: int) -> void:
	role = p_role
	is_structure = true
	var ids := {"engine": "train_engine", "flak": "train_flak", "artillery": "train_artillery",
		"troop": "train_troop", "repair": "train_repair", "command": "train_command"}
	def_id = ids[role]
	def = {"name": "Pilgrim " + role.capitalize() + " Car", "hp": 1500, "armor": "heavy", "radius": 0.9,
		"height": 1.3, "model": def_id, "faction": "veil"}
	match role:
		"engine":
			def["hp"] = 3200
			def["weapon"] = "buggy_mg"
		"flak":
			def["hp"] = 1100
			def["weapon"] = "flak"
		"artillery":
			def["hp"] = 1400
			def["weapon"] = "artillery"
		"troop":
			def["hp"] = 1500
			def["weapon"] = "buggy_mg"
		"repair":
			def["hp"] = 1100
		"command":
			def["hp"] = 1800
			def["weapon"] = "buggy_mg"
	team = team_id
	max_hp = float(def["hp"])
	hp = max_hp
	armor = "heavy"
	radius = 0.9
	bar_height = 1.3
	if def.has("weapon"):
		weapon = G.weapon_def(def["weapon"])
	_build_model()
	_make_ring()
	invulnerable = role == "engine"


func display_name() -> String:
	return def["name"]


func place(pos: Vector3, dir: Vector3) -> void:
	position = Vector3(pos.x, G.map.height_at(pos), pos.z)
	if dir.length_squared() > 0.0001:
		model.rotation.y = atan2(dir.x, dir.z)


func _physics_process(delta: float) -> void:
	if not alive or weapon.is_empty():
		return
	weapon_cd = maxf(0.0, weapon_cd - delta)
	if not (is_instance_valid(target) and target.alive and in_range(target) and can_target(target)):
		target = null
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.3
			target = G.find_target(self, weapon_range())
	if target:
		aim_and_fire(target, delta)
