#============================================================================
# LexiconScene.gd
# The Lexicon: the persistent hub between runs (Design Doc 4.5). Four tabs -
# Vocabulary Trees, Tomes, the Trophy Room, and Delve (pick a grid size and
# start a run) - under a header showing the Ink balance and player level.
#
# Built entirely in code (CLAUDE.md 2.2) and presentation only: every rule
# lives in VocabularyTree / TomeManager / InkDropManager / AchievementTracker.
# The scene's public action methods (buy_node, buy_tome, ...) are what its
# buttons call, and are also what the tests drive. Every successful action is
# saved straight away, so a crash never loses a purchase.
#
# Dependencies: VocabularyTree, TomeManager, InkDropManager, PlayerLevel,
#               AchievementTracker, LexiconData, GameState, SaveManager
# Events: none of its own - the systems it calls emit on EventBus
#============================================================================

class_name LexiconScene
extends Control

#----------------------------------------------------------------------------
# CONSTANTS
#----------------------------------------------------------------------------
const DUNGEON_SCENE_PATH := "res://src/scenes/dungeon/DungeonScene.tscn"
const MENU_SCENE_PATH := "res://src/scenes/main_menu/MainMenuScene.tscn"

const COLOR_TEXT := Color(0.92, 0.92, 0.96)
const COLOR_DIM := Color(0.62, 0.62, 0.7)
const COLOR_GOOD := Color(0.55, 0.9, 0.6)
const COLOR_GOLD := Color(0.95, 0.85, 0.4)
const COLOR_RARITY := {
	"common": Color(0.75, 0.75, 0.8),
	"uncommon": Color(0.45, 0.85, 0.55),
	"rare": Color(0.55, 0.65, 1.0),
}

const CARD_WIDTH: int = 230

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _ink_label: Label
var _level_label: Label
var _level_bar: ProgressBar
var _streak_label: Label
var _toast_label: Label
var _tabs: TabContainer
var _vocabulary_box: VBoxContainer
var _tomes_box: VBoxContainer
var _trophy_box: VBoxContainer
var _delve_box: VBoxContainer

var _selected_grid_size: int = 5

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	_claim_daily_login()
	_refresh()

#----------------------------------------------------------------------------
# PUBLIC METHODS - actions (buttons call these; tests do too)
#----------------------------------------------------------------------------

## Buys a vocabulary node. Returns true on success.
func buy_node(node_id: String) -> bool:
	var verdict := VocabularyTree.purchase(GameState.get_lexicon(), GameState.player_profile, node_id)
	if not bool(verdict.ok):
		_toast(_describe_failure(String(verdict.reason)), true)
		return false
	_toast("Learned %s" % LexiconData.get_node_def(node_id).get("name", node_id))
	_after_change()
	return true

## Buys a tome (into the library, not a slot). Returns true on success.
func buy_tome(tome_id: String) -> bool:
	var verdict := TomeManager.buy(GameState.get_lexicon(), GameState.player_profile, tome_id)
	if not bool(verdict.ok):
		_toast(_describe_failure(String(verdict.reason)), true)
		return false
	_toast("Acquired %s" % LexiconData.get_tome(tome_id).get("name", tome_id))
	_after_change()
	return true

## Equips an owned tome in the first free slot. Returns true on success.
func equip_tome(tome_id: String) -> bool:
	var verdict := TomeManager.equip(GameState.get_lexicon(), tome_id)
	if not bool(verdict.ok):
		_toast(_describe_failure(String(verdict.reason)), true)
		return false
	_after_change()
	return true

## Empties a tome slot. Returns true if something was unequipped.
func unequip_slot(slot: int) -> bool:
	if not TomeManager.unequip(GameState.get_lexicon(), slot):
		return false
	_after_change()
	return true

## Chooses the grid size for the next delve, if the player's level allows it.
func select_grid_size(size: int) -> bool:
	if not PlayerLevel.available_grid_sizes(_level()).has(size):
		_toast("That dungeon size is not unlocked yet.", true)
		return false
	_selected_grid_size = size
	_refresh()
	return true

