#============================================================================
# random_bot.gd
# Automated playtest bot. Navigates generated grids and fights every
# encounter through the real CombatStateMachine, looking for crashes,
# soft-locks, and balance outliers.
#
# The bot drives the state machine directly rather than instantiating
# CombatScene: all encounter logic lives in the machine, the scene is only
# presentation, and skipping the UI keeps a few hundred simulations fast.
#
# Run with: godot --headless --path . tests/bots/BotRunner.tscn
#============================================================================

class_name RandomBot
extends RefCounted

const NUM_SIMULATIONS: int = 100
const MAX_MOVES_PER_RUN: int = 200

## Chance the bot types the right answer. Deliberately well below a real
## player so misses, counter-attacks and attempt exhaustion all get covered.
const CORRECT_ANSWER_CHANCE: float = 0.45

enum FightOutcome { WON, OUT_OF_ATTEMPTS, PLAYER_DIED }

var runs_completed: int = 0
var runs_died: int = 0
var runs_out_of_moves: int = 0
var soft_locks: int = 0
var encounters_fought: int = 0
var encounters_won: int = 0
var encounters_abandoned: int = 0
var chains_activated: int = 0
var total_moves: int = 0

func run_all() -> void:
	print("=== Random Bot Simulation ===")
	print("Running %d simulations, max %d moves each\n" % [NUM_SIMULATIONS, MAX_MOVES_PER_RUN])

	for i in range(NUM_SIMULATIONS):
		_run_simulation()

	_report()

#----------------------------------------------------------------------------
# SIMULATION
#----------------------------------------------------------------------------
func _run_simulation() -> void:
	var generator := GridGenerator.new()
	var grid: Dictionary = generator.generate_grid(5, 1, 1)

	var navigator := GridNavigator.new()
	navigator.initialize(grid)

	var player_state: Dictionary = {
		"current_hp": 100,
		"max_hp": 100,
		"skip_tokens": 0,
	}
	var activated_chains: Dictionary = {}
	var failed_cells: Dictionary = {}
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]

	for move in range(MAX_MOVES_PER_RUN):
		total_moves += 1

		if navigator.is_at_exit() and navigator.unsolved_letter_count() == 0:
			runs_completed += 1
			return

		# Prefer a cell this run has not already failed. A player who just
		# burned three attempts on a clue walks away and comes back; a bot
		# that immediately re-attacks the same wall measures nothing but its
		# own stubbornness.
		var interactables: Array[Vector2i] = navigator.get_adjacent_interactables()
		var candidates: Array[Vector2i] = []
		for pos in interactables:
			if not failed_cells.has(pos):
				candidates.append(pos)
		if candidates.is_empty():
			candidates = interactables

		if not candidates.is_empty():
			var target: Vector2i = candidates[randi() % candidates.size()]
			var outcome := _fight(navigator, grid, player_state, activated_chains, target)
			if outcome == FightOutcome.PLAYER_DIED:
				runs_died += 1
				return
			if outcome == FightOutcome.OUT_OF_ATTEMPTS:
				failed_cells[target] = true
				encounters_abandoned += 1
			continue

		# Nothing to fight nearby: wander.
		directions.shuffle()
		var moved := false
		for direction in directions:
			if navigator.can_move(direction):
				navigator.move(direction)
				moved = true
				break

		if not moved:
			# Boxed in with no reachable encounter - that is a real soft-lock.
			soft_locks += 1
			return

	runs_out_of_moves += 1

