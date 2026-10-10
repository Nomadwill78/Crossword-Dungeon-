#============================================================================
# BossEncounter.gd
# The logic of a boss fight (Design Doc 4.4): The Thesaurus, who guards the
# exit of every 5th floor for a player with the Lv 30 unlock.
#
# A fight is a series of single-clue ROUNDS against one shared HP pool. Each
# round is a normal CombatStateMachine in round_mode, so timers, attempts,
# damage and the player's Lexicon bonuses all work exactly as in any duel;
# this class only decides what the next round asks and which phase the boss is
# in. Phases come from the boss's `phases` data (hp_threshold = the fraction of
# max HP at or below which the phase begins):
#
#   1 synonym_swap      the clue is reworded after your first miss
#   2 antonym_inversion the prompt asks for the OPPOSITE of a clue's answer
#   3 obscure_variant   an archaic spelling is demanded; the modern one still
#                       counts, but deals only the boss's exact_match penalty
#
# Round content (variants, opposite pairs, archaic spellings) is data in
# boss_rounds.json. A boss does not counter-attack a correct hit
# (no_counter_on_hit), only a miss, so the fight is long but survivable.
#
# Dependencies: EnemyDatabase, ClueDatabase, PlayerLevel, ConfigLoader
# Events: none - DungeonScene runs the rounds and reports to EventBus
#============================================================================

class_name BossEncounter
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC VARIABLES
#----------------------------------------------------------------------------
## Runtime boss state (EnemyDatabase.build_encounter); current_hp persists
## across rounds because every round's state machine mutates this Dictionary.
var boss: Dictionary = {}
var rounds_played: int = 0
## True when the player died during the fight.
var player_died: bool = false
## True when max_rounds ran out before either side fell.
var abandoned: bool = false

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _used: Dictionary = {}

#----------------------------------------------------------------------------
# PUBLIC METHODS - whether and how a fight starts
#----------------------------------------------------------------------------

## The `boss_encounter` block of game_config.json.
static func config() -> Dictionary:
	return ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("boss_encounter", {})

## True when the boss guards the exit of [param depth] for a player of
## [param player_level]: every every_n_floors-th floor, and only once the
## player has the configured level unlock.
static func is_due(depth: int, player_level: int) -> bool:
	var cfg := config()
	var every := int(cfg.get("every_n_floors", 0))
	if every <= 0 or depth <= 0 or depth % every != 0:
		return false
	var required := String(cfg.get("require_unlock", ""))
	return required == "" or PlayerLevel.is_unlocked(required, player_level)

## Starts a fight against the first boss in the data, scaled to [param depth].
static func begin(depth: int, grid_size: int) -> BossEncounter:
	var ids := EnemyDatabase.get_boss_ids()
	var fight := BossEncounter.new()
	fight.boss = EnemyDatabase.build_encounter(String(ids[0]) if not ids.is_empty() else "", depth, grid_size)
	return fight

#----------------------------------------------------------------------------
# PUBLIC METHODS - state
#----------------------------------------------------------------------------

func hp_fraction() -> float:
	return float(int(boss.get("current_hp", 0))) / float(maxi(1, int(boss.get("max_hp", 1))))

## Index into the boss's `phases` array for an HP fraction. A phase begins when
## HP falls to or below its hp_threshold.
func phase_for_fraction(fraction: float) -> int:
	var phases: Array = boss.get("phases", [])
	var chosen := 0
	for i in range(phases.size()):
		if fraction <= float(phases[i].get("hp_threshold", 1.0)) + 0.0001:
			chosen = i
	return chosen

func current_phase_index() -> int:
	return phase_for_fraction(hp_fraction())

func current_phase() -> Dictionary:
	var phases: Array = boss.get("phases", [])
	if phases.is_empty():
		return {}
	return phases[current_phase_index()]

func is_won() -> bool:
	return int(boss.get("current_hp", 0)) <= 0

func is_over() -> bool:
	return is_won() or player_died or abandoned

## Ink awarded for beating the boss.
func reward_ink() -> int:
	return int(config().get("reward_ink", 0))

## The line shown above the boss during a round: the current phase and what
## it does.
func phase_label() -> String:
	var phase := current_phase()
	if phase.is_empty():
		return String(boss.get("display_name", "Boss"))
	return "Phase %d - %s" % [int(phase.get("phase", current_phase_index() + 1)), String(phase.get("description", ""))]

