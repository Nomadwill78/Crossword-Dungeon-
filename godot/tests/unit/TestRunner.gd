## Runs every test suite and exits with a non-zero code if anything failed.
##
## Godot's `--script` / `--main-loop` invocation modes replace the main loop
## *before* project autoloads become resolvable as bare identifiers at compile
## time (the autoload nodes do exist under /root at runtime even then - it is
## purely a compile-time lookup gap). A normal scene run, which this is, boots
## autoloads first, so this wrapper is how the suites actually get run.
##
## Run with: godot --headless --path . tests/unit/TestRunner.tscn
extends Node

func _ready() -> void:
	var total_passed := 0
	var total_failed := 0
	var failed_suites: Array[String] = []

	# The Milestone 1 grid suite predates TestSuite and drives itself from
	# _init(). Its quit() calls land on its own throwaway SceneTree object,
	# not this one, so they are inert here.
	print("=== GridGenerator (Milestone 1 suite) ===")
	var grid_suite := TestGridGenerator.new()
	total_passed += grid_suite._tests_passed
	total_failed += grid_suite._tests_failed
	if grid_suite._tests_failed > 0:
		failed_suites.append("GridGenerator")

	for suite in _suites():
		print("\n=== %s ===" % suite.suite_name)
		suite.run(self)
		await suite.run_async(self)

		total_passed += suite.passed
		total_failed += suite.failed
		if suite.failed > 0:
			failed_suites.append(suite.suite_name)
			for failure in suite.failures:
				print("  FAILED: %s" % failure)
		print("  %d passed, %d failed" % [suite.passed, suite.failed])

	print("\n=== Totals ===")
	print("Passed: %d" % total_passed)
	print("Failed: %d" % total_failed)
	print("Total:  %d" % (total_passed + total_failed))
	if failed_suites.is_empty():
		print("Result: ALL SUITES PASSED")
	else:
		print("Result: FAILING SUITES -> %s" % ", ".join(failed_suites))

	get_tree().quit(1 if total_failed > 0 else 0)

func _suites() -> Array[TestSuite]:
	return [
		TestDatabases.new(),
		TestClueResolver.new(),
		TestCombatEngine.new(),
		TestChainDetector.new(),
		TestCombatStateMachine.new(),
		TestTimerSystem.new(),
		TestLexiconData.new(),
		TestProgression.new(),
		TestVocabularyTree.new(),
		TestTomeManager.new(),
		TestAchievements.new(),
		TestLexiconEffects.new(),
		TestRunSettlement.new(),
		TestSaveManager.new(),
		TestLexiconScenes.new(),
		TestPerformance.new(),
	]
