#============================================================================
# test_achievements.gd
# AchievementTracker: each Trophy Room condition, one-time rewards, and the
# cascade where a reward's Ink levels the player into another achievement.
#============================================================================

class_name TestAchievements
extends TestSuite

func _init() -> void:
	suite_name = "AchievementTracker"

func run(_host: Node) -> void:
	_test_stat_achievements()
	_test_speed_demon()
	_test_vocabulary_master()
	_test_cascade_and_signal()

func _ids(earned: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry in earned:
		out.append(String(entry.id))
	out.sort()
	return out

func _test_stat_achievements() -> void:
	var profile := GameState.default_profile()
	var lexicon := LexiconState.default_state()
	var statistics := GameState.default_statistics()

	assert_eq(AchievementTracker.evaluate(profile, lexicon, statistics).size(), 0, "a brand-new player has earned nothing")

	profile["total_runs"] = 1
	var earned := AchievementTracker.evaluate(profile, lexicon, statistics)
	assert_eq(_ids(earned), ["first_run"], "finishing a run earns First Steps")
	assert_true(AchievementTracker.is_earned(lexicon, "first_run"), "and records it in the lexicon")
	var reward := int(LexiconData.get_achievement("first_run").reward_ink)
	assert_eq(int(profile.ink_drops), reward, "the reward is paid in Ink")
	assert_eq(int(earned[0].reward_ink), reward, "the result reports the reward")

	assert_eq(AchievementTracker.evaluate(profile, lexicon, statistics).size(), 0, "an achievement is only ever earned once")
	assert_eq(int(profile.ink_drops), reward, "and its reward is only paid once")

	statistics["total_chains"] = 1
	assert_eq(_ids(AchievementTracker.evaluate(profile, lexicon, statistics)), ["first_chain"], "a first chain earns Linked Letters via the statistics")

func _test_speed_demon() -> void:
	var limit := float(LexiconData.get_achievement("speed_demon").condition.value)
	var statistics := GameState.default_statistics()

	var slow_profile := GameState.default_profile()
	var slow_lexicon := LexiconState.default_state()
	AchievementTracker.evaluate(slow_profile, slow_lexicon, statistics, { "completed": true, "duration_seconds": limit + 1.0 })
	assert_false(AchievementTracker.is_earned(slow_lexicon, "speed_demon"), "a slow clear does not earn Speed Demon")

	var lost_profile := GameState.default_profile()
	var lost_lexicon := LexiconState.default_state()
	AchievementTracker.evaluate(lost_profile, lost_lexicon, statistics, { "completed": false, "duration_seconds": 5.0 })
	assert_false(AchievementTracker.is_earned(lost_lexicon, "speed_demon"), "a fast death does not earn it either")

	var fast_profile := GameState.default_profile()
	var fast_lexicon := LexiconState.default_state()
	AchievementTracker.evaluate(fast_profile, fast_lexicon, statistics, { "completed": true, "duration_seconds": limit - 1.0 })
	assert_true(AchievementTracker.is_earned(fast_lexicon, "speed_demon"), "a fast clear earns Speed Demon")

	var no_run_lexicon := LexiconState.default_state()
	AchievementTracker.evaluate(GameState.default_profile(), no_run_lexicon, statistics)
	assert_false(AchievementTracker.is_earned(no_run_lexicon, "speed_demon"), "outside a run end it can never fire")

func _test_vocabulary_master() -> void:
	var profile := GameState.default_profile()
	InkDropManager.award(profile, 20000, "test")
	var lexicon := LexiconState.default_state()
	var statistics := GameState.default_statistics()
	AchievementTracker.evaluate(profile, lexicon, statistics)
	assert_false(AchievementTracker.is_earned(lexicon, "vocabulary_master"), "no trees bought, no mastery")

	for node_id in ["wld_01", "wld_02"]:
		VocabularyTree.purchase(lexicon, profile, node_id)
	AchievementTracker.evaluate(profile, lexicon, statistics)
	assert_false(AchievementTracker.is_earned(lexicon, "vocabulary_master"), "two of three nodes is not mastery")

	VocabularyTree.purchase(lexicon, profile, "wld_03")
	AchievementTracker.evaluate(profile, lexicon, statistics)
	assert_true(AchievementTracker.is_earned(lexicon, "vocabulary_master"), "completing any one tree earns Vocabulary Master")

func _test_cascade_and_signal() -> void:
	# Park the player 1 Ink short of the level cap with First Steps still
	# unearned: its small reward tips them to level 50, which must award
	# Grandmaster in the same call rather than waiting for the next run.
	var profile := GameState.default_profile()
	var cap_ink := PlayerLevel.ink_for_level(PlayerLevel.max_level())
	profile["total_ink_drops"] = cap_ink - 1
	profile["ink_drops"] = cap_ink - 1
	profile["player_level"] = PlayerLevel.max_level() - 1
	profile["total_runs"] = 1
	var lexicon := LexiconState.default_state()

	var seen: Array = []
	var handler := func(id: String): seen.append(id)
	EventBus.achievement_unlocked.connect(handler)

	var earned := AchievementTracker.evaluate(profile, lexicon, GameState.default_statistics())
	assert_eq(_ids(earned), ["first_run", "grandmaster"], "a reward's level-up earns the next achievement in the same call")
	assert_eq(int(profile.player_level), PlayerLevel.max_level(), "the player is at the cap")
	assert_eq(seen, ["first_run", "grandmaster"], "achievement_unlocked fires in earning order")

	EventBus.achievement_unlocked.disconnect(handler)
