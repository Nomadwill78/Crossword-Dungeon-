#============================================================================
# test_databases.gd
# Unit tests for the ClueDatabase / EnemyDatabase wrappers, including the
# fallback paths that keep a bad id from crashing a run (CLAUDE.md 5.3).
#============================================================================

class_name TestDatabases
extends TestSuite

func _init() -> void:
	suite_name = "Databases"

func run(_host: Node) -> void:
	test_clue_lookup()
	test_unknown_clue_falls_back()
	test_clue_normalizes_spec_field_names()
	test_random_clue_by_length()
	test_random_clue_falls_back_when_length_absent()
	test_enemy_roster_matches_design_doc()
	test_unknown_enemy_falls_back()
	test_encounter_scaling_matches_design_doc()
	test_ability_unlock_depths()
	test_returned_dictionaries_are_copies()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func test_clue_lookup() -> void:
	assert_gt(ClueDatabase.count(), 100, "Clue database is populated")
	var clue := ClueDatabase.get_clue("clue_001_orc")
	assert_eq(String(clue.answer), "ORC", "Known clue id resolves")

func test_unknown_clue_falls_back() -> void:
	var clue := ClueDatabase.get_clue("clue_does_not_exist")
	assert_eq(String(clue.id), "clue_fallback", "Unknown id yields the fallback clue")
	assert_eq(String(clue.answer), "CAT", "Fallback is always solvable")

## The Technical Design Doc names these `answer_length` / `clue_text`;
## clues_master.json stores `length` / `clue`. Both spellings must be present
## once a clue leaves the database.
func test_clue_normalizes_spec_field_names() -> void:
	var clue := ClueDatabase.get_clue("clue_001_orc")
	assert_eq(int(clue.answer_length), 3, "answer_length alias present")
	assert_eq(int(clue.length), 3, "length still present")
	assert_ne(String(clue.clue_text), "", "clue_text alias present")
	assert_eq(String(clue.clue_text), String(clue.clue), "Both spellings agree")

func test_random_clue_by_length() -> void:
	for i in range(20):
		var clue := ClueDatabase.get_random_clue(6)
		assert_eq(String(clue.answer).length(), 6, "Random 6-letter clue really has 6 letters")

func test_random_clue_falls_back_when_length_absent() -> void:
	# No 20-letter answers exist; this must degrade, not return junk.
	var clue := ClueDatabase.get_random_clue(20)
	assert_eq(String(clue.id), "clue_fallback", "Impossible length yields the fallback clue")

## Design Doc 4.4 names the roster; make sure the data actually contains it.
func test_enemy_roster_matches_design_doc() -> void:
	var expected := [
		"enemy_anagram_01", "enemy_palindrome_01", "enemy_homophone_01",
		"enemy_acronym_01", "enemy_portmanteau_01",
	]
	var regular := EnemyDatabase.get_regular_ids()
	for id in expected:
		assert_true(regular.has(id), "Roster contains %s" % id)
	assert_eq(regular.size(), 5, "Five regular enemy types")

	var bosses := EnemyDatabase.get_boss_ids()
	assert_eq(bosses, ["boss_thesaurus"] as Array[String], "The Thesaurus is the boss")
	assert_true(EnemyDatabase.is_boss("boss_thesaurus"), "Boss flagged correctly")
	assert_false(EnemyDatabase.is_boss("enemy_anagram_01"), "Regular enemy is not a boss")

func test_unknown_enemy_falls_back() -> void:
	var enemy := EnemyDatabase.get_enemy("enemy_does_not_exist")
	assert_eq(String(enemy.id), "enemy_fallback", "Unknown id yields the fallback enemy")

## Design Doc 4.4: HP = 20 + (depth * 5) + (grid_size * 2),
## damage = 5 + (depth * 2).
func test_encounter_scaling_matches_design_doc() -> void:
	var shallow := EnemyDatabase.build_encounter("enemy_anagram_01", 1, 5)
	assert_eq(int(shallow.max_hp), 35, "Depth 1, 5x5: 20 + 5 + 10 = 35 HP")
	assert_eq(int(shallow.damage), 7, "Depth 1: 5 + 2 = 7 damage")
	assert_eq(int(shallow.current_hp), int(shallow.max_hp), "Encounter starts at full HP")

	var deep := EnemyDatabase.build_encounter("enemy_anagram_01", 3, 9)
	assert_eq(int(deep.max_hp), 53, "Depth 3, 9x9: 20 + 15 + 18 = 53 HP")
	assert_eq(int(deep.damage), 11, "Depth 3: 5 + 6 = 11 damage")
	assert_gt(float(deep.max_hp), float(shallow.max_hp), "Deeper enemies are tougher")

## Design Doc 4.4: special abilities unlock at depths 3, 6, 10, 15.
func test_ability_unlock_depths() -> void:
	var anagram := EnemyDatabase.get_enemy("enemy_anagram_01")
	assert_false(EnemyDatabase.ability_unlocked(anagram, 1), "Anagram ability locked at depth 1")
	assert_true(EnemyDatabase.ability_unlocked(anagram, 3), "Anagram ability unlocks at depth 3")

	var portmanteau := EnemyDatabase.get_enemy("enemy_portmanteau_01")
	assert_false(EnemyDatabase.ability_unlocked(portmanteau, 6), "Portmanteau still locked at depth 6")
	assert_true(EnemyDatabase.ability_unlocked(portmanteau, 10), "Portmanteau unlocks at depth 10")

## Mutating a returned record must not corrupt the shared database.
func test_returned_dictionaries_are_copies() -> void:
	var first := ClueDatabase.get_clue("clue_001_orc")
	first["answer"] = "TAMPERED"
	assert_eq(String(ClueDatabase.get_clue("clue_001_orc").answer), "ORC", "Clue database is not mutated")

	var enemy := EnemyDatabase.get_enemy("enemy_anagram_01")
	enemy["base_hp"] = 9999
	assert_eq(int(EnemyDatabase.get_enemy("enemy_anagram_01").base_hp), 20, "Enemy database is not mutated")
