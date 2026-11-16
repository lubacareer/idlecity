extends SceneTree

const EconomyScript = preload("res://scripts/economy.gd")
const SaveScript = preload("res://scripts/save_manager.gd")

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	test_income_and_unlocks()
	test_purchase_and_placement()
	test_offline_and_clock()
	test_validation()
	test_save_and_recovery()
	test_interrupted_first_write()
	if failures.is_empty():
		print("PASS: economy and persistence tests")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func test_income_and_unlocks() -> void:
	var game = EconomyScript.new(1000)
	check(game.coins == 40 and game.xp == 0 and game.level() == 1, "starter balance and level")
	check(game.buildings.size() == 1, "one starter house")
	check(not game.is_ready(999, 1000) and not game.collect(999, 1000), "unknown building rejected")
	var id: int = game.buildings[0].id
	check(not game.is_ready(id, 1029), "cycle is not ready early")
	check(not game.collect(id, 1029), "cannot collect early")
	check(game.collect(id, 1030), "ready income can be collected")
	check(game.coins == 50 and game.xp == 1, "collection awards income and XP")
	check(not game.collect(id, 1030), "duplicate tap cannot award again")
	check(game.collect(id, 1060), "second cycle")
	check(game.collect(id, 1090), "third cycle")
	check(game.level() == 2 and game.xp == 3, "level 2 at 3 XP")
	check(game.purchase("cafe", 2, 3, 1090), "cafe unlocks at level 2")
	check(game.collect(id, 1120), "house fourth cycle")
	check(game.collect(id, 1150), "house fifth cycle")
	check(game.collect(2, 1150), "cafe cycle awards 2 XP")
	check(game.collect(id, 1180), "house sixth cycle")
	check(game.collect(id, 1210), "house seventh cycle")
	check(game.collect(2, 1210), "second cafe cycle")
	check(game.level() == 3 and game.xp == 11, "level 3 at 10 cumulative XP")


func test_purchase_and_placement() -> void:
	var game = EconomyScript.new(0)
	check(not game.purchase("cafe", 1, 1, 0), "locked building is rejected")
	check(not game.purchase("unknown", 1, 1, 0), "unknown type is rejected")
	check(not game.purchase("house", 3, 3, 0), "occupied cell is rejected")
	check(not game.purchase("house", -1, 0, 0), "negative cell is rejected")
	check(not game.purchase("house", 8, 0, 0), "out of bounds cell is rejected")
	check(game.purchase("house", 0, 0, 0), "unlocked house can be bought")
	check(not game.purchase("house", 1, 0, 0), "insufficient balance is rejected")
	check(game.coins == 0 and game.buildings.size() == 2, "failed purchases do not spend")


func test_offline_and_clock() -> void:
	var game = EconomyScript.new(1000)
	var id: int = game.buildings[0].id
	check(game.collect(id, 10000), "offline cycle completes")
	check(game.coins == 50 and game.xp == 1, "offline income capped at one cycle")
	check(not game.collect(id, 10000), "offline collection starts next cycle")
	check(not game.collect(id, 9000), "backward clock does not grant income")
	check(not game.collect(id, 10029), "clock rollback does not shorten next cycle")
	check(game.collect(id, 10030), "cycle completes after clock catches up")
	var restored = EconomyScript.from_data(game.serialize(), 9000)
	check(restored != null and not restored.is_ready(id, 9000), "rollback remains safe after loading")


func test_validation() -> void:
	var game = EconomyScript.new(100)
	var original: Dictionary = game.serialize()
	check(EconomyScript.from_data(original, 100) != null, "valid save loads")
	var at_unlock: Dictionary = original.duplicate(true)
	at_unlock["xp"] = 10
	check(EconomyScript.from_data(at_unlock, 100).level() == 3, "level 3 unlocks at exactly 10 XP")
	var invalid: Dictionary = original.duplicate(true)
	invalid["version"] = 99
	check(EconomyScript.from_data(invalid, 100) == null, "unknown save version rejected")
	invalid = original.duplicate(true)
	invalid["coins"] = -1
	check(EconomyScript.from_data(invalid, 100) == null, "negative balance rejected")
	invalid = original.duplicate(true)
	invalid["buildings"][0]["type"] = "fake"
	check(EconomyScript.from_data(invalid, 100) == null, "unknown type rejected")
	invalid = original.duplicate(true)
	invalid["buildings"].append(invalid["buildings"][0].duplicate(true))
	check(EconomyScript.from_data(invalid, 100) == null, "duplicate id and position rejected")
	invalid = original.duplicate(true)
	invalid["buildings"][0]["cycle_started_at"] = 1000
	check(EconomyScript.from_data(invalid, 100) == null, "future cycle inconsistent with checkpoint rejected")


func test_save_and_recovery() -> void:
	var path = "user://test_economy_save.json"
	var saver = SaveScript.new(path)
	clear_save_files(path)
	check(not saver.exists(), "clean test save")
	check(saver.load_game(1000) == null and saver.last_error.is_empty(), "missing save means first launch")
	var game = EconomyScript.new(1000)
	check(saver.save_game(game), "first save succeeds")
	check(game.collect(1, 1030) and saver.save_game(game), "second save succeeds")
	var loaded = saver.load_game(1030)
	check(loaded != null and loaded.coins == 50 and loaded.xp == 1, "round trip preserves progress")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	loaded = saver.load_game(1030)
	check(loaded != null and saver.recovered_from_backup, "corrupt primary recovers backup")
	check(loaded != null and loaded.coins == 40, "backup retains prior committed state")
	check(saver.save_game(loaded), "recovered city can be saved")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt again")
	file.close()
	loaded = saver.load_game(1030)
	check(loaded != null and loaded.coins == 40, "saving recovered data preserves good backup")
	var backup = FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string("corrupt")
	backup.close()
	check(saver.load_game(1030) == null and not saver.last_error.is_empty(), "unrecoverable save is surfaced")
	check(not saver.save_game(EconomyScript.new(1000)), "unrecoverable save is never overwritten")
	check(FileAccess.get_file_as_string(path) == "corrupt again", "corrupt primary remains intact")
	clear_save_files(path)


func clear_save_files(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func test_interrupted_first_write() -> void:
	var path = "user://test_interrupted_save.json"
	clear_save_files(path)
	var temporary = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	temporary.store_string(JSON.stringify(EconomyScript.new(1000).serialize()))
	temporary.close()
	var saver = SaveScript.new(path)
	check(saver.exists(), "interrupted first write is detected")
	var game = saver.load_game(1000)
	check(game != null and game.coins == 40, "complete staged first save recovers")
	if game != null:
		check(saver.save_game(game), "recovered staged save commits")
		check(FileAccess.file_exists(path + ".bak"), "staged recovery retains a backup")
	clear_save_files(path)
	temporary = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	temporary.store_string("incomplete")
	temporary.close()
	saver = SaveScript.new(path)
	check(saver.load_game(1000) == null and not saver.last_error.is_empty(), "incomplete first write is reported")
	check(not saver.save_game(EconomyScript.new(1000)), "incomplete staged save is not overwritten")
	check(FileAccess.get_file_as_string(path + ".tmp") == "incomplete", "incomplete staged data remains intact")
	clear_save_files(path)
