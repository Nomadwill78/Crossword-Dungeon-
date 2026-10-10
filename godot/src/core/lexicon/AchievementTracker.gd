#============================================================================
# AchievementTracker.gd
# The Trophy Room's rules (Design Doc 4.5): decides which achievements a
# player has just earned and pays their Ink Drop rewards. Achievement
# definitions and their conditions live in data/lexicon/achievements.json.
#
# Awarding Ink can itself level the player up and satisfy a level-based
# achievement, so evaluate() keeps passing over the list until a pass earns
# nothing new.
# Dependencies: LexiconData, VocabularyTree, InkDropManager, EventBus
# Events: achievement_unlocked
#============================================================================

class_name AchievementTracker
extends RefCounted

## Upper bound on re-evaluation passes. Each pass must earn at least one
## achievement to trigger the next, so this is only a backstop against a
## malformed data file.
const MAX_PASSES: int = 8

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Earns every achievement whose condition now holds.
##
## [param profile] Player profile (level and run counters are read from it;
##                 reward Ink is added to it)
## [param lexicon] Lexicon state; `achievements` is updated in place
## [param statistics] Lifetime statistics Dictionary
## [param last_run] Facts about the run that just ended, or {} outside a
##                  run end: { completed: bool, duration_seconds: float }
## [return] The newly earned achievements: [{ id, name, reward_ink }]
static func evaluate(
	profile: Dictionary,
	lexicon: Dictionary,
	statistics: Dictionary,
	last_run: Dictionary = {}
) -> Array[Dictionary]:
	var earned: Array[Dictionary] = []
	if not lexicon.has("achievements"):
		lexicon["achievements"] = {}
	var flags: Dictionary = lexicon["achievements"]

	for pass_index in range(MAX_PASSES):
		var found_any := false
		for achievement in LexiconData.get_achievements():
			var id := String(achievement.get("achievement_id", ""))
			if id == "" or bool(flags.get(id, false)):
				continue
			if not _condition_met(achievement.get("condition", {}), profile, lexicon, statistics, last_run):
				continue

			flags[id] = true
			found_any = true
			var reward := int(achievement.get("reward_ink", 0))
			InkDropManager.award(profile, reward, "achievement:%s" % id)
			EventBus.achievement_unlocked.emit(id)
			earned.append({
				"id": id,
				"name": String(achievement.get("name", id)),
				"reward_ink": reward,
			})
		if not found_any:
			break
	return earned

## True if [param achievement_id] has already been earned.
static func is_earned(lexicon: Dictionary, achievement_id: String) -> bool:
	return bool(lexicon.get("achievements", {}).get(achievement_id, false))

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _condition_met(
	condition: Dictionary,
	profile: Dictionary,
	lexicon: Dictionary,
	statistics: Dictionary,
	last_run: Dictionary
) -> bool:
	match String(condition.get("type", "")):
		"stat_at_least":
			var stat := String(condition.get("stat", ""))
			var value: float = float(profile.get(stat, statistics.get(stat, 0)))
			return value >= float(condition.get("value", 0))
		"run_completed_faster_than":
			return (
				bool(last_run.get("completed", false))
				and float(last_run.get("duration_seconds", INF)) < float(condition.get("value", 0))
			)
		"tree_fully_purchased":
			for tree_id in LexiconData.tree_ids():
				if VocabularyTree.is_tree_complete(lexicon, tree_id):
					return true
			return false
		"player_level":
			return int(profile.get("player_level", 1)) >= int(condition.get("value", 1))
	push_warning("AchievementTracker: unknown condition type '%s'" % condition.get("type", ""))
	return false
