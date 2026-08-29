#============================================================================
# ChainEffects.gd
# Turns a detected chain into its reward (Design Doc 4.3). Tier definitions
# live in game_config.json under `chains.tiers`, so re-tuning which word
# length grants which effect is a data edit, not a code edit.
# Dependencies: ConfigLoader, Constants
# Events: none - the caller emits chain_activated with the returned effect
#============================================================================

class_name ChainEffects
extends RefCounted

## Effects this class applies directly to player_state.
const PLAYER_SCOPED: Array[String] = ["damage_buff", "heal", "double_rewards"]

## Effects that act on the dungeon grid, so the caller (DungeonScene, which
## owns the GridNavigator) has to carry them out.
const GRID_SCOPED: Array[String] = ["reveal_letter", "skip_encounter", "clear_line"]

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## The effect earned by a chain of [param chain_length] letters, or an empty
## Dictionary if the chain is too short to earn anything.
##
## Tiers are matched highest-first, so an 8-letter chain gets the 8+ reward
## rather than the 3-letter one.
static func effect_for_length(chain_length: int) -> Dictionary:
	for tier in _tiers():
		if chain_length >= int(tier.get("min_length", 0)):
			var effect: Dictionary = tier.duplicate(true)
			effect["chain_length"] = chain_length
			effect["scope"] = "grid" if GRID_SCOPED.has(String(effect.get("effect", ""))) else "player"
			return effect
	return {}

## Convenience: the effect for a chain Dictionary from ChainDetector.
static func effect_for_chain(chain: Dictionary) -> Dictionary:
	return effect_for_length(int(chain.get("length", 0)))

## Applies a player-scoped [param effect] to [param player_state] in place.
##
## Returns a summary Dictionary describing what actually changed, so the UI
## can report it ("Healed 15 HP", "+20% damage for 3 encounters") without
## re-deriving the numbers. Grid-scoped effects are left for the caller and
## come back with applied = false.
static func apply(effect: Dictionary, player_state: Dictionary) -> Dictionary:
	var kind := String(effect.get("effect", ""))
	var magnitude := float(effect.get("magnitude", 0.0))

	match kind:
		"damage_buff":
			# Buffs stack additively and share one encounter counter; the
			# longest remaining duration wins.
			player_state["chain_damage_buff"] = float(player_state.get("chain_damage_buff", 0.0)) + magnitude
			var duration := int(effect.get("duration_encounters", 3))
			player_state["chain_damage_buff_encounters"] = maxi(
				int(player_state.get("chain_damage_buff_encounters", 0)), duration
			)
			return {
				"applied": true,
				"kind": kind,
				"amount": magnitude,
				"encounters": player_state["chain_damage_buff_encounters"],
			}

		"heal":
			var max_hp: int = int(player_state.get("max_hp", 100))
			var before: int = int(player_state.get("current_hp", max_hp))
			var healed: int = int(round(max_hp * magnitude))
			var after: int = mini(max_hp, before + healed)
			player_state["current_hp"] = after
			return { "applied": true, "kind": kind, "amount": after - before }

		"double_rewards":
			player_state["reward_multiplier"] = maxf(
				float(player_state.get("reward_multiplier", 1.0)), magnitude
			)
			player_state["reward_multiplier_encounters"] = maxi(
				int(player_state.get("reward_multiplier_encounters", 0)), 1
			)
			return { "applied": true, "kind": kind, "amount": magnitude }

	if GRID_SCOPED.has(kind):
		return { "applied": false, "kind": kind, "reason": "grid_scoped" }

	if kind != "":
		push_warning("ChainEffects: unknown effect '%s'" % kind)
	return { "applied": false, "kind": kind, "reason": "unknown" }

## Ticks down per-encounter chain buffs. Call once when an encounter ends.
static func expire_buffs(player_state: Dictionary) -> void:
	var encounters_left := int(player_state.get("chain_damage_buff_encounters", 0))
	if encounters_left > 0:
		encounters_left -= 1
		player_state["chain_damage_buff_encounters"] = encounters_left
		if encounters_left == 0:
			player_state["chain_damage_buff"] = 0.0

	var reward_left := int(player_state.get("reward_multiplier_encounters", 0))
	if reward_left > 0:
		reward_left -= 1
		player_state["reward_multiplier_encounters"] = reward_left
		if reward_left == 0:
			player_state["reward_multiplier"] = 1.0

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

## Tiers sorted longest-first so effect_for_length can take the first match.
static func _tiers() -> Array:
	var chains_cfg: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("chains", {})
	var tiers: Array = chains_cfg.get("tiers", []).duplicate(true)
	tiers.sort_custom(func(a, b): return int(a.get("min_length", 0)) > int(b.get("min_length", 0)))
	return tiers
