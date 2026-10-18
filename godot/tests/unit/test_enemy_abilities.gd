#============================================================================
# test_enemy_abilities.gd
# Enemy special abilities (unlock depth, cooldowns, each effect) driven
# through the real CombatStateMachine, plus the tag-based weaknesses, round
# mode and accepted-alternate answers the boss relies on.
#============================================================================

class_name TestEnemyAbilities
extends TestSuite

const ORC := "clue_001_orc"

func _init() -> void:
	suite_name = "EnemyAbilities"

func run(host: Node) -> void:
	_test_unlock_depths()
	_test_cooldowns()
	_test_reverse_and_mishear()
	_test_blend()
	_test_mirror_input()
	_test_letter_swap()
	_test_mishearing_and_cross_encounter_cooldown()
	_test_blend_in_a_fight()
	_test_abbreviate(host)
	_test_weaknesses()
	_test_round_mode()
	_test_synonym_swap()
	_test_alternate_answers()

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _player(hp: int = 100) -> Dictionary:
	return { "current_hp": hp, "max_hp": hp }

func _enemy(enemy_id: String, depth: int) -> Dictionary:
	return EnemyDatabase.build_encounter(enemy_id, depth, 5)

## A machine set up (and not yet begun) for [param enemy_id] at [param depth].
func _machine(enemy: Dictionary, clue: Dictionary, player_state: Dictionary, round_mode: bool = false, timer: TimerSystem = null) -> CombatStateMachine:
	var machine := CombatStateMachine.new()
	machine.round_mode = round_mode
	machine.setup(clue, enemy, player_state, timer)
	return machine

## Plays an encounter to its end with correct answers (bounded), returning how
## many attempts it took.
func _finish_with_correct_answers(machine: CombatStateMachine, answer: String) -> int:
	var attempts := 0
	machine.begin()
	while not machine.is_finished() and attempts < 12:
		machine.submit_answer(answer)
		attempts += 1
	return attempts

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func _test_unlock_depths() -> void:
	var table := [
		["enemy_anagram_01", 3, "Letter Swap"],
		["enemy_palindrome_01", 3, "Mirror Input"],
		["enemy_homophone_01", 6, "Mishearing"],
		["enemy_acronym_01", 6, "Abbreviate"],
		["enemy_portmanteau_01", 10, "Blend"],
	]
	for row in table:
		var enemy_id := String(row[0])
		var depth := int(row[1])
		assert_true(EnemyAbilities.active_ability(_enemy(enemy_id, depth - 1)).is_empty(), "%s has no ability one depth before it unlocks" % enemy_id)
		assert_eq(String(EnemyAbilities.active_ability(_enemy(enemy_id, depth)).get("name", "")), String(row[2]), "%s unlocks %s at depth %d" % [enemy_id, row[2], depth])
		assert_false(EnemyAbilities.active_ability(_enemy(enemy_id, depth + 5)).is_empty(), "%s keeps its ability deeper down" % enemy_id)
	assert_true(EnemyAbilities.active_ability(EnemyDatabase.build_encounter("boss_thesaurus", 20, 5)).is_empty(), "the boss has no regular special ability (it has phases)")
	assert_true(EnemyAbilities.active_ability(EnemyDatabase.get_fallback_enemy()).is_empty(), "the fallback enemy has none")

func _test_cooldowns() -> void:
	var player := _player()
	var anagram := _enemy("enemy_anagram_01", 3)
	var ability := EnemyAbilities.active_ability(anagram)
	assert_true(EnemyAbilities.is_ready(player, anagram), "a run starts with every ability ready")
	EnemyAbilities.start_cooldown(player, anagram, ability)
	assert_false(EnemyAbilities.is_ready(player, anagram), "using it starts the cooldown")
	EnemyAbilities.tick(player, anagram)
	EnemyAbilities.tick(player, anagram)
	assert_false(EnemyAbilities.is_ready(player, anagram), "two of its three turns is not enough")
	EnemyAbilities.tick(player, anagram)
	assert_true(EnemyAbilities.is_ready(player, anagram), "the third turn readies it")
	EnemyAbilities.tick(player, anagram)
	assert_true(EnemyAbilities.is_ready(player, anagram), "ticking past zero stays ready")
	assert_true(EnemyAbilities.is_ready(player, _enemy("enemy_palindrome_01", 3)), "another enemy type has its own cooldown")