## Hands the chosen options to the next run and, unless [param change_scene]
## is false (tests), starts it.
func begin_delve(change_scene: bool = true) -> void:
	GameState.run_options = {"grid_size": _selected_grid_size}
	if change_scene:
		get_tree().change_scene_to_file(DUNGEON_SCENE_PATH)

#----------------------------------------------------------------------------
# PRIVATE METHODS - flow
#----------------------------------------------------------------------------
func _level() -> int:
	return int(GameState.player_profile.get("player_level", 1))

## Runs after any successful purchase or loadout change: achievements may
## have been earned (Vocabulary Master), then save and redraw.
func _after_change() -> void:
	var earned := AchievementTracker.evaluate(GameState.player_profile, GameState.get_lexicon(), GameState.statistics)
	for achievement in earned:
		_toast("Achievement: %s (+%d Ink)" % [achievement.name, achievement.reward_ink])
	SaveManager.save_game()
	_refresh()

func _claim_daily_login() -> void:
	var result := InkDropManager.claim_daily_login(GameState.player_profile, Time.get_date_string_from_system())
	if not bool(result.claimed):
		return
	_toast("Daily login: +%d Ink (day %d streak)" % [int(result.amount), int(result.streak)])
	AchievementTracker.evaluate(GameState.player_profile, GameState.get_lexicon(), GameState.statistics)
	SaveManager.save_game()

func _describe_failure(reason: String) -> String:
	match reason:
		"insufficient_ink":
			return "Not enough Ink Drops."
		"prerequisites":
			return "Learn the earlier nodes first."
		"locked":
			return "That tome is still locked."
		"already_purchased", "already_owned":
			return "You already have that."
		"no_free_slot":
			return "All tome slots are full. Unequip one first."
		"already_equipped":
			return "That tome is already equipped."
		"not_owned":
			return "Buy that tome first."
	return "That is not possible right now."

func _toast(text: String, is_error: bool = false) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", Constants.COLOR_EXIT if is_error else COLOR_GOOD)

#----------------------------------------------------------------------------
# PRIVATE METHODS - building the frame
#----------------------------------------------------------------------------
func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.08, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# Header: title, Ink, level.
	var title := _label("The Lexicon", 34, Constants.COLOR_SOLVED_LETTER, false)
	root.add_child(title)

	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 24)
	root.add_child(header)
	_ink_label = _label("", 20, COLOR_GOLD, false)
	header.add_child(_ink_label)
	_level_label = _label("", 18, COLOR_TEXT, false)
	header.add_child(_level_label)
	_streak_label = _label("", 14, COLOR_DIM, false)
	header.add_child(_streak_label)

	_level_bar = ProgressBar.new()
	_level_bar.custom_minimum_size = Vector2(0, 14)
	_level_bar.show_percentage = false
	_level_bar.max_value = 1.0
	_level_bar.add_theme_stylebox_override("background", _bar_style(Color(0.2, 0.19, 0.27)))
	_level_bar.add_theme_stylebox_override("fill", _bar_style(COLOR_GOLD))
	root.add_child(_level_bar)

	_toast_label = _label("", 15, COLOR_GOOD)
	_toast_label.custom_minimum_size = Vector2(0, 22)
	root.add_child(_toast_label)

	# Tabs.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_vocabulary_box = _add_tab("Vocabulary")
	_tomes_box = _add_tab("Tomes")
	_trophy_box = _add_tab("Trophy Room")
	_delve_box = _add_tab("Delve")

	var back := Button.new()
	back.text = "Main Menu"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE_PATH))
	root.add_child(back)

## A scrolling tab page; returns the VBox its content goes in.
func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(inner)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	inner.add_child(box)
	return box

