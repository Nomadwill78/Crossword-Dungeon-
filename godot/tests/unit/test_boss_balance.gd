#============================================================================
# test_boss_balance.gd
# Two things: that the boss-balance simulation (tests/bots/BossBalance.gd) is
# itself trustworthy, and that The Thesaurus, as the data stands, lands inside
# the win-rate targets in tests/bots/boss_balance.json for each kind of
# simulated player. If a clue, a tome or the damage formula changes and the
# boss drifts out of its bands, this suite fails and says by how much.
#
# The simulation is seeded, so every number here is reproducible. The bands
# are wide enough (about 15 points) that a few hundred fights land inside them
# with room to spare.
#============================================================================

class_name TestBossBalance
extends TestSuite

const FIGHTS_PER_CELL := 600
const SEED_BASE := 20260101

func _init() -> void:
	suite_name = "BossBalance"

func run(_host: Node) -> void:
	_test_sim_timer()
	_test_recall_chance()
	_test_response_seconds()
	_test_players()
	_test_a_perfect_player_wins()
	_test_a_hopeless_player_loses()
	_test_running_out_of_clock_is_a_miss()
	_test_fights_are_reproducible()
	_test_boss_scaling_data()
	_test_win_rates_are_inside_the_targets()
	_test_a_bigger_grid_is_never_easier()
	_test_skill_and_depth_ordering()
	_test_the_tuning_survives_other_assumptions()

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _archetype(name: String) -> Dictionary:
	return BossBalance.config().archetypes[name]

func _win_rate(archetype: String, loadout: String, depth: int, options: Dictionary = {}) -> float:
	return float(BossBalance.run_cell(_archetype(archetype), loadout, depth, FIGHTS_PER_CELL, SEED_BASE, options).win_rate)

## A model with no slips: nobody mistypes, answers take the same time, every
## prompt is as easy as a plain one (no extra step in the opposite-of phase) and
## everyone knows the archaic spelling.
func _flawless_model() -> Dictionary:
	return {
		"typo_chance": 0.0, "time_spread": 0.0, "archaic_known_chance": 1.0,
		"phase_recall_multiplier": {"1": 1.0, "2": 1.0, "3": 1.0},
	}

#----------------------------------------------------------------------------
# TESTS - the simulation's parts
#----------------------------------------------------------------------------
func _test_sim_timer() -> void:
	var timer := SimTimer.new()
	assert_eq(timer.get_time_remaining(), 0.0, "a SimTimer that has not started reports no time")
	timer.start(3, {})
	assert_approx(timer.max_time, TimerSystem.calculate_max_time(3, {}), "it starts at the real clock length for the clue")
	assert_true(timer.is_running, "and is running")
	assert_approx(timer.get_time_remaining(), timer.max_time, "with the whole clock left")
	timer.simulated_remaining = 7.5
	assert_approx(timer.get_time_remaining(), 7.5, "the simulation decides how much is left")
	timer.stop()
	assert_eq(timer.get_time_remaining(), 0.0, "stopped means no time (as with the real timer)")
	timer.free()

func _test_recall_chance() -> void:
	var model := {
		"retry_recall_bonus": 0.35,
		"reworded_clue_bonus": 0.5,
		"phase_recall_multiplier": {"1": 1.0, "2": 0.8, "3": 1.0},
	}
	assert_approx(BossBalance.recall_chance(0.8, 1, 1, model), 0.8, "phase 1, first look: the player's own recall")
	assert_approx(BossBalance.recall_chance(0.8, 1, 2, model), 0.8 + 0.2 * 0.5, "phase 1 retry: the reworded clue helps most")
	assert_approx(BossBalance.recall_chance(0.8, 2, 1, model), 0.64, "phase 2: the opposite-of step costs recall")
	assert_approx(BossBalance.recall_chance(0.8, 2, 2, model), 0.64 + 0.36 * 0.35, "phase 2 retry: a plain second look")
	assert_approx(BossBalance.recall_chance(0.8, 3, 3, model), 0.8 + 0.2 * 0.35, "phase 3 retry")
	assert_eq(BossBalance.recall_chance(0.0, 1, 1, model), 0.0, "someone who does not know it, does not")
	assert_true(BossBalance.recall_chance(0.999, 1, 2, model) <= 1.0, "never above certainty")
	assert_true(BossBalance.recall_chance(0.7, 1, 3, model) >= BossBalance.recall_chance(0.7, 1, 1, model), "a retry never makes it harder")

