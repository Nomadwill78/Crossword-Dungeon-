#============================================================================
# CombatEngine.gd
# Damage resolution for a single combat attempt. Implements the damage
# formula from Technical Design Doc section 3.2.
# Dependencies: ClueResolver, WordProperties, TimerSystem, ConfigLoader
# Events: none - CombatStateMachine emits from the returned result
#============================================================================

class_name CombatEngine
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Resolves one submitted answer end to end: validates it, then either
## computes damage dealt (correct) or damage taken (wrong / timed out).
##
## This is the entry point gameplay should call. `calculate_damage` below is
## the pure formula and assumes the answer is already known-correct.
##
## [param raw_answer] Whatever the player typed ("" for a timeout)
## [param clue] Clue Dictionary from ClueDatabase
## [param enemy] Runtime enemy state from EnemyDatabase.build_encounter
## [param player_state] Player state (hp, multipliers); see _get_* helpers
## [param attempt_number] 1-based attempt counter
## [param time_remaining] Seconds left when submitted (0.0 on timeout)
## [param timed_out] True when the timer expired rather than the player
##                   submitting
## [return] Dictionary with damage_dealt, damage_taken, is_correct,
##          is_first_attempt, enemy_defeated, weakness_hit, resistance_hit
static func resolve_attempt(
	raw_answer: String,
	clue: Dictionary,
	enemy: Dictionary,
	player_state: Dictionary,
	attempt_number: int,
	time_remaining: float,
	timed_out: bool = false
) -> Dictionary:
	var verdict := ClueResolver.validate(raw_answer, clue)

	if verdict.is_correct and not timed_out:
		var result := calculate_damage(raw_answer, clue, enemy, player_state, attempt_number, time_remaining)
		result["timed_out"] = false
		return result

	# Wrong answer or timeout: no damage dealt, the enemy strikes back.
	return {
		"damage_dealt": 0,
		"damage_taken": calculate_enemy_damage(enemy, player_state),
		"is_correct": false,
		"is_first_attempt": attempt_number == 1,
		"enemy_defeated": false,
		"weakness_hit": false,
		"resistance_hit": false,
		"timed_out": timed_out,
		"answer": verdict.normalized,
	}

## Calculates damage dealt for a CORRECT answer.
##
## Formula (Technical Design Doc 3.2), applied in order:
##   base-by-length -> difficulty -> first attempt -> time -> vocabulary
##   category -> tome -> chain buff -> enemy weakness/resistance
##
## [param answer] The player's (correct) answer
## [param clue] The clue Dictionary
## [param enemy] Runtime enemy state, including current_hp
## [param player_state] Player state dictionary
## [param attempt_number] Which attempt this is (1 = first)
## [param time_remaining] Seconds left on the timer
## [return] Dictionary with damage_dealt, damage_taken, is_correct, etc.
static func calculate_damage(
	answer: String,
	clue: Dictionary,
	enemy: Dictionary,
	player_state: Dictionary,
	attempt_number: int,
	time_remaining: float
) -> Dictionary:
	var normalized := ClueResolver.normalize(answer)
	var length := normalized.length()

	var result := {
		"damage_dealt": 0,
		"damage_taken": 0,
		"is_correct": true,
		"is_first_attempt": attempt_number == 1,
		"enemy_defeated": false,
		"weakness_hit": false,
		"resistance_hit": false,
		"answer": normalized,
	}

	var combat_cfg: Dictionary = _combat_config()
	var total_base_damage := get_base_damage_per_letter(length) * length
	var multipliers := 1.0

	# Harder clues hit harder.
	var difficulty: int = int(clue.get("difficulty", 1))
	multipliers *= 1.0 + (difficulty * float(combat_cfg.get("difficulty_bonus_per_level", 0.1)))

	# Reward getting it right the first time.
	if attempt_number == 1:
		multipliers *= float(combat_cfg.get("first_attempt_multiplier", 1.25))

	# Reward answering fast.
	var base_timer := TimerSystem.base_seconds_for_difficulty(difficulty)
	var time_ratio := 0.0 if base_timer <= 0.0 else time_remaining / base_timer
	multipliers *= clampf(
		1.0 + (time_ratio * float(combat_cfg.get("time_bonus_scale", 0.5))),
		float(combat_cfg.get("time_bonus_min", 1.0)),
		float(combat_cfg.get("time_bonus_max", 2.0))
	)

	# Meta-progression multipliers. These read player_state and default to 1.0
	# while the Lexicon (Milestone 3) has not populated them yet.
	multipliers *= get_category_multiplier(String(clue.get("category", "")), player_state)
	multipliers *= get_tome_multiplier("combat", player_state)
	multipliers *= get_chain_buff_multiplier(player_state)

	# Enemy weakness / resistance (data-driven, see enemies_master.json).
	if matches_weakness(normalized, enemy):
		multipliers *= float(enemy.weakness.get("bonus_multiplier", 1.0))
		result.weakness_hit = true
	elif matches_resistance(normalized, enemy):
		multipliers *= float(enemy.resistance.get("penalty_multiplier", 1.0))
		result.resistance_hit = true

	result.damage_dealt = int(floor(total_base_damage * multipliers))

	var current_hp: int = int(enemy.get("current_hp", enemy.get("base_hp", 0)))
	if result.damage_dealt >= current_hp:
		result.enemy_defeated = true
	else:
		# Still standing, so it counter-attacks.
		result.damage_taken = calculate_enemy_damage(enemy, player_state)

	return result

