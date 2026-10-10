#============================================================================
# test_lexicon_effects.gd
# The bridge from the Lexicon into a run: loadout building, the player_state
# keys it stamps, and - the point of Milestone 3 - that those keys actually
# change what CombatEngine, CombatStateMachine and ChainEffects do.
#============================================================================

class_name TestLexiconEffects
extends TestSuite

const TEST_CLUE := { "id": "clue_test", "answer": "FOREST", "category": "NATURE_ELEMENTS", "difficulty": 1 }

func _init() -> void:
	suite_name = "LexiconEffects"

func run(_host: Node) -> void:
	_test_loadout_aggregation()
	_test_apply_to_player_state()
	_test_damage_integration()
	_test_enemy_damage_reduction()
	_test_timer_integration()
	_test_chain_duration()
	_test_solve_helpers()

## A lexicon with the named nodes bought and tomes owned + equipped.
func _lexicon(node_ids: Array, tome_ids: Array = []) -> Dictionary:
	var lexicon := LexiconState.default_state()
	var profile := GameState.default_profile()
	InkDropManager.award(profile, 100000, "test")
	for node_id in node_ids:
		var verdict := VocabularyTree.purchase(lexicon, profile, String(node_id))
		assert_true(bool(verdict.ok), "fixture bought %s" % node_id)
	for tome_id in tome_ids:
		lexicon.unlocked_tomes.append(tome_id)
		TomeManager.equip(lexicon, String(tome_id))
	return lexicon

func _enemy() -> Dictionary:
	return { "id": "enemy_test", "current_hp": 100000, "base_hp": 100000, "damage": 20 }

func _test_loadout_aggregation() -> void:
	var empty := LexiconEffects.build_loadout(LexiconState.default_state())
	assert_eq(empty, LexiconEffects.neutral_loadout(), "an empty lexicon builds the neutral loadout")

	var loadout := LexiconEffects.build_loadout(_lexicon(
		["arc_01", "arc_02", "arc_03", "arc_04", "bst_01", "bst_02", "bst_03", "bst_04", "wld_01", "wld_02", "sen_01", "sen_02", "sen_03"]
	))
	var multipliers: Dictionary = loadout.category_multipliers
	assert_approx(float(multipliers.MAGIC_ARCANE), 1.1 * 1.15, "two arcane damage nodes multiply")
	assert_approx(float(multipliers.FANTASY_CREATURES), 1.1, "a single node gives its multiplier")
	assert_approx(float((loadout.category_timer_bonus as Dictionary).MAGIC_ARCANE), 5.0, "timer bonuses are per category")
	assert_approx(float((loadout.category_timer_bonus as Dictionary).EMOTIONS_ABSTRACT), 5.0, "including Calm Mind")
	assert_eq(int((loadout.category_heal as Dictionary).NATURE_ELEMENTS), 5, "Wild Remedy heals on nature answers")
	assert_eq(int((loadout.category_ink_bonus as Dictionary).FANTASY_CREATURES), 1, "Slayer's Spoils adds Ink for creature answers")
	assert_eq(int(loadout.chain_duration_bonus), 1, "Lingering Spell extends chain buffs")
	assert_eq(int(loadout.chain_ink_bonus), 10, "Resonance adds chain Ink")
	assert_approx(float(loadout.damage_reduction), 0.1, "Thick Hide reduces damage")

	var tomed := LexiconEffects.build_loadout(_lexicon([], [
		"tome_healing_01", "tome_damage_01", "tome_timer_01",
	]))
	assert_approx(float(tomed.heal_percent_on_solve), 0.05, "Restoration heals 5% of max HP")
	assert_approx(float((tomed.tome_multipliers as Dictionary).combat_first_attempt), 1.15, "Precision boosts first attempts")
	assert_approx(float((tomed.tome_multipliers as Dictionary).combat), 1.0, "and leaves ordinary damage alone")
	assert_approx(float(tomed.timer_bonus), 5.0, "Patience adds seconds to every clock")

	var capped := LexiconEffects.neutral_loadout()
	capped["damage_reduction"] = 0.99
	LexiconEffects.finalize(capped)
	assert_approx(float(capped.damage_reduction), float(LexiconData.progression().max_damage_reduction), "stacked damage reduction is capped")
	capped["damage_reduction"] = -0.2
	LexiconEffects.finalize(capped)
	assert_approx(float(capped.damage_reduction), 0.0, "and never negative")

