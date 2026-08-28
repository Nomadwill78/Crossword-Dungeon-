#============================================================================
# test_grid_generator.gd
# Unit tests for GridGenerator. Validates grid structure, solvability, and constraints.
# Run with: godot --headless --script tests/unit/test_grid_generator.gd
#============================================================================

class_name TestGridGenerator
extends SceneTree

var _tests_passed: int = 0
var _tests_failed: int = 0

func _init():
	print("=== GridGenerator Tests ===\n")

	test_generate_5x5_grid()
	test_generate_7x7_grid()
	test_grid_has_entrance_and_exit()
	test_grid_is_solvable()
	test_all_word_slots_have_length_at_least_3()
	test_no_orphaned_letter_cells()
	test_fallback_grid_on_failure()

	print("\n=== Results ===")
	print("Passed: ", _tests_passed)
	print("Failed: ", _tests_failed)
	print("Total:  ", _tests_passed + _tests_failed)

	if _tests_failed > 0:
		quit(1)
	else:
		quit(0)

func _assert(condition: bool, message: String):
	if condition:
		_tests_passed += 1
		print("  ✓ ", message)
	else:
		_tests_failed += 1
		push_error("  ✗ " + message)

func test_generate_5x5_grid():
	print("Test: generate_5x5_grid")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)
	_assert(grid.size == 5, "Grid size is 5")
	_assert(grid.cells.size() == 25, "Has 25 cells")

func test_generate_7x7_grid():
	print("\nTest: generate_7x7_grid")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(7, 1, 1)
	_assert(grid.size == 7, "Grid size is 7")
	_assert(grid.cells.size() == 49, "Has 49 cells")

func test_grid_has_entrance_and_exit():
	print("\nTest: grid_has_entrance_and_exit")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)

	var has_entrance = false
	var has_exit = false
	for cell in grid.cells:
		if cell.type == "entrance":
			has_entrance = true
		if cell.type == "exit":
			has_exit = true

	_assert(has_entrance, "Grid has entrance")
	_assert(has_exit, "Grid has exit")

func test_grid_is_solvable():
	print("\nTest: grid_is_solvable")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)

	var start = Vector2i(grid.entrance.x, grid.entrance.y)
	var end = Vector2i(grid.exit.x, grid.exit.y)

	var queue = [start]
	var visited = {str(start): true}
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found = false

	while not queue.is_empty():
		var current = queue.pop_front()
		if current == end:
			found = true
			break

		for dir in directions:
			var next = current + dir
			var key = str(next)
			if not visited.has(key):
				for cell in grid.cells:
					if cell.x == next.x and cell.y == next.y:
						if cell.type != "black":
							visited[key] = true
							queue.append(next)
						break

	_assert(found, "Path exists from entrance to exit")

func test_all_word_slots_have_length_at_least_3():
	print("\nTest: word_slots_minimum_length")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)

	for word in grid.words_horizontal:
		_assert(word.length >= 3, "Horizontal word length >= 3 (got " + str(word.length) + ")")
	for word in grid.words_vertical:
		_assert(word.length >= 3, "Vertical word length >= 3 (got " + str(word.length) + ")")

func test_no_orphaned_letter_cells():
	print("\nTest: no_orphaned_letter_cells")
	var gen = GridGenerator.new()
	var grid = gen.generate_grid(5, 1, 1)

	for cell in grid.cells:
		if cell.type == "letter" and not cell.solved:
			# Must have a clue_id and enemy_id
			_assert(not cell.enemy_id.is_empty(), "Unsolved letter has enemy: (" + str(cell.x) + "," + str(cell.y) + ")")
			_assert(not cell.clue_id.is_empty(), "Unsolved letter has clue: (" + str(cell.x) + "," + str(cell.y) + ")")

func test_fallback_grid_on_failure():
	print("\nTest: fallback_grid_on_failure")
	var gen = GridGenerator.new()
	# Request impossible size to force fallback
	var grid = gen.generate_grid(3, 1, 1)
	_assert(grid.size == 3, "Fallback grid generated for invalid size")
	_assert(grid.cells.size() == 9, "Fallback has correct cell count")
