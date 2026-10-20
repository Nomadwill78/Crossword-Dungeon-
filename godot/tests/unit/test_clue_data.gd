#============================================================================
# test_clue_data.gd
# Data-integrity checks for the clue pool (clues_master.json) and the boss's
# round content built on it. Content lives in JSON (CLAUDE.md 2.1), so a typo
# or a careless addition there is the likeliest way to break a run: a clue whose
# answer is wrong-length, a duplicate that makes two clues ambiguous, an answer
# the dictionary does not know, a clue that gives its own answer away.
#============================================================================

class_name TestClueData
extends TestSuite

const MIN_CLUES: int = 350
const MIN_PER_LENGTH: int = 25
const MIN_PER_CATEGORY: int = 40
const MIN_JARGON: int = 10
const MAX_DIFFICULTY: int = 3

func _init() -> void:
	suite_name = "ClueData"

func run(_host: Node) -> void:
	ClueDatabase.reset_cache()
	ChainDetector.reset_cache()
	_test_every_clue_is_well_formed()
	_test_no_two_clues_collide()
	_test_difficulty_follows_length()
	_test_answers_are_dictionary_words()
	_test_clues_do_not_give_themselves_away()
	_test_the_pool_is_big_and_balanced()
	_test_boss_round_content()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func _test_every_clue_is_well_formed() -> void:
	var letters := RegEx.new()
	letters.compile("^[A-Z]{3,10}$")
	for clue in ClueDatabase.get_all_clues():
		var answer := String(clue.answer)
		assert_true(letters.search(answer) != null, "%s: the answer is 3-10 capital letters" % clue.id)
		assert_eq(int(clue.length), answer.length(), "%s: length matches the answer" % clue.id)
		assert_eq(String(clue.id), "clue_%s_%s" % [String(clue.id).split("_")[1], answer.to_lower()], "%s: the id is clue_<number>_<answer>" % clue.id)
		var text := String(clue.clue)
		assert_true(text.length() >= 12 and text.length() <= 70, "%s: the clue is a short sentence (%d characters)" % [clue.id, text.length()])
		assert_false(text.ends_with("."), "%s: clues carry no trailing period, like the rest of the pool" % clue.id)
		var homophones: Array = clue.get("homophones", [])
		assert_eq(ClueResolver.has_tag(clue, "homophone"), not homophones.is_empty(), "%s: the homophone tag and the homophones list go together" % clue.id)
		for homophone in homophones:
			assert_true(letters.search(String(homophone)) != null, "%s: homophone %s is capital letters" % [clue.id, homophone])
			assert_ne(String(homophone), answer, "%s: a homophone is a different word" % clue.id)

func _test_no_two_clues_collide() -> void:
	var ids := {}
	var answers := {}
	var texts := {}
	var numbers := {}
	for clue in ClueDatabase.get_all_clues():
		assert_false(ids.has(clue.id), "%s: id is unique" % clue.id)
		ids[clue.id] = true
		assert_false(answers.has(String(clue.answer)), "%s: no other clue has this answer" % clue.id)
		answers[String(clue.answer)] = true
		assert_false(texts.has(String(clue.clue).to_lower()), "%s: no other clue has this text" % clue.id)
		texts[String(clue.clue).to_lower()] = true
		var number := String(clue.id).split("_")[1]
		assert_false(numbers.has(number), "%s: the number in the id is unique" % clue.id)
		numbers[number] = true

func _test_difficulty_follows_length() -> void:
	# Difficulty sets the clock (game_config timer) and the damage bonus, and
	# the pool has always scaled it with word length: short words easy, long
	# words hard. The abbreviations are the exception, they are 3-4 letters but
	# not guessable from the letters alone.
	for clue in ClueDatabase.get_all_clues():
		var difficulty := int(clue.difficulty)
		assert_between(float(difficulty), 1.0, float(MAX_DIFFICULTY), "%s: difficulty is 1-%d" % [clue.id, MAX_DIFFICULTY])
		if ClueResolver.has_tag(clue, "abbreviation"):
			continue  # 3-4 letters, but not guessable from the letters alone: set by hand
		var length := int(clue.length)
		var expected := 1 if length <= 4 else (2 if length <= 7 else 3)
		if length <= 3:
			continue  # the original three-letter clues are mixed; only the longer bands are pinned
		assert_eq(difficulty, expected, "%s: a %d-letter answer is difficulty %d" % [clue.id, length, expected])

