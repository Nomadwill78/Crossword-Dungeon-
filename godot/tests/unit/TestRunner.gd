## Thin Node wrapper so test_grid_generator.gd's SceneTree-based tests run
## with autoloads available. Godot's `--script`/`--main-loop` invocation
## modes replace the main loop *before* project autoloads become resolvable
## as bare identifiers at compile time (confirmed: the autoload nodes exist
## under /root at runtime even then — it's purely a compile-time lookup
## gap) — but a normal scene run, which this is, boots autoloads first.
## Run with: godot --headless --path . tests/unit/TestRunner.tscn
extends Node

func _ready() -> void:
	var suite := TestGridGenerator.new()
	get_tree().quit(1 if suite._tests_failed > 0 else 0)
