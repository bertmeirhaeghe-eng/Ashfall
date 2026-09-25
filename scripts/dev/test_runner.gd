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
	elif p_name == "voice":
		_voice_test.call_deferred()
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
		if OS.get_cmdline_user_args().has("--fxdemo"):
			await _fx_demo(m)
		elif OS.get_cmdline_user_args().has("--fxboom"):
			await _fx_boom(m)
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


## Stages a firefight in front of the camera (--fxdemo with shotN) to look at
## muzzle flashes, impacts, explosions, lights and lightning in screenshots.
func _fx_demo(m: Mission) -> void:
	var c: Vector3 = G.camera.position
	var z := OS.get_environment("ASHFALL_SHOT_ZOOM")
	if z != "":
		G.camera.target_zoom = float(z)
	if G.hud:
		G.hud.visible = false
	for n in get_tree().get_nodes_in_group("dialogue"):
		n.visible = false
	var ids_a := ["rifleman", "rifleman", "rocket_trooper", "warden", "tempest"]
	var ids_b := ["cyborg", "cyborg", "scorpion", "scorpion", "veil_artillery"]
	for i in ids_a.size():
		G.spawn_unit(ids_a[i], G.PLAYER, c + Vector3(-4.5 + randf_range(-1, 1), 0, -3.0 + i * 1.5))
	for i in ids_b.size():
		G.spawn_unit(ids_b[i], G.ENEMY, c + Vector3(4.5 + randf_range(-1, 1), 0, -3.0 + i * 1.5))
	await _wait_time(m, 2.4)
	Fx.explosion(c + Vector3(2.0, 0.3, 3.5), 1.6)
	await _wait_time(m, 0.3)
	Fx.explosion(c + Vector3(-1.5, 0.3, -3.0), 0.9)
	if G.weather:
		G.weather.strike(c + Vector3(1.0, G.map.height_at(c), -5.0), Color(0.6, 0.7, 1.0))
	await _wait_time(m, 0.12)
	await _save_shot("mission%d_a" % m.number)
	await _wait_time(m, 0.5)


## Frame sequence of one explosion and a cannon shot up close (--fxboom).
func _fx_boom(m: Mission) -> void:
	var c: Vector3 = G.camera.position
	G.camera.target_zoom = 14.0
	if G.hud:
		G.hud.visible = false
	await _wait_time(m, 1.2)
	var p := Vector3(c.x, G.map.height_at(c) + 0.4, c.z)
	Fx.explosion(p, 1.5)
	Fx.flash(p + Vector3(-3, 0.5, 2), Vector3(1, 0, 0), "shell", 90.0)
	Fx.flash(p + Vector3(-3, 0.5, 3), Vector3(1, 0, 0), "tracer", 12.0)
	Fx.impact(p + Vector3(3, -0.3, 2.5), "tracer")
	var times := [0.05, 0.15, 0.35, 0.7, 1.4]
	var t := 0.0
	for i in times.size():
		await _wait_time(m, times[i] - t)
		t = times[i]
		await _save_shot("boom%d" % i)


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
	# shot0:menu | shot0:options | shot0:briefing | shot0:prologue
	var what := spec.get_slice(":", 1)
	if what == "menu" or what == "" or what == "options":
		get_tree().change_scene_to_file(Campaign.MENU_SCENE)
		if what == "options":
			await get_tree().create_timer(0.5).timeout
			get_tree().current_scene.call("_on_options")
	else:
		Campaign.story_mode = what
		get_tree().change_scene_to_file(Campaign.STORY_SCENE)
	await get_tree().create_timer(2.5).timeout
	await _save_shot(what)
	get_tree().quit(0)


## Speaks one line per character through the active voice backend (run with
## ASHFALL_VOICE=kokoro) and saves the rendered Kokoro audio for inspection.
func _voice_test() -> void:
	print("TEST voice backend: ", Voice.backend_name(), "  language: ", Settings.language)
	if not ["kokoro", "kokoro_nl", "piper"].has(Voice.engine_for(Settings.language)):
		_fail("no rendering voice engine (Kokoro / Piper) active")
		return
	var lines := [["okafor", "I don't like it either, Commander. But I like losing Istanbul less. She's under your command."],
		["havel", "The Pilgrim is rolling. Here it comes."], ["rourke", "I taught you everything you're about to try, Commander."],
		["sibyl", "A tower is a thought, Commander. I have many thoughts."], ["tallow", "We kept our word, Bastion. Now keep yours."],
		["kestrel", "This is for Oriel."], ["lindqvist", "Sample one. It's warm, Commander. Crystal shouldn't be warm."],
		["narrator", "In the night sky, a tiny green star is moving. Towards Earth."]]
	var t0 := Time.get_ticks_msec()
	var started := {}
	Voice.line_started.connect(func(spk, _n, _t, _c): started[spk] = (Time.get_ticks_msec() - t0) / 1000.0)
	for l in lines:
		Voice.say(l[0], l[1])
	while Voice.busy() and Time.get_ticks_msec() - t0 < 180000:
		await get_tree().process_frame
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	var dir := OS.get_environment("ASHFALL_SHOT_DIR")
	for l in lines:
		var item: Dictionary = Voice._make_item(l[0], l[1], Voice.Prio.DIALOG, "spk_" + l[0], Voice.SPEAKERS[l[0]], true)
		var wav: AudioStreamWAV = Voice._cached(item["key"])
		if wav == null:
			_fail("no audio rendered for " + l[0])
			return
		var secs := wav.get_length()
		print("TEST voice %-10s voice %s  %.2fs audio, started at %.2fs  \"%s\"" % [l[0], str(item["sid"]), secs, started.get(l[0], -1.0), item["text"]])
		if dir != "":
			wav.save_to_wav(dir.path_join("voice_%s.wav" % l[0]))
	print("TEST voice all lines finished in %.1fs" % total)
	# a unit reaction twice: the second one must come straight from the cache
	Voice.unit_ack("infantry", "select")
	await get_tree().create_timer(3.0).timeout
	_pass("voice")


func _wait_time(m: Mission, secs: float) -> void:
	var t0 := m.time
	while is_instance_valid(m) and m.time - t0 < secs and not m.ended:
		await get_tree().physics_frame


func _pass(what: String) -> void:
	_report_translations()
	print("TEST PASS %s" % what)
	get_tree().quit(0)


func _fail(msg: String) -> void:
	_report_translations()
	print("TEST FAIL %s" % msg)
	get_tree().quit(1)


## With --langcheck: every string that was shown or spoken without a translation.
func _report_translations() -> void:
	if not OS.get_cmdline_user_args().has("--langcheck"):
		return
	var miss: Array = Settings.missing_translations()
	miss.sort()
	for s in miss:
		print("TEST untranslated: ", str(s).replace("\n", "\\n"))
	print("TEST untranslated total: %d" % miss.size())