func _test_response_seconds() -> void:
	var rng := _rng(7)
	var model := {"phase_time_multiplier": {"1": 1.0, "2": 1.3, "3": 1.2}, "time_spread": 0.35}
	var total := 0.0
	var shortest := INF
	for i in range(4000):
		var seconds := BossBalance.response_seconds(30.0, 0.5, 2, model, rng)
		shortest = minf(shortest, seconds)
		total += seconds
	assert_true(shortest >= 0.0, "a response time is never negative")
	var expected := 30.0 * 0.5 * 1.3 * exp(0.35 * 0.35 / 2.0) # the mean of a log-normal
	assert_true(absf(total / 4000.0 - expected) < expected * 0.04, "average response time matches the model (%.2f vs %.2f)" % [total / 4000.0, expected])
	assert_approx(BossBalance.response_seconds(30.0, 0.5, 1, {"time_spread": 0.0}, rng), 15.0, "no spread means exactly speed x clock")
	assert_eq(BossBalance.response_seconds(30.0, 0.0, 1, model, rng), 0.0, "an instant answer takes no time")

func _test_players() -> void:
	var bare := BossBalance.make_player("bare")
	assert_eq(int(bare.max_hp), 100, "a bare player has the base 100 HP")
	assert_eq(int(bare.current_hp), 80, "and arrives at the configured 80% of it")
	assert_approx(float(bare.damage_reduction), 0.0, "with no damage reduction")

	var geared := BossBalance.make_player("geared")
	assert_eq(int(geared.max_hp), 125, "the geared player's Vitality tome adds 25 max HP")
	assert_eq(int(geared.current_hp), 100, "arriving at 80% of the larger pool")
	assert_approx(float(geared.damage_reduction), 0.15, "Ward takes 15% off every strike")
	assert_approx(float(geared.tome_multipliers.combat), 1.10, "Might adds 10% damage")

	assert_eq(int(BossBalance.make_player("geared", 1.0).current_hp), 125, "arrival health can be overridden")
	assert_eq(int(BossBalance.make_player("geared", 0.0).current_hp), 1, "but a player always arrives alive")
	assert_eq(int(BossBalance.make_player("no_such_loadout").max_hp), 100, "an unknown loadout is a bare player, not a crash")

	var merged := BossBalance.merged_model({"phase_recall_multiplier": {"2": 0.5}, "typo_chance": 0.5})
	assert_approx(float(merged.phase_recall_multiplier["2"]), 0.5, "an override replaces just that entry")
	assert_approx(float(merged.phase_recall_multiplier["1"]), 1.0, "and leaves the others alone")
	assert_approx(float(merged.typo_chance), 0.5, "scalars are replaced")
	assert_approx(float(BossBalance.config().model.typo_chance), 0.03, "the config itself is untouched")

#----------------------------------------------------------------------------
# TESTS - whole fights through the real game code
#----------------------------------------------------------------------------
func _test_a_perfect_player_wins() -> void:
	var perfect := {"recall": 1.0, "speed": 0.1}
	var options := {"model": _flawless_model()}
	for depth in [5, 10, 15]:
		var r := BossBalance.fight(perfect, "geared", depth, _rng(depth), options)
		assert_true(bool(r.won), "a flawless, fast player beats the depth-%d boss" % depth)
		assert_false(bool(r.died), "and does not die doing it")
		assert_false(bool(r.abandoned), "the fight ends on its own, not on the safety backstop")
		assert_eq(int(r.misses), 0, "without a single miss")
		assert_eq(int(r.hp_left), 100, "so arrives and leaves with the same HP")
		assert_eq(int(r.phase_reached), 3, "and sees all three phases")
		var counted := 0
		for phase in r.rounds_by_phase:
			counted += int(r.rounds_by_phase[phase])
		assert_eq(counted, int(r.rounds), "every round is counted in exactly one phase")
		assert_true(int(r.rounds) >= 3, "a 260+ HP boss takes several rounds")

