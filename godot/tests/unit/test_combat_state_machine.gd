#============================================================================
# test_combat_state_machine.gd
# Unit tests for the encounter flow: attempts, victory, defeat, and the
# guards that stop a finished encounter from accepting more input.
#============================================================================

class_name TestCombatStateMachine
extends TestSuite

func _init() -> void:
	suite_name = "CombatStateMachine"

func run(_host: Node) -> void:
	test_starts_in_reveal_then_awaits_input()
	test_correct_answer_wins()
	test_correct_answer_that_does_not_kill_continues()
	test_wrong_answer_costs_hp_and_consumes_an_attempt()
	test_running_out_of_attempts_ends_the_encounter()
	test_player_death_ends_the_encounter()
	test_timeout_counts_as_a_failed_attempt()
	test_input_rejected_before_begin_and_after_finish()
	test_finished_signal_fires_once()
	test_case_insensitive_answer_accepted()

#----------------------------------------------------------------------------
# TESTS
#----------------------------------------------------------------------------
func test_starts_in_reveal_then_awaits_input() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(100), player)
	assert_eq(machine.current_state, CombatStateMachine.State.REVEAL_CLUE, "setup() reveals the clue")

	machine.begin()
	assert_eq(machine.current_state, CombatStateMachine.State.AWAIT_INPUT, "begin() opens input")
	assert_eq(machine.attempt_number, 1, "First attempt is number 1")
	assert_eq(machine.attempts_remaining(), 3, "Three attempts available")

func test_correct_answer_wins() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	var finished: Array[Dictionary] = []
	machine.combat_finished.connect(func(r: Dictionary): finished.append(r))

	# 30 HP dies to CAT's 37 damage.
	machine.setup(_clue("CAT"), _enemy(30), player)
	machine.begin()
	var result := machine.submit_answer("CAT")

	assert_true(result.is_correct, "CAT is correct")
	assert_true(result.enemy_defeated, "Enemy is defeated")
	assert_eq(machine.current_state, CombatStateMachine.State.CLEANUP, "Encounter cleans up")
	assert_true(machine.is_finished(), "Encounter is finished")
	assert_eq(finished.size(), 1, "combat_finished fired once")
	assert_true(finished[0].victory, "Result records a victory")
	assert_eq(int(finished[0].damage_taken), 0, "Player took no damage")

func test_correct_answer_that_does_not_kill_continues() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(500), player)
	machine.begin()
	var result := machine.submit_answer("CAT")

	assert_true(result.is_correct, "Answer was right")
	assert_false(result.enemy_defeated, "500 HP enemy survives one hit")
	assert_eq(machine.current_state, CombatStateMachine.State.AWAIT_INPUT, "Back to accepting input")
	assert_eq(machine.attempt_number, 1, "A correct answer does not burn an attempt")
	assert_lt(float(player.current_hp), 100.0, "Surviving enemy counter-attacked")

func test_wrong_answer_costs_hp_and_consumes_an_attempt() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(500), player)
	machine.begin()
	var result := machine.submit_answer("DOG")

	assert_false(result.is_correct, "DOG is wrong")
	assert_eq(int(result.damage_dealt), 0, "No damage dealt")
	assert_eq(int(player.current_hp), 93, "Player took 7 damage")
	assert_eq(machine.attempt_number, 2, "Attempt counter advanced")
	assert_eq(machine.attempts_remaining(), 2, "Two attempts left")
	assert_eq(machine.current_state, CombatStateMachine.State.AWAIT_INPUT, "Still accepting input")

func test_running_out_of_attempts_ends_the_encounter() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	var finished: Array[Dictionary] = []
	machine.combat_finished.connect(func(r: Dictionary): finished.append(r))

	machine.setup(_clue("CAT"), _enemy(500), player)
	machine.begin()
	machine.submit_answer("DOG")
	machine.submit_answer("DOG")
	machine.submit_answer("DOG")

	assert_true(machine.is_finished(), "Three misses end the encounter")
	assert_eq(finished.size(), 1, "combat_finished fired once")
	assert_false(finished[0].victory, "Not a victory")
	assert_false(finished[0].player_defeated, "Player survived - they just ran out of tries")
	assert_eq(int(player.current_hp), 79, "Took 7 damage three times")

func test_player_death_ends_the_encounter() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	player["current_hp"] = 5
	var finished: Array[Dictionary] = []
	machine.combat_finished.connect(func(r: Dictionary): finished.append(r))

	machine.setup(_clue("CAT"), _enemy(500), player)
	machine.begin()
	machine.submit_answer("DOG")

	assert_eq(int(player.current_hp), 0, "HP floors at zero, never negative")
	assert_true(machine.is_finished(), "Death ends the encounter immediately")
	assert_true(finished[0].player_defeated, "Result records the player's defeat")
	assert_false(finished[0].victory, "Death is not a victory")

func test_timeout_counts_as_a_failed_attempt() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(500), player)
	machine.begin()
	var result := machine.force_timeout()

	assert_true(result.timed_out, "Result is flagged as a timeout")
	assert_false(result.is_correct, "Timeout is never correct")
	assert_eq(machine.attempt_number, 2, "Timeout burns an attempt")
	assert_eq(int(player.current_hp), 93, "Timeout draws a counter-attack")

func test_input_rejected_before_begin_and_after_finish() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(30), player)

	# Still in REVEAL_CLUE - not accepting answers yet.
	assert_true(machine.submit_answer("CAT").is_empty(), "No input before begin()")

	machine.begin()
	machine.submit_answer("CAT")
	assert_true(machine.is_finished(), "Encounter finished")

	# A late click on Submit must not resurrect a finished encounter.
	assert_true(machine.submit_answer("CAT").is_empty(), "No input after finish")
	assert_true(machine.force_timeout().is_empty(), "No timeout after finish")

func test_finished_signal_fires_once() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	var count := [0]
	machine.combat_finished.connect(func(_r: Dictionary): count[0] += 1)

	machine.setup(_clue("CAT"), _enemy(30), player)
	machine.begin()
	machine.submit_answer("CAT")
	machine.submit_answer("CAT")

	assert_eq(count[0], 1, "combat_finished never fires twice")

func test_case_insensitive_answer_accepted() -> void:
	var machine := CombatStateMachine.new()
	var player := _player()
	machine.setup(_clue("CAT"), _enemy(30), player)
	machine.begin()
	assert_true(machine.submit_answer("  cat ").is_correct, "Lowercase, padded answer accepted")

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _clue(answer: String) -> Dictionary:
	return {
		"id": "clue_test_%s" % answer.to_lower(),
		"answer": answer,
		"length": answer.length(),
		"answer_length": answer.length(),
		"clue": "test clue",
		"difficulty": 1,
		"category": "TEST",
	}

func _enemy(hp: int) -> Dictionary:
	return {
		"id": "enemy_test",
		"is_boss": false,
		"base_hp": hp,
		"max_hp": hp,
		"current_hp": hp,
		"base_damage": 7,
		"damage": 7,
		"weakness": null,
		"resistance": null,
	}

func _player() -> Dictionary:
	return {"current_hp": 100, "max_hp": 100}
