class_name RTSCamera
extends Node3D
## Classic RTS camera: pivot on the ground, pitched camera boom.
## Arrow keys / screen edges / middle-mouse drag to pan, wheel to zoom,
## Q/E to rotate between 4 fixed angles (design doc 3.2).

const PITCH_DEG := 55.0
const MIN_ZOOM := 10.0
const MAX_ZOOM := 48.0
const PAN_SPEED := 1.1       # multiplied by zoom
const EDGE_PX := 10

var cam: Camera3D
var zoom := 26.0
var target_zoom := 26.0
var yaw := 0.0
var target_yaw := 0.0
var edge_scroll := true
var bounds := Rect2(0, 0, 80, 80)
var _mmb := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_update_boom()


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func focus_on(p: Vector3) -> void:
	position = Vector3(p.x, G.map.height_at(p) if G.map else 0.0, p.z)
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_zoom = clampf(target_zoom * 0.88, MIN_ZOOM, MAX_ZOOM)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_zoom = clampf(target_zoom * 1.12, MIN_ZOOM, MAX_ZOOM)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb = mb.pressed
	elif event is InputEventMouseMotion and _mmb:
		var mm := event as InputEventMouseMotion
		var k := zoom * 0.0022
		position += (-right() * mm.relative.x + forward() * mm.relative.y) * k
		_clamp()
	elif event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_Q:
			target_yaw += PI / 2.0
		elif ke.keycode == KEY_E:
			target_yaw -= PI / 2.0


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if edge_scroll and not _mmb and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var sz := vp.get_visible_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x <= sz.x and mp.y <= sz.y:
			if mp.x < EDGE_PX:
				dir.x -= 1
			elif mp.x > sz.x - EDGE_PX:
				dir.x += 1
			if mp.y < EDGE_PX:
				dir.y -= 1
			elif mp.y > sz.y - EDGE_PX:
				dir.y += 1
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		# real delta even while paused
		position += (right() * dir.x - forward() * dir.y) * PAN_SPEED * zoom * delta
		_clamp()
	if G.map:
		position.y = lerpf(position.y, G.map.height_at(position), minf(1.0, delta * 4.0))
	zoom = lerpf(zoom, target_zoom, minf(1.0, delta * 10.0))
	yaw = lerp_angle(yaw, target_yaw, minf(1.0, delta * 8.0))
	_update_boom()


func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _update_boom() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	var p := deg_to_rad(PITCH_DEG)
	cam.position = Vector3(0.0, sin(p) * zoom, cos(p) * zoom)
	cam.rotation = Vector3(-p, 0.0, 0.0)


## Mouse position -> point on the terrain.
func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen_pos)
	var n := cam.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return Vector3(o.x, 0, o.z)
	# march down to the plane, then refine against the terrain height
	var p := o + n * (-o.y / n.y)
	if G.map:
		for i in 5:
			var gh: float = G.map.height_at(p)
			p = o + n * ((gh - o.y) / n.y)
	return p
