#============================================================================
# test_boss_encounter.gd
# The Thesaurus: when it appears, its HP and phases, what each phase asks for,
# and whole fights played out through real CombatStateMachine rounds.
#============================================================================

class_name TestBossEncounter
extends TestSuite

func _init() -> void:
	suite_name = "BossEncounter"

func run(_host: Node) -> void:
	_test_when_it_appears()
	_test_stats_and_phases()
	_test_synonym_rounds()
	_test_antonym_rounds()
	_test_archaic_rounds()
	_test_round_bookkeeping()
	_test_a_perfect_fight()
	_test_a_hopeless_fight()
	_test_modern_spelling_is_worth_less()

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _fight(depth: int = 5, size: int = 5) -> BossEncounter:
	return BossEncounter.begin(depth, size)

## Puts the boss at [param fraction] of its max HP.
func _set_hp(fight: BossEncounter, fraction: float) -> void:
	fight.boss["current_hp"] = int(round(float(fight.boss.max_hp) * fraction))

func _player(hp: int = 100) -> Dictionary:
	return { "current_hp": hp, "max_hp": hp }

## Plays one round through a real state machine. [param answer_for] maps the
## round's clue to what the player types; "" means type something wrong.
func _play_round(fight: BossEncounter, player: Dictionary, perfect: bool) -> Dictionary:
	var clue := fight.next_round_clue()
	var machine := CombatStateMachine.new()
	machine.round_mode = true
	var holder: Array = []
	machine.combat_finished.connect(func(summary): holder.append(summary))
	machine.setup(clue, fight.boss, player)
	machine.begin()
	var guard := 0
	while not machine.is_finished() and guard < 8:
		machine.submit_answer(String(clue.answer) if perfect else "ZZZ")
		guard += 1
	fight.finish_round(holder[0])
	return holder[0]

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func _test_when_it_appears() -> void:
	assert_true(BossEncounter.is_due(5, 30), "depth 5 at level 30: the boss guards the way down")
	assert_false(BossEncounter.is_due(5, 29), "one level short: it does not appear")
	assert_false(BossEncounter.is_due(4, 50), "off-floors never have it, whatever the level")
	assert_true(BossEncounter.is_due(10, 30), "every fifth floor: depth 10")
	assert_true(BossEncounter.is_due(15, 50), "and 15")
	assert_false(BossEncounter.is_due(0, 50), "depth 0 is nothing")
	assert_false(BossEncounter.is_due(7, 50), "depth 7 is not a fifth floor")

func _test_stats_and_phases() -> void:
	var fight := _fight(5, 7)
	assert_eq(int(fight.boss.max_hp), 200 + 10 * 5 + 2 * 7, "boss HP scales with depth and grid size")
	assert_eq(int(fight.boss.current_hp), int(fight.boss.max_hp), "it starts at full health")
	assert_eq(int(fight.boss.damage), 35, "and hits for 20 + 3 per depth")
	assert_false(fight.is_over(), "a new fight is not over")

	var expected := [[1.0, 0], [0.9, 0], [0.51, 0], [0.5, 1], [0.26, 1], [0.25, 2], [0.1, 2], [0.0, 2]]
	for row in expected:
		assert_eq(fight.phase_for_fraction(float(row[0])), int(row[1]), "at %.2f of max HP the boss is in phase %d" % [row[0], int(row[1]) + 1])

	assert_true(fight.phase_label().begins_with("Phase 1"), "the label names the phase")
	_set_hp(fight, 0.4)
	assert_true(fight.phase_label().begins_with("Phase 2"), "and follows the boss's health")
	_set_hp(fight, 0.1)
	assert_true(fight.phase_label().begins_with("Phase 3"), "into the last phase")

func _test_synonym_rounds() -> void:
	var variants: Dictionary = ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH).synonym_variants
	var fight := _fight()
	var seen: Dictionary = {}
	for i in range(variants.size()):
		var clue := fight.next_round_clue()
		assert_true(variants.has(String(clue.id)), "phase 1 draws from the reworded clues (%s)" % clue.id)
		assert_eq(String(clue.variant_clue), String(variants[clue.id]), "and carries its rewording")
		assert_ne(String(clue.variant_clue), String(clue.clue), "which differs from the original")
		seen[String(clue.id)] = true
	assert_eq(seen.size(), variants.size(), "no clue repeats until the whole pool has been used")
	assert_true(variants.has(String(fight.next_round_clue().id)), "after that the pool is reused instead of running dry")

func _test_antonym_rounds() -> void:
	var pairs: Array = ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH).antonym_pairs
	var fight := _fight()
	_set_hp(fight, 0.4)
	var prompts: Dictionary = {}
	for i in range(pairs.size() * 2):
		var clue := fight.next_round_clue()
		var text := String(clue.clue)
		assert_true(text.contains("OPPOSITE"), "phase 2 asks for the opposite")
		assert_eq(String(clue.clue_text), text, "both text fields agree")
		var partner_found := false
		for pair in pairs:
			for side in range(2):
				if String(pair[side]) == String(clue.id):
					var source := ClueDatabase.get_clue(String(pair[1 - side]))
					if text.contains(String(source.clue)):
						partner_found = true
		assert_true(partner_found, "the prompt for %s quotes the clue of its opposite" % clue.answer)
		assert_false(text.contains(String(clue.answer)), "and does not contain the answer")
		prompts[text] = true
	assert_eq(prompts.size(), pairs.size() * 2, "every direction of every pair comes up once before any repeats")

