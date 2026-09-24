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
			await get_tree().create_timer(2.0).timeout
			print("TEST epilogue reached, flags: %s" % str(Campaign.flags))
			_pass("campaign")
	else:
		_pass("m%d" % m.number)


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
