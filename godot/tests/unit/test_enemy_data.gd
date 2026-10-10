#============================================================================
# test_enemy_data.gd
# Data-integrity checks for Milestone 4's content: enemy definitions, clue
# tags, the boss's round content and the ability rules. Content lives in JSON
# (CLAUDE.md 2.1), so a typo there is the likeliest way to break the boss.
#============================================================================

class_name TestEnemyData
extends TestSuite

const TRIGGERS: Array[String] = ["on_clue_reveal", "on_attempt", "on_attempt_failed", "player_takes_damage"]
const MODES: Array[String] = ["swap_solved_letters", "reverse_answer", "scale_remaining", "mishear", "blend"]
const WEAKNESS_TYPES: Array[String] = ["word_property", "clue_tag", "not_clue_tag", "exact_match"]
const BOSS_ABILITIES: Array[String] = ["synonym_swap", "antonym_inversion", "obscure_variant"]
const TAGS: Array[String] = ["compound", "homophone", "abbreviation"]
const UNLOCK_DEPTHS: Array[int] = [3, 6, 10, 15]

func _init() -> void:
	suite_name = "EnemyData"

func run(_host: Node) -> void:
	EnemyDatabase.reset_cache()
	ClueDatabase.reset_cache()
	_test_enemies()
	_test_boss_definition()
	_test_clue_tags()
	_test_boss_rounds()
	_test_ability_rules()

func _test_enemies() -> void:
	var ids := EnemyDatabase.get_regular_ids()
	assert_eq(ids.size(), 5, "five regular enemies (Design Doc 5.3)")
	for id in ids:
		var enemy := EnemyDatabase.get_enemy(id)
		assert_false(enemy.has("weakness_pending"), "%s has no pending weakness left" % id)
		assert_true(enemy.get("weakness") != null, "%s has a weakness" % id)
		var weakness: Dictionary = enemy.weakness
		assert_true(WEAKNESS_TYPES.has(String(weakness.get("type", ""))), "%s's weakness type is known (%s)" % [id, weakness.get("type", "")])
		assert_gt(float(weakness.get("bonus_multiplier", 1.0)), 1.0, "%s's weakness is a bonus" % id)
		match String(weakness.type):
			"word_property":
				assert_true(WordProperties.SUPPORTED_PROPERTIES.has(String(weakness.get("property", ""))), "%s's word property is supported" % id)
			"clue_tag", "not_clue_tag":
				assert_true(TAGS.has(String(weakness.get("tag", ""))), "%s's weakness tag is one clues use" % id)

		var ability: Dictionary = enemy.get("special_ability", {})
		assert_true(TRIGGERS.has(String(ability.get("trigger_condition", ""))), "%s's ability trigger is known" % id)
		assert_true(MODES.has(String(ability.get("effect", {}).get("mode", ""))), "%s's ability mode is implemented" % id)
		assert_true(UNLOCK_DEPTHS.has(int(ability.get("unlock_depth", 0))), "%s unlocks at one of depths 3/6/10/15" % id)
		assert_gt(float(ability.get("cooldown_turns", 0)), 0.0, "%s's ability has a cooldown" % id)

	# Every weakness tag in use must actually exist on some clue, or the
	# enemy's weakness could never fire.
	for id in ids:
		var weakness: Dictionary = EnemyDatabase.get_enemy(id).weakness
		if String(weakness.type) == "clue_tag":
			assert_true(_count_tagged(String(weakness.tag)) > 0, "%s: some clue carries the '%s' tag" % [id, weakness.tag])
		elif String(weakness.type) == "not_clue_tag":
			assert_true(_count_tagged(String(weakness.tag)) > 0, "%s: some clue DOES carry '%s', so 'lacks it' is not an always-on bonus" % [id, weakness.tag])
			assert_true(_count_tagged(String(weakness.tag)) < ClueDatabase.count(), "%s: and not every clue does" % id)

func _test_boss_definition() -> void:
	var boss := EnemyDatabase.get_enemy("boss_thesaurus")
	assert_true(bool(boss.is_boss), "the Thesaurus is a boss")
	assert_true(bool(boss.get("no_counter_on_hit", false)), "it only strikes on a miss")
	assert_false(boss.has("weakness_pending"), "its weakness is no longer pending")
	assert_eq(String(boss.weakness.type), "exact_match", "its weakness is exact-match")
	assert_between(float(boss.weakness.penalty_multiplier), 0.01, 0.99, "with a real penalty for the alternate")

	var phases: Array = boss.phases
	assert_eq(phases.size(), 3, "three phases")
	assert_approx(float(phases[0].hp_threshold), 1.0, "phase 1 starts at full health")
	var previous := 2.0
	for index in range(phases.size()):
		var phase: Dictionary = phases[index]
		assert_eq(int(phase.phase), index + 1, "phases are numbered in order")
		assert_lt(float(phase.hp_threshold), previous, "phase %d starts lower than the one before" % (index + 1))
		previous = float(phase.hp_threshold)
		assert_true(BOSS_ABILITIES.has(String(phase.ability)), "phase %d's ability is implemented (%s)" % [index + 1, phase.ability])

