#============================================================================
# LexiconData.gd
# Typed read access to the Lexicon's JSON content: vocabulary trees, tomes,
# achievements and the progression block of game_config.json (CLAUDE.md 4.3
# data-access pattern). Everything the meta-progression systems know about
# the game's content comes through here, so no tree, tome or level threshold
# is ever written into GDScript (CLAUDE.md 2.1).
# Dependencies: ConfigLoader, Constants
# Events: none
#============================================================================

class_name LexiconData
extends RefCounted

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
static var _node_index: Dictionary = {}
static var _tome_index: Dictionary = {}
static var _achievement_index: Dictionary = {}
static var _indexed: bool = false

#----------------------------------------------------------------------------
# PUBLIC METHODS - vocabulary trees
#----------------------------------------------------------------------------

## Every vocabulary tree, in file order. Each is a deep copy.
static func get_trees() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var trees: Dictionary = ConfigLoader.load_json(Constants.VOCABULARY_TREES_PATH).get("vocabulary_trees", {})
	for tree_id in trees:
		out.append((trees[tree_id] as Dictionary).duplicate(true))
	return out

## Tree ids in file order.
static func tree_ids() -> Array[String]:
	var out: Array[String] = []
	for tree in get_trees():
		out.append(String(tree.get("tree_id", "")))
	return out

## One tree by id, or an empty Dictionary if unknown.
static func get_tree(tree_id: String) -> Dictionary:
	var trees: Dictionary = ConfigLoader.load_json(Constants.VOCABULARY_TREES_PATH).get("vocabulary_trees", {})
	if not trees.has(tree_id):
		return {}
	return (trees[tree_id] as Dictionary).duplicate(true)

## One node by id, or an empty Dictionary if unknown. The copy gains `tree_id`
## and `category` keys so callers do not have to look the tree up again.
static func get_node_def(node_id: String) -> Dictionary:
	_ensure_indexed()
	if not _node_index.has(node_id):
		return {}
	return (_node_index[node_id] as Dictionary).duplicate(true)

#----------------------------------------------------------------------------
# PUBLIC METHODS - tomes
#----------------------------------------------------------------------------

## Every tome, in file order. Each is a deep copy.
static func get_tomes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tome in ConfigLoader.load_json(Constants.TOMES_PATH).get("tomes", []):
		out.append((tome as Dictionary).duplicate(true))
	return out

## One tome by id, or an empty Dictionary if unknown.
static func get_tome(tome_id: String) -> Dictionary:
	_ensure_indexed()
	if not _tome_index.has(tome_id):
		return {}
	return (_tome_index[tome_id] as Dictionary).duplicate(true)

#----------------------------------------------------------------------------
# PUBLIC METHODS - achievements and progression
#----------------------------------------------------------------------------

## Every achievement, in file order. Each is a deep copy.
static func get_achievements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for achievement in ConfigLoader.load_json(Constants.ACHIEVEMENTS_PATH).get("achievements", []):
		out.append((achievement as Dictionary).duplicate(true))
	return out

## One achievement by id, or an empty Dictionary if unknown.
static func get_achievement(achievement_id: String) -> Dictionary:
	_ensure_indexed()
	if not _achievement_index.has(achievement_id):
		return {}
	return (_achievement_index[achievement_id] as Dictionary).duplicate(true)

## The `progression` block of game_config.json (level curve, unlocks, slots).
static func progression() -> Dictionary:
	return ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("progression", {})

## How many tome slots the player has.
static func tome_slot_count() -> int:
	return maxi(1, int(progression().get("tome_slots", 3)))

## Drops the lookup indexes. Tests call this after swapping data around.
static func reset_cache() -> void:
	_node_index.clear()
	_tome_index.clear()
	_achievement_index.clear()
	_indexed = false

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _ensure_indexed() -> void:
	if _indexed:
		return
	_node_index.clear()
	_tome_index.clear()
	_achievement_index.clear()

	for tree in get_trees():
		for node in tree.get("nodes", []):
			var entry: Dictionary = (node as Dictionary).duplicate(true)
			entry["tree_id"] = String(tree.get("tree_id", ""))
			entry["category"] = String(tree.get("category", ""))
			_node_index[String(entry.get("node_id", ""))] = entry

	for tome in get_tomes():
		_tome_index[String(tome.get("tome_id", ""))] = tome

	for achievement in get_achievements():
		_achievement_index[String(achievement.get("achievement_id", ""))] = achievement

	_indexed = true
