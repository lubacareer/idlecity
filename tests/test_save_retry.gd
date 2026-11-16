extends SceneTree

class FailingSaver extends SaveManager:
	var calls := 0
	var failures_remaining := 2

	func load_game(_now: int):
		return null

	func save_game(_game) -> bool:
		calls += 1
		if failures_remaining > 0:
			failures_remaining -= 1
			last_error = "simulated storage failure"
			return false
		last_error = ""
		return true

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var city = load("res://scenes/main.tscn").instantiate()
	var fake := FailingSaver.new()
	city.saver = fake
	root.add_child(city)
	await process_frame
	if fake.calls != 1 or not city.save_warning.visible:
		printerr("FAIL: failed initial save must display warning")
		quit(1)
		return
	city._process(5.1)
	if fake.calls != 2 or not city.save_warning.visible:
		printerr("FAIL: failed retry must retain warning")
		quit(1)
		return
	city._process(10.1)
	if fake.calls != 3 or city.save_warning.visible:
		printerr("FAIL: successful retry must clear warning")
		quit(1)
		return
	city.queue_free()
	print("PASS: save retry interaction tests")
	quit(0)
