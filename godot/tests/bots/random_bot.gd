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
# Milestone 3: the 100 simulations are one career. Between runs the bot
# shops in the Lexicon (random affordable vocabulary nodes and tomes through
# the real VocabularyTree / TomeManager), each run starts from that loadout,
# and each ends in RunSettlement. After every settlement the bot checks the
# economy invariants (balance never negative or above lifetime Ink, lifetime
# Ink exactly equals everything ever awarded, the level always matches
# lifetime Ink and never falls) - a violation fails the run like a soft-lock.
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

## Economy invariant breaches found across the career. Must stay 0.
var economy_violations: int = 0
var nodes_bought: int = 0
var tomes_bought: int = 0
var achievements_earned: int = 0
var damage_reduction_peak: float = 0.0
## Ink actually paid out by run settlement (excludes the bot's random
## windfalls and achievement rewards), for judging real pacing.
var settled_run_ink: int = 0
var settled_completed_ink: int = 0

# The bot's persistent "player": it never touches the real GameState.
var _profile: Dictionary = {}
var _lexicon: Dictionary = {}
var _statistics: Dictionary = {}
var _tally: Dictionary = {}
var _run_ink: int = 0
var _expected_lifetime: int = 0
var _total_spent: int = 0
var _last_level: int = 1

func run_all() -> void:
	print("=== Random Bot Simulation ===")
	print("Running %d simulations, max %d moves each\n" % [NUM_SIMULATIONS, MAX_MOVES_PER_RUN])

	_profile = GameState.default_profile()
	_lexicon = LexiconState.default_state()
	_statistics = GameState.default_statistics()
	_expected_lifetime = 0
	_total_spent = 0
	_last_level = 1
	EventBus.letter_solved.connect(_on_letter_solved)

	for i in range(NUM_SIMULATIONS):
		_run_simulation()

	EventBus.letter_solved.disconnect(_on_letter_solved)
	_report()

#----------------------------------------------------------------------------
# SIMULATION
#----------------------------------------------------------------------------
func _run_simulation() -> void:
	_grant_and_shop()

	var player_state: Dictionary = {
		"current_hp": 100,
		"max_hp": 100,
		"skip_tokens": 0,
	}
	var loadout := LexiconEffects.apply_to_player_state(player_state, _lexicon)
	damage_reduction_peak = maxf(damage_reduction_peak, float(loadout.damage_reduction))
	_tally = {
		"words_solved": 0, "letters_solved": 0, "enemies_defeated": 0, "bosses_defeated": 0,
		"chains_activated": 0, "chains_by_length": {}, "longest_chain": 0,
	}
	_run_ink = 0

	var completed := _play_run(player_state)
	_check(int(player_state.current_hp) <= int(player_state.max_hp), "HP never exceeds max HP")

	var run := {
		"player_state": { "total_ink_drops_this_run": _run_ink, "loadout": loadout },
		"tally": _tally,
		"final_score": 100 if completed else 0,
		"duration_seconds": 60.0 if completed else INF,
	}
	var summary := RunSettlement.settle(_profile, _lexicon, _statistics, run, completed)
	_expected_lifetime += int(summary.ink.total)
	settled_run_ink += int(summary.ink.total)
	if completed:
		settled_completed_ink += int(summary.ink.total)
	for earned in summary.achievements:
		_expected_lifetime += int(earned.reward_ink)
		achievements_earned += 1
	_check_economy()

## Plays one dungeon. Returns true if the grid was cleared.
func _play_run(player_state: Dictionary) -> bool:
	var generator := GridGenerator.new()
	var grid: Dictionary = generator.generate_grid(5, 1, 1)

	var navigator := GridNavigator.new()
	navigator.initialize(grid)

	var activated_chains: Dictionary = {}
	var failed_cells: Dictionary = {}
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]

	for move in range(MAX_MOVES_PER_RUN):
		total_moves += 1

		if navigator.is_at_exit() and navigator.unsolved_letter_count() == 0:
			runs_completed += 1
			return true

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
				return false
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
			return false

	runs_out_of_moves += 1
	return false

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
		_solve(navigator, target, clue, player_state)
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
		_tally["enemies_defeated"] = int(_tally.enemies_defeated) + 1
		_solve(navigator, target, clue, player_state)
		LexiconEffects.heal_for_solve(player_state, clue)
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
			_tally["chains_activated"] = int(_tally.chains_activated) + 1
			_tally["longest_chain"] = maxi(int(_tally.longest_chain), int(chain.length))
			var by_length: Dictionary = _tally.chains_by_length
			by_length[str(chain.length)] = int(by_length.get(str(chain.length), 0)) + 1
			_run_ink += InkDropManager.ink_for_chain(player_state.get("loadout", {}))

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
# LEXICON CAREER
#----------------------------------------------------------------------------

