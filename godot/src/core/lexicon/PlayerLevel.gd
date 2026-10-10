#============================================================================
# PlayerLevel.gd
# The 1-50 player level (Design Doc 5.2). Level is a pure function of the
# total Ink Drops ever collected - spending Ink never costs you a level - and
# the curve, the cap and the unlock list all live in game_config.json under
# `progression`.
# Dependencies: LexiconData, ConfigLoader, Constants
# Events: none
#============================================================================

class_name PlayerLevel
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## The level cap.
static func max_level() -> int:
	return int(LexiconData.progression().get("max_level", 50))

## Total Ink Drops that must have been collected to reach [param level].
## Level 1 needs none.
static func ink_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var curve: Dictionary = LexiconData.progression().get("level_curve", {})
	var base := float(curve.get("base_ink", 40))
	var exponent := float(curve.get("exponent", 1.6))
	return int(round(base * pow(float(level - 1), exponent)))

## The level reached after collecting [param total_ink] Ink Drops, capped at
## max_level().
static func level_for_ink(total_ink: int) -> int:
	var level := 1
	for candidate in range(2, max_level() + 1):
		if total_ink >= ink_for_level(candidate):
			level = candidate
		else:
			break
	return level

## Progress through the current level, for the Lexicon's level bar.
## Returns { level, ink_into_level, ink_for_next, fraction, is_max }.
static func progress(total_ink: int) -> Dictionary:
	var level := level_for_ink(total_ink)
	if level >= max_level():
		return { "level": level, "ink_into_level": 0, "ink_for_next": 0, "fraction": 1.0, "is_max": true }

	var floor_ink := ink_for_level(level)
	var span := ink_for_level(level + 1) - floor_ink
	var into := total_ink - floor_ink
	return {
		"level": level,
		"ink_into_level": into,
		"ink_for_next": span,
		"fraction": clampf(float(into) / float(maxi(1, span)), 0.0, 1.0),
		"is_max": false,
	}

## Every level unlock from game_config.json, lowest level first.
static func unlocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in LexiconData.progression().get("level_unlocks", []):
		out.append((entry as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return int(a.get("level", 0)) < int(b.get("level", 0)))
	return out

## True when the feature [param unlock_id] is available at [param level].
## An unknown id is treated as locked rather than free.
static func is_unlocked(unlock_id: String, level: int) -> bool:
	for entry in unlocks():
		if String(entry.get("unlock_id", "")) == unlock_id:
			return level >= int(entry.get("level", 0))
	return false

## Unlocks first reached by climbing from [param old_level] to
## [param new_level] (exclusive of old, inclusive of new).
static func unlocks_gained(old_level: int, new_level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in unlocks():
		var at := int(entry.get("level", 0))
		if at > old_level and at <= new_level:
			out.append(entry)
	return out

## Every grid size the game supports (grid.supported_sizes), smallest first,
## whether or not the player has unlocked it.
static func supported_grid_sizes() -> Array[int]:
	var config: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var out: Array[int] = []
	for size in config.get("grid", {}).get("supported_sizes", [5]):
		out.append(int(size))
	out.sort()
	return out

## Grid sizes the player may pick at [param level], smallest first, gated by
## progression.grid_size_unlocks. Never empty: the default size is always
## offered.
static func available_grid_sizes(level: int) -> Array[int]:
	var gates: Dictionary = LexiconData.progression().get("grid_size_unlocks", {})
	var out: Array[int] = []
	for size in supported_grid_sizes():
		var gate := String(gates.get(str(size), ""))
		if gate == "" or is_unlocked(gate, level):
			out.append(size)
	if out.is_empty():
		out.append(int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("grid", {}).get("default_size", 5)))
	return out
