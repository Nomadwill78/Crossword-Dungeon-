#============================================================================
# SimTimer.gd
# A stand-in for TimerSystem that lets a headless simulation say exactly how
# much time was left when an answer arrived. CombatStateMachine reads the
# clock from whatever timer it was given, so handing it this one makes the
# damage formula's speed bonus (and a timeout) depend on a simulated human's
# response time instead of the wall clock. Test code only: nothing here
# changes how the real game runs.
# Dependencies: TimerSystem
# Events: none (timer_expired is inherited but never emitted; the simulation
#         calls CombatStateMachine.force_timeout() when its player runs out)
#============================================================================

class_name SimTimer
extends TimerSystem

## What get_time_remaining() reports while the clock is "running".
var simulated_remaining: float = 0.0

## Starts the clock at its full length for the clue (the same length the real
## TimerSystem would use), without creating any real Timer nodes.
func start(clue_difficulty: int, player_modifiers: Dictionary = {}) -> void:
	max_time = TimerSystem.calculate_max_time(clue_difficulty, player_modifiers)
	simulated_remaining = max_time
	is_running = true
	is_paused = false

func stop() -> void:
	is_running = false

func get_time_remaining() -> float:
	return simulated_remaining if is_running else 0.0
