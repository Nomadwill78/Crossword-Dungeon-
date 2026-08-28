## Thin Node wrapper for random_bot.gd — see TestRunner.gd for why this
## indirection is needed (autoloads aren't resolvable as bare identifiers
## under --script/--main-loop, only in a normal scene run like this one).
## Run with: godot --headless --path . tests/bots/BotRunner.tscn
extends Node

func _ready() -> void:
	var bot := RandomBot.new()
	get_tree().quit(0)
