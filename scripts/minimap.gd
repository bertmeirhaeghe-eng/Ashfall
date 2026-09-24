class_name Minimap
extends Control
## North-up radar: terrain/crystal image, unit dots, structure blocks and the
## camera's ground footprint. Click or drag to move the camera.

var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _map_to_ui(p: Vector3) -> Vector2:
	return Vector2(p.x / G.map.w * size.x, p.z / G.map.h * size.y)


func _ui_to_map(p: Vector2) -> Vector3:
	return Vector3(p.x / size.x * G.map.w, 0.0, p.y / size.y * G.map.h)


func _draw() -> void:
	if G.map == null or G.map.ground_tex == null:
		return
	draw_texture_rect(G.map.ground_tex, Rect2(Vector2.ZERO, size), false)
	var cell_px := size / Vector2(G.map.w, G.map.h)
	for e in G.entities:
		if not e.alive:
			continue
		var col: Color = G.players[e.team].color
		if e is Structure:
			var tl := _map_to_ui(Vector3(e.cell.x, 0, e.cell.y))
			draw_rect(Rect2(tl, cell_px * Vector2(e.size)), col, true)
		else:
			var p := _map_to_ui(e.position)
			draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), col.lightened(0.3), true)
	# camera footprint
	if G.camera and G.camera.cam:
		var vs := get_viewport().get_visible_rect().size
		var pts := PackedVector2Array()
		for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y), Vector2(0, 0)]:
			var gp: Vector3 = G.camera.screen_to_ground(c)
			pts.append(_map_to_ui(gp).clamp(Vector2.ZERO, size))
		draw_polyline(pts, Color(1, 1, 1, 0.8), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.66, 0.2, 0.8), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			G.camera.focus_on(_ui_to_map(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		G.camera.focus_on(_ui_to_map(event.position))
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# right-click on radar: move selected units there
		var cell: Vector2i = G.map.world_to_cell(_ui_to_map(event.position))
		if G.controller:
			G.controller._group_move(G.controller._own_units(G.controller.selection), cell)
		accept_event()
