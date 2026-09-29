class_name LightRig
extends Node3D
## Lights carried by units and buildings, so night missions are lit by the
## armies themselves: vehicle headlights and tail lights, infantry flashlights
## (Outcast torches, cyborg eyes), aircraft nav lights and belly searchlights,
## hover under-glow, amber beacons on harvesters and the MCV, building
## floodlights and window glow, blinking aviation lights and sweeping
## searchlights on defense towers that lock onto their target.
##
## Brightness follows G.darkness (the mission's night level), building lights
## flicker and die on low power, and each rig switches itself off when it is
## far from the camera. LightRig.attach() is called whenever a model is built.

const FADE_BEGIN := 62.0
const FADE_LENGTH := 14.0

var entity: Entity
var dark := 1.0
var _powered := []           # [Light3D or lamp MeshInstance3D, base energy]
var _flickers := []          # [OmniLight3D, base energy, phase]
var _spinners := []          # [Node3D, speed]
var _pulses := []            # [Light3D, base energy, speed, phase]
var _search: Node3D          # searchlight yaw pivot
var _search_yaw := 0.0
var _search_phase := 0.0
var _t := 0.0
var _check_t := 0.0
var _power_on := true
var _near := true

static var _cone_mesh: ArrayMesh
## Fake beam meshes are drawn only when volumetric fog is not doing it for real.
static var use_cones := true
static var _lens_mesh: SphereMesh
static var _cone_mat: ShaderMaterial
static var _lamp_mat: ShaderMaterial


## Drops the shared meshes and materials (the mission is ending).
static func clear_cache() -> void:
	_cone_mesh = null
	_lens_mesh = null
	_cone_mat = null
	_lamp_mat = null


## Builds the lights that suit this entity's model. Does nothing in daylight.
static func attach(e: Entity) -> void:
	if e.model == null or G.darkness < 0.12:
		return
	var rig := LightRig.new()
	rig.name = "Lights"
	rig.entity = e
	rig.dark = G.darkness
	rig._search_phase = randf() * TAU
	rig._t = randf() * 10.0
	e.model.add_child(rig)
	var b := _bounds(e.model)
	if e.is_structure:
		rig._build_structure(e, b)
	elif e.def.get("category", "") == "infantry":
		rig._build_infantry(e, b)
	else:
		rig._build_vehicle(e, b)


## Local-space bounds of all meshes under `root`.
static func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box := xf * m.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	if first:
		out = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.8, 0.6))
	return out


# ---------------------------------------------------------------- palette

static func _faction_light(fac: String) -> Color:
	match fac:
		"veil":
			return Color(1.0, 0.55, 0.48)
		"outcast":
			return Color(1.0, 0.6, 0.28)
		"creature":
			return Color(0.45, 1.0, 0.6)
		"neutral", "any", "":
			return Color(1.0, 0.82, 0.58)
	return Color(1.0, 0.9, 0.74)


static func _accent(fac: String) -> Color:
	match fac:
		"veil":
			return Color(1.0, 0.12, 0.08)
		"outcast":
			return Color(0.4, 1.0, 0.45)
		"creature":
			return Color(0.35, 1.0, 0.55)
	return Color(1.0, 0.62, 0.15)


# ---------------------------------------------------------------- parts

