#============================================================================
# FloorPanel.gd
# The choice shown when a floor is cleared: go deeper (or, on a boss floor,
# face The Thesaurus to earn the way down) or cash out and bank the run.
# Built in code (CLAUDE.md 2.2); purely presentational - DungeonScene decides
# what each button does.
# Dependencies: Constants
# Events: primary_pressed, cash_out_pressed
#============================================================================

class_name FloorPanel
extends Control

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal primary_pressed
signal cash_out_pressed

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _primary_button: Button = null
var _cash_out_button: Button = null

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Fills the panel. [param info] keys:
##   depth (int) the floor just cleared, hp / max_hp (int), run_ink (int) Ink
##   collected so far, cash_out_ink (int) what cashing out would bank now,
##   primary_text (String) the main button, lines (Array[String]) extra notes,
##   title (String, optional).
func show_floor(info: Dictionary) -> void:
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

	var title := String(info.get("title", "Floor %d cleared" % int(info.get("depth", 1))))
	box.add_child(_label(title, 30, Constants.COLOR_SOLVED_LETTER, true))
	box.add_child(_label(
		"HP %d / %d     Ink this run: %d" % [int(info.get("hp", 0)), int(info.get("max_hp", 0)), int(info.get("run_ink", 0))],
		16, Color(0.85, 0.85, 0.9), true
	))
	for line in info.get("lines", []):
		box.add_child(_label(String(line), 14, Color(0.7, 0.7, 0.78), true))
	box.add_child(HSeparator.new())

	_primary_button = Button.new()
	_primary_button.text = String(info.get("primary_text", "Descend"))
	_primary_button.custom_minimum_size = Vector2(0, 48)
	_primary_button.pressed.connect(func(): primary_pressed.emit())
	box.add_child(_primary_button)

	_cash_out_button = Button.new()
	_cash_out_button.text = "Cash Out  (bank %d Ink)" % int(info.get("cash_out_ink", 0))
	_cash_out_button.custom_minimum_size = Vector2(0, 44)
	_cash_out_button.pressed.connect(func(): cash_out_pressed.emit())
	box.add_child(_cash_out_button)

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
func _label(text: String, size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