## Sometimes hands the bot a windfall (tracked, so the ledger still has to
## balance), then spends whatever it can afford at random.
func _grant_and_shop() -> void:
	if randf() < 0.3:
		var grant := randi_range(100, 1500)
		InkDropManager.award(_profile, grant, "bot_grant")
		_expected_lifetime += grant

	for attempt in range(6):
		if randf() < 0.5:
			var nodes: Array[String] = []
			for tree in LexiconData.get_trees():
				for node in tree.get("nodes", []):
					nodes.append(String(node.get("node_id", "")))
			nodes.shuffle()
			for node_id in nodes:
				if bool(VocabularyTree.can_purchase(_lexicon, _profile, node_id).ok):
					var bought := VocabularyTree.purchase(_lexicon, _profile, node_id)
					_total_spent += int(bought.cost)
					nodes_bought += 1
					break
		else:
			var tomes := LexiconData.get_tomes()
			tomes.shuffle()
			for tome in tomes:
				var tome_id := String(tome.get("tome_id", ""))
				if bool(TomeManager.can_buy(_lexicon, _profile, tome_id).ok):
					var bought := TomeManager.buy(_lexicon, _profile, tome_id)
					_total_spent += int(bought.cost)
					tomes_bought += 1
					break

	# Re-roll the loadout: empty the slots, then equip owned tomes at random.
	for slot in range((_lexicon.equipped_tomes as Array).size()):
		TomeManager.unequip(_lexicon, slot)
	var owned: Array = (_lexicon.unlocked_tomes as Array).duplicate()
	owned.shuffle()
	for tome_id in owned:
		if randf() < 0.7:
			TomeManager.equip(_lexicon, String(tome_id))

	# Buying the last node of a tree can earn Vocabulary Master; account for
	# its reward exactly, like every other Ink the ledger must explain.
	for earned in AchievementTracker.evaluate(_profile, _lexicon, _statistics):
		_expected_lifetime += int(earned.reward_ink)
		achievements_earned += 1

func _solve(navigator: GridNavigator, target: Vector2i, clue: Dictionary, player_state: Dictionary) -> void:
	if navigator.solve_cell(target, String(clue.get("answer", ""))):
		_tally["words_solved"] = int(_tally.words_solved) + 1
		_run_ink += LexiconEffects.ink_bonus_for_word(player_state, clue)

func _on_letter_solved(_pos: Vector2i, _letter: String, ink_drops: int) -> void:
	_tally["letters_solved"] = int(_tally.get("letters_solved", 0)) + 1
	_run_ink += ink_drops

func _check(condition: bool, description: String) -> void:
	if not condition:
		economy_violations += 1
		push_error("RandomBot: invariant broken: %s" % description)

func _check_economy() -> void:
	var balance := int(_profile.ink_drops)
	var lifetime := int(_profile.total_ink_drops)
	_check(balance >= 0, "balance is never negative")
	_check(balance <= lifetime, "balance never exceeds lifetime Ink")
	_check(lifetime == _expected_lifetime, "lifetime Ink (%d) equals everything awarded (%d)" % [lifetime, _expected_lifetime])
	_check(balance == lifetime - _total_spent, "balance (%d) equals lifetime minus spending (%d)" % [balance, lifetime - _total_spent])
	var level := int(_profile.player_level)
	_check(level == PlayerLevel.level_for_ink(lifetime), "level matches lifetime Ink")
	_check(level >= _last_level, "level never falls")
	_last_level = level

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
	print("--- Lexicon career ---")
	print("Vocabulary nodes bought:        %d" % nodes_bought)
	print("Tomes bought:                   %d" % tomes_bought)
	print("Achievements earned:            %d" % achievements_earned)
	print("Final level / lifetime Ink:     %d / %d (inflated by random bot windfalls)" % [int(_profile.player_level), int(_profile.total_ink_drops)])
	print("Avg Ink paid per run:           %s (cleared runs: %s)" % [
		str(snappedf(float(settled_run_ink) / NUM_SIMULATIONS, 0.1)),
		str(snappedf(float(settled_completed_ink) / maxf(1.0, float(runs_completed)), 0.1)),
	])
	print("Peak damage reduction rolled:   %s" % str(snappedf(damage_reduction_peak, 0.01)))
	print("Economy violations:             %d" % economy_violations)
	if encounters_fought > 0:
		var win_rate := float(encounters_won) / float(encounters_fought) * 100.0
		print("Encounter win rate:             %s%%" % str(snappedf(win_rate, 0.1)))
	print("Completion rate:                %s%%" % str(
		snappedf(float(runs_completed) / NUM_SIMULATIONS * 100.0, 0.1)
	))
