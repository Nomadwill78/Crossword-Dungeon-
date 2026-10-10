#============================================================================
# test_run_settlement.gd
# RunSettlement: what a finished run does to the persistent profile.
#============================================================================

class_name TestRunSettlement
extends TestSuite

func _init() -> void:
	suite_name = "RunSettlement"

func run(_host: Node) -> void:
	_test_completed_run()
	_test_defeated_run()
	_test_level_up_and_unlocks()
	_test_accumulation_across_runs()
	_test_missing_data_is_tolerated()

func _run_dict(base_ink: int, tally: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var run := {
		"player_state": { "total_ink_drops_this_run": base_ink, "loadout": LexiconEffects.neutral_loadout() },
		"tally": tally,
		"final_score": 321,
		"duration_seconds": 100.0,
	}
	run.merge(extra, true)
	return run

func _world() -> Dictionary:
	return {
		"profile": GameState.default_profile(),
		"lexicon": LexiconState.default_state(),
		"statistics": GameState.default_statistics(),
	}

func _test_completed_run() -> void:
	var w := _world()
	var tally := {
		"words_solved": 6, "letters_solved": 22, "enemies_defeated": 5, "bosses_defeated": 0,
		"chains_activated": 3, "chains_by_length": { "3": 2, "5": 1 }, "longest_chain": 5,
	}
	var summary := RunSettlement.settle(w.profile, w.lexicon, w.statistics, _run_dict(80, tally), true)
	var completion := int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).ink_economy.run_completion_bonus)

	assert_true(bool(summary.completed), "the summary says the run was won")
	assert_eq(int(summary.ink.total), 80 + completion, "a win pays the haul plus the completion bonus")
	assert_eq(int(w.profile.total_runs), 1, "the run is counted")
	assert_eq(int(w.profile.runs_completed), 1, "and counted as a win")
	assert_eq(int(w.profile.best_score), 321, "the best score is recorded")
	assert_eq(int(w.profile.total_letters_solved), 22, "letters solved accumulate")
	assert_eq(int(w.profile.longest_chain), 5, "the longest chain is recorded")
	assert_eq(int(w.statistics.total_words_solved), 6, "words solved accumulate")
	assert_eq(int(w.statistics.total_enemies_defeated), 5, "enemies defeated accumulate")
	assert_eq(int(w.statistics.total_chains), 3, "chains accumulate")
	assert_eq(int(w.statistics.chains_by_length["3"]), 2, "chains are tallied by length")
	assert_eq(int(w.statistics.chains_by_length["5"]), 1, "including each length")
	assert_eq(int(w.statistics.total_deaths), 0, "a win is not a death")

	# The payout, plus First Steps and Linked Letters' rewards.
	var first_run_reward := int(LexiconData.get_achievement("first_run").reward_ink)
	var first_chain_reward := int(LexiconData.get_achievement("first_chain").reward_ink)
	var ids: Array = []
	for earned in summary.achievements:
		ids.append(String(earned.id))
	ids.sort()
	assert_true(ids.has("first_run") and ids.has("first_chain"), "finishing a first run with a chain earns both starter achievements")
	assert_true(ids.has("speed_demon"), "and a 100s clear earns Speed Demon")
	var rewards := 0
	for earned in summary.achievements:
		rewards += int(earned.reward_ink)
	assert_gt(float(rewards), float(first_run_reward + first_chain_reward) - 1.0, "the summary lists the achievement rewards")
	assert_eq(int(w.profile.ink_drops), int(summary.ink.total) + rewards, "the balance holds the payout plus rewards")
	assert_eq(int(summary.balance), int(w.profile.ink_drops), "the summary reports the new balance")

func _test_defeated_run() -> void:
	var w := _world()
	var summary := RunSettlement.settle(w.profile, w.lexicon, w.statistics, _run_dict(100, { "words_solved": 2 }, { "final_score": 0, "duration_seconds": INF }), false)
	var retention := float(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).ink_economy.defeat_retention)

	assert_false(bool(summary.completed), "the summary says the run was lost")
	assert_eq(int(summary.ink.total), int(floor(100 * retention)), "a loss keeps the configured fraction")
	assert_eq(int(w.profile.runs_completed), 0, "a loss is not a win")
	assert_eq(int(w.profile.total_runs), 1, "but it is a run")
	assert_eq(int(w.statistics.total_deaths), 1, "and a death is recorded")
	assert_false(AchievementTracker.is_earned(w.lexicon, "speed_demon"), "a loss never earns Speed Demon")
	assert_true(AchievementTracker.is_earned(w.lexicon, "first_run"), "but does earn First Steps")

func _test_level_up_and_unlocks() -> void:
	var w := _world()
	# One enormous haul to cross level 5 (7x7 grids) in a single settlement.
	var target := PlayerLevel.ink_for_level(5)
	var summary := RunSettlement.settle(w.profile, w.lexicon, w.statistics, _run_dict(target), true)
	assert_eq(int(summary.old_level), 1, "the summary remembers the starting level")
	assert_gt(float(summary.new_level), 4.0, "a big haul levels the player up")
	var unlock_ids: Array = []
	for entry in summary.unlocks:
		unlock_ids.append(String(entry.unlock_id))
	assert_true(unlock_ids.has("grid_7x7"), "crossing level 5 reports the 7x7 unlock")
	assert_eq(int(summary.new_level), int(w.profile.player_level), "the summary matches the profile")

func _test_accumulation_across_runs() -> void:
	var w := _world()
	var expected_lifetime := 0
	for i in range(5):
		var summary := RunSettlement.settle(w.profile, w.lexicon, w.statistics, _run_dict(40 + i, { "words_solved": 1, "chains_by_length": { "4": 1 }, "chains_activated": 1 }), i % 2 == 0)
		expected_lifetime += int(summary.ink.total)
		for earned in summary.achievements:
			expected_lifetime += int(earned.reward_ink)
	assert_eq(int(w.profile.total_runs), 5, "five runs are counted")
	assert_eq(int(w.profile.runs_completed), 3, "of which three were wins")
	assert_eq(int(w.statistics.total_deaths), 2, "and two were deaths")
	assert_eq(int(w.statistics.chains_by_length["4"]), 5, "chain tallies accumulate across runs")
	assert_eq(int(w.profile.total_ink_drops), expected_lifetime, "lifetime Ink is exactly the sum of every payout")
	assert_eq(int(w.profile.ink_drops), expected_lifetime, "and with nothing spent, the balance matches it")
	assert_true(int(w.profile.ink_drops) <= int(w.profile.total_ink_drops), "the balance never exceeds lifetime Ink")

func _test_missing_data_is_tolerated() -> void:
	var w := _world()
	var summary := RunSettlement.settle(w.profile, w.lexicon, w.statistics, {}, false)
	assert_eq(int(summary.ink.total), 0, "an empty run dictionary pays nothing")
	assert_eq(int(w.profile.total_runs), 1, "but is still counted")
	assert_eq(int(w.profile.player_level), 1, "and does not level anyone")
