#============================================================================
# DungeonScene.gd
# Main dungeon scene. Owns the grid, the player's position, and the handoff
# into and out of combat.
# Dependencies: GridGenerator, GridNavigator, GridRenderer, CombatScene,
#               ChainDetector, ChainEffects, ClueDatabase, EnemyDatabase
# Events: listens on EventBus; emits run_started / run_ended
#============================================================================

class_name DungeonScene
extends Node2D

#----------------------------------------------------------------------------
# CONSTANTS
#----------------------------------------------------------------------------
const COMBAT_SCENE_PATH := "res://src/scenes/combat/CombatScene.tscn"

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

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready() -> void:
	EventBus.grid_completed.connect(_on_grid_completed)
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
	_grid_size = int(config.get("grid", {}).get("default_size", 5))

	_generator = GridGenerator.new()
	var grid_state: Dictionary = _generator.generate_grid(_grid_size, _dungeon_depth, 1)

	_navigator = GridNavigator.new()
	_navigator.initialize(grid_state)
	_activated_chain_ids.clear()

	var start_pos: Vector2i = _navigator.get_player_position()
	GameState.current_run = {
		"run_id": _generate_run_id(),
		"started_at": _iso_timestamp(),
		"difficulty": String(GameState.settings.get("gameplay", {}).get("difficulty", "standard")),
		"grid_size": _grid_size,
		"dungeon_depth": _dungeon_depth,
		"player_state": {
			"current_hp": int(player_cfg.get("starting_hp", 100)),
			"max_hp": int(player_cfg.get("starting_max_hp", 100)),
			"position": {"x": start_pos.x, "y": start_pos.y},
			"active_chains": [],
			"inventory": {"health_potions": 0, "dictionary_fragments": 0, "special_items": []},
			"combo_streak": 0,
			"skip_tokens": 0,
			"total_ink_drops_this_run": 0,
		},
		"grid_state": grid_state,
		"combat_log": [],
		"boss_encountered": false,
		"boss_defeated": false,
		"run_status": "in_progress",
	}

	_grid_renderer.initialize(grid_state)
	_highlight_reachable()

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
		_solve_and_advance(cell_pos, String(clue.get("answer", "")))
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
		_solve_and_advance(result.get("cell", Vector2i.ZERO), String(result.get("answer", "")))

	# An encounter has ended either way, so per-encounter buffs tick down.
	ChainEffects.expire_buffs(_player_state())

	_is_input_locked = false
	_grid_renderer.update_cell(result.get("cell", Vector2i.ZERO))
	_highlight_reachable()

	if bool(result.get("player_defeated", false)):
		_end_run(false)

func _solve_and_advance(cell_pos: Vector2i, answer: String) -> void:
	if not _navigator.solve_cell(cell_pos, answer):
		return
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
func _on_grid_completed(score: int, time_seconds: float) -> void:
	GameState.current_run["final_score"] = score
	GameState.current_run["duration_seconds"] = time_seconds
	_end_run(true)

func _end_run(completed: bool) -> void:
	if String(GameState.current_run.get("run_status", "")) != "in_progress":
		return
	GameState.current_run["run_status"] = "completed" if completed else "failed"
	_is_input_locked = true

	var score: int = int(GameState.current_run.get("final_score", 0))
	GameState.record_run_end(completed, score)
	EventBus.run_ended.emit(
		String(GameState.current_run.run_id),
		{"completed": completed, "score": score}
	)

#----------------------------------------------------------------------------
# PRIVATE METHODS - helpers
#----------------------------------------------------------------------------
func _player_state() -> Dictionary:
	return GameState.current_run.get("player_state", {})

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