#----------------------------------------------------------------------------
# PRIVATE METHODS - refreshing
#----------------------------------------------------------------------------
func _refresh() -> void:
	var profile: Dictionary = GameState.player_profile
	var lifetime := int(profile.get("total_ink_drops", 0))
	var progress := PlayerLevel.progress(lifetime)

	_ink_label.text = "Ink Drops: %d" % int(profile.get("ink_drops", 0))
	_level_label.text = "Level %d" % int(progress.level)
	if bool(progress.is_max):
		_level_label.text += "  (MAX)"
	else:
		_level_label.text += "  (%d / %d to next)" % [int(progress.ink_into_level), int(progress.ink_for_next)]
	_level_bar.value = float(progress.fraction)
	_streak_label.text = "Login streak: %d day(s)" % int(profile.get("current_streak_days", 0))

	var available := PlayerLevel.available_grid_sizes(int(progress.level))
	if not available.has(_selected_grid_size):
		_selected_grid_size = available[0]

	_rebuild_vocabulary()
	_rebuild_tomes()
	_rebuild_trophy_room()
	_rebuild_delve()

func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

#----------------------------------------------------------------------------
# PRIVATE METHODS - Vocabulary tab
#----------------------------------------------------------------------------
func _rebuild_vocabulary() -> void:
	_clear(_vocabulary_box)
	var lexicon: Dictionary = GameState.get_lexicon()
	var balance := int(GameState.player_profile.get("ink_drops", 0))

	_vocabulary_box.add_child(_label("Spend Ink Drops to learn the words of each realm. Each node unlocks the next.", 14, COLOR_DIM))

	for tree in LexiconData.get_trees():
		var tree_id := String(tree.get("tree_id", ""))
		var color := Color.from_string(String(tree.get("tree_color", "#ffffff")), Color.WHITE)

		var header := _label("%s  -  %s" % [tree.get("tree_name", tree_id), _category_name(String(tree.get("category", "")))], 20, color)
		_vocabulary_box.add_child(header)
		_vocabulary_box.add_child(_label(String(tree.get("tree_description", "")), 13, COLOR_DIM))

		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		_vocabulary_box.add_child(row)

		for node in tree.get("nodes", []):
			row.add_child(_node_card(lexicon, node, balance, color))

func _node_card(lexicon: Dictionary, node: Dictionary, balance: int, accent: Color) -> Control:
	var node_id := String(node.get("node_id", ""))
	var cost := int(node.get("cost", 0))
	var state := VocabularyTree.node_state(lexicon, node_id)

	var card := _card(accent if state != VocabularyTree.NodeState.LOCKED else COLOR_DIM)
	var box: VBoxContainer = card.get_meta("box")
	box.add_child(_label(String(node.get("name", node_id)), 17, COLOR_TEXT))
	box.add_child(_label(String(node.get("description", "")), 13, COLOR_DIM))

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 36)
	match state:
		VocabularyTree.NodeState.PURCHASED:
			button.text = "Learned"
			button.disabled = true
		VocabularyTree.NodeState.AVAILABLE:
			if balance >= cost:
				button.text = "Learn - %d Ink" % cost
				button.pressed.connect(buy_node.bind(node_id))
			else:
				button.text = "Need %d more Ink" % (cost - balance)
				button.disabled = true
		_:
			button.text = "Requires %s" % _prerequisite_names(node)
			button.disabled = true
	box.add_child(button)
	return card

func _prerequisite_names(node: Dictionary) -> String:
	var names: Array[String] = []
	for prerequisite in node.get("prerequisites", []):
		names.append(String(LexiconData.get_node_def(String(prerequisite)).get("name", prerequisite)))
	return ", ".join(names)

## "FANTASY_CREATURES" -> "Fantasy Creatures".
func _category_name(category: String) -> String:
	return category.replace("_", " ").capitalize()