func _test_reverse_and_mishear() -> void:
	assert_eq(EnemyAbilities.reverse_answer("radar"), "RADAR", "a palindrome survives reversal")
	assert_eq(EnemyAbilities.reverse_answer(" cat "), "TAC", "reversal normalizes first")
	assert_eq(EnemyAbilities.reverse_answer(""), "", "an empty answer stays empty")

	assert_eq(EnemyAbilities.mishear("Undead noble that feeds at night"), "Undead noble that feeds at knight", "a word is swapped for its sound-alike")
	assert_eq(EnemyAbilities.mishear("Night falls"), "Knight falls", "a leading capital is kept")
	assert_eq(EnemyAbilities.mishear("Heavy rain, then hail"), "Heavy reign, then hail", "punctuation survives the swap")
	assert_eq(EnemyAbilities.mishear("Phantom of the keep"), "Fantom of the keep", "phonetic rules garble spelling")
	assert_eq(EnemyAbilities.mishear("Brutish green-skinned raider"), "Brutish green-skinned raider", "text with nothing to mishear is returned unchanged")

	var changed := 0
	var total := 0
	for clue in ClueDatabase.get_all_clues():
		var original := String(clue.clue)
		var garbled := EnemyAbilities.mishear(original)
		total += 1
		if garbled != original:
			changed += 1
		assert_false(garbled.strip_edges().is_empty(), "mishearing never empties a clue (%s)" % clue.id)
		assert_eq(garbled.split(" ", false).size(), original.split(" ", false).size(), "mishearing keeps the word count (%s)" % clue.id)
	assert_gt(float(changed) / float(total), 0.4, "mishearing visibly changes a good share of clues (%d of %d)" % [changed, total])

func _test_blend() -> void:
	var orc := ClueDatabase.get_clue(ORC)
	var orders: Dictionary = {}
	for i in range(60):
		var blended := EnemyAbilities.blend(orc)
		assert_false(blended.is_empty(), "blending finds a decoy")
		var decoy := ClueDatabase.get_clue(String(blended.decoy_id))
		assert_eq(String(decoy.answer).length(), 3, "the decoy has the same answer length")
		assert_ne(String(blended.decoy_answer), "ORC", "and a different answer")
		assert_true(String(blended.text).contains(String(orc.clue)), "the real clue is in the merged prompt")
		assert_true(String(blended.text).contains(String(decoy.clue)), "and so is the decoy")
		orders[String(blended.text).find(String(orc.clue)) < String(blended.text).find(String(decoy.clue))] = true
	assert_eq(orders.size(), 2, "the real clue appears first sometimes and second sometimes")
	assert_true(EnemyAbilities.blend({ "answer": "ZZZ", "length": 99 }).is_empty(), "no same-length decoy means no blend")

func _test_mirror_input() -> void:
	var seen: Array = []
	var orc := ClueDatabase.get_clue(ORC)

	# Armed on depth 3: the first answer is read backwards.
	var player := _player()
	var machine := _machine(_enemy("enemy_palindrome_01", 3), orc, player)
	machine.ability_triggered.connect(func(info): seen.append(info))
	machine.begin()
	assert_eq(seen.size(), 1, "Mirror Input is announced before the player types")
	assert_true(String(seen[0].message).contains("backwards"), "and says what it will do")
	var first := machine.submit_answer("ORC")
	assert_true(bool(first.mirrored), "the answer was mirrored")
	assert_false(bool(first.is_correct), "so the right answer fails")
	assert_lt(float(player.current_hp), 100.0, "and costs HP")
	var second := machine.submit_answer("ORC")
	assert_eq(seen.size(), 1, "it is on cooldown for the next attempt")
	assert_true(bool(second.is_correct) and not bool(second.mirrored), "so the second answer lands normally")

	# Typing the word backwards beats it.
	var cunning := _machine(_enemy("enemy_palindrome_01", 3), orc, _player())
	cunning.begin()
	var reversed_attempt := cunning.submit_answer("CRO")
	assert_true(bool(reversed_attempt.mirrored) and bool(reversed_attempt.is_correct), "a player who types the answer backwards gets it through")

	# Shallower than the unlock depth, nothing happens.
	var shallow_seen: Array = []
	var shallow := _machine(_enemy("enemy_palindrome_01", 2), orc, _player())
	shallow.ability_triggered.connect(func(info): shallow_seen.append(info))
	shallow.begin()
	var plain := shallow.submit_answer("ORC")
	assert_eq(shallow_seen.size(), 0, "no ability fires below depth 3")
	assert_false(bool(plain.mirrored), "and the answer is not mirrored")
	assert_true(bool(plain.is_correct), "so ORC is simply right")