## Damage per letter for a word of [param length], per Design Doc 4.2:
## shorter words hit harder per letter, so a 3-letter answer is not strictly
## worse than a 7-letter one.
static func get_base_damage_per_letter(length: int) -> int:
	var table: Dictionary = _combat_config().get("base_damage_by_length", {})
	var key := str(length)
	if table.has(key):
		return int(table[key])
	return int(table.get("default", 2))

## Damage the enemy deals to the player on a failed attempt.
static func calculate_enemy_damage(enemy: Dictionary, player_state: Dictionary) -> int:
	var raw: int = int(enemy.get("damage", enemy.get("base_damage", 5)))
	var reduction := float(player_state.get("damage_reduction", 0.0))
	return maxi(0, int(floor(raw * (1.0 - reduction))))

## True when [param answer] satisfies the enemy's weakness rule. A null
## weakness (see enemies_master.json weakness_pending notes) never matches.
static func matches_weakness(answer: String, enemy: Dictionary) -> bool:
	return _matches_rule(answer, enemy.get("weakness", null))

## True when [param answer] satisfies the enemy's resistance rule.
static func matches_resistance(answer: String, enemy: Dictionary) -> bool:
	return _matches_rule(answer, enemy.get("resistance", null))

## Vocabulary-tree damage bonus for [param category]. Milestone 3 populates
## player_state.category_multipliers; until then every category is 1.0.
static func get_category_multiplier(category: String, player_state: Dictionary) -> float:
	var multipliers: Dictionary = player_state.get("category_multipliers", {})
	return float(multipliers.get(category, 1.0))

## Equipped-tome bonus for [param scope] ("combat", "combo", ...).
## Milestone 3 populates player_state.tome_multipliers.
static func get_tome_multiplier(scope: String, player_state: Dictionary) -> float:
	var multipliers: Dictionary = player_state.get("tome_multipliers", {})
	return float(multipliers.get(scope, 1.0))

## Active vocabulary-chain damage buff (Design Doc 4.3: a 3-letter chain
## grants +20% damage for the next 3 encounters). ChainEffects writes
## player_state.chain_damage_buff; 0.0 means no active buff.
static func get_chain_buff_multiplier(player_state: Dictionary) -> float:
	return 1.0 + float(player_state.get("chain_damage_buff", 0.0))

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _matches_rule(answer: String, rule) -> bool:
	if rule == null or typeof(rule) != TYPE_DICTIONARY:
		return false
	if String(rule.get("type", "")) != "word_property":
		# Only word-property rules are computable from the answer alone.
		return false
	return WordProperties.has_property(answer, String(rule.get("property", "")))

static func _combat_config() -> Dictionary:
	return ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("combat", {})
