#============================================================================
# InkDropManager.gd
# The Ink Drop ledger (Design Doc 4.5). Ink is earned by solving letters,
# completing chains, finishing dungeons and logging in daily; it is spent on
# vocabulary nodes and tomes. No microtransactions - every drop is earned in
# play.
#
# Two counters live on the player profile and they mean different things:
#   ink_drops        - the spendable balance
#   total_ink_drops  - everything ever collected; this alone drives the level
#
# All functions take the profile Dictionary explicitly instead of reaching
# for the GameState autoload (CLAUDE.md 2.4), which keeps them unit-testable.
# Dependencies: PlayerLevel, ConfigLoader, Constants, EventBus
# Events: ink_drops_earned, ink_drops_spent, ink_drops_changed, level_up
#============================================================================

class_name InkDropManager
extends RefCounted

#----------------------------------------------------------------------------
# PUBLIC METHODS - ledger
#----------------------------------------------------------------------------

## Adds [param amount] Ink Drops to [param profile] and levels the player up
## if the new lifetime total crosses a threshold. A non-positive amount is a
## no-op.
##
## [param source] Free-text origin ("run_end", "daily_login", "achievement:x")
## [return] { awarded, balance, old_level, new_level }
static func award(profile: Dictionary, amount: int, source: String) -> Dictionary:
	var old_level := int(profile.get("player_level", 1))
	var result := {
		"awarded": 0,
		"balance": int(profile.get("ink_drops", 0)),
		"old_level": old_level,
		"new_level": old_level,
	}
	if amount <= 0:
		return result

	var balance := int(profile.get("ink_drops", 0)) + amount
	var lifetime := int(profile.get("total_ink_drops", 0)) + amount
	profile["ink_drops"] = balance
	profile["total_ink_drops"] = lifetime

	# Levels never go backwards, even if the curve is retuned in a later build.
	var new_level := maxi(old_level, PlayerLevel.level_for_ink(lifetime))
	profile["player_level"] = new_level

	result.awarded = amount
	result.balance = balance
	result.new_level = new_level

	EventBus.ink_drops_earned.emit(amount, source)
	EventBus.ink_drops_changed.emit(balance, amount)
	for level in range(old_level + 1, new_level + 1):
		EventBus.level_up.emit(level)
	return result

## True when the spendable balance covers [param amount].
static func can_afford(profile: Dictionary, amount: int) -> bool:
	return amount >= 0 and int(profile.get("ink_drops", 0)) >= amount

## Spends [param amount] from the balance. Returns false, changing nothing,
## when the player cannot afford it. Lifetime Ink (and so level) is untouched.
static func spend(profile: Dictionary, amount: int, item: String) -> bool:
	if not can_afford(profile, amount):
		return false
	if amount == 0:
		return true
	var balance := int(profile.get("ink_drops", 0)) - amount
	profile["ink_drops"] = balance
	EventBus.ink_drops_spent.emit(amount, item)
	EventBus.ink_drops_changed.emit(balance, -amount)
	return true

#----------------------------------------------------------------------------
# PUBLIC METHODS - run economy
#----------------------------------------------------------------------------

## Ink earned for one activated chain: the flat chain reward from game_config
## plus any vocabulary-node chain bonus in [param loadout].
static func ink_for_chain(loadout: Dictionary) -> int:
	var base := int(_economy().get("ink_per_chain", 20))
	return base + int(loadout.get("chain_ink_bonus", 0))

## Works out what a finished run pays out.
##
## Completed runs gain the completion bonus. The equipped tomes' multiplier
## applies to the whole haul. A lost run then keeps only `defeat_retention`
## of it.
##
## [param base_ink] Ink collected during the run itself (letters, chains, bonuses)
## [param completed] True if the dungeon was cleared
## [param loadout] LexiconEffects.build_loadout output (for ink_multiplier)
## [return] { base, completion_bonus, tome_bonus, defeat_penalty, total }
static func settle_run_ink(base_ink: int, completed: bool, loadout: Dictionary) -> Dictionary:
	var economy := _economy()
	var completion_bonus := int(economy.get("run_completion_bonus", 0)) if completed else 0
	var gross := maxi(0, base_ink) + completion_bonus
	var boosted := int(floor(gross * float(loadout.get("ink_multiplier", 1.0))))

	var total := boosted
	var defeat_penalty := 0
	if not completed:
		total = int(floor(boosted * clampf(float(economy.get("defeat_retention", 1.0)), 0.0, 1.0)))
		defeat_penalty = boosted - total

	return {
		"base": maxi(0, base_ink),
		"completion_bonus": completion_bonus,
		"tome_bonus": boosted - gross,
		"defeat_penalty": defeat_penalty,
		"total": total,
	}

#----------------------------------------------------------------------------
# PUBLIC METHODS - daily login
#----------------------------------------------------------------------------

## Pays the once-a-day login reward and maintains the streak counters.
##
## [param today] "YYYY-MM-DD". Passed in rather than read from the clock so
##               tests can walk across days.
## [return] { claimed, amount, streak }. claimed is false when today was
##          already claimed, or when the clock has gone backwards (which
##          would otherwise let a player farm the reward by re-dating).
static func claim_daily_login(profile: Dictionary, today: String) -> Dictionary:
	var streak := int(profile.get("current_streak_days", 0))
	var last := String(profile.get("last_login_date", ""))
	var denied := { "claimed": false, "amount": 0, "streak": streak }

	var today_day := _day_number(today)
	if today_day < 0:
		push_warning("InkDropManager: ignoring malformed login date '%s'" % today)
		return denied

	if last != "":
		var last_day := _day_number(last)
		if last_day >= 0:
			if today_day <= last_day:
				return denied
			streak = streak + 1 if today_day - last_day == 1 else 1
		else:
			streak = 1
	else:
		streak = 1

	var economy := _economy()
	var bonus := mini(
		int(economy.get("daily_streak_bonus_per_day", 0)) * (streak - 1),
		int(economy.get("daily_streak_bonus_cap", 0))
	)
	var amount := int(economy.get("daily_login_ink", 0)) + bonus

	profile["last_login_date"] = today
	profile["current_streak_days"] = streak
	profile["longest_streak_days"] = maxi(int(profile.get("longest_streak_days", 0)), streak)
	award(profile, amount, "daily_login")
	return { "claimed": true, "amount": amount, "streak": streak }

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _economy() -> Dictionary:
	return ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).get("ink_economy", {})

## Whole days since 1970-01-01 for a "YYYY-MM-DD" string, or -1 if malformed.
static func _day_number(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return -1
	var month := int(parts[1])
	var day := int(parts[2])
	if month < 1 or month > 12 or day < 1 or day > 31:
		return -1
	var stamp := "%04d-%02d-%02dT00:00:00" % [int(parts[0]), month, day]
	return floori(Time.get_unix_time_from_datetime_string(stamp) / 86400.0)
