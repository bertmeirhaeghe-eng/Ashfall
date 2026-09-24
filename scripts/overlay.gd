class_name Overlay
extends Control
## Screen-space overlay: health bars, veterancy chevrons, harvester cargo,
## drag box and mode hint next to the cursor.

const GREEN := Color(0.3, 0.95, 0.35)
const YELLOW := Color(1.0, 0.85, 0.2)
const RED := Color(1.0, 0.25, 0.2)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if G.camera == null or G.camera.cam == null:
		return
	var cam: Camera3D = G.camera.cam
	var vp := get_viewport_rect()
	for e in G.entities:
		if not e.alive:
			continue
		var want_bar: bool = e.selected or e.hp < e.max_hp - 0.5 or (e is Structure and e.repairing)
		if not want_bar:
			continue
		var wp: Vector3 = e.position + Vector3(0, e.bar_height + 0.15, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not vp.grow(40).has_point(sp):
			continue
		_draw_bars(e, sp)
	# drag box
	if G.controller:
		var r: Rect2 = G.controller.drag_rect()
		if r.size.x > 2 and r.size.y > 2:
			draw_rect(r, Color(0.4, 1.0, 0.4, 0.12), true)
			draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 1.0)
		var label: String = G.controller.mode_label()
		if label != "":
			var mp := get_viewport().get_mouse_position()
			var font := get_theme_default_font()
			draw_string(font, mp + Vector2(18, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.4))


func _draw_bars(e, sp: Vector2) -> void:
	var w := 70.0 if e is Structure else 34.0
	var frac: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
	var col := GREEN if frac > 0.6 else (YELLOW if frac > 0.3 else RED)
	var r := Rect2(sp.x - w * 0.5, sp.y, w, 5)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(r.position, Vector2(w * frac, 5)), col, true)
	# pips every 25%
	for i: int in range(1, 4):
		var x: float = r.position.x + w * i / 4.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.5), 1.0)
	if e.team != G.local_team:
		draw_rect(Rect2(r.position.x - 6, r.position.y, 4, 5), RED, true)
	# harvester cargo
	if e is Harvester:
		var c: float = e.cargo / maxf(e.capacity, 1.0)
		var r2 := Rect2(r.position.x, r.end.y + 2, w, 3)
		draw_rect(r2.grow(1), Color(0, 0, 0, 0.75), true)
		draw_rect(Rect2(r2.position, Vector2(w * c, 3)), Color(0.35, 1.0, 0.5), true)
	# veterancy chevrons
	var rank_i: int = e.rank
	for i: int in rank_i:
		var cx: float = r.end.x + 5.0 + i * 7.0
		var cy: float = r.position.y + 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, cy - 2), Vector2(cx, cy + 2), Vector2(cx + 3, cy - 2)]), Color(1.0, 0.8, 0.2))
	# repair wrench blink
	if e is Structure and e.repairing and int(G.elapsed * 3.0) % 2 == 0:
		draw_string(get_theme_default_font(), Vector2(sp.x - 5, sp.y - 6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GREEN)
