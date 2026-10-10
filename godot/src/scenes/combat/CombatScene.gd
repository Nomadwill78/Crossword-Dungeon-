#============================================================================
# CombatScene.gd
# The Word Duel UI (Design Doc 4.2): shows the clue, takes a typed answer,
# runs the countdown, and reports the outcome back to the dungeon.
#
# All encounter logic lives in CombatStateMachine; this script is presentation
# and input only. That split is what lets the playtest bot exercise combat
# headlessly without instantiating any of this.
#
# Dependencies: CombatStateMachine, TimerSystem, ClueResolver, ChainDetector
# Events: combat_finished
#============================================================================

class_name CombatScene
extends Control

#----------------------------------------------------------------------------
# CONSTANTS
#----------------------------------------------------------------------------
## Beat between the clue appearing and input opening, so the encounter does
## not start mid-keystroke from the move that triggered it.
const REVEAL_SECONDS: float = 0.6

## How often the countdown bar redraws. CLAUDE.md 2.5 rules out `_process`
## for game logic; this is display-only refresh, and 20Hz is smooth enough
## for a bar while costing far less than a per-frame callback.
const UI_REFRESH_SECONDS: float = 0.05

const MAX_LOG_LINES: int = 6

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal combat_finished(result: Dictionary)

#----------------------------------------------------------------------------
# ONREADY VARIABLES
#----------------------------------------------------------------------------
@onready var _phase_banner: Label = %PhaseBanner
@onready var _ability_notice: Label = %AbilityNotice
@onready var _enemy_name: Label = %EnemyName
@onready var _enemy_flavor: Label = %EnemyFlavor
@onready var _enemy_hp_bar: ProgressBar = %EnemyHpBar
@onready var _enemy_hp_label: Label = %EnemyHpLabel
@onready var _timer_bar: ProgressBar = %TimerBar
@onready var _timer_label: Label = %TimerLabel
@onready var _clue_text: Label = %ClueText
@onready var _clue_meta: Label = %ClueMeta
@onready var _answer_input: LineEdit = %AnswerInput
@onready var _submit_button: Button = %SubmitButton
@onready var _attempts_label: Label = %AttemptsLabel
@onready var _player_hp_bar: ProgressBar = %PlayerHpBar
@onready var _player_hp_label: Label = %PlayerHpLabel
@onready var _combat_log: Label = %CombatLog

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _machine: CombatStateMachine = null
var _timer_system: TimerSystem = null
var _reveal_timer: Timer
var _ui_refresh_timer: Timer
var _player_state: Dictionary = {}
var _log_lines: Array[String] = []
var _pending: Dictionary = {}

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready() -> void:
	_timer_system = TimerSystem.new()
	_timer_system.name = "TimerSystem"
	add_child(_timer_system)
	_timer_system.timer_warning.connect(_on_timer_warning)

	_reveal_timer = Timer.new()
	_reveal_timer.one_shot = true
	_reveal_timer.timeout.connect(_on_reveal_finished)
	add_child(_reveal_timer)

	_ui_refresh_timer = Timer.new()
	_ui_refresh_timer.wait_time = UI_REFRESH_SECONDS
	_ui_refresh_timer.timeout.connect(_refresh_timer_display)
	add_child(_ui_refresh_timer)

	_submit_button.pressed.connect(_on_submit_pressed)
	_answer_input.text_submitted.connect(_on_answer_submitted)

	_set_input_enabled(false)

	# If start_encounter() was called before this scene entered the tree,
	# the encounter was parked in _pending; run it now that nodes exist.
	if not _pending.is_empty():
		var pending := _pending
		_pending = {}
		start_encounter(pending.clue, pending.enemy, pending.player_state, pending.cell, pending.options)

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Begins an encounter. [param player_state] is mutated in place as the player
## takes damage, so the caller sees HP changes without a round trip.
##
## [param options] Optional: `round_mode` (bool) makes this one round of a
## longer fight - a correct answer ends the round with the enemy still
## standing; `banner` (String) is a line shown above the enemy's name, used for
## the boss's phase.
func start_encounter(
	clue: Dictionary,
	enemy: Dictionary,
	player_state: Dictionary,
	cell_pos: Vector2i = Vector2i.ZERO,
	options: Dictionary = {}
) -> void:
	if not is_node_ready():
		_pending = {"clue": clue, "enemy": enemy, "player_state": player_state, "cell": cell_pos, "options": options}
		return

	_player_state = player_state
	_log_lines.clear()
	_phase_banner.text = String(options.get("banner", ""))
	_phase_banner.visible = _phase_banner.text != ""
	_ability_notice.text = ""

	_machine = CombatStateMachine.new()
	_machine.round_mode = bool(options.get("round_mode", false))
	_machine.attempt_resolved.connect(_on_attempt_resolved)
	_machine.combat_finished.connect(_on_combat_finished)
	_machine.prompt_changed.connect(_on_prompt_changed)
	_machine.ability_triggered.connect(_on_ability_triggered)
	_machine.setup(clue, enemy, player_state, _timer_system, cell_pos)

	_show_clue(clue, enemy)
	_refresh_enemy_hp()
	_refresh_player_hp()
	_refresh_attempts()
	_append_log("%s blocks the way." % String(enemy.get("display_name", enemy.get("name", "Something"))))

	_set_input_enabled(false)
	_reveal_timer.start(REVEAL_SECONDS)

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
func _show_clue(clue: Dictionary, enemy: Dictionary) -> void:
	_enemy_name.text = String(enemy.get("display_name", enemy.get("name", "Enemy")))
	_enemy_flavor.text = String(enemy.get("flavor_text", ""))
	# The machine's prompt, not the clue's text: an ability may already have
	# garbled or blended it during the reveal.
	_clue_text.text = _machine.get_prompt()

	var length: int = int(clue.get("answer_length", clue.get("length", 0)))
	var category := String(clue.get("category", "")).replace("_", " ").capitalize()
	_clue_meta.text = "%d letters   -   %s" % [length, category]
	# An accepted alternate spelling can be longer than the demanded one.
	var longest := length
	for alternate in clue.get("alternates", []):
		longest = maxi(longest, String(alternate.get("answer", "")).length())
	_answer_input.max_length = longest
	_answer_input.text = ""

