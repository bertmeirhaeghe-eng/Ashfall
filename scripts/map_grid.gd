class_name MapGrid
extends Node3D
## The battlefield: a cell grid with terrain, crystal fields, pathfinding and
## the visuals for ground, rocks, blossom trees and crystals.
## One cell == one world unit. Cell (x, y) covers world X in [x, x+1), Z in [y, y+1).

enum Terrain { GROUND = 0, ROCK = 1, TREE = 2 }
enum Crystal { NONE = 0, GREEN = 1, BLUE = 2 }

var w := 80
var h := 80
var terrain := PackedByteArray()
var crystal := PackedFloat32Array()
var crystal_kind := PackedByteArray()
var occupant: Array = []            # Structure or null per cell
var crystal_cells := {}             # Vector2i -> true
var blossoms: Array = []            # Array of Vector2i
var base_cells: Array = []          # Array of Vector2i, index == team

var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()

var ground_img: Image
var ground_tex: ImageTexture
var _noise := FastNoiseLite.new()
var _mm_green: MultiMeshInstance3D
var _mm_blue: MultiMeshInstance3D
var _crystal_dirty := true
var _redraw_t := 0.0
var _grow_t := 0.0
var _spread_t := 0.0
var _blossom_t := 0.0
var _cr: Dictionary = {}


# ================================================================ helpers

func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := idx(c)
	return terrain[i] == Terrain.GROUND and occupant[i] == null


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func mirror(c: Vector2i) -> Vector2i:
	return Vector2i(w - 1 - c.x, h - 1 - c.y)


func crystal_at(c: Vector2i) -> float:
	if not in_bounds(c):
		return 0.0
	return crystal[idx(c)]


func occupant_at(c: Vector2i) -> Variant:
	if not in_bounds(c):
		return null
	return occupant[idx(c)]


func set_occupant(c: Vector2i, s: Variant) -> void:
	if not in_bounds(c):
		return
	occupant[idx(c)] = s
	_refresh_solid(c)


func _refresh_solid(c: Vector2i) -> void:
	astar.set_point_solid(c, not is_walkable(c))


# ================================================================ generation

func generate(seed_value: int) -> void:
	_cr = G.rules.get("crystal", {})
	rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.08
	var n := w * h
	terrain.resize(n)
	terrain.fill(Terrain.GROUND)
	crystal.resize(n)
	crystal.fill(0.0)
	crystal_kind.resize(n)
	crystal_kind.fill(Crystal.NONE)
	occupant.resize(n)
	occupant.fill(null)
	crystal_cells.clear()
	blossoms.clear()

	base_cells = [Vector2i(14, h - 15), mirror(Vector2i(14, h - 15))]

	# --- rock outcrops and ridges (every feature is mirrored for fairness)
	for i in 10:
		var c := Vector2i(rng.randi_range(6, w - 7), rng.randi_range(6, h - 7))
		_rock_blob(c, rng.randf_range(1.5, 3.4))
	for i in 4:
		_rock_ridge(Vector2i(rng.randi_range(10, w - 11), rng.randi_range(10, h - 11)), rng.randi_range(8, 15))
	# map edge rim
	for x in w:
		for y in h:
			var edge_d := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if edge_d == 0 or (edge_d == 1 and _noise.get_noise_2d(x, y) > 0.1):
				_set_rock_sym(Vector2i(x, y))

	# --- keep bases clear
	for b in base_cells:
		_clear_rocks(b, 10.0)

	# --- crystal fields: [center, radius, kind, blossom]
	var fields := [
		[Vector2i(24, h - 25), 3.6, Crystal.GREEN, false],   # home field
		[Vector2i(14, 30), 3.0, Crystal.GREEN, true],        # flank field with blossom tree
		[Vector2i(40, h - 13), 3.0, Crystal.GREEN, false],   # forward field
	]
	for f in fields:
		_crystal_field(f[0], f[1], f[2], f[3])
		_crystal_field(mirror(f[0]), f[1], f[2], f[3])
	# contested blue field in the dead centre (symmetric by construction)
	_crystal_field(Vector2i(w / 2, h / 2), 2.6, Crystal.BLUE, false)

	# --- pathfinding
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for x in w:
		for y in h:
			_refresh_solid(Vector2i(x, y))

	# --- guarantee connectivity between bases and to every field
	_ensure_route(base_cells[0], base_cells[1])
	for f in fields:
		_ensure_route(base_cells[0], f[0])
		_ensure_route(base_cells[1], mirror(f[0]))
	_ensure_route(base_cells[0], Vector2i(w / 2, h / 2))
	_ensure_route(base_cells[1], Vector2i(w / 2, h / 2))

	_build_visuals()


