class_name SaveManager
extends RefCounted

const EconomyScript = preload("res://scripts/economy.gd")
const DEFAULT_PATH := "user://idle_city_save.json"
const MAX_SAVE_BYTES := 1024 * 1024

var path: String
var last_error: String = ""
var recovered_from_backup: bool = false
var recovered_from_temporary: bool = false
var _unsafe_to_overwrite: bool = false


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")


func load_game(now: int):
	last_error = ""
	recovered_from_backup = false
	recovered_from_temporary = false
	_unsafe_to_overwrite = false
	if not exists():
		return null
	var game = _read_game(path, now)
	if game != null:
		return game
	game = _read_game(path + ".bak", now)
	if game != null:
		recovered_from_backup = true
		return game
	game = _read_game(path + ".tmp", now)
	if game != null:
		recovered_from_temporary = true
		return game
	last_error = "The saved city could not be read. Your existing save files were preserved."
	_unsafe_to_overwrite = true
	return null


func _read_game(source: String, now: int):
	if not FileAccess.file_exists(source):
		return null
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return null
	var contents := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(contents) != OK:
		return null
	return EconomyScript.from_data(json.data, now)


func save_game(game) -> bool:
	last_error = ""
	if _unsafe_to_overwrite:
		last_error = "The unreadable city has not been overwritten."
		return false
	var temporary := path + ".tmp"
	var primary := ProjectSettings.globalize_path(path)
	var backup := ProjectSettings.globalize_path(path + ".bak")
	var temp_absolute := ProjectSettings.globalize_path(temporary)
	# A complete staged save may be the only surviving copy after an interrupted
	# first write. Preserve it before opening the staging path for a new write.
	if recovered_from_temporary:
		if FileAccess.file_exists(path + ".bak") and DirAccess.remove_absolute(backup) != OK:
			last_error = "Could not preserve the recovered city."
			return false
		if DirAccess.copy_absolute(temp_absolute, backup) != OK:
			last_error = "Could not preserve the recovered city."
			return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the city save for writing."
		return false
	file.store_string(JSON.stringify(game.serialize()))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Could not finish writing the city save."
		return false
	if FileAccess.file_exists(path) and not recovered_from_backup and not recovered_from_temporary:
		if FileAccess.file_exists(path + ".bak") and DirAccess.remove_absolute(backup) != OK:
			last_error = "Could not replace the city backup."
			return false
		if DirAccess.copy_absolute(primary, backup) != OK:
			last_error = "Could not create a city backup."
			return false
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(primary) != OK:
		last_error = "Could not replace the city save."
		return false
	if DirAccess.rename_absolute(temp_absolute, primary) != OK:
		last_error = "Could not finish saving the city; the backup has been preserved."
		return false
	recovered_from_backup = false
	recovered_from_temporary = false
	return true
