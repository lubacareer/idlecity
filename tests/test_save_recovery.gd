extends SceneTree

const EconomyScript = preload("res://scripts/economy.gd")
const SaveScript = preload("res://scripts/save_manager.gd")
const TEST_PATH := "user://test_recovery_revision.json"

var failures: Array[String] = []


class SimulatedFailure extends "res://scripts/save_manager.gd":
	var fail_write := false
	var fail_promotion := false

	func _write_staged(contents: String) -> bool:
		if fail_write:
			var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
			file.store_string("{partial")
			file.close()
			last_error = "Simulated write failure"
			return false
		return super._write_staged(contents)

	func _promote_staged() -> bool:
		if fail_promotion:
			last_error = "Simulated promotion failure"
			return false
		return super._promote_staged()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	test_legacy_priority()
	test_revision_order_and_validation()
	test_retry_preserves_recovered_save()
	test_promotion_failure_and_retry()
	clear_files()
	if failures.is_empty():
		print("PASS: interrupted save recovery tests")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func city(coins: int) -> Dictionary:
	var game = EconomyScript.new(1000)
	game.coins = coins
	return game.serialize()


func write_json(suffix: String, data: Dictionary) -> void:
	var file := FileAccess.open(TEST_PATH + suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func load_coins(suffix: String) -> int:
	var file := FileAccess.open(TEST_PATH + suffix, FileAccess.READ)
	if file == null:
		return -1
	var data: Variant = JSON.parse_string(file.get_as_text())
	return int(data.coins) if data is Dictionary and data.has("coins") else -1


func test_legacy_priority() -> void:
	clear_files()
	write_json("", city(41))
	write_json(".bak", city(40))
	write_json(".tmp", city(42))
	var saver = SaveScript.new(TEST_PATH)
	var game = saver.load_game(1000)
	check(game != null and game.coins == 42 and saver.recovered_from_temporary, "legacy staged save beats legacy primary and backup")


func test_revision_order_and_validation() -> void:
	clear_files()
	var primary := city(44)
	primary["_save_revision"] = 4
	var backup := city(43)
	backup["_save_revision"] = 3
	var staged := city(45)
	staged["_save_revision"] = 5
	write_json("", primary)
	write_json(".bak", backup)
	write_json(".tmp", staged)
	var saver = SaveScript.new(TEST_PATH)
	var game = saver.load_game(1000)
	check(game != null and game.coins == 45 and saver.recovered_from_temporary, "newest valid revision selected")
	staged["_save_revision"] = -1
	write_json(".tmp", staged)
	saver = SaveScript.new(TEST_PATH)
	game = saver.load_game(1000)
	check(game != null and game.coins == 44, "invalid revision rejected in favor of valid primary")
	staged["_save_revision"] = 4
	write_json(".tmp", staged)
	saver = SaveScript.new(TEST_PATH)
	game = saver.load_game(1000)
	check(game != null and game.coins == 44, "revision tie prefers primary")


func test_retry_preserves_recovered_save() -> void:
	clear_files()
	write_json(".tmp", city(55))
	var saver = SimulatedFailure.new(TEST_PATH)
	var game = saver.load_game(1000)
	check(game != null and saver.recovered_from_temporary, "staged save recovered")
	game.coins = 65
	saver.fail_write = true
	check(not saver.save_game(game), "first simulated write fails")
	check(load_coins(".bak") == 55, "staged recovery secured before write")
	check(not saver.save_game(game), "retry simulated write fails")
	check(load_coins(".bak") == 55, "retry keeps last good backup")
	var after_crash = SaveScript.new(TEST_PATH).load_game(1000)
	check(after_crash != null and after_crash.coins == 55, "restart after failed retries retains recovered progress")
	saver.fail_write = false
	check(saver.save_game(game), "retry eventually succeeds")
	check(load_coins("") == 65, "successful retry promotes current progress")
	var reopened = SaveScript.new(TEST_PATH).load_game(1000)
	check(reopened != null and reopened.coins == 65, "successful retry reloads current progress")


func test_promotion_failure_and_retry() -> void:
	clear_files()
	var saver = SimulatedFailure.new(TEST_PATH)
	var game = EconomyScript.new(1000)
	check(saver.save_game(game), "initial save succeeds")
	game.coins = 75
	saver.fail_promotion = true
	check(not saver.save_game(game), "simulated promotion failure")
	check(load_coins("") == 40, "failed promotion preserves prior primary")
	var reopened_saver = SaveScript.new(TEST_PATH)
	var reopened = reopened_saver.load_game(1000)
	check(reopened != null and reopened.coins == 75, "newest valid staged revision survives restart")
	check(reopened_saver.save_game(reopened), "recovered newer staged save can be committed")
	check(load_coins("") == 75, "commit replaces existing primary")


func clear_files() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
