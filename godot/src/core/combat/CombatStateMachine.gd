#============================================================================
# CombatStateMachine.gd
# Drives one combat encounter from clue reveal to victory or defeat
# (CLAUDE.md 4.2 state machine pattern).
#
# Two deliberate differences from the CLAUDE.md 4.2 sketch:
#  * `extends RefCounted`, not Node. An encounter is a short-lived object,
#    and the playtest bot creates hundreds per session; RefCounted frees
#    itself, so a bot run cannot leak encounters.
#  * Transitions are synchronous. The sketch awaits a reveal animation inside
#    `_enter_reveal_clue`, which makes the machine untestable without a
#    SceneTree and hides the flow behind coroutines. Here the scene owns
#    presentation delay and calls begin() when it is done animating; headless
#    callers just call begin() immediately.
#
# Dependencies: CombatEngine, ClueResolver, TimerSystem, ConfigLoader
# Events: state_changed, attempt_resolved, combat_finished (+ EventBus)
#============================================================================

class_name CombatStateMachine
extends RefCounted

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal state_changed(old_state: int, new_state: int)
signal attempt_resolved(result: Dictionary)
signal combat_finished(result: Dictionary)

#----------------------------------------------------------------------------
# ENUMS
#----------------------------------------------------------------------------
enum State {
	IDLE,
	REVEAL_CLUE,
	AWAIT_INPUT,
	VALIDATE_ANSWER,
	APPLY_DAMAGE,
	ENEMY_ATTACK,
	CHECK_RESOLUTION,
	VICTORY,
	DEFEAT,
	CLEANUP,
}

#----------------------------------------------------------------------------
# PUBLIC VARIABLES
#----------------------------------------------------------------------------
var current_state: int = State.IDLE
var attempt_number: int = 1
var max_attempts: int = 3

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _clue: Dictionary = {}
var _enemy: Dictionary = {}
var _player_state: Dictionary = {}
var _timer: TimerSystem = null
var _cell_pos: Vector2i = Vector2i.ZERO

var _damage_dealt_total: int = 0
var _damage_taken_total: int = 0
var _last_result: Dictionary = {}
var _finished: bool = false

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Prepares an encounter. Does not start the timer - call begin() for that.
##
## [param clue] Clue Dictionary (ClueDatabase)
## [param enemy] Runtime enemy state (EnemyDatabase.build_encounter)
## [param player_state] Mutated in place as the player takes damage
## [param timer] Optional; when null the encounter is untimed (headless
##               tests and the playtest bot run this way)
## [param cell_pos] Grid cell this encounter belongs to, echoed back in the
##                  finished result so the caller knows what to solve
func setup(
	clue: Dictionary,
	enemy: Dictionary,
	player_state: Dictionary,
	timer: TimerSystem = null,
	cell_pos: Vector2i = Vector2i.ZERO
) -> void:
	_clue = clue
	_enemy = enemy
	_player_state = player_state
	_timer = timer
	_cell_pos = cell_pos
	_damage_dealt_total = 0
	_damage_taken_total = 0
	_finished = false
	attempt_number = 1
	max_attempts = int(_combat_config().get("max_attempts", 3))

	if _timer != null and not _timer.timer_expired.is_connected(_on_timer_expired):
		_timer.timer_expired.connect(_on_timer_expired)

	_transition_to(State.REVEAL_CLUE)

## Moves from the clue reveal into accepting input, starting the timer.
## The scene calls this once its reveal animation finishes.
func begin() -> void:
	if current_state != State.REVEAL_CLUE:
		return
	_transition_to(State.AWAIT_INPUT)

## Submits [param raw_answer] as this attempt. Returns the attempt result
## (see CombatEngine.resolve_attempt), or an empty Dictionary if the
## encounter is not currently accepting input.
func submit_answer(raw_answer: String) -> Dictionary:
	if current_state != State.AWAIT_INPUT:
		return {}
	return _resolve(raw_answer, false)

## Ends the current attempt as a timeout (no damage dealt, enemy strikes).
func force_timeout() -> Dictionary:
	if current_state != State.AWAIT_INPUT:
		return {}
	return _resolve("", true)

func is_finished() -> bool:
	return _finished

func get_clue() -> Dictionary:
	return _clue

func get_enemy() -> Dictionary:
	return _enemy

func attempts_remaining() -> int:
	return maxi(0, max_attempts - attempt_number + 1)

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
func _transition_to(new_state: int) -> void:
	var old_state := current_state
	_exit_state(old_state)
	current_state = new_state
	_enter_state(new_state)
	state_changed.emit(old_state, new_state)

func _enter_state(state: int) -> void:
	match state:
		State.REVEAL_CLUE:
			EventBus.combat_started.emit(String(_enemy.get("id", "")), String(_clue.get("id", "")))
			if bool(_enemy.get("is_boss", false)):
				EventBus.boss_encountered.emit(String(_enemy.get("id", "")))
		State.AWAIT_INPUT:
			if _timer != null:
				_timer.start(int(_clue.get("difficulty", 1)), _timer_modifiers())
		State.VICTORY:
			_finish(true)
		State.DEFEAT:
			_finish(false)

