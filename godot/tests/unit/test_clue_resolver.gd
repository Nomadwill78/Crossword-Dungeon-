#============================================================================
# test_clue_resolver.gd
# Unit tests for answer normalization/validation and the word-property
# predicates that back enemy weaknesses.
#============================================================================

class_name TestClueResolver
extends TestSuite

func _init() -> void:
	suite_name = "ClueResolver"

func run(_host: Node) -> void:
	test_normalization()
	test_exact_match()
	test_case_and_whitespace_insensitive()
	test_wrong_answer_rejected()
	test_empty_answer_rejected()
	test_length_matches_flag()
	test_correct_letter_count()
	test_word_property_double_letter()
	test_word_property_palindrome()
	test_word_property_single_letter()
	test_unknown_word_property_is_false()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func test_normalization() -> void:
	assert_eq(ClueResolver.normalize("  cat  "), "CAT", "Trims and uppercases")
	assert_eq(ClueResolver.normalize("c a t"), "CAT", "Strips interior spaces")
	assert_eq(ClueResolver.normalize("c-a-t!"), "CAT", "Strips punctuation")
	assert_eq(ClueResolver.normalize("cat9"), "CAT", "Strips digits")
	assert_eq(ClueResolver.normalize("   "), "", "Whitespace only normalizes to empty")

func test_exact_match() -> void:
	var verdict := ClueResolver.validate("DRAGON", _clue("DRAGON"))
	assert_true(verdict.is_correct, "Exact answer is correct")
	assert_eq(verdict.normalized, "DRAGON", "Normalized answer echoed back")
	assert_eq(verdict.expected_length, 6, "Expected length reported")

func test_case_and_whitespace_insensitive() -> void:
	assert_true(ClueResolver.validate("dragon", _clue("DRAGON")).is_correct, "Lowercase accepted")
	assert_true(ClueResolver.validate(" DrAgOn ", _clue("DRAGON")).is_correct, "Mixed case + spaces accepted")

func test_wrong_answer_rejected() -> void:
	var verdict := ClueResolver.validate("GOBLIN", _clue("DRAGON"))
	assert_false(verdict.is_correct, "Different word rejected")
	assert_true(verdict.length_matches, "GOBLIN is still 6 letters")

func test_empty_answer_rejected() -> void:
	var verdict := ClueResolver.validate("", _clue("DRAGON"))
	assert_false(verdict.is_correct, "Empty answer is not correct")
	assert_true(verdict.is_empty, "Empty answer is flagged")

func test_length_matches_flag() -> void:
	assert_false(ClueResolver.validate("CAT", _clue("DRAGON")).length_matches, "3 != 6 letters")
	assert_true(ClueResolver.validate("WIZARD", _clue("DRAGON")).length_matches, "6 == 6 letters")

func test_correct_letter_count() -> void:
	# D_A_O_ vs DRAGON: positions 0 (D), 2 (A), 4 (O) line up.
	assert_eq(ClueResolver.correct_letter_count("DXAXOX", _clue("DRAGON")), 3, "Counts positional matches")
	assert_eq(ClueResolver.correct_letter_count("DRAGON", _clue("DRAGON")), 6, "All six match")
	assert_eq(ClueResolver.correct_letter_count("", _clue("DRAGON")), 0, "Empty matches nothing")

func test_word_property_double_letter() -> void:
	assert_true(WordProperties.has_double_letter("BALLOON"), "BALLOON has LL and OO")
	assert_true(WordProperties.has_double_letter("SCROLL"), "SCROLL has LL")
	assert_false(WordProperties.has_double_letter("DRAGON"), "DRAGON has no doubled letter")
	# A letter repeated but not adjacent is NOT a double letter.
	assert_false(WordProperties.has_double_letter("LEVEL"), "LEVEL repeats L but never adjacently")

func test_word_property_palindrome() -> void:
	assert_true(WordProperties.is_palindrome("LEVEL"), "LEVEL is a palindrome")
	assert_true(WordProperties.is_palindrome("radar"), "Case insensitive")
	assert_false(WordProperties.is_palindrome("DRAGON"), "DRAGON is not")
	assert_false(WordProperties.is_palindrome("A"), "Single letters do not count")

func test_word_property_single_letter() -> void:
	assert_true(WordProperties.has_property("A", "single_letter"), "A is a single letter")
	assert_false(WordProperties.has_property("CAT", "single_letter"), "CAT is not")

## An unrecognised property name is a data error; it must resolve to false
## (so the enemy simply has no weakness) rather than throwing.
func test_unknown_word_property_is_false() -> void:
	assert_false(WordProperties.has_property("CAT", "not_a_real_property"), "Unknown property is false")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _clue(answer: String) -> Dictionary:
	return {
		"id": "clue_test",
		"answer": answer,
		"length": answer.length(),
		"answer_length": answer.length(),
		"difficulty": 1,
	}
