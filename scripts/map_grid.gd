class_name MapGrid
extends Node3D
## The battlefield: a cell grid with terrain, crystal fields, pathfinding and
## the visuals for ground, rocks, forest, city blocks, water and crystals.
## One cell == one world unit. Cell (x, y) covers world X in [x, x+1), Z in [y, y+1).
## Missions build the map with the painter API (fill_rect, blob, line, crystal_field ...)
## and then call finalize().

enum Terrain { GROUND = 0, ROCK = 1, WATER = 3, FOREST = 4, BUILDING = 5, BRIDGE = 6 }
enum Crystal { NONE = 0, GREEN = 1, BLUE = 2 }

var w := 80
var h := 80
var terrain := PackedByteArray()
var crystal := PackedFloat32Array()
var crystal_kind := PackedByteArray()
var occupant: Array = []            # Structure or null per cell
var crystal_cells := {}             # Vector2i -> true
var blossoms: Array = []            # Array of Vector2i (crystal seeders)
var tints := {}                     # Vector2i -> Color (roads, rails, snow ...)

var palette := {
	"ground": Color(0.34, 0.30, 0.25), "rock": Color(0.26, 0.23, 0.21),
	"water": Color(0.1, 0.22, 0.28), "forest": Color(0.13, 0.2, 0.11),
	"building": Color(0.3, 0.3, 0.32), "variation": 0.05,
	"tree": Color(0.14, 0.26, 0.12), "block": Color(0.36, 0.35, 0.37),
}
var growth_enabled := true
var spread_enabled := true
var redraw_interval := 0.5

var astar := AStarGrid2D.new()        # ground units
var astar_hover := AStarGrid2D.new()  # hover / amphibious units
var rng := RandomNumberGenerator.new()

var ground_img: Image
var ground_tex: ImageTexture
var _noise := FastNoiseLite.new()
var _mm_green: MultiMeshInstance3D
var _mm_blue: MultiMeshInstance3D
var _mm_water: MultiMeshInstance3D
var _crystal_dirty := true
var _water_dirty := false
var _terrain_dirty := false
var _redraw_t := 0.0
var _grow_t := 0.0
var _spread_t := 0.0
var _blossom_t := 0.0
var _cr: Dictionary = {}
var _finalized := false
var _static_nodes: Array = []


# ================================================================ helpers

func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func terrain_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return Terrain.ROCK
	return terrain[idx(c)]


## Ground-unit walkability (also used for building placement).
func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := idx(c)
	var t := terrain[i]
	return (t == Terrain.GROUND or t == Terrain.BRIDGE) and occupant[i] == null


## Walkability for a movement class: ground | hover | air | jump.
func passable(c: Vector2i, mc := "ground") -> bool:
	if not in_bounds(c):
		return false
	if mc == "air" or mc == "jump":
		return true
	var i := idx(c)
	if occupant[i] != null:
		return false
	var t := terrain[i]
	if t == Terrain.GROUND or t == Terrain.BRIDGE:
		return true
	return mc == "hover" and t == Terrain.WATER


func is_water(c: Vector2i) -> bool:
	return terrain_at(c) == Terrain.WATER


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func crystal_at(c: Vector2i) -> float:
	if not in_bounds(c):
		return 0.0
	return crystal[idx(c)]


func crystal_kind_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return Crystal.NONE
	return crystal_kind[idx(c)]


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
	if not _finalized:
		return
	astar.set_point_solid(c, not passable(c, "ground"))
	astar_hover.set_point_solid(c, not passable(c, "hover"))


# ================================================================ painter API

func init_blank(p_w: int, p_h: int, seed_value: int, p_palette: Dictionary = {}) -> void:
	_cr = G.rules.get("crystal", {})
	w = p_w
	h = p_h
	for k in p_palette.keys():
		palette[k] = p_palette[k]
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
	tints.clear()
	# rock rim around the edge
	for x in w:
		for y in h:
			var edge_d := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if edge_d == 0:
				terrain[idx(Vector2i(x, y))] = Terrain.ROCK


func set_terrain(c: Vector2i, t: int) -> void:
	if not in_bounds(c):
		return
	var i := idx(c)
	if terrain[i] == t:
		return
	var was_water := terrain[i] == Terrain.WATER
	terrain[i] = t
	if t != Terrain.GROUND and t != Terrain.BRIDGE and crystal[i] > 0.0:
		_remove_crystal(c)
	if was_water or t == Terrain.WATER:
		_water_dirty = true
	_terrain_dirty = true
	_refresh_solid(c)


