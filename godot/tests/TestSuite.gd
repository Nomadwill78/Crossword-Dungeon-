#============================================================================
# TestSuite.gd
# Minimal assertion harness shared by the Milestone 2 unit suites.
#
# The project does not vendor the Gut framework that CLAUDE.md 6.3 assumes,
# and pulling in an addon just to count assertions would be a heavier
# dependency than the tests themselves. A suite subclasses this, implements
# run(), and calls the assert helpers; TestRunner aggregates the totals.
# Dependencies: none
# Events: none
#============================================================================

class_name TestSuite
extends RefCounted

var suite_name: String = "UnnamedSuite"
var passed: int = 0
var failed: int = 0
var failures: Array[String] = []

## Override in each suite for synchronous tests. [param host] is a Node
## already inside the scene tree, for the rare test that needs to parent a
## Node (e.g. a Timer).
func run(_host: Node) -> void:
	pass

## Override for tests that must let real time pass (the countdown timer).
## Always a coroutine - the trivial frame await keeps TestRunner able to
## `await` this uniformly whether or not a suite overrides it.
func run_async(host: Node) -> void:
	await host.get_tree().process_frame

func assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		_fail(message)

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		passed += 1
	else:
		_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func assert_ne(actual, unexpected, message: String) -> void:
	if actual != unexpected:
		passed += 1
	else:
		_fail("%s (expected anything but %s)" % [message, str(unexpected)])

## Float comparison helper - CLAUDE.md 13.1 warns against `==` on floats.
func assert_approx(actual: float, expected: float, message: String, epsilon: float = 0.0001) -> void:
	if absf(actual - expected) <= epsilon:
		passed += 1
	else:
		_fail("%s (expected ~%s, got %s)" % [message, str(expected), str(actual)])

func assert_gt(actual: float, floor_value: float, message: String) -> void:
	if actual > floor_value:
		passed += 1
	else:
		_fail("%s (expected > %s, got %s)" % [message, str(floor_value), str(actual)])

func assert_lt(actual: float, ceiling: float, message: String) -> void:
	if actual < ceiling:
		passed += 1
	else:
		_fail("%s (expected < %s, got %s)" % [message, str(ceiling), str(actual)])

func assert_between(actual: float, low: float, high: float, message: String) -> void:
	if actual >= low and actual <= high:
		passed += 1
	else:
		_fail("%s (expected %s..%s, got %s)" % [message, str(low), str(high), str(actual)])

func _fail(message: String) -> void:
	failed += 1
	failures.append(message)
	push_error("  FAIL [%s] %s" % [suite_name, message])
