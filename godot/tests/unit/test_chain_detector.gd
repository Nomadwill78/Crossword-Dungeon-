#============================================================================
# test_chain_detector.gd
# Unit tests for chain detection and the tiered chain rewards
# (Design Doc 4.3, Technical Design Doc 3.3).
#============================================================================

class_name TestChainDetector
extends TestSuite

func _init() -> void:
	suite_name = "ChainDetector"

func run(_host: Node) -> void:
	test_dictionary_loaded()
	test_dictionary_covers_every_clue_answer()
	test_detects_horizontal_chain()
	test_detects_vertical_chain()
	test_ignores_unsolved_letters()
	test_ignores_non_words()
	test_ignores_runs_below_minimum_length()
	test_run_is_bounded_by_black_cells()
	test_chain_ids_are_stable_and_distinct()
	test_valid_prefix_lookup()
	test_effect_tiers_match_design_doc()
	test_effect_applies_heal()
	test_effect_applies_damage_buff()
	test_grid_scoped_effects_are_deferred()
	test_buffs_expire_after_their_encounter_count()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func test_dictionary_loaded() -> void:
	assert_gt(ChainDetector.word_count(), 10000, "Dictionary has a usable number of words")
	assert_true(ChainDetector.is_valid_word("DRAGON"), "DRAGON is a word")
	assert_true(ChainDetector.is_valid_word("dragon"), "Lookup is case insensitive")
	assert_false(ChainDetector.is_valid_word("ZZQX"), "ZZQX is not a word")

## The chain dictionary must be a superset of the clue answers, or the game
## would refuse to recognise its own solved words as chains.
func test_dictionary_covers_every_clue_answer() -> void:
	var missing: Array[String] = []
	for clue in ClueDatabase.get_all_clues():
		var answer := String(clue.answer)
		if not ChainDetector.is_valid_word(answer):
			missing.append(answer)
	assert_eq(missing.size(), 0, "Every clue answer is in the chain dictionary (missing: %s)" % str(missing))