## soft: unit lights, a gentle pool that fades from the centre and dies off
## within a few cells, instead of a hard-edged far-reaching beam.
func _spot(pos: Vector3, dir: Vector3, color: Color, energy: float, rng: float, angle: float, cone := false, cone_k := 1.0, soft := false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.basis = _aim(dir)
	l.light_color = color
	l.light_energy = energy * dark
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.55 if soft else 1.6
	l.spot_attenuation = 1.9 if soft else 1.1
	l.light_specular = 0.35 if soft else 0.8
	l.light_volumetric_fog_energy = 0.35 if soft else 0.7
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE_BEGIN
	l.distance_fade_length = FADE_LENGTH
	add_child(l)
	if cone and use_cones and Settings.graphics >= 1:
		l.add_child(_cone(rng * 0.8, tan(deg_to_rad(angle)) * rng * 0.8 * 0.85, color, cone_k))
	return l


func _omni(pos: Vector3, color: Color, energy: float, rng: float, soft := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * dark
	l.omni_range = rng
	l.omni_attenuation = 2.0 if soft else 1.4
	l.light_specular = 0.25 if soft else 0.5
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE_BEGIN
	l.distance_fade_length = FADE_LENGTH
	add_child(l)
	return l


## Basis whose -Z (the way lights shine) points along dir.
static func _aim(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	return Basis.looking_at(d, up)


## Glowing lens (0 steady, 1 blink, 2 strobe, 3 flicker).
func _lens(pos: Vector3, color: Color, size := 0.05, mode := 0, energy := 4.0) -> MeshInstance3D:
	if _lens_mesh == null:
		_lens_mesh = SphereMesh.new()
		_lens_mesh.radius = 0.5
		_lens_mesh.height = 1.0
		_lens_mesh.radial_segments = 8
		_lens_mesh.rings = 4
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.shader = load("res://shaders/fx/lamp.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = _lens_mesh
	mi.material_override = _lamp_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size * 2.0
	mi.position = pos
	mi.set_instance_shader_parameter("lamp_color", color)
	mi.set_instance_shader_parameter("energy", energy * (0.5 + 0.5 * dark))
	mi.set_instance_shader_parameter("mode", mode)
	mi.set_instance_shader_parameter("phase", randf() * 3.0)
	add_child(mi)
	return mi


## Fake volumetric beam along -Z from the light.
func _cone(length: float, radius: float, color: Color, k := 1.0) -> MeshInstance3D:
	if _cone_mesh == null:
		_cone_mesh = _make_cone()
		_cone_mat = ShaderMaterial.new()
		_cone_mat.shader = load("res://shaders/fx/light_cone.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh
	mi.material_override = _cone_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, radius, length)
	mi.set_instance_shader_parameter("beam_color", color)
	mi.set_instance_shader_parameter("strength", dark * k)
	mi.visibility_range_end = FADE_BEGIN + FADE_LENGTH
	return mi


## Unit cone: tip at the origin, opening along -Z to radius 1 at length 1.
static func _make_cone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r0 := Vector3(cos(a0), sin(a0), -1.0)
		var r1 := Vector3(cos(a1), sin(a1), -1.0)
		var tip0 := Vector3(cos(a0), sin(a0), 0.0) * 0.08   # small open tip, like a lens
		var tip1 := Vector3(cos(a1), sin(a1), 0.0) * 0.08
		var n0 := Vector3(cos(a0), sin(a0), 0.3).normalized()
		var n1 := Vector3(cos(a1), sin(a1), 0.3).normalized()
		var verts := [tip0, r0, r1, tip0, r1, tip1]
		var norms := [n0, n0, n1, n0, n1, n1]
		var uvs := [Vector2(float(i) / seg, 0), Vector2(float(i) / seg, 1), Vector2(float(i + 1) / seg, 1),
			Vector2(float(i) / seg, 0), Vector2(float(i + 1) / seg, 1), Vector2(float(i + 1) / seg, 0)]
		for j in 6:
			st.set_normal(norms[j])
			st.set_uv(uvs[j])
			st.add_vertex(verts[j])
	return st.commit()


# ---------------------------------------------------------------- builders

func _build_infantry(e: Entity, b: AABB) -> void:
	var fac := e.model_faction()
	var h := b.size.y
	var model: String = e.def.get("model", "")
	if fac == "outcast" or model == "brute" or model == "tallow":
		# a torch held up at shoulder height
		var tl := _omni(Vector3(0.12, h * 0.9, 0.05), Color(1.0, 0.55, 0.2), 1.1, 2.6, true)
		_flickers.append([tl, tl.light_energy, randf() * 10.0])
		_lens(tl.position, Color(1.0, 0.5, 0.15), 0.045, 3, 6.0)
		return
	if model == "civilian" or model == "scientist" or e.def.get("faction", "") == "creature":
		return
	var chest := Vector3(0.07, h * 0.68, b.end.z * 0.6)
	var fwd := Vector3(0, -0.4, 1)
	if model == "cyborg":
		# red optics and a narrow red scanning beam
		_lens(Vector3(0, h * 0.88, b.end.z * 0.5), Color(1.0, 0.1, 0.05), 0.035, 0, 6.0)
		if Settings.graphics >= 1:
			_spot(chest, fwd, Color(1.0, 0.3, 0.25), 1.3, 4.0, 22.0, Settings.graphics >= 2, 0.35, true)
		return
	_lens(chest, Color(0.9, 0.95, 1.0), 0.03, 0, 5.0)
	if Settings.graphics >= 1:
		_spot(chest, fwd, Color(0.86, 0.92, 1.0), 1.6, 4.5, 26.0, Settings.graphics >= 2, 0.35, true)


func _build_vehicle(e: Entity, b: AABB) -> void:
	var fac := e.model_faction()
	var model: String = e.def.get("model", "")
	var col := _faction_light(fac)
	if e.def.get("cloak", false):
		return   # stealth tanks run dark
	if fac == "creature":
		var g := _omni(Vector3(0, b.size.y * 0.5, 0), Color(0.4, 1.0, 0.55), 1.4, 2.6, true)
		_pulses.append([g, g.light_energy, 1.3, randf() * TAU])
		return
	var move: String = e.def.get("move", "ground")
	if move == "air":
		_build_aircraft(b, col)
		return
	var front := b.end.z - 0.02
	var h := b.position.y + b.size.y * 0.32
	var half := b.size.x * 0.32
	# twin headlight lenses, one light between them (cheaper, looks the same from above)
	_lens(Vector3(-half, h, front), Color(1.0, 0.95, 0.85), 0.045, 0, 6.0)
	_lens(Vector3(half, h, front), Color(1.0, 0.95, 0.85), 0.045, 0, 6.0)
	if Settings.graphics >= 1 or e.team == G.local_team:
		var rng := 5.0 + b.size.z
		var spot := _spot(Vector3(0, h, front), Vector3(0, -0.3, 1), col, 2.8, rng, 36.0, false, 1.0, true)
		# cones from each lamp
		if use_cones and Settings.graphics >= 1:
			for sx in [-half, half]:
				var cn := _cone(rng * 0.45, tan(deg_to_rad(24.0)) * rng * 0.45, col, 0.35)
				cn.position = Vector3(sx, h, front)
				cn.basis = _aim(Vector3(0, -0.3, 1)) * Basis.from_scale(Vector3(cn.scale))
				add_child(cn)
		spot.name = "Headlights"
	# red tail lights
	var back := b.position.z + 0.02
	_lens(Vector3(-half * 1.1, h, back), Color(1.0, 0.08, 0.04), 0.035, 0, 4.0)
	_lens(Vector3(half * 1.1, h, back), Color(1.0, 0.08, 0.04), 0.035, 0, 4.0)
	if move == "hover":
		var glow := _omni(Vector3(0, 0.05, 0), Color(0.35, 0.75, 1.0), 1.4, 2.0, true)
		_pulses.append([glow, glow.light_energy, 5.0, randf() * TAU])
	if model == "harvester" or model == "mcv" or e.def.get("heal", false) or model == "sensor_truck":
		_beacon(Vector3(0, b.end.y + 0.06, b.position.z + b.size.z * 0.35), Color(1.0, 0.6, 0.1))


func _build_aircraft(b: AABB, col: Color) -> void:
	var wing := b.size.x * 0.5
	_lens(Vector3(-wing, b.size.y * 0.5, 0), Color(1.0, 0.1, 0.05), 0.04, 1, 6.0)
	_lens(Vector3(wing, b.size.y * 0.5, 0), Color(0.1, 1.0, 0.25), 0.04, 1, 6.0)
	_lens(Vector3(0, b.end.y, b.position.z), Color(1.0, 1.0, 1.0), 0.035, 2, 10.0)
	# belly searchlight sweeping the ground ahead
	var piv := Node3D.new()
	piv.position = Vector3(0, b.position.y, b.end.z * 0.4)
	add_child(piv)
	var l := SpotLight3D.new()
	l.basis = _aim(Vector3(0, -1, 0.6))
	l.light_color = col.lerp(Color.WHITE, 0.5)
	l.light_energy = 3.2 * dark
	l.spot_range = 8.0
	l.spot_angle = 18.0
	l.spot_angle_attenuation = 0.6
	l.spot_attenuation = 1.6
	l.light_volumetric_fog_energy = 0.5
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE_BEGIN
	l.distance_fade_length = FADE_LENGTH
	piv.add_child(l)
	if use_cones and Settings.graphics >= 1:
		l.add_child(_cone(6.0, tan(deg_to_rad(16.0)) * 6.0, l.light_color, 0.5))
	_search = piv   # swept by _process


## Rotating amber warning beacon.
func _beacon(pos: Vector3, color: Color) -> void:
	_lens(pos, color, 0.06, 0, 5.0)
	var piv := Node3D.new()
	piv.position = pos
	add_child(piv)
	var l := SpotLight3D.new()
	l.basis = _aim(Vector3(0, -0.35, 1))
	l.light_color = color
	l.light_energy = 2.4 * dark
	l.spot_range = 3.5
	l.spot_angle = 40.0
	l.spot_angle_attenuation = 0.6
	l.spot_attenuation = 1.8
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE_BEGIN
	l.distance_fade_length = FADE_LENGTH
	piv.add_child(l)
	_spinners.append([piv, 5.5])


func _build_structure(e: Entity, b: AABB) -> void:
	var s := e as Structure
	var fac := e.model_faction()
	var id: String = e.def_id
	var model: String = e.def.get("model", "")
	var col := _faction_light(fac)
	var acc := _accent(fac)
	var sz := Vector2(s.size.x if s else 2, s.size.y if s else 2)
	var top := b.end.y
	if e.def.get("decor", false) or fac == "neutral":
		# homes: warm light spilling out of the windows, fires in huts and tents
		if hash(Vector2i(int(e.position.x), int(e.position.z))) % 3 == 0 and model != "church":
			return
		var wl := _omni(Vector3(0, top * 0.45, sz.y * 0.25), Color(1.0, 0.62, 0.3), 1.6, maxf(sz.x, sz.y) + 1.8)
		if model == "hut" or model == "tent":
			_flickers.append([wl, wl.light_energy, randf() * 10.0])
		_lens(Vector3(sz.x * 0.2, top * 0.45, b.end.z + 0.01), Color(1.0, 0.7, 0.35), 0.06, 3 if model == "hut" else 0, 3.0)
		return
	if fac == "creature" or model == "maw" or model == "blossom":
		var g := _omni(Vector3(0, top * 0.5, 0), Color(0.4, 1.0, 0.55), 2.2, maxf(sz.x, sz.y) + 2.0)
		_pulses.append([g, g.light_energy, 0.8, randf() * TAU])
		return
	# glow around the building: lights its own walls and the ground around it
	var spill := _omni(Vector3(0, top * 0.55, 0), col.lerp(acc, 0.25), 1.1, maxf(sz.x, sz.y) * 0.9 + 1.6)
	_powered.append([spill, spill.light_energy])
	# floodlights on the front corners, aimed at the apron
	var n_flood := 2 if maxf(sz.x, sz.y) >= 3 else 1
	for i in n_flood:
		var x := 0.0 if n_flood == 1 else (-sz.x * 0.38 if i == 0 else sz.x * 0.38)
		var mount := Vector3(x, top * 0.85, b.end.z * 0.9)
		var aim := Vector3(x * 0.3, -0.9, 1.0)
		var fl := _spot(mount, aim, col, 3.6, top + sz.y * 1.2 + 3.5, 40.0, false)
		_powered.append([fl, fl.light_energy])
		_powered.append([_lens(mount, Color(1.0, 0.95, 0.85), 0.07, 0, 6.0), 6.0])
	# red aviation light on tall buildings
	if top > 1.5:
		_powered.append([_lens(Vector3(b.position.x * 0.5, top + 0.05, b.position.z * 0.5), Color(1.0, 0.1, 0.05), 0.06, 1, 8.0), 8.0])
	# per-building character
	match id:
		"power_plant", "tech_power_station":
			var p := _omni(Vector3(0, top * 0.6, 0), Color(0.45, 0.85, 1.0), 2.2, maxf(sz.x, sz.y) + 1.5)
			_pulses.append([p, p.light_energy, 2.2, randf() * TAU])
			_powered.append([p, p.light_energy])
		"refinery":
			var r := _omni(Vector3(0, top * 0.35, 0), Color(0.4, 1.0, 0.45), 1.5, 3.5)
			_pulses.append([r, r.light_energy, 1.5, randf() * TAU])
		"construction_yard":
			_beacon(Vector3(sz.x * 0.35, top + 0.08, -sz.y * 0.3), Color(1.0, 0.6, 0.1))
		"lance_uplink", "lance_control", "lance_relay":
			var up := _spot(Vector3(0, top, 0), Vector3(0, 1, 0), Color(0.6, 0.8, 1.0), 6.0, 20.0, 8.0, true, 1.4)
			_powered.append([up, up.light_energy])
		"stealth_generator", "veil_pylon", "veil_substation":
			var v := _omni(Vector3(0, top * 0.7, 0), Color(0.9, 0.2, 0.6) if id == "stealth_generator" else Color(1.0, 0.15, 0.1), 2.0, 3.0)
			_pulses.append([v, v.light_energy, 1.8, randf() * TAU])
			_powered.append([v, v.light_energy])
		"inhibitor_pylon", "sensor_tower", "resonance_shelter":
			var i2 := _omni(Vector3(0, top * 0.8, 0), Color(0.5, 0.8, 1.0), 1.8, 3.0)
			_pulses.append([i2, i2.light_energy, 2.5, randf() * TAU])
			_powered.append([i2, i2.light_energy])
		"sibyl_relay", "sibyl_core", "data_node", "shaft_guardian":
			var g2 := _omni(Vector3(0, top * 0.6, 0), Color(0.3, 1.0, 0.5), 2.5, maxf(sz.x, sz.y) + 2.0)
			_pulses.append([g2, g2.light_energy, 3.0, randf() * TAU])
	# defenses: a searchlight that sweeps the approaches and locks onto targets
	if not e.weapon.is_empty():
		var mount_y := top + 0.1
		var piv := Node3D.new()
		piv.position = Vector3(0, mount_y, 0)
		add_child(piv)
		var sl := SpotLight3D.new()
		sl.basis = _aim(Vector3(0, -mount_y / 9.0, 1))
		sl.light_color = col.lerp(Color.WHITE, 0.55)
		sl.light_energy = 9.0 * dark
		sl.spot_range = 16.0
		sl.spot_angle = 11.0
		sl.spot_angle_attenuation = 1.3
		sl.light_specular = 0.9
		sl.light_volumetric_fog_energy = 1.6
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = FADE_BEGIN
		sl.distance_fade_length = FADE_LENGTH
		sl.shadow_enabled = Settings.graphics >= 2
		piv.add_child(sl)
		if use_cones and Settings.graphics >= 1:
			sl.add_child(_cone(12.0, tan(deg_to_rad(11.0)) * 12.0, sl.light_color, 1.2))
		_lens(Vector3(0, mount_y, 0.12), Color(1.0, 0.97, 0.9), 0.08, 0, 8.0)
		_powered.append([sl, sl.light_energy])
		_search = piv


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_t += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.3
		var near := Vfx.near_camera(global_position, 18.0)
		if near != _near:
			_near = near
			visible = near
		if entity is Structure:
			var s := entity as Structure
			var on: bool = s.is_built() and (s.def.get("decor", false) or s.powered())
			if on != _power_on:
				_power_on = on
				_set_power(on)
	if not _near:
		return
	for f in _flickers:
		var l: OmniLight3D = f[0]
		var t: float = _t + float(f[2])
		l.light_energy = float(f[1]) * (0.72 + 0.18 * sin(t * 13.0) + 0.1 * sin(t * 29.0 + 1.7))
	for p in _pulses:
		var l: Light3D = p[0]
		if _power_on or not _powered_has(l):
			l.light_energy = float(p[1]) * (0.7 + 0.3 * sin(_t * float(p[2]) + float(p[3])))
	for s in _spinners:
		if float(s[1]) != 0.0:
			(s[0] as Node3D).rotate_y(delta * float(s[1]))
	if _search:
		_update_searchlight(delta)
	if not _power_on and entity is Structure and (entity as Structure).is_built():
		# brown-out: the lights stutter and die back
		var k := 0.15 + (0.6 if randf() < 0.08 else 0.0)
		for pw in _powered:
			_set_energy(pw[0], float(pw[1]) * k)


func _update_searchlight(delta: float) -> void:
	var want := 0.0
	var t = entity.target
	if is_instance_valid(t) and t.alive:
		# lock on: aim straight at the target (model yaw is subtracted: the rig turns with the model)
		var d: Vector3 = t.global_position - _search.global_position
		want = atan2(d.x, d.z) - entity.model.rotation.y
		var dist := Vector2(d.x, d.z).length()
		var pitch := atan2(_search.global_position.y - t.global_position.y - 0.3, maxf(dist, 0.5))
		(_search.get_child(0) as Node3D).basis = _aim(Vector3(0, -tan(pitch), 1))
		_search_yaw = lerp_angle(_search_yaw, want, minf(1.0, delta * 6.0))
	else:
		# idle sweep across the approaches
		_search_phase += delta * (0.35 if entity.is_structure else 0.6)
		want = sin(_search_phase) * (1.4 if entity.is_structure else 0.7)
		_search_yaw = lerp_angle(_search_yaw, want, minf(1.0, delta * 2.0))
	_search.rotation.y = _search_yaw


func _powered_has(l: Object) -> bool:
	for pw in _powered:
		if pw[0] == l:
			return true
	return false


func _set_power(on: bool) -> void:
	for pw in _powered:
		_set_energy(pw[0], float(pw[1]) if on else 0.0)


static func _set_energy(n: Object, e: float) -> void:
	if n is Light3D:
		(n as Light3D).light_energy = e
	elif n is MeshInstance3D:
		(n as MeshInstance3D).set_instance_shader_parameter("energy", e)
