extends SceneTree

const SaveScript = preload("res://scripts/save_manager.gd")
const TEST_SAVE := "user://test_ui_save.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run_tests() -> void:
	root.size = Vector2i(1280, 720)
	await test_touch_purchase()
	await test_touch_collection_and_cancel()
	await test_corrupt_save_controls()
	clear_save()
	if failures.is_empty():
		print("PASS: UI interaction tests")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func make_city():
	var city = load("res://scenes/main.tscn").instantiate()
	city.saver = SaveScript.new(TEST_SAVE)
	root.add_child(city)
	return city


func tap(pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = pos
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = pos
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func test_touch_purchase() -> void:
	clear_save()
	var city = make_city()
	await process_frame
	await process_frame
	check(city.economy != null, "fresh city starts")
	# PLACE in the first building card.
	await tap(Vector2(1140, 307))
	check(city.active_type == "house", "touch selects a building")
	var target: Vector2 = city._tile_center(2, 2)
	await tap(target)
	check(city.economy.buildings.size() == 1 and city.economy.coins == 40, "first touch previews without purchase")
	check(city.hover_cell == Vector2i(2, 2), "first touch highlights chosen tile")
	await tap(target)
	check(city.economy.buildings.size() == 2 and city.economy.coins == 0, "second touch confirms purchase")
	if city.economy.buildings.size() == 2:
		var placed: Dictionary = city.economy.buildings[1]
		check(placed.x == 2 and placed.y == 2, "confirmed building occupies selected tile")
	city.queue_free()
	await process_frame


func test_corrupt_save_controls() -> void:
	clear_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("broken save")
	file.close()
	var city = make_city()
	await process_frame
	await process_frame
	check(city.economy == null and not city.saver.last_error.is_empty(), "corrupt save is surfaced")
	check(city.buildings_tab.disabled and city.residents_tab.disabled, "tabs disabled when game could not load")
	await tap(Vector2(1150, 200))
	check(FileAccess.get_file_as_string(TEST_SAVE) == "broken save", "touching error screen preserves corrupt save")
	city.queue_free()
	await process_frame


func test_touch_collection_and_cancel() -> void:
	clear_save()
	var city = make_city()
	await process_frame
	await process_frame
	var starter: Dictionary = city.economy.buildings[0]
	for index in range(3):
		starter["cycle_started_at"] = city._now() - 30
		await tap(city._coin_position(starter))
		check(city.economy.xp == index + 1, "touch collects the ready coin once")
	check(city.economy.level() == 2 and city.economy.coins == 70, "touch collection unlocks level 2")
	# Select the unlocked café card, then preview and cancel its placement.
	await tap(Vector2(1140, 401))
	check(city.active_type == "cafe", "unlocked café is selectable by touch")
	await tap(city._tile_center(2, 2))
	check(city.economy.buildings.size() == 1 and city.economy.coins == 70, "preview does not charge")
	await tap(Vector2(1100, 642))
	check(city.active_type.is_empty(), "touch cancellation exits placement")
	check(city.economy.buildings.size() == 1 and city.economy.coins == 70, "cancellation does not charge")
	city.queue_free()
	await process_frame


func clear_save() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + suffix))
