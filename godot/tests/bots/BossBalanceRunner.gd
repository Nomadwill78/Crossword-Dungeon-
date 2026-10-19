## Prints how often each kind of simulated player beats The Thesaurus.
## Run with: godot --headless --path . tests/bots/BossBalanceRunner.tscn
## Optional, after `--`: `--fights=1000` for more fights per cell (default from
## boss_balance.json); `--grid=9` for a larger dungeon (5, 7 or 9; the boss has a
## little more HP on bigger grids); `--bonus=10` and `--hp-offset=20` to try a boss
## clock bonus (seconds per round) or extra boss HP without editing its data;
## `--sensitivity` for how the geared win rates
## move when each assumption about how people play is changed. Always exits 0: this is a
## report, the pass/fail checks live in tests/unit/test_boss_balance.gd.
extends Node

const SEED_BASE := 20260101

func _ready() -> void:
	var cfg := BossBalance.config()
	var fights := int(cfg.get("fights_per_cell", 400))
	var sensitivity := false
	var grid_size := BossBalance.DEFAULT_GRID_SIZE
	var what_if := {}
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--fights="):
			fights = maxi(1, int(String(arg).trim_prefix("--fights=")))
		elif String(arg).begins_with("--grid="):
			grid_size = int(String(arg).trim_prefix("--grid="))
		elif String(arg).begins_with("--bonus="):
			what_if["round_timer_bonus"] = float(String(arg).trim_prefix("--bonus="))
		elif String(arg).begins_with("--hp-offset="):
			what_if["hp_offset"] = int(String(arg).trim_prefix("--hp-offset="))
		elif String(arg) == "--sensitivity":
			sensitivity = true

	var boss: Dictionary = EnemyDatabase.build_encounter(String(EnemyDatabase.get_boss_ids()[0]), 5, grid_size)
	print("The Thesaurus at depth 5 on a %dx%d grid: %d HP, %d damage per miss (before the player's damage reduction)" % [grid_size, grid_size, int(boss.max_hp), int(boss.damage)])
	print("%d fights per cell, seed %d. Win rate / avg rounds / avg misses (of which timeouts) / HP left\n" % [fights, SEED_BASE])

	if sensitivity:
		_print_sensitivity(cfg, fights, what_if)
		get_tree().quit(0)
		return

	var archetypes: Dictionary = cfg.get("archetypes", {})
	for loadout_name in cfg.get("loadouts", {}).keys():
		if String(loadout_name).begins_with("_"):
			continue
		var player := BossBalance.make_player(String(loadout_name))
		print("== %s loadout: %d max HP, %d%% damage reduction, arrives with %d HP ==" % [
			loadout_name, int(player.max_hp), int(round(float(player.damage_reduction) * 100.0)), int(player.current_hp)])
		for depth in cfg.get("depths", [5]):
			print("  depth %d" % int(depth))
			for archetype_name in archetypes.keys():
				var r := BossBalance.run_cell(archetypes[archetype_name], String(loadout_name), int(depth), fights, SEED_BASE, _options(grid_size, what_if))
				print("    %-8s %3d%% win | %4.1f rounds | %4.1f misses (%3.1f timeouts) | %3d%% HP left | reach p2 %3d%% p3 %3d%%" % [
					archetype_name, int(round(float(r.win_rate) * 100.0)), float(r.avg_rounds),
					float(r.avg_misses), float(r.avg_timeouts), int(round(float(r.avg_hp_fraction_left) * 100.0)),
					int(round(float(r.phase_reached_rate[2] + r.phase_reached_rate[3]) * 100.0)),
					int(round(float(r.phase_reached_rate[3]) * 100.0))])
		print("")
	get_tree().quit(0)

## How the geared win rates (average / strong players, by depth) move when one
## assumption at a time is changed. A tuning that only works for one exact set
## of guesses is not a tuning; this shows how much the answer depends on them.
func _print_sensitivity(cfg: Dictionary, fights: int, what_if: Dictionary) -> void:
	var variants: Array = [
		["as configured", {}],
		["arrive at full HP", {"arrival_hp": 1.0}],
		["arrive at 60% HP", {"arrival_hp": 0.6}],
		["opposite-of phase is easy (x1.0)", {"model": {"phase_recall_multiplier": {"2": 1.0}}}],
		["opposite-of phase is hard (x0.6)", {"model": {"phase_recall_multiplier": {"2": 0.6}}}],
		["nobody knows the archaic spelling", {"model": {"archaic_known_chance": 0.0}}],
		["everyone knows the archaic spelling", {"model": {"archaic_known_chance": 1.0}}],
		["twice the typos (6%)", {"model": {"typo_chance": 0.06}}],
		["no typos", {"model": {"typo_chance": 0.0}}],
		["everyone 30% slower", {"speed_scale": 1.3}],
		["everyone 30% faster", {"speed_scale": 0.7}],
		["7x7 grid (boss +4 HP)", {"grid_size": 7}],
		["9x9 grid (boss +8 HP)", {"grid_size": 9}],
	]
	var archetypes: Dictionary = cfg.get("archetypes", {})
	print("Geared win rates, %d fights each. Columns: depth 5 / 10 / 15.\n" % fights)
	print("%-36s %-17s %-17s" % ["assumption changed", "average", "strong"])
	for variant in variants:
		var options: Dictionary = (variant[1] as Dictionary).duplicate(true)
		options.merge(what_if)
		var cells := {}
		for archetype_name in ["average", "strong"]:
			var profile: Dictionary = (archetypes[archetype_name] as Dictionary).duplicate()
			profile["speed"] = float(profile.speed) * float(options.get("speed_scale", 1.0))
			var rates: Array[String] = []
			for depth in cfg.get("depths", [5, 10, 15]):
				var r := BossBalance.run_cell(profile, "geared", int(depth), fights, SEED_BASE, options)
				rates.append("%3d" % int(round(float(r.win_rate) * 100.0)))
			cells[archetype_name] = " / ".join(rates)
		print("%-36s %-17s %-17s" % [variant[0], cells.average, cells.strong])

func _options(grid_size: int, what_if: Dictionary) -> Dictionary:
	var options := {"grid_size": grid_size}
	options.merge(what_if)
	return options