func _test_letter_swap() -> void:
	var orc := ClueDatabase.get_clue(ORC)
	var summary_holder: Array = []
	var machine := _machine(_enemy("enemy_anagram_01", 3), orc, _player())
	machine.combat_finished.connect(func(summary): summary_holder.append(summary))
	machine.begin()
	for i in range(3):
		machine.submit_answer("ZZZ")
	assert_eq(summary_holder.size(), 1, "the fight ended after three misses")
	var summary: Dictionary = summary_holder[0]
	assert_eq(summary.grid_effects.size(), 1, "taking damage triggered exactly one Letter Swap (then it cooled down)")
	assert_eq(String(summary.grid_effects[0].type), "swap_solved_letters", "it is a grid effect")
	assert_eq(int(summary.grid_effects[0].count), 2, "swapping two pairs")
	assert_eq(summary.abilities_triggered.size(), 1, "and was reported once")

	var shallow_holder: Array = []
	var shallow := _machine(_enemy("enemy_anagram_01", 2), orc, _player())
	shallow.combat_finished.connect(func(s): shallow_holder.append(s))
	shallow.begin()
	for i in range(3):
		shallow.submit_answer("ZZZ")
	assert_eq(shallow_holder[0].grid_effects.size(), 0, "no swap below depth 3")

func _test_mishearing_and_cross_encounter_cooldown() -> void:
	var vampire := ClueDatabase.get_clue("clue_068_vampire")
	var player := _player(1000)
	var triggered_flags: Array[bool] = []
	for encounter in range(6):
		var enemy := _enemy("enemy_homophone_01", 6)
		var ready_before := EnemyAbilities.is_ready(player, enemy)
		var machine := _machine(enemy, vampire, player)
		# The ability fires during setup's reveal, before anything could
		# connect to its signal, so read what it did to the prompt instead.
		var garbled := machine.get_prompt() != String(vampire.clue)
		assert_eq(garbled, ready_before, "Mishearing fires on a reveal exactly when its cooldown is up (encounter %d)" % encounter)
		triggered_flags.append(garbled)
		if garbled:
			assert_true(machine.get_prompt().contains("knight"), "the garbled prompt uses the sound-alike")
		_finish_with_correct_answers(machine, "VAMPIRE")
	assert_true(triggered_flags[0], "the first encounter is garbled")
	assert_true(triggered_flags.has(false), "later encounters are not garbled every time (the cooldown works across fights)")
	assert_true(triggered_flags.count(true) >= 2, "but it comes back")

func _test_blend_in_a_fight() -> void:
	var orc := ClueDatabase.get_clue(ORC)
	var player := _player(500)
	var machine := _machine(_enemy("enemy_portmanteau_01", 10), orc, player)
	var prompt := machine.get_prompt()
	assert_ne(prompt, String(orc.clue), "Blend merges a second clue into the prompt")
	assert_true(prompt.contains(String(orc.clue)), "the real clue is still in there")

	var decoy_answer := ""
	for clue in ClueDatabase.get_all_clues():
		if int(clue.length) == 3 and clue.answer != "ORC" and prompt.contains(String(clue.clue)):
			decoy_answer = String(clue.answer)
	assert_ne(decoy_answer, "", "setup: the decoy clue can be identified from the prompt")
	machine.begin()
	var wrong := machine.submit_answer(decoy_answer)
	assert_false(bool(wrong.is_correct), "answering the decoy is wrong")
	assert_true(bool(machine.submit_answer("ORC").is_correct), "answering the real clue is right")

func _test_abbreviate(host: Node) -> void:
	var timer := TimerSystem.new()
	host.add_child(timer)
	var orc := ClueDatabase.get_clue(ORC)
	var machine := _machine(_enemy("enemy_acronym_01", 6), orc, _player(500), false, timer)
	var seen: Array = []
	machine.ability_triggered.connect(func(info): seen.append(info))
	machine.begin()
	var full := timer.max_time
	assert_gt(full, 20.0, "setup: the clock started")

	machine.submit_answer("ZZZ")
	assert_eq(seen.size(), 1, "a miss triggers Abbreviate")
	assert_true(String(seen[0].message).contains("half"), "and says the next attempt gets half the time")
	assert_between(timer.get_time_remaining(), full * 0.5 - 0.5, full * 0.5 + 0.01, "the next attempt's clock really is halved")

	machine.submit_answer("ZZZ")
	assert_eq(seen.size(), 1, "it is on cooldown for the next miss")
	assert_between(timer.get_time_remaining(), full - 0.5, full + 0.01, "so that attempt gets the full clock again")
	machine.force_timeout()
	timer.queue_free()

	var untimed_seen: Array = []
	var untimed := _machine(_enemy("enemy_acronym_01", 6), orc, _player(500))
	untimed.ability_triggered.connect(func(info): untimed_seen.append(info))
	untimed.begin()
	untimed.submit_answer("ZZZ")
	assert_eq(untimed_seen.size(), 0, "with no clock there is nothing to halve, so nothing fires")

