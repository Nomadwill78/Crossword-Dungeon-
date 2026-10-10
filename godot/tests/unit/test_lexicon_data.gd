#============================================================================
# test_lexicon_data.gd
# Data-integrity checks for the Lexicon's JSON content. These guard the data
# files themselves (CLAUDE.md 2.1: content lives in JSON, so a typo there is
# the likeliest way for Milestone 3 to break): ids resolve, prerequisite
# graphs are acyclic, every effect is one the game knows how to apply, and
# each description states the number its effect actually uses.
#============================================================================

class_name TestLexiconData
extends TestSuite

const NODE_EFFECT_TYPES: Array[String] = [
	"damage_multiplier", "timer_bonus", "heal_on_solve", "ink_bonus",
	"chain_duration", "chain_bonus", "damage_reduction",
]
const CATEGORY_EFFECT_TYPES: Array[String] = [
	"damage_multiplier", "timer_bonus", "heal_on_solve", "ink_bonus",
]
const TOME_EFFECT_TYPES: Array[String] = [
	"post_combat_heal", "first_attempt_bonus", "damage_bonus", "timer_bonus",
	"ink_multiplier", "max_hp_bonus", "damage_reduction",
]
const RARITIES: Array[String] = ["common", "uncommon", "rare"]
const CONDITION_TYPES: Array[String] = [
	"stat_at_least", "run_completed_faster_than", "tree_fully_purchased", "player_level",
]
## Levels Design Doc 5.2 requires an unlock at.
const REQUIRED_UNLOCK_LEVELS: Array[int] = [5, 10, 15, 20, 25, 30, 40, 50]

func _init() -> void:
	suite_name = "LexiconData"

func run(_host: Node) -> void:
	LexiconData.reset_cache()
	_test_trees()
	_test_tomes()
	_test_achievements()
	_test_progression()
	_test_lookups()

func _test_trees() -> void:
	var trees := LexiconData.get_trees()
	assert_eq(trees.size(), Constants.CATEGORIES.size(), "one vocabulary tree per clue category")

	var seen_categories: Array[String] = []
	var seen_nodes: Dictionary = {}
	var total_nodes := 0
	for tree in trees:
		var tree_id := String(tree.get("tree_id", ""))
		var category := String(tree.get("category", ""))
		assert_true(Constants.CATEGORIES.has(category), "%s targets a real clue category (%s)" % [tree_id, category])
		assert_false(seen_categories.has(category), "%s: no two trees share a category" % tree_id)
		seen_categories.append(category)
		assert_true(String(tree.get("tree_color", "")).begins_with("#"), "%s has a tree_color" % tree_id)

		for node in tree.get("nodes", []):
			total_nodes += 1
			var node_id := String(node.get("node_id", ""))
			assert_false(seen_nodes.has(node_id), "node id %s is unique" % node_id)
			seen_nodes[node_id] = true
			assert_gt(float(node.get("cost", 0)), 0.0, "%s has a positive cost" % node_id)
			assert_eq(int(node.get("max_rank", 1)), 1, "%s: only max_rank 1 is supported" % node_id)
			assert_false((node.get("effects", []) as Array).is_empty(), "%s has at least one effect" % node_id)
			for effect in node.get("effects", []):
				var type := String(effect.get("type", ""))
				assert_true(NODE_EFFECT_TYPES.has(type), "%s uses a known effect type (%s)" % [node_id, type])
				if CATEGORY_EFFECT_TYPES.has(type):
					assert_eq(String(effect.get("category", "")), category, "%s's effect targets its own tree's category" % node_id)
				_assert_description_matches(node_id, String(node.get("description", "")), effect, true)

	assert_eq(total_nodes, 20, "Design Doc 5.3: 20 vocabulary nodes at launch")

	# Prerequisites must exist and the graph must be acyclic.
	for tree in trees:
		for node in tree.get("nodes", []):
			for prerequisite in node.get("prerequisites", []):
				assert_true(seen_nodes.has(String(prerequisite)), "%s's prerequisite %s exists" % [node.get("node_id", ""), prerequisite])
		assert_true(_is_acyclic(tree), "%s prerequisites form no cycle" % tree.get("tree_id", ""))
		var roots := 0
		for node in tree.get("nodes", []):
			if (node.get("prerequisites", []) as Array).is_empty():
				roots += 1
		assert_gt(roots, 0, "%s has a purchasable root node" % tree.get("tree_id", ""))

func _test_tomes() -> void:
	var seen: Dictionary = {}
	var tomes := LexiconData.get_tomes()
	assert_gt(tomes.size(), 0, "tomes exist")
	for tome in tomes:
		var tome_id := String(tome.get("tome_id", ""))
		assert_false(seen.has(tome_id), "tome id %s is unique" % tome_id)
		seen[tome_id] = true
		assert_true(RARITIES.has(String(tome.get("rarity", ""))), "%s has a known rarity" % tome_id)
		assert_gt(float(tome.get("cost", 0)), 0.0, "%s has a positive cost" % tome_id)
		assert_false((tome.get("effects", []) as Array).is_empty(), "%s has an effect" % tome_id)
		for effect in tome.get("effects", []):
			var type := String(effect.get("type", ""))
			assert_true(TOME_EFFECT_TYPES.has(type), "%s uses a known effect type (%s)" % [tome_id, type])
			_assert_description_matches(tome_id, String(tome.get("description", "")), effect, false)

		var condition: Dictionary = tome.get("unlock_condition", {})
		var condition_type := String(condition.get("type", ""))
		assert_true(["player_level", "achievement"].has(condition_type), "%s has a known unlock condition (%s)" % [tome_id, condition_type])
		if condition_type == "achievement":
			assert_false(LexiconData.get_achievement(String(condition.get("value", ""))).is_empty(), "%s unlocks by an achievement that exists" % tome_id)
		elif condition_type == "player_level":
			assert_between(float(condition.get("value", 0)), 1.0, float(PlayerLevel.max_level()), "%s unlock level is within 1..max" % tome_id)