#----------------------------------------------------------------------------
# PRIVATE METHODS - Tomes tab
#----------------------------------------------------------------------------
func _rebuild_tomes() -> void:
	_clear(_tomes_box)
	var lexicon: Dictionary = GameState.get_lexicon()
	var profile: Dictionary = GameState.player_profile

	_tomes_box.add_child(_label("Equipped Tomes", 20, Constants.COLOR_SOLVED_LETTER))
	var slots: Array = lexicon.get("equipped_tomes", [])
	for slot in range(slots.size()):
		var row := HBoxContainer.new()
		_tomes_box.add_child(row)
		var tome_id = slots[slot]
		var text := "Slot %d: empty" % (slot + 1)
		if tome_id != null:
			text = "Slot %d: %s" % [slot + 1, LexiconData.get_tome(String(tome_id)).get("name", tome_id)]
		var slot_label := _label(text, 16, COLOR_TEXT if tome_id != null else COLOR_DIM)
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot_label)
		if tome_id != null:
			var remove := Button.new()
			remove.text = "Unequip"
			remove.pressed.connect(unequip_slot.bind(slot))
			row.add_child(remove)

	_tomes_box.add_child(HSeparator.new())
	_tomes_box.add_child(_label("Library", 20, Constants.COLOR_SOLVED_LETTER))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_tomes_box.add_child(flow)
	for tome in LexiconData.get_tomes():
		flow.add_child(_tome_card(lexicon, profile, tome))

func _tome_card(lexicon: Dictionary, profile: Dictionary, tome: Dictionary) -> Control:
	var tome_id := String(tome.get("tome_id", ""))
	var cost := int(tome.get("cost", 0))
	var state := TomeManager.tome_state(lexicon, profile, tome_id)
	var rarity_color: Color = COLOR_RARITY.get(String(tome.get("rarity", "common")), COLOR_TEXT)

	var card := _card(rarity_color if state != TomeManager.TomeState.LOCKED else COLOR_DIM)
	var box: VBoxContainer = card.get_meta("box")
	box.add_child(_label(String(tome.get("name", tome_id)), 17, rarity_color))
	box.add_child(_label(String(tome.get("rarity", "")).capitalize(), 12, COLOR_DIM))
	box.add_child(_label(String(tome.get("description", "")), 13, COLOR_TEXT))

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 36)
	match state:
		TomeManager.TomeState.LOCKED:
			button.text = "Locked - %s" % TomeManager.describe_condition(tome)
			button.disabled = true
		TomeManager.TomeState.AVAILABLE:
			if InkDropManager.can_afford(profile, cost):
				button.text = "Buy - %d Ink" % cost
				button.pressed.connect(buy_tome.bind(tome_id))
			else:
				button.text = "Need %d more Ink" % (cost - int(profile.get("ink_drops", 0)))
				button.disabled = true
		TomeManager.TomeState.OWNED:
			button.text = "Equip"
			var has_room: bool = (lexicon.get("equipped_tomes", []) as Array).has(null)
			button.disabled = not has_room
			if has_room:
				button.pressed.connect(equip_tome.bind(tome_id))
			else:
				button.text = "Slots full"
		TomeManager.TomeState.EQUIPPED:
			button.text = "Equipped"
			button.disabled = true
	box.add_child(button)
	return card