func test_detects_horizontal_chain() -> void:
	var grid := _grid(5, [
		["C", "A", "T", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
	])
	var chains := ChainDetector.detect_chains(grid)
	assert_eq(chains.size(), 1, "One chain found")
	assert_eq(chains[0].word, "CAT", "Chain word is CAT")
	assert_eq(chains[0].direction, "horizontal", "Chain is horizontal")
	assert_eq(chains[0].cells.size(), 3, "Chain covers 3 cells")

func test_detects_vertical_chain() -> void:
	var grid := _grid(5, [
		["C", "", "", "", ""],
		["A", "", "", "", ""],
		["T", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
	])
	var chains := ChainDetector.detect_chains(grid)
	assert_eq(chains.size(), 1, "One chain found")
	assert_eq(chains[0].direction, "vertical", "Chain is vertical")

## An unsolved cell breaks the run even though it has a letter behind it.
func test_ignores_unsolved_letters() -> void:
	var grid := _grid(5, [
		["C", "A", "T", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
	])
	# Mark the middle letter unsolved.
	for cell in grid.cells:
		if cell.x == 1 and cell.y == 0:
			cell.solved = false
	assert_eq(ChainDetector.detect_chains(grid).size(), 0, "Unsolved letter breaks the chain")

func test_ignores_non_words() -> void:
	var grid := _grid(5, [
		["X", "Q", "Z", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
	])
	assert_eq(ChainDetector.detect_chains(grid).size(), 0, "XQZ is not a chain")

func test_ignores_runs_below_minimum_length() -> void:
	var grid := _grid(5, [
		["A", "T", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
		["", "", "", "", ""],
	])
	assert_eq(ChainDetector.detect_chains(grid).size(), 0, "2-letter run is below min_chain_length")

func test_run_is_bounded_by_black_cells() -> void:
	# CAT, a black cell, then DOG - two separate chains, not "CATDOG".
	var grid := _grid(7, [
		["C", "A", "T", "", "D", "O", "G"],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
	])
	var chains := ChainDetector.detect_chains(grid)
	var words: Array[String] = []
	for chain in chains:
		words.append(String(chain.word))
	words.sort()
	assert_eq(words, ["CAT", "DOG"] as Array[String], "Black cell splits the run into two chains")

func test_chain_ids_are_stable_and_distinct() -> void:
	var grid := _grid(7, [
		["C", "A", "T", "", "D", "O", "G"],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
		["", "", "", "", "", "", ""],
	])
	var first := ChainDetector.detect_chains(grid)
	var second := ChainDetector.detect_chains(grid)
	assert_eq(first[0].id, second[0].id, "Same chain keeps the same id across passes")
	assert_ne(first[0].id, first[1].id, "Different chains get different ids")

func test_valid_prefix_lookup() -> void:
	assert_true(ChainDetector.is_valid_prefix("DRA"), "DRA prefixes DRAGON")
	assert_true(ChainDetector.is_valid_prefix(""), "Empty prefix is trivially valid")
	assert_false(ChainDetector.is_valid_prefix("ZZQX"), "ZZQX prefixes nothing")

## Design Doc 4.3's tier table.
func test_effect_tiers_match_design_doc() -> void:
	assert_eq(String(ChainEffects.effect_for_length(3).effect), "damage_buff", "3 letters -> damage buff")
	assert_eq(String(ChainEffects.effect_for_length(4).effect), "heal", "4 letters -> heal")
	assert_eq(String(ChainEffects.effect_for_length(5).effect), "reveal_letter", "5 letters -> reveal")
	assert_eq(String(ChainEffects.effect_for_length(6).effect), "skip_encounter", "6 letters -> skip")
	assert_eq(String(ChainEffects.effect_for_length(7).effect), "double_rewards", "7 letters -> double rewards")
	assert_eq(String(ChainEffects.effect_for_length(8).effect), "clear_line", "8 letters -> clear line")
	assert_eq(String(ChainEffects.effect_for_length(11).effect), "clear_line", "11 letters still -> clear line")
	assert_true(ChainEffects.effect_for_length(2).is_empty(), "2 letters earns nothing")

func test_effect_applies_heal() -> void:
	var player := {"current_hp": 50, "max_hp": 100}
	var summary := ChainEffects.apply(ChainEffects.effect_for_length(4), player)
	assert_true(summary.applied, "Heal applied")
	assert_eq(player.current_hp, 65, "Healed 15% of 100 max HP")

	# Healing cannot overshoot the maximum.
	var topped := {"current_hp": 95, "max_hp": 100}
	ChainEffects.apply(ChainEffects.effect_for_length(4), topped)
	assert_eq(topped.current_hp, 100, "Heal clamps at max HP")

func test_effect_applies_damage_buff() -> void:
	var player := {"current_hp": 100, "max_hp": 100}
	ChainEffects.apply(ChainEffects.effect_for_length(3), player)
	assert_approx(float(player.chain_damage_buff), 0.2, "3-letter chain grants +20%")
	assert_eq(int(player.chain_damage_buff_encounters), 3, "Buff lasts 3 encounters")

func test_grid_scoped_effects_are_deferred() -> void:
	var player := {"current_hp": 100, "max_hp": 100}
	var summary := ChainEffects.apply(ChainEffects.effect_for_length(5), player)
	assert_false(summary.applied, "reveal_letter is not applied by ChainEffects")
	assert_eq(String(summary.reason), "grid_scoped", "It is handed back to the grid owner")

func test_buffs_expire_after_their_encounter_count() -> void:
	var player := {"current_hp": 100, "max_hp": 100}
	ChainEffects.apply(ChainEffects.effect_for_length(3), player)
	for i in range(3):
		ChainEffects.expire_buffs(player)
	assert_approx(float(player.chain_damage_buff), 0.0, "Buff is gone after 3 encounters")
	assert_eq(int(player.chain_damage_buff_encounters), 0, "Counter bottoms out at zero")

	# Expiring again must not underflow.
	ChainEffects.expire_buffs(player)
	assert_eq(int(player.chain_damage_buff_encounters), 0, "Counter never goes negative")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------

## Builds a grid_state from a letter grid. "" means a black cell; any letter
## means a solved letter cell.
func _grid(size: int, rows: Array) -> Dictionary:
	var cells: Array = []
	for y in range(size):
		for x in range(size):
			var letter := String(rows[y][x])
			if letter == "":
				cells.append({
					"x": x, "y": y, "type": "black", "letter": "", "solved": false,
					"enemy_id": "", "clue_id": "", "bonus": null, "bonus_claimed": false,
				})
			else:
				cells.append({
					"x": x, "y": y, "type": "letter", "letter": letter, "solved": true,
					"enemy_id": "", "clue_id": "", "bonus": null, "bonus_claimed": false,
				})
	return {
		"size": size,
		"cells": cells,
		"words_horizontal": [],
		"words_vertical": [],
		"entrance": {"x": 0, "y": 0},
		"exit": {"x": size - 1, "y": size - 1},
	}
