#============================================================================
# LexiconState.gd
# Builds and repairs the `lexicon` Dictionary that GameState holds and
# SaveManager persists (Technical Design Doc 2.1). `normalize` is the single
# gate a loaded save goes through, so a save from an older build - or one
# whose data has since lost a tome or tree node - can never leave the game
# holding an id it cannot resolve (CLAUDE.md 5.3: corrupted/outdated saves
# degrade, they do not crash).
# Dependencies: LexiconData, VocabularyTree
# Events: none
#============================================================================

class_name LexiconState
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## A brand-new lexicon: nothing bought, all slots empty, achievements unearned.
static func default_state() -> Dictionary:
	var trees := {}
	for tree_id in LexiconData.tree_ids():
		trees[tree_id] = { "nodes_unlocked": [], "nodes_purchased": [], "total_invested": 0 }

	var slots: Array = []
	for i in range(LexiconData.tome_slot_count()):
		slots.append(null)

	var achievements := {}
	for achievement in LexiconData.get_achievements():
		achievements[String(achievement.get("achievement_id", ""))] = false

	var state := {
		"vocabulary_trees": trees,
		"equipped_tomes": slots,
		"unlocked_tomes": [],
		"unlocked_themes": ["default"],
		"active_theme": "default",
		"achievements": achievements,
	}
	VocabularyTree.refresh_unlocked(state)
	return state

## Returns a clean lexicon built from [param raw] (typically parsed straight
## from a save file). Unknown node, tome and achievement ids are dropped,
## duplicates removed, an equipped tome must be an owned one, the slot count
## follows the current config, and numbers JSON parsed as floats come back as
## ints. Anything missing falls back to the default.
static func normalize(raw: Dictionary) -> Dictionary:
	var state := default_state()

	var raw_trees: Dictionary = raw.get("vocabulary_trees", {}) if typeof(raw.get("vocabulary_trees", null)) == TYPE_DICTIONARY else {}
	for tree_id in state.vocabulary_trees:
		var raw_tree: Dictionary = raw_trees.get(tree_id, {}) if typeof(raw_trees.get(tree_id, null)) == TYPE_DICTIONARY else {}
		var purchased: Array = []
		var invested := 0
		for node_id in _as_array(raw_tree.get("nodes_purchased", [])):
			var id := String(node_id)
			var node := LexiconData.get_node_def(id)
			if node.is_empty() or String(node.tree_id) != String(tree_id) or purchased.has(id):
				continue
			purchased.append(id)
			invested += int(node.get("cost", 0))
		state.vocabulary_trees[tree_id]["nodes_purchased"] = purchased
		state.vocabulary_trees[tree_id]["total_invested"] = invested

	var owned: Array = []
	for tome_id in _as_array(raw.get("unlocked_tomes", [])):
		var id := String(tome_id)
		if not LexiconData.get_tome(id).is_empty() and not owned.has(id):
			owned.append(id)
	state["unlocked_tomes"] = owned

	var raw_slots := _as_array(raw.get("equipped_tomes", []))
	var slots: Array = state["equipped_tomes"]
	var used: Array = []
	for i in range(mini(slots.size(), raw_slots.size())):
		if raw_slots[i] == null:
			continue
		var id := String(raw_slots[i])
		if owned.has(id) and not used.has(id):
			slots[i] = id
			used.append(id)

	var themes: Array = []
	for theme in _as_array(raw.get("unlocked_themes", [])):
		if typeof(theme) == TYPE_STRING and not themes.has(theme):
			themes.append(theme)
	if not themes.has("default"):
		themes.push_front("default")
	state["unlocked_themes"] = themes
	var active := String(raw.get("active_theme", "default"))
	state["active_theme"] = active if themes.has(active) else "default"

	var raw_achievements: Dictionary = raw.get("achievements", {}) if typeof(raw.get("achievements", null)) == TYPE_DICTIONARY else {}
	for achievement_id in state.achievements:
		state.achievements[achievement_id] = bool(raw_achievements.get(achievement_id, false))

	VocabularyTree.refresh_unlocked(state)
	return state

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _as_array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
