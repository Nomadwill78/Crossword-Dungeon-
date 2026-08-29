#============================================================================
# WordProperties.gd
# Pure predicates over an answer word, used to evaluate the data-driven
# enemy weakness/resistance rules in enemies_master.json
# ("weakness": {"type": "word_property", "property": "double_letter", ...}).
# Dependencies: none
# Events: none
#============================================================================

class_name WordProperties
extends RefCounted

## Every property name this class can evaluate. Anything in enemies_master.json
## outside this set is a data error, and `has_property` says so loudly rather
## than silently returning false and quietly disabling an enemy's weakness.
const SUPPORTED_PROPERTIES: Array[String] = [
	"double_letter",
	"palindrome",
	"single_letter",
	"no_repeated_letter",
]

## Evaluates [param property] against [param word]. Returns false and warns if
## the property name is not one this build knows how to compute.
static func has_property(word: String, property: String) -> bool:
	var normalized := word.strip_edges().to_upper()
	match property:
		"double_letter":
			return has_double_letter(normalized)
		"palindrome":
			return is_palindrome(normalized)
		"single_letter":
			return normalized.length() == 1
		"no_repeated_letter":
			return not has_repeated_letter(normalized)
	push_warning("WordProperties: unknown property '%s' (supported: %s)" % [property, ", ".join(SUPPORTED_PROPERTIES)])
	return false

## True when the word contains the same letter twice in a row (BALLOON, LETTER).
static func has_double_letter(word: String) -> bool:
	var w := word.to_upper()
	for i in range(w.length() - 1):
		if w[i] == w[i + 1]:
			return true
	return false

## True when the word reads the same forwards and backwards (RADAR, LEVEL).
## Single letters are excluded - trivially palindromic, not interesting.
static func is_palindrome(word: String) -> bool:
	var w := word.to_upper()
	if w.length() < 2:
		return false
	return w == w.reverse()

## True when any letter appears more than once anywhere in the word.
static func has_repeated_letter(word: String) -> bool:
	var seen: Dictionary = {}
	for ch in word.to_upper():
		if seen.has(ch):
			return true
		seen[ch] = true
	return false
