#============================================================================
# test_tome_manager.gd
# Tome life cycle: locked -> available -> owned -> equipped, slot rules, and
# the signals fired along the way.
#============================================================================

class_name TestTomeManager
extends TestSuite

func _init() -> void:
	suite_name = "TomeManager"

func run(_host: Node) -> void:
	_test_states_and_conditions()
	_test_buying()
	_test_equipping()
	_test_effects_and_signals()

func _profile_at_level(level: int, ink: int = 10000) -> Dictionary:
	var profile := GameState.default_profile()
	profile["player_level"] = level
	profile["ink_drops"] = ink
	profile["total_ink_drops"] = ink
	return profile

func _test_states_and_conditions() -> void:
	var lexicon := LexiconState.default_state()
	assert_eq(TomeManager.tome_state(lexicon, _profile_at_level(1), "tome_healing_01"), TomeManager.TomeState.LOCKED, "a level-gated tome is locked below its level")
	assert_eq(TomeManager.tome_state(lexicon, _profile_at_level(3), "tome_healing_01"), TomeManager.TomeState.AVAILABLE, "and available at its level")
	assert_eq(TomeManager.tome_state(lexicon, _profile_at_level(50), "tome_damage_01"), TomeManager.TomeState.LOCKED, "an achievement-gated tome ignores level")

	lexicon.achievements["first_chain"] = true
	assert_eq(TomeManager.tome_state(lexicon, _profile_at_level(1), "tome_damage_01"), TomeManager.TomeState.AVAILABLE, "earning the achievement makes it available")
	assert_eq(TomeManager.tome_state(lexicon, _profile_at_level(50), "tome_nope"), TomeManager.TomeState.LOCKED, "an unknown tome reads as locked")

	assert_eq(TomeManager.describe_condition(LexiconData.get_tome("tome_healing_01")), "Reach level 3", "a level condition reads naturally")
	assert_true(TomeManager.describe_condition(LexiconData.get_tome("tome_damage_01")).contains("Linked Letters"), "an achievement condition names the achievement")

func _test_buying() -> void:
	var lexicon := LexiconState.default_state()
	var profile := _profile_at_level(3, 1000)
	var cost := int(LexiconData.get_tome("tome_healing_01").cost)

	var locked := TomeManager.buy(lexicon, _profile_at_level(1, 1000), "tome_healing_01")
	assert_eq(String(locked.reason), "locked", "a locked tome cannot be bought")

	var unknown := TomeManager.buy(lexicon, profile, "tome_nope")
	assert_eq(String(unknown.reason), "unknown_tome", "an unknown tome is rejected")

	var poor := TomeManager.buy(lexicon, _profile_at_level(3, cost - 1), "tome_healing_01")
	assert_eq(String(poor.reason), "insufficient_ink", "one Ink short is refused")
	assert_false(TomeManager.is_owned(lexicon, "tome_healing_01"), "a refused buy grants nothing")

	var bought := TomeManager.buy(lexicon, profile, "tome_healing_01")
	assert_true(bool(bought.ok), "an unlocked, affordable tome can be bought")
	assert_eq(int(profile.ink_drops), 1000 - cost, "buying spends its cost")
	assert_eq(int(profile.total_ink_drops), 1000, "buying never lowers lifetime Ink")
	assert_true(TomeManager.is_owned(lexicon, "tome_healing_01"), "the tome joins the library")
	assert_false(TomeManager.is_equipped(lexicon, "tome_healing_01"), "but is not auto-equipped")
	assert_eq(TomeManager.tome_state(lexicon, profile, "tome_healing_01"), TomeManager.TomeState.OWNED, "state reads OWNED")

	var again := TomeManager.buy(lexicon, profile, "tome_healing_01")
	assert_eq(String(again.reason), "already_owned", "a tome cannot be bought twice")
	assert_eq(int(profile.ink_drops), 1000 - cost, "and is not charged twice")

func _own(lexicon: Dictionary, tome_ids: Array) -> void:
	for tome_id in tome_ids:
		lexicon.unlocked_tomes.append(tome_id)

