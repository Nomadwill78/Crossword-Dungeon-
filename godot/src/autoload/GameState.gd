## Autoload singleton. Holds the in-progress run, the persistent player
## profile, settings, and lifetime statistics. Mostly a passive data holder —
## gameplay scenes (e.g. DungeonScene) read and mutate `current_run` directly.
extends Node

## The active dungeon run. Shape (set by DungeonScene._start_new_run):
## { run_id, started_at, difficulty, grid_size, dungeon_depth, player_state,
##   grid_state, combat_log, boss_encountered, boss_defeated, run_status }
var current_run: Dictionary = {}

## Persists across runs. Loaded/saved by SaveManager.
var player_profile: Dictionary = {
	"total_runs": 0,
	"runs_completed": 0,
	"best_score": 0,
	"total_ink_drops": 0,
	"dictionary_fragments": 0,
	"unlocked_vocabulary": [],
	"unlocked_word_count": 0,
}

## Shape matches the Technical Design Doc's settings schema (docs/design/
## technical_design_document.md, section 2.1).
var settings: Dictionary = {
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

var statistics: Dictionary = {
	"total_words_solved": 0,
	"total_enemies_defeated": 0,
	"total_bosses_defeated": 0,
	"longest_combo_streak": 0,
	"total_playtime_seconds": 0.0,
}

func reset_run() -> void:
	current_run = {}

func has_active_run() -> bool:
	return not current_run.is_empty() and current_run.get("run_status", "") == "in_progress"

func record_run_end(completed: bool, score: int) -> void:
	player_profile.total_runs += 1
	if completed:
		player_profile.runs_completed += 1
	player_profile.best_score = max(player_profile.best_score, score)