func fill_rect(r: Rect2i, t: int) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			set_terrain(Vector2i(x, y), t)


func blob(center: Vector2i, r: float, t: int, rough := 1.2) -> void:
	var ri := ceili(r + rough) + 1
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var d := Vector2(x - center.x, y - center.y).length()
			if d <= r + _noise.get_noise_2d(x * 3.0, y * 3.0) * rough:
				set_terrain(Vector2i(x, y), t)


## Thick line of terrain between points (rivers, ridges, walls).
func line(a: Vector2i, b: Vector2i, width: float, t: int, rough := 0.0) -> void:
	var steps := int(Vector2(a).distance_to(Vector2(b)) * 2.0) + 1
	for i in steps + 1:
		var q := Vector2(a).lerp(Vector2(b), float(i) / steps)
		var wr := width * 0.5 + _noise.get_noise_2d(q.x * 2.0, q.y * 2.0) * rough
		var ri := ceili(wr) + 1
		for x in range(int(q.x) - ri, int(q.x) + ri + 1):
			for y in range(int(q.y) - ri, int(q.y) + ri + 1):
				if Vector2(x + 0.5, y + 0.5).distance_to(q + Vector2(0.5, 0.5)) <= wr:
					set_terrain(Vector2i(x, y), t)


func polyline(pts: Array, width: float, t: int, rough := 0.0) -> void:
	for i in range(pts.size() - 1):
		line(pts[i], pts[i + 1], width, t, rough)


## Colour tint for decorative ground (roads, rails, snow, sand).
func tint_line(a: Vector2i, b: Vector2i, width: float, col: Color) -> void:
	var steps := int(Vector2(a).distance_to(Vector2(b)) * 2.0) + 1
	for i in steps + 1:
		var q := Vector2(a).lerp(Vector2(b), float(i) / steps)
		var ri := ceili(width * 0.5) + 1
		for x in range(int(q.x) - ri, int(q.x) + ri + 1):
			for y in range(int(q.y) - ri, int(q.y) + ri + 1):
				if Vector2(x, y).distance_to(q) <= width * 0.5:
					var c := Vector2i(x, y)
					if in_bounds(c):
						tints[c] = col
	_terrain_dirty = true


func tint_polyline(pts: Array, width: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		tint_line(pts[i], pts[i + 1], width, col)


func tint_blob(center: Vector2i, r: float, col: Color) -> void:
	var ri := ceili(r) + 1
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var c := Vector2i(x, y)
			if in_bounds(c) and Vector2(x - center.x, y - center.y).length() <= r + _noise.get_noise_2d(x * 3.0, y * 3.0):
				tints[c] = col
	_terrain_dirty = true


func clear_area(center: Vector2i, r: float) -> void:
	var ri := ceili(r)
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or Vector2(x - center.x, y - center.y).length() > r:
				continue
			var edge_d := mini(mini(c.x, c.y), mini(w - 1 - c.x, h - 1 - c.y))
			if edge_d > 0 and terrain[idx(c)] != Terrain.GROUND:
				set_terrain(c, Terrain.GROUND)


## Scatter random rock outcrops, avoiding a list of [center, radius] keep-clear zones.
func scatter(t: int, count: int, rmin: float, rmax: float, keep_clear: Array = []) -> void:
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 20:
		tries += 1
		var c := Vector2i(rng.randi_range(3, w - 4), rng.randi_range(3, h - 4))
		var ok := true
		for k in keep_clear:
			if Vector2(c).distance_to(Vector2(k[0])) < float(k[1]) + rmax:
				ok = false
				break
		if not ok:
			continue
		blob(c, rng.randf_range(rmin, rmax), t)
		placed += 1


func crystal_field(center: Vector2i, r: float, kind: int, density_mult := 1.0) -> void:
	var mx := _max_for(kind)
	var ri := ceili(r) + 1
	for x in range(center.x - ri, center.x + ri + 1):
		for y in range(center.y - ri, center.y + ri + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or terrain[idx(c)] != Terrain.GROUND:
				continue
			var d := Vector2(x - center.x, y - center.y).length()
			if d > r + _noise.get_noise_2d(x * 2.0, y * 2.0) * 0.8:
				continue
			var density := clampf(1.0 - d / (r + 1.0), 0.3, 1.0) * density_mult
			add_crystal(c, kind, mx * clampf(density, 0.1, 1.0))


## Carves a guaranteed ground corridor between two cells (only through rock/forest).
func carve(a: Vector2i, b: Vector2i, width := 2.0) -> void:
	var steps := int(Vector2(a).distance_to(Vector2(b)) * 2.0) + 1
	for i in steps + 1:
		var q := Vector2(a).lerp(Vector2(b), float(i) / steps)
		var ri := ceili(width * 0.5)
		for x in range(int(q.x) - ri, int(q.x) + ri + 1):
			for y in range(int(q.y) - ri, int(q.y) + ri + 1):
				var c := Vector2i(x, y)
				if not in_bounds(c):
					continue
				var edge_d := mini(mini(c.x, c.y), mini(w - 1 - c.x, h - 1 - c.y))
				var t := terrain[idx(c)]
				if edge_d > 0 and (t == Terrain.ROCK or t == Terrain.FOREST or t == Terrain.BUILDING):
					set_terrain(c, Terrain.GROUND)


## Builds pathfinding and all visuals. Call once after painting.
func finalize() -> void:
	for a in [astar, astar_hover]:
		a.region = Rect2i(0, 0, w, h)
		a.cell_size = Vector2(1, 1)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
	_finalized = true
	for x in w:
		for y in h:
			_refresh_solid(Vector2i(x, y))
	_build_visuals()


# ================================================================ pathfinding

func nearest_walkable(c: Vector2i, max_r := 14) -> Vector2i:
	return nearest_passable(c, "ground", max_r)


func nearest_passable(c: Vector2i, mc := "ground", max_r := 14) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, h - 1))
	if passable(c, mc):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if absi(x - c.x) != r and absi(y - c.y) != r:
					continue
				var cc := Vector2i(x, y)
				if not passable(cc, mc):
					continue
				var d := Vector2(cc - c).length_squared()
				if d < best_d:
					best_d = d
					best = cc
		if best.x >= 0:
			return best
	return c


