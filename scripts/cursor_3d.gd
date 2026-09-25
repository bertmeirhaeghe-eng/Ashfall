class_name Cursor3D
extends CanvasLayer
## Replaces the flat OS mouse pointer with a small, lit 3D scene rendered
## into a SubViewport and stamped over the mouse position: an actual model
## instead of a bitmap. Icons follow the classic TD-style cursor set (white
## pointer / green move diamonds / red attack reticle / gold $ sell coin),
## plus a cyan + coin for repair, matched from InputController.cursor_kind().
## Only lives in the gameplay scene (added by main.gd); menus keep the OS
## pointer.

const SIZE := 48
const HALF := SIZE * 0.5

var _tex_rect: TextureRect
var _vp: SubViewport
var _icons := {}   # kind -> Node3D root, one per built icon
var _mats := {}    # kind -> StandardMaterial3D, for icons whose colour is retinted at runtime
var _spin := 0.0
var _shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	_tex_rect = TextureRect.new()
	_tex_rect.size = Vector2(SIZE, SIZE)
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_tex_rect)

	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_tex_rect.texture = _vp.get_texture()

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.3, 1.7)
	cam.fov = 30.0
	_vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 1.2
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.55, 0.7, 1.0)
	_vp.add_child(fill)

	var rig := Node3D.new()
	_vp.add_child(rig)
	_icons["arrow"] = _build_arrow()
	_icons["move"] = _build_move()
	_icons["attack"] = _build_attack()
	_icons["sell"] = _build_coin("sell", Color(1.0, 0.82, 0.25), "$")
	_icons["repair"] = _build_coin("repair", Color(0.35, 0.9, 0.95), "+")
	for k in _icons.keys():
		rig.add_child(_icons[k])
		_icons[k].visible = false


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if G.controller == null or G.camera == null or not is_instance_valid(G.controller):
		if _shown:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_tex_rect.visible = false
			_shown = false
		return
	if not _shown:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_tex_rect.visible = true
		_shown = true

	var mp := get_viewport().get_mouse_position()
	_tex_rect.position = mp - Vector2(HALF, HALF)

	var kind := "arrow"
	if not G.game_over and get_viewport().gui_get_hovered_control() == null:
		kind = G.controller.cursor_kind(mp)
	if kind == "place":
		kind = "move"
		_tint("move", Color(0.3, 1.0, 0.35) if G.controller.place_ok() else Color(1.0, 0.25, 0.2))
	elif kind == "target":
		kind = "attack"
		_tint("attack", Color(0.62, 0.42, 1.0))
	elif kind == "attack":
		_tint("attack", Color(1.0, 0.25, 0.2))
	elif kind == "move":
		_tint("move", Color(0.35, 1.0, 0.4))
	if not _icons.has(kind):
		kind = "arrow"

	_spin += delta
	for k in _icons.keys():
		var icon: Node3D = _icons[k]
		var active: bool = k == kind
		icon.visible = active
		if active and k != "arrow":
			icon.rotation.y += delta * 1.6
			icon.position.y = sin(_spin * 3.0) * 0.03


func _tint(key: String, color: Color) -> void:
	var mat: StandardMaterial3D = _mats.get(key)
	if mat == null:
		return
	mat.albedo_color = color.darkened(0.35)
	mat.emission = color


# ================================================================ icon meshes

func _build_arrow() -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.78)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.95, 1.0)
	mat.emission_energy_multiplier = 0.8
	mat.metallic = 0.1
	mat.roughness = 0.35

	# lying flat on the ground plane (XZ); apex sits at the hotspot (local
	# origin, under the mouse) and points along +Z, tail trailing behind it
	var rig := Node3D.new()
	var tip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.17
	cm.height = 0.5
	tip.mesh = cm
	tip.material_override = mat
	tip.rotation_degrees.x = 90.0
	tip.position = Vector3(0, 0, -0.25)
	rig.add_child(tip)

	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.1, 0.55)
	shaft.mesh = bm
	shaft.material_override = mat
	shaft.position = Vector3(0, 0, -0.775)
	rig.add_child(shaft)

	return rig


func _build_move() -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.55, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 1.0, 0.4)
	mat.emission_energy_multiplier = 1.8
	_mats["move"] = mat

	# four diamonds lying flat around the centre, in the XZ ground plane
	var rig := Node3D.new()
	for i in 4:
		var ang := deg_to_rad(90.0 * i)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.08, 0.22)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(sin(ang), 0, cos(ang)) * 0.5
		mi.rotation_degrees.y = 45.0
		rig.add_child(mi)
	return rig


func _build_attack() -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.08, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.2)
	mat.emission_energy_multiplier = 1.9
	_mats["attack"] = mat

	# ring + ticks lying flat in the XZ ground plane (a torus is already flat)
	var rig := Node3D.new()
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.42
	tm.rings = 6
	tm.ring_segments = 16
	ring.mesh = tm
	ring.material_override = mat
	rig.add_child(ring)
	for i in 4:
		var ang := deg_to_rad(90.0 * i + 45.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 0.22)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(sin(ang), 0, cos(ang)) * 0.5
		mi.rotation_degrees.y = rad_to_deg(ang)
		rig.add_child(mi)
	var dot := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(0.1, 0.06, 0.1)
	dot.mesh = db
	dot.material_override = mat
	dot.rotation_degrees.y = 45.0
	rig.add_child(dot)
	return rig


func _build_coin(key: String, color: Color, glyph: String) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.metallic = 0.6
	mat.roughness = 0.3
	_mats[key] = mat

	# coin lying flat on the ground (a cylinder's caps already face up/down)
	var rig := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.12
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = mat
	rig.add_child(mi)

	var label := Label3D.new()
	label.text = glyph
	label.font_size = 72
	label.pixel_size = 0.006
	label.modulate = color.lightened(0.5)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 0.09, 0)
	rig.add_child(label)
	return rig
