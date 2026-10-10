#============================================================================
# DungeonScene.gd
# Main dungeon scene. Owns the grid, the player's position, and the handoff
# into and out of combat.
# Dependencies: GridGenerator, GridNavigator, GridRenderer, CombatScene,
#               ChainDetector, ChainEffects, ClueDatabase, EnemyDatabase,
#               LexiconEffects, InkDropManager, RunSettlement, RunSummaryPanel
# Events: listens on EventBus; emits run_started / run_ended
#============================================================================

class_name DungeonScene
extends Node2D

#----------------------------------------------------------------------------
# CONSTANTS
#----------------------------------------------------------------------------
const COMBAT_SCENE_PATH := "res://src/scenes/combat/CombatScene.tscn"
const LEXICON_SCENE_PATH := "res://src/scenes/lexicon/LexiconScene.tscn"

## Cap on cascading chain passes. Revealing letters can spell new words, which
## can reveal more; this stops a pathological grid from looping forever.
const MAX_CHAIN_CASCADES: int = 5

#----------------------------------------------------------------------------
# ONREADY VARIABLES
#----------------------------------------------------------------------------
@onready var _grid_renderer: GridRenderer = $GridRenderer
@onready var _ui_layer: CanvasLayer = $UI

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _navigator: GridNavigator = null
var _generator: GridGenerator = null
var _combat_scene: CombatScene = null
var _is_input_locked: bool = false
var _activated_chain_ids: Dictionary = {}
var _grid_size: int = 5
var _dungeon_depth: int = 1
var _grid_cleared: bool = false
var _summary_panel: RunSummaryPanel = null

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready() -> void:
	EventBus.grid_completed.connect(_on_grid_completed)
	EventBus.letter_solved.connect(_on_letter_solved)
	EventBus.chain_activated.connect(_on_chain_activated)
	_start_new_run()

func _input(event: InputEvent) -> void:
	if _is_input_locked or _navigator == null:
		return

	var direction := Vector2i.ZERO
	if event.is_action_pressed("ui_right"):
		direction = Vector2i(1, 0)
	elif event.is_action_pressed("ui_left"):
		direction = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_down"):
		direction = Vector2i(0, 1)
	elif event.is_action_pressed("ui_up"):
		direction = Vector2i(0, -1)

	if direction != Vector2i.ZERO:
		_attempt_move(direction)

#----------------------------------------------------------------------------
# PRIVATE METHODS - run setup
#----------------------------------------------------------------------------
func _start_new_run() -> void:
	var config: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var player_cfg: Dictionary = config.get("player", {})
	_grid_size = _pick_grid_size(int(config.get("grid", {}).get("default_size", 5)))
	_grid_cleared = false

	_generator = GridGenerator.new()
	var grid_state: Dictionary = _generator.generate_grid(_grid_size, _dungeon_depth, 1)

	_navigator = GridNavigator.new()
	_navigator.initialize(grid_state)
	_activated_chain_ids.clear()

	var start_pos: Vector2i = _navigator.get_player_position()
	var player_state: Dictionary = {
		"current_hp": int(player_cfg.get("starting_hp", 100)),
		"max_hp": int(player_cfg.get("starting_max_hp", 100)),
		"position": {"x": start_pos.x, "y": start_pos.y},
		"active_chains": [],
		"inventory": {"health_potions": 0, "dictionary_fragments": 0, "special_items": []},
		"combo_streak": 0,
		"skip_tokens": 0,
		"total_ink_drops_this_run": 0,
	}
	# Everything bought in the Lexicon takes effect here, once, at run start.
	LexiconEffects.apply_to_player_state(player_state, GameState.get_lexicon())

	GameState.current_run = {
		"run_id": _generate_run_id(),
		"started_at": _iso_timestamp(),
		"difficulty": String(GameState.settings.get("gameplay", {}).get("difficulty", "standard")),
		"grid_size": _grid_size,
		"dungeon_depth": _dungeon_depth,
		"player_state": player_state,
		"grid_state": grid_state,
		"combat_log": [],
		"tally": {
			"words_solved": 0,
			"letters_solved": 0,
			"enemies_defeated": 0,
			"bosses_defeated": 0,
			"chains_activated": 0,
			"chains_by_length": {},
			"longest_chain": 0,
		},
		"boss_encountered": false,
		"boss_defeated": false,
		"run_status": "in_progress",
	}

	_grid_renderer.initialize(grid_state)
	_highlight_reachable()
	_refresh_hud()

	EventBus.run_started.emit(
		String(GameState.current_run.run_id),
		String(GameState.current_run.difficulty),
		_grid_size
	)

