#============================================================================
# LexiconEffects.gd
# Turns what the player bought in the Lexicon into numbers a run can use.
# This is the bridge into combat: it fills in the player_state keys that
# CombatEngine, CombatStateMachine and ChainEffects already read but that
# Milestone 2 left empty (category_multipliers, tome_multipliers,
# timer_modifiers, damage_reduction, chain_duration_bonus).
#
# build_loadout() folds every purchased vocabulary node and equipped tome
# into one flat Dictionary; apply_to_player_state() stamps it onto a run's
# player_state once at run start. The remaining helpers are the per-event
# lookups the dungeon uses mid-run (healing, bonus Ink).
# Dependencies: VocabularyTree, TomeManager, LexiconData, ConfigLoader, EventBus
# Events: player_healed
#============================================================================

class_name LexiconEffects
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS - building a loadout
#----------------------------------------------------------------------------

## An empty loadout: every bonus at its neutral value.
static func neutral_loadout() -> Dictionary:
	return {
		"category_multipliers": {},
		"category_timer_bonus": {},
		"category_heal": {},
		"category_ink_bonus": {},
		"chain_duration_bonus": 0,
		"chain_ink_bonus": 0,
		"damage_reduction": 0.0,
		"max_hp_bonus": 0,
		"timer_bonus": 0.0,
		"heal_percent_on_solve": 0.0,
		"ink_multiplier": 1.0,
		"tome_multipliers": { "combat": 1.0, "combat_first_attempt": 1.0 },
	}

## Folds all purchased nodes and equipped tomes in [param lexicon] into a
## loadout. Multipliers multiply and additive bonuses add; see finalize() for
## the caps. An unknown effect type is skipped with a warning rather than
## crashing a run.
static func build_loadout(lexicon: Dictionary) -> Dictionary:
	var loadout := neutral_loadout()
	for effect in VocabularyTree.effects(lexicon):
		_accumulate_node_effect(loadout, effect)
	for effect in TomeManager.effects(lexicon):
		_accumulate_tome_effect(loadout, effect)

	finalize(loadout)
	return loadout

## Applies the limits that stop stacking from breaking the game: total damage
## reduction is clamped to progression.max_damage_reduction.
static func finalize(loadout: Dictionary) -> void:
	var cap := float(LexiconData.progression().get("max_damage_reduction", 0.75))
	loadout["damage_reduction"] = clampf(float(loadout.get("damage_reduction", 0.0)), 0.0, cap)

## Stamps [param lexicon]'s loadout onto [param player_state] for a new run.
## Raises max HP (and current HP with it) by any tome's max_hp_bonus.
## Returns the loadout so the caller can show or log it.
static func apply_to_player_state(player_state: Dictionary, lexicon: Dictionary) -> Dictionary:
	var loadout := build_loadout(lexicon)
	player_state["loadout"] = loadout
	player_state["category_multipliers"] = (loadout.category_multipliers as Dictionary).duplicate()
	player_state["tome_multipliers"] = (loadout.tome_multipliers as Dictionary).duplicate()
	player_state["category_timer_bonus"] = (loadout.category_timer_bonus as Dictionary).duplicate()
	player_state["timer_modifiers"] = { "timer_bonus": float(loadout.timer_bonus) }
	player_state["damage_reduction"] = float(loadout.damage_reduction)
	player_state["chain_duration_bonus"] = int(loadout.chain_duration_bonus)

	var hp_bonus := int(loadout.max_hp_bonus)
	if hp_bonus > 0:
		player_state["max_hp"] = int(player_state.get("max_hp", 100)) + hp_bonus
		player_state["current_hp"] = int(player_state.get("current_hp", 100)) + hp_bonus
	return loadout

#----------------------------------------------------------------------------
# PUBLIC METHODS - mid-run lookups
#----------------------------------------------------------------------------

