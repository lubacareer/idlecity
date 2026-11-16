class_name SaveManager
extends RefCounted

const EconomyScript = preload("res://scripts/economy.gd")
const DEFAULT_PATH := "user://idle_city_save.json"
const MAX_SAVE_BYTES := 1024 * 1024
const MAX_REVISION := 9007199254740990

var path: String
var last_error: String = ""
var recovered_from_backup: bool = false
var recovered_from_temporary: bool = false
var _unsafe_to_overwrite: bool = false
var _loaded: bool = false


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")


func load_game(now: int):
	last_error = ""
	recovered_from_backup = false
	recovered_from_temporary = false
	_unsafe_to_overwrite = false
	_loaded = true
	if not exists():
		return null
	var best := _best_candidate(now)
	if best.is_empty():
		last_error = "The saved city could not be read. Your existing save files were preserved."
		_unsafe_to_overwrite = true
		return null
	recovered_from_backup = best["source"] == ".bak"
	recovered_from_temporary = best["source"] == ".tmp"
	return best["game"]


func _read_candidate(suffix: String, now: int) -> Dictionary:
	var source := path + suffix
	if not FileAccess.file_exists(source):
		return {}
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return {}
	var contents := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(contents) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var legacy := not data.has("_save_revision")
	var revision: int = 0
	if not legacy:
		var value: Variant = data["_save_revision"]
		if not EconomyScript._is_nonnegative_integer(value) or value > MAX_REVISION:
			return {}
		revision = int(value)
	var game = EconomyScript.from_data(data, now)
	if game == null:
		return {}
	return {"source": suffix, "data": data, "game": game, "legacy": legacy, "revision": revision}


func _best_candidate(now: int) -> Dictionary:
	var best := {}
	# This order breaks revisioned ties; old, unversioned staged writes have
	# priority over old primary saves because they contain interrupted progress.
	for suffix in ["", ".tmp", ".bak"]:
		var candidate := _read_candidate(suffix, now)
		if candidate.is_empty():
			continue
		if best.is_empty() or candidate["revision"] > best["revision"]:
			best = candidate
		elif candidate["revision"] == best["revision"] and candidate["legacy"] and best["legacy"] and suffix == ".tmp":
			best = candidate
	return best


func _write_file(destination: String, contents: String) -> bool:
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the city save for writing."
		return false
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Could not finish writing the city save."
		return false
	return true


func _write_staged(contents: String) -> bool:
	return _write_file(path + ".tmp", contents)


func _promote_staged() -> bool:
	var temporary := ProjectSettings.globalize_path(path + ".tmp")
	var primary := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(temporary, primary) != OK:
		last_error = "Could not finish saving the city; the backup has been preserved."
		return false
	return true


func save_game(game) -> bool:
	last_error = ""
	# A new manager must inspect existing data before it can replace any files.
	if not _loaded:
		load_game(0)
	if _unsafe_to_overwrite:
		last_error = "The unreadable city has not been overwritten."
		return false
	var best := _best_candidate(0)
	var revision := 0
	if not best.is_empty():
		revision = int(best["revision"])
		if best["source"] != ".bak":
			# Secure the newest known good state before staging overwrites .tmp.
			# Upgrade legacy candidates to a revision so they remain newer than
			# a legacy primary after an interrupted retry or process restart.
			revision = maxi(1, revision)
			var backup_data: Dictionary = best["data"].duplicate(true)
			backup_data["_save_revision"] = revision
			if not _write_file(path + ".bak", JSON.stringify(backup_data)):
				last_error = "Could not preserve the recovered city. " + last_error
				return false
			recovered_from_temporary = false
			recovered_from_backup = true
	if revision >= MAX_REVISION:
		last_error = "The city save revision limit was reached."
		return false
	var data: Dictionary = game.serialize()
	data["_save_revision"] = revision + 1
	if not _write_staged(JSON.stringify(data)):
		return false
	if not _promote_staged():
		return false
	recovered_from_backup = false
	recovered_from_temporary = false
	return true