func _set_input_enabled(enabled: bool) -> void:
	_answer_input.editable = enabled
	_submit_button.disabled = not enabled
	if enabled:
		_answer_input.grab_focus()

func _on_reveal_finished() -> void:
	if _machine == null or _machine.is_finished():
		return
	_machine.begin()
	_set_input_enabled(true)
	_ui_refresh_timer.start()

func _on_submit_pressed() -> void:
	_on_answer_submitted(_answer_input.text)

func _on_answer_submitted(text: String) -> void:
	if _machine == null or _machine.is_finished():
		return
	if _machine.current_state != CombatStateMachine.State.AWAIT_INPUT:
		return
	if ClueResolver.normalize(text).is_empty():
		return
	_machine.submit_answer(text)

func _on_attempt_resolved(result: Dictionary) -> void:
	_answer_input.text = ""

	if bool(result.get("mirrored", false)):
		_append_log("Your answer was read backwards!")

	if bool(result.get("timed_out", false)):
		_append_log("Out of time! You take %d damage." % int(result.damage_taken))
	elif bool(result.is_correct):
		var line := "\"%s\" hits for %d." % [String(result.answer), int(result.damage_dealt)]
		if bool(result.get("weakness_hit", false)):
			line = "Weakness! " + line
		elif bool(result.get("resistance_hit", false)):
			line = "Resisted. " + line
		if bool(result.get("alternate_hit", false)):
			line += " (Only the old spelling lands in full.)"
		if int(result.get("damage_taken", 0)) > 0:
			line += " It strikes back for %d." % int(result.damage_taken)
		_append_log(line)
	else:
		_append_log("\"%s\" is wrong. You take %d damage." % [
			String(result.answer), int(result.damage_taken)
		])

	_refresh_enemy_hp()
	_refresh_player_hp()
	_refresh_attempts()

	# The machine reopens input by itself when the encounter continues.
	if not _machine.is_finished():
		_set_input_enabled(true)

func _on_combat_finished(result: Dictionary) -> void:
	_set_input_enabled(false)
	_ui_refresh_timer.stop()
	_timer_bar.value = 0.0
	_timer_label.text = ""

	if bool(result.victory) and not bool(result.get("enemy_dead", true)):
		_append_log("Round cleared.")
	elif bool(result.victory):
		_append_log("Defeated! The letters are yours.")
	elif bool(result.player_defeated):
		_append_log("You fall. The dungeon keeps its word.")
	else:
		_append_log("Out of attempts. The cell stays locked.")

	_refresh_enemy_hp()
	_refresh_player_hp()
	combat_finished.emit(result)

func _on_prompt_changed(text: String) -> void:
	_clue_text.text = text

func _on_ability_triggered(info: Dictionary) -> void:
	_ability_notice.text = String(info.get("message", ""))
	_append_log(String(info.get("message", "")))

func _on_timer_warning(threshold: float) -> void:
	_append_log("%d%% of your time is gone." % int(round((1.0 - threshold) * 100.0)))

func _refresh_timer_display() -> void:
	if _timer_system == null or not _timer_system.is_running:
		return
	_timer_bar.value = _timer_system.get_time_ratio() * 100.0
	_timer_label.text = "%.1fs" % _timer_system.get_time_remaining()

func _refresh_enemy_hp() -> void:
	if _machine == null:
		return
	var enemy := _machine.get_enemy()
	var max_hp: int = maxi(1, int(enemy.get("max_hp", 1)))
	var current: int = int(enemy.get("current_hp", 0))
	_enemy_hp_bar.value = (float(current) / float(max_hp)) * 100.0
	_enemy_hp_label.text = "%d / %d" % [current, max_hp]

func _refresh_player_hp() -> void:
	var max_hp: int = maxi(1, int(_player_state.get("max_hp", 100)))
	var current: int = int(_player_state.get("current_hp", 0))
	_player_hp_bar.value = (float(current) / float(max_hp)) * 100.0
	_player_hp_label.text = "%d / %d" % [current, max_hp]

func _refresh_attempts() -> void:
	if _machine == null:
		return
	_attempts_label.text = "Attempts left: %d" % _machine.attempts_remaining()

func _append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	_combat_log.text = "\n".join(_log_lines)
