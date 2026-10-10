#============================================================================
# ClueResolver.gd
# Validates a player's typed answer against a clue. Owns answer
# normalization so every system agrees on what "the same answer" means.
# Dependencies: none (operates on plain clue Dictionaries)
# Events: none - the state machine decides what to emit from the verdict
#============================================================================

class_name ClueResolver
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Normalizes a raw typed answer: trims, uppercases, and strips everything
## that is not a letter. Crossword answers are letters only, so spaces and
## punctuation a player types (or a phone keyboard inserts) are noise rather
## than a wrong answer.
static func normalize(raw_answer: String) -> String:
	var out := ""
	for ch in raw_answer.strip_edges().to_upper():
		if ch >= "A" and ch <= "Z":
			out += ch
	return out

## Checks [param raw_answer] against [param clue].
##
## [param raw_answer] Whatever the player typed, unnormalized
## [param clue] A clue Dictionary (from ClueDatabase)
## [return] Dictionary with:
##   is_correct        - bool, the answer matches the expected word
##   normalized        - String, the cleaned-up answer
##   expected          - String, the clue's answer
##   expected_length   - int
##   length_matches    - bool, right number of letters (useful for UI hints
##                       like "5 letters" turning green before submission)
##   is_empty          - bool, nothing usable was typed
##   alternate         - Dictionary, the matching entry of clue.alternates when
##                       the answer was accepted as an alternate rather than
##                       the exact answer; {} otherwise
static func validate(raw_answer: String, clue: Dictionary) -> Dictionary:
	var normalized := normalize(raw_answer)
	var expected := String(clue.get("answer", "")).to_upper()
	var expected_length: int = int(clue.get("answer_length", clue.get("length", expected.length())))
	var alternate := alternate_for(normalized, clue)

	return {
		"is_correct": normalized != "" and (normalized == expected or not alternate.is_empty()),
		"alternate": alternate,
		"normalized": normalized,
		"expected": expected,
		"expected_length": expected_length,
		"length_matches": normalized.length() == expected_length,
		"is_empty": normalized.is_empty(),
	}

## The entry of [param clue].alternates that [param normalized] matches, or {}.
## An alternate is an extra accepted answer - { answer, damage_multiplier } -
## that is not the exact one. The boss's archaic-spelling phase uses it: the
## modern spelling is still right, but deals reduced damage. The exact answer
## never counts as an alternate.
static func alternate_for(normalized: String, clue: Dictionary) -> Dictionary:
	if normalized == "" or normalized == String(clue.get("answer", "")).to_upper():
		return {}
	for entry in clue.get("alternates", []):
		if normalize(String(entry.get("answer", ""))) == normalized:
			return entry
	return {}

## True when [param clue] carries [param tag] in its `tags` list
## (clues_master.json tags clues as compound, homophone or abbreviation).
static func has_tag(clue: Dictionary, tag: String) -> bool:
	return Array(clue.get("tags", [])).has(tag)

## How many letters of [param raw_answer] are in the right position. Not used
## for damage; exposed for UI feedback and for bots that want a "warmer /
## colder" signal without being handed the answer.
static func correct_letter_count(raw_answer: String, clue: Dictionary) -> int:
	var normalized := normalize(raw_answer)
	var expected := String(clue.get("answer", "")).to_upper()
	var count := 0
	for i in range(min(normalized.length(), expected.length())):
		if normalized[i] == expected[i]:
			count += 1
	return count