func _test_apply_to_player_state() -> void:
	var player_state := { "current_hp": 100, "max_hp": 100 }
	var lexicon := _lexicon(["bst_01", "bst_02", "bst_03", "bst_04"], ["tome_vitality_01", "tome_timer_01"])
	var loadout := LexiconEffects.apply_to_player_state(player_state, lexicon)

	assert_eq(int(player_state.max_hp), 125, "Vigor raises max HP")
	assert_eq(int(player_state.current_hp), 125, "and the player starts the run at full health")
	assert_approx(float(player_state.category_multipliers.FANTASY_CREATURES), 1.1, "category multipliers reach player_state")
	assert_approx(float(player_state.timer_modifiers.timer_bonus), 5.0, "the tome's timer bonus reaches timer_modifiers")
	assert_approx(float(player_state.category_timer_bonus.FANTASY_CREATURES), 5.0, "category timer bonuses reach player_state")
	assert_approx(float(player_state.damage_reduction), 0.1, "damage reduction reaches player_state")
	assert_eq(player_state.loadout, loadout, "the full loadout rides along for mid-run lookups")

	# The loadout must not alias the lexicon or itself: mutating the run's
	# copy mid-run cannot leak back into the next run.
	player_state.category_multipliers["FANTASY_CREATURES"] = 99.0
	assert_approx(float(LexiconEffects.build_loadout(lexicon).category_multipliers.FANTASY_CREATURES), 1.1, "run state is a copy, not shared")

	var bare := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(bare, LexiconState.default_state())
	assert_eq(int(bare.max_hp), 100, "no tome, no HP change")

func _test_damage_integration() -> void:
	var enemy := _enemy()
	var plain := { "current_hp": 100, "max_hp": 100 }
	var base := int(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, plain, 2, 20.0).damage_dealt)
	assert_gt(float(base), 0.0, "baseline damage is positive")

	var nature := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(nature, _lexicon(["wld_01"]))
	var with_node := int(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, nature, 2, 20.0).damage_dealt)
	assert_gt(float(with_node), float(base), "Green Thumb raises damage on a nature answer")
	assert_between(float(with_node) / float(base), 1.07, 1.13, "by about its +10%")

	var off_category := { "id": "clue_x", "answer": "FOREST", "category": "MAGIC_ARCANE", "difficulty": 1 }
	var unaffected := int(CombatEngine.calculate_damage("FOREST", off_category, enemy, nature, 2, 20.0).damage_dealt)
	assert_eq(unaffected, base, "and does nothing for another category")

	var precise := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(precise, _lexicon([], ["tome_damage_01"]))
	var first_try := int(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, precise, 1, 20.0).damage_dealt)
	var first_try_plain := int(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, plain, 1, 20.0).damage_dealt)
	assert_gt(float(first_try), float(first_try_plain), "Precision boosts a first-attempt answer")
	var second_try := int(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, precise, 2, 20.0).damage_dealt)
	assert_eq(second_try, base, "and does nothing on a retry")

	var mighty := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(mighty, _lexicon([], ["tome_might_01"]))
	assert_gt(
		float(CombatEngine.calculate_damage("FOREST", TEST_CLUE, enemy, mighty, 2, 20.0).damage_dealt),
		float(base),
		"Might boosts every answer, retries included"
	)

func _test_enemy_damage_reduction() -> void:
	var enemy := _enemy()
	assert_eq(CombatEngine.calculate_enemy_damage(enemy, {}), 20, "an unarmoured player takes full damage")
	var warded := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(warded, _lexicon([], ["tome_ward_01"]))
	assert_eq(CombatEngine.calculate_enemy_damage(enemy, warded), 17, "Warding takes 15% off a 20-damage hit")