func _test_archaic_rounds() -> void:
	var entries: Array = ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH).archaic_spellings
	var fight := _fight()
	_set_hp(fight, 0.2)
	var penalty := float(fight.boss.weakness.penalty_multiplier)
	var spellings: Dictionary = {}
	for i in range(entries.size()):
		var clue := fight.next_round_clue()
		assert_eq(int(clue.length), String(clue.answer).length(), "the clue's length follows the archaic spelling")
		assert_eq(int(clue.answer_length), String(clue.answer).length(), "in both length fields")
		assert_eq(clue.alternates.size(), 1, "the modern spelling is the one alternate")
		var modern := String(ClueDatabase.get_clue(String(clue.id)).answer)
		assert_eq(String(clue.alternates[0].answer), modern, "and it is the clue's real answer")
		assert_approx(float(clue.alternates[0].damage_multiplier), penalty, "worth the boss's exact-match penalty")
		assert_true(String(clue.clue).contains("Archaic"), "the prompt says to use the old spelling")
		assert_true(bool(ClueResolver.validate(String(clue.answer), clue).is_correct), "the archaic spelling is accepted")
		assert_true(bool(ClueResolver.validate(modern, clue).is_correct), "and so is the modern one")
		spellings[String(clue.answer)] = true
	assert_eq(spellings.size(), entries.size(), "each archaic spelling comes up before any repeats")

func _test_round_bookkeeping() -> void:
	var fight := _fight()
	assert_eq(fight.rounds_played, 0, "no rounds yet")
	fight.finish_round({ "player_defeated": false })
	assert_eq(fight.rounds_played, 1, "a finished round is counted")
	assert_false(fight.is_over(), "and does not end the fight by itself")

	fight.finish_round({ "player_defeated": true })
	assert_true(fight.player_died, "a player death is recorded")
	assert_true(fight.is_over(), "and ends the fight")

	var endless := _fight()
	var cap := int(BossEncounter.config().max_rounds)
	for i in range(cap):
		endless.finish_round({ "player_defeated": false })
	assert_true(endless.abandoned, "the max_rounds backstop ends a fight nobody is winning")
	assert_true(endless.is_over(), "so a fight can never run forever")
	assert_false(endless.is_won(), "without counting as a win")
	assert_gt(float(fight.reward_ink()), 0.0, "beating the boss pays Ink")

func _test_a_perfect_fight() -> void:
	var fight := _fight(5, 5)
	var player := _player(100)
	var phases_seen: Array[int] = []
	var last_hp := int(fight.boss.current_hp)
	var rounds := 0
	while not fight.is_over() and rounds < 60:
		phases_seen.append(fight.current_phase_index())
		var summary := _play_round(fight, player, true)
		rounds += 1
		assert_true(bool(summary.victory), "a perfect answer clears each round")
		assert_lt(float(fight.boss.current_hp), float(last_hp), "every round takes the boss lower")
		last_hp = int(fight.boss.current_hp)

	assert_true(fight.is_won(), "perfect play beats the boss")
	assert_false(fight.player_died, "without dying")
	assert_eq(int(player.current_hp), 100, "and without losing a single HP - the boss never strikes a hit")
	assert_between(float(rounds), 3.0, 30.0, "in a sensible number of rounds (%d)" % rounds)
	assert_eq(phases_seen[0], 0, "it started in phase 1")
	var ordered := true
	for i in range(1, phases_seen.size()):
		if phases_seen[i] < phases_seen[i - 1]:
			ordered = false
	assert_true(ordered, "phases only ever advance")
	var distinct: Dictionary = {}
	for phase in phases_seen:
		distinct[phase] = true
	assert_gt(float(distinct.size()), 1.0, "and the fight passes through more than one phase (%s)" % str(phases_seen))

func _test_a_hopeless_fight() -> void:
	var fight := _fight(5, 5)
	var player := _player(100)
	var rounds := 0
	while not fight.is_over() and rounds < 60:
		_play_round(fight, player, false)
		rounds += 1
	assert_true(fight.player_died, "a player who only misses dies")
	assert_false(fight.is_won(), "and the boss survives")
	assert_eq(rounds, 1, "within the first round (three misses at 35 each)")
	assert_eq(int(fight.boss.current_hp), int(fight.boss.max_hp), "having never scratched it")

func _test_modern_spelling_is_worth_less() -> void:
	var fight := _fight()
	_set_hp(fight, 0.2)
	for i in range(8):
		var clue := fight.next_round_clue()
		var modern := String(clue.alternates[0].answer)
		var archaic := String(clue.answer)
		var full := int(CombatEngine.calculate_damage(archaic, clue, fight.boss, _player(), 2, 20.0).damage_dealt)
		var reduced_result := CombatEngine.calculate_damage(modern, clue, fight.boss, _player(), 2, 20.0)
		assert_true(bool(reduced_result.alternate_hit), "the modern spelling is flagged as the alternate")
		# Word lengths differ by a letter, which changes the base damage a little.
		assert_between(float(reduced_result.damage_dealt) / float(full), 0.35, 0.65, "%s deals about half of %s" % [modern, archaic])