func _set_rock_sym(c: Vector2i) -> void:
	for cc in [c, mirror(c)]:
		if in_bounds(cc):
			terrain[idx(cc)] = Terrain.ROCK


func _rock_blob(center: Vector2i, r: float) -> void:
	var ri := ceili(r) + 1
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var d := Vector2(x - center.x, y - center.y).length()
			if d <= r + _noise.get_noise_2d(x * 3.0, y * 3.0) * 1.2:
				_set_rock_sym(Vector2i(x, y))


func _rock_ridge(start: Vector2i, length: int) -> void:
	var p := Vector2(start)
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	for i in length:
		_set_rock_sym(Vector2i(p))
		_set_rock_sym(Vector2i(p + dir.orthogonal()))
		dir = dir.rotated(rng.randf_range(-0.5, 0.5))
		p += dir


func _clear_rocks(center: Vector2i, r: float) -> void:
	var ri := ceili(r)
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or Vector2(x - center.x, y - center.y).length() > r:
				continue
			for cc in [c, mirror(c)]:
				var edge_d := mini(mini(cc.x, cc.y), mini(w - 1 - cc.x, h - 1 - cc.y))
				if edge_d > 0 and terrain[idx(cc)] == Terrain.ROCK:
					terrain[idx(cc)] = Terrain.GROUND


func _crystal_field(center: Vector2i, r: float, kind: int, blossom: bool) -> void:
	_clear_rocks(center, r + 2.0)
	var mx := float(_cr.get("green_max", 300)) if kind == Crystal.GREEN else float(_cr.get("blue_max", 600))
	var ri := ceili(r)
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or terrain[idx(c)] != Terrain.GROUND:
				continue
			var d := Vector2(x - center.x, y - center.y).length()
			if d > r + _noise.get_noise_2d(x * 2.0, y * 2.0) * 0.8:
				continue
			var density := clampf(1.0 - d / (r + 1.0), 0.3, 1.0)
			_add_crystal(c, kind, mx * density)
	if blossom:
		var i := idx(center)
		_remove_crystal(center)
		terrain[i] = Terrain.TREE
		blossoms.append(center)


func _add_crystal(c: Vector2i, kind: int, amount: float) -> void:
	var i := idx(c)
	crystal_kind[i] = kind
	crystal[i] = amount
	crystal_cells[c] = true
	_crystal_dirty = true


func _remove_crystal(c: Vector2i) -> void:
	var i := idx(c)
	crystal[i] = 0.0
	crystal_kind[i] = Crystal.NONE
	crystal_cells.erase(c)
	_crystal_dirty = true


func _ensure_route(a: Vector2i, b: Vector2i) -> void:
	a = nearest_walkable(a)
	b = nearest_walkable(b)
	var p := astar.get_id_path(a, b)
	if not p.is_empty():
		return
	# carve a 2-wide corridor along the straight line
	var steps := int(Vector2(a).distance_to(Vector2(b))) * 2
	for i in steps + 1:
		var q := Vector2(a).lerp(Vector2(b), float(i) / maxf(steps, 1))
		for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var c: Vector2i = Vector2i(q) + off
			for cc in [c, mirror(c)]:
				if in_bounds(cc) and terrain[idx(cc)] == Terrain.ROCK:
					terrain[idx(cc)] = Terrain.GROUND
					_refresh_solid(cc)