func _test_clue_tags() -> void:
	var counts := {"compound": 0, "homophone": 0, "abbreviation": 0}
	var compound_halves_ok := true
	for clue in ClueDatabase.get_all_clues():
		var tags: Array = clue.get("tags", [])
		for tag in tags:
			assert_true(TAGS.has(String(tag)), "%s: tag '%s' is known" % [clue.id, tag])
			counts[String(tag)] += 1

		var is_abbreviation := ClueResolver.has_tag(clue, "abbreviation")
		assert_eq(String(clue.category) == "GAME_JARGON", is_abbreviation, "%s: the GAME_JARGON category is exactly the abbreviations" % clue.id)
		assert_true(Constants.CATEGORIES.has(String(clue.category)), "%s has a known category" % clue.id)
		if is_abbreviation:
			assert_eq(String(clue.answer), String(clue.answer).to_upper(), "%s is upper case" % clue.id)
			assert_true(String(clue.clue).ends_with("for short"), "%s's clue says it is an abbreviation" % clue.id)

		if ClueResolver.has_tag(clue, "compound"):
			assert_true(_splits_into_words(String(clue.answer)), "%s really is two dictionary words joined" % clue.answer)
		if ClueResolver.has_tag(clue, "homophone"):
			assert_false((clue.get("homophones", []) as Array).is_empty(), "%s lists its homophones" % clue.answer)
			for twin in clue.homophones:
				assert_ne(String(twin).to_upper(), String(clue.answer), "%s's twin is a different spelling" % clue.answer)
	assert_gt(float(counts.compound), 14.0, "at least 15 compound clues (%d)" % counts.compound)
	assert_gt(float(counts.homophone), 4.0, "at least 5 homophone clues (%d)" % counts.homophone)
	assert_gt(float(counts.abbreviation), 5.0, "at least 6 abbreviation clues (%d)" % counts.abbreviation)

func _test_boss_rounds() -> void:
	var data := ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH)
	for key in ["antonym", "archaic"]:
		assert_true(String(data.prompts[key]).contains("%s"), "the %s prompt template takes the clue text" % key)

	var variants: Dictionary = data.synonym_variants
	assert_gt(float(variants.size()), 29.0, "at least 30 reworded clues (%d)" % variants.size())
	for id in variants:
		var clue := ClueDatabase.get_clue(String(id))
		assert_ne(String(clue.id), "clue_fallback", "variant id %s exists" % id)
		assert_ne(String(variants[id]), String(clue.clue), "%s's variant is actually reworded" % id)
		assert_false(String(variants[id]).to_upper().contains(String(clue.answer)), "%s's variant does not give away the answer" % id)

	var pairs: Array = data.antonym_pairs
	assert_gt(float(pairs.size()), 5.0, "at least six opposite pairs")
	var in_a_pair: Dictionary = {}
	for pair in pairs:
		for id in pair:
			# "Opposite of <clue>" must have exactly one right answer, so a
			# clue may belong to only one pair.
			assert_false(in_a_pair.has(String(id)), "%s is in only one opposite pair (otherwise its prompt is ambiguous)" % id)
			in_a_pair[String(id)] = true
	for pair in pairs:
		var a := ClueDatabase.get_clue(String(pair[0]))
		var b := ClueDatabase.get_clue(String(pair[1]))
		assert_true(String(a.id) != "clue_fallback" and String(b.id) != "clue_fallback", "pair %s / %s exists" % [pair[0], pair[1]])
		assert_ne(String(a.answer), String(b.answer), "%s and %s are different words" % [pair[0], pair[1]])

	var archaic: Array = data.archaic_spellings
	assert_gt(float(archaic.size()), 5.0, "at least six archaic spellings")
	for entry in archaic:
		var clue := ClueDatabase.get_clue(String(entry.clue_id))
		var spelling := String(entry.archaic)
		assert_ne(String(clue.id), "clue_fallback", "archaic entry %s exists" % entry.clue_id)
		assert_ne(spelling, String(clue.answer), "%s's archaic spelling differs from the modern one" % entry.clue_id)
		assert_eq(ClueResolver.normalize(spelling), spelling, "%s's archaic spelling is plain upper-case letters" % entry.clue_id)
		assert_gt(float(spelling.length()), 2.0, "%s's archaic spelling is a real word length" % entry.clue_id)

func _test_ability_rules() -> void:
	var rules := ConfigLoader.load_json(Constants.ABILITY_RULES_PATH)
	for rule in rules.mishearing.phonetic_rules:
		assert_eq((rule as Array).size(), 2, "a phonetic rule is a [from, to] pair")
		assert_ne(String(rule[0]), "", "and has something to replace")
		assert_ne(String(rule[0]), String(rule[1]), "and changes it")
	var swaps: Dictionary = rules.mishearing.word_swaps
	assert_gt(float(swaps.size()), 30.0, "plenty of sound-alike swaps")
	for word in swaps:
		assert_eq(String(word), String(word).to_lower(), "swap key '%s' is lower case" % word)
		assert_ne(String(swaps[word]), String(word), "'%s' is swapped for something different" % word)
	assert_true(String(rules.blend.separator).strip_edges() != "", "the blend separator is visible")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _count_tagged(tag: String) -> int:
	var count := 0
	for clue in ClueDatabase.get_all_clues():
		if ClueResolver.has_tag(clue, tag):
			count += 1
	return count

## True if [param word] splits into two words of 3+ letters. The word list is
## a curated common-words list, so a half counts if it or its plural is in it
## (STAIR is not listed, STAIRS is).
func _splits_into_words(word: String) -> bool:
	for i in range(3, word.length() - 2):
		if _is_word(word.substr(0, i)) and _is_word(word.substr(i)):
			return true
	return false

func _is_word(candidate: String) -> bool:
	return ChainDetector.is_valid_word(candidate) or ChainDetector.is_valid_word(candidate + "S")
