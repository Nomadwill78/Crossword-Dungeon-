## Autoload singleton. Atomic saves (write-to-temp-then-rename so a crash
## mid-write can't corrupt the save file) with rotating backups and schema
## version migration.
extends Node

const CURRENT_SCHEMA_VERSION := 1

## Where the save lives. Public so tests can point the manager at a scratch
## location instead of the player's real save.
var save_path: String = Constants.SAVE_PATH
var backup_dir: String = Constants.BACKUP_DIR

func _ready() -> void:
	# Pick up the player's progress on boot. A missing save is a fresh install.
	load_game()

func save_game() -> bool:
	var payload := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"player_profile": GameState.player_profile,
		"lexicon": GameState.get_lexicon(),
		"settings": GameState.settings,
		"statistics": GameState.statistics,
	}

	_rotate_backups()

	var tmp_path := save_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open temp save file (error %s)" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()

	var dir := DirAccess.open(save_path.get_base_dir())
	if dir == null:
		dir = DirAccess.open("user://")
	var tmp_name := tmp_path.get_file()
	var final_name := save_path.get_file()
	var err := dir.rename(tmp_name, final_name)
	if err != OK:
		push_error("SaveManager: atomic rename failed (error %s)" % err)
		return false

	EventBus.save_completed.emit("default")
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file is corrupt")
		return false

	var data: Dictionary = _migrate(parsed)

	# Merge over pristine defaults rather than replacing wholesale, so a save
	# written before a key existed (the lexicon, player_level, ...) still
	# loads with that key defaulted instead of missing.
	GameState.player_profile = merge_with_defaults(GameState.default_profile(), _as_dict(data.get("player_profile", {})))
	GameState.settings = merge_with_defaults(GameState.default_settings(), _as_dict(data.get("settings", {})))
	GameState.statistics = merge_with_defaults(GameState.default_statistics(), _as_dict(data.get("statistics", {})))
	GameState.lexicon = LexiconState.normalize(_as_dict(data.get("lexicon", {})))
	_repair_progression(GameState.player_profile)

	EventBus.load_completed.emit("default")
	return true

## Returns [param loaded] laid over [param defaults]: every key in the
## defaults is present in the result, loaded values win where their type is
## compatible, and numbers are coerced to the default's int/float type (JSON
## parses every number as a float). Keys the defaults do not know about -
## e.g. the per-length counters in statistics - are kept, with whole-number
## floats turned back into ints.
func merge_with_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var merged := {}
	for key in defaults:
		var default_value = defaults[key]
		if not loaded.has(key):
			merged[key] = _deep_copy(default_value)
			continue
		var loaded_value = loaded[key]
		match typeof(default_value):
			TYPE_DICTIONARY:
				if typeof(loaded_value) == TYPE_DICTIONARY:
					merged[key] = merge_with_defaults(default_value, loaded_value)
				else:
					merged[key] = _deep_copy(default_value)
			TYPE_INT:
				merged[key] = int(loaded_value) if _is_number(loaded_value) else default_value
			TYPE_FLOAT:
				merged[key] = float(loaded_value) if _is_number(loaded_value) else default_value
			TYPE_ARRAY:
				merged[key] = _loosen(loaded_value) if typeof(loaded_value) == TYPE_ARRAY else _deep_copy(default_value)
			_:
				merged[key] = loaded_value if typeof(loaded_value) == typeof(default_value) else default_value
	for key in loaded:
		if not defaults.has(key):
			merged[key] = _loosen(loaded[key])
	return merged

func _migrate(data: Dictionary) -> Dictionary:
	var version: int = data.get("schema_version", 0)
	# Each step below should bring `data` from `version` to `version + 1`.
	# Add new branches here as the schema evolves; never mutate old branches.
	if version < 1:
		data["schema_version"] = 1
		version = 1
	return data

func _rotate_backups() -> void:
	if not FileAccess.file_exists(save_path):
		return

	if not DirAccess.dir_exists_absolute(backup_dir):
		DirAccess.make_dir_recursive_absolute(backup_dir)

	var config := ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var max_backups: int = config.get("save", {}).get("max_backups", 5)

	var timestamp := Time.get_unix_time_from_system()
	var backup_path := "%sbackup_%d.json" % [backup_dir, int(timestamp)]

	var src := FileAccess.open(save_path, FileAccess.READ)
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
	var dir := DirAccess.open(backup_dir)
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

## A save can hold a player_level that disagrees with its own lifetime Ink -
## hand-edited, or written under a different level curve. Level is derived
## from lifetime Ink, but never lowered (a retune must not demote anyone),
## and a balance can never exceed what was ever collected.
func _repair_progression(profile: Dictionary) -> void:
	var lifetime := maxi(0, int(profile.get("total_ink_drops", 0)))
	profile["total_ink_drops"] = lifetime
	profile["ink_drops"] = clampi(int(profile.get("ink_drops", 0)), 0, lifetime)
	profile["player_level"] = maxi(
		clampi(int(profile.get("player_level", 1)), 1, PlayerLevel.max_level()),
		PlayerLevel.level_for_ink(lifetime)
	)

func _as_dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}

func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _deep_copy(value):
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	return value

## Recursively turns whole-number floats (how JSON hands back ints) into ints.
func _loosen(value):
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if is_equal_approx(value, floorf(value)) and absf(value) < 9.0e15 else value
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_loosen(item))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = _loosen(value[key])
			return out
	return value
