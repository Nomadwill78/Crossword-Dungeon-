#============================================================================
# BossBalance.gd
# Plays The Thesaurus again and again with simulated PEOPLE (not the playtest
# bot, which is an untimed, near-perfect typist) and reports how often each
# kind of player wins. This is how the boss is tuned: change the boss's data
# (enemies_master.json), re-run, and see the win rates move.
#
# What it simulates, per attempt (all assumptions, see boss_balance.json):
#   * how long the player takes, against the clue's REAL clock - a slow answer
#     earns less speed bonus and running out of clock is a miss;
#   * whether they know the answer (harder in the opposite-of phase, and a
#     retry or a reworded clue helps), and whether they mistype it;
#   * in the archaic phase, whether they type the archaic spelling (full
#     damage) or the modern one (accepted at half).
# Every fight runs through the real BossEncounter, CombatStateMachine and
# CombatEngine, so the damage formula, the boss's HP and strikes, the phases
# and the player's Lexicon loadout are the game's own.
#
# Run: godot --headless --path . tests/bots/BossBalanceRunner.tscn
# Dependencies: BossEncounter, CombatStateMachine, CombatEngine, SimTimer,
#               LexiconEffects, ConfigLoader
# Events: none
#============================================================================

class_name BossBalance
extends RefCounted

const CONFIG_PATH := "res://tests/bots/boss_balance.json"
## The grid size a simulated fight uses unless told otherwise (the smallest).
const DEFAULT_GRID_SIZE := 5
## A wrong answer to type when the simulated player does not know the clue.
const WRONG_ANSWER := "QQQQQQQQQQ"

#----------------------------------------------------------------------------
# PUBLIC METHODS - inputs
#----------------------------------------------------------------------------

## The assumptions, archetypes, loadouts and targets (boss_balance.json).
static func config() -> Dictionary:
	return ConfigLoader.load_json(CONFIG_PATH)

## The `model` block with [param overrides] laid over it (one level deep, so
## `{"phase_recall_multiplier": {"2": 0.6}}` changes only phase 2).
static func merged_model(overrides: Dictionary = {}) -> Dictionary:
	var model: Dictionary = (config().get("model", {}) as Dictionary).duplicate(true)
	for key in overrides:
		if typeof(overrides[key]) == TYPE_DICTIONARY and typeof(model.get(key)) == TYPE_DICTIONARY:
			for inner in overrides[key]:
				model[key][inner] = overrides[key][inner]
		else:
			model[key] = overrides[key]
	return model

## A fresh player_state for the named loadout, built through the real
## LexiconEffects so the tomes do exactly what they do in a run.
## [param arrival_hp] (0..1) overrides the loadout's arrival health.
static func make_player(loadout_name: String, arrival_hp: float = -1.0) -> Dictionary:
	var loadout: Dictionary = config().get("loadouts", {}).get(loadout_name, {})
	var state: Dictionary = {"current_hp": 100, "max_hp": 100, "skip_tokens": 0}
	LexiconEffects.apply_to_player_state(state, {"equipped_tomes": loadout.get("tomes", [])})
	var arrival := arrival_hp if arrival_hp >= 0.0 else float(loadout.get("arrival_hp", 1.0))
	state["current_hp"] = maxi(1, int(round(float(state.max_hp) * arrival)))
	return state

#----------------------------------------------------------------------------
# PUBLIC METHODS - one fight
#----------------------------------------------------------------------------

## Plays one whole boss fight at [param depth] and returns
## { won, died, abandoned, rounds, misses, timeouts, hp_left, hp_fraction_left,
##   phase_reached, rounds_by_phase }.
## [param profile] is { recall, speed } (an archetype); [param rng] drives every
## choice the simulated player makes. [param options] can hold `model`
## (overrides laid over boss_balance.json's model, see merged_model),
## `arrival_hp` (0..1) and `grid_size` (default 5; a larger grid gives the boss a
## little more HP, as in a real run): tests and the sensitivity report use them
## to vary the assumptions.
static func fight(
	profile: Dictionary, loadout_name: String, depth: int, rng: RandomNumberGenerator,
	options: Dictionary = {}
) -> Dictionary:
	var model := merged_model(options.get("model", {}))
	var player := make_player(loadout_name, float(options.get("arrival_hp", -1.0)))
	var encounter := BossEncounter.begin(depth, int(options.get("grid_size", DEFAULT_GRID_SIZE)))
	var guard := int(model.get("max_rounds_guard", 120))
	var misses := 0
	var timeouts := 0
	var rounds_by_phase := {1: 0, 2: 0, 3: 0}
	var phase_reached := 1

	while not encounter.is_over() and encounter.rounds_played < guard:
		var phase := encounter.current_phase_index() + 1
		phase_reached = maxi(phase_reached, phase)
		rounds_by_phase[phase] = int(rounds_by_phase.get(phase, 0)) + 1
		var outcome := _play_round(encounter, player, profile, phase, model, rng)
		misses += int(outcome.misses)
		timeouts += int(outcome.timeouts)

	return {
		"won": encounter.is_won(),
		"died": encounter.player_died,
		"abandoned": encounter.abandoned or not encounter.is_over(),
		"rounds": encounter.rounds_played,
		"misses": misses,
		"timeouts": timeouts,
		"hp_left": int(player.current_hp),
		"hp_fraction_left": float(player.current_hp) / float(maxi(1, int(player.max_hp))),
		"phase_reached": phase_reached,
		"rounds_by_phase": rounds_by_phase,
	}

