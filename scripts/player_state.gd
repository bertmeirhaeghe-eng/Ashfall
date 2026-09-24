class_name PlayerState
extends RefCounted
## One side in the match: credits, power, production queues.
## Production follows the RA2 model: one queue per category, pay-as-you-build,
## structures wait "ready" until placed.

const CATEGORIES := ["structure", "defense", "infantry", "vehicle"]
const MAX_UNIT_QUEUE := 5

var id := 0
var faction := "bastion"
var color := Color.WHITE
var display := "Player"
var is_ai := false
var credits := 0.0
var power_produced := 0
var power_used := 0
var defeated := false
var queues := {"structure": [], "defense": [], "infantry": [], "vehicle": []}
var ready_structure := {"structure": "", "defense": ""}
var last_attack_warning := -100.0
var last_attack_pos := Vector3.ZERO
var _funds_warned := false
var _was_low_power := false


func _init(p_id: int, p_faction: String, p_color: Color, p_ai: bool, p_name: String) -> void:
	id = p_id
	faction = p_faction
	color = p_color
	is_ai = p_ai
	display = p_name
	credits = float(G.game_rule("start_credits", 4000))


func low_power() -> bool:
	return power_used > power_produced


func recalc_power() -> void:
	power_produced = 0
	power_used = 0
	for s in structures():
		if s.power > 0:
			power_produced += s.power
		else:
			power_used -= s.power
	var low := low_power()
	if low and not _was_low_power:
		G.notify(id, "Low power")
	_was_low_power = low


func structures() -> Array:
	var out: Array = []
	for e in G.entities:
		if e is Structure and e.team == id and e.alive:
			out.append(e)
	return out


func units() -> Array:
	var out: Array = []
	for e in G.entities:
		if e is Unit and e.team == id and e.alive:
			out.append(e)
	return out


func count_of(def_id: String) -> int:
	var n := 0
	for e in G.entities:
		if e.team == id and e.alive and e.def_id == def_id:
			n += 1
	return n


func factories(category: String) -> Array:
	var out: Array = []
	for s in structures():
		if s.is_factory_for(category):
			out.append(s)
	return out


func missing_prereqs(def_id: String) -> Array:
	var d: Dictionary = G.def_of(def_id)
	var missing: Array = []
	for req in d.get("prereq", []):
		if count_of(req) == 0:
			missing.append(G.def_of(req).get("name", req))
	return missing


func can_build(def_id: String) -> bool:
	var d: Dictionary = G.def_of(def_id)
	if d.is_empty() or not d.get("buildable", true):
		return false
	var fac: String = d.get("faction", "any")
	if fac != "any" and fac != faction:
		return false
	if factories(d.get("category", "")).is_empty():
		return false
	return missing_prereqs(def_id).is_empty()


func queue_count(def_id: String) -> int:
	var d: Dictionary = G.def_of(def_id)
	var n := 0
	for item in queues.get(d.get("category", ""), []):
		if item["id"] == def_id:
			n += 1
	return n


## Progress 0..1 of the item currently being built for def_id, or -1.
func progress_of(def_id: String) -> float:
	var d: Dictionary = G.def_of(def_id)
	var q: Array = queues.get(d.get("category", ""), [])
	if not q.is_empty() and q[0]["id"] == def_id:
		return q[0]["spent"] / maxf(q[0]["cost"], 1.0)
	return -1.0


func queue_item(def_id: String) -> bool:
	if not can_build(def_id):
		return false
	var d: Dictionary = G.def_of(def_id)
	var cat: String = d["category"]
	var q: Array = queues[cat]
	if cat == "structure" or cat == "defense":
		if not q.is_empty() or ready_structure[cat] != "":
			return false
	elif q.size() >= MAX_UNIT_QUEUE:
		return false
	q.append({"id": def_id, "spent": 0.0, "cost": float(d.get("cost", 0)), "time": float(d.get("build_time", 5))})
	return true


## Right-click on a cameo: cancel the last queued copy (full refund of what was spent).
func cancel_item(def_id: String) -> void:
	var d: Dictionary = G.def_of(def_id)
	var cat: String = d.get("category", "")
	if ready_structure.get(cat, "") == def_id:
		ready_structure[cat] = ""
		credits += float(d.get("cost", 0))
		return
	var q: Array = queues.get(cat, [])
	for i in range(q.size() - 1, -1, -1):
		if q[i]["id"] == def_id:
			credits += q[i]["spent"]
			q.remove_at(i)
			return


func speed_mult(category: String) -> float:
	var m := 1.0
	if low_power():
		m *= float(G.game_rule("low_power_build_mult", 0.5))
	var n := factories(category).size()
	if n > 1:
		m *= 1.0 + float(G.game_rule("extra_factory_bonus", 0.25)) * (n - 1)
	return m


func process(delta: float) -> void:
	if defeated:
		return
	var starved := false
	for cat in CATEGORIES:
		var q: Array = queues[cat]
		if q.is_empty():
			continue
		if (cat == "structure" or cat == "defense") and ready_structure[cat] != "":
			continue
		if factories(cat).is_empty():
			continue
		var item: Dictionary = q[0]
		var rate: float = item["cost"] / maxf(item["time"], 0.1) * speed_mult(cat)
		var want: float = minf(rate * delta, item["cost"] - item["spent"])
		var pay := minf(want, credits)
		if pay < want - 0.001:
			starved = true
		credits -= pay
		item["spent"] += pay
		if item["spent"] >= item["cost"] - 0.001:
			q.pop_front()
			_complete(cat, item["id"])
	if starved and not _funds_warned:
		G.notify(id, "Insufficient funds")
	_funds_warned = starved


func _complete(cat: String, def_id: String) -> void:
	if cat == "structure" or cat == "defense":
		ready_structure[cat] = def_id
		G.notify(id, "Construction complete - place %s" % G.def_of(def_id).get("name", def_id))
		return
	var facs := factories(cat)
	if facs.is_empty():
		return
	var f: Structure = facs[0]
	for s in facs:
		if s.get_meta("primary", false):
			f = s
	var exit_c := f.exit_cell()
	var u: Unit = G.spawn_unit(def_id, id, G.map.cell_to_world(exit_c))
	if u == null:
		return
	var goal := f.rally_cell
	if goal.x < 0:
		goal = exit_c + Vector2i(0, 2)
	u.cmd_move(goal)
	G.notify(id, "Unit ready: %s" % u.display_name())
