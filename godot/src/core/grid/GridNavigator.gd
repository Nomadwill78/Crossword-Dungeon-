## Player movement, reachability, and word-solving over a generated
## grid_state Dictionary (see GridGenerator). Cell Dictionaries are shared by
## reference with grid_state.cells, so mutations here (e.g. marking a cell
## solved) are immediately visible to anything else holding the same
## grid_state — including GameState.current_run.grid_state.
class_name GridNavigator
extends RefCounted

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _grid_state: Dictionary
var _size: int
var _player_pos: Vector2i
var _cell_lookup: Dictionary  # Vector2i -> cell Dictionary (shared reference)
var _start_time_msec: int

func initialize(grid_state: Dictionary) -> void:
	_grid_state = grid_state
	_size = int(grid_state.size)
	_cell_lookup = {}
	for cell in grid_state.cells:
		_cell_lookup[Vector2i(int(cell.x), int(cell.y))] = cell
	var entrance: Dictionary = grid_state.get("entrance", {"x": 0, "y": 0})
	_player_pos = Vector2i(int(entrance.x), int(entrance.y))
	_start_time_msec = Time.get_ticks_msec()

func get_player_position() -> Vector2i:
	return _player_pos

func _cell_at(pos: Vector2i) -> Dictionary:
	return _cell_lookup.get(pos, {})

func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _size and pos.y >= 0 and pos.y < _size

func _is_passable(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return false
	var cell := _cell_at(pos)
	if cell.is_empty():
		return false
	var type: String = cell.type
	if type == "black":
		return false
	if type == "letter":
		return bool(cell.solved)
	return true  # entrance / exit are always walkable

func can_move(direction: Vector2i) -> bool:
	return _is_passable(_player_pos + direction)

func move(direction: Vector2i) -> bool:
	var target := _player_pos + direction
	if not _is_passable(target):
		EventBus.player_blocked.emit(target)
		return false
	var from := _player_pos
	_player_pos = target
	EventBus.player_moved.emit(from, target)
	return true

## Unsolved letter cells adjacent to the player — these are combat triggers,
## not plain moves; DungeonScene checks this before falling back to move().
func get_adjacent_interactables() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		var pos := _player_pos + d
		if not _is_in_bounds(pos):
			continue
		var cell := _cell_at(pos)
		if cell.is_empty():
			continue
		if cell.type == "letter" and not bool(cell.solved):
			out.append(pos)
	return out

## Cells worth highlighting on the map: walkable cells reachable via already
## solved corridors, plus the unsolved frontier you can fight into next.
func get_reachable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var visited := {_player_pos: true}
	var queue: Array[Vector2i] = [_player_pos]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			var nxt := cur + d
			if visited.has(nxt) or not _is_in_bounds(nxt):
				continue
			visited[nxt] = true
			if _is_passable(nxt):
				out.append(nxt)
				queue.append(nxt)
			else:
				var cell := _cell_at(nxt)
				if not cell.is_empty() and cell.type == "letter" and not bool(cell.solved):
					out.append(nxt)
	return out

func is_at_exit() -> bool:
	var cell := _cell_at(_player_pos)
	return not cell.is_empty() and cell.type == "exit"

func _slot_contains(slot: Dictionary, pos: Vector2i) -> bool:
	var length: int = int(slot.length)
	var sx: int = int(slot.start_x)
	var sy: int = int(slot.start_y)
	if slot.direction == "across":
		return pos.y == sy and pos.x >= sx and pos.x < sx + length
	return pos.x == sx and pos.y >= sy and pos.y < sy + length

func _slot_at_direction(pos: Vector2i, direction: String) -> Dictionary:
	var list: Array = _grid_state.get("words_horizontal", []) if direction == "across" else _grid_state.get("words_vertical", [])
	for slot in list:
		if _slot_contains(slot, pos):
			return slot
	return {}

## Attempt to solve the word occupying `cell_pos` with `answer`. On a match,
## every cell of that word (not just cell_pos) is revealed and marked solved.
func solve_cell(cell_pos: Vector2i, answer: String) -> bool:
	var cell := _cell_at(cell_pos)
	if cell.is_empty() or cell.type != "letter" or bool(cell.solved):
		return false

	var normalized := answer.strip_edges().to_upper()
	var slot := {}
	for direction in ["across", "down"]:
		var candidate := _slot_at_direction(cell_pos, direction)
		if not candidate.is_empty() and String(candidate.answer).to_upper() == normalized:
			slot = candidate
			break
	if slot.is_empty():
		return false

	var config: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var ink_per_letter: int = int(config.get("ink_economy", {}).get("ink_per_letter", 2))

	var length: int = int(slot.length)
	var sx: int = int(slot.start_x)
	var sy: int = int(slot.start_y)
	var dir: String = slot.direction
	for i in range(length):
		var cx: int = sx + i if dir == "across" else sx
		var cy: int = sy if dir == "across" else sy + i
		_mark_solved(Vector2i(cx, cy), ink_per_letter)

	EventBus.word_solved.emit(String(slot.id), String(slot.answer), ink_per_letter * length)
	_check_completion()
	return true

## Reveals one random unsolved letter cell, the reward for a 5-letter
## Vocabulary Chain (Design Doc 4.3).
## Returns the revealed cell, or (-1, -1) if nothing was left to reveal.
func reveal_random_unsolved_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for cell in _grid_state.cells:
		if cell.type == "letter" and not bool(cell.solved):
			candidates.append(Vector2i(int(cell.x), int(cell.y)))
	if candidates.is_empty():
		return Vector2i(-1, -1)

	var pos: Vector2i = candidates[randi() % candidates.size()]
	_mark_solved(pos, _ink_per_letter())
	_check_completion()
	return pos

## Clears every unsolved letter in one row or column - the 8+ letter chain
## "Ultimate" (Design Doc 4.3). Returns how many cells were cleared.
func clear_unsolved_in_line(line_index: int, direction: String) -> int:
	var ink := _ink_per_letter()
	var cleared := 0
	for i in range(_size):
		var pos := Vector2i(i, line_index) if direction == "horizontal" else Vector2i(line_index, i)
		var cell := _cell_at(pos)
		if cell.is_empty() or cell.type != "letter" or bool(cell.solved):
			continue
		_mark_solved(pos, ink)
		cleared += 1
	if cleared > 0:
		_check_completion()
	return cleared

## Number of letter cells still unsolved. Used to tell "grid finished" from
## "player walked to the exit early".
func unsolved_letter_count() -> int:
	var count := 0
	for cell in _grid_state.cells:
		if cell.type == "letter" and not bool(cell.solved):
			count += 1
	return count

func _mark_solved(pos: Vector2i, ink_per_letter: int) -> void:
	var cell := _cell_at(pos)
	if cell.is_empty() or cell.type != "letter" or bool(cell.solved):
		return
	cell.solved = true
	cell.enemy_id = ""
	EventBus.letter_solved.emit(pos, cell.letter, ink_per_letter)

func _check_completion() -> void:
	if _all_letters_solved():
		var elapsed := (Time.get_ticks_msec() - _start_time_msec) / 1000.0
		EventBus.grid_completed.emit(_score(), elapsed)

func _ink_per_letter() -> int:
	var config: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	return int(config.get("ink_economy", {}).get("ink_per_letter", 2))

func _all_letters_solved() -> bool:
	for cell in _grid_state.cells:
		if cell.type == "letter" and not bool(cell.solved):
			return false
	return true

func _score() -> int:
	var total := 0
	for cell in _grid_state.cells:
		if cell.type in ["letter", "entrance"] and bool(cell.solved):
			total += 10
	return total