# ================================================================ pathfinding

func nearest_walkable(c: Vector2i, max_r := 14) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, h - 1))
	if is_walkable(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if absi(x - c.x) != r and absi(y - c.y) != r:
					continue
				var cc := Vector2i(x, y)
				if not is_walkable(cc):
					continue
				var d := Vector2(cc - c).length_squared()
				if d < best_d:
					best_d = d
					best = cc
		if best.x >= 0:
			return best
	return c


## Returns an Array of Vector3 waypoints (excluding the start position).
func find_path(from_pos: Vector3, to_cell: Vector2i) -> Array:
	var a := nearest_walkable(world_to_cell(from_pos))
	var b := nearest_walkable(to_cell)
	if a == b:
		return [cell_to_world(b)]
	var ids := astar.get_id_path(a, b, true)
	if ids.is_empty():
		return []
	var pts: Array = []
	for i in range(1, ids.size()):
		pts.append(cell_to_world(ids[i]))
	return _smooth(from_pos, pts)


func _smooth(start: Vector3, pts: Array) -> Array:
	var out: Array = []
	var cur := start
	var i := 0
	var n := pts.size()
	while i < n:
		var j := mini(i + 10, n - 1)
		while j > i and not clear_line(cur, pts[j]):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out


func clear_line(p0: Vector3, p1: Vector3) -> bool:
	var dist := p0.distance_to(p1)
	var steps := int(dist * 3.0) + 1
	for k in steps + 1:
		var p := p0.lerp(p1, float(k) / steps)
		for off in [Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, -0.3)]:
			if not is_walkable(world_to_cell(p + off)):
				return false
	return true


## Walkable cells spiralling out from centre, for spreading a group move.
func spread_cells(center: Vector2i, count: int) -> Array:
	var out: Array = []
	center = nearest_walkable(center)
	if count <= 0:
		return out
	out.append(center)
	var r := 1
	while out.size() < count and r < 12:
		var ring: Array = []
		for x in range(center.x - r, center.x + r + 1):
			for y in range(center.y - r, center.y + r + 1):
				if absi(x - center.x) != r and absi(y - center.y) != r:
					continue
				var c := Vector2i(x, y)
				if is_walkable(c):
					ring.append(c)
		ring.sort_custom(func(p, q): return Vector2(p - center).length_squared() < Vector2(q - center).length_squared())
		for c in ring:
			if out.size() >= count:
				break
			out.append(c)
		r += 1
	while out.size() < count:
		out.append(center)
	return out


# ================================================================ crystal economy

func harvest(c: Vector2i, amount: float) -> float:
	if not in_bounds(c):
		return 0.0
	var i := idx(c)
	var have: float = crystal[i]
	if have <= 0.0:
		return 0.0
	var take := minf(have, amount)
	crystal[i] = have - take
	if crystal[i] <= 0.5:
		_remove_crystal(c)
	_crystal_dirty = true
	return take


