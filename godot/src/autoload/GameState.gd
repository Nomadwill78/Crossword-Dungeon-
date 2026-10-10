## Autoload singleton. Holds the in-progress run, the persistent player
## profile, the Lexicon, settings, and lifetime statistics. Mostly a passive
## data holder - gameplay scenes (e.g. DungeonScene) read and mutate
## `current_run` directly, and the Lexicon systems (InkDropManager,
## VocabularyTree, TomeManager, ...) operate on the dictionaries below when
## they are passed in.
##
## Each persistent section has a default_*() function returning a fresh
## pristine copy. SaveManager merges loaded data over those, so a save from an
## older build that lacks a newer key still loads with that key defaulted.
extends Node

## The active dungeon run. Shape (set by DungeonScene._start_new_run):
## { run_id, started_at, difficulty, grid_size, dungeon_depth, player_state,
##   grid_state, combat_log, tally, boss_encountered, boss_defeated, run_status }
var current_run: Dictionary = {}

## Persists across runs. Loaded/saved by SaveManager.
##   ink_drops        spendable balance
##   total_ink_drops  everything ever collected; drives player_level
## See InkDropManager for how the two move.
var player_profile: Dictionary = default_profile()

## The Lexicon: vocabulary-tree purchases, owned and equipped tomes, themes
## and achievements (Technical Design Doc 2.1). Empty until first use, then
## built from the data files by get_lexicon() - it cannot be built in _ready
## because ConfigLoader, the last autoload, may not be initialised yet.
var lexicon: Dictionary = {}

## Options the Lexicon's Delve panel hands to the next run, e.g.
## { "grid_size": 7 }. DungeonScene reads and then clears it.
var run_options: Dictionary = {}

## Shape matches the Technical Design Doc's settings schema (docs/design/
## technical_design_document.md, section 2.1).
var settings: Dictionary = default_settings()

var statistics: Dictionary = default_statistics()

static func default_profile() -> Dictionary:
	return {
		"total_runs": 0,
		"runs_completed": 0,
		"best_score": 0,
		"ink_drops": 0,
		"total_ink_drops": 0,
		"player_level": 1,
		"total_letters_solved": 0,
		"longest_chain": 0,
		"current_streak_days": 0,
		"longest_streak_days": 0,
		"last_login_date": "",
		"dictionary_fragments": 0,
		"unlocked_vocabulary": [],
		"unlocked_word_count": 0,
	}

static func default_settings() -> Dictionary:
	return {
		"audio": {
			"master_volume": 0.8,
			"music_volume": 0.6,
			"sfx_volume": 0.9,
		},
		"display": {
			"fullscreen": false,
			"grid_theme": "default",
			"colorblind_mode": "none",
			"dyslexia_font": false,
			"text_size": "medium",
		},
		"gameplay": {
			"difficulty": "standard",
			"timer_visible": true,
			"hint_enabled": true,
			"auto_save": true,
			"auto_save_interval_seconds": 60,
		},
		"accessibility": {
			"screen_reader": false,
			"high_contrast": false,
			"reduced_motion": false,
			"extended_timer": false,
		},
	}

static func default_statistics() -> Dictionary:
	return {
		"total_words_solved": 0,
		"total_enemies_defeated": 0,
		"total_bosses_defeated": 0,
		"total_chains": 0,
		"chains_by_length": {},
		"total_deaths": 0,
		"longest_combo_streak": 0,
		"total_playtime_seconds": 0.0,
	}

func reset_run() -> void:
	current_run = {}

func has_active_run() -> bool:
	return not current_run.is_empty() and current_run.get("run_status", "") == "in_progress"

## The lexicon, built from the data files on first use.
func get_lexicon() -> Dictionary:
	if lexicon.is_empty():
		lexicon = LexiconState.default_state()
	return lexicon
