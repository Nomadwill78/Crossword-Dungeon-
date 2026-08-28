## Autoload singleton. Atomic saves (write-to-temp-then-rename so a crash
## mid-write can't corrupt the save file) with rotating backups and schema
## version migration.
extends Node

const CURRENT_SCHEMA_VERSION := 1

func save_game() -> bool:
	var payload := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"player_profile": GameState.player_profile,
		"settings": GameState.settings,
		"statistics": GameState.statistics,
	}

	_rotate_backups()

	var tmp_path := Constants.SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open temp save file (error %s)" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()

	var dir := DirAccess.open(Constants.SAVE_PATH.get_base_dir())
	if dir == null:
		dir = DirAccess.open("user://")
	var tmp_name := tmp_path.get_file()
	var final_name := Constants.SAVE_PATH.get_file()
	var err := dir.rename(tmp_name, final_name)
	if err != OK:
		push_error("SaveManager: atomic rename failed (error %s)" % err)
		return false

	EventBus.save_completed.emit("default")
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(Constants.SAVE_PATH):
		return false

	var file := FileAccess.open(Constants.SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file is corrupt")
		return false

	var data: Dictionary = _migrate(parsed)

	GameState.player_profile = data.get("player_profile", GameState.player_profile)
	GameState.settings = data.get("settings", GameState.settings)
	GameState.statistics = data.get("statistics", GameState.statistics)

	EventBus.load_completed.emit("default")
	return true

func _migrate(data: Dictionary) -> Dictionary:
	var version: int = data.get("schema_version", 0)
	# Each step below should bring `data` from `version` to `version + 1`.
	# Add new branches here as the schema evolves; never mutate old branches.
	if version < 1:
		data["schema_version"] = 1
		version = 1
	return data

func _rotate_backups() -> void:
	if not FileAccess.file_exists(Constants.SAVE_PATH):
		return

	if not DirAccess.dir_exists_absolute(Constants.BACKUP_DIR):
		DirAccess.make_dir_recursive_absolute(Constants.BACKUP_DIR)

	var config := ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var max_backups: int = config.get("save", {}).get("max_backups", 5)

	var timestamp := Time.get_unix_time_from_system()
	var backup_path := "%sbackup_%d.json" % [Constants.BACKUP_DIR, int(timestamp)]

	var src := FileAccess.open(Constants.SAVE_PATH, FileAccess.READ)
	if src == null:
		return
	var content := src.get_as_text()
	src.close()

	var dst := FileAccess.open(backup_path, FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(content)
	dst.close()

	_prune_backups(max_backups)

func _prune_backups(max_backups: int) -> void:
	var dir := DirAccess.open(Constants.BACKUP_DIR)
	if dir == null:
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("backup_"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()

	files.sort()  # timestamps in the filename sort chronologically
	while files.size() > max_backups:
		var oldest: String = files.pop_front()
		dir.remove(oldest)
