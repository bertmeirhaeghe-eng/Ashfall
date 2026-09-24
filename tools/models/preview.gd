extends SceneTree
## Renders a contact sheet of models (both factions) to a PNG.
## xvfb-run godot --rendering-driver opengl3 --path . --script tools/models/preview.gd -- out.png [model ...]

const PREVIEW_UNITS := ["rifleman", "rocket_trooper", "harvester", "scout_mech", "walker", "buggy", "tank"]
const PREVIEW_STRUCTURES := ["construction_yard", "power_plant", "refinery", "barracks", "war_factory", "guard_tower"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "preview.png" if args.is_empty() else args[0]
	var names: Array = []
	for i in range(1, args.size()):
		names.append(args[i])
	if names.is_empty():
		names = PREVIEW_UNITS + PREVIEW_STRUCTURES
	var zoom := float(OS.get_environment("ZOOM")) if OS.has_environment("ZOOM") else 1.0
	var yaw := float(OS.get_environment("YAW")) if OS.has_environment("YAW") else 35.0

	var world := Node3D.new()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.27, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.27, 0.21)
	ground.material_override = gm
	world.add_child(ground)

	var cols := 0
	var x := 0.0
	var width := 0.0
	var row_depth := 0.0
	for n in names:
		var sz := _size_of(n)
		width += sz + 0.6
		row_depth = maxf(row_depth, sz)
	x = -width / 2.0
	for n in names:
		var sz := _size_of(n)
		for fi in 2:
			var faction: String = ["bastion", "veil"][fi]
			var col: Color = [Color(0.2, 0.5, 1.0), Color(0.9, 0.15, 0.1)][fi]
			var m := MeshFactory.build(n, col, faction)
			m.position = Vector3(x + sz / 2.0, 0, fi * (row_depth + 0.8))
			m.rotation.y = deg_to_rad(float(OS.get_environment("SPIN")) if OS.has_environment("SPIN") else 25.0)
			world.add_child(m)
		x += sz + 0.6
		cols += 1
	get_root().add_child(world)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(width * 0.55, row_depth * 2.0 + 2.0) / zoom
	world.add_child(cam)
	var c := Vector3(0, 0.3, (row_depth + 0.8) / 2.0)
	if OS.has_environment("PAN"):
		c.x += float(OS.get_environment("PAN"))
	var dir := Vector3(0, 0.75, 1.0).rotated(Vector3.UP, deg_to_rad(yaw - 35.0)).normalized()
	cam.look_at_from_position(c + dir * 40.0, c)
	get_root().size = Vector2i(1800, 900)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()


func _size_of(n: String) -> float:
	match n:
		"construction_yard", "refinery", "war_factory":
			return 3.0
		"power_plant", "barracks":
			return 2.0
		"harvester", "walker":
			return 1.5
		"guard_tower", "scout_mech", "buggy", "tank":
			return 1.0
	return 0.5
