## Autoload singleton. Loads and caches JSON data files (clues, enemies,
## grid presets, game config) so repeated lookups don't hit disk again.
extends Node

var _cache: Dictionary = {}

func load_json(path: String, use_cache: bool = true) -> Dictionary:
	if use_cache and _cache.has(path):
		return _cache[path]

	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: failed to open %s (error %s)" % [path, FileAccess.get_open_error()])
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ConfigLoader: %s did not parse to a Dictionary" % path)
		return {}

	if use_cache:
		_cache[path] = parsed
	return parsed

func save_json(path: String, data: Dictionary) -> bool:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ConfigLoader: failed to write %s (error %s)" % [path, FileAccess.get_open_error()])
		return false

	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_cache[path] = data
	return true

func clear_cache(path: String = "") -> void:
	if path == "":
		_cache.clear()
	else:
		_cache.erase(path)