func _test_achievements() -> void:
	var seen: Dictionary = {}
	var achievements := LexiconData.get_achievements()
	assert_gt(achievements.size(), 0, "achievements exist")
	for achievement in achievements:
		var id := String(achievement.get("achievement_id", ""))
		assert_false(seen.has(id), "achievement id %s is unique" % id)
		seen[id] = true
		assert_true(CONDITION_TYPES.has(String(achievement.get("condition", {}).get("type", ""))), "%s has a known condition type" % id)
		assert_true(int(achievement.get("reward_ink", -1)) >= 0, "%s has a non-negative reward" % id)
	for required in ["first_run", "first_chain", "speed_demon", "vocabulary_master", "grandmaster"]:
		assert_true(seen.has(required), "Technical Design Doc 2.1 achievement %s exists" % required)

func _test_progression() -> void:
	assert_eq(PlayerLevel.max_level(), 50, "Design Doc 5.2: level cap is 50")
	assert_eq(LexiconData.tome_slot_count(), 3, "Design Doc 4.5: three tome slots")

	var levels: Array[int] = []
	var ids: Dictionary = {}
	for entry in PlayerLevel.unlocks():
		levels.append(int(entry.get("level", 0)))
		assert_false(ids.has(String(entry.get("unlock_id", ""))), "unlock id %s is unique" % entry.get("unlock_id", ""))
		ids[String(entry.get("unlock_id", ""))] = true
		assert_between(float(entry.get("level", 0)), 2.0, float(PlayerLevel.max_level()), "unlock %s is within the level range" % entry.get("unlock_id", ""))
	for required in REQUIRED_UNLOCK_LEVELS:
		assert_true(levels.has(required), "Design Doc 5.2 unlock at level %d is configured" % required)

	var gates: Dictionary = LexiconData.progression().get("grid_size_unlocks", {})
	for size in gates:
		var gate := String(gates[size])
		assert_true(gate == "" or ids.has(gate), "grid size %s is gated by a real unlock (%s)" % [size, gate])

func _test_lookups() -> void:
	assert_true(LexiconData.get_node_def("nope_00").is_empty(), "unknown node -> empty")
	assert_true(LexiconData.get_tome("tome_nope").is_empty(), "unknown tome -> empty")
	assert_true(LexiconData.get_tree("nope").is_empty(), "unknown tree -> empty")
	assert_true(LexiconData.get_achievement("nope").is_empty(), "unknown achievement -> empty")

	var node := LexiconData.get_node_def("bst_01")
	assert_eq(String(node.get("tree_id", "")), "bestiary", "get_node_def adds tree_id")
	assert_eq(String(node.get("category", "")), "FANTASY_CREATURES", "get_node_def adds category")

	# The lookup hands out copies: scribbling on one must not corrupt the data.
	node["cost"] = -999
	assert_ne(int(LexiconData.get_node_def("bst_01").get("cost", 0)), -999, "get_node_def returns a copy")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------

## A description must state the number its effect really uses, so the UI
## text and the maths cannot drift apart when one is edited without the other.
func _assert_description_matches(owner_id: String, description: String, effect: Dictionary, is_node: bool) -> void:
	var regex := RegEx.new()
	regex.compile("\\d+")
	var found := regex.search(description)
	if found == null:
		_fail("%s: description '%s' states no number" % [owner_id, description])
		return
	var stated := int(found.get_string())

	var value := float(effect.get("value", 0))
	var expected := int(round(value))
	match String(effect.get("type", "")):
		"damage_multiplier", "first_attempt_bonus", "damage_bonus", "ink_multiplier":
			expected = int(round((value - 1.0) * 100.0))
		"damage_reduction", "post_combat_heal":
			expected = int(round(value * 100.0))
	assert_eq(stated, expected, "%s: description '%s' matches its effect value %s" % [owner_id, description, str(value)])

## Kahn's algorithm: a tree is acyclic if every node can be peeled off in
## dependency order.
func _is_acyclic(tree: Dictionary) -> bool:
	var remaining: Dictionary = {}
	for node in tree.get("nodes", []):
		remaining[String(node.get("node_id", ""))] = (node.get("prerequisites", []) as Array).duplicate()
	var progressed := true
	while progressed and not remaining.is_empty():
		progressed = false
		for node_id in remaining.keys():
			var unmet := false
			for prerequisite in remaining[node_id]:
				if remaining.has(String(prerequisite)):
					unmet = true
					break
			if not unmet:
				remaining.erase(node_id)
				progressed = true
	return remaining.is_empty()