#----------------------------------------------------------------------------
# PRIVATE METHODS - movement
#----------------------------------------------------------------------------
func _attempt_move(direction: Vector2i) -> void:
	var target: Vector2i = _navigator.get_player_position() + direction

	# Walking into an unsolved letter starts a Word Duel instead of moving.
	if target in _navigator.get_adjacent_interactables():
		_begin_encounter(target)
		return

	if _navigator.move(direction):
		_sync_player_position()
		_grid_renderer.move_player_to(_navigator.get_player_position())
		_highlight_reachable()

func _sync_player_position() -> void:
	var pos: Vector2i = _navigator.get_player_position()
	_player_state()["position"] = {"x": pos.x, "y": pos.y}

func _highlight_reachable() -> void:
	_grid_renderer.clear_highlights()
	_grid_renderer.highlight_reachable_cells(_navigator.get_reachable_cells())

#----------------------------------------------------------------------------
# PRIVATE METHODS - combat
#----------------------------------------------------------------------------
func _begin_encounter(cell_pos: Vector2i) -> void:
	var cell: Dictionary = _cell_at(cell_pos)
	if cell.is_empty():
		return

	var clue: Dictionary = ClueDatabase.get_clue(String(cell.get("clue_id", "")))
	var player_state: Dictionary = _player_state()

	# A 6-letter chain banked a free solve; spend it instead of fighting.
	if int(player_state.get("skip_tokens", 0)) > 0:
		player_state["skip_tokens"] = int(player_state.skip_tokens) - 1
		_solve_and_advance(cell_pos, clue)
		_refresh_hud()
		_conclude_if_over()
		return

	_is_input_locked = true

	var enemy: Dictionary = EnemyDatabase.build_encounter(
		String(cell.get("enemy_id", "")), _dungeon_depth, _grid_size
	)
	if bool(enemy.get("is_boss", false)):
		GameState.current_run["boss_encountered"] = true

	_combat_scene = AssetRegistry.instantiate_scene(COMBAT_SCENE_PATH) as CombatScene
	if _combat_scene == null:
		# Never strand the player in a locked dungeon because a scene failed
		# to load (CLAUDE.md 5.3).
		push_error("DungeonScene: could not load %s" % COMBAT_SCENE_PATH)
		_is_input_locked = false
		return

	_combat_scene.combat_finished.connect(_on_combat_finished, CONNECT_ONE_SHOT)
	_ui_layer.add_child(_combat_scene)
	_combat_scene.start_encounter(clue, enemy, player_state, cell_pos)

func _on_combat_finished(result: Dictionary) -> void:
	if _combat_scene != null:
		_combat_scene.queue_free()
		_combat_scene = null

	GameState.current_run.combat_log.append({
		"timestamp": _iso_timestamp(),
		"enemy_id": String(result.get("enemy_id", "")),
		"clue_id": String(result.get("clue_id", "")),
		"answer": String(result.get("answer", "")),
		"damage_dealt": int(result.get("damage_dealt", 0)),
		"damage_taken": int(result.get("damage_taken", 0)),
		"attempts": int(result.get("attempts_used", 1)),
		"victory": bool(result.get("victory", false)),
	})

	if bool(result.get("victory", false)):
		var clue: Dictionary = ClueDatabase.get_clue(String(result.get("clue_id", "")))
		_tally()["enemies_defeated"] = int(_tally().get("enemies_defeated", 0)) + 1
		_solve_and_advance(result.get("cell", Vector2i.ZERO), clue)
		LexiconEffects.heal_for_solve(_player_state(), clue)

	# An encounter has ended either way, so per-encounter buffs tick down.
	ChainEffects.expire_buffs(_player_state())

	_grid_renderer.update_cell(result.get("cell", Vector2i.ZERO))
	_highlight_reachable()
	_refresh_hud()

	# Only unlock input if the run carries on; a cleared grid or a dead
	# player has already been settled and must stay locked.
	_is_input_locked = false
	_conclude_if_over(bool(result.get("player_defeated", false)))

