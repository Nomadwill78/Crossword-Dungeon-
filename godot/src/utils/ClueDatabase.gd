#============================================================================
# ClueDatabase.gd
# Typed wrapper around clues_master.json (CLAUDE.md 4.3). Gameplay code asks
# this for clues instead of reaching into ConfigLoader and indexing raw JSON.
# Dependencies: ConfigLoader, Constants
# Events: none
#============================================================================

class_name ClueDatabase
extends RefCounted

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
static var _clues: Dictionary = {}
static var _by_length: Dictionary = {}
static var _initialized: bool = false

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Returns the clue with [param clue_id], or a safe fallback clue if the id is
## unknown (CLAUDE.md 5.3: an invalid clue id must never crash a run).
## The returned Dictionary is a deep copy - mutating it cannot corrupt the
## shared database.
static func get_clue(clue_id: String) -> Dictionary:
	_ensure_loaded()
	if not _clues.has(clue_id):
		push_warning("ClueDatabase: clue not found: %s" % clue_id)
		return get_fallback_clue()
	return _clues[clue_id].duplicate(true)

## Returns a random clue matching [param length], optionally filtered by
## [param category] and [param difficulty] (pass -1 for any difficulty).
## Falls back progressively (drop difficulty, then drop category, then the
## fallback clue) rather than returning an empty Dictionary.
static func get_random_clue(length: int, difficulty: int = -1, category: String = "") -> Dictionary:
	_ensure_loaded()
	var pool: Array = _by_length.get(length, [])

	var filtered := _filter(pool, difficulty, category)
	if filtered.is_empty() and category != "":
		filtered = _filter(pool, difficulty, "")
	if filtered.is_empty() and difficulty >= 0:
		filtered = _filter(pool, -1, "")
	if filtered.is_empty():
		push_warning("ClueDatabase: no clue of length %d" % length)
		return get_fallback_clue()

	return filtered[randi() % filtered.size()].duplicate(true)

## Every clue answer of the given length. Used by the grid generator and by
## tests that need to know what the content actually contains.
static func get_answers_of_length(length: int) -> Array:
	_ensure_loaded()
	var out: Array = []
	for clue in _by_length.get(length, []):
		out.append(clue.answer)
	return out

static func get_all_clues() -> Array:
	_ensure_loaded()
	return _clues.values().duplicate(true)

static func count() -> int:
	_ensure_loaded()
	return _clues.size()

## The clue used whenever a lookup fails. Deliberately trivial and always
## valid so a broken clue id degrades to a solvable encounter, not a crash.
static func get_fallback_clue() -> Dictionary:
	return {
		"id": "clue_fallback",
		"answer": "CAT",
		"length": 3,
		"answer_length": 3,
		"clue": "A common three-letter animal",
		"clue_text": "A common three-letter animal",
		"difficulty": 1,
		"category": "NATURE_ELEMENTS",
	}

## Drops the cache so the next call re-reads from disk. For tests/tools.
static func reset_cache() -> void:
	_clues.clear()
	_by_length.clear()
	_initialized = false

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _ensure_loaded() -> void:
	if _initialized:
		return
	_initialized = true

	var data: Dictionary = ConfigLoader.load_json(Constants.CLUES_PATH)
	var raw: Array = data.get("clues", [])
	if raw.is_empty():
		push_error("ClueDatabase: clues_master.json is empty or missing")
		return

	for clue in raw:
		var normalized := _normalize(clue)
		_clues[String(normalized.id)] = normalized
		var length: int = int(normalized.length)
		if not _by_length.has(length):
			_by_length[length] = []
		_by_length[length].append(normalized)

## The Technical Design Doc (2.2) names these fields `answer_length` and
## `clue_text`; clues_master.json stores them as `length` and `clue`.
## Rather than renaming stored keys (CLAUDE.md 9.5 forbids that without
## approval, and the grid generator already reads the stored names), every
## clue carries both spellings once it leaves this class.
static func _normalize(clue: Dictionary) -> Dictionary:
	var out: Dictionary = clue.duplicate(true)
	if not out.has("answer_length"):
		out["answer_length"] = int(out.get("length", String(out.get("answer", "")).length()))
	if not out.has("length"):
		out["length"] = int(out["answer_length"])
	if not out.has("clue_text"):
		out["clue_text"] = out.get("clue", "")
	if not out.has("clue"):
		out["clue"] = out.get("clue_text", "")
	return out

static func _filter(pool: Array, difficulty: int, category: String) -> Array:
	var out: Array = []
	for clue in pool:
		if difficulty >= 0 and int(clue.get("difficulty", 1)) != difficulty:
			continue
		if category != "" and String(clue.get("category", "")) != category:
			continue
		out.append(clue)
	return out