func _exit_state(state: int) -> void:
	match state:
		State.AWAIT_INPUT:
			# Leaving input for any reason stops the clock, so a slow
			# animation or a resolved attempt cannot be "timed out".
			if _timer != null:
				_timer.stop()

## One attempt, walked through the validate -> damage -> resolution states.
func _resolve(raw_answer: String, timed_out: bool) -> Dictionary:
	# Read the clock BEFORE leaving AWAIT_INPUT. Exiting that state stops the
	# timer, and a stopped timer reports 0.0 seconds left - so sampling after
	# the transition would score every answer as if it arrived at the buzzer
	# and silently forfeit the whole time bonus (up to 1.5x damage).
	var time_remaining := 0.0 if _timer == null else _timer.get_time_remaining()
	# With no timer attached the encounter is untimed, so a correct answer
	# should not be penalised for having "no time left".
	if _timer == null and not timed_out:
		time_remaining = TimerSystem.base_seconds_for_difficulty(int(_clue.get("difficulty", 1)))

	_transition_to(State.VALIDATE_ANSWER)

	var result := CombatEngine.resolve_attempt(
		raw_answer, _clue, _enemy, _player_state, attempt_number, time_remaining, timed_out
	)
	_last_result = result

	EventBus.answer_submitted.emit(
		String(result.get("answer", "")), bool(result.is_correct), attempt_number
	)

	if bool(result.is_correct):
		_transition_to(State.APPLY_DAMAGE)
		_apply_damage_to_enemy(result)
	else:
		_transition_to(State.ENEMY_ATTACK)
		_apply_damage_to_player(result)

	attempt_resolved.emit(result)
	_transition_to(State.CHECK_RESOLUTION)
	_check_resolution(result)
	return result

func _apply_damage_to_enemy(result: Dictionary) -> void:
	var damage := int(result.get("damage_dealt", 0))
	_damage_dealt_total += damage
	_enemy["current_hp"] = maxi(0, int(_enemy.get("current_hp", 0)) - damage)
	EventBus.combat_damage_dealt.emit(damage, String(_enemy.get("id", "")))

	# A correct answer that does not finish the enemy still draws a counter.
	var taken := int(result.get("damage_taken", 0))
	if taken > 0:
		_apply_damage_to_player(result)

func _apply_damage_to_player(result: Dictionary) -> void:
	var damage := int(result.get("damage_taken", 0))
	if damage <= 0:
		return
	_damage_taken_total += damage
	var hp := int(_player_state.get("current_hp", 0)) - damage
	_player_state["current_hp"] = maxi(0, hp)
	EventBus.combat_damage_taken.emit(damage, String(_enemy.get("id", "")))
	EventBus.player_hp_changed.emit(
		int(_player_state["current_hp"]), int(_player_state.get("max_hp", 100))
	)

func _check_resolution(result: Dictionary) -> void:
	if int(_player_state.get("current_hp", 0)) <= 0:
		_transition_to(State.DEFEAT)
		return

	if int(_enemy.get("current_hp", 0)) <= 0:
		_transition_to(State.VICTORY)
		return

	if not bool(result.is_correct):
		attempt_number += 1
		if attempt_number > max_attempts:
			# Out of attempts: the encounter ends without solving the cell.
			_transition_to(State.DEFEAT)
			return

	_transition_to(State.AWAIT_INPUT)

func _finish(victory: bool) -> void:
	if _finished:
		return
	_finished = true

	if _timer != null:
		_timer.stop()
		if _timer.timer_expired.is_connected(_on_timer_expired):
			_timer.timer_expired.disconnect(_on_timer_expired)

	var summary := {
		"victory": victory,
		"enemy_id": String(_enemy.get("id", "")),
		"clue_id": String(_clue.get("id", "")),
		"answer": String(_clue.get("answer", "")),
		"cell": _cell_pos,
		"attempts_used": attempt_number,
		"damage_dealt": _damage_dealt_total,
		"damage_taken": _damage_taken_total,
		"player_hp": int(_player_state.get("current_hp", 0)),
		"player_defeated": int(_player_state.get("current_hp", 0)) <= 0,
	}

	if victory:
		EventBus.enemy_defeated.emit(String(_enemy.get("id", "")), summary)
		if bool(_enemy.get("is_boss", false)):
			EventBus.boss_defeated.emit(String(_enemy.get("id", "")))
	elif summary.player_defeated:
		EventBus.player_defeated.emit()

	EventBus.combat_ended.emit(summary)
	_transition_to(State.CLEANUP)
	combat_finished.emit(summary)

## The player's timer modifiers plus any vocabulary-node bonus for this
## clue's category (player_state.category_timer_bonus, set by LexiconEffects).
func _timer_modifiers() -> Dictionary:
	var modifiers: Dictionary = (_player_state.get("timer_modifiers", {}) as Dictionary).duplicate()
	var by_category: Dictionary = _player_state.get("category_timer_bonus", {})
	var category_bonus := float(by_category.get(String(_clue.get("category", "")), 0.0))
	if category_bonus != 0.0:
		modifiers["timer_bonus"] = float(modifiers.get("timer_bonus", 0.0)) + category_bonus
	return modifiers

func _on_timer_expired() -> void:
	if current_state == State.AWAIT_INPUT:
		force_timeout()

func _combat_config() -> Dictionary:
	return ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("combat", {})
