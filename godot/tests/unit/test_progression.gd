#============================================================================
# test_progression.gd
# PlayerLevel (the 1-50 curve and its unlocks) and InkDropManager (the Ink
# Drop ledger, run payouts and the daily login).
#============================================================================

class_name TestProgression
extends TestSuite

func _init() -> void:
	suite_name = "Progression (PlayerLevel + InkDropManager)"

func run(_host: Node) -> void:
	_test_level_curve()
	_test_level_progress()
	_test_unlocks()
	_test_award_and_spend()
	_test_level_up_signals()
	_test_settle_run_ink()
	_test_daily_login()

#----------------------------------------------------------------------------
# PlayerLevel
#----------------------------------------------------------------------------
func _test_level_curve() -> void:
	assert_eq(PlayerLevel.ink_for_level(1), 0, "level 1 costs nothing")
	assert_eq(PlayerLevel.level_for_ink(0), 1, "0 Ink is level 1")
	assert_eq(PlayerLevel.level_for_ink(-50), 1, "negative Ink is still level 1")

	var previous := 0
	var round_trips_ok := true
	var strictly_rising := true
	for level in range(2, PlayerLevel.max_level() + 1):
		var needed := PlayerLevel.ink_for_level(level)
		if needed <= previous:
			strictly_rising = false
		if PlayerLevel.level_for_ink(needed) != level or PlayerLevel.level_for_ink(needed - 1) != level - 1:
			round_trips_ok = false
		previous = needed
	assert_true(strictly_rising, "each level needs strictly more total Ink than the last")
	assert_true(round_trips_ok, "level_for_ink inverts ink_for_level at every boundary")

	var cap_ink := PlayerLevel.ink_for_level(PlayerLevel.max_level())
	assert_eq(PlayerLevel.level_for_ink(cap_ink), PlayerLevel.max_level(), "enough Ink reaches the cap")
	assert_eq(PlayerLevel.level_for_ink(cap_ink * 100), PlayerLevel.max_level(), "Ink beyond the cap does not exceed it")

func _test_level_progress() -> void:
	var start := PlayerLevel.progress(0)
	assert_eq(int(start.level), 1, "progress at 0 Ink is level 1")
	assert_eq(int(start.ink_into_level), 0, "no Ink into level 1 yet")
	assert_false(bool(start.is_max), "level 1 is not max")
	assert_approx(float(start.fraction), 0.0, "fraction starts at 0")

	var mid_ink := PlayerLevel.ink_for_level(4) + 7
	var mid := PlayerLevel.progress(mid_ink)
	assert_eq(int(mid.level), 4, "progress reports the current level")
	assert_eq(int(mid.ink_into_level), 7, "progress counts Ink into the level")
	assert_eq(int(mid.ink_for_next), PlayerLevel.ink_for_level(5) - PlayerLevel.ink_for_level(4), "progress spans the level's width")
	assert_between(float(mid.fraction), 0.0, 1.0, "fraction stays within 0..1")

	var top := PlayerLevel.progress(PlayerLevel.ink_for_level(PlayerLevel.max_level()))
	assert_true(bool(top.is_max), "the cap reports is_max")
	assert_approx(float(top.fraction), 1.0, "a maxed bar is full")

func _test_unlocks() -> void:
	assert_false(PlayerLevel.is_unlocked("grid_7x7", 4), "7x7 grids are locked below level 5")
	assert_true(PlayerLevel.is_unlocked("grid_7x7", 5), "Design Doc 5.2: level 5 unlocks 7x7 grids")
	assert_false(PlayerLevel.is_unlocked("grid_9x9", 19), "9x9 grids are locked below level 20")
	assert_true(PlayerLevel.is_unlocked("grid_9x9", 20), "Design Doc 5.2: level 20 unlocks 9x9 grids")
	assert_false(PlayerLevel.is_unlocked("not_a_feature", 50), "an unknown feature id is locked, not free")

	var gained := PlayerLevel.unlocks_gained(1, 10)
	var ids: Array[String] = []
	for entry in gained:
		ids.append(String(entry.unlock_id))
	assert_eq(ids, ["grid_7x7", "chain_stacking"], "unlocks_gained lists levels 5 and 10 climbing 1 -> 10")
	assert_eq(PlayerLevel.unlocks_gained(5, 5).size(), 0, "no change in level gains nothing")
	assert_eq(PlayerLevel.unlocks_gained(5, 9).size(), 0, "the old level's own unlock is not re-granted")

	assert_eq(PlayerLevel.available_grid_sizes(1), [5], "only 5x5 at level 1")
	assert_eq(PlayerLevel.available_grid_sizes(5), [5, 7], "7x7 joins at level 5")
	assert_eq(PlayerLevel.available_grid_sizes(20), [5, 7, 9], "9x9 joins at level 20")

