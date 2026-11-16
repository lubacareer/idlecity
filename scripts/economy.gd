class_name Economy
extends RefCounted

const SAVE_VERSION := 1
const GRID_SIZE := 8
const LEVEL_TWO_XP := 3
const LEVEL_THREE_XP := 10
const MAX_OFFLINE_SECONDS := 120
const CATALOG := {
	"house": {"name": "House", "cost": 40, "required_level": 1, "income": 10, "xp": 1, "seconds": 30},
	"cafe": {"name": "Café", "cost": 50, "required_level": 2, "income": 25, "xp": 2, "seconds": 60},
	"bakery": {"name": "Bakery", "cost": 150, "required_level": 3, "income": 60, "xp": 3, "seconds": 120},
}

var coins: int = 40
var xp: int = 0
var buildings: Array = []
var last_observed_at: int = 0
var next_id: int = 2
var wall_checkpoint_at: int = 0
var _clock_started := false
var _clock_paused := false
var _last_monotonic_ms: int = 0


func _init(now: int = 0) -> void:
	last_observed_at = maxi(0, now)
	wall_checkpoint_at = last_observed_at
	buildings = [{"id": 1, "type": "house", "x": 3, "y": 3, "cycle_started_at": last_observed_at}]


func catalog() -> Dictionary:
	return CATALOG.duplicate(true)


func level() -> int:
	if xp >= LEVEL_THREE_XP:
		return 3
	if xp >= LEVEL_TWO_XP:
		return 2
	return 1


func observe_time(now: int) -> int:
	# Callers using the original API supply a wall-clock-like timeline. Active
	# sessions instead pass the monotonic logical time from advance_time().
	last_observed_at = maxi(last_observed_at, now)
	if not _clock_started:
		wall_checkpoint_at = maxi(wall_checkpoint_at, now)
	return last_observed_at


func start_clock(wall_now: int, monotonic_ms: int) -> void:
	_clock_started = true
	_clock_paused = false
	wall_checkpoint_at = maxi(0, wall_now)
	_last_monotonic_ms = monotonic_ms


func advance_time(wall_now: int, monotonic_ms: int) -> int:
	if not _clock_started:
		start_clock(wall_now, monotonic_ms)
	if _clock_paused:
		return last_observed_at
	var elapsed_ms := maxi(0, monotonic_ms - _last_monotonic_ms)
	var elapsed_seconds := int(elapsed_ms / 1000)
	last_observed_at += elapsed_seconds
	_last_monotonic_ms += elapsed_seconds * 1000
	wall_checkpoint_at = maxi(0, wall_now)
	return last_observed_at


func pause_clock(wall_now: int) -> void:
	if not _clock_paused:
		wall_checkpoint_at = maxi(0, wall_now)
		_clock_paused = true


func resume_clock(wall_now: int, monotonic_ms: int) -> void:
	if _clock_paused:
		last_observed_at += clampi(wall_now - wall_checkpoint_at, 0, MAX_OFFLINE_SECONDS)
	start_clock(wall_now, monotonic_ms)


func is_ready(id: int, now: int) -> bool:
	var current := observe_time(now)
	for building: Dictionary in buildings:
		if building["id"] == id:
			return current - int(building["cycle_started_at"]) >= int(CATALOG[building["type"]]["seconds"])
	return false


func collect(id: int, now: int) -> bool:
	var current := observe_time(now)
	for building: Dictionary in buildings:
		if building["id"] != id:
			continue
		var definition: Dictionary = CATALOG[building["type"]]
		if current - int(building["cycle_started_at"]) < int(definition["seconds"]):
			return false
		coins += int(definition["income"])
		xp += int(definition["xp"])
		building["cycle_started_at"] = current
		return true
	return false


func purchase(type: String, x: int, y: int, now: int) -> bool:
	var current := observe_time(now)
	if not CATALOG.has(type) or x < 0 or y < 0 or x >= GRID_SIZE or y >= GRID_SIZE:
		return false
	var definition: Dictionary = CATALOG[type]
	if level() < int(definition["required_level"]) or coins < int(definition["cost"]):
		return false
	for building: Dictionary in buildings:
		if building["x"] == x and building["y"] == y:
			return false
	coins -= int(definition["cost"])
	buildings.append({"id": next_id, "type": type, "x": x, "y": y, "cycle_started_at": current})
	next_id += 1
	return true


func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"xp": xp,
		"buildings": buildings.duplicate(true),
		"last_observed_at": last_observed_at,
		"wall_checkpoint_at": wall_checkpoint_at,
		"next_id": next_id,
	}


static func _is_nonnegative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 0
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value >= 0 and value <= 9007199254740991.0 and floor(value) == value
	return false


static func from_data(data: Variant, now: int):
	if not data is Dictionary:
		return null
	for field in ["version", "coins", "xp", "last_observed_at", "next_id"]:
		if not data.has(field) or not _is_nonnegative_integer(data[field]):
			return null
	if int(data["version"]) != SAVE_VERSION or int(data["next_id"]) < 2:
		return null
	if data.has("wall_checkpoint_at") and not _is_nonnegative_integer(data["wall_checkpoint_at"]):
		return null
	if not data.has("buildings") or not data["buildings"] is Array:
		return null
	var saved_buildings: Array = data["buildings"]
	if saved_buildings.is_empty() or saved_buildings.size() > GRID_SIZE * GRID_SIZE:
		return null
	var seen_ids := {}
	var seen_cells := {}
	var checked_buildings: Array = []
	for item in saved_buildings:
		if not item is Dictionary or not item.has("type") or not item["type"] is String:
			return null
		if not CATALOG.has(item["type"]):
			return null
		var required_level: int = CATALOG[item["type"]]["required_level"]
		var saved_xp: int = int(data["xp"])
		var saved_level := 3 if saved_xp >= LEVEL_THREE_XP else (2 if saved_xp >= LEVEL_TWO_XP else 1)
		if required_level > saved_level:
			return null
		for field in ["id", "x", "y", "cycle_started_at"]:
			if not item.has(field) or not _is_nonnegative_integer(item[field]):
				return null
		var id := int(item["id"])
		var x := int(item["x"])
		var y := int(item["y"])
		var started := int(item["cycle_started_at"])
		var cell := Vector2i(x, y)
		if id <= 0 or id >= int(data["next_id"]) or x >= GRID_SIZE or y >= GRID_SIZE:
			return null
		if seen_ids.has(id) or seen_cells.has(cell) or started > int(data["last_observed_at"]):
			return null
		seen_ids[id] = true
		seen_cells[cell] = true
		checked_buildings.append({"id": id, "type": item["type"], "x": x, "y": y, "cycle_started_at": started})
	var result = load("res://scripts/economy.gd").new(int(data["last_observed_at"]))
	result.coins = int(data["coins"])
	result.xp = int(data["xp"])
	result.next_id = int(data["next_id"])
	result.buildings = checked_buildings
	var checkpoint := int(data.get("wall_checkpoint_at", data["last_observed_at"]))
	result.last_observed_at += clampi(now - checkpoint, 0, MAX_OFFLINE_SECONDS)
	result.wall_checkpoint_at = maxi(0, now)
	return result
