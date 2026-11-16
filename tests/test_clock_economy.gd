extends SceneTree

const EconomyScript = preload("res://scripts/economy.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _initialize() -> void:
	test_active_clock()
	test_restart_and_resume()
	test_validation_and_placement()
	if failures.is_empty():
		print("PASS: clock and economy regressions")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func test_active_clock() -> void:
	var game = EconomyScript.new(1000)
	game.start_clock(1000, 0)
	check(not game.is_ready(1, game.advance_time(100000, 10000)), "forward wall change does not grant active income")
	check(not game.is_ready(1, game.advance_time(1001, 29000)), "wall correction does not block active time")
	check(game.is_ready(1, game.advance_time(1002, 30000)), "cycle becomes ready at monotonic boundary")
	check(game.collect(1, game.advance_time(1002, 30000)), "ready cycle is collectible")
	check(not game.is_ready(1, game.advance_time(1, 59000)), "rollback does not grant another cycle")
	check(game.is_ready(1, game.advance_time(2, 60000)), "active cycle continues after backward clock change")

func test_restart_and_resume() -> void:
	var game = EconomyScript.new(1000)
	game.start_clock(1000, 0)
	game.advance_time(1010, 10000)
	game.pause_clock(1010)
	var loaded = EconomyScript.from_data(game.serialize(), 1000000)
	check(loaded != null and loaded.is_ready(1, loaded.last_observed_at), "offline return completes cycle")
	check(loaded.collect(1, loaded.last_observed_at), "offline ready income can be collected")
	check(not loaded.collect(1, loaded.last_observed_at), "long offline period grants one cycle")
	loaded.start_clock(1000000, 10000)
	loaded.pause_clock(1000000)
	loaded.resume_clock(10, 20000)
	check(not loaded.is_ready(1, loaded.advance_time(10, 20000)), "backward wall clock gives no offline income")
	check(loaded.is_ready(1, loaded.advance_time(40, 50000)), "clock resumes after backward correction")
	var legacy: Dictionary = EconomyScript.new(1000).serialize()
	legacy.erase("wall_checkpoint_at")
	var legacy_loaded = EconomyScript.from_data(legacy, 1030)
	check(legacy_loaded != null and legacy_loaded.is_ready(1, legacy_loaded.last_observed_at), "legacy v1 save accrues offline time")
	var partial = EconomyScript.from_data(EconomyScript.new(1000).serialize(), 1029)
	check(partial != null and not partial.is_ready(1, partial.last_observed_at), "partial offline cycle is not ready early")
	var at_boundary = EconomyScript.from_data(partial.serialize(), 1030)
	check(at_boundary != null and at_boundary.is_ready(1, at_boundary.last_observed_at), "partial offline cycle survives restart to boundary")
	var corrected = EconomyScript.from_data(EconomyScript.new(5000).serialize(), 1000)
	check(corrected != null and not corrected.is_ready(1, corrected.last_observed_at), "clock correction at restart grants no income")
	corrected.start_clock(1000, 0)
	check(corrected.is_ready(1, corrected.advance_time(1030, 30000)), "clock correction at restart does not stall future cycles")
	var paused = EconomyScript.new(1000)
	paused.start_clock(1000, 0)
	paused.pause_clock(1000)
	paused.pause_clock(1020)
	paused.resume_clock(1030, 30000)
	check(paused.is_ready(1, paused.last_observed_at), "duplicate pause does not discard offline elapsed time")

func test_validation_and_placement() -> void:
	var data: Dictionary = EconomyScript.new(1000).serialize()
	data.buildings[0].type = "cafe"
	check(EconomyScript.from_data(data, 1000) == null, "locked cafe is rejected")
	data.xp = 3
	check(EconomyScript.from_data(data, 1000) != null, "cafe valid at level 2")
	data.buildings[0].type = "bakery"
	check(EconomyScript.from_data(data, 1000) == null, "locked bakery is rejected")
	data.xp = 10
	check(EconomyScript.from_data(data, 1000) != null, "bakery valid at level 3")
	data.wall_checkpoint_at = -1
	check(EconomyScript.from_data(data, 1000) == null, "invalid wall checkpoint rejected")
	var game = EconomyScript.new(1000)
	check(game.is_ready(1, 1030), "ready cycle is visible at exact boundary")
	check(game.purchase("house", 1, 2, 1030), "buy house at chosen coordinate")
	check(game.buildings[1].x == 1 and game.buildings[1].y == 2, "purchase records chosen coordinate")