func _test_equipping() -> void:
	var lexicon := LexiconState.default_state()
	assert_eq((lexicon.equipped_tomes as Array).size(), 3, "there are three tome slots")

	assert_eq(String(TomeManager.equip(lexicon, "tome_healing_01").reason), "not_owned", "an unowned tome cannot be equipped")

	_own(lexicon, ["tome_healing_01", "tome_damage_01", "tome_timer_01", "tome_ink_01"])
	var first := TomeManager.equip(lexicon, "tome_healing_01")
	assert_true(bool(first.ok), "an owned tome equips")
	assert_eq(int(first.slot), 0, "into the first free slot")
	assert_eq(String(TomeManager.equip(lexicon, "tome_healing_01").reason), "already_equipped", "a tome cannot fill two slots")

	assert_eq(int(TomeManager.equip(lexicon, "tome_damage_01").slot), 1, "the next tome takes the next slot")
	assert_eq(int(TomeManager.equip(lexicon, "tome_timer_01").slot), 2, "and the next")
	var full := TomeManager.equip(lexicon, "tome_ink_01")
	assert_eq(String(full.reason), "no_free_slot", "a full loadout refuses an automatic equip")

	var swapped := TomeManager.equip(lexicon, "tome_ink_01", 1)
	assert_true(bool(swapped.ok), "an explicit slot replaces its occupant")
	assert_eq(lexicon.equipped_tomes, ["tome_healing_01", "tome_ink_01", "tome_timer_01"], "the replaced tome is out, the new one is in")
	assert_true(TomeManager.is_owned(lexicon, "tome_damage_01"), "the replaced tome stays owned")
	assert_eq(String(TomeManager.equip(lexicon, "tome_damage_01", 9).reason), "bad_slot", "an out-of-range slot is rejected")
	assert_eq(String(TomeManager.equip(lexicon, "tome_damage_01", -2).reason), "bad_slot", "a negative slot other than -1 is rejected")

	assert_true(TomeManager.unequip(lexicon, 0), "unequip empties a slot")
	assert_eq(lexicon.equipped_tomes[0], null, "the slot is null")
	assert_false(TomeManager.unequip(lexicon, 0), "unequipping an empty slot reports false")
	assert_false(TomeManager.unequip(lexicon, 7), "unequipping a bad slot reports false")
	assert_eq(int(TomeManager.equip(lexicon, "tome_damage_01").slot), 0, "a freed slot is reused")

func _test_effects_and_signals() -> void:
	var lexicon := LexiconState.default_state()
	_own(lexicon, ["tome_healing_01", "tome_damage_01"])
	assert_eq(TomeManager.effects(lexicon).size(), 0, "owned but unequipped tomes grant nothing")
	assert_eq(TomeManager.equipped_tomes(lexicon).size(), 0, "no equipped tomes yet")

	var equipped_log: Array = []
	var bought_log: Array = []
	var on_equipped := func(slot: int, tome_id: String): equipped_log.append([slot, tome_id])
	var on_bought := func(tome_id: String): bought_log.append(tome_id)
	EventBus.tome_equipped.connect(on_equipped)
	EventBus.tome_purchased.connect(on_bought)

	TomeManager.equip(lexicon, "tome_damage_01")
	assert_eq(equipped_log, [[0, "tome_damage_01"]], "equipping emits tome_equipped")
	var effects := TomeManager.effects(lexicon)
	assert_eq(effects.size(), 1, "an equipped tome contributes its effect")
	assert_eq(String(effects[0].source), "tome_damage_01", "the effect names its tome")
	assert_eq(TomeManager.equipped_tomes(lexicon).size(), 1, "equipped_tomes lists it")

	TomeManager.unequip(lexicon, 0)
	assert_eq(equipped_log.back(), [0, ""], "unequipping emits an empty tome id")
	assert_eq(TomeManager.effects(lexicon).size(), 0, "an unequipped tome grants nothing again")

	var profile := _profile_at_level(10, 5000)
	TomeManager.buy(lexicon, profile, "tome_timer_01")
	TomeManager.buy(lexicon, profile, "tome_timer_01")
	assert_eq(bought_log, ["tome_timer_01"], "tome_purchased fires once, not for the refused repeat")

	EventBus.tome_equipped.disconnect(on_equipped)
	EventBus.tome_purchased.disconnect(on_bought)
