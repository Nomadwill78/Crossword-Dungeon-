#============================================================================
# test_timer_system.gd
# Unit tests for the combat countdown. The expiry/warning tests let real
# (very short) time pass, so they live in run_async.
#============================================================================

class_name TestTimerSystem
extends TestSuite

var _warnings_seen: Array[float] = []
var _expired_count: int = 0

func _init() -> void:
	suite_name = "TimerSystem"

func run(_host: Node) -> void:
	test_base_seconds_by_difficulty()
	test_modifiers_apply_in_order()
	test_accessibility_extended_timer()

func run_async(host: Node) -> void:
	await host.get_tree().process_frame
	await test_start_and_stop(host)
	await test_pause_and_resume(host)
	await test_expiry_and_warnings(host)
	await test_answer_keeps_its_time_bonus(host)

#----------------------------------------------------------------------------
# SYNCHRONOUS TESTS
#----------------------------------------------------------------------------
func test_base_seconds_by_difficulty() -> void:
	# Technical Design Doc 3.2's table.
	assert_approx(TimerSystem.base_seconds_for_difficulty(1), 45.0, "Difficulty 1 = 45s")
	assert_approx(TimerSystem.base_seconds_for_difficulty(3), 30.0, "Difficulty 3 = 30s")
	assert_approx(TimerSystem.base_seconds_for_difficulty(5), 20.0, "Difficulty 5 = 20s")
	assert_approx(TimerSystem.base_seconds_for_difficulty(99), 30.0, "Unknown difficulty falls back to 30s")

func test_modifiers_apply_in_order() -> void:
	# Bonus seconds are added first, then the multiplier scales the total.
	assert_approx(
		TimerSystem.calculate_max_time(3, {"timer_bonus": 5.0}), 35.0, "+5s bonus on a 30s clue"
	)
	assert_approx(
		TimerSystem.calculate_max_time(3, {"timer_multiplier": 2.0}), 60.0, "2x multiplier on a 30s clue"
	)
	assert_approx(
		TimerSystem.calculate_max_time(3, {"timer_bonus": 5.0, "timer_multiplier": 2.0}),
		70.0,
		"Bonus applies before the multiplier"
	)

func test_accessibility_extended_timer() -> void:
	var accessibility: Dictionary = GameState.settings.get("accessibility", {})
	var previous := bool(accessibility.get("extended_timer", false))

	accessibility["extended_timer"] = true
	assert_approx(TimerSystem.calculate_max_time(3, {}), 45.0, "Extended timer gives 30s * 1.5")

	accessibility["extended_timer"] = false
	assert_approx(TimerSystem.calculate_max_time(3, {}), 30.0, "Normal timer is unscaled")

	accessibility["extended_timer"] = previous

#----------------------------------------------------------------------------
# ASYNC TESTS
#----------------------------------------------------------------------------
func test_start_and_stop(host: Node) -> void:
	var timer := _make_timer(host)
	await host.get_tree().process_frame

	assert_false(timer.is_running, "Fresh timer is idle")
	assert_approx(timer.get_time_remaining(), 0.0, "Idle timer reports no time left")

	timer.start(3)
	assert_true(timer.is_running, "Timer runs after start()")
	assert_approx(timer.max_time, 30.0, "Difficulty 3 budgets 30s")
	assert_between(timer.get_time_ratio(), 0.9, 1.0, "Ratio starts near 1.0")

	timer.stop()
	assert_false(timer.is_running, "stop() halts the timer")
	assert_approx(timer.get_time_remaining(), 0.0, "Stopped timer reports no time left")

	timer.queue_free()

func test_pause_and_resume(host: Node) -> void:
	var timer := _make_timer(host)
	await host.get_tree().process_frame

	timer.start(3)
	timer.pause()
	assert_true(timer.is_paused, "pause() sets the flag")
	var frozen := timer.get_time_remaining()

	# Let a few frames go by; a paused countdown must not move.
	for i in range(5):
		await host.get_tree().process_frame
	assert_approx(timer.get_time_remaining(), frozen, "Paused timer does not tick", 0.001)

	timer.resume()
	assert_false(timer.is_paused, "resume() clears the flag")

	timer.stop()
	timer.queue_free()

## Drives a real expiry by scaling a 45s budget down to ~45ms, which also
## exercises scale_remaining (the Acronym enemy's Abbreviate ability).
func test_expiry_and_warnings(host: Node) -> void:
	var timer := _make_timer(host)
	await host.get_tree().process_frame

	_warnings_seen.clear()
	_expired_count = 0
	timer.timer_expired.connect(func(): _expired_count += 1)
	timer.timer_warning.connect(func(threshold: float): _warnings_seen.append(threshold))

	timer.start(1)
	assert_approx(timer.max_time, 45.0, "Difficulty 1 budgets 45s")

	# Compress 45s to ~0.45s. Not shorter: Timer nodes only fire on frame
	# boundaries, so at ~45ms the two later warnings and the expiry all land
	# on one 60fps frame, and expiry clears the pending warnings first - the
	# test flakes rather than the timer misbehaving. At 0.45s every threshold
	# gets its own frame, which is what real 20-45s clocks look like anyway.
	timer.scale_remaining(0.01)
	assert_lt(timer.get_time_remaining(), 1.0, "scale_remaining shortened the clock")

	# Wait well past the ~450ms that is left.
	await host.get_tree().create_timer(0.9).timeout

	assert_eq(_expired_count, 1, "Expiry fires exactly once")
	assert_false(timer.is_running, "Timer is no longer running after expiry")
	assert_eq(_warnings_seen.size(), 3, "All three warning thresholds fired")

	# Expiry must not re-fire after the fact.
	await host.get_tree().create_timer(0.1).timeout
	assert_eq(_expired_count, 1, "Expiry does not repeat")

	timer.queue_free()

## Regression test. CombatStateMachine used to sample the clock AFTER leaving
## AWAIT_INPUT, and leaving that state stops the timer - so a stopped timer
## reported 0.0s left and every answer was scored as if it arrived at the
## buzzer, quietly forfeiting the time bonus (up to 1.5x damage). Only the UI
## path exercised this: the headless bot passes a null timer.
func test_answer_keeps_its_time_bonus(host: Node) -> void:
	var timer := _make_timer(host)
	await host.get_tree().process_frame

	var clue := {
		"id": "clue_timing", "answer": "CAT", "length": 3, "answer_length": 3,
		"clue": "timing fixture", "difficulty": 1, "category": "TEST",
	}
	var enemy := {
		"id": "enemy_timing", "is_boss": false, "base_hp": 500, "max_hp": 500,
		"current_hp": 500, "base_damage": 5, "damage": 5,
		"weakness": null, "resistance": null,
	}
	var player := {"current_hp": 100, "max_hp": 100}

	var machine := CombatStateMachine.new()
	machine.setup(clue, enemy, player, timer)
	machine.begin()

	# Answer immediately, with essentially the whole 45s clock still running.
	var result := machine.submit_answer("CAT")

	assert_true(result.is_correct, "Answer accepted")
	# Full clock => the spec's worked example, 37. Scoring it at the buzzer
	# instead would yield 24.
	assert_eq(int(result.damage_dealt), 37, "A fast answer keeps its full time bonus")
	assert_gt(float(result.damage_dealt), 24.0, "Damage is not the zero-time-left value")

	timer.stop()
	timer.queue_free()

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _make_timer(host: Node) -> TimerSystem:
	var timer := TimerSystem.new()
	host.add_child(timer)
	return timer