## Plays [param count] fights from a fixed [param seed_base] (so a result can
## be reproduced exactly) and returns the averages as
## { fights, win_rate, death_rate, avg_rounds, avg_misses, avg_timeouts,
##   avg_hp_fraction_left, phase_reached_rate: {1,2,3} }.
static func run_cell(
	profile: Dictionary, loadout_name: String, depth: int, count: int, seed_base: int,
	options: Dictionary = {}
) -> Dictionary:
	var wins := 0
	var deaths := 0
	var rounds := 0
	var misses := 0
	var timeouts := 0
	var hp_fraction := 0.0
	var reached := {1: 0, 2: 0, 3: 0}
	var rng := RandomNumberGenerator.new()
	for i in range(count):
		rng.seed = seed_base + i
		seed(seed_base + i) # BossEncounter picks round content with the global RNG
		var result := fight(profile, loadout_name, depth, rng, options)
		if bool(result.won):
			wins += 1
		if bool(result.died):
			deaths += 1
		rounds += int(result.rounds)
		misses += int(result.misses)
		timeouts += int(result.timeouts)
		hp_fraction += float(result.hp_fraction_left)
		reached[int(result.phase_reached)] = int(reached[int(result.phase_reached)]) + 1
	var n := float(maxi(1, count))
	return {
		"fights": count,
		"win_rate": wins / n,
		"death_rate": deaths / n,
		"avg_rounds": rounds / n,
		"avg_misses": misses / n,
		"avg_timeouts": timeouts / n,
		"avg_hp_fraction_left": hp_fraction / n,
		"phase_reached_rate": {1: reached[1] / n, 2: reached[2] / n, 3: reached[3] / n},
	}

#----------------------------------------------------------------------------
# PUBLIC METHODS - the person model (pure, so it is unit-testable)
#----------------------------------------------------------------------------

## The chance a simulated player knows the answer on [param attempt] (1-based)
## of a round in [param phase], given their base [param recall].
static func recall_chance(recall: float, phase: int, attempt: int, model: Dictionary) -> float:
	var multiplier := float(model.get("phase_recall_multiplier", {}).get(str(phase), 1.0))
	var chance := clampf(recall * multiplier, 0.0, 1.0)
	if attempt > 1:
		var bonus := float(model.get("reworded_clue_bonus", 0.0)) if phase == 1 else float(model.get("retry_recall_bonus", 0.0))
		chance = chance + (1.0 - chance) * clampf(bonus, 0.0, 1.0)
	return clampf(chance, 0.0, 1.0)

## Seconds a simulated player takes to answer when the clock is [param clock]
## long: their typical share of it, slower on harder prompts, varying
## log-normally. Never negative.
static func response_seconds(clock: float, speed: float, phase: int, model: Dictionary, rng: RandomNumberGenerator) -> float:
	var phase_factor := float(model.get("phase_time_multiplier", {}).get(str(phase), 1.0))
	var spread := float(model.get("time_spread", 0.0))
	return maxf(0.0, clock * speed * phase_factor * exp(rng.randfn(0.0, 1.0) * spread))

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

## Plays one round of the fight: up to max_attempts answers against a real
## CombatStateMachine. Returns { misses, timeouts }.
static func _play_round(
	encounter: BossEncounter, player: Dictionary, profile: Dictionary, phase: int,
	model: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var clue := encounter.next_round_clue()
	var timer := SimTimer.new()
	var machine := CombatStateMachine.new()
	machine.round_mode = true
	var holder: Array = []
	machine.combat_finished.connect(func(summary): holder.append(summary))
	machine.setup(clue, encounter.boss, player, timer)
	machine.begin()

	var misses := 0
	var timeouts := 0
	var attempt := 1
	var guard := 0
	while not machine.is_finished() and guard < 12:
		guard += 1
		var clock := timer.max_time
		var seconds := response_seconds(clock, float(profile.get("speed", 0.5)), phase, model, rng)
		if seconds >= clock:
			timeouts += 1
			misses += 1
			machine.force_timeout()
		else:
			timer.simulated_remaining = clock - seconds
			var answer := _answer_for(clue, profile, phase, attempt, model, rng)
			var result := machine.submit_answer(answer)
			if not bool(result.get("is_correct", false)):
				misses += 1
		attempt += 1

	if not holder.is_empty():
		encounter.finish_round(holder[0])
	else:
		# The round never reported (a bug the tests will notice): end the fight.
		encounter.abandoned = true
	timer.free()
	return {"misses": misses, "timeouts": timeouts}

## What the simulated player types for [param clue] on [param attempt].
static func _answer_for(
	clue: Dictionary, profile: Dictionary, phase: int, attempt: int,
	model: Dictionary, rng: RandomNumberGenerator
) -> String:
	if rng.randf() < float(model.get("typo_chance", 0.0)):
		return WRONG_ANSWER
	var chance := recall_chance(float(profile.get("recall", 0.5)), phase, attempt, model)
	if rng.randf() >= chance:
		return WRONG_ANSWER
	var alternates: Array = clue.get("alternates", [])
	if not alternates.is_empty() and rng.randf() >= float(model.get("archaic_known_chance", 1.0)):
		return String(alternates[0].get("answer", clue.get("answer", "")))
	return String(clue.get("answer", ""))