func _test_answers_are_dictionary_words() -> void:
	# The chain detector scores words by looking them up, and the dictionary
	# has always held every clue answer (the abbreviations apart), so a new
	# answer that is missing from words_en.json is a content bug.
	for clue in ClueDatabase.get_all_clues():
		if ClueResolver.has_tag(clue, "abbreviation"):
			continue
		assert_true(ChainDetector.is_valid_word(String(clue.answer)), "%s: the answer is in the dictionary" % clue.id)

func _test_clues_do_not_give_themselves_away() -> void:
	for clue in ClueDatabase.get_all_clues():
		var answer := String(clue.answer).to_lower()
		var text := String(clue.clue).to_lower()
		assert_false(_contains_word(text, answer), "%s: the clue does not contain its own answer" % clue.id)
		if answer.length() >= 5:
			var stem := answer.substr(0, maxi(4, answer.length() - 2))
			assert_false(_starts_a_word(text, stem), "%s: nor a long start of it (%s)" % [clue.id, stem])

func _test_the_pool_is_big_and_balanced() -> void:
	assert_gt(float(ClueDatabase.count()), float(MIN_CLUES - 1), "the pool has at least %d clues" % MIN_CLUES)
	var by_length := {}
	var by_category := {}
	for clue in ClueDatabase.get_all_clues():
		by_length[int(clue.length)] = int(by_length.get(int(clue.length), 0)) + 1
		by_category[String(clue.category)] = int(by_category.get(String(clue.category), 0)) + 1
	for length in range(3, 11):
		assert_gt(float(by_length.get(length, 0)), float(MIN_PER_LENGTH - 1), "at least %d clues have %d letters" % [MIN_PER_LENGTH, length])
	for category in Constants.CATEGORIES:
		var floor_value := MIN_JARGON if category == "GAME_JARGON" else MIN_PER_CATEGORY
		assert_gt(float(by_category.get(category, 0)), float(floor_value - 1), "%s has at least %d clues" % [category, floor_value])

func _test_boss_round_content() -> void:
	var rounds: Dictionary = ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH)
	var answers := {}
	for clue in ClueDatabase.get_all_clues():
		answers[String(clue.answer)] = true

	var variants: Dictionary = rounds.synonym_variants
	assert_gt(float(variants.size()), 59.0, "phase 1 has a deep pool of reworded clues")
	for id in variants:
		var clue := ClueDatabase.get_clue(String(id))
		assert_eq(String(clue.id), String(id), "%s: a reworded clue belongs to a real clue" % id)
		assert_ne(String(variants[id]).to_lower(), String(clue.clue).to_lower(), "%s: the rewording is different" % id)
		assert_false(_contains_word(String(variants[id]).to_lower(), String(clue.answer).to_lower()), "%s: and does not give the answer away" % id)

	var in_pairs := {}
	var pairs: Array = rounds.antonym_pairs
	assert_gt(float(pairs.size()), 11.0, "phase 2 has a deep pool of opposite pairs")
	for pair in pairs:
		for id in pair:
			assert_false(in_pairs.has(String(id)), "%s: appears in only one pair" % id)
			in_pairs[String(id)] = true
			assert_eq(String(ClueDatabase.get_clue(String(id)).id), String(id), "%s: a pair uses real clues" % id)

	var archaic_seen := {}
	var spellings: Array = rounds.archaic_spellings
	assert_gt(float(spellings.size()), 11.0, "phase 3 has a deep pool of archaic spellings")
	for entry in spellings:
		var clue := ClueDatabase.get_clue(String(entry.clue_id))
		var archaic := String(entry.archaic).to_upper()
		assert_eq(String(clue.id), String(entry.clue_id), "%s: an archaic spelling belongs to a real clue" % entry.clue_id)
		assert_ne(archaic, String(clue.answer), "%s: the archaic spelling is not the modern one" % entry.clue_id)
		assert_false(answers.has(archaic), "%s: and is not some other clue's answer" % archaic)
		assert_false(archaic_seen.has(String(entry.clue_id)), "%s: each clue has one archaic spelling" % entry.clue_id)
		archaic_seen[String(entry.clue_id)] = true

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------

## True when [param word] appears in [param text] as a whole word.
func _contains_word(text: String, word: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("\\b%s\\b" % word)
	return pattern.search(text) != null

## True when some word in [param text] begins with [param stem].
func _starts_a_word(text: String, stem: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("\\b%s" % stem)
	return pattern.search(text) != null