## Returns an Array of Vector3 waypoints (excluding the start position).
func find_path(from_pos: Vector3, to_cell: Vector2i, mc := "ground") -> Array:
	to_cell = Vector2i(clampi(to_cell.x, 1, w - 2), clampi(to_cell.y, 1, h - 2))
	if mc == "air" or mc == "jump":
		return [cell_to_world(to_cell)]
	var a := nearest_passable(world_to_cell(from_pos), mc)
	var b := nearest_passable(to_cell, mc)
	if a == b:
		return [cell_to_world(b)]
	var grid: AStarGrid2D = astar_hover if mc == "hover" else astar
	var ids := grid.get_id_path(a, b, true)
	if ids.is_empty():
		return []
	var pts: Array = []
	for i in range(1, ids.size()):
		pts.append(cell_to_world(ids[i]))
	return _smooth(from_pos, pts, mc)


func _smooth(start: Vector3, pts: Array, mc: String) -> Array:
	var out: Array = []
	var cur := start
	var i := 0
	var n := pts.size()
	while i < n:
		var j := mini(i + 10, n - 1)
		while j > i and not clear_line(cur, pts[j], mc):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out


func clear_line(p0: Vector3, p1: Vector3, mc := "ground") -> bool:
	var dist := p0.distance_to(p1)
	var steps := int(dist * 3.0) + 1
	for k in steps + 1:
		var p := p0.lerp(p1, float(k) / steps)
		for off in [Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, -0.3)]:
			if not passable(world_to_cell(p + off), mc):
				return false
	return true


func has_route(a: Vector2i, b: Vector2i, mc := "ground") -> bool:
	a = nearest_passable(a, mc)
	b = nearest_passable(b, mc)
	var grid: AStarGrid2D = astar_hover if mc == "hover" else astar
	return not grid.get_id_path(a, b).is_empty()


## Walkable cells spiralling out from centre, for spreading a group move.
func spread_cells(center: Vector2i, count: int, mc := "ground") -> Array:
	var out: Array = []
	center = nearest_passable(center, mc)
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
				if passable(c, mc):
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

func add_crystal(c: Vector2i, kind: int, amount: float) -> void:
	if not in_bounds(c):
		return
	var i := idx(c)
	crystal_kind[i] = kind
	crystal[i] = minf(amount, _max_for(kind))
	crystal_cells[c] = true
	_crystal_dirty = true


func remove_crystal(c: Vector2i) -> void:
	if in_bounds(c) and crystal[idx(c)] > 0.0:
		_remove_crystal(c)


func _remove_crystal(c: Vector2i) -> void:
	var i := idx(c)
	crystal[i] = 0.0
	crystal_kind[i] = Crystal.NONE
	crystal_cells.erase(c)
	_crystal_dirty = true


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


