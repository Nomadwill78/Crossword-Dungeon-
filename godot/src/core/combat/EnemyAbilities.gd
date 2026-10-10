#============================================================================
# EnemyAbilities.gd
# The special abilities of the five regular enemies (Design Doc 4.4,
# Technical Design Doc 2.3). The abilities themselves are data in
# enemies_master.json (`special_ability`: trigger, cooldown, unlock depth and
# an `effect.mode`); this class decides when one is live and implements what
# each mode does to the encounter. CombatStateMachine calls it at the moments
# each trigger names.
#
#   enemy      trigger               mode                  what happens
#   Anagram    player_takes_damage   swap_solved_letters   two solved grid letters swap
#   Palindrome on_attempt            reverse_answer        the next answer is reversed
#   Homophone  on_clue_reveal        mishear               the clue text is garbled
#   Acronym    on_attempt_failed     scale_remaining       the next attempt's clock is halved
#   Portmanteau on_clue_reveal       blend                 a second clue is merged in
#
# Cooldowns are counted in attempts against that enemy type and live in
# player_state.ability_cooldowns (per run, never saved), so a "cooldown of 3"
# on a clue-reveal ability means roughly every third encounter with that enemy.
# Dependencies: EnemyDatabase, ClueDatabase, ClueResolver, ConfigLoader
# Events: none - the state machine reports what fired
#============================================================================

class_name EnemyAbilities
extends RefCounted

const TRIGGER_ON_CLUE_REVEAL := "on_clue_reveal"
const TRIGGER_ON_ATTEMPT := "on_attempt"
const TRIGGER_ON_ATTEMPT_FAILED := "on_attempt_failed"
const TRIGGER_PLAYER_TAKES_DAMAGE := "player_takes_damage"

#----------------------------------------------------------------------------
# PUBLIC METHODS - which ability is live
#----------------------------------------------------------------------------

## The enemy's special ability if it is unlocked at the enemy's dungeon depth
## (Design Doc 4.4: depths 3, 6, 10, 15), otherwise {}. A deep copy.
static func active_ability(enemy: Dictionary) -> Dictionary:
	if not EnemyDatabase.ability_unlocked(enemy, int(enemy.get("dungeon_depth", 0))):
		return {}
	return (enemy.get("special_ability", {}) as Dictionary).duplicate(true)

static func trigger_of(ability: Dictionary) -> String:
	return String(ability.get("trigger_condition", ""))

static func mode_of(ability: Dictionary) -> String:
	return String(ability.get("effect", {}).get("mode", ""))

#----------------------------------------------------------------------------
# PUBLIC METHODS - cooldowns
#----------------------------------------------------------------------------

## True when the enemy's ability is off cooldown. A run starts with every
## ability ready.
static func is_ready(player_state: Dictionary, enemy: Dictionary) -> bool:
	return int(_cooldowns(player_state).get(String(enemy.get("id", "")), 0)) <= 0

## Puts [param ability] on cooldown for its configured number of turns.
static func start_cooldown(player_state: Dictionary, enemy: Dictionary, ability: Dictionary) -> void:
	_cooldowns(player_state)[String(enemy.get("id", ""))] = int(ability.get("cooldown_turns", 0))

## One attempt has passed against this enemy type: cool down by a turn.
static func tick(player_state: Dictionary, enemy: Dictionary) -> void:
	var cooldowns := _cooldowns(player_state)
	var id := String(enemy.get("id", ""))
	if cooldowns.has(id):
		cooldowns[id] = maxi(0, int(cooldowns[id]) - 1)

#----------------------------------------------------------------------------
# PUBLIC METHODS - effects
#----------------------------------------------------------------------------

## Palindrome's Mirror Input: the answer, normalized, read backwards.
static func reverse_answer(raw_answer: String) -> String:
	return ClueResolver.normalize(raw_answer).reverse()

## Homophone's Mishearing: replaces words with sound-alikes, then applies
## phonetic spelling rules to the rest (ability_rules.json). The clue's
## meaning stays recoverable and its answer is untouched. Returns the text
## unchanged if no rule applies.
static func mishear(text: String) -> String:
	var rules: Dictionary = ConfigLoader.load_json(Constants.ABILITY_RULES_PATH).get("mishearing", {})
	var swaps: Dictionary = rules.get("word_swaps", {})
	var phonetic: Array = rules.get("phonetic_rules", [])

	var out: Array[String] = []
	for token in text.split(" ", false):
		out.append(_mishear_token(String(token), swaps, phonetic))
	var result := " ".join(out)
	return result if result != text.strip_edges() else text

## Portmanteau's Blend: merges a second clue - same answer length, different
## answer - into the prompt, in random order, so the player cannot tell which
## is real from the length alone. Returns { text, decoy_id, decoy_answer, notice },
## or {} when no decoy exists.
static func blend(clue: Dictionary) -> Dictionary:
	var rules: Dictionary = ConfigLoader.load_json(Constants.ABILITY_RULES_PATH).get("blend", {})
	var answer := String(clue.get("answer", "")).to_upper()
	var length := int(clue.get("answer_length", clue.get("length", answer.length())))

	var decoys: Array = []
	for candidate in ClueDatabase.get_all_clues():
		if String(candidate.get("answer", "")).to_upper() != answer and int(candidate.get("length", 0)) == length:
			decoys.append(candidate)
	if decoys.is_empty():
		return {}

	var decoy: Dictionary = decoys[randi() % decoys.size()]
	var real_text := String(clue.get("clue_text", clue.get("clue", "")))
	var decoy_text := String(decoy.get("clue", ""))
	var parts: Array[String] = [real_text, decoy_text]
	if randi() % 2 == 0:
		parts.reverse()
	return {
		"text": String(rules.get("separator", "  ...or...  ")).join(parts),
		"decoy_id": String(decoy.get("id", "")),
		"decoy_answer": String(decoy.get("answer", "")),
		"notice": String(rules.get("notice", "")),
	}

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _cooldowns(player_state: Dictionary) -> Dictionary:
	if not player_state.has("ability_cooldowns"):
		player_state["ability_cooldowns"] = {}
	return player_state["ability_cooldowns"]

static func _mishear_token(token: String, swaps: Dictionary, phonetic: Array) -> String:
	# Peel punctuation off both ends so "fear," still matches "fear".
	var start := 0
	var end := token.length()
	while start < end and not _is_letter(token[start]):
		start += 1
	while end > start and not _is_letter(token[end - 1]):
		end -= 1
	if start >= end:
		return token

	var prefix := token.substr(0, start)
	var core := token.substr(start, end - start)
	var suffix := token.substr(end)
	var lower := core.to_lower()

	var replaced := lower
	if swaps.has(lower):
		replaced = String(swaps[lower])
	else:
		for rule in phonetic:
			replaced = replaced.replace(String(rule[0]), String(rule[1]))

	if replaced == lower:
		return token
	# Keep a leading capital.
	if core[0] != core[0].to_lower():
		replaced = replaced[0].to_upper() + replaced.substr(1)
	return prefix + replaced + suffix

static func _is_letter(ch: String) -> bool:
	var lower := ch.to_lower()
	return lower >= "a" and lower <= "z"
