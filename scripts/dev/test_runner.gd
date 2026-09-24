extends Node
## Automated test harness (autoload "TestRunner"). Idle unless the game is
## started with `-- --test=NAME`:
##   --test=mN        play mission N with a scripted solution; must be won
##   --test=campaign  play all ten missions back to back through the real
##                    briefing / mission-accomplished flow, then the epilogue
##   --test=smoke     load every mission and let it run for a while
## Prints "TEST PASS ..." or "TEST FAIL ..." and quits with exit code 0 / 1.

var mode := ""
var only := 0
var mission: Mission
var _deadline := 0.0
var _results: Array = []
var _campaign_flags := {}


func begin(p_name: String) -> void:
	mode = p_name
	process_mode = Node.PROCESS_MODE_ALWAYS
	Campaign.flags = {}
	Campaign.completed = false
	if p_name.begins_with("m"):
		only = int(p_name.substr(1))
		Campaign.mission_index = only
		Campaign.start_mission()
	elif p_name == "campaign":
		Campaign.new_game()
	elif p_name.begins_with("shot"):
		# shotN[:seconds] - render mission N for a while and save a screenshot
		var spec := p_name.substr(4)
		only = int(spec.get_slice(":", 0))
		Campaign.mission_index = maxi(only, 1)
		if only == 0:
			_shot_menu.call_deferred(spec)
		else:
			Campaign.start_mission()
	elif p_name == "smoke":
		Campaign.mission_index = 1
		Campaign.start_mission()
	else:
		_fail("unknown test " + p_name)


func attach(m: Mission) -> void:
	mission = m
	_run.call_deferred(m)


func _run(m: Mission) -> void:
	print("TEST mission %d start" % m.number)
	if mode.begins_with("shot"):
		var secs := float(mode.get_slice(":", 1)) if mode.contains(":") else 4.0
		await _wait_time(m, secs)
		await _save_shot("mission%d" % m.number)
		get_tree().quit(0)
		return
	if mode == "smoke":
		await _wait_time(m, 150.0)
		if not is_instance_valid(m):
			return
		print("TEST smoke mission %d ok (t=%.0f, ended=%s)" % [m.number, m.time, m.ended])
		if m.number >= Campaign.MISSIONS.size():
			_pass("smoke")
			return
		Campaign.mission_index = m.number + 1
		Campaign.start_mission()
		return
	var fn := "solve_m%d" % m.number
	var solver := MissionSolver.new()
	solver.m = m
	solver.runner = self
	add_child(solver)
	await solver.call(fn)
	if not is_instance_valid(m):
		return
	# wait for the win (or a loss)
	var t0 := m.time
	while is_instance_valid(m) and not m.ended and m.time - t0 < 60.0:
		await get_tree().physics_frame
	solver.queue_free()
	if not is_instance_valid(m):
		return
	if not m.won:
		var states: Array = []
		for o in m.objectives:
			states.append("%s=%s" % [o["id"], o["state"]])
		_fail("mission %d not won (ended=%s) objectives: %s" % [m.number, m.ended, ", ".join(PackedStringArray(states))])
		return
	var st: Array = []
	for o in m.objectives:
		st.append("%s=%s" % [o["id"], o["state"]])
	print("TEST mission %d WON at t=%.0f  [%s]" % [m.number, m.time, ", ".join(PackedStringArray(st))])
	if mode == "campaign":
		await get_tree().create_timer(0.5).timeout
		Campaign.advance()
		if Campaign.completed:
			await get_tree().create_timer(0.5).timeout
			print("TEST epilogue reached, flags: %s" % str(Campaign.flags))
			var need := ["tallow_friendly", "resonator_x", "refugees_saved", "seed_core_known", "rourke_arrested"]
			for k in need:
				if not Campaign.flag(k):
					_fail("campaign flag missing: " + k)
					return
			_pass("campaign")
	else:
		_pass("m%d" % m.number)


func _save_shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("ASHFALL_SHOT_DIR")
	if dir == "":
		dir = "user://"
	var path := dir.path_join("shot_%s.png" % tag)
	img.save_png(path)
	print("TEST shot saved ", path)


func _shot_menu(spec: String) -> void:
	# shot0:menu | shot0:briefing | shot0:prologue
	var what := spec.get_slice(":", 1)
	if what == "menu" or what == "":
		get_tree().change_scene_to_file(Campaign.MENU_SCENE)
	else:
		Campaign.story_mode = what
		get_tree().change_scene_to_file(Campaign.STORY_SCENE)
	await get_tree().create_timer(2.5).timeout
	await _save_shot(what)
	get_tree().quit(0)


func _wait_time(m: Mission, secs: float) -> void:
	var t0 := m.time
	while is_instance_valid(m) and m.time - t0 < secs and not m.ended:
		await get_tree().physics_frame


func _pass(what: String) -> void:
	print("TEST PASS %s" % what)
	get_tree().quit(0)


func _fail(msg: String) -> void:
	print("TEST FAIL %s" % msg)
	get_tree().quit(1)