func _test_a_hopeless_player_loses() -> void:
	var r := BossBalance.fight({"recall": 0.0, "speed": 0.5}, "geared", 5, _rng(3))
	assert_true(bool(r.died), "someone who knows nothing dies")
	assert_false(bool(r.won), "and does not win")
	assert_false(bool(r.abandoned), "the fight still ends properly")
	assert_eq(int(r.hp_left), 0, "with no HP left")
	assert_true(int(r.misses) >= 3, "after several misses")
	assert_eq(int(r.phase_reached), 1, "never getting past the first phase")

func _test_running_out_of_clock_is_a_miss() -> void:
	# Answering after the clock has run out is a timeout: a miss the boss punishes.
	var r := BossBalance.fight({"recall": 1.0, "speed": 5.0}, "geared", 5, _rng(5), {"model": _flawless_model()})
	assert_true(int(r.timeouts) > 0, "answers that arrive after the clock are timeouts")
	assert_eq(int(r.timeouts), int(r.misses), "and every one of them is a miss")
	assert_true(bool(r.died), "a player who is always too slow dies even though they know every answer")

func _test_fights_are_reproducible() -> void:
	var profile := _archetype("average")
	var a := BossBalance.run_cell(profile, "geared", 5, 60, 99)
	var b := BossBalance.run_cell(profile, "geared", 5, 60, 99)
	assert_eq(a, b, "the same seed gives exactly the same results")
	var c := BossBalance.run_cell(profile, "geared", 5, 60, 100)
	assert_ne(a, c, "a different seed gives different ones")

#----------------------------------------------------------------------------
# TESTS - the boss's own numbers
#----------------------------------------------------------------------------
func _test_boss_scaling_data() -> void:
	var boss_id := String(EnemyDatabase.get_boss_ids()[0])
	var boss := EnemyDatabase.get_enemy(boss_id)
	var grid_hp := int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).difficulty_scaling.hp_per_grid_size)
	var previous_hp := 0
	for depth: int in [5, 10, 15, 20]:
		var encounter := EnemyDatabase.build_encounter(boss_id, depth, 5)
		var expected_hp: int = int(boss.base_hp) + int(boss.scaling.hp_per_depth) * depth + grid_hp * 5
		assert_eq(int(encounter.max_hp), expected_hp, "depth %d: HP follows the boss's own scaling" % depth)
		assert_true(int(encounter.max_hp) > previous_hp, "depth %d: a deeper boss has more HP" % depth)
		previous_hp = int(encounter.max_hp)
		var expected_damage: int = int(boss.base_damage) + int(boss.scaling.damage_per_depth) * depth
		assert_eq(int(encounter.damage), expected_damage, "depth %d: damage follows the boss's scaling" % depth)

#----------------------------------------------------------------------------
# TESTS - the targets
#----------------------------------------------------------------------------
func _test_win_rates_are_inside_the_targets() -> void:
	var targets: Dictionary = BossBalance.config().targets
	# A bigger grid gives the boss a little more HP, and the live fight passes the
	# player's chosen grid size, so the bands must hold at the smallest AND the
	# largest supported size (the sizes in between fall between the two).
	var sizes: Array = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).grid.supported_sizes
	for grid_size in [int(sizes.min()), int(sizes.max())]:
		for depth_key in targets.geared:
			for archetype in targets.geared[depth_key]:
				var band: Array = targets.geared[depth_key][archetype]
				var rate := _win_rate(archetype, "geared", int(depth_key), {"grid_size": grid_size})
				assert_true(rate >= float(band[0]) and rate <= float(band[1]),
					"geared %s at depth %s on a %dx%d grid wins %.0f%% (target %.0f-%.0f%%)" % [archetype, depth_key, grid_size, grid_size, rate * 100.0, float(band[0]) * 100.0, float(band[1]) * 100.0])
	for depth_key in targets.bare:
		for archetype in targets.bare[depth_key]:
			var band: Array = targets.bare[depth_key][archetype]
			var rate := _win_rate(archetype, "bare", int(depth_key))
			assert_true(rate >= float(band[0]) and rate <= float(band[1]),
				"bare %s at depth %s wins %.0f%% (target %.0f-%.0f%%)" % [archetype, depth_key, rate * 100.0, float(band[0]) * 100.0, float(band[1]) * 100.0])

