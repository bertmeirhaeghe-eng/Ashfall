class_name MeshFactory
extends RefCounted
## Builds placeholder models from primitive meshes.
## Every model faces +Z. Metadata on the returned root:
##   "turret"        Node3D that rotates to aim
##   "muzzle_height" float
##   "walker"/"legs" walker leg animation
##   "cutter"/"bin"  harvester parts
##   "spin"          Node3D spun continuously (radar dishes, rotors)
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


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material, yscale := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 * yscale
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


## Faction palette: Bastion = steel/blue-gold, Veil = black/red, Outcast = patched brown/green,
## creatures = crystal, neutral = civilian stone.
static func palette(faction: String) -> Dictionary:
	match faction:
		"veil":
			return {"body": Color(0.16, 0.16, 0.18), "trim": Color(0.55, 0.08, 0.06), "dark": Color(0.07, 0.07, 0.08)}
		"outcast":
			return {"body": Color(0.38, 0.32, 0.24), "trim": Color(0.3, 0.8, 0.4), "dark": Color(0.16, 0.14, 0.11)}
		"creature":
			return {"body": Color(0.15, 0.45, 0.25), "trim": Color(0.4, 1.0, 0.55), "dark": Color(0.06, 0.18, 0.1)}
		"neutral", "any":
			return {"body": Color(0.62, 0.58, 0.5), "trim": Color(0.55, 0.35, 0.25), "dark": Color(0.25, 0.23, 0.2)}
	return {"body": Color(0.56, 0.58, 0.6), "trim": Color(0.85, 0.66, 0.2), "dark": Color(0.18, 0.19, 0.21)}


static func _soldier(root: Node3D, tc: Material, head: Material, dark: Material, scale := 1.0) -> void:
	box(root, Vector3(0.07, 0.22, 0.08) * scale, Vector3(-0.05, 0.11, 0) * scale, dark)
	box(root, Vector3(0.07, 0.22, 0.08) * scale, Vector3(0.05, 0.11, 0) * scale, dark)
	box(root, Vector3(0.2, 0.24, 0.13) * scale, Vector3(0, 0.34, 0) * scale, tc)
	sphere(root, 0.065 * scale, Vector3(0, 0.52, 0) * scale, head)


static func _wheels(root: Node3D, xs: Array, zs: Array, r: float, m: Material) -> void:
	for wx in xs:
		for wz in zs:
			cyl(root, r, r, 0.1, Vector3(wx, r, wz), m, Vector3(0, 0, PI / 2.0), 10)


