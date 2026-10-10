#============================================================================
# VocabularyTree.gd
# Skill-tree logic for the Lexicon's Vocabulary Trees (Design Doc 4.5,
# Technical Design Doc 2.4). A node is LOCKED until its prerequisites are
# purchased, AVAILABLE once they are, and PURCHASED after the player pays its
# Ink Drop cost. Tree content lives in data/lexicon/vocabulary_trees.json.
#
# All state lives in the `lexicon` Dictionary the caller passes in
# (GameState.lexicon in play, a fixture in tests):
#   lexicon.vocabulary_trees[tree_id] = { nodes_unlocked, nodes_purchased, total_invested }
# Only max_rank 1 is supported; a data file asking for more is warned about
# and treated as rank 1.
# Dependencies: LexiconData, InkDropManager, EventBus
# Events: vocabulary_node_purchased
#============================================================================

class_name VocabularyTree
extends RefCounted

enum NodeState { LOCKED, AVAILABLE, PURCHASED }

#----------------------------------------------------------------------------
# PUBLIC METHODS - queries
#----------------------------------------------------------------------------

## LOCKED, AVAILABLE or PURCHASED for [param node_id]. Unknown ids are LOCKED.
static func node_state(lexicon: Dictionary, node_id: String) -> int:
	var node := LexiconData.get_node_def(node_id)
	if node.is_empty():
		return NodeState.LOCKED
	if is_purchased(lexicon, node_id):
		return NodeState.PURCHASED
	return NodeState.AVAILABLE if prerequisites_met(lexicon, node) else NodeState.LOCKED

## True when [param node_id] has been bought.
static func is_purchased(lexicon: Dictionary, node_id: String) -> bool:
	var node := LexiconData.get_node_def(node_id)
	if node.is_empty():
		return false
	return _purchased_list(lexicon, String(node.tree_id)).has(node_id)

## True when every prerequisite of [param node] (a node Dictionary) is bought.
static func prerequisites_met(lexicon: Dictionary, node: Dictionary) -> bool:
	for prerequisite in node.get("prerequisites", []):
		if not is_purchased(lexicon, String(prerequisite)):
			return false
	return true

## True when every node in [param tree_id] has been bought.
static func is_tree_complete(lexicon: Dictionary, tree_id: String) -> bool:
	var tree := LexiconData.get_tree(tree_id)
	if tree.is_empty():
		return false
	for node in tree.get("nodes", []):
		if not is_purchased(lexicon, String(node.get("node_id", ""))):
			return false
	return true

## Every effect granted by the purchased nodes. Each entry is the node's
## effect Dictionary plus a `source` key naming the node.
static func effects(lexicon: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tree in LexiconData.get_trees():
		for node in tree.get("nodes", []):
			var node_id := String(node.get("node_id", ""))
			if not is_purchased(lexicon, node_id):
				continue
			for effect in node.get("effects", []):
				var entry: Dictionary = (effect as Dictionary).duplicate(true)
				entry["source"] = node_id
				out.append(entry)
	return out

#----------------------------------------------------------------------------
# PUBLIC METHODS - purchasing
#----------------------------------------------------------------------------

## Whether [param node_id] can be bought right now.
## Returns { ok: bool, reason: String } where reason is one of
## "" | "unknown_node" | "already_purchased" | "prerequisites" | "insufficient_ink".
static func can_purchase(lexicon: Dictionary, profile: Dictionary, node_id: String) -> Dictionary:
	var node := LexiconData.get_node_def(node_id)
	if node.is_empty():
		return { "ok": false, "reason": "unknown_node" }
	if is_purchased(lexicon, node_id):
		return { "ok": false, "reason": "already_purchased" }
	if not prerequisites_met(lexicon, node):
		return { "ok": false, "reason": "prerequisites" }
	if not InkDropManager.can_afford(profile, int(node.get("cost", 0))):
		return { "ok": false, "reason": "insufficient_ink" }
	return { "ok": true, "reason": "" }

## Buys [param node_id]: spends its cost, records the purchase and unlocks
## whatever it was gating. Returns { ok, reason, cost }; on failure nothing
## has changed.
static func purchase(lexicon: Dictionary, profile: Dictionary, node_id: String) -> Dictionary:
	var verdict := can_purchase(lexicon, profile, node_id)
	if not bool(verdict.ok):
		verdict["cost"] = 0
		return verdict

	var node := LexiconData.get_node_def(node_id)
	if int(node.get("max_rank", 1)) > 1:
		push_warning("VocabularyTree: %s asks for max_rank > 1, which is not supported; treating as 1" % node_id)

	var cost := int(node.get("cost", 0))
	if not InkDropManager.spend(profile, cost, node_id):
		return { "ok": false, "reason": "insufficient_ink", "cost": 0 }

	var tree_state := _tree_state(lexicon, String(node.tree_id))
	var purchased: Array = tree_state.nodes_purchased
	purchased.append(node_id)
	tree_state["total_invested"] = int(tree_state.get("total_invested", 0)) + cost
	refresh_unlocked(lexicon)

	EventBus.vocabulary_node_purchased.emit(String(node.tree_id), node_id)
	return { "ok": true, "reason": "", "cost": cost }

## Recomputes each tree's `nodes_unlocked` list: every purchased node plus
## every node whose prerequisites are all purchased. Called after any change
## to the purchased lists, so the two never drift.
static func refresh_unlocked(lexicon: Dictionary) -> void:
	for tree in LexiconData.get_trees():
		var tree_id := String(tree.get("tree_id", ""))
		var unlocked: Array = []
		for node in tree.get("nodes", []):
			var node_id := String(node.get("node_id", ""))
			if is_purchased(lexicon, node_id) or prerequisites_met(lexicon, node):
				unlocked.append(node_id)
		_tree_state(lexicon, tree_id)["nodes_unlocked"] = unlocked

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

## The mutable per-tree state Dictionary, created on first touch.
static func _tree_state(lexicon: Dictionary, tree_id: String) -> Dictionary:
	if not lexicon.has("vocabulary_trees"):
		lexicon["vocabulary_trees"] = {}
	var trees: Dictionary = lexicon["vocabulary_trees"]
	if not trees.has(tree_id):
		trees[tree_id] = { "nodes_unlocked": [], "nodes_purchased": [], "total_invested": 0 }
	return trees[tree_id]

static func _purchased_list(lexicon: Dictionary, tree_id: String) -> Array:
	var trees: Dictionary = lexicon.get("vocabulary_trees", {})
	return trees.get(tree_id, {}).get("nodes_purchased", [])