## Solves the clue's word on the grid, pays any category Ink bonus, and
## resolves the chains the new letters complete.
func _solve_and_advance(cell_pos: Vector2i, clue: Dictionary) -> void:
	var answer := String(clue.get("answer", ""))
	if not _navigator.solve_cell(cell_pos, answer):
		return
	_tally()["words_solved"] = int(_tally().get("words_solved", 0)) + 1
	_add_run_ink(LexiconEffects.ink_bonus_for_word(_player_state(), clue))
	_grid_renderer.update_cell(cell_pos)
	_resolve_chains()

#----------------------------------------------------------------------------
# PRIVATE METHODS - vocabulary chains
#----------------------------------------------------------------------------

## Finds chains the newly solved letters completed and pays out their
## rewards. Loops because a grid-scoped reward (revealing letters, clearing a
## line) can itself spell new words.
func _resolve_chains() -> void:
	var player_state: Dictionary = _player_state()

	for pass_index in range(MAX_CHAIN_CASCADES):
		var fresh: Array = []
		for chain in ChainDetector.detect_chains(GameState.current_run.grid_state):
			if not _activated_chain_ids.has(String(chain.id)):
				fresh.append(chain)
		if fresh.is_empty():
			return

		for chain in fresh:
			_activated_chain_ids[String(chain.id)] = true
			EventBus.chain_detected.emit(chain)

			var effect: Dictionary = ChainEffects.effect_for_chain(chain)
			if effect.is_empty():
				continue

			var summary: Dictionary = ChainEffects.apply(effect, player_state)
			if not bool(summary.get("applied", false)) and String(summary.get("reason", "")) == "grid_scoped":
				_apply_grid_chain_effect(effect, chain)

			EventBus.chain_activated.emit(chain, effect)
			EventBus.chain_formed.emit(int(chain.length), float(effect.get("magnitude", 0.0)))

## Chain rewards that act on the dungeon rather than the player.
func _apply_grid_chain_effect(effect: Dictionary, chain: Dictionary) -> void:
	match String(effect.get("effect", "")):
		"reveal_letter":
			var revealed: Vector2i = _navigator.reveal_random_unsolved_cell()
			if revealed.x >= 0:
				_grid_renderer.update_cell(revealed)

		"skip_encounter":
			var player_state: Dictionary = _player_state()
			player_state["skip_tokens"] = int(player_state.get("skip_tokens", 0)) + 1

		"clear_line":
			# Clear the row or column the chain itself lies along.
			var cells: Array = chain.get("cells", [])
			if cells.is_empty():
				return
			var first: Vector2i = cells[0]
			var direction := String(chain.get("direction", "horizontal"))
			var line_index: int = first.y if direction == "horizontal" else first.x
			if _navigator.clear_unsolved_in_line(line_index, direction) > 0:
				_grid_renderer.update_cell(first)

#----------------------------------------------------------------------------
# PRIVATE METHODS - run end
#----------------------------------------------------------------------------
## The grid reports its own completion from deep inside solve_cell, before
## the last word's chains and rewards have resolved. So this only records the
## fact; _conclude_if_over settles the run once everything has been paid out.
func _on_grid_completed(score: int, time_seconds: float) -> void:
	GameState.current_run["final_score"] = score
	GameState.current_run["duration_seconds"] = time_seconds
	_grid_cleared = true

## Ends the run if the player died or the grid is cleared. Returns true if it
## did, so callers know input must stay locked.
func _conclude_if_over(player_defeated: bool = false) -> bool:
	if player_defeated:
		_end_run(false)
		return true
	if _grid_cleared:
		_end_run(true)
		return true
	return false

