#============================================================================
# MainMenuScene.gd
# Simple main menu for Milestone 1. Provides entry to dungeon demo.
#============================================================================

class_name MainMenuScene
extends Control

@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton

func _ready():
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	get_tree().change_scene_to_file("res://src/scenes/dungeon/DungeonScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
