class_name PropLibrary
extends RefCounted
## Loads and instances the hand-modeled decoration props (houses, church,
## cottage, trees) used to dress the battlefield. Source files come in at
## arbitrary import scales, so every model is uniformly rescaled to a target
## world-space height and re-centred on its own footprint before use.

const HOUSE := "res://assets/models/house/House.fbx"
const CHURCH := "res://assets/models/church/church.fbx"
const COTTAGE := "res://assets/models/cottage/Cottage.fbx"
const TREE := "res://assets/models/tree/Tree.fbx"
const MAPLE_STEM := "res://assets/models/mapletree/MapleTreeStem.obj"
const MAPLE_LEAVES := "res://assets/models/mapletree/MapleTreeLeaves.obj"
const MAPLE_BARK_TEX := "res://assets/models/mapletree/maple_bark.png"
const MAPLE_LEAF_TEX := "res://assets/models/mapletree/maple_leaf.png"

const RUINS := [HOUSE, CHURCH, COTTAGE]

static var _cache := {}


static func _load(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path]
	var res: Resource = null
	if ResourceLoader.exists(path):
		res = load(path)
	_cache[path] = res
	return res


static func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


static func _combined_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _all_mesh_instances(node):
		if mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


## Wraps `inner` in a pivot so it sits centred on X/Z and resting on y=0,
## scaled so its tallest axis equals `target_height`.
static func _normalize(inner: Node3D, target_height: float) -> Node3D:
	var aabb := _combined_aabb(inner)
	var wrapper := Node3D.new()
	wrapper.add_child(inner)
	if aabb.size.y > 0.001:
		var s := target_height / aabb.size.y
		inner.scale = Vector3(s, s, s)
		inner.position = Vector3(
			-(aabb.position.x + aabb.size.x * 0.5) * s,
			-aabb.position.y * s,
			-(aabb.position.z + aabb.size.z * 0.5) * s
		)
	return wrapper


static func _instance_scaled(path: String, target_height: float) -> Node3D:
	var res := _load(path)
	if res == null or not (res is PackedScene):
		return null
	var ps := res as PackedScene
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	return _normalize(inst, target_height)


## One of the three untextured ruin buildings (house/church/cottage),
## picked deterministically from `rng`.
static func ruin(rng: RandomNumberGenerator, target_height := 2.2) -> Node3D:
	var path: String = RUINS[rng.randi_range(0, RUINS.size() - 1)]
	return _instance_scaled(path, target_height)


## The plain hero tree (its own textures weren't shipped, so it gets a
## flat bark tint instead).
static func tree(target_height := 2.2) -> Node3D:
	var inst := _instance_scaled(TREE, target_height)
	if inst == null:
		return null
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.24, 0.16)
	bark.roughness = 0.9
	for mi in _all_mesh_instances(inst):
		mi.material_override = bark
	return inst


## The textured maple tree, assembled from separate stem/leaf meshes.
static func maple_tree(target_height := 2.2) -> Node3D:
	var stem_mesh := _load(MAPLE_STEM)
	var leaves_mesh := _load(MAPLE_LEAVES)
	if stem_mesh == null or leaves_mesh == null:
		return null
	var inner := Node3D.new()

	var stem := MeshInstance3D.new()
	stem.mesh = stem_mesh as Mesh
	var bark_mat := StandardMaterial3D.new()
	var bark_tex := _load(MAPLE_BARK_TEX)
	if bark_tex:
		bark_mat.albedo_texture = bark_tex as Texture2D
	else:
		bark_mat.albedo_color = Color(0.32, 0.22, 0.14)
	bark_mat.roughness = 0.9
	stem.material_override = bark_mat
	inner.add_child(stem)

	var leaves := MeshInstance3D.new()
	leaves.mesh = leaves_mesh as Mesh
	var leaf_mat := StandardMaterial3D.new()
	var leaf_tex := _load(MAPLE_LEAF_TEX)
	if leaf_tex:
		leaf_mat.albedo_texture = leaf_tex as Texture2D
	else:
		leaf_mat.albedo_color = Color(0.2, 0.45, 0.15)
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves.material_override = leaf_mat
	inner.add_child(leaves)

	return _normalize(inner, target_height)