func harvestable(c: Vector2i) -> bool:
	if crystal_at(c) <= 0.0:
		return false
	return G.blue_allowed or crystal_kind[idx(c)] != Crystal.BLUE


func nearest_crystal(from: Vector2i, prefer_near: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for c in crystal_cells.keys():
		var cv: Vector2i = c
		if not harvestable(cv):
			continue
		if G.mission and not G.mission.harvest_cell_ok(cv):
			continue
		var d: float = Vector2(cv - from).length_squared()
		if prefer_near.x >= 0:
			d = minf(d, Vector2(cv - prefer_near).length_squared() * 0.5)
		if crystal_kind[idx(cv)] == Crystal.BLUE:
			d *= 0.8
		if d < best_d:
			best_d = d
			best = cv
	return best


func crystal_near(c: Vector2i, r: int) -> Vector2i:
	for rr in range(0, r + 1):
		for x in range(c.x - rr, c.x + rr + 1):
			for y in range(c.y - rr, c.y + rr + 1):
				var cc := Vector2i(x, y)
				if in_bounds(cc) and harvestable(cc):
					return cc
	return Vector2i(-1, -1)


func _process(delta: float) -> void:
	if not _finalized:
		return
	_grow_t += delta
	_spread_t += delta
	_blossom_t += delta
	if growth_enabled and _grow_t >= float(_cr.get("growth_interval", 6.0)):
		_grow_t = 0.0
		_grow()
	if spread_enabled and _spread_t >= float(_cr.get("spread_interval", 18.0)):
		_spread_t = 0.0
		_spread()
	if _blossom_t >= float(_cr.get("blossom_interval", 14.0)):
		_blossom_t = 0.0
		_blossom_seed()
	_redraw_t -= delta
	if (_crystal_dirty or _water_dirty or _terrain_dirty) and _redraw_t <= 0.0:
		_redraw_t = redraw_interval
		if _crystal_dirty:
			_rebuild_crystal_meshes()
		if _water_dirty:
			_rebuild_water()
		_crystal_dirty = false
		_water_dirty = false
		_terrain_dirty = false
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


func can_seed(c: Vector2i) -> bool:
	return is_walkable(c) and crystal[idx(c)] <= 0.0 and not _unit_on(c) and (G.mission == null or G.mission.crystal_allowed(c))


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
			if in_bounds(n) and can_seed(n):
				add_crystal(n, crystal_kind[idx(c)], float(_cr.get("spread_seed_amount", 40)))
				seeded += 1
				break


func _blossom_seed() -> void:
	var r := int(_cr.get("blossom_radius", 4))
	for b in blossoms:
		for attempt in 6:
			var c: Vector2i = b + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r))
			if in_bounds(c) and can_seed(c):
				add_crystal(c, Crystal.GREEN, float(_cr.get("spread_seed_amount", 40)))
				break


# ================================================================ visuals

func _build_visuals() -> void:
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

	var skirt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 4, h * 4)
	skirt.mesh = pm
	skirt.position = Vector3(w * 0.5, -0.05, h * 0.5)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = (palette["rock"] as Color).darkened(0.5)
	sm.roughness = 1.0
	skirt.material_override = sm
	add_child(skirt)

	rebuild_static()

	var wq := QuadMesh.new()
	wq.size = Vector2(1.0, 1.0)
	wq.orientation = PlaneMesh.FACE_Y
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(palette["water"].r, palette["water"].g, palette["water"].b, 0.78)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.metallic = 0.4
	wmat.roughness = 0.08
	wmat.emission_enabled = true
	wmat.emission = (palette["water"] as Color).lightened(0.2)
	wmat.emission_energy_multiplier = 0.25
	var wmm := MultiMesh.new()
	wmm.transform_format = MultiMesh.TRANSFORM_3D
	wmm.mesh = wq
	_mm_water = MultiMeshInstance3D.new()
	_mm_water.multimesh = wmm
	_mm_water.material_override = wmat
	_mm_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_water)
	_rebuild_water()

	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.11
	shard.height = 0.6
	shard.radial_segments = 5
	shard.rings = 1
	_mm_green = _make_crystal_mmi(shard, Color(0.25, 1.0, 0.35), Color(0.1, 0.5, 0.15))
	_mm_blue = _make_crystal_mmi(shard, Color(0.3, 0.6, 1.0), Color(0.1, 0.25, 0.6))
	_rebuild_crystal_meshes()


## Rebuilds rocks / forest / city block meshes (call after large terrain edits).
func rebuild_static() -> void:
	for n in _static_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_static_nodes.clear()
	_build_rocks()
	_build_forest()
	_build_blocks()


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
	if _mm_green == null:
		return
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