func _test_weaknesses() -> void:
	var big := func(enemy_id: String) -> Dictionary:
		var enemy := _enemy(enemy_id, 1)
		enemy["current_hp"] = 100000
		return enemy
	var hit := func(enemy_id: String, clue_id: String) -> Dictionary:
		var clue := ClueDatabase.get_clue(clue_id)
		var target: Dictionary = big.call(enemy_id)
		return CombatEngine.calculate_damage(String(clue.answer), clue, target, _player(), 2, 20.0)

	assert_true(bool(hit.call("enemy_portmanteau_01", "clue_078_werewolf").weakness_hit), "the Portmanteau is weak to a compound answer")
	assert_false(bool(hit.call("enemy_portmanteau_01", ORC).weakness_hit), "but not to a plain one")
	assert_true(bool(hit.call("enemy_homophone_01", "clue_024_rain").weakness_hit), "the Homophone is weak to RAIN (REIGN / REIN)")
	assert_false(bool(hit.call("enemy_homophone_01", "clue_026_fire").weakness_hit), "but not to FIRE")
	assert_true(bool(hit.call("enemy_acronym_01", ORC).weakness_hit), "the Acronym is weak to a full-word answer")
	assert_false(bool(hit.call("enemy_acronym_01", "clue_116_npc").weakness_hit), "but not to an abbreviation like NPC")
	assert_false(CombatEngine.matches_weakness("ORC", _enemy("enemy_acronym_01", 1)), "with no clue to inspect, 'lacks a tag' is not an always-on bonus")

	var with_weakness := int(hit.call("enemy_portmanteau_01", "clue_078_werewolf").damage_dealt)
	var plain_enemy: Dictionary = big.call("enemy_portmanteau_01")
	plain_enemy["weakness"] = null
	var werewolf := ClueDatabase.get_clue("clue_078_werewolf")
	var without := int(CombatEngine.calculate_damage("WEREWOLF", werewolf, plain_enemy, _player(), 2, 20.0).damage_dealt)
	assert_between(float(with_weakness) / float(without), 1.45, 1.55, "a weakness hit is worth about +50%")

