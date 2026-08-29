#============================================================================
# test_performance.gd
# Performance budgets from Technical Design Doc section 8. Numbers are
# measured on this machine, so the assertions use the doc's "Max" column
# rather than its "Target" column to stay meaningful on slower CI hardware.
#============================================================================

class_name TestPerformance
extends TestSuite

func _init() -> void:
	suite_name = "Performance"

func run(_host: Node) -> void:
	test_grid_generation_5x5()
	test_grid_generation_7x7()
	test_chain_detection_on_full_9x9()
	test_dictionary_load_time()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------

## Budget: 5x5 generation under 100ms (TDD section 8).
func test_grid_generation_5x5() -> void:
	var average := _time_average(20, func():
		var generator := GridGenerator.new()
		generator.generate_grid(5, 1, 1)
	)
	print("      5x5 grid generation: %.2f ms avg" % average)
	assert_lt(average, 100.0, "5x5 grid generation averages under 100ms")

## Budget: 7x7 generation under 500ms (TDD section 8).
func test_grid_generation_7x7() -> void:
	var average := _time_average(10, func():
		var generator := GridGenerator.new()
		generator.generate_grid(7, 1, 1)
	)
	print("      7x7 grid generation: %.2f ms avg" % average)
	assert_lt(average, 500.0, "7x7 grid generation averages under 500ms")

## Budget: chain detection under 5ms on a fully solved 9x9 (TDD section 8).
func test_chain_detection_on_full_9x9() -> void:
	var grid := _solved_grid(9)
	# Warm the dictionary so we measure detection, not the one-off JSON load.
	ChainDetector.detect_chains(grid)

	var average := _time_average(200, func(): ChainDetector.detect_chains(grid))
	print("      chain detection (9x9 full): %.3f ms avg" % average)
	assert_lt(average, 5.0, "Chain detection averages under 5ms on a full 9x9")

## Budget: dictionary load under 500ms (TDD section 3.3).
func test_dictionary_load_time() -> void:
	ChainDetector.reset_cache()
	ConfigLoader.clear_cache(Constants.DICTIONARY_PATH)

	var start := Time.get_ticks_usec()
	ChainDetector.is_valid_word("DRAGON")
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0

	print("      dictionary cold load: %.2f ms (%d words)" % [elapsed, ChainDetector.word_count()])
	assert_lt(elapsed, 500.0, "Dictionary loads in under 500ms")
	assert_gt(ChainDetector.word_count(), 10000, "Dictionary actually loaded")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _time_average(iterations: int, body: Callable) -> float:
	var start := Time.get_ticks_usec()
	for i in range(iterations):
		body.call()
	return float(Time.get_ticks_usec() - start) / float(iterations) / 1000.0

## Worst case for chain detection: every cell solved, so every row and column
## is one long run the detector has to scan and look up.
func _solved_grid(size: int) -> Dictionary:
	var letters := "ABCDEFGHI"
	var cells: Array = []
	for y in range(size):
		for x in range(size):
			cells.append({
				"x": x, "y": y, "type": "letter",
				"letter": letters[(x + y) % letters.length()],
				"solved": true, "enemy_id": "", "clue_id": "",
				"bonus": null, "bonus_claimed": false,
			})
	return {
		"size": size,
		"cells": cells,
		"words_horizontal": [],
		"words_vertical": [],
		"entrance": {"x": 0, "y": 0},
		"exit": {"x": size - 1, "y": size - 1},
	}