func _end_run(completed: bool) -> void:
	if String(GameState.current_run.get("run_status", "")) != "in_progress":
		return
	GameState.current_run["run_status"] = "completed" if completed else "failed"
	_is_input_locked = true

	var score: int = int(GameState.current_run.get("final_score", 0))
	var summary: Dictionary = RunSettlement.settle(
		GameState.player_profile, GameState.get_lexicon(), GameState.statistics,
		GameState.current_run, completed
	)
	GameState.current_run["settlement"] = summary
	# Persist immediately: the Ink just banked is the point of the run.
	SaveManager.save_game()

	EventBus.run_ended.emit(
		String(GameState.current_run.run_id),
		{"completed": completed, "score": score, "summary": summary}
	)
	_show_summary(summary)

func _show_summary(summary: Dictionary) -> void:
	_summary_panel = RunSummaryPanel.new()
	_ui_layer.add_child(_summary_panel)
	_summary_panel.show_summary(summary, GameState.current_run)
	_summary_panel.return_to_lexicon_pressed.connect(_on_return_to_lexicon)
	_summary_panel.delve_again_pressed.connect(_on_delve_again)

func _on_return_to_lexicon() -> void:
	get_tree().change_scene_to_file(LEXICON_SCENE_PATH)

func _on_delve_again() -> void:
	GameState.run_options = {"grid_size": _grid_size}
	get_tree().reload_current_scene()

#----------------------------------------------------------------------------
# PRIVATE METHODS - helpers
#----------------------------------------------------------------------------
func _player_state() -> Dictionary:
	return GameState.current_run.get("player_state", {})

func _tally() -> Dictionary:
	return GameState.current_run.get("tally", {})

## Credits Ink to the run's tally. It is only banked to the profile when the
## run is settled, so dying with it in hand still costs something.
func _add_run_ink(amount: int) -> void:
	if amount <= 0 or not GameState.has_active_run():
		return
	var player_state: Dictionary = _player_state()
	player_state["total_ink_drops_this_run"] = int(player_state.get("total_ink_drops_this_run", 0)) + amount

func _on_letter_solved(_pos: Vector2i, _letter: String, ink_drops: int) -> void:
	if not GameState.has_active_run():
		return
	_tally()["letters_solved"] = int(_tally().get("letters_solved", 0)) + 1
	_add_run_ink(ink_drops)
	_refresh_hud()

func _on_chain_activated(chain: Dictionary, _effect: Dictionary) -> void:
	if not GameState.has_active_run():
		return
	var tally: Dictionary = _tally()
	var length := int(chain.get("length", 0))
	tally["chains_activated"] = int(tally.get("chains_activated", 0)) + 1
	tally["longest_chain"] = maxi(int(tally.get("longest_chain", 0)), length)
	var by_length: Dictionary = tally["chains_by_length"]
	by_length[str(length)] = int(by_length.get(str(length), 0)) + 1
	_add_run_ink(InkDropManager.ink_for_chain(_player_state().get("loadout", {})))

## The grid size the Lexicon asked for, if the player's level allows it.
## Consumed once: the option is cleared so a later quick-start is unaffected.
func _pick_grid_size(default_size: int) -> int:
	var wanted := int(GameState.run_options.get("grid_size", default_size))
	GameState.run_options = {}
	if PlayerLevel.available_grid_sizes(int(GameState.player_profile.get("player_level", 1))).has(wanted):
		return wanted
	return default_size

## One-line status under the title: HP, Ink collected this run, level.
func _refresh_hud() -> void:
	var label := get_node_or_null("UI/MarginContainer/VBoxContainer/SubtitleLabel") as Label
	if label == null or not GameState.has_active_run():
		return
	var player_state: Dictionary = _player_state()
	label.text = "HP %d/%d   |   Ink this run: %d   |   Level %d" % [
		int(player_state.get("current_hp", 0)),
		int(player_state.get("max_hp", 0)),
		int(player_state.get("total_ink_drops_this_run", 0)),
		int(GameState.player_profile.get("player_level", 1)),
	]

func _cell_at(pos: Vector2i) -> Dictionary:
	for cell in GameState.current_run.grid_state.get("cells", []):
		if int(cell.get("x", -1)) == pos.x and int(cell.get("y", -1)) == pos.y:
			return cell
	return {}

func _generate_run_id() -> String:
	const HEX := "0123456789abcdef"
	var id := ""
	for i in range(16):
		id += HEX[randi() % HEX.length()]
	return id

func _iso_timestamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
