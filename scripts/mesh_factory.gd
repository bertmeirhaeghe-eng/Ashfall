class_name MeshFactory
extends RefCounted
## Builds placeholder models from primitive meshes.
## Every model faces +Z. Metadata on the returned root:
##   "turret"        Node3D that rotates to aim
##   "muzzle_height" float
##   "walker"/"legs" walker leg animation
##   "cutter"/"bin"  harvester parts
## Swap these for real art later: keep the same metadata contract.

static var _mats := {}


static func mat(color: Color, emissive := 0.0, rough := 0.65, metal := 0.25) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), emissive, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, top_r: float, bot_r: float, height: float, pos: Vector3, m: Material, rot := Vector3.ZERO, segments := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Faction palette (design doc 6.1): Bastion = steel/blue-gold, Veil = black/red.
static func palette(faction: String) -> Dictionary:
	if faction == "veil":
		return {"body": Color(0.16, 0.16, 0.18), "trim": Color(0.55, 0.08, 0.06), "dark": Color(0.07, 0.07, 0.08)}
	return {"body": Color(0.56, 0.58, 0.6), "trim": Color(0.85, 0.66, 0.2), "dark": Color(0.18, 0.19, 0.21)}


static func build(model: String, team_color: Color, faction: String) -> Node3D:
	var root := Node3D.new()
	var pal := palette(faction)
	var body := mat(pal["body"])
	var trim := mat(pal["trim"], 0.0, 0.4, 0.6)
	var dark := mat(pal["dark"], 0.0, 0.8, 0.3)
	var tc := mat(team_color, 0.0, 0.5, 0.2)
	var glow := mat(team_color.lightened(0.3), 2.0)
	match model:
		"rifleman", "rocket_trooper":
			box(root, Vector3(0.07, 0.22, 0.08), Vector3(-0.05, 0.11, 0), dark)
			box(root, Vector3(0.07, 0.22, 0.08), Vector3(0.05, 0.11, 0), dark)
			box(root, Vector3(0.2, 0.24, 0.13), Vector3(0, 0.34, 0), tc)
			sphere(root, 0.065, Vector3(0, 0.52, 0), body)
			box(root, Vector3(0.03, 0.03, 0.26), Vector3(0.09, 0.36, 0.1), dark)
			if model == "rocket_trooper":
				cyl(root, 0.045, 0.045, 0.34, Vector3(-0.07, 0.48, 0.02), trim, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("muzzle_height", 0.4)
		"harvester":
			box(root, Vector3(0.95, 0.3, 1.3), Vector3(0, 0.3, 0), body)
			box(root, Vector3(1.0, 0.18, 1.35), Vector3(0, 0.12, 0), dark)
			box(root, Vector3(0.5, 0.3, 0.35), Vector3(-0.2, 0.6, 0.4), tc)
			box(root, Vector3(0.44, 0.1, 0.02), Vector3(-0.2, 0.65, 0.58), glow)
			var bin_root := pivot(root, Vector3(0.1, 0.45, -0.2))
			box(bin_root, Vector3(0.75, 0.5, 0.75), Vector3(0, 0.25, 0), trim)
			root.set_meta("bin", bin_root)
			var cutter := pivot(root, Vector3(0, 0.22, 0.75))
			cyl(cutter, 0.16, 0.16, 0.9, Vector3.ZERO, dark, Vector3(0, 0, PI / 2.0), 6)
			root.set_meta("cutter", cutter)
			root.set_meta("muzzle_height", 0.6)
		"walker":
			var legs: Array = []
			for sx in [-0.22, 0.22]:
				var hip := pivot(root, Vector3(sx, 0.62, 0))
				box(hip, Vector3(0.16, 0.6, 0.2), Vector3(0, -0.3, 0), dark)
				box(hip, Vector3(0.22, 0.06, 0.34), Vector3(0, -0.6, 0.04), body)
				legs.append(hip)
			root.set_meta("walker", true)
			root.set_meta("legs", legs)
			var t := pivot(root, Vector3(0, 0.72, 0))
			box(t, Vector3(0.62, 0.36, 0.6), Vector3(0, 0.1, 0), body)
			box(t, Vector3(0.64, 0.06, 0.62), Vector3(0, 0.3, 0), tc)
			box(t, Vector3(0.3, 0.12, 0.05), Vector3(0, 0.15, 0.31), glow)
			cyl(t, 0.05, 0.06, 0.8, Vector3(0.12, 0.1, 0.62), dark, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("turret", t)
			root.set_meta("muzzle_height", 0.85)
		"scout_mech":
			var legs2: Array = []
			for sx in [-0.14, 0.14]:
				var hip := pivot(root, Vector3(sx, 0.5, 0))
				box(hip, Vector3(0.1, 0.5, 0.14), Vector3(0, -0.25, 0), dark)
				legs2.append(hip)
			root.set_meta("walker", true)
			root.set_meta("legs", legs2)
			var t2 := pivot(root, Vector3(0, 0.6, 0))
			box(t2, Vector3(0.36, 0.3, 0.34), Vector3(0, 0.08, 0), tc)
			box(t2, Vector3(0.2, 0.08, 0.04), Vector3(0, 0.14, 0.18), glow)
			for gx in [-0.22, 0.22]:
				cyl(t2, 0.03, 0.03, 0.4, Vector3(gx, 0.05, 0.2), dark, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t2)
			root.set_meta("muzzle_height", 0.65)
		"tank":
			box(root, Vector3(0.72, 0.22, 0.95), Vector3(0, 0.2, 0), body)
			for sx in [-0.4, 0.4]:
				box(root, Vector3(0.18, 0.22, 1.0), Vector3(sx, 0.12, 0), dark)
			box(root, Vector3(0.5, 0.04, 0.2), Vector3(0, 0.32, 0.38), trim)
			var t3 := pivot(root, Vector3(0, 0.36, -0.05))
			box(t3, Vector3(0.42, 0.18, 0.46), Vector3(0, 0.05, 0), tc)
			cyl(t3, 0.04, 0.05, 0.6, Vector3(0, 0.06, 0.5), dark, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("turret", t3)
			root.set_meta("muzzle_height", 0.42)
		"buggy":
			box(root, Vector3(0.5, 0.16, 0.8), Vector3(0, 0.25, 0), tc)
			box(root, Vector3(0.42, 0.12, 0.3), Vector3(0, 0.38, -0.15), dark)
			for wx in [-0.3, 0.3]:
				for wz in [-0.28, 0.28]:
					cyl(root, 0.13, 0.13, 0.1, Vector3(wx, 0.13, wz), dark, Vector3(0, 0, PI / 2.0), 10)
			var t4 := pivot(root, Vector3(0, 0.45, 0.05))
			box(t4, Vector3(0.12, 0.1, 0.14), Vector3.ZERO, trim)
			cyl(t4, 0.025, 0.025, 0.35, Vector3(0, 0.02, 0.2), dark, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t4)
			root.set_meta("muzzle_height", 0.47)

		# ------------------------------------------------ structures
		"construction_yard":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.4, 0.8, 1.5), Vector3(0, 0.5, -0.5), body)
			box(root, Vector3(2.42, 0.08, 1.52), Vector3(0, 0.92, -0.5), tc)
			box(root, Vector3(1.0, 0.5, 0.9), Vector3(0.6, 0.35, 0.8), body)
			box(root, Vector3(0.22, 2.0, 0.22), Vector3(-1.1, 1.0, 1.1), trim)
			box(root, Vector3(1.8, 0.12, 0.14), Vector3(-0.3, 2.0, 1.1), trim)
			sphere(root, 0.1, Vector3(-1.1, 2.1, 1.1), glow)
			box(root, Vector3(0.8, 0.06, 0.03), Vector3(-0.4, 0.6, 0.26), glow)
		"power_plant":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.6, 0.5, 1.6), Vector3(0, 0.3, 0), body)
			for cx in [-0.4, 0.4]:
				cyl(root, 0.24, 0.32, 1.1, Vector3(cx, 1.0, -0.2), body)
				cyl(root, 0.25, 0.25, 0.1, Vector3(cx, 1.3, -0.2), mat(Color(1.0, 0.8, 0.3), 3.0))
			box(root, Vector3(1.62, 0.06, 0.3), Vector3(0, 0.56, 0.6), tc)
		"refinery":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(1.8, 0.8, 1.6), Vector3(-0.5, 0.5, -0.5), body)
			box(root, Vector3(1.82, 0.08, 1.62), Vector3(-0.5, 0.92, -0.5), tc)
			for sz in [-0.9, 0.2]:
				cyl(root, 0.35, 0.35, 1.3, Vector3(0.95, 0.75, sz), body)
				cyl(root, 0.36, 0.36, 0.08, Vector3(0.95, 1.2, sz), mat(Color(0.3, 1.0, 0.4), 2.0))
			box(root, Vector3(1.2, 0.08, 0.03), Vector3(-0.5, 0.6, 0.31), mat(Color(0.3, 1.0, 0.4), 2.0))
			# unloading pad on the right edge (dock is the cell just outside it)
			box(root, Vector3(0.8, 0.06, 1.0), Vector3(1.1, 0.07, 0.9), trim)
		"barracks":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.6, 0.6, 1.4), Vector3(0, 0.35, -0.1), body)
			var roof := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(1.4, 0.4, 1.7)
			roof.mesh = pm
			roof.position = Vector3(0, 0.85, -0.1)
			roof.rotation = Vector3(0, PI / 2.0, 0)
			roof.material_override = tc
			root.add_child(roof)
			box(root, Vector3(0.4, 0.4, 0.05), Vector3(0, 0.25, 0.62), dark)
			box(root, Vector3(0.6, 0.04, 0.03), Vector3(0, 0.5, 0.62), glow)
		"war_factory":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.6, 1.0, 2.2), Vector3(0, 0.55, -0.2), body)
			for rz in [-0.9, -0.3, 0.3]:
				box(root, Vector3(2.64, 0.1, 0.14), Vector3(0, 1.08, rz), tc)
			box(root, Vector3(1.3, 0.75, 0.05), Vector3(0, 0.42, 0.91), dark)
			box(root, Vector3(1.3, 0.05, 0.05), Vector3(0, 0.85, 0.93), glow)
		"guard_tower":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.28, 0.36, 0.9, Vector3(0, 0.5, 0), body)
			var t5 := pivot(root, Vector3(0, 1.05, 0))
			box(t5, Vector3(0.4, 0.26, 0.46), Vector3.ZERO, tc)
			cyl(t5, 0.05, 0.05, 0.55, Vector3(0, 0.02, 0.4), dark, Vector3(PI / 2.0, 0, 0), 8)
			sphere(t5, 0.05, Vector3(0, 0.16, -0.1), glow)
			root.set_meta("turret", t5)
			root.set_meta("muzzle_height", 1.07)
		_:
			box(root, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), tc)
	return root


static func _slab(root: Node3D, size: Vector2, m: Material) -> void:
	box(root, Vector3(size.x - 0.08, 0.1, size.y - 0.08), Vector3(0, 0.05, 0), m)


## A translucent placement ghost of a footprint.
static func ghost(size: Vector2i) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x - 0.05, 0.6, size.y - 0.05)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.2, 1.0, 0.3, 0.35)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
