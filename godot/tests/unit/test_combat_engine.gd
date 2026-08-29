#============================================================================
# test_combat_engine.gd
# Unit tests for the damage formula (Technical Design Doc 3.2).
#============================================================================

class_name TestCombatEngine
extends TestSuite

func _init() -> void:
	suite_name = "CombatEngine"

func run(_host: Node) -> void:
	test_worked_example_from_spec()
	test_shorter_words_hit_harder_per_letter()
	test_first_attempt_bonus()
	test_time_bonus_scales_with_remaining_time()
	test_double_letter_weakness()
	test_palindrome_weakness()
	test_null_weakness_never_triggers()
	test_resistance_reduces_damage()
	test_enemy_defeated_when_damage_exceeds_hp()
	test_counter_attack_only_while_enemy_lives()
	test_wrong_answer_deals_no_damage_and_costs_hp()
	test_timeout_is_treated_as_a_miss()
	test_chain_buff_multiplier()
	test_meta_multipliers_default_to_neutral()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------

## The Technical Design Doc's own worked example (section 5.1):
## "CAT", difficulty 1, first attempt, full timer.
##   3-letter: 6 dmg/letter = 18 base
##   difficulty 1: +10%  -> 19.8
##   first attempt: +25% -> 24.75
##   full time: +50%     -> 37.125  => 37
##
## NOTE: the spec's test passes time_remaining = 30.0 while its TimerSystem
## gives difficulty 1 a 45-second budget, so 30.0 is only 2/3 of the clock and
## cannot produce the "+50% full time" step the comment describes. The formula
## is implemented exactly as section 3.2 specifies; this test supplies a
## genuinely full timer (45.0) and lands on the spec's expected 37.
func test_worked_example_from_spec() -> void:
	var result := CombatEngine.calculate_damage(
		"CAT", _clue("CAT", 1), _enemy(100), {}, 1, 45.0
	)
	assert_eq(result.damage_dealt, 37, "Spec worked example: CAT deals 37")
	assert_true(result.is_correct, "Spec worked example: marked correct")
	assert_true(result.is_first_attempt, "Spec worked example: first attempt")

## Design Doc 4.2 gives short words a higher per-letter rate so a 3-letter
## answer is not strictly worse than a long one.
func test_shorter_words_hit_harder_per_letter() -> void:
	assert_eq(CombatEngine.get_base_damage_per_letter(1), 10, "1-letter = 10/letter")
	assert_eq(CombatEngine.get_base_damage_per_letter(3), 6, "3-letter = 6/letter")
	assert_eq(CombatEngine.get_base_damage_per_letter(5), 4, "5-letter = 4/letter")
	assert_eq(CombatEngine.get_base_damage_per_letter(8), 3, "8-letter = 3/letter")
	assert_eq(CombatEngine.get_base_damage_per_letter(12), 2, "9+ letters fall back to 2/letter")

func test_first_attempt_bonus() -> void:
	var first := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(100), {}, 1, 45.0)
	var second := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(100), {}, 2, 45.0)
	assert_gt(first.damage_dealt, second.damage_dealt, "First attempt beats second")
	assert_false(second.is_first_attempt, "Second attempt is flagged as such")

func test_time_bonus_scales_with_remaining_time() -> void:
	var fast := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(100), {}, 1, 45.0)
	var slow := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(100), {}, 1, 0.0)
	assert_gt(fast.damage_dealt, slow.damage_dealt, "Answering fast beats answering slow")
	# At zero time left the multiplier clamps to its 1.0 floor: 18 * 1.1 * 1.25.
	assert_eq(slow.damage_dealt, 24, "No time left still applies the 1.0 floor")

## The Anagram's weakness from Design Doc 4.4: words with double letters.
func test_double_letter_weakness() -> void:
	var enemy := _enemy(500)
	enemy["weakness"] = {
		"type": "word_property", "property": "double_letter", "bonus_multiplier": 1.5,
	}
	var with_double := CombatEngine.calculate_damage("BALLOON", _clue("BALLOON", 2), enemy, {}, 1, 40.0)
	var without := CombatEngine.calculate_damage("BALLOON", _clue("BALLOON", 2), _enemy(500), {}, 1, 40.0)

	assert_true(with_double.weakness_hit, "BALLOON triggers the double-letter weakness")
	assert_eq(with_double.damage_dealt, 70, "BALLOON into double-letter weakness = 70")
	assert_eq(without.damage_dealt, 47, "Same word, no weakness = 47")

## The Palindrome's weakness from Design Doc 4.4.
func test_palindrome_weakness() -> void:
	var enemy := _enemy(500)
	enemy["weakness"] = {
		"type": "word_property", "property": "palindrome", "bonus_multiplier": 1.5,
	}
	var hit := CombatEngine.calculate_damage("LEVEL", _clue("LEVEL", 2), enemy, {}, 1, 40.0)
	var miss := CombatEngine.calculate_damage("STORM", _clue("STORM", 2), enemy, {}, 1, 40.0)

	assert_true(hit.weakness_hit, "LEVEL is a palindrome")
	assert_false(miss.weakness_hit, "STORM is not a palindrome")
	assert_gt(hit.damage_dealt, miss.damage_dealt, "Palindrome answer hits harder")

