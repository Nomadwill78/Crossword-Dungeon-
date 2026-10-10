#============================================================================
# TomeManager.gd
# Tomes: passive bonuses bought with Ink Drops and equipped into a small
# number of slots before a run (Design Doc 4.5, Technical Design Doc 2.5).
#
# A tome moves through four states:
#   LOCKED    - its unlock_condition (player level or achievement) is unmet
#   AVAILABLE - unlocked, not yet bought
#   OWNED     - bought, sitting in the library
#   EQUIPPED  - bought and slotted for the next run
#
# State lives in the `lexicon` Dictionary the caller passes in:
#   lexicon.unlocked_tomes - ids of owned tomes
#   lexicon.equipped_tomes - one entry per slot, a tome id or null
# Dependencies: LexiconData, InkDropManager, EventBus
# Events: tome_purchased, tome_equipped
#============================================================================

class_name TomeManager
extends RefCounted

enum TomeState { LOCKED, AVAILABLE, OWNED, EQUIPPED }

#----------------------------------------------------------------------------
# PUBLIC METHODS - queries
#----------------------------------------------------------------------------

## Where [param tome_id] is in its life cycle. Unknown ids are LOCKED.
static func tome_state(lexicon: Dictionary, profile: Dictionary, tome_id: String) -> int:
	var tome := LexiconData.get_tome(tome_id)
	if tome.is_empty():
		return TomeState.LOCKED
	if is_equipped(lexicon, tome_id):
		return TomeState.EQUIPPED
	if is_owned(lexicon, tome_id):
		return TomeState.OWNED
	return TomeState.AVAILABLE if unlock_condition_met(lexicon, profile, tome) else TomeState.LOCKED

## True when the tome has been bought.
static func is_owned(lexicon: Dictionary, tome_id: String) -> bool:
	return Array(lexicon.get("unlocked_tomes", [])).has(tome_id)

## True when the tome is in any slot.
static func is_equipped(lexicon: Dictionary, tome_id: String) -> bool:
	return Array(lexicon.get("equipped_tomes", [])).has(tome_id)

## True when [param tome]'s unlock_condition is satisfied. An unknown
## condition type fails closed (the tome stays locked) with a warning.
static func unlock_condition_met(lexicon: Dictionary, profile: Dictionary, tome: Dictionary) -> bool:
	var condition: Dictionary = tome.get("unlock_condition", {})
	match String(condition.get("type", "")):
		"":
			return true
		"player_level":
			return int(profile.get("player_level", 1)) >= int(condition.get("value", 1))
		"achievement":
			return bool(lexicon.get("achievements", {}).get(String(condition.get("value", "")), false))
	push_warning("TomeManager: unknown unlock_condition type '%s' on %s" % [condition.get("type", ""), tome.get("tome_id", "?")])
	return false

## Human-readable form of an unlock condition, for the Lexicon UI.
static func describe_condition(tome: Dictionary) -> String:
	var condition: Dictionary = tome.get("unlock_condition", {})
	match String(condition.get("type", "")):
		"player_level":
			return "Reach level %d" % int(condition.get("value", 1))
		"achievement":
			var achievement := LexiconData.get_achievement(String(condition.get("value", "")))
			return "Earn \"%s\"" % String(achievement.get("name", condition.get("value", "?")))
	return ""

## The equipped tomes as full tome Dictionaries, slot order, empties skipped.
static func equipped_tomes(lexicon: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tome_id in lexicon.get("equipped_tomes", []):
		if tome_id == null:
			continue
		var tome := LexiconData.get_tome(String(tome_id))
		if not tome.is_empty():
			out.append(tome)
	return out

## Every effect from the equipped tomes, each tagged with a `source`.
static func effects(lexicon: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tome in equipped_tomes(lexicon):
		for effect in tome.get("effects", []):
			var entry: Dictionary = (effect as Dictionary).duplicate(true)
			entry["source"] = String(tome.get("tome_id", ""))
			out.append(entry)
	return out

#----------------------------------------------------------------------------
# PUBLIC METHODS - buying and equipping
#----------------------------------------------------------------------------

## Whether [param tome_id] can be bought now.
## Returns { ok, reason } with reason one of
## "" | "unknown_tome" | "already_owned" | "locked" | "insufficient_ink".
static func can_buy(lexicon: Dictionary, profile: Dictionary, tome_id: String) -> Dictionary:
	var tome := LexiconData.get_tome(tome_id)
	if tome.is_empty():
		return { "ok": false, "reason": "unknown_tome" }
	if is_owned(lexicon, tome_id):
		return { "ok": false, "reason": "already_owned" }
	if not unlock_condition_met(lexicon, profile, tome):
		return { "ok": false, "reason": "locked" }
	if not InkDropManager.can_afford(profile, int(tome.get("cost", 0))):
		return { "ok": false, "reason": "insufficient_ink" }
	return { "ok": true, "reason": "" }

## Buys [param tome_id], adding it to the library (not to a slot). Returns
## { ok, reason, cost }; on failure nothing has changed.
static func buy(lexicon: Dictionary, profile: Dictionary, tome_id: String) -> Dictionary:
	var verdict := can_buy(lexicon, profile, tome_id)
	if not bool(verdict.ok):
		verdict["cost"] = 0
		return verdict

	var cost := int(LexiconData.get_tome(tome_id).get("cost", 0))
	if not InkDropManager.spend(profile, cost, tome_id):
		return { "ok": false, "reason": "insufficient_ink", "cost": 0 }

	if not lexicon.has("unlocked_tomes"):
		lexicon["unlocked_tomes"] = []
	var owned: Array = lexicon["unlocked_tomes"]
	owned.append(tome_id)
	EventBus.tome_purchased.emit(tome_id)
	return { "ok": true, "reason": "", "cost": cost }

## Equips an owned tome. With [param slot] -1 it takes the first empty slot;
## with an explicit slot it replaces whatever is there.
## Returns { ok, reason, slot } with reason one of
## "" | "not_owned" | "already_equipped" | "bad_slot" | "no_free_slot".
static func equip(lexicon: Dictionary, tome_id: String, slot: int = -1) -> Dictionary:
	if not is_owned(lexicon, tome_id):
		return { "ok": false, "reason": "not_owned", "slot": -1 }
	if is_equipped(lexicon, tome_id):
		return { "ok": false, "reason": "already_equipped", "slot": -1 }

	var slots: Array = lexicon.get("equipped_tomes", [])
	if slot == -1:
		slot = slots.find(null)
		if slot == -1:
			return { "ok": false, "reason": "no_free_slot", "slot": -1 }
	elif slot < 0 or slot >= slots.size():
		return { "ok": false, "reason": "bad_slot", "slot": slot }

	slots[slot] = tome_id
	EventBus.tome_equipped.emit(slot, tome_id)
	return { "ok": true, "reason": "", "slot": slot }

## Empties [param slot]. Returns false for a bad or already-empty slot.
static func unequip(lexicon: Dictionary, slot: int) -> bool:
	var slots: Array = lexicon.get("equipped_tomes", [])
	if slot < 0 or slot >= slots.size() or slots[slot] == null:
		return false
	slots[slot] = null
	EventBus.tome_equipped.emit(slot, "")
	return true