## Fights one encounter and reports how it ended.
func _fight(
	navigator: GridNavigator,
	grid: Dictionary,
	player_state: Dictionary,
	activated_chains: Dictionary,
	target: Vector2i
) -> FightOutcome:
	var cell: Dictionary = _cell_at(grid, target)
	var clue: Dictionary = ClueDatabase.get_clue(String(cell.get("clue_id", "")))
	var enemy: Dictionary = EnemyDatabase.build_encounter(String(cell.get("enemy_id", "")), 1, 5)

	# A banked 6-letter chain reward solves the cell outright.
	if int(player_state.get("skip_tokens", 0)) > 0:
		player_state["skip_tokens"] = int(player_state.skip_tokens) - 1
		navigator.solve_cell(target, String(clue.get("answer", "")))
		_resolve_chains(navigator, grid, player_state, activated_chains)
		return FightOutcome.WON

	encounters_fought += 1

	var machine := CombatStateMachine.new()
	machine.setup(clue, enemy, player_state, null, target)
	machine.begin()

	# Answer until the machine says the encounter is over. The machine owns
	# the attempt limit, so this cannot spin forever.
	var guard := 0
	while not machine.is_finished() and guard < 32:
		guard += 1
		machine.submit_answer(_pick_answer(clue))

	if guard >= 32:
		push_error("RandomBot: encounter did not terminate within 32 attempts")
		soft_locks += 1
		return FightOutcome.PLAYER_DIED

	ChainEffects.expire_buffs(player_state)

	if int(player_state.get("current_hp", 0)) <= 0:
		return FightOutcome.PLAYER_DIED

	if int(enemy.get("current_hp", 0)) <= 0:
		encounters_won += 1
		navigator.solve_cell(target, String(clue.get("answer", "")))
		_resolve_chains(navigator, grid, player_state, activated_chains)
		return FightOutcome.WON

	return FightOutcome.OUT_OF_ATTEMPTS

## Mirrors DungeonScene's chain handling so the bot exercises the same paths.
func _resolve_chains(
	navigator: GridNavigator,
	grid: Dictionary,
	player_state: Dictionary,
	activated_chains: Dictionary
) -> void:
	for cascade in range(5):
		var fresh: Array = []
		for chain in ChainDetector.detect_chains(grid):
			if not activated_chains.has(String(chain.id)):
				fresh.append(chain)
		if fresh.is_empty():
			return

		for chain in fresh:
			activated_chains[String(chain.id)] = true
			var effect: Dictionary = ChainEffects.effect_for_chain(chain)
			if effect.is_empty():
				continue
			chains_activated += 1

			var summary: Dictionary = ChainEffects.apply(effect, player_state)
			if bool(summary.get("applied", false)):
				continue

			match String(effect.get("effect", "")):
				"reveal_letter":
					navigator.reveal_random_unsolved_cell()
				"skip_encounter":
					player_state["skip_tokens"] = int(player_state.get("skip_tokens", 0)) + 1
				"clear_line":
					var cells: Array = chain.get("cells", [])
					if cells.is_empty():
						continue
					var first: Vector2i = cells[0]
					var direction := String(chain.get("direction", "horizontal"))
					navigator.clear_unsolved_in_line(
						first.y if direction == "horizontal" else first.x, direction
					)

#----------------------------------------------------------------------------
# HELPERS
#----------------------------------------------------------------------------
func _pick_answer(clue: Dictionary) -> String:
	if randf() < CORRECT_ANSWER_CHANCE:
		return String(clue.get("answer", ""))
	return _random_word(String(clue.get("answer", "")).length())

func _random_word(length: int) -> String:
	const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var out := ""
	for i in range(maxi(1, length)):
		out += LETTERS[randi() % LETTERS.length()]
	return out

func _cell_at(grid: Dictionary, pos: Vector2i) -> Dictionary:
	for cell in grid.get("cells", []):
		if int(cell.get("x", -1)) == pos.x and int(cell.get("y", -1)) == pos.y:
			return cell
	return {}

func _report() -> void:
	print("\n=== Simulation Results ===")
	print("Runs completed (grid cleared):  %d" % runs_completed)
	print("Runs died (HP <= 0):            %d" % runs_died)
	print("Runs out of moves:              %d" % runs_out_of_moves)
	print("Soft-locks:                     %d" % soft_locks)
	print("Encounters fought:              %d" % encounters_fought)
	print("Encounters won:                 %d" % encounters_won)
	print("Encounters abandoned:           %d" % encounters_abandoned)
	print("Chains activated:               %d" % chains_activated)
	print("Average moves per run:          %s" % str(snappedf(float(total_moves) / NUM_SIMULATIONS, 0.1)))
	if encounters_fought > 0:
		var win_rate := float(encounters_won) / float(encounters_fought) * 100.0
		print("Encounter win rate:             %s%%" % str(snappedf(win_rate, 0.1)))
	print("Completion rate:                %s%%" % str(
		snappedf(float(runs_completed) / NUM_SIMULATIONS * 100.0, 0.1)
	))