static func build(model: String, team_color: Color, faction: String) -> Node3D:
	var root := Node3D.new()
	var pal := palette(faction)
	var body := mat(pal["body"])
	var trim := mat(pal["trim"], 0.0, 0.4, 0.6)
	var dark := mat(pal["dark"], 0.0, 0.8, 0.3)
	var tc := mat(team_color, 0.0, 0.5, 0.2)
	var glow := mat(team_color.lightened(0.3), 2.0)
	var crystal := mat(Color(0.3, 1.0, 0.45), 1.8, 0.15, 0.3)
	var skin := mat(Color(0.75, 0.6, 0.5))
	match model:
		# ------------------------------------------------ infantry
		"rifleman", "rocket_trooper", "engineer", "medic", "skyjumper", "cyborg", "civilian", "scientist", "kestrel", "tallow", "outcast":
			var head := body
			if model == "civilian" or model == "scientist":
				head = skin
			_soldier(root, tc, head, dark)
			match model:
				"rocket_trooper":
					cyl(root, 0.045, 0.045, 0.34, Vector3(-0.07, 0.48, 0.02), trim, Vector3(PI / 2.0, 0, 0), 8)
					box(root, Vector3(0.03, 0.03, 0.26), Vector3(0.09, 0.36, 0.1), dark)
				"engineer":
					box(root, Vector3(0.16, 0.14, 0.08), Vector3(0, 0.36, -0.1), mat(Color(0.9, 0.75, 0.2)))
					sphere(root, 0.07, Vector3(0, 0.56, 0), mat(Color(0.95, 0.8, 0.2)))
				"medic":
					box(root, Vector3(0.1, 0.03, 0.03), Vector3(0, 0.4, 0.07), mat(Color(1, 0.2, 0.2), 1.0))
					box(root, Vector3(0.03, 0.1, 0.03), Vector3(0, 0.4, 0.07), mat(Color(1, 0.2, 0.2), 1.0))
					box(root, Vector3(0.14, 0.14, 0.08), Vector3(0, 0.36, -0.1), mat(Color(0.9, 0.9, 0.9)))
				"skyjumper":
					cyl(root, 0.04, 0.05, 0.22, Vector3(-0.06, 0.34, -0.1), dark, Vector3.ZERO, 6)
					cyl(root, 0.04, 0.05, 0.22, Vector3(0.06, 0.34, -0.1), dark, Vector3.ZERO, 6)
					sphere(root, 0.03, Vector3(-0.06, 0.21, -0.1), glow)
					sphere(root, 0.03, Vector3(0.06, 0.21, -0.1), glow)
					box(root, Vector3(0.03, 0.03, 0.26), Vector3(0.09, 0.36, 0.1), dark)
				"cyborg":
					box(root, Vector3(0.24, 0.1, 0.16), Vector3(0, 0.44, 0), dark)
					sphere(root, 0.025, Vector3(0.03, 0.53, 0.06), mat(Color(1.0, 0.2, 0.2), 3.0))
					box(root, Vector3(0.04, 0.04, 0.3), Vector3(0.1, 0.36, 0.12), dark)
				"scientist":
					box(root, Vector3(0.22, 0.3, 0.15), Vector3(0, 0.3, 0), mat(Color(0.92, 0.92, 0.9)))
					box(root, Vector3(0.12, 0.08, 0.06), Vector3(0.12, 0.28, 0.06), mat(Color(0.3, 1.0, 0.5), 1.5))
				"kestrel":
					box(root, Vector3(0.24, 0.34, 0.16), Vector3(0, 0.3, 0), mat(Color(0.25, 0.08, 0.07)))
					box(root, Vector3(0.03, 0.03, 0.32), Vector3(0.09, 0.38, 0.12), dark)
					sphere(root, 0.07, Vector3(0, 0.53, 0), skin)
				"tallow", "outcast":
					for k in 3:
						box(root, Vector3(0.04, 0.08, 0.04), Vector3(-0.08 + k * 0.05, 0.47 + (k % 2) * 0.03, -0.04), crystal, Vector3(0, 0, 0.3 * (k - 1)))
					box(root, Vector3(0.03, 0.03, 0.26), Vector3(0.09, 0.36, 0.1), dark)
					if model == "tallow":
						box(root, Vector3(0.26, 0.36, 0.16), Vector3(0, 0.3, 0), mat(Color(0.45, 0.4, 0.33)))
						sphere(root, 0.08, Vector3(-0.07, 0.4, 0.02), crystal)
				"civilian":
					box(root, Vector3(0.2, 0.26, 0.13), Vector3(0, 0.32, 0), mat(Color(0.5, 0.45, 0.6)))
				_:
					box(root, Vector3(0.03, 0.03, 0.26), Vector3(0.09, 0.36, 0.1), dark)
			root.set_meta("muzzle_height", 0.4)
		"brute":
			_soldier(root, tc, crystal, dark, 1.5)
			box(root, Vector3(0.12, 0.12, 0.4), Vector3(0.18, 0.45, 0.15), crystal)
			sphere(root, 0.12, Vector3(-0.15, 0.62, 0), crystal)
			root.set_meta("muzzle_height", 0.5)

		# ------------------------------------------------ vehicles
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
		"mcv":
			box(root, Vector3(1.1, 0.35, 1.5), Vector3(0, 0.35, 0), body)
			box(root, Vector3(1.15, 0.18, 1.55), Vector3(0, 0.12, 0), dark)
			box(root, Vector3(0.9, 0.4, 0.7), Vector3(0, 0.72, -0.3), tc)
			box(root, Vector3(0.12, 0.8, 0.12), Vector3(0.35, 0.95, 0.35), trim)
			box(root, Vector3(0.6, 0.08, 0.1), Vector3(0.1, 1.3, 0.35), trim)
			box(root, Vector3(0.5, 0.08, 0.02), Vector3(0, 0.55, 0.76), glow)
		"sensor_truck":
			box(root, Vector3(0.7, 0.3, 1.0), Vector3(0, 0.35, 0), body)
			_wheels(root, [-0.38, 0.38], [-0.3, 0.3], 0.15, dark)
			box(root, Vector3(0.6, 0.25, 0.35), Vector3(0, 0.62, 0.25), tc)
			var dish := pivot(root, Vector3(0, 0.95, -0.2))
			cyl(dish, 0.35, 0.05, 0.12, Vector3.ZERO, trim, Vector3(0.6, 0, 0), 14)
			sphere(dish, 0.05, Vector3(0, 0.12, 0.05), glow)
			root.set_meta("spin", dish)
		"hover":
			box(root, Vector3(0.7, 0.14, 0.95), Vector3(0, 0.12, 0), dark)
			box(root, Vector3(0.6, 0.18, 0.8), Vector3(0, 0.28, 0), body)
			box(root, Vector3(0.72, 0.03, 0.97), Vector3(0, 0.05, 0), glow)
			var t_h := pivot(root, Vector3(0, 0.42, -0.05))
			box(t_h, Vector3(0.44, 0.16, 0.4), Vector3.ZERO, tc)
			for rx in [-0.12, 0.0, 0.12]:
				cyl(t_h, 0.04, 0.04, 0.3, Vector3(rx, 0.05, 0.2), trim, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t_h)
			root.set_meta("muzzle_height", 0.5)
		"apc":
			box(root, Vector3(0.8, 0.4, 1.2), Vector3(0, 0.35, 0), body)
			box(root, Vector3(0.84, 0.16, 1.24), Vector3(0, 0.1, 0), dark)
			box(root, Vector3(0.82, 0.04, 0.3), Vector3(0, 0.56, 0.3), tc)
			box(root, Vector3(0.4, 0.06, 0.02), Vector3(0, 0.45, 0.61), glow)
			var t_a := pivot(root, Vector3(0, 0.62, -0.1))
			box(t_a, Vector3(0.22, 0.12, 0.22), Vector3.ZERO, trim)
			cyl(t_a, 0.025, 0.025, 0.3, Vector3(0, 0.02, 0.2), dark, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t_a)
			root.set_meta("muzzle_height", 0.64)
		"resonator":
			box(root, Vector3(0.75, 0.26, 1.0), Vector3(0, 0.22, 0), body)
			for sx in [-0.42, 0.42]:
				box(root, Vector3(0.16, 0.24, 1.05), Vector3(sx, 0.12, 0), dark)
			var t_r := pivot(root, Vector3(0, 0.45, 0))
			cyl(t_r, 0.18, 0.22, 0.2, Vector3.ZERO, tc)
			cyl(t_r, 0.28, 0.08, 0.3, Vector3(0, 0.12, 0.3), trim, Vector3(PI / 2.0, 0, 0), 14)
			sphere(t_r, 0.07, Vector3(0, 0.12, 0.42), mat(Color(0.5, 0.9, 1.0), 2.5))
			root.set_meta("turret", t_r)
			root.set_meta("muzzle_height", 0.6)
		"bulwark":
			var legs_b: Array = []
			for sx in [-0.45, 0.45]:
				var hip_b := pivot(root, Vector3(sx, 1.1, 0))
				box(hip_b, Vector3(0.3, 1.1, 0.4), Vector3(0, -0.55, 0), dark)
				box(hip_b, Vector3(0.45, 0.1, 0.65), Vector3(0, -1.08, 0.08), body)
				legs_b.append(hip_b)
			root.set_meta("walker", true)
			root.set_meta("legs", legs_b)
			var t_b := pivot(root, Vector3(0, 1.3, 0))
			box(t_b, Vector3(1.3, 0.6, 1.1), Vector3(0, 0.15, 0), body)
			box(t_b, Vector3(1.32, 0.1, 1.12), Vector3(0, 0.5, 0), tc)
			for gx in [-0.35, 0.35]:
				cyl(t_b, 0.09, 0.1, 1.2, Vector3(gx, 0.15, 0.9), dark, Vector3(PI / 2.0, 0, 0), 8)
			box(t_b, Vector3(0.5, 0.12, 0.05), Vector3(0, 0.25, 0.56), glow)
			root.set_meta("turret", t_b)
			root.set_meta("muzzle_height", 1.45)
		"kite":
			box(root, Vector3(0.36, 0.2, 0.9), Vector3(0, 0.1, 0), body)
			box(root, Vector3(1.2, 0.04, 0.3), Vector3(0, 0.12, -0.05), tc)
			for sx in [-0.6, 0.6]:
				var rot_n := pivot(root, Vector3(sx, 0.2, -0.05))
				cyl(rot_n, 0.3, 0.3, 0.02, Vector3.ZERO, mat(Color(0.2, 0.2, 0.2, 1.0)), Vector3.ZERO, 12)
				cyl(root, 0.08, 0.08, 0.12, Vector3(sx, 0.14, -0.05), dark, Vector3.ZERO, 8)
			box(root, Vector3(0.2, 0.08, 0.02), Vector3(0, 0.15, 0.46), glow)
			root.set_meta("muzzle_height", 0.1)
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
				var hip2 := pivot(root, Vector3(sx, 0.5, 0))
				box(hip2, Vector3(0.1, 0.5, 0.14), Vector3(0, -0.25, 0), dark)
				legs2.append(hip2)
			root.set_meta("walker", true)
			root.set_meta("legs", legs2)
			var t2 := pivot(root, Vector3(0, 0.6, 0))
			box(t2, Vector3(0.36, 0.3, 0.34), Vector3(0, 0.08, 0), tc)
			box(t2, Vector3(0.2, 0.08, 0.04), Vector3(0, 0.14, 0.18), glow)
			for gx in [-0.22, 0.22]:
				cyl(t2, 0.03, 0.03, 0.4, Vector3(gx, 0.05, 0.2), dark, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t2)
			root.set_meta("muzzle_height", 0.65)
		"tank", "shade_tank", "artillery":
			box(root, Vector3(0.72, 0.22, 0.95), Vector3(0, 0.2, 0), body)
			for sx in [-0.4, 0.4]:
				box(root, Vector3(0.18, 0.22, 1.0), Vector3(sx, 0.12, 0), dark)
			box(root, Vector3(0.5, 0.04, 0.2), Vector3(0, 0.32, 0.38), trim)
			var t3 := pivot(root, Vector3(0, 0.36, -0.05))
			if model == "shade_tank":
				box(t3, Vector3(0.46, 0.14, 0.5), Vector3(0, 0.04, 0), dark)
				box(t3, Vector3(0.48, 0.02, 0.52), Vector3(0, 0.12, 0), mat(Color(0.5, 0.2, 0.8), 1.5))
				cyl(t3, 0.04, 0.05, 0.6, Vector3(0, 0.05, 0.5), dark, Vector3(PI / 2.0, 0, 0), 8)
			elif model == "artillery":
				box(t3, Vector3(0.4, 0.2, 0.5), Vector3(0, 0.06, 0), tc)
				cyl(t3, 0.06, 0.07, 1.0, Vector3(0, 0.3, 0.4), dark, Vector3(PI / 2.0 - 0.5, 0, 0), 8)
			else:
				box(t3, Vector3(0.42, 0.18, 0.46), Vector3(0, 0.05, 0), tc)
				cyl(t3, 0.04, 0.05, 0.6, Vector3(0, 0.06, 0.5), dark, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("turret", t3)
			root.set_meta("muzzle_height", 0.42)
		"buggy":
			box(root, Vector3(0.5, 0.16, 0.8), Vector3(0, 0.25, 0), tc)
			box(root, Vector3(0.42, 0.12, 0.3), Vector3(0, 0.38, -0.15), dark)
			_wheels(root, [-0.3, 0.3], [-0.28, 0.28], 0.13, dark)
			var t4 := pivot(root, Vector3(0, 0.45, 0.05))
			box(t4, Vector3(0.12, 0.1, 0.14), Vector3.ZERO, trim)
			cyl(t4, 0.025, 0.025, 0.35, Vector3(0, 0.02, 0.2), dark, Vector3(PI / 2.0, 0, 0), 6)
			root.set_meta("turret", t4)
			root.set_meta("muzzle_height", 0.47)
		"drill", "mole":
			box(root, Vector3(0.7, 0.35, 1.0), Vector3(0, 0.3, -0.05), body)
			for sx in [-0.4, 0.4]:
				box(root, Vector3(0.16, 0.24, 1.0), Vector3(sx, 0.12, 0), dark)
			cyl(root, 0.0, 0.32, 0.6, Vector3(0, 0.3, 0.7), trim, Vector3(PI / 2.0, 0, 0), 10)
			box(root, Vector3(0.5, 0.05, 0.4), Vector3(0, 0.5, -0.1), tc)
			if model == "drill":
				sphere(root, 0.08, Vector3(0, 0.3, 0.95), mat(Color(1.0, 0.5, 0.1), 3.0))
			else:
				cyl(root, 0.3, 0.3, 0.05, Vector3(0, 0.52, -0.2), mat(Color(0.4, 0.8, 1.0), 1.2), Vector3.ZERO, 16)
			root.set_meta("muzzle_height", 0.35)
		"truck", "bus", "damper":
			var cab_m := tc
			if model == "bus":
				box(root, Vector3(0.75, 0.55, 1.6), Vector3(0, 0.45, 0), mat(Color(0.85, 0.7, 0.25)))
				box(root, Vector3(0.77, 0.12, 1.3), Vector3(0, 0.55, -0.05), mat(Color(0.3, 0.45, 0.6), 0.3))
				_wheels(root, [-0.4, 0.4], [-0.55, 0.55], 0.16, dark)
			else:
				box(root, Vector3(0.7, 0.4, 0.4), Vector3(0, 0.4, 0.5), cab_m)
				box(root, Vector3(0.72, 0.1, 1.3), Vector3(0, 0.2, 0), dark)
				_wheels(root, [-0.38, 0.38], [-0.45, 0.1, 0.5], 0.15, dark)
				if model == "damper":
					cyl(root, 0.3, 0.3, 0.7, Vector3(0, 0.6, -0.25), body, Vector3.ZERO, 14)
					for k in 3:
						cyl(root, 0.33, 0.33, 0.04, Vector3(0, 0.35 + k * 0.25, -0.25), mat(Color(0.4, 0.8, 1.0), 2.0), Vector3.ZERO, 14)
				else:
					box(root, Vector3(0.7, 0.5, 0.85), Vector3(0, 0.5, -0.2), body)
					if faction == "bastion":
						box(root, Vector3(0.2, 0.06, 0.02), Vector3(0, 0.6, 0.23), mat(Color(1, 0.2, 0.2), 1.0))
		"floater":
			sphere(root, 0.4, Vector3(0, 0.9, 0), mat(Color(0.3, 0.8, 0.5, 1.0), 0.6, 0.2))
			for k in 5:
				var a := TAU * k / 5.0
				cyl(root, 0.03, 0.01, 0.6, Vector3(cos(a) * 0.25, 0.45, sin(a) * 0.25), crystal, Vector3(0.2 * cos(a), 0, 0.2 * sin(a)), 5)
			sphere(root, 0.1, Vector3(0, 0.9, 0.35), crystal)
			root.set_meta("muzzle_height", 0.9)
		"fiend":
			box(root, Vector3(0.4, 0.3, 0.8), Vector3(0, 0.35, 0), mat(Color(0.12, 0.3, 0.18)))
			for k in 4:
				cyl(root, 0.0, 0.08, 0.5, Vector3(0, 0.55, -0.3 + k * 0.2), crystal, Vector3(0.3, 0, 0), 5)
			for sx in [-0.18, 0.18]:
				for sz in [-0.25, 0.25]:
					box(root, Vector3(0.06, 0.25, 0.06), Vector3(sx, 0.12, sz), dark)
			sphere(root, 0.12, Vector3(0, 0.4, 0.45), crystal)
			root.set_meta("muzzle_height", 0.4)
		"choir":
			cyl(root, 0.9, 1.2, 1.2, Vector3(0, 0.6, 0), mat(Color(0.1, 0.12, 0.12)), Vector3.ZERO, 10)
			for k in 8:
				var a2 := TAU * k / 8.0
				cyl(root, 0.0, 0.25, 2.2, Vector3(cos(a2) * 0.8, 1.6, sin(a2) * 0.8), crystal, Vector3(0.35 * sin(a2), 0, -0.35 * cos(a2)), 6)
			sphere(root, 0.5, Vector3(0, 2.2, 0), mat(Color(0.6, 1.0, 0.7), 3.0))
			var sh := sphere(root, 1.7, Vector3(0, 1.4, 0), mat(Color(0.4, 1.0, 0.7, 1.0), 0.8, 0.1))
			sh.transparency = 0.75
			root.set_meta("shield", sh)
			root.set_meta("muzzle_height", 2.2)

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
			box(root, Vector3(0.8, 0.06, 1.0), Vector3(1.1, 0.07, 0.9), trim)
		"barracks", "veil_camp":
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
		"war_factory", "veil_foundry":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.6, 1.0, 2.2), Vector3(0, 0.55, -0.2), body)
			for rz in [-0.9, -0.3, 0.3]:
				box(root, Vector3(2.64, 0.1, 0.14), Vector3(0, 1.08, rz), tc)
			box(root, Vector3(1.3, 0.75, 0.05), Vector3(0, 0.42, 0.91), dark)
			box(root, Vector3(1.3, 0.05, 0.05), Vector3(0, 0.85, 0.93), glow)
			if model == "veil_foundry":
				for sx in [-1.0, 1.0]:
					cyl(root, 0.0, 0.25, 1.4, Vector3(sx, 1.6, -0.8), trim, Vector3.ZERO, 6)
		"radar":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.4, 0.6, 1.4), Vector3(0, 0.3, 0), body)
			box(root, Vector3(1.42, 0.06, 1.42), Vector3(0, 0.62, 0), tc)
			var dish2 := pivot(root, Vector3(0, 1.2, 0))
			cyl(dish2, 0.6, 0.1, 0.18, Vector3.ZERO, trim, Vector3(0.7, 0, 0), 16)
			cyl(root, 0.06, 0.08, 0.6, Vector3(0, 0.9, 0), dark)
			root.set_meta("spin", dish2)
		"service_depot":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.6, 0.08, 2.6), Vector3(0, 0.12, 0), mat(Color(0.3, 0.32, 0.34)))
			for c in [Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(-1.1, 1.1), Vector2(1.1, 1.1)]:
				box(root, Vector3(0.2, 1.0, 0.2), Vector3(c.x, 0.5, c.y), body)
			box(root, Vector3(2.4, 0.1, 0.2), Vector3(0, 1.0, -1.1), tc)
			box(root, Vector3(2.4, 0.1, 0.2), Vector3(0, 1.0, 1.1), tc)
			box(root, Vector3(0.6, 0.04, 0.6), Vector3(0, 0.18, 0), glow)
		"helipad":
			_slab(root, Vector2(2, 2), dark)
			cyl(root, 0.9, 0.95, 0.12, Vector3(0, 0.12, 0), body, Vector3.ZERO, 20)
			box(root, Vector3(0.6, 0.02, 0.1), Vector3(0, 0.2, 0), glow)
			box(root, Vector3(0.1, 0.02, 0.6), Vector3(-0.25, 0.2, 0), glow)
			box(root, Vector3(0.1, 0.02, 0.6), Vector3(0.25, 0.2, 0), glow)
		"tech_center":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.5, 0.9, 1.5), Vector3(0, 0.45, 0), body)
			sphere(root, 0.6, Vector3(0, 1.0, 0), mat(Color(0.5, 0.8, 1.0, 1.0), 0.6, 0.1, 0.5), 0.8)
			box(root, Vector3(1.52, 0.08, 1.52), Vector3(0, 0.85, 0), tc)
		"uplink":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.2, 0.6, 2.2), Vector3(0, 0.3, 0), body)
			cyl(root, 0.2, 0.35, 1.6, Vector3(0, 1.3, 0), trim)
			var dish3 := pivot(root, Vector3(0, 2.2, 0))
			cyl(dish3, 0.9, 0.1, 0.25, Vector3.ZERO, body, Vector3(-0.5, 0, 0), 20)
			sphere(dish3, 0.12, Vector3(0, 0.25, -0.1), mat(Color(1.0, 1.0, 0.9), 3.0))
			box(root, Vector3(2.22, 0.08, 2.22), Vector3(0, 0.62, 0), tc)
		"decoy":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.4, 1.2, 2.4), Vector3(0, 0.6, 0), mat(Color(0.6, 0.62, 0.64, 1.0), 0.0, 0.9, 0.0))
			box(root, Vector3(2.42, 0.1, 2.42), Vector3(0, 1.25, 0), tc)
			sphere(root, 0.5, Vector3(0, 1.5, 0), mat(Color(0.6, 0.62, 0.64)), 0.6)
		"guard_tower":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.28, 0.36, 0.9, Vector3(0, 0.5, 0), body)
			var t5 := pivot(root, Vector3(0, 1.05, 0))
			box(t5, Vector3(0.4, 0.26, 0.46), Vector3.ZERO, tc)
			cyl(t5, 0.05, 0.05, 0.55, Vector3(0, 0.02, 0.4), dark, Vector3(PI / 2.0, 0, 0), 8)
			sphere(t5, 0.05, Vector3(0, 0.16, -0.1), glow)
			root.set_meta("turret", t5)
			root.set_meta("muzzle_height", 1.07)
		"sensor_tower":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.08, 0.2, 1.8, Vector3(0, 0.9, 0), body, Vector3.ZERO, 8)
			var dish4 := pivot(root, Vector3(0, 1.9, 0))
			cyl(dish4, 0.3, 0.05, 0.1, Vector3.ZERO, trim, Vector3(0.8, 0, 0), 12)
			sphere(root, 0.07, Vector3(0, 2.05, 0), glow)
			root.set_meta("spin", dish4)
		"inhibitor":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.1, 0.3, 1.6, Vector3(0, 0.8, 0), body, Vector3.ZERO, 6)
			for k in 3:
				cyl(root, 0.32 - k * 0.06, 0.32 - k * 0.06, 0.04, Vector3(0, 0.6 + k * 0.45, 0), mat(Color(0.5, 0.8, 1.0), 2.0), Vector3.ZERO, 12)
			sphere(root, 0.12, Vector3(0, 1.75, 0), mat(Color(0.6, 0.9, 1.0), 3.0))
		"shelter":
			_slab(root, Vector2(2, 2), dark)
			cyl(root, 0.8, 0.9, 0.4, Vector3(0, 0.2, 0), body, Vector3.ZERO, 16)
			var dome := sphere(root, 0.9, Vector3(0, 0.4, 0), mat(Color(0.4, 0.8, 1.0, 1.0), 0.9, 0.1), 0.8)
			dome.transparency = 0.6
		"beacon":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.05, 0.15, 1.6, Vector3(0, 0.8, 0), trim, Vector3.ZERO, 6)
			sphere(root, 0.12, Vector3(0, 1.7, 0), mat(Color(1.0, 0.95, 0.6), 4.0))
			root.set_meta("spin", pivot(root, Vector3.ZERO))
		"pylon":
			_slab(root, Vector2(1, 1), dark)
			for sx in [-0.25, 0.25]:
				box(root, Vector3(0.06, 2.0, 0.06), Vector3(sx, 1.0, 0), body, Vector3(0, 0, -sx * 0.25))
			box(root, Vector3(0.9, 0.06, 0.06), Vector3(0, 1.8, 0), body)
			for sx in [-0.4, 0.4]:
				sphere(root, 0.05, Vector3(sx, 1.75, 0), mat(Color(1.0, 0.25, 0.2), 2.5))
		"substation":
			_slab(root, Vector2(2, 2), dark)
			for k in 3:
				box(root, Vector3(0.35, 0.8, 0.35), Vector3(-0.5 + k * 0.5, 0.4, -0.2), body)
				sphere(root, 0.08, Vector3(-0.5 + k * 0.5, 0.9, -0.2), mat(Color(1.0, 0.3, 0.2), 2.0))
			box(root, Vector3(1.6, 0.3, 0.4), Vector3(0, 0.15, 0.55), tc)
		"stealth_gen":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.4, 0.5, 1.4), Vector3(0, 0.25, 0), body)
			cyl(root, 0.1, 0.4, 1.6, Vector3(0, 1.2, 0), trim, Vector3.ZERO, 8)
			var orb := sphere(root, 0.45, Vector3(0, 2.2, 0), mat(Color(0.6, 0.3, 1.0), 2.5))
			orb.transparency = 0.3
		"spire":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.05, 0.4, 3.0, Vector3(0, 1.5, 0), body, Vector3.ZERO, 5)
			var t6 := pivot(root, Vector3(0, 3.0, 0))
			sphere(t6, 0.2, Vector3.ZERO, mat(Color(1.0, 0.3, 0.9), 3.5))
			root.set_meta("turret", t6)
			root.set_meta("muzzle_height", 3.0)
		"gatehouse":
			_slab(root, Vector2(3, 2), dark)
			for sx in [-1.1, 1.1]:
				box(root, Vector3(0.7, 1.8, 1.6), Vector3(sx, 0.9, 0), body)
				box(root, Vector3(0.72, 0.1, 1.62), Vector3(sx, 1.8, 0), tc)
			box(root, Vector3(1.6, 0.5, 1.2), Vector3(0, 1.55, 0), body)
			var t7 := pivot(root, Vector3(0, 1.9, 0))
			box(t7, Vector3(0.4, 0.2, 0.4), Vector3.ZERO, tc)
			cyl(t7, 0.05, 0.05, 0.5, Vector3(0, 0, 0.35), dark, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("turret", t7)
			root.set_meta("muzzle_height", 1.9)
		"artillery_nest":
			_slab(root, Vector2(2, 2), dark)
			cyl(root, 0.8, 0.9, 0.4, Vector3(0, 0.2, 0), body, Vector3.ZERO, 12)
			var t8 := pivot(root, Vector3(0, 0.55, 0))
			box(t8, Vector3(0.6, 0.3, 0.7), Vector3.ZERO, tc)
			cyl(t8, 0.08, 0.09, 1.4, Vector3(0, 0.35, 0.6), dark, Vector3(PI / 2.0 - 0.5, 0, 0), 8)
			root.set_meta("turret", t8)
			root.set_meta("muzzle_height", 1.0)
		"flak_nest":
			_slab(root, Vector2(1, 1), dark)
			cyl(root, 0.35, 0.4, 0.4, Vector3(0, 0.2, 0), body, Vector3.ZERO, 10)
			var t9 := pivot(root, Vector3(0, 0.5, 0))
			box(t9, Vector3(0.3, 0.2, 0.3), Vector3.ZERO, tc)
			for gx in [-0.1, 0.1]:
				cyl(t9, 0.03, 0.03, 0.5, Vector3(gx, 0.2, 0.15), dark, Vector3(PI / 2.0 - 0.9, 0, 0), 6)
			root.set_meta("turret", t9)
			root.set_meta("muzzle_height", 0.8)
		"tent":
			var tent := MeshInstance3D.new()
			var tp := PrismMesh.new()
			tp.size = Vector3(0.9, 0.7, 0.9)
			tent.mesh = tp
			tent.position = Vector3(0, 0.35, 0)
			tent.material_override = mat(Color(0.55, 0.45, 0.35)) if faction != "veil" else tc
			root.add_child(tent)
			if faction == "veil":
				var tent2 := MeshInstance3D.new()
				var tp2 := PrismMesh.new()
				tp2.size = Vector3(1.6, 0.9, 1.6)
				tent2.mesh = tp2
				tent2.position = Vector3(0, 0.45, 0)
				tent2.material_override = dark
				root.add_child(tent2)
				tent.position = Vector3(0.5, 0.35, 0.5)
		"relay":
			_slab(root, Vector2(2, 2), dark)
			cyl(root, 0.15, 0.6, 3.2, Vector3(0, 1.6, 0), body, Vector3.ZERO, 6)
			for k in 4:
				cyl(root, 0.5 - k * 0.1, 0.5 - k * 0.1, 0.05, Vector3(0, 0.8 + k * 0.6, 0), mat(Color(0.4, 1.0, 0.6), 2.5), Vector3.ZERO, 12)
			sphere(root, 0.2, Vector3(0, 3.3, 0), mat(Color(0.4, 1.0, 0.6), 3.0))
		"guardian":
			_slab(root, Vector2(3, 3), dark)
			cyl(root, 1.1, 1.4, 1.0, Vector3(0, 0.5, 0), body, Vector3.ZERO, 8)
			for k in 6:
				var a3 := TAU * k / 6.0
				cyl(root, 0.0, 0.3, 2.4, Vector3(cos(a3) * 0.8, 1.8, sin(a3) * 0.8), crystal, Vector3(0.25 * sin(a3), 0, -0.25 * cos(a3)), 6)
			var t10 := pivot(root, Vector3(0, 2.6, 0))
			sphere(t10, 0.35, Vector3.ZERO, mat(Color(0.5, 1.0, 0.6), 3.0))
			root.set_meta("turret", t10)
			root.set_meta("muzzle_height", 2.6)
		"core":
			_slab(root, Vector2(3, 3), dark)
			cyl(root, 1.2, 1.4, 0.6, Vector3(0, 0.3, 0), body, Vector3.ZERO, 12)
			sphere(root, 0.9, Vector3(0, 1.5, 0), mat(Color(0.3, 1.0, 0.5), 2.5))
			for k in 3:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 1.1 + k * 0.2
				tm.outer_radius = 1.2 + k * 0.2
				ring.mesh = tm
				ring.position = Vector3(0, 1.5, 0)
				ring.rotation = Vector3(0.6 * k, 0.4 * k, 0)
				ring.material_override = trim
				root.add_child(ring)
			root.set_meta("spin", root.get_child(root.get_child_count() - 1))
		"coal_plant":
			_slab(root, Vector2(3, 3), dark)
			box(root, Vector3(2.4, 1.2, 1.6), Vector3(0, 0.6, 0.4), mat(Color(0.4, 0.3, 0.25)))
			for cx in [-0.7, 0.7]:
				cyl(root, 0.25, 0.35, 2.4, Vector3(cx, 1.2, -0.8), mat(Color(0.35, 0.3, 0.28)))
			box(root, Vector3(2.42, 0.1, 1.62), Vector3(0, 1.2, 0.4), tc)
		"dam_control":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.6, 1.0, 1.6), Vector3(0, 0.5, 0), mat(Color(0.6, 0.56, 0.48)))
			box(root, Vector3(1.62, 0.12, 1.62), Vector3(0, 1.0, 0), tc)
			cyl(root, 0.04, 0.04, 1.0, Vector3(0.5, 1.5, 0.5), dark)
			sphere(root, 0.06, Vector3(0.5, 2.0, 0.5), glow)
		"pillar":
			box(root, Vector3(0.9, 2.0, 0.9), Vector3(0, 1.0, 0), mat(Color(0.62, 0.58, 0.5)))
			box(root, Vector3(0.95, 0.12, 0.95), Vector3(0, 2.0, 0), tc)
		"water_station":
			_slab(root, Vector2(2, 2), dark)
			cyl(root, 0.55, 0.55, 1.0, Vector3(-0.2, 1.3, -0.2), mat(Color(0.5, 0.48, 0.44)), Vector3.ZERO, 14)
			for c2 in [Vector2(-0.6, -0.6), Vector2(0.2, -0.6), Vector2(-0.6, 0.2), Vector2(0.2, 0.2)]:
				box(root, Vector3(0.08, 0.9, 0.08), Vector3(c2.x, 0.45, c2.y), dark)
			box(root, Vector3(0.6, 0.5, 0.5), Vector3(0.6, 0.25, 0.6), tc)
		"bridge":
			box(root, Vector3(3.0, 0.2, 3.0), Vector3(0, 0.15, 0), mat(Color(0.35, 0.3, 0.26)))
			for sx in [-1.4, 1.4]:
				box(root, Vector3(0.1, 0.3, 3.0), Vector3(sx, 0.35, 0), dark)
			for sz in [-1.0, 0.0, 1.0]:
				box(root, Vector3(0.3, 0.6, 0.3), Vector3(-1.2, -0.1, sz), dark)
				box(root, Vector3(0.3, 0.6, 0.3), Vector3(1.2, -0.1, sz), dark)
		"mine_exit":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.8, 1.0, 1.4), Vector3(0, 0.5, -0.2), mat(Color(0.35, 0.3, 0.26)))
			box(root, Vector3(0.8, 0.7, 0.1), Vector3(0, 0.35, 0.55), mat(Color(0.03, 0.03, 0.03)))
			box(root, Vector3(1.0, 0.1, 0.12), Vector3(0, 0.75, 0.56), mat(Color(0.4, 0.28, 0.15)))
		"bunker":
			_slab(root, Vector2(3, 3), dark)
			cyl(root, 1.2, 1.4, 0.9, Vector3(0, 0.45, 0), body, Vector3.ZERO, 8)
			box(root, Vector3(1.6, 0.08, 0.1), Vector3(0, 0.7, 1.2), glow)
			var t11 := pivot(root, Vector3(0, 1.0, 0))
			box(t11, Vector3(0.5, 0.25, 0.5), Vector3.ZERO, tc)
			cyl(t11, 0.05, 0.05, 0.6, Vector3(0, 0, 0.4), dark, Vector3(PI / 2.0, 0, 0), 8)
			root.set_meta("turret", t11)
			root.set_meta("muzzle_height", 1.0)
		"field_hq":
			_slab(root, Vector2(3, 2), dark)
			box(root, Vector3(2.6, 0.8, 1.6), Vector3(0, 0.4, 0), body)
			box(root, Vector3(2.62, 0.08, 1.62), Vector3(0, 0.82, 0), tc)
			cyl(root, 0.03, 0.03, 1.4, Vector3(1.0, 1.5, 0), dark)
			box(root, Vector3(0.4, 0.25, 0.02), Vector3(1.2, 2.0, 0), tc)
		"lance_relay":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.4, 0.6, 1.4), Vector3(0, 0.3, 0), body)
			for k in 3:
				cyl(root, 0.18, 0.18, 0.5, Vector3(-0.4 + k * 0.4, 0.85, 0), mat(Color(0.6, 0.8, 1.0), 1.5), Vector3.ZERO, 10)
			cyl(root, 0.03, 0.03, 1.2, Vector3(0, 1.8, 0), dark)
		"city_gate":
			_slab(root, Vector2(4, 2), dark)
			for sx in [-1.6, 1.6]:
				box(root, Vector3(0.8, 2.2, 1.8), Vector3(sx, 1.1, 0), body)
			box(root, Vector3(2.4, 1.6, 0.5), Vector3(0, 0.8, 0), mat(Color(0.3, 0.32, 0.35)))
			box(root, Vector3(4.0, 0.2, 1.9), Vector3(0, 2.2, 0), tc)
		"data_node":
			box(root, Vector3(0.6, 0.8, 0.6), Vector3(0, 0.4, 0), dark)
			for k in 4:
				box(root, Vector3(0.62, 0.03, 0.62), Vector3(0, 0.15 + k * 0.18, 0), mat(Color(0.4, 1.0, 0.6), 2.5))
		"maw":
			sphere(root, 1.0, Vector3(0, 0.2, 0), mat(Color(0.08, 0.18, 0.1)), 0.5)
			for k in 7:
				var a4 := TAU * k / 7.0
				cyl(root, 0.0, 0.18, 1.2, Vector3(cos(a4) * 0.7, 0.6, sin(a4) * 0.7), crystal, Vector3(0.5 * sin(a4), 0, -0.5 * cos(a4)), 5)
			sphere(root, 0.35, Vector3(0, 0.45, 0), mat(Color(0.8, 1.0, 0.3), 2.0))
		"blossom":
			cyl(root, 0.12, 0.25, 1.4, Vector3(0, 0.7, 0), mat(Color(0.2, 0.25, 0.15)))
			for k in 5:
				var a5: float = TAU * k / 5.0
				sphere(root, 0.26, Vector3(cos(a5) * 0.35, 1.35 + 0.15 * (k % 2), sin(a5) * 0.35), mat(Color(0.3, 0.9, 0.35), 1.2))
		"house":
			_slab(root, Vector2(2, 2), dark)
			box(root, Vector3(1.4, 0.8, 1.2), Vector3(0, 0.4, 0), mat(Color(0.7, 0.66, 0.58)))
			var roof2 := MeshInstance3D.new()
			var pm2 := PrismMesh.new()
			pm2.size = Vector3(1.5, 0.6, 1.3)
			roof2.mesh = pm2
			roof2.position = Vector3(0, 1.1, 0)
			roof2.material_override = mat(Color(0.5, 0.22, 0.16))
			root.add_child(roof2)
		"church":
			_slab(root, Vector2(2, 3), dark)
			box(root, Vector3(1.6, 1.0, 2.4), Vector3(0, 0.5, 0.1), mat(Color(0.6, 0.57, 0.52)))
			box(root, Vector3(0.7, 2.2, 0.7), Vector3(0, 1.1, -1.0), mat(Color(0.6, 0.57, 0.52)), Vector3(0, 0, 0.2))
			box(root, Vector3(1.0, 0.4, 0.6), Vector3(0.4, 0.2, 0.9), mat(Color(0.35, 0.33, 0.3)), Vector3(0.3, 0.2, 0.4))
		"hut":
			cyl(root, 0.4, 0.45, 0.6, Vector3(0, 0.3, 0), mat(Color(0.45, 0.38, 0.3)), Vector3.ZERO, 8)
			cyl(root, 0.0, 0.55, 0.5, Vector3(0, 0.85, 0), mat(Color(0.35, 0.3, 0.2)), Vector3.ZERO, 8)
			sphere(root, 0.1, Vector3(0.2, 0.9, 0.2), crystal)
		"sanctum":
			_slab(root, Vector2(6, 5), dark)
			box(root, Vector3(5.0, 2.0, 4.0), Vector3(0, 1.0, 0), body)
			box(root, Vector3(3.0, 1.4, 2.4), Vector3(0, 2.6, 0), body)
			cyl(root, 0.0, 1.2, 2.4, Vector3(0, 4.4, 0), trim, Vector3.ZERO, 6)
			sphere(root, 0.6, Vector3(0, 2.6, 1.25), mat(Color(0.9, 0.95, 1.0), 2.0, 0.05, 1.0))
			box(root, Vector3(1.4, 1.6, 0.1), Vector3(0, 0.8, 2.02), mat(Color(0.05, 0.03, 0.03)))

		# ------------------------------------------------ the Pilgrim (train cars)
		"train_engine", "train_flak", "train_artillery", "train_troop", "train_repair", "train_command":
			box(root, Vector3(0.9, 0.2, 2.2), Vector3(0, 0.2, 0), dark)
			_wheels(root, [-0.42, 0.42], [-0.8, 0.8], 0.16, dark)
			match model:
				"train_engine":
					box(root, Vector3(0.85, 0.8, 2.0), Vector3(0, 0.7, 0), body)
					box(root, Vector3(0.87, 0.1, 2.02), Vector3(0, 1.05, 0), tc)
					cyl(root, 0.12, 0.15, 0.5, Vector3(0, 1.3, 0.6), dark)
					box(root, Vector3(0.6, 0.1, 0.05), Vector3(0, 0.9, 1.01), glow)
				"train_flak":
					box(root, Vector3(0.85, 0.4, 2.0), Vector3(0, 0.5, 0), body)
					var tf := pivot(root, Vector3(0, 0.85, 0))
					box(tf, Vector3(0.5, 0.25, 0.5), Vector3.ZERO, tc)
					for gx in [-0.12, 0.12]:
						cyl(tf, 0.03, 0.03, 0.6, Vector3(gx, 0.25, 0.2), dark, Vector3(PI / 2.0 - 0.9, 0, 0), 6)
					root.set_meta("turret", tf)
					root.set_meta("muzzle_height", 1.1)
				"train_artillery":
					box(root, Vector3(0.85, 0.4, 2.0), Vector3(0, 0.5, 0), body)
					var ta := pivot(root, Vector3(0, 0.85, 0))
					box(ta, Vector3(0.6, 0.3, 0.8), Vector3.ZERO, tc)
					cyl(ta, 0.08, 0.09, 1.6, Vector3(0, 0.4, 0.7), dark, Vector3(PI / 2.0 - 0.5, 0, 0), 8)
					root.set_meta("turret", ta)
					root.set_meta("muzzle_height", 1.3)
				"train_troop":
					box(root, Vector3(0.85, 0.7, 2.0), Vector3(0, 0.65, 0), body)
					for z in [-0.6, 0.0, 0.6]:
						box(root, Vector3(0.87, 0.12, 0.25), Vector3(0, 0.75, z), mat(Color(0.1, 0.1, 0.1)))
				"train_repair":
					box(root, Vector3(0.85, 0.6, 2.0), Vector3(0, 0.6, 0), body)
					box(root, Vector3(0.3, 0.3, 0.05), Vector3(0, 0.7, 1.01), mat(Color(0.3, 1.0, 0.4), 2.0))
					cyl(root, 0.05, 0.05, 0.8, Vector3(0.2, 1.2, -0.5), trim, Vector3(0, 0, 0.6))
				"train_command":
					box(root, Vector3(0.85, 0.9, 2.0), Vector3(0, 0.75, 0), body)
					box(root, Vector3(0.87, 0.1, 2.02), Vector3(0, 1.2, 0), tc)
					cyl(root, 0.02, 0.02, 0.9, Vector3(0.25, 1.65, -0.5), dark)
					sphere(root, 0.12, Vector3(0, 1.3, 0.4), mat(Color(0.3, 1.0, 0.5), 2.5))
			if not root.has_meta("muzzle_height"):
				root.set_meta("muzzle_height", 1.0)
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


## Objective marker: a tall translucent light pillar.
static func marker_pillar(color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.45
	cm.height = 8.0
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.position.y = 4.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	ring.mesh = tm
	ring.position.y = 0.06
	ring.scale = Vector3(1, 0.2, 1)
	var rm := m.duplicate() as StandardMaterial3D
	rm.albedo_color = Color(color.r, color.g, color.b, 0.7)
	ring.material_override = rm
	root.add_child(ring)
	return root
