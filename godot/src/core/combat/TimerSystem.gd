#============================================================================
# TimerSystem.gd
# Combat countdown. Emits a warning at each configured threshold and expires
# once at zero.
#
# NOTE ON IMPLEMENTATION: Technical Design Doc 3.2 sketches this system with
# a `_process(delta)` loop that decrements a float and compares ratios every
# frame. CLAUDE.md 2.5 forbids `_process` for game logic ("use timers and
# state machines"), and the sketched ratio comparison is also fragile - it
# only fires a warning if some frame happens to land inside a narrow window
# (`ratio <= 0.5 and ratio > 0.49`), so a frame hitch silently skips it.
# This implementation uses Timer nodes instead: one for expiry, one one-shot
# per warning threshold. Same observable behaviour, no per-frame game logic,
# and warnings cannot be missed. Display code reads get_time_remaining().
#
# Dependencies: ConfigLoader, Constants, GameState
# Events: timer_expired, timer_warning, timer_paused, timer_resumed
#============================================================================

class_name TimerSystem
extends Node

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal timer_expired
signal timer_warning(threshold: float)
signal timer_paused
signal timer_resumed

#----------------------------------------------------------------------------
# PUBLIC VARIABLES
#----------------------------------------------------------------------------
var max_time: float = 30.0
var is_running: bool = false
var is_paused: bool = false

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _expiry_timer: Timer
var _warning_timers: Array[Timer] = []

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready() -> void:
	_expiry_timer = Timer.new()
	_expiry_timer.one_shot = true
	_expiry_timer.timeout.connect(_on_expiry_timeout)
	add_child(_expiry_timer)

func _exit_tree() -> void:
	_clear_warning_timers()

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Starts a countdown sized for [param clue_difficulty], adjusted by
## [param player_modifiers] (timer_bonus seconds, then timer_multiplier) and
## by the accessibility extended-timer setting.
func start(clue_difficulty: int, player_modifiers: Dictionary = {}) -> void:
	stop()
	max_time = calculate_max_time(clue_difficulty, player_modifiers)
	is_running = true
	is_paused = false

	_expiry_timer.start(max_time)
	_schedule_warnings()

## Stops the countdown without emitting expiry. Safe to call when idle.
func stop() -> void:
	is_running = false
	is_paused = false
	if _expiry_timer:
		_expiry_timer.stop()
	_clear_warning_timers()

func pause() -> void:
	if not is_running or is_paused:
		return
	is_paused = true
	_set_all_paused(true)
	timer_paused.emit()

func resume() -> void:
	if not is_running or not is_paused:
		return
	is_paused = false
	_set_all_paused(false)
	timer_resumed.emit()

## Seconds left, or 0.0 when not running. Read this for display; do not
## re-derive elapsed time by counting frames.
func get_time_remaining() -> float:
	if not is_running or _expiry_timer == null:
		return 0.0
	return _expiry_timer.time_left

## Fraction of the original time still left, 0.0-1.0. Handy for progress bars.
func get_time_ratio() -> float:
	if max_time <= 0.0:
		return 0.0
	return clampf(get_time_remaining() / max_time, 0.0, 1.0)

## Shortens the remaining time by [param multiplier] (the Acronym enemy's
## "Abbreviate" ability halves it). Re-schedules warnings against the new
## remaining time.
func scale_remaining(multiplier: float) -> void:
	if not is_running:
		return
	var remaining := get_time_remaining() * clampf(multiplier, 0.0, 1.0)
	_expiry_timer.stop()
	_clear_warning_timers()
	if remaining <= 0.0:
		_on_expiry_timeout()
		return
	_expiry_timer.start(remaining)
	_schedule_warnings()

## Base seconds for a clue of [param difficulty], before modifiers.
## Static so CombatEngine can compute its time-bonus ratio against the same
## number the timer actually used, without needing a TimerSystem instance.
static func base_seconds_for_difficulty(difficulty: int) -> float:
	var timer_cfg: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("timer", {})
	var table: Dictionary = timer_cfg.get("base_seconds_by_difficulty", {})
	var key := str(difficulty)
	if table.has(key):
		return float(table[key])
	return float(timer_cfg.get("default_seconds", 30))

## Full time budget for a clue, including player modifiers and accessibility.
static func calculate_max_time(clue_difficulty: int, player_modifiers: Dictionary = {}) -> float:
	var timer_cfg: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("timer", {})
	var seconds := base_seconds_for_difficulty(clue_difficulty)

	seconds += float(player_modifiers.get("timer_bonus", 0.0))
	seconds *= float(player_modifiers.get("timer_multiplier", 1.0))

	var accessibility: Dictionary = GameState.settings.get("accessibility", {})
	if bool(accessibility.get("extended_timer", false)):
		seconds *= float(timer_cfg.get("accessibility_extended_multiplier", 1.5))

	return maxf(0.0, seconds)

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
func _schedule_warnings() -> void:
	_clear_warning_timers()
	var timer_cfg: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("timer", {})
	var thresholds: Array = timer_cfg.get("warning_thresholds", [])
	var remaining := get_time_remaining()

	for threshold_value in thresholds:
		var threshold := float(threshold_value)
		# Fire when the countdown crosses this fraction of the time left.
		var delay := remaining - (remaining * threshold)
		if delay <= 0.0 or delay >= remaining:
			continue
		var warning := Timer.new()
		warning.one_shot = true
		warning.timeout.connect(_on_warning_timeout.bind(threshold))
		add_child(warning)
		warning.start(delay)
		_warning_timers.append(warning)

func _clear_warning_timers() -> void:
	for warning in _warning_timers:
		if is_instance_valid(warning):
			warning.stop()
			warning.queue_free()
	_warning_timers.clear()

func _set_all_paused(paused: bool) -> void:
	if _expiry_timer:
		_expiry_timer.paused = paused
	for warning in _warning_timers:
		if is_instance_valid(warning):
			warning.paused = paused

func _on_warning_timeout(threshold: float) -> void:
	if is_running:
		timer_warning.emit(threshold)

func _on_expiry_timeout() -> void:
	is_running = false
	_clear_warning_timers()
	timer_expired.emit()
	EventBus.timer_expired.emit()