func nearest_crystal(from: Vector2i, prefer_near: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for c in crystal_cells.keys():
		var cv: Vector2i = c
		var d: float = Vector2(cv - from).length_squared()
		if prefer_near.x >= 0:
			d = minf(d, Vector2(cv - prefer_near).length_squared() * 0.5)
		# lightly prefer blue crystal
		if crystal_kind[idx(c)] == Crystal.BLUE:
			d *= 0.8
		if d < best_d:
			best_d = d
			best = c
	return best


func crystal_near(c: Vector2i, r: int) -> Vector2i:
	for rr in range(0, r + 1):
		for x in range(c.x - rr, c.x + rr + 1):
			for y in range(c.y - rr, c.y + rr + 1):
				var cc := Vector2i(x, y)
				if in_bounds(cc) and crystal[idx(cc)] > 0.0:
					return cc
	return Vector2i(-1, -1)


func _process(delta: float) -> void:
	_grow_t += delta
	_spread_t += delta
	_blossom_t += delta
	if _grow_t >= float(_cr.get("growth_interval", 6.0)):
		_grow_t = 0.0
		_grow()
	if _spread_t >= float(_cr.get("spread_interval", 18.0)):
		_spread_t = 0.0
		_spread()
	if _blossom_t >= float(_cr.get("blossom_interval", 14.0)):
		_blossom_t = 0.0
		_blossom_seed()
	_redraw_t -= delta
	if _crystal_dirty and _redraw_t <= 0.0:
		_redraw_t = 0.5
		_crystal_dirty = false
		_rebuild_crystal_meshes()
		_paint_ground()


func _max_for(kind: int) -> float:
	return float(_cr.get("blue_max", 600)) if kind == Crystal.BLUE else float(_cr.get("green_max", 300))


func _grow() -> void:
	var g := float(_cr.get("growth_amount", 12))
	for c in crystal_cells.keys():
		var i := idx(c)
		var mx := _max_for(crystal_kind[i])
		if crystal[i] < mx:
			crystal[i] = minf(mx, crystal[i] + g * (2.0 if crystal_kind[i] == Crystal.BLUE else 1.0))
			_crystal_dirty = true


func _can_seed(c: Vector2i) -> bool:
	return is_walkable(c) and crystal[idx(c)] <= 0.0 and not _unit_on(c)


func _unit_on(c: Vector2i) -> bool:
	for e in G.entities:
		if e is Unit and world_to_cell(e.position) == c:
			return true
	return false


func _spread() -> void:
	if crystal_cells.size() >= int(_cr.get("max_cells", 900)):
		return
	var full: Array = []
	for c in crystal_cells.keys():
		var i := idx(c)
		if crystal[i] >= _max_for(crystal_kind[i]) * 0.95:
			full.append(c)
	full.shuffle()
	var seeded := 0
	for c in full:
		if seeded >= int(_cr.get("spread_per_tick", 3)):
			break
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		dirs.shuffle()
		for d in dirs:
			var n: Vector2i = c + d
			if _can_seed(n):
				_add_crystal(n, crystal_kind[idx(c)], float(_cr.get("spread_seed_amount", 40)))
				seeded += 1
				break


func _blossom_seed() -> void:
	var r := int(_cr.get("blossom_radius", 4))
	for b in blossoms:
		for attempt in 6:
			var c: Vector2i = b + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r))
			if _can_seed(c):
				_add_crystal(c, Crystal.GREEN, float(_cr.get("spread_seed_amount", 40)))
				break


# ================================================================ visuals

func _build_visuals() -> void:
	# Ground: a single quad with an explicit UV mapping to the per-cell colour image.
	ground_img = Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	_paint_ground()
	ground_tex = ImageTexture.create_from_image(ground_img)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, h), Vector3(0, 0, h)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.add_vertex(corners[k])
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = st.commit()
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = ground_tex
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	gm.roughness = 0.95
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = gm
	add_child(ground)

	# Out-of-bounds skirt so the map edge doesn't float in the sky.
	var skirt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 4, h * 4)
	skirt.mesh = pm
	skirt.position = Vector3(w * 0.5, -0.05, h * 0.5)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.09, 0.08, 0.07)
	sm.roughness = 1.0
	skirt.material_override = sm
	add_child(skirt)

	_build_rocks()
	_build_trees()

	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.11
	shard.height = 0.6
	shard.radial_segments = 5
	shard.rings = 1
	_mm_green = _make_crystal_mmi(shard, Color(0.25, 1.0, 0.35), Color(0.1, 0.5, 0.15))
	_mm_blue = _make_crystal_mmi(shard, Color(0.3, 0.6, 1.0), Color(0.1, 0.25, 0.6))
	_rebuild_crystal_meshes()


