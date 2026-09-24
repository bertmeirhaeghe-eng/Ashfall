class_name SkyBackdrop
extends Control
## Animated 2D backdrop for the menu and briefing screens: a dark sky with
## green meteor streaks falling (the Ashfall) and a glowing crystal horizon.

var meteors: Array = []
var stars: Array = []
var intensity := 1.0
var tint := Color(0.3, 1.0, 0.45)
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 140:
		stars.append(Vector3(randf(), randf() * 0.75, randf_range(0.3, 1.0)))
	for i in 10:
		meteors.append(_new_meteor(true))


func _new_meteor(anywhere := false) -> Dictionary:
	return {
		"x": randf_range(-0.2, 1.1), "y": randf_range(-0.6, 0.5) if anywhere else randf_range(-0.4, -0.05),
		"v": randf_range(0.12, 0.3), "len": randf_range(0.05, 0.16), "w": randf_range(1.0, 3.0),
	}


func _process(delta: float) -> void:
	_t += delta
	for m in meteors:
		m["x"] += m["v"] * delta * 0.55
		m["y"] += m["v"] * delta
		if m["y"] > 1.1:
			var n := _new_meteor()
			for k in n.keys():
				m[k] = n[k]
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.025, 0.035))
	# horizon glow
	for i in 24:
		var k := float(i) / 24.0
		var y := s.y * (0.62 + k * 0.38)
		var c := Color(tint.r * 0.25, tint.g * 0.25, tint.b * 0.25, 0.04 + k * 0.05)
		draw_rect(Rect2(0, y, s.x, s.y * 0.02 + 1), c)
	for st in stars:
		var tw := 0.6 + 0.4 * sin(_t * 2.0 + st.x * 40.0)
		draw_rect(Rect2(st.x * s.x, st.y * s.y, 1.5, 1.5), Color(0.8, 0.85, 1.0, st.z * tw * 0.8))
	for m in meteors:
		var head := Vector2(m["x"] * s.x, m["y"] * s.y)
		var tail: Vector2 = head - Vector2(0.55, 1.0).normalized() * float(m["len"]) * s.y
		for k in 4:
			var a := 0.12 + 0.22 * k
			draw_line(tail.lerp(head, k / 4.0), head, Color(tint.r, tint.g, tint.b, a * intensity), m["w"] * (1.0 + k * 0.4))
		draw_circle(head, m["w"] * 1.6, Color(0.8, 1.0, 0.85, 0.9 * intensity))
	# crystal silhouettes on the horizon
	var base_y := s.y * 0.9
	var x := 0.0
	var i := 0
	while x < s.x:
		var hgt := 20.0 + float(hash(i) % 70)
		var wdt := 16.0 + float(hash(i * 7) % 30)
		draw_colored_polygon(PackedVector2Array([Vector2(x, s.y), Vector2(x + wdt * 0.5, base_y - hgt), Vector2(x + wdt, s.y)]),
			Color(0.04, 0.09, 0.06))
		x += wdt * 0.7
		i += 1