func _test_timer_integration() -> void:
	var clue := { "id": "clue_t", "answer": "OAK", "category": "FANTASY_CREATURES", "difficulty": 1 }
	var player_state := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(player_state, _lexicon(["bst_01", "bst_02"], ["tome_timer_01"]))

	var base_seconds := TimerSystem.calculate_max_time(1, {})
	var machine := CombatStateMachine.new()
	machine.setup(clue, _enemy(), player_state)
	assert_approx(
		TimerSystem.calculate_max_time(1, machine._timer_modifiers()),
		base_seconds + 5.0 + 5.0,
		"the tome and the matching category node both extend the clock"
	)

	var other := CombatStateMachine.new()
	other.setup({ "id": "clue_u", "answer": "OAK", "category": "NATURE_ELEMENTS", "difficulty": 1 }, _enemy(), player_state)
	assert_approx(
		TimerSystem.calculate_max_time(1, other._timer_modifiers()),
		base_seconds + 5.0,
		"a different category gets only the tome's seconds"
	)

	var untouched := { "current_hp": 100, "max_hp": 100 }
	var plain := CombatStateMachine.new()
	plain.setup(clue, _enemy(), untouched)
	assert_approx(TimerSystem.calculate_max_time(1, plain._timer_modifiers()), base_seconds, "no Lexicon, no change")
	assert_false(untouched.has("timer_modifiers"), "and the machine does not scribble on player_state")

func _test_chain_duration() -> void:
	var buff_effect := ChainEffects.effect_for_length(3)
	var plain := { "max_hp": 100, "current_hp": 100 }
	ChainEffects.apply(buff_effect, plain)
	var baseline := int(plain.chain_damage_buff_encounters)

	var extended := { "max_hp": 100, "current_hp": 100 }
	LexiconEffects.apply_to_player_state(extended, _lexicon(["arc_01", "arc_02", "arc_03"]))
	ChainEffects.apply(buff_effect, extended)
	assert_eq(int(extended.chain_damage_buff_encounters), baseline + 1, "Lingering Spell adds an encounter to a damage buff")

func _test_solve_helpers() -> void:
	var healed_log: Array = []
	var on_heal := func(amount: int, source: String): healed_log.append([amount, source])
	EventBus.player_healed.connect(on_heal)

	var player_state := { "current_hp": 50, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(player_state, _lexicon(["wld_01", "wld_02"], ["tome_healing_01"]))
	assert_eq(LexiconEffects.heal_for_solve(player_state, TEST_CLUE), 10, "a nature answer heals Wild Remedy's 5 plus Restoration's 5%")
	assert_eq(int(player_state.current_hp), 60, "the HP is added")
	assert_eq(healed_log, [[10, "lexicon"]], "and player_healed is emitted")

	var off := { "id": "clue_y", "answer": "SWORD", "category": "WEAPONS_ARMOR", "difficulty": 1 }
	assert_eq(LexiconEffects.heal_for_solve(player_state, off), 5, "another category gets only the tome")

	player_state["current_hp"] = 98
	assert_eq(LexiconEffects.heal_for_solve(player_state, TEST_CLUE), 2, "healing stops at max HP")
	assert_eq(LexiconEffects.heal_for_solve(player_state, TEST_CLUE), 0, "and a full player heals nothing")
	assert_eq(healed_log.size(), 3, "no event for a heal of zero")

	var none := { "current_hp": 10, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(none, LexiconState.default_state())
	assert_eq(LexiconEffects.heal_for_solve(none, TEST_CLUE), 0, "without the Lexicon nothing heals")
	assert_eq(int(none.current_hp), 10, "and HP is unchanged")

	var spoils := { "current_hp": 100, "max_hp": 100 }
	LexiconEffects.apply_to_player_state(spoils, _lexicon(["bst_01", "bst_02", "bst_03"]))
	var orc := { "id": "c", "answer": "ORC", "category": "FANTASY_CREATURES", "difficulty": 1 }
	assert_eq(LexiconEffects.ink_bonus_for_word(spoils, orc), 3, "Slayer's Spoils pays 1 Ink per letter of ORC")
	assert_eq(LexiconEffects.ink_bonus_for_word(spoils, TEST_CLUE), 0, "and nothing for other categories")
	assert_eq(LexiconEffects.ink_bonus_for_word({}, orc), 0, "and nothing without a loadout")

	EventBus.player_healed.disconnect(on_heal)