#----------------------------------------------------------------------------
# PRIVATE METHODS - Trophy Room tab
#----------------------------------------------------------------------------
func _rebuild_trophy_room() -> void:
	_clear(_trophy_box)
	var lexicon: Dictionary = GameState.get_lexicon()
	var profile: Dictionary = GameState.player_profile
	var statistics: Dictionary = GameState.statistics

	_trophy_box.add_child(_label("Achievements", 20, Constants.COLOR_SOLVED_LETTER))
	for achievement in LexiconData.get_achievements():
		var id := String(achievement.get("achievement_id", ""))
		var earned := AchievementTracker.is_earned(lexicon, id)
		var line := "%s - %s" % [achievement.get("name", id), achievement.get("description", "")]
		if earned:
			line += "   [earned]"
		else:
			line += "   [+%d Ink]" % int(achievement.get("reward_ink", 0))
		_trophy_box.add_child(_label(line, 15, COLOR_GOLD if earned else COLOR_DIM))

	_trophy_box.add_child(HSeparator.new())
	_trophy_box.add_child(_label("Records", 20, Constants.COLOR_SOLVED_LETTER))
	var records := [
		["Runs", "%d (%d cleared)" % [int(profile.get("total_runs", 0)), int(profile.get("runs_completed", 0))]],
		["Best score", str(int(profile.get("best_score", 0)))],
		["Letters solved", str(int(profile.get("total_letters_solved", 0)))],
		["Words solved", str(int(statistics.get("total_words_solved", 0)))],
		["Enemies defeated", str(int(statistics.get("total_enemies_defeated", 0)))],
		["Deaths", str(int(statistics.get("total_deaths", 0)))],
		["Longest chain", str(int(profile.get("longest_chain", 0)))],
		["Chains activated", str(int(statistics.get("total_chains", 0)))],
		["Longest login streak", "%d day(s)" % int(profile.get("longest_streak_days", 0))],
		["Lifetime Ink collected", str(int(profile.get("total_ink_drops", 0)))],
	]
	for record in records:
		var row := HBoxContainer.new()
		var name_label := _label(String(record[0]), 15, COLOR_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_label(String(record[1]), 15, COLOR_TEXT, false))
		_trophy_box.add_child(row)

	var chains: Dictionary = statistics.get("chains_by_length", {})
	if not chains.is_empty():
		var keys: Array = chains.keys()
		keys.sort_custom(func(a, b): return int(a) < int(b))
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s-letter x%d" % [key, int(chains[key])])
		_trophy_box.add_child(_label("Chains by length: " + ", ".join(parts), 14, COLOR_DIM))

#----------------------------------------------------------------------------
# PRIVATE METHODS - Delve tab
#----------------------------------------------------------------------------
func _rebuild_delve() -> void:
	_clear(_delve_box)
	var level := _level()

	_delve_box.add_child(_label("Choose your dungeon", 20, Constants.COLOR_SOLVED_LETTER))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 8)
	_delve_box.add_child(sizes)
	var available := PlayerLevel.available_grid_sizes(level)
	var group := ButtonGroup.new()
	for size in PlayerLevel.supported_grid_sizes():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = "%d x %d" % [size, size]
		button.custom_minimum_size = Vector2(90, 40)
		if available.has(size):
			button.button_pressed = size == _selected_grid_size
			button.pressed.connect(select_grid_size.bind(size))
		else:
			button.disabled = true
		sizes.add_child(button)

	_delve_box.add_child(_label("Loadout", 18, Constants.COLOR_SOLVED_LETTER))
	var equipped := TomeManager.equipped_tomes(GameState.get_lexicon())
	if equipped.is_empty():
		_delve_box.add_child(_label("No tomes equipped.", 14, COLOR_DIM))
	for tome in equipped:
		_delve_box.add_child(_label("%s - %s" % [tome.get("name", ""), tome.get("description", "")], 14, COLOR_TEXT))

	var begin := Button.new()
	begin.text = "Begin Delve"
	begin.custom_minimum_size = Vector2(0, 52)
	begin.add_theme_font_size_override("font_size", 20)
	begin.pressed.connect(begin_delve)
	_delve_box.add_child(begin)

	_delve_box.add_child(HSeparator.new())
	_delve_box.add_child(_label("Level rewards", 18, Constants.COLOR_SOLVED_LETTER))
	for unlock in PlayerLevel.unlocks():
		var reached := level >= int(unlock.get("level", 0))
		var line := "Level %d - %s: %s" % [int(unlock.level), unlock.get("name", ""), unlock.get("description", "")]
		_delve_box.add_child(_label(line, 14, COLOR_GOOD if reached else COLOR_DIM))

#----------------------------------------------------------------------------
# PRIVATE METHODS - widgets
#----------------------------------------------------------------------------
## [param wrap] should be false for a label that sits in a flow or a row
## without expanding: an autowrapping label has no natural width there, so
## the container shrinks it to one character per line.
func _label(text: String, size: int, color: Color, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	return style

## A bordered card; its content VBox is stored in the "box" meta key.
func _card(accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.13, 0.19)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	card.set_meta("box", box)
	return card
