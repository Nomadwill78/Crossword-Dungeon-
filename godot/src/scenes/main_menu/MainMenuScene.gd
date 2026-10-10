#============================================================================
# MainMenuScene.gd
# Main menu: the Lexicon hub (between-run progression), a quick delve straight
# into a run with the player's current loadout, and quit.
#============================================================================

class_name MainMenuScene
extends Control

@onready var _lexicon_button: Button = %LexiconButton
@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton

func _ready():
	_lexicon_button.pressed.connect(_on_lexicon_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

func _on_lexicon_pressed():
	get_tree().change_scene_to_file("res://src/scenes/lexicon/LexiconScene.tscn")

func _on_start_pressed():
	get_tree().change_scene_to_file("res://src/scenes/dungeon/DungeonScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