## Heals the player for solving [param clue]: the clue category's
## heal_on_solve node bonus plus any post_combat_heal tome (a percentage of
## max HP). Mutates player_state.current_hp, never past max, and returns the
## HP actually restored.
static func heal_for_solve(player_state: Dictionary, clue: Dictionary) -> int:
	var loadout: Dictionary = player_state.get("loadout", {})
	var category := String(clue.get("category", ""))
	var max_hp := int(player_state.get("max_hp", 100))

	var flat := int((loadout.get("category_heal", {}) as Dictionary).get(category, 0))
	var percent := int(round(max_hp * float(loadout.get("heal_percent_on_solve", 0.0))))
	if flat + percent <= 0:
		return 0

	var before := int(player_state.get("current_hp", max_hp))
	var after := mini(max_hp, before + flat + percent)
	player_state["current_hp"] = after
	var healed := after - before
	if healed > 0:
		EventBus.player_healed.emit(healed, "lexicon")
	return healed

## Bonus Ink for solving [param clue]'s word: the category's ink_bonus
## (per letter) times the word's length.
static func ink_bonus_for_word(player_state: Dictionary, clue: Dictionary) -> int:
	var loadout: Dictionary = player_state.get("loadout", {})
	var per_letter := int((loadout.get("category_ink_bonus", {}) as Dictionary).get(String(clue.get("category", "")), 0))
	return per_letter * String(clue.get("answer", "")).length()

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _accumulate_node_effect(loadout: Dictionary, effect: Dictionary) -> void:
	var category := String(effect.get("category", ""))
	var value = effect.get("value", 0)
	match String(effect.get("type", "")):
		"damage_multiplier":
			var table: Dictionary = loadout.category_multipliers
			table[category] = float(table.get(category, 1.0)) * float(value)
		"timer_bonus":
			var table: Dictionary = loadout.category_timer_bonus
			table[category] = float(table.get(category, 0.0)) + float(value)
		"heal_on_solve":
			var table: Dictionary = loadout.category_heal
			table[category] = int(table.get(category, 0)) + int(value)
		"ink_bonus":
			var table: Dictionary = loadout.category_ink_bonus
			table[category] = int(table.get(category, 0)) + int(value)
		"chain_duration":
			loadout["chain_duration_bonus"] = int(loadout.chain_duration_bonus) + int(value)
		"chain_bonus":
			loadout["chain_ink_bonus"] = int(loadout.chain_ink_bonus) + int(value)
		"damage_reduction":
			loadout["damage_reduction"] = float(loadout.damage_reduction) + float(value)
		_:
			push_warning("LexiconEffects: unknown vocabulary effect '%s' from %s" % [effect.get("type", ""), effect.get("source", "?")])

static func _accumulate_tome_effect(loadout: Dictionary, effect: Dictionary) -> void:
	var value = effect.get("value", 0)
	match String(effect.get("type", "")):
		"post_combat_heal":
			loadout["heal_percent_on_solve"] = float(loadout.heal_percent_on_solve) + float(value)
		"first_attempt_bonus":
			var table: Dictionary = loadout.tome_multipliers
			table["combat_first_attempt"] = float(table.combat_first_attempt) * float(value)
		"damage_bonus":
			var table: Dictionary = loadout.tome_multipliers
			table["combat"] = float(table.combat) * float(value)
		"timer_bonus":
			loadout["timer_bonus"] = float(loadout.timer_bonus) + float(value)
		"ink_multiplier":
			loadout["ink_multiplier"] = float(loadout.ink_multiplier) * float(value)
		"max_hp_bonus":
			loadout["max_hp_bonus"] = int(loadout.max_hp_bonus) + int(value)
		"damage_reduction":
			loadout["damage_reduction"] = float(loadout.damage_reduction) + float(value)
		_:
			push_warning("LexiconEffects: unknown tome effect '%s' from %s" % [effect.get("type", ""), effect.get("source", "?")])