func _test_round_mode() -> void:
	var boss := EnemyDatabase.build_encounter("boss_thesaurus", 5, 5)
	var data := EnemyDatabase.get_enemy("boss_thesaurus")
	var grid_hp: int = int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).difficulty_scaling.hp_per_grid_size)
	var expected_hp: int = int(data.base_hp) + int(data.scaling.hp_per_depth) * 5 + grid_hp * 5
	var expected_damage: int = int(data.base_damage) + int(data.scaling.damage_per_depth) * 5
	assert_eq(int(boss.max_hp), expected_hp, "the boss scales with depth and grid size, per its own data")
	assert_eq(int(boss.damage), expected_damage, "and hits for its base damage plus its per-depth scaling")

	var orc := ClueDatabase.get_clue(ORC)
	var defeated_events: Array = []
	var on_defeated := func(id: String, rewards: Dictionary): defeated_events.append(id)
	EventBus.enemy_defeated.connect(on_defeated)

	var player := _player(300)
	var round_machine := _machine(boss, orc, player, true)
	var finished: Array = []
	round_machine.combat_finished.connect(func(s): finished.append(s))
	round_machine.begin()
	var hit := round_machine.submit_answer("ORC")
	assert_true(bool(hit.is_correct), "a correct answer lands")
	assert_eq(int(player.current_hp), 300, "and the boss does not strike back at a hit")
	assert_lt(float(boss.current_hp), float(boss.max_hp), "it took damage")
	assert_gt(float(boss.current_hp), 0.0, "and is still standing")
	assert_eq(finished.size(), 1, "the round ended on the correct answer")
	assert_true(bool(finished[0].victory), "a cleared round reports victory")
	assert_false(bool(finished[0].enemy_dead), "while the enemy is not dead")
	assert_false(bool(finished[0].player_defeated), "and the player is fine")
	assert_eq(defeated_events.size(), 0, "no enemy_defeated event for a round")

	# A miss does cost HP, and three misses end the round (not the fight).
	var miss_finished: Array = []
	var miss_machine := _machine(boss, orc, player, true)
	miss_machine.combat_finished.connect(func(s): miss_finished.append(s))
	miss_machine.begin()
	miss_machine.submit_answer("ZZZ")
	assert_eq(int(player.current_hp), 300 - int(boss.damage), "a miss costs the boss's damage")
	miss_machine.submit_answer("ZZZ")
	miss_machine.submit_answer("ZZZ")
	assert_eq(miss_finished.size(), 1, "three misses end the round")
	assert_false(bool(miss_finished[0].victory), "without clearing it")
	assert_false(bool(miss_finished[0].player_defeated), "and the player survives it")
	assert_false(bool(miss_finished[0].enemy_dead), "the boss lives on")

	# A killing blow ends the fight for real.
	var weak_boss := EnemyDatabase.build_encounter("boss_thesaurus", 1, 5)
	weak_boss["current_hp"] = 1
	var kill_machine := _machine(weak_boss, orc, _player(), true)
	var kill_finished: Array = []
	kill_machine.combat_finished.connect(func(s): kill_finished.append(s))
	kill_machine.begin()
	kill_machine.submit_answer("ORC")
	assert_true(bool(kill_finished[0].enemy_dead), "a lethal hit reports enemy_dead")
	assert_eq(defeated_events, ["boss_thesaurus"], "and only then is enemy_defeated emitted")
	EventBus.enemy_defeated.disconnect(on_defeated)

func _test_synonym_swap() -> void:
	var boss := EnemyDatabase.build_encounter("boss_thesaurus", 5, 5)
	var clue := ClueDatabase.get_clue(ORC)
	clue["variant_clue"] = "A reworded clue"
	var prompts: Array[String] = []
	var machine := _machine(boss, clue, _player(500), true)
	machine.prompt_changed.connect(func(text): prompts.append(text))
	machine.begin()
	assert_eq(machine.get_prompt(), String(clue.clue), "the clue starts in its original wording")
	machine.submit_answer("ZZZ")
	assert_eq(prompts, ["A reworded clue"], "the first miss rewords the clue")
	assert_eq(machine.get_prompt(), "A reworded clue", "and the prompt now reads the new wording")
	machine.submit_answer("ZZZ")
	assert_eq(prompts.size(), 1, "it only rewords once")

	var clean_prompts: Array[String] = []
	var no_miss := _machine(boss, clue, _player(500), true)
	no_miss.prompt_changed.connect(func(text): clean_prompts.append(text))
	no_miss.begin()
	no_miss.submit_answer("ORC")
	assert_eq(clean_prompts.size(), 0, "a clean first answer never triggers the reword")

func _test_alternate_answers() -> void:
	var clue := {
		"id": "clue_alt", "answer": "SWERD", "length": 5, "answer_length": 5,
		"category": "WEAPONS_ARMOR", "difficulty": 1, "clue": "x", "clue_text": "x",
		"alternates": [{ "answer": "SWORD", "damage_multiplier": 0.5 }],
	}
	var exact := ClueResolver.validate("swerd", clue)
	assert_true(bool(exact.is_correct) and exact.alternate.is_empty(), "the exact answer is right and is not an alternate")
	var alt := ClueResolver.validate("Sword", clue)
	assert_true(bool(alt.is_correct), "an alternate answer is accepted")
	assert_eq(float(alt.alternate.damage_multiplier), 0.5, "and carries its multiplier")
	assert_false(bool(ClueResolver.validate("sward", clue).is_correct), "anything else is still wrong")

	var enemy := _enemy("enemy_anagram_01", 1)
	enemy["current_hp"] = 100000
	var exact_hit := CombatEngine.calculate_damage("SWERD", clue, enemy, _player(), 2, 20.0)
	var alt_hit := CombatEngine.calculate_damage("SWORD", clue, enemy, _player(), 2, 20.0)
	assert_true(bool(alt_hit.alternate_hit) and not bool(exact_hit.alternate_hit), "only the alternate is flagged")
	assert_between(float(alt_hit.damage_dealt) / float(exact_hit.damage_dealt), 0.45, 0.55, "the alternate deals about half")
