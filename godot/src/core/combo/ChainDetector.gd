#============================================================================
# ChainDetector.gd
# Finds "Vocabulary Chains": runs of solved letters on the grid that spell a
# valid dictionary word (Design Doc 4.3, Technical Design Doc 3.3).
# Detection is pure - it never mutates the grid and never decides what a
# chain is worth. ChainEffects does that.
# Dependencies: ConfigLoader, Constants
# Events: none - the caller emits chain_detected for genuinely new chains
#============================================================================

class_name ChainDetector
extends RefCounted

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
static var _words: Dictionary = {}
static var _loaded: bool = false

## Prefix tree, built lazily on first is_valid_prefix() call. Detection itself
## only needs the flat word set, and building the trie over ~16k words is
## wasted startup cost for a feature (hints/autocomplete) that may never be
## used in a given session.
static var _trie_root: Dictionary = {}
static var _trie_built: bool = false

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Scans [param grid_state] and returns every chain currently spelled out by
## solved letters, horizontally and vertically.
##
## A chain is a maximal run of consecutive solved letter cells whose letters
## form a dictionary word and which is at least `chains.min_chain_length`
## long. Runs are bounded by black cells, unsolved cells, and the grid edge.
##
## [return] Array of Dictionaries: {id, word, cells, direction, length}
static func detect_chains(grid_state: Dictionary) -> Array:
	var size: int = int(grid_state.get("size", 0))
	if size <= 0:
		return []

	var lookup := _build_cell_lookup(grid_state)
	var min_length := _min_chain_length()
	var chains: Array = []

	for y in range(size):
		_scan_line(lookup, size, min_length, chains, "horizontal", y)
	for x in range(size):
		_scan_line(lookup, size, min_length, chains, "vertical", x)

	return chains

## True when [param word] is in the dictionary.
static func is_valid_word(word: String) -> bool:
	_ensure_loaded()
	return _words.has(word.strip_edges().to_upper())

## True when any dictionary word starts with [param prefix]. Builds the trie
## on first use. Intended for hint/autocomplete UI.
static func is_valid_prefix(prefix: String) -> bool:
	_ensure_trie_built()
	var node := _trie_root
	for ch in prefix.strip_edges().to_upper():
		if not node.has(ch):
			return false
		node = node[ch]
	return true

static func word_count() -> int:
	_ensure_loaded()
	return _words.size()

static func reset_cache() -> void:
	_words.clear()
	_trie_root.clear()
	_loaded = false
	_trie_built = false

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

## Walks one row or column, accumulating consecutive solved letters and
## emitting a chain wherever a completed run spells a real word.
static func _scan_line(
	lookup: Dictionary,
	size: int,
	min_length: int,
	chains: Array,
	direction: String,
	line_index: int
) -> void:
	var word := ""
	var cells: Array = []

	for i in range(size):
		var pos := Vector2i(i, line_index) if direction == "horizontal" else Vector2i(line_index, i)
		var cell: Dictionary = lookup.get(pos, {})
		var is_solved_letter: bool = (
			not cell.is_empty()
			and String(cell.get("type", "")) == "letter"
			and bool(cell.get("solved", false))
		)

		if is_solved_letter:
			word += String(cell.get("letter", ""))
			cells.append(pos)
		else:
			_emit_if_valid(chains, word, cells, direction, min_length)
			word = ""
			cells = []

	# A run that reaches the end of the line still counts.
	_emit_if_valid(chains, word, cells, direction, min_length)

static func _emit_if_valid(
	chains: Array,
	word: String,
	cells: Array,
	direction: String,
	min_length: int
) -> void:
	if word.length() < min_length or not is_valid_word(word):
		return
	chains.append({
		"id": _chain_id(word, cells, direction),
		"word": word,
		"cells": cells.duplicate(),
		"direction": direction,
		"length": word.length(),
	})

## Stable identity for a chain, so a caller can tell an already-activated
## chain from a new one across repeated detection passes.
static func _chain_id(word: String, cells: Array, direction: String) -> String:
	if cells.is_empty():
		return "%s_%s" % [direction, word]
	var first: Vector2i = cells[0]
	return "%s_%d_%d_%s" % [direction, first.x, first.y, word]

static func _build_cell_lookup(grid_state: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	for cell in grid_state.get("cells", []):
		lookup[Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))] = cell
	return lookup

static func _min_chain_length() -> int:
	var chains_cfg: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("chains", {})
	return int(chains_cfg.get("min_chain_length", 3))

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var data: Dictionary = ConfigLoader.load_json(Constants.DICTIONARY_PATH)
	var words: Array = data.get("words", [])
	if words.is_empty():
		push_error("ChainDetector: dictionary is empty or missing at %s" % Constants.DICTIONARY_PATH)
		return
	for word in words:
		_words[String(word).to_upper()] = true

static func _ensure_trie_built() -> void:
	if _trie_built:
		return
	_ensure_loaded()
	_trie_built = true
	for word in _words.keys():
		var node := _trie_root
		for ch in String(word):
			if not node.has(ch):
				node[ch] = {}
			node = node[ch]
		node["_end"] = true
