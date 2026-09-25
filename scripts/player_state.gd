class_name PlayerState
extends RefCounted
## One side in the match: credits, power, production queues, alliances and
## the campaign tech list. Production follows the RA2 model: one queue per
## category, pay-as-you-build, structures wait "ready" until placed.

const CATEGORIES := ["structure", "defense", "infantry", "vehicle", "aircraft", "veil"]
const MAX_UNIT_QUEUE := 5

var id := 0
var faction := "bastion"
var color := Color.WHITE
var display := "Player"
var is_ai := false
var passive := false            # neutral: never targeted automatically, never shoots
var allies: Array = []          # team ids treated as friends
var allowed: Variant = null     # null = anything; Dictionary id -> true = campaign tech list
var extra_factions: Array = []  # e.g. ["veil"] when Kestrel's units join you
var credits := 0.0
var power_produced := 0
var power_used := 0
var defense_rof_mult := 1.0
var free_radar := false
var defeated := false
var blue_refined := 0.0
var queues := {"structure": [], "defense": [], "infantry": [], "vehicle": [], "aircraft": [], "veil": []}
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


func has_radar() -> bool:
	if G.radar_jammed:
		return false
	if free_radar:
		return true
	for s in structures():
		if s.def.get("radar", false) and s.powered() and s.is_built():
			return true
	return false


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
		G.notify(id, "Low power", true)
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


## The production queue a def goes into for this player.
func queue_cat(def_id: String) -> String:
	var d: Dictionary = G.def_of(def_id)
	var cat: String = d.get("category", "")
	if (cat == "infantry" or cat == "vehicle") and d.get("faction", "any") != "any" \
			and d.get("faction", "any") != faction and extra_factions.has(d.get("faction", "")):
		return "veil"
	return cat


func factories(category: String) -> Array:
	var out: Array = []
	for s in structures():
		if s.is_factory_for(category) and s.is_built():
			out.append(s)
	return out


func missing_prereqs(def_id: String) -> Array:
	var d: Dictionary = G.def_of(def_id)
	var missing: Array = []
	if queue_cat(def_id) == "veil":
		return missing
	for req in d.get("prereq", []):
		if count_of(req) == 0:
			missing.append(G.def_of(req).get("name", req))
	return missing


func faction_ok(def_id: String) -> bool:
	var fac: String = G.def_of(def_id).get("faction", "any")
	return fac == "any" or fac == faction or extra_factions.has(fac)


func is_allowed(def_id: String) -> bool:
	return allowed == null or (allowed as Dictionary).has(def_id)


func can_build(def_id: String) -> bool:
	var d: Dictionary = G.def_of(def_id)
	if d.is_empty() or not d.get("buildable", true):
		return false
	if not faction_ok(def_id) or not is_allowed(def_id):
		return false
	if d.has("limit") and count_of(def_id) + queue_count(def_id) + (1 if ready_structure.values().has(def_id) else 0) >= int(d["limit"]):
		return false
	if factories(queue_cat(def_id)).is_empty():
		return false
	return missing_prereqs(def_id).is_empty()


func queue_count(def_id: String) -> int:
	var n := 0
	for item in queues.get(queue_cat(def_id), []):
		if item["id"] == def_id:
			n += 1
	return n


## Progress 0..1 of the item currently being built for def_id, or -1.
func progress_of(def_id: String) -> float:
	var q: Array = queues.get(queue_cat(def_id), [])
	if not q.is_empty() and q[0]["id"] == def_id:
		return q[0]["spent"] / maxf(q[0]["cost"], 1.0)
	return -1.0


func queue_item(def_id: String) -> bool:
	if not can_build(def_id):
		return false
	var d: Dictionary = G.def_of(def_id)
	var cat := queue_cat(def_id)
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
	var cat := queue_cat(def_id)
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
		G.notify(id, "Insufficient funds", true)
	_funds_warned = starved


func _complete(cat: String, def_id: String) -> void:
	if cat == "structure" or cat == "defense":
		ready_structure[cat] = def_id
		G.notify(id, tr("Construction complete - place %s") % tr(G.def_of(def_id).get("name", def_id)))
		if id == G.local_team:
			Voice.eva("Construction complete")
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
	if is_ai:
		u.tags["ai_made"] = true
	if G.mission:
		G.mission.on_unit_built(u)
	var goal := f.rally_cell
	if goal.x < 0:
		goal = exit_c + Vector2i(0, 2)
	u.cmd_move(goal)
	G.notify(id, tr("Unit ready: %s") % u.display_name())
	if id == G.local_team:
		Voice.eva("Unit ready")
