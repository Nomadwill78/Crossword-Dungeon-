#============================================================================
# RunSettlement.gd
# Everything that happens to the persistent profile when a run ends:
# lifetime counters, the Ink Drop payout, level-ups and achievements. The
# dungeon hands over what the run produced and gets back a summary to show;
# it never edits the profile itself.
#
# The `run` argument is GameState.current_run. It carries:
#   player_state.total_ink_drops_this_run  Ink collected during the run
#   player_state.loadout                   LexiconEffects loadout (ink_multiplier)
#   tally                                  { words_solved, letters_solved,
#                                            enemies_defeated, bosses_defeated,
#                                            chains_activated, chains_by_length,
#                                            longest_chain, floors_cleared,
#                                            deepest_depth }
#   final_score                            summed over every floor cleared
#   duration_seconds                       the fastest floor (Speed Demon)
# Dependencies: InkDropManager, PlayerLevel, AchievementTracker
# Events: via InkDropManager / AchievementTracker
#============================================================================

class_name RunSettlement
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Applies a finished [param run] to [param profile], [param lexicon] and
## [param statistics], in place.
##
## Order matters: counters are updated first so "finish a run" style
## achievements see them, then Ink is paid (which may level the player up),
## then achievements are evaluated (whose own rewards may level them up
## again).
##
## [param completed] True if the dungeon was cleared, false if the player died
## [return] { completed, ink: {base, completion_bonus, tome_bonus,
##          defeat_penalty, total}, old_level, new_level, unlocks: Array,
##          achievements: Array, balance }
static func settle(
	profile: Dictionary,
	lexicon: Dictionary,
	statistics: Dictionary,
	run: Dictionary,
	completed: bool
) -> Dictionary:
	var player_state: Dictionary = run.get("player_state", {})
	var tally: Dictionary = run.get("tally", {})
	var old_level := int(profile.get("player_level", 1))

	_record_counters(profile, statistics, tally, completed, int(run.get("final_score", 0)))

	var ink := InkDropManager.settle_run_ink(
		int(player_state.get("total_ink_drops_this_run", 0)),
		completed,
		player_state.get("loadout", {})
	)
	InkDropManager.award(profile, int(ink.total), "run_end")

	var achievements := AchievementTracker.evaluate(profile, lexicon, statistics, {
		"completed": completed,
		"duration_seconds": float(run.get("duration_seconds", INF)),
	})

	var new_level := int(profile.get("player_level", 1))
	return {
		"completed": completed,
		"ink": ink,
		"old_level": old_level,
		"new_level": new_level,
		"unlocks": PlayerLevel.unlocks_gained(old_level, new_level),
		"achievements": achievements,
		"balance": int(profile.get("ink_drops", 0)),
	}

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _record_counters(
	profile: Dictionary,
	statistics: Dictionary,
	tally: Dictionary,
	completed: bool,
	score: int
) -> void:
	profile["total_runs"] = int(profile.get("total_runs", 0)) + 1
	if completed:
		profile["runs_completed"] = int(profile.get("runs_completed", 0)) + 1
	profile["best_score"] = maxi(int(profile.get("best_score", 0)), score)
	profile["total_letters_solved"] = int(profile.get("total_letters_solved", 0)) + int(tally.get("letters_solved", 0))
	profile["longest_chain"] = maxi(int(profile.get("longest_chain", 0)), int(tally.get("longest_chain", 0)))
	profile["deepest_depth"] = maxi(int(profile.get("deepest_depth", 0)), int(tally.get("deepest_depth", 0)))

	statistics["total_words_solved"] = int(statistics.get("total_words_solved", 0)) + int(tally.get("words_solved", 0))
	statistics["total_enemies_defeated"] = int(statistics.get("total_enemies_defeated", 0)) + int(tally.get("enemies_defeated", 0))
	statistics["total_bosses_defeated"] = int(statistics.get("total_bosses_defeated", 0)) + int(tally.get("bosses_defeated", 0))
	statistics["total_chains"] = int(statistics.get("total_chains", 0)) + int(tally.get("chains_activated", 0))
	statistics["total_floors_cleared"] = int(statistics.get("total_floors_cleared", 0)) + int(tally.get("floors_cleared", 0))
	if not completed:
		statistics["total_deaths"] = int(statistics.get("total_deaths", 0)) + 1

	if not statistics.has("chains_by_length") or typeof(statistics["chains_by_length"]) != TYPE_DICTIONARY:
		statistics["chains_by_length"] = {}
	var by_length: Dictionary = statistics["chains_by_length"]
	var run_by_length: Dictionary = tally.get("chains_by_length", {})
	for length in run_by_length:
		var key := str(length)
		by_length[key] = int(by_length.get(key, 0)) + int(run_by_length[length])