func _test_a_bigger_grid_is_never_easier() -> void:
	var small := BossBalance.run_cell(_archetype("average"), "geared", 10, 600, SEED_BASE, {"grid_size": 5})
	var large := BossBalance.run_cell(_archetype("average"), "geared", 10, 600, SEED_BASE, {"grid_size": 9})
	assert_true(float(large.win_rate) <= float(small.win_rate) + 0.03, "a 9x9 boss (+8 HP) is not easier than a 5x5 one (%.0f%% vs %.0f%%)" % [float(large.win_rate) * 100.0, float(small.win_rate) * 100.0])
	var boss_id := String(EnemyDatabase.get_boss_ids()[0])
	var hp_5 := int(EnemyDatabase.build_encounter(boss_id, 10, 5).max_hp)
	var hp_9 := int(EnemyDatabase.build_encounter(boss_id, 10, 9).max_hp)
	assert_gt(float(hp_9), float(hp_5), "the simulation's grid size really reaches the boss: more HP on a larger grid")

func _test_skill_and_depth_ordering() -> void:
	for depth in [5, 10, 15]:
		var novice := _win_rate("novice", "geared", depth)
		var average := _win_rate("average", "geared", depth)
		var strong := _win_rate("strong", "geared", depth)
		var expert := _win_rate("expert", "geared", depth)
		assert_true(novice < average and average < strong and strong < expert,
			"depth %d: better players win more often (%.0f / %.0f / %.0f / %.0f%%)" % [depth, novice * 100.0, average * 100.0, strong * 100.0, expert * 100.0])
		assert_true(novice > 0.0, "depth %d: even a novice can win by luck" % depth)
	# Deeper bosses are harder, but by a gentle slope (a wall at depth 15 was the
	# problem this tuning fixed): at most 30 points of win rate lost from depth 5 to 15.
	for archetype in ["average", "strong"]:
		var d5 := _win_rate(archetype, "geared", 5)
		var d10 := _win_rate(archetype, "geared", 10)
		var d15 := _win_rate(archetype, "geared", 15)
		assert_true(d10 <= d5 + 0.03 and d15 <= d10 + 0.03, "%s: a deeper boss is not easier" % archetype)
		assert_true(d5 - d15 <= 0.30, "%s: depth 15 is %.0f points harder than depth 5, not a wall" % [archetype, (d5 - d15) * 100.0])

## The simulated person is a set of guesses. A tuning that only works for one
## exact set of guesses is no tuning, so check that the conclusions hold when
## the guesses that matter most are moved.
func _test_the_tuning_survives_other_assumptions() -> void:
	var variants := {
		"arrive at 60% HP": {"arrival_hp": 0.6},
		"arrive at full HP": {"arrival_hp": 1.0},
		"opposite-of phase is hard": {"model": {"phase_recall_multiplier": {"2": 0.6}}},
		"twice the typos": {"model": {"typo_chance": 0.06}},
	}
	for label in variants:
		var options: Dictionary = variants[label]
		var average := _win_rate("average", "geared", 5, options)
		var strong := _win_rate("strong", "geared", 15, options)
		var novice := _win_rate("novice", "geared", 5, options)
		assert_true(average < 0.80, "%s: an average player still finds the first boss hard (%.0f%%)" % [label, average * 100.0])
		assert_true(strong > 0.40, "%s: a strong player still has a real chance at depth 15 (%.0f%%)" % [label, strong * 100.0])
		assert_true(novice < average, "%s: skill still matters" % label)
