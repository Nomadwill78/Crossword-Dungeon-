#============================================================================
# test_save_manager.gd
# Persistence of the Lexicon and profile: round trips, saves from older
# builds, unknown ids, corrupt files, and the atomic-write / backup behaviour.
#
# Runs against a scratch directory, never the player's real save, and puts
# the GameState it borrows back when it is done.
#============================================================================

class_name TestSaveManager
extends TestSuite

const SCRATCH_DIR := "user://test_saves/"
const SAVE_FILE := "user://test_saves/save.json"
const BACKUPS := "user://test_saves/backups/"

var _manager: Node = null
var _saved_profile: Dictionary
var _saved_lexicon: Dictionary
var _saved_settings: Dictionary
var _saved_statistics: Dictionary

func _init() -> void:
	suite_name = "SaveManager"

func run(_host: Node) -> void:
	_begin()
	_test_round_trip()
	_test_old_save_gets_defaults()
	_test_unknown_ids_are_dropped()
	_test_corrupt_files()
	_test_progression_repair()
	_test_atomic_write_and_backups()
	_test_merge_with_defaults()
	_end()

#----------------------------------------------------------------------------
# FIXTURE
#----------------------------------------------------------------------------
func _begin() -> void:
	_saved_profile = GameState.player_profile.duplicate(true)
	_saved_lexicon = GameState.lexicon.duplicate(true)
	_saved_settings = GameState.settings.duplicate(true)
	_saved_statistics = GameState.statistics.duplicate(true)

	_manager = load("res://src/autoload/SaveManager.gd").new()
	_manager.save_path = SAVE_FILE
	_manager.backup_dir = BACKUPS
	_wipe_scratch()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

func _end() -> void:
	_wipe_scratch()
	_manager.free()
	GameState.player_profile = _saved_profile
	GameState.lexicon = _saved_lexicon
	GameState.settings = _saved_settings
	GameState.statistics = _saved_statistics

