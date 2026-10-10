#============================================================================
# test_vocabulary_tree.gd
# Vocabulary Tree purchasing: prerequisites, costs, ledger interaction and
# the nodes_unlocked / nodes_purchased bookkeeping.
#============================================================================

class_name TestVocabularyTree
extends TestSuite

func _init() -> void:
	suite_name = "VocabularyTree"

func run(_host: Node) -> void:
	_test_initial_state()
	_test_purchase_flow()
	_test_failures()
	_test_effects_and_completion()
	_test_signal()

func _fresh() -> Dictionary:
	return LexiconState.default_state()

func _rich_profile() -> Dictionary:
	var profile := GameState.default_profile()
	InkDropManager.award(profile, 10000, "test")
	return profile

func _test_initial_state() -> void:
	var lexicon := _fresh()
	assert_eq(VocabularyTree.node_state(lexicon, "bst_01"), VocabularyTree.NodeState.AVAILABLE, "a root node starts available")
	assert_eq(VocabularyTree.node_state(lexicon, "bst_02"), VocabularyTree.NodeState.LOCKED, "a gated node starts locked")
	assert_eq(VocabularyTree.node_state(lexicon, "nope"), VocabularyTree.NodeState.LOCKED, "an unknown node reads as locked")
	assert_false(VocabularyTree.is_purchased(lexicon, "bst_01"), "nothing starts purchased")

	var unlocked: Array = lexicon.vocabulary_trees.bestiary.nodes_unlocked
	assert_eq(unlocked, ["bst_01"], "only the root is in nodes_unlocked at the start")
	assert_eq(VocabularyTree.effects(lexicon).size(), 0, "an empty lexicon grants no effects")

func _test_purchase_flow() -> void:
	var lexicon := _fresh()
	var profile := _rich_profile()
	var lifetime := int(profile.total_ink_drops)
	var cost := int(LexiconData.get_node_def("bst_01").cost)

	var verdict := VocabularyTree.can_purchase(lexicon, profile, "bst_01")
	assert_true(bool(verdict.ok), "an affordable root node can be bought")

	var bought := VocabularyTree.purchase(lexicon, profile, "bst_01")
	assert_true(bool(bought.ok), "purchase succeeds")
	assert_eq(int(bought.cost), cost, "purchase reports the price paid")
	assert_eq(int(profile.ink_drops), 10000 - cost, "purchase spends the node's cost")
	assert_eq(int(profile.total_ink_drops), lifetime, "buying never lowers lifetime Ink")
	assert_eq(VocabularyTree.node_state(lexicon, "bst_01"), VocabularyTree.NodeState.PURCHASED, "the node reads as purchased")
	assert_eq(VocabularyTree.node_state(lexicon, "bst_02"), VocabularyTree.NodeState.AVAILABLE, "its dependent unlocks")
	assert_eq(VocabularyTree.node_state(lexicon, "bst_03"), VocabularyTree.NodeState.LOCKED, "and nothing further down")
	assert_eq(int(lexicon.vocabulary_trees.bestiary.total_invested), cost, "total_invested tracks spending")

	var unlocked: Array = lexicon.vocabulary_trees.bestiary.nodes_unlocked
	assert_true(unlocked.has("bst_01") and unlocked.has("bst_02") and not unlocked.has("bst_03"), "nodes_unlocked holds purchased nodes plus the newly reachable one")

	# Trees are independent.
	assert_eq(VocabularyTree.node_state(lexicon, "arc_02"), VocabularyTree.NodeState.LOCKED, "other trees are untouched")
	assert_eq(int(lexicon.vocabulary_trees.arcana.total_invested), 0, "other trees record no spending")

func _test_failures() -> void:
	var lexicon := _fresh()
	var profile := _rich_profile()
	var balance := int(profile.ink_drops)

	var gated := VocabularyTree.purchase(lexicon, profile, "bst_02")
	assert_false(bool(gated.ok), "a node cannot be bought before its prerequisite")
	assert_eq(String(gated.reason), "prerequisites", "the reason names the prerequisite gate")

	var unknown := VocabularyTree.purchase(lexicon, profile, "zzz_99")
	assert_eq(String(unknown.reason), "unknown_node", "an unknown id is rejected")
	assert_eq(int(profile.ink_drops), balance, "failed purchases cost nothing")

	VocabularyTree.purchase(lexicon, profile, "bst_01")
	var after_first := int(profile.ink_drops)
	var twice := VocabularyTree.purchase(lexicon, profile, "bst_01")
	assert_eq(String(twice.reason), "already_purchased", "a node cannot be bought twice")
	assert_eq(int(profile.ink_drops), after_first, "and is not charged twice")
	assert_eq((lexicon.vocabulary_trees.bestiary.nodes_purchased as Array).size(), 1, "and is not listed twice")

	var poor := GameState.default_profile()
	InkDropManager.award(poor, int(LexiconData.get_node_def("arc_01").cost) - 1, "test")
	var broke := VocabularyTree.purchase(lexicon, poor, "arc_01")
	assert_eq(String(broke.reason), "insufficient_ink", "one Ink short is refused")
	assert_false(VocabularyTree.is_purchased(lexicon, "arc_01"), "and nothing is granted")
	assert_eq(int(poor.ink_drops), int(LexiconData.get_node_def("arc_01").cost) - 1, "and nothing is taken")

func _test_effects_and_completion() -> void:
	var lexicon := _fresh()
	var profile := _rich_profile()

	VocabularyTree.purchase(lexicon, profile, "wld_01")
	var effects := VocabularyTree.effects(lexicon)
	assert_eq(effects.size(), 1, "one purchased node, one effect")
	assert_eq(String(effects[0].type), "damage_multiplier", "the effect is the node's")
	assert_eq(String(effects[0].source), "wld_01", "each effect names its source node")

	assert_false(VocabularyTree.is_tree_complete(lexicon, "wilds"), "a partly bought tree is not complete")
	VocabularyTree.purchase(lexicon, profile, "wld_02")
	VocabularyTree.purchase(lexicon, profile, "wld_03")
	assert_true(VocabularyTree.is_tree_complete(lexicon, "wilds"), "buying every node completes the tree")
	assert_false(VocabularyTree.is_tree_complete(lexicon, "arcana"), "other trees stay incomplete")
	assert_false(VocabularyTree.is_tree_complete(lexicon, "nope"), "an unknown tree is never complete")
	assert_eq(VocabularyTree.effects(lexicon).size(), 3, "all three nodes contribute")

func _test_signal() -> void:
	var lexicon := _fresh()
	var profile := _rich_profile()
	var seen: Array = []
	var handler := func(tree_id: String, node_id: String): seen.append([tree_id, node_id])
	EventBus.vocabulary_node_purchased.connect(handler)

	VocabularyTree.purchase(lexicon, profile, "sen_02")
	assert_eq(seen.size(), 0, "a refused purchase emits nothing")
	VocabularyTree.purchase(lexicon, profile, "sen_01")
	assert_eq(seen, [["sentiment", "sen_01"]], "a purchase emits vocabulary_node_purchased once")

	EventBus.vocabulary_node_purchased.disconnect(handler)
