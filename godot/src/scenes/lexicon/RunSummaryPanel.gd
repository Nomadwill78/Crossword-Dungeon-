#============================================================================
# RunSummaryPanel.gd
# The overlay shown when a run ends: what the run earned, what it banked,
# any level-ups, unlocks and achievements. Built entirely in code (CLAUDE.md
# 2.2) and purely presentational - RunSettlement has already done the work,
# this just reports it.
# Dependencies: Constants
# Events: return_to_lexicon_pressed, delve_again_pressed
#============================================================================

class_name RunSummaryPanel
extends Control

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal return_to_lexicon_pressed
signal delve_again_pressed

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _lexicon_button: Button = null
var _again_button: Button = null

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Fills the panel from a RunSettlement summary and the finished run.
func show_summary(summary: Dictionary, run: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var completed := bool(summary.get("completed", false))
	box.add_child(_label("Dungeon Cleared" if completed else "You Fell", 32, Constants.COLOR_SOLVED_LETTER if completed else Constants.COLOR_EXIT, true))

	var tally: Dictionary = run.get("tally", {})
	box.add_child(_label(
		"Floors cleared %d   |   Deepest depth %d" % [
			int(tally.get("floors_cleared", 0)),
			int(tally.get("deepest_depth", 1)),
		], 14, Color(0.8, 0.8, 0.85), true
	))
	box.add_child(_label(
		"Words solved %d   |   Chains %d   |   Longest chain %d" % [
			int(tally.get("words_solved", 0)),
			int(tally.get("chains_activated", 0)),
			int(tally.get("longest_chain", 0)),
		], 14, Color(0.8, 0.8, 0.85), true
	))
	if int(tally.get("bosses_defeated", 0)) > 0:
		box.add_child(_label("The Thesaurus is defeated!", 15, Constants.COLOR_SOLVED_LETTER, true))
	box.add_child(HSeparator.new())

	var ink: Dictionary = summary.get("ink", {})
	box.add_child(_row("Ink collected", "%d" % int(ink.get("base", 0))))
	if int(ink.get("completion_bonus", 0)) > 0:
		box.add_child(_row("Completion bonus", "+%d" % int(ink.completion_bonus)))
	if int(ink.get("tome_bonus", 0)) > 0:
		box.add_child(_row("Tome bonus", "+%d" % int(ink.tome_bonus)))
	if int(ink.get("defeat_penalty", 0)) > 0:
		box.add_child(_row("Lost with the fall", "-%d" % int(ink.defeat_penalty)))
	box.add_child(_row("Banked", "%d Ink" % int(ink.get("total", 0)), true))

	for earned in summary.get("achievements", []):
		box.add_child(_label("Achievement: %s  (+%d Ink)" % [earned.get("name", ""), int(earned.get("reward_ink", 0))], 14, Color(0.95, 0.85, 0.4)))

	if int(summary.get("new_level", 1)) > int(summary.get("old_level", 1)):
		box.add_child(_label("Level %d -> %d" % [int(summary.old_level), int(summary.new_level)], 18, Color(0.55, 0.9, 0.6), true))
		for unlock in summary.get("unlocks", []):
			box.add_child(_label("Unlocked: %s" % unlock.get("name", ""), 14, Color(0.55, 0.9, 0.6), true))

	box.add_child(_row("Ink balance", "%d" % int(summary.get("balance", 0))))
	box.add_child(HSeparator.new())

	_lexicon_button = Button.new()
	_lexicon_button.text = "Return to the Lexicon"
	_lexicon_button.custom_minimum_size = Vector2(0, 44)
	_lexicon_button.pressed.connect(func(): return_to_lexicon_pressed.emit())
	box.add_child(_lexicon_button)

	_again_button = Button.new()
	_again_button.text = "Delve Again"
	_again_button.custom_minimum_size = Vector2(0, 44)
	_again_button.pressed.connect(func(): delve_again_pressed.emit())
	box.add_child(_again_button)

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
## [param wrap] must be false for a label in a row that does not expand: an
## autowrapping label has no natural width there and collapses to one
## character per line.
func _label(text: String, size: int, color: Color, centered: bool = false, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _row(left: String, right: String, emphasised: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := _label(left, 16 if not emphasised else 18, Color(0.85, 0.85, 0.9))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_label(right, 16 if not emphasised else 18, Constants.COLOR_SOLVED_LETTER if emphasised else Color(0.95, 0.95, 1.0), false, false))
	return row