func _make_crystal_mmi(mesh: Mesh, glow: Color, base: Color) -> MultiMeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.metallic = 0.3
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 1.6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _rebuild_crystal_meshes() -> void:
	var green: Array = []
	var blue: Array = []
	for c in crystal_cells.keys():
		var i := idx(c)
		var amount: float = crystal[i]
		var frac := clampf(amount / _max_for(crystal_kind[i]), 0.0, 1.0)
		var count := 1 + int(frac * 3.0)
		var h32 := hash(c)
		for k in count:
			var hk: int = hash(h32 + k * 7919)
			var ox := float(hk % 1000) / 1000.0 * 0.7 - 0.35
			var oz := float((hk / 1000) % 1000) / 1000.0 * 0.7 - 0.35
			var yaw := float((hk / 7) % 628) / 100.0
			var tilt := float((hk / 13) % 60) / 100.0 - 0.3
			var s := (0.45 + frac * 0.75) * (0.8 + float(hk % 7) * 0.06)
			var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
			bs = bs.scaled(Vector3(s, s * 1.2, s))
			var t := Transform3D(bs, Vector3(c.x + 0.5 + ox, 0.25 * s, c.y + 0.5 + oz))
			if crystal_kind[i] == Crystal.BLUE:
				blue.append(t)
			else:
				green.append(t)
	_fill_mm(_mm_green.multimesh, green)
	_fill_mm(_mm_blue.multimesh, blue)


func _fill_mm(mm: MultiMesh, xforms: Array) -> void:
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])


func _paint_ground() -> void:
	if ground_img == null:
		return
	for x in w:
		for y in h:
			var i := y * w + x
			var n := _noise.get_noise_2d(x * 1.7, y * 1.7) * 0.05
			var col := Color(0.34 + n, 0.30 + n, 0.25 + n)
			if terrain[i] == Terrain.ROCK:
				col = Color(0.2 + n, 0.18 + n, 0.16 + n)
			elif crystal[i] > 0.0:
				var k := clampf(crystal[i] / _max_for(crystal_kind[i]), 0.2, 1.0)
				var tint := Color(0.16, 0.32, 0.12) if crystal_kind[i] == Crystal.GREEN else Color(0.12, 0.2, 0.38)
				col = col.lerp(tint, 0.5 + k * 0.4)
			ground_img.set_pixel(x, y, col)
	if ground_tex:
		ground_tex.update(ground_img)


func _build_rocks() -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.5
	rock_mesh.height = 1.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var cells: Array = []
	for x in w:
		for y in h:
			if terrain[y * w + x] == Terrain.ROCK:
				cells.append(Vector2i(x, y))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock_mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		var hk := hash(c)
		var sx := 1.1 + float(hk % 5) * 0.08
		var sy := 0.7 + float((hk / 5) % 9) * 0.12
		var b := Basis(Vector3.UP, float(hk % 628) / 100.0).scaled(Vector3(sx, sy, sx))
		mm.set_instance_transform(i, Transform3D(b, Vector3(c.x + 0.5, sy * 0.25, c.y + 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.23, 0.21)
	mat.roughness = 1.0
	mmi.material_override = mat
	add_child(mmi)


func _build_trees() -> void:
	for b in blossoms:
		var root := Node3D.new()
		root.position = cell_to_world(b)
		add_child(root)
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.12
		tm.bottom_radius = 0.3
		tm.height = 1.6
		trunk.mesh = tm
		trunk.position.y = 0.8
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color(0.2, 0.25, 0.15)
		trunk.material_override = bark
		root.add_child(trunk)
		var pod_mat := StandardMaterial3D.new()
		pod_mat.albedo_color = Color(0.2, 0.6, 0.2)
		pod_mat.emission_enabled = true
		pod_mat.emission = Color(0.3, 1.0, 0.3)
		pod_mat.emission_energy_multiplier = 1.2
		for k in 5:
			var pod := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.5
			pod.mesh = sm
			var a: float = TAU * k / 5.0
			pod.position = Vector3(cos(a) * 0.35, 1.5 + 0.15 * (k % 2), sin(a) * 0.35)
			pod.material_override = pod_mat
			root.add_child(pod)
