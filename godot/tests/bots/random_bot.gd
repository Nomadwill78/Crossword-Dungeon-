#============================================================================
# random_bot.gd
# Automated playtest bot that randomly navigates grids to find crashes and soft-locks.
# Run with: godot --headless --script tests/bots/random_bot.gd
#============================================================================

class_name RandomBot
extends SceneTree

const NUM_SIMULATIONS: int = 100
const MAX_MOVES_PER_RUN: int = 200

var _runs_completed: int = 0
var _runs_died: int = 0
var _soft_locks: int = 0
var _crashes: int = 0
var _avg_moves: float = 0.0

func _init():
	print("=== Random Bot Simulation ===")
	print("Running ", NUM_SIMULATIONS, " simulations with max ", MAX_MOVES_PER_RUN, " moves each\n")

	for i in range(NUM_SIMULATIONS):
		_run_simulation(i + 1)

	_avg_moves = _avg_moves / NUM_SIMULATIONS

	print("\n=== Simulation Results ===")
	print("Runs completed (reached exit): ", _runs_completed)
	print("Runs died (HP <= 0):           ", _runs_died)
	print("Soft-locks (max moves reached): ", _soft_locks)
	print("Crashes:                       ", _crashes)
	print("Average moves per run:         ", snappedf(_avg_moves, 0.1))
	print("Completion rate:               ", snappedf(float(_runs_completed) / NUM_SIMULATIONS * 100, 1), "%")

	quit(0)

func _run_simulation(index: int):
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)
	var navigator = GridNavigator.new()
	navigator.initialize(grid)

	var moves = 0
	var hp = 100
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while moves < MAX_MOVES_PER_RUN:
		moves += 1

		# Check if at exit
		if navigator.is_at_exit():
			_runs_completed += 1
			_avg_moves += moves
			return

		# Get adjacent interactables (combat)
		var adjacent = navigator.get_adjacent_interactables()
		if not adjacent.is_empty():
			# Auto-solve combat (Milestone 1)
			var target = adjacent.pick_random()
			var cell = _get_cell(grid, target)
			var clue = _get_clue(cell.get("clue_id", ""))
			var answer = clue.get("answer", "A") if not clue.is_empty() else "A"
			navigator.solve_cell(target, answer)
			continue

		# Random movement
		directions.shuffle()
		var moved = false
		for dir in directions:
			if navigator.can_move(dir):
				navigator.move(dir)
				moved = true
				break

		if not moved:
			# Stuck — soft lock
			_soft_locks += 1
			return

		# Simulate random damage from failed encounters (10% chance)
		if randf() < 0.1:
			hp -= 10
			if hp <= 0:
				_runs_died += 1
				return

	# Max moves reached
	_soft_locks += 1

func _get_cell(grid: Dictionary, pos: Vector2i) -> Dictionary:
	for cell in grid.cells:
		if cell.x == pos.x and cell.y == pos.y:
			return cell
	return {}

func _get_clue(clue_id: String) -> Dictionary:
	var clues = ConfigLoader.load_json(Constants.CLUES_PATH)
	for clue in clues.get("clues", []):
		if clue.id == clue_id:
			return clue
	return {}