#----------------------------------------------------------------------------
# InkDropManager - ledger
#----------------------------------------------------------------------------
func _test_award_and_spend() -> void:
	var profile := GameState.default_profile()
	var earned_log: Array = []
	var spent_log: Array = []
	var changed_log: Array = []
	var on_earned := func(amount: int, source: String): earned_log.append([amount, source])
	var on_spent := func(amount: int, item: String): spent_log.append([amount, item])
	var on_changed := func(total: int, delta: int): changed_log.append([total, delta])
	EventBus.ink_drops_earned.connect(on_earned)
	EventBus.ink_drops_spent.connect(on_spent)
	EventBus.ink_drops_changed.connect(on_changed)

	var result := InkDropManager.award(profile, 100, "test")
	assert_eq(int(result.awarded), 100, "award reports what it granted")
	assert_eq(int(profile.ink_drops), 100, "award raises the balance")
	assert_eq(int(profile.total_ink_drops), 100, "award raises lifetime Ink")
	assert_eq(earned_log, [[100, "test"]], "award emits ink_drops_earned")
	assert_eq(changed_log, [[100, 100]], "award emits ink_drops_changed with the new balance")

	InkDropManager.award(profile, 0, "nothing")
	InkDropManager.award(profile, -5, "nothing")
	assert_eq(int(profile.ink_drops), 100, "zero and negative awards are ignored")
	assert_eq(earned_log.size(), 1, "ignored awards emit nothing")

	assert_true(InkDropManager.can_afford(profile, 100), "can afford exactly the balance")
	assert_false(InkDropManager.can_afford(profile, 101), "cannot afford more than the balance")
	assert_false(InkDropManager.can_afford(profile, -1), "a negative price is never affordable")

	assert_false(InkDropManager.spend(profile, 101, "too_much"), "overspending is refused")
	assert_eq(int(profile.ink_drops), 100, "a refused spend changes nothing")
	assert_eq(spent_log.size(), 0, "a refused spend emits nothing")

	assert_true(InkDropManager.spend(profile, 40, "thing"), "affordable spend succeeds")
	assert_eq(int(profile.ink_drops), 60, "spend lowers the balance")
	assert_eq(int(profile.total_ink_drops), 100, "spending never lowers lifetime Ink")
	assert_eq(spent_log, [[40, "thing"]], "spend emits ink_drops_spent")
	assert_eq(changed_log.back(), [60, -40], "spend emits a negative delta")

	assert_true(InkDropManager.spend(profile, 0, "free"), "a free item can always be taken")
	assert_eq(spent_log.size(), 1, "a free spend emits nothing")

	EventBus.ink_drops_earned.disconnect(on_earned)
	EventBus.ink_drops_spent.disconnect(on_spent)
	EventBus.ink_drops_changed.disconnect(on_changed)

func _test_level_up_signals() -> void:
	var profile := GameState.default_profile()
	var levels: Array = []
	var on_level := func(level: int): levels.append(level)
	EventBus.level_up.connect(on_level)

	# Enough in one award to jump several levels: every level crossed fires.
	var target_level := 6
	var result := InkDropManager.award(profile, PlayerLevel.ink_for_level(target_level), "big")
	assert_eq(int(profile.player_level), target_level, "a large award levels the player up")
	assert_eq(levels, [2, 3, 4, 5, 6], "level_up fires once for each level crossed")
	assert_eq(int(result.old_level), 1, "award reports the old level")
	assert_eq(int(result.new_level), target_level, "award reports the new level")

	levels.clear()
	InkDropManager.spend(profile, 50, "x")
	InkDropManager.award(profile, 1, "tiny")
	assert_eq(levels, [], "spending first does not make a later small award re-level")
	assert_eq(int(profile.player_level), target_level, "level is driven by lifetime Ink, not the balance")

	# A retuned curve must never demote anyone.
	profile["player_level"] = 12
	InkDropManager.award(profile, 1, "retune")
	assert_eq(int(profile.player_level), 12, "level never goes backwards")

	EventBus.level_up.disconnect(on_level)

