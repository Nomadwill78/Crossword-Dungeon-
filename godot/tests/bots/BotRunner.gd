## Thin Node wrapper for random_bot.gd - see tests/unit/TestRunner.gd for why
## this indirection is needed (autoloads are not resolvable as bare
## identifiers under --script/--main-loop, only in a normal scene run).
## Run with: godot --headless --path . tests/bots/BotRunner.tscn
extends Node

func _ready() -> void:
	var bot := RandomBot.new()
	bot.run_all()

	# A soft-lock or a non-terminating encounter is a hard failure, not a
	# statistic - fail the run so CI notices.
	var exit_code := 1 if (bot.soft_locks > 0 or bot.economy_violations > 0) else 0
	if bot.soft_locks > 0:
		push_error("RandomBot: %d soft-lock(s) detected" % bot.soft_locks)
	if bot.economy_violations > 0:
		push_error("RandomBot: %d Ink economy invariant violation(s)" % bot.economy_violations)
	get_tree().quit(exit_code)
