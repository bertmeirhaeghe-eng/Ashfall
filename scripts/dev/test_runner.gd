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


## Speaks one line per character through the active voice backend (run with
## ASHFALL_VOICE=kokoro) and saves the rendered Kokoro audio for inspection.
func _voice_test() -> void:
	print("TEST voice backend: ", Voice.backend_name())
	if Voice.backend != Voice.Backend.KOKORO:
		_fail("Kokoro backend not active")
		return
	var lines := [["okafor", "Commander, welcome to the Rhine."], ["havel", "Bad news first."],
		["rourke", "I don't waste loans."], ["sibyl", "Every machine you own already listens to me."],
		["tallow", "Don't wake the Maw."], ["kestrel", "Let's not waste each other's time."],
		["lindqvist", "I think the Seed is not a rock."], ["narrator", "In 2031, the night sky filled with green fire."]]
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
		print("TEST voice %-10s voice #%d  %.2fs audio, started at %.2fs" % [l[0], item["sid"], secs, started.get(l[0], -1.0)])
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
	print("TEST PASS %s" % what)
	get_tree().quit(0)


func _fail(msg: String) -> void:
	print("TEST FAIL %s" % msg)
	get_tree().quit(1)