#----------------------------------------------------------------------------
# InkDropManager - run payout
#----------------------------------------------------------------------------
func _test_settle_run_ink() -> void:
	var economy: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("ink_economy", {})
	var completion := int(economy.get("run_completion_bonus", 0))
	var retention := float(economy.get("defeat_retention", 1.0))
	var neutral := LexiconEffects.neutral_loadout()

	var won := InkDropManager.settle_run_ink(100, true, neutral)
	assert_eq(int(won.completion_bonus), completion, "a cleared dungeon earns the completion bonus")
	assert_eq(int(won.total), 100 + completion, "a clear pays base plus bonus")
	assert_eq(int(won.defeat_penalty), 0, "a clear has no penalty")
	assert_eq(int(won.tome_bonus), 0, "no tome, no tome bonus")

	var lost := InkDropManager.settle_run_ink(100, false, neutral)
	assert_eq(int(lost.completion_bonus), 0, "a lost run earns no completion bonus")
	assert_eq(int(lost.total), int(floor(100 * retention)), "a lost run keeps only the configured fraction")
	assert_eq(int(lost.total) + int(lost.defeat_penalty), 100, "kept + lost accounts for every drop")

	var boosted_loadout := LexiconEffects.neutral_loadout()
	boosted_loadout["ink_multiplier"] = 1.5
	var boosted := InkDropManager.settle_run_ink(100, true, boosted_loadout)
	assert_eq(int(boosted.total), int(floor((100 + completion) * 1.5)), "the ink multiplier applies to the whole haul")
	assert_eq(int(boosted.tome_bonus), int(boosted.total) - (100 + completion), "the tome's share is reported separately")

	var penniless := InkDropManager.settle_run_ink(-40, false, neutral)
	assert_eq(int(penniless.base), 0, "a negative tally is treated as zero")
	assert_eq(int(penniless.total), 0, "nothing earned, nothing paid")

	var chain_loadout := LexiconEffects.neutral_loadout()
	chain_loadout["chain_ink_bonus"] = 10
	assert_eq(InkDropManager.ink_for_chain(neutral), int(economy.get("ink_per_chain", 20)), "a chain pays the configured reward")
	assert_eq(InkDropManager.ink_for_chain(chain_loadout), int(economy.get("ink_per_chain", 20)) + 10, "Resonance adds to the chain reward")

#----------------------------------------------------------------------------
# InkDropManager - daily login
#----------------------------------------------------------------------------
func _test_daily_login() -> void:
	var economy: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("ink_economy", {})
	var base := int(economy.get("daily_login_ink", 0))
	var per_day := int(economy.get("daily_streak_bonus_per_day", 0))
	var cap := int(economy.get("daily_streak_bonus_cap", 0))

	var profile := GameState.default_profile()
	var first := InkDropManager.claim_daily_login(profile, "2026-03-10")
	assert_true(bool(first.claimed), "the first login pays out")
	assert_eq(int(first.amount), base, "day one pays the base reward")
	assert_eq(int(first.streak), 1, "day one starts a streak of 1")
	assert_eq(int(profile.ink_drops), base, "the reward lands in the balance")

	var again := InkDropManager.claim_daily_login(profile, "2026-03-10")
	assert_false(bool(again.claimed), "a second login the same day pays nothing")
	assert_eq(int(profile.ink_drops), base, "and changes nothing")

	var second := InkDropManager.claim_daily_login(profile, "2026-03-11")
	assert_true(bool(second.claimed), "the next day pays again")
	assert_eq(int(second.streak), 2, "consecutive days extend the streak")
	assert_eq(int(second.amount), base + per_day, "a streak adds the per-day bonus")

	var gap := InkDropManager.claim_daily_login(profile, "2026-03-14")
	assert_eq(int(gap.streak), 1, "missing days resets the streak")
	assert_eq(int(profile.longest_streak_days), 2, "the best streak is remembered")
	assert_eq(int(gap.amount), base, "a reset streak pays the base reward")

	var back := InkDropManager.claim_daily_login(profile, "2026-03-01")
	assert_false(bool(back.claimed), "a clock set back in time cannot re-claim")
	var garbage := InkDropManager.claim_daily_login(profile, "not-a-date")
	assert_false(bool(garbage.claimed), "a malformed date is refused")
	var impossible := InkDropManager.claim_daily_login(profile, "2026-13-45")
	assert_false(bool(impossible.claimed), "an impossible date is refused")

	# The streak bonus tops out at the configured cap.
	var long_profile := GameState.default_profile()
	var capped_amount := 0
	for day in range(1, 31):
		var result := InkDropManager.claim_daily_login(long_profile, "2026-04-%02d" % day)
		capped_amount = int(result.amount)
	assert_eq(capped_amount, base + cap, "the streak bonus is capped")
	assert_eq(int(long_profile.current_streak_days), 30, "thirty consecutive days is a 30-day streak")