func _wipe_scratch() -> void:
	for dir_path in [BACKUPS, SCRATCH_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				dir.remove(name)
			name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(BACKUPS)
	DirAccess.remove_absolute(SCRATCH_DIR)

func _reset_game_state() -> void:
	GameState.player_profile = GameState.default_profile()
	GameState.lexicon = {}
	GameState.settings = GameState.default_settings()
	GameState.statistics = GameState.default_statistics()

func _write_raw(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func _test_round_trip() -> void:
	_reset_game_state()
	var lexicon := GameState.get_lexicon()
	InkDropManager.award(GameState.player_profile, 3400, "test")
	VocabularyTree.purchase(lexicon, GameState.player_profile, "bst_01")
	VocabularyTree.purchase(lexicon, GameState.player_profile, "bst_02")
	lexicon.unlocked_tomes.append("tome_timer_01")
	TomeManager.equip(lexicon, "tome_timer_01")
	lexicon.achievements["first_run"] = true
	GameState.statistics["chains_by_length"] = { "3": 2, "5": 1 }
	GameState.player_profile["last_login_date"] = "2026-03-10"

	var level_before := int(GameState.player_profile.player_level)
	var balance_before := int(GameState.player_profile.ink_drops)
	assert_true(_manager.save_game(), "save_game succeeds")
	assert_true(FileAccess.file_exists(SAVE_FILE), "the save file exists")

	_reset_game_state()
	assert_true(_manager.load_game(), "load_game succeeds")

	var profile := GameState.player_profile
	assert_eq(typeof(profile.ink_drops), TYPE_INT, "Ink loads back as an int, not JSON's float")
	assert_eq(int(profile.ink_drops), balance_before, "the Ink balance survives")
	assert_eq(int(profile.player_level), level_before, "the level survives")
	assert_eq(String(profile.last_login_date), "2026-03-10", "the login date survives")

	var loaded := GameState.get_lexicon()
	assert_true(VocabularyTree.is_purchased(loaded, "bst_01") and VocabularyTree.is_purchased(loaded, "bst_02"), "vocabulary purchases survive")
	assert_false(VocabularyTree.is_purchased(loaded, "bst_03"), "and nothing extra appears")
	assert_eq(int(loaded.vocabulary_trees.bestiary.total_invested), 500, "total_invested is intact")
	assert_eq(loaded.equipped_tomes, ["tome_timer_01", null, null], "equipped tomes survive, empty slots stay null")
	assert_true(TomeManager.is_owned(loaded, "tome_timer_01"), "owned tomes survive")
	assert_true(AchievementTracker.is_earned(loaded, "first_run"), "achievements survive")
	assert_eq(int(GameState.statistics.chains_by_length["3"]), 2, "per-length chain counters survive as ints")
	assert_eq(typeof(GameState.statistics.chains_by_length["3"]), TYPE_INT, "and are ints, not floats")

func _test_old_save_gets_defaults() -> void:
	# What a Milestone 1/2 build wrote: no lexicon, no ink_drops, no level.
	_write_raw(JSON.stringify({
		"schema_version": 1,
		"player_profile": { "total_runs": 4, "runs_completed": 2, "best_score": 99, "total_ink_drops": 0, "dictionary_fragments": 3, "unlocked_vocabulary": [], "unlocked_word_count": 0 },
		"settings": { "audio": { "master_volume": 0.5 } },
		"statistics": { "total_words_solved": 12 },
	}))
	_reset_game_state()
	assert_true(_manager.load_game(), "an older save loads")

	assert_eq(int(GameState.player_profile.total_runs), 4, "its old values are kept")
	assert_eq(int(GameState.player_profile.ink_drops), 0, "new profile keys are defaulted")
	assert_eq(int(GameState.player_profile.player_level), 1, "including the level")
	assert_approx(float(GameState.settings.audio.master_volume), 0.5, "a partial settings block keeps what it had")
	assert_approx(float(GameState.settings.audio.music_volume), 0.6, "and defaults what it lacked")
	assert_true(GameState.settings.has("accessibility"), "whole missing sections are defaulted")
	assert_eq(int(GameState.statistics.total_words_solved), 12, "statistics keep old values")
	assert_true(GameState.statistics.has("total_chains"), "and gain new keys")
	assert_eq((GameState.get_lexicon().vocabulary_trees as Dictionary).size(), LexiconData.tree_ids().size(), "a missing lexicon becomes a full default one")
	assert_eq((GameState.get_lexicon().equipped_tomes as Array).size(), 3, "with three empty slots")

func _test_unknown_ids_are_dropped() -> void:
	var raw := LexiconState.default_state()
	raw.vocabulary_trees.bestiary.nodes_purchased = ["bst_01", "bst_01", "zzz_99", "arc_01"]
	raw.unlocked_tomes = ["tome_timer_01", "tome_nope", "tome_timer_01"]
	raw.equipped_tomes = ["tome_nope", "tome_healing_01", "tome_timer_01"]
	raw.achievements["made_up"] = true
	raw.active_theme = "a_theme_i_do_not_own"
	_write_raw(JSON.stringify({ "schema_version": 1, "lexicon": raw }))
	_reset_game_state()
	assert_true(_manager.load_game(), "a save with stale ids still loads")

	var lexicon := GameState.get_lexicon()
	assert_eq(lexicon.vocabulary_trees.bestiary.nodes_purchased, ["bst_01"], "unknown, duplicate and wrong-tree nodes are dropped")
	assert_eq(lexicon.unlocked_tomes, ["tome_timer_01"], "unknown and duplicate tomes are dropped")
	assert_eq(lexicon.equipped_tomes, [null, null, "tome_timer_01"], "an unowned or unknown tome cannot stay equipped")
	assert_false(lexicon.achievements.has("made_up"), "unknown achievements are dropped")
	assert_eq(String(lexicon.active_theme), "default", "an unowned theme falls back to the default")
	assert_eq(int(lexicon.vocabulary_trees.bestiary.total_invested), int(LexiconData.get_node_def("bst_01").cost), "total_invested is recomputed from what is really owned")
	assert_true((lexicon.vocabulary_trees.bestiary.nodes_unlocked as Array).has("bst_02"), "nodes_unlocked is recomputed")

func _test_corrupt_files() -> void:
	_reset_game_state()
	GameState.player_profile["total_runs"] = 77

	_write_raw("{ this is not json")
	assert_false(_manager.load_game(), "garbage JSON is refused")
	assert_eq(int(GameState.player_profile.total_runs), 77, "and leaves the game state alone")

	_write_raw("[1, 2, 3]")
	assert_false(_manager.load_game(), "JSON that is not an object is refused")

	_write_raw(JSON.stringify({ "schema_version": 1, "player_profile": "oops", "lexicon": 5, "settings": [], "statistics": null }))
	assert_true(_manager.load_game(), "wrongly-typed sections fall back instead of crashing")
	assert_eq(int(GameState.player_profile.total_runs), 0, "the profile is defaulted")
	assert_eq((GameState.get_lexicon().equipped_tomes as Array).size(), 3, "the lexicon is defaulted")

	DirAccess.remove_absolute(SAVE_FILE)
	assert_false(_manager.load_game(), "a missing save reports false (a fresh install)")

func _test_progression_repair() -> void:
	var lifetime := 5000
	_write_raw(JSON.stringify({
		"schema_version": 1,
		"player_profile": { "total_ink_drops": lifetime, "ink_drops": 999999, "player_level": 1 },
	}))
	_reset_game_state()
	_manager.load_game()
	assert_eq(int(GameState.player_profile.ink_drops), lifetime, "a balance above lifetime Ink is clamped")
	assert_eq(int(GameState.player_profile.player_level), PlayerLevel.level_for_ink(lifetime), "a stale level is raised to match lifetime Ink")

	_write_raw(JSON.stringify({
		"schema_version": 1,
		"player_profile": { "total_ink_drops": 0, "ink_drops": -50, "player_level": 999 },
	}))
	_manager.load_game()
	assert_eq(int(GameState.player_profile.ink_drops), 0, "a negative balance is clamped to zero")
	assert_eq(int(GameState.player_profile.player_level), PlayerLevel.max_level(), "an absurd level is capped")

func _test_atomic_write_and_backups() -> void:
	_reset_game_state()
	GameState.get_lexicon()
	for i in range(8):
		GameState.player_profile["total_runs"] = i
		assert_true(_manager.save_game(), "save #%d succeeds" % i)
		OS.delay_msec(1100)  # backups are named by unix second

	assert_false(FileAccess.file_exists(SAVE_FILE + ".tmp"), "no temp file is left behind after a save")
	var backups := 0
	var dir := DirAccess.open(BACKUPS)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("backup_"):
				backups += 1
			name = dir.get_next()
		dir.list_dir_end()
	var max_backups := int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).save.max_backups)
	assert_eq(backups, max_backups, "seven rotations leave exactly the configured maximum of backups")

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the save on disk is valid JSON")
	assert_eq(int(parsed.player_profile.total_runs), 7, "and holds the latest state")
	assert_true(parsed.has("lexicon"), "and includes the lexicon")
	assert_eq(int(parsed.schema_version), 1, "the schema version is unchanged (the lexicon is an additive key)")

