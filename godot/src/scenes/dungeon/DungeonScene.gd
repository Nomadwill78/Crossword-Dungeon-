#============================================================================
# DungeonScene.gd
# Main dungeon scene. Orchestrates grid generation, navigation, and rendering.
# Dependencies: GridGenerator, GridNavigator, GridRenderer, EventBus, GameState
#============================================================================

class_name DungeonScene
extends Node2D

@onready var _grid_renderer: GridRenderer = $GridRenderer
@onready var _ui_layer: CanvasLayer = $UI

var _navigator: GridNavigator = null
var _generator: GridGenerator = null
var _is_input_locked: bool = false

func _ready():
	EventBus.grid_generated.connect(_on_grid_generated)
	EventBus.player_moved.connect(_on_player_moved)
	EventBus.letter_solved.connect(_on_letter_solved)
	EventBus.grid_completed.connect(_on_grid_completed)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)

	_start_new_run()

func _start_new_run():
	_generator = GridGenerator.new()
	var grid_state = _generator.generate_grid(5, 1, 1)

	_navigator = GridNavigator.new()
	_navigator.initialize(grid_state)

	GameState.current_run = {
		"run_id": _generate_run_id(),
		"started_at": _get_iso_timestamp(),
		"difficulty": "standard",
		"grid_size": 5,
		"dungeon_depth": 1,
		"player_state": {
			"current_hp": 100,
			"max_hp": 100,
			"position": {"x": _navigator.get_player_position().x, "y": _navigator.get_player_position().y},
			"active_chains": [],
			"inventory": {"health_potions": 0, "dictionary_fragments": 0, "special_items": []},
			"combo_streak": 0,
			"total_ink_drops_this_run": 0
		},
		"grid_state": grid_state,
		"combat_log": [],
		"boss_encountered": false,
		"boss_defeated": false,
		"run_status": "in_progress"
	}

	_grid_renderer.initialize(grid_state)
	_highlight_reachable()

	EventBus.run_started.emit(GameState.current_run.run_id, "standard", 5)

func _input(event: InputEvent):
	if _is_input_locked or _navigator == null:
		return

	var direction = Vector2i.ZERO

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

func _attempt_move(direction: Vector2i):
	# Check if adjacent cell is an unsolved letter (combat trigger)
	var target = _navigator.get_player_position() + direction
	var adjacent = _navigator.get_adjacent_interactables()

	if target in adjacent:
		_trigger_combat(target)
		return

	# Otherwise try normal movement
	if _navigator.move(direction):
		_update_player_position_in_state()
		_grid_renderer.move_player_to(_navigator.get_player_position())
		_highlight_reachable()

func _trigger_combat(cell_pos: Vector2i):
	_is_input_locked = true
	var cell = _get_cell_at(cell_pos)
	var enemy_id = cell.get("enemy_id", "")
	var clue_id = cell.get("clue_id", "")

	# For Milestone 1: auto-solve combat for demonstration
	# In full game, this would open the combat UI
	print("Combat triggered! Enemy: ", enemy_id, " Clue: ", clue_id)

	# Simulate solving the clue
	var clue = _get_clue_data(clue_id)
	var answer = clue.get("answer", "A") if not clue.is_empty() else "A"

	_navigator.solve_cell(cell_pos, answer)
	_update_player_position_in_state()
	_grid_renderer.update_cell(cell_pos)

	# Check for chains
	_check_chains()

	_is_input_locked = false

func _check_chains():
	# Placeholder: full chain detection in Milestone 2
	pass

func _highlight_reachable():
	_grid_renderer.clear_highlights()
	var reachable = _navigator.get_reachable_cells()
	_grid_renderer.highlight_reachable_cells(reachable)

func _update_player_position_in_state():
	if GameState.current_run.has("player_state"):
		var pos = _navigator.get_player_position()
		GameState.current_run.player_state.position = {"x": pos.x, "y": pos.y}

func _get_cell_at(pos: Vector2i) -> Dictionary:
	var cells = GameState.current_run.grid_state.get("cells", [])
	for cell in cells:
		if cell.get("x", -1) == pos.x and cell.get("y", -1) == pos.y:
			return cell
	return {}

func _get_clue_data(clue_id: String) -> Dictionary:
	var clues_data = ConfigLoader.load_json(Constants.CLUES_PATH)
	for clue in clues_data.get("clues", []):
		if clue.get("id", "") == clue_id:
			return clue
	return {}

func _on_grid_generated(grid_state: Dictionary):
	print("Grid generated: ", grid_state.size, "x", grid_state.size)

func _on_player_moved(from_pos: Vector2i, to_pos: Vector2i):
	print("Player moved from ", from_pos, " to ", to_pos)

func _on_letter_solved(pos: Vector2i, letter: String, ink_drops: int):
	print("Letter solved at ", pos, ": ", letter, " (+", ink_drops, " ink)")

func _on_grid_completed(score: int, time_seconds: float):
	print("Grid completed! Score: ", score)
	EventBus.run_ended.emit(GameState.current_run.run_id, {"completed": true, "score": score})

func _on_combat_started(enemy_id: String, clue_id: String):
	print("Combat started vs ", enemy_id)

func _on_combat_ended(result: Dictionary):
	print("Combat ended: ", result)

func _generate_run_id() -> String:
	var chars = "0123456789abcdef"
	var id = ""
	for i in range(16):
		id += chars[randi() % chars.length()]
	return id

func _get_iso_timestamp() -> String:
	var dt = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