func _rebuild_water() -> void:
	if _mm_water == null:
		return
	var xs: Array = []
	for x in w:
		for y in h:
			if terrain[y * w + x] == Terrain.WATER:
				xs.append(Transform3D(Basis(), Vector3(x + 0.5, 0.06, y + 0.5)))
	_fill_mm(_mm_water.multimesh, xs)


func _fill_mm(mm: MultiMesh, xforms: Array) -> void:
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])


func _paint_ground() -> void:
	if ground_img == null:
		return
	var var_k: float = palette["variation"]
	var base: Color = palette["ground"]
	for x in w:
		for y in h:
			var i := y * w + x
			var n := _noise.get_noise_2d(x * 1.7, y * 1.7) * var_k
			var col := Color(base.r + n, base.g + n, base.b + n)
			var c := Vector2i(x, y)
			if tints.has(c):
				var tc: Color = tints[c]
				col = Color(tc.r + n * 0.5, tc.g + n * 0.5, tc.b + n * 0.5)
			match terrain[i]:
				Terrain.ROCK:
					var rc: Color = palette["rock"]
					col = Color(rc.r + n, rc.g + n, rc.b + n)
				Terrain.WATER:
					col = (palette["water"] as Color).darkened(0.2 + n)
				Terrain.FOREST:
					col = palette["forest"]
				Terrain.BUILDING:
					col = palette["building"]
				Terrain.BRIDGE:
					col = Color(0.3, 0.27, 0.24)
			if crystal[i] > 0.0:
				var k := clampf(crystal[i] / _max_for(crystal_kind[i]), 0.2, 1.0)
				var tint := Color(0.16, 0.32, 0.12) if crystal_kind[i] == Crystal.GREEN else Color(0.12, 0.2, 0.38)
				col = col.lerp(tint, 0.5 + k * 0.4)
			ground_img.set_pixel(x, y, col)
	if ground_tex:
		ground_tex.update(ground_img)


func _cells_of(t: int) -> Array:
	var cells: Array = []
	for x in w:
		for y in h:
			if terrain[y * w + x] == t:
				cells.append(Vector2i(x, y))
	return cells


func _add_mm(mesh: Mesh, xforms: Array, col: Color, rough := 1.0, emissive := 0.0) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	_fill_mm(mm, xforms)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emissive
	mmi.material_override = mat
	add_child(mmi)
	_static_nodes.append(mmi)


func _build_rocks() -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.5
	rock_mesh.height = 1.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var xs: Array = []
	for c in _cells_of(Terrain.ROCK):
		var hk := hash(c)
		var sx := 1.1 + float(hk % 5) * 0.08
		var sy := 0.7 + float((hk / 5) % 9) * 0.12
		var b := Basis(Vector3.UP, float(hk % 628) / 100.0).scaled(Vector3(sx, sy, sx))
		xs.append(Transform3D(b, Vector3(c.x + 0.5, sy * 0.25, c.y + 0.5)))
	_add_mm(rock_mesh, xs, palette["rock"])


func _build_forest() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.6
	cone.radial_segments = 6
	cone.rings = 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.07
	trunk.bottom_radius = 0.1
	trunk.height = 0.6
	trunk.radial_segments = 5
	trunk.rings = 1
	var tops: Array = []
	var trunks: Array = []
	for c in _cells_of(Terrain.FOREST):
		var hk := hash(c)
		var s := 0.8 + float(hk % 7) * 0.08
		var ox := float(hk % 100) / 100.0 * 0.3 - 0.15
		var oz := float((hk / 100) % 100) / 100.0 * 0.3 - 0.15
		tops.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(c.x + 0.5 + ox, 0.55 + 0.8 * s, c.y + 0.5 + oz)))
		trunks.append(Transform3D(Basis(), Vector3(c.x + 0.5 + ox, 0.3, c.y + 0.5 + oz)))
	_add_mm(cone, tops, palette["tree"])
	_add_mm(trunk, trunks, Color(0.22, 0.17, 0.12))


func _build_blocks() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var xs: Array = []
	for c in _cells_of(Terrain.BUILDING):
		var hk := hash(Vector2i(c.x / 2, c.y / 2))
		var hgt := 0.8 + float(hk % 9) * 0.35
		xs.append(Transform3D(Basis().scaled(Vector3(0.98, hgt, 0.98)), Vector3(c.x + 0.5, hgt * 0.5, c.y + 0.5)))
	_add_mm(bm, xs, palette["block"], 0.85)