#----------------------------------------------------------------------------
# PUBLIC METHODS - rounds
#----------------------------------------------------------------------------

## Builds the clue for the next round, according to the current phase's
## ability. The returned Dictionary is a normal clue (so ClueResolver and
## CombatEngine need no special cases) with any extras the phase adds
## (`variant_clue`, `alternates`).
func next_round_clue() -> Dictionary:
	match String(current_phase().get("ability", "")):
		"synonym_swap":
			return _synonym_round()
		"antonym_inversion":
			return _antonym_round()
		"obscure_variant":
			return _archaic_round()
	return _plain_round()

## Records a finished round (the summary CombatStateMachine emitted).
func finish_round(summary: Dictionary) -> void:
	rounds_played += 1
	if bool(summary.get("player_defeated", false)):
		player_died = true
	elif not is_won() and rounds_played >= int(config().get("max_rounds", 60)):
		abandoned = true

#----------------------------------------------------------------------------
# PRIVATE METHODS - round builders
#----------------------------------------------------------------------------
func _rounds_data() -> Dictionary:
	return ConfigLoader.load_json(Constants.BOSS_ROUNDS_PATH)

## Picks an unused key from [param keys]; once every key has been used the
## fight starts reusing them rather than running dry.
func _pick_unused(scope: String, keys: Array) -> Variant:
	if keys.is_empty():
		return null
	var fresh: Array = []
	for key in keys:
		if not _used.has("%s:%s" % [scope, str(key)]):
			fresh.append(key)
	if fresh.is_empty():
		for key in keys:
			_used.erase("%s:%s" % [scope, str(key)])
		fresh = keys
	var picked = fresh[randi() % fresh.size()]
	_used["%s:%s" % [scope, str(picked)]] = true
	return picked

func _with_text(clue: Dictionary, text: String) -> Dictionary:
	clue["clue"] = text
	clue["clue_text"] = text
	return clue

func _synonym_round() -> Dictionary:
	var variants: Dictionary = _rounds_data().get("synonym_variants", {})
	var picked = _pick_unused("synonym", variants.keys())
	if picked == null:
		return _plain_round()
	var clue := ClueDatabase.get_clue(String(picked))
	clue["variant_clue"] = String(variants[picked])
	return clue

func _antonym_round() -> Dictionary:
	var pairs: Array = _rounds_data().get("antonym_pairs", [])
	var directed: Array = []
	for pair in pairs:
		directed.append("%s>%s" % [pair[0], pair[1]])
		directed.append("%s>%s" % [pair[1], pair[0]])
	var picked = _pick_unused("antonym", directed)
	if picked == null:
		return _plain_round()
	var ids := String(picked).split(">")
	var source := ClueDatabase.get_clue(ids[0])
	var target := ClueDatabase.get_clue(ids[1])
	var template := String(_rounds_data().get("prompts", {}).get("antonym", "%s"))
	return _with_text(target, template % String(source.get("clue", "")))

func _archaic_round() -> Dictionary:
	var entries: Array = _rounds_data().get("archaic_spellings", [])
	var picked = _pick_unused("archaic", range(entries.size()))
	if picked == null:
		return _plain_round()
	var entry: Dictionary = entries[int(picked)]
	var clue := ClueDatabase.get_clue(String(entry.get("clue_id", "")))
	var modern := String(clue.get("answer", ""))
	var archaic := String(entry.get("archaic", modern)).to_upper()
	var penalty := float(boss.get("weakness", {}).get("penalty_multiplier", 0.5))

	clue["answer"] = archaic
	clue["length"] = archaic.length()
	clue["answer_length"] = archaic.length()
	clue["alternates"] = [{"answer": modern, "damage_multiplier": penalty}]
	var template := String(_rounds_data().get("prompts", {}).get("archaic", "%s"))
	return _with_text(clue, template % String(clue.get("clue", "")))

## A round with no phase twist: any clue from the pool.
func _plain_round() -> Dictionary:
	var clues := ClueDatabase.get_all_clues()
	return (clues[randi() % clues.size()] as Dictionary).duplicate(true)