func _test_merge_with_defaults() -> void:
	var defaults := { "a": 1, "b": 2.5, "c": "x", "d": { "e": 1, "f": true }, "g": [1] }

	var merged: Dictionary = _manager.merge_with_defaults(defaults, {})
	assert_eq(merged, defaults, "merging nothing yields the defaults")
	merged["d"]["e"] = 99
	assert_eq(int(defaults.d.e), 1, "the merge does not alias the defaults")

	merged = _manager.merge_with_defaults(defaults, { "a": 7.0, "b": 3, "c": 5, "d": "not a dict", "g": "nope", "extra": { "n": 4.0, "list": [2.0, 2.5] } })
	assert_eq(typeof(merged.a), TYPE_INT, "a whole float loads into an int field as an int")
	assert_eq(int(merged.a), 7, "with its value")
	assert_eq(typeof(merged.b), TYPE_FLOAT, "an int loads into a float field as a float")
	assert_eq(String(merged.c), "x", "a wrongly typed value falls back to the default")
	assert_eq(merged.d, defaults.d, "a non-dict where a dict belongs falls back")
	assert_eq(merged.g, [1], "a non-array where an array belongs falls back")
	assert_eq(typeof(merged.extra.n), TYPE_INT, "unknown keys keep their data, with whole floats turned to ints")
	assert_eq(typeof(merged.extra.list[0]), TYPE_INT, "even inside arrays")
	assert_eq(typeof(merged.extra.list[1]), TYPE_FLOAT, "while real fractions stay floats")