## Three enemies ship with weakness: null because the Design Doc weakness they
## are meant to have needs a system that does not exist yet. Null must simply
## never match - not error, not always-match.
func test_null_weakness_never_triggers() -> void:
	var enemy := _enemy(500)
	enemy["weakness"] = null
	var result := CombatEngine.calculate_damage("BALLOON", _clue("BALLOON", 2), enemy, {}, 1, 40.0)
	assert_false(result.weakness_hit, "Null weakness never fires")
	assert_false(CombatEngine.matches_weakness("BALLOON", enemy), "matches_weakness handles null")

	# And the real roster's pending-weakness enemies behave the same way.
	var homophone := EnemyDatabase.get_enemy("enemy_homophone_01")
	assert_false(CombatEngine.matches_weakness("BALLOON", homophone), "Homophone has no live weakness")

func test_resistance_reduces_damage() -> void:
	var enemy := _enemy(500)
	enemy["resistance"] = {
		"type": "word_property", "property": "palindrome", "penalty_multiplier": 0.75,
	}
	var resisted := CombatEngine.calculate_damage("LEVEL", _clue("LEVEL", 2), enemy, {}, 1, 40.0)
	var normal := CombatEngine.calculate_damage("STORM", _clue("STORM", 2), enemy, {}, 1, 40.0)

	assert_true(resisted.resistance_hit, "LEVEL triggers the palindrome resistance")
	assert_lt(resisted.damage_dealt, normal.damage_dealt, "Resisted answer deals less")

func test_enemy_defeated_when_damage_exceeds_hp() -> void:
	var result := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(10), {}, 1, 45.0)
	assert_true(result.enemy_defeated, "37 damage kills a 10 HP enemy")
	assert_eq(result.damage_taken, 0, "A defeated enemy does not counter-attack")

func test_counter_attack_only_while_enemy_lives() -> void:
	var enemy := _enemy(500)
	enemy["damage"] = 9
	var result := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), enemy, {}, 1, 45.0)
	assert_false(result.enemy_defeated, "500 HP enemy survives")
	assert_eq(result.damage_taken, 9, "Surviving enemy counters for its damage stat")

func test_wrong_answer_deals_no_damage_and_costs_hp() -> void:
	var enemy := _enemy(100)
	enemy["damage"] = 7
	var result := CombatEngine.resolve_attempt("DOG", _clue("CAT", 1), enemy, {}, 1, 45.0)
	assert_false(result.is_correct, "DOG is not CAT")
	assert_eq(result.damage_dealt, 0, "Wrong answer deals no damage")
	assert_eq(result.damage_taken, 7, "Wrong answer draws a counter-attack")

func test_timeout_is_treated_as_a_miss() -> void:
	var enemy := _enemy(100)
	enemy["damage"] = 7
	# Even a correct answer counts as a miss once the clock has run out.
	var result := CombatEngine.resolve_attempt("CAT", _clue("CAT", 1), enemy, {}, 1, 0.0, true)
	assert_false(result.is_correct, "Timeout is never a hit")
	assert_true(result.timed_out, "Timeout is flagged")
	assert_eq(result.damage_taken, 7, "Timeout draws a counter-attack")

## Design Doc 4.3: a 3-letter chain grants +20% damage for 3 encounters.
func test_chain_buff_multiplier() -> void:
	var buffed := CombatEngine.calculate_damage(
		"CAT", _clue("CAT", 1), _enemy(500), {"chain_damage_buff": 0.2}, 1, 45.0
	)
	var plain := CombatEngine.calculate_damage("CAT", _clue("CAT", 1), _enemy(500), {}, 1, 45.0)
	assert_eq(plain.damage_dealt, 37, "Unbuffed baseline")
	assert_eq(buffed.damage_dealt, 44, "+20% chain buff: floor(37.125 * 1.2) = 44")

## The vocabulary-tree and tome hooks exist now but stay neutral until
## Milestone 3 fills them in.
func test_meta_multipliers_default_to_neutral() -> void:
	assert_approx(CombatEngine.get_category_multiplier("NATURE_ELEMENTS", {}), 1.0, "No vocab tree = 1.0")
	assert_approx(CombatEngine.get_tome_multiplier("combat", {}), 1.0, "No tomes = 1.0")
	assert_approx(CombatEngine.get_chain_buff_multiplier({}), 1.0, "No chain buff = 1.0")
	assert_approx(
		CombatEngine.get_category_multiplier("SCIENCE", {"category_multipliers": {"SCIENCE": 1.1}}),
		1.1,
		"Populated vocab tree multiplier is honoured"
	)

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _clue(answer: String, difficulty: int) -> Dictionary:
	return {
		"id": "clue_test_%s" % answer.to_lower(),
		"answer": answer,
		"length": answer.length(),
		"answer_length": answer.length(),
		"clue": "test clue for %s" % answer,
		"difficulty": difficulty,
		"category": "TEST",
	}

func _enemy(hp: int) -> Dictionary:
	return {
		"id": "enemy_test",
		"base_hp": hp,
		"max_hp": hp,
		"current_hp": hp,
		"base_damage": 5,
		"damage": 5,
		"weakness": null,
		"resistance": null,
	}
