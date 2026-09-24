class_name Minimap
extends Control
## North-up radar: terrain/crystal image, unit dots, structure blocks, mission
## markers and the camera's ground footprint. Needs a powered Radar (or a
## mission-provided uplink); glass storms jam it. Click or drag to move the
## camera, right-click to send the selection.

var _dragging := false
var _was_online := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _view() -> Rect2:
	if G.camera:
		var b: Rect2 = G.camera.bounds
		return b.grow(4).intersection(Rect2(0, 0, G.map.w, G.map.h))
	return Rect2(0, 0, G.map.w, G.map.h)


func _map_to_ui(p: Vector3) -> Vector2:
	var v := _view()
	return Vector2((p.x - v.position.x) / v.size.x * size.x, (p.z - v.position.y) / v.size.y * size.y)


func _ui_to_map(p: Vector2) -> Vector3:
	var v := _view()
	return Vector3(v.position.x + p.x / size.x * v.size.x, 0.0, v.position.y + p.y / size.y * v.size.y)


func online() -> bool:
	return G.players.size() > G.local_team and (G.players[G.local_team] as PlayerState).has_radar()


func _draw() -> void:
	if G.map == null or G.map.ground_tex == null:
		return
	var on := online()
	if on != _was_online:
		_was_online = on
		if G.mission and G.mission.time > 1.0:
			G.notify(G.local_team, "Radar online" if on else "Radar offline", true)
	var v := _view()
	var src := Rect2(v.position.x, v.position.y, v.size.x, v.size.y)
	draw_texture_rect_region(G.map.ground_tex, Rect2(Vector2.ZERO, size), src)
	if not on:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.03, 0.85))
		for i in 60:
			var y := randf() * size.y
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.4, 0.5, 0.45, randf() * 0.3), 1.0)
		var font := get_theme_default_font()
		var msg := "RADAR JAMMED" if G.radar_jammed else "NO RADAR"
		draw_string(font, Vector2(0, size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1.0, 0.5, 0.3))
		_draw_frame()
		return
	var cell_px := size / v.size
	for e in G.entities:
		if not e.alive or not e.visible_to(G.local_team) or e.def.get("decor", false):
			continue
		if e.hidden_underground() and e.team != G.local_team:
			continue
		var col: Color = G.players[e.team].color
		if e is Structure:
			var tl := _map_to_ui(Vector3(e.cell.x, 0, e.cell.y))
			draw_rect(Rect2(tl, cell_px * Vector2(e.size)), col, true)
		else:
			var p := _map_to_ui(e.position)
			draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), col.lightened(0.3), true)
	if G.mission:
		var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
		for m in G.mission.markers:
			var mp := _map_to_ui(m["pos"])
			var c: Color = m["color"]
			draw_arc(mp, 5.0 if blink else 7.0, 0, TAU, 16, c, 2.0)
	_draw_frame()


func _draw_frame() -> void:
	if G.camera and G.camera.cam:
		var vs := get_viewport().get_visible_rect().size
		var pts := PackedVector2Array()
		for c in [Vector2(0, 0), Vector2(vs.x - HUD.SIDEBAR_W, 0), Vector2(vs.x - HUD.SIDEBAR_W, vs.y), Vector2(0, vs.y), Vector2(0, 0)]:
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
		var cell: Vector2i = G.map.world_to_cell(_ui_to_map(event.position))
		if G.controller:
			G.controller._group_move(G.controller._own_units(G.controller.selection), cell)
		accept_event()
