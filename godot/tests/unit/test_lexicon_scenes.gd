#============================================================================
# test_lexicon_scenes.gd
# Scene-level smoke tests for Milestone 3. The unit suites prove the rules;
# these prove the rules are actually wired to the scenes a player touches:
#   * LexiconScene: buying, equipping, grid-size gating, daily login, saving
#   * DungeonScene: the Lexicon loadout applies at run start, Ink is tallied
#     from real events, and a finished run is settled, saved and summarised
#
# DungeonScene's combat hand-off is exercised through _on_combat_finished
# with a fabricated victory result - the same call CombatScene makes - so a
# whole dungeon can be cleared headlessly in milliseconds.
#
# Borrows GameState and points SaveManager at a scratch file; both are put
# back afterwards.
#============================================================================

class_name TestLexiconScenes
extends TestSuite

const SCRATCH_DIR := "user://test_scene_saves/"
const SAVE_FILE := "user://test_scene_saves/save.json"
const LEXICON_SCENE := "res://src/scenes/lexicon/LexiconScene.tscn"
const DUNGEON_SCENE := "res://src/scenes/dungeon/DungeonScene.tscn"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _saved: Dictionary = {}

func _init() -> void:
	suite_name = "Lexicon scenes (smoke)"

func run_async(host: Node) -> void:
	_borrow_state()
	await _test_lexicon_actions(host)
	await _test_daily_login_and_gating(host)
	await _test_full_run_settles(host)
	await _test_defeat_settles(host)
	await _test_grid_size_option(host)
	_return_state()

#----------------------------------------------------------------------------
# FIXTURE
#----------------------------------------------------------------------------
func _borrow_state() -> void:
	_saved = {
		"profile": GameState.player_profile.duplicate(true),
		"lexicon": GameState.lexicon.duplicate(true),
		"settings": GameState.settings.duplicate(true),
		"statistics": GameState.statistics.duplicate(true),
		"run": GameState.current_run.duplicate(true),
		"options": GameState.run_options.duplicate(true),
		"save_path": SaveManager.save_path,
		"backup_dir": SaveManager.backup_dir,
	}
	SaveManager.save_path = SAVE_FILE
	SaveManager.backup_dir = SCRATCH_DIR + "backups/"
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

func _return_state() -> void:
	_wipe(SCRATCH_DIR + "backups/")
	_wipe(SCRATCH_DIR)
	GameState.player_profile = _saved.profile
	GameState.lexicon = _saved.lexicon
	GameState.settings = _saved.settings
	GameState.statistics = _saved.statistics
	GameState.current_run = _saved.run
	GameState.run_options = _saved.options
	SaveManager.save_path = _saved.save_path
	SaveManager.backup_dir = _saved.backup_dir

func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				dir.remove(name)
			name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)

func _fresh_game(ink: int = 0, last_login: String = "") -> void:
	GameState.player_profile = GameState.default_profile()
	GameState.lexicon = LexiconState.default_state()
	GameState.statistics = GameState.default_statistics()
	GameState.current_run = {}
	GameState.run_options = {}
	GameState.player_profile["last_login_date"] = last_login
	if ink > 0:
		InkDropManager.award(GameState.player_profile, ink, "test")

## Hosts the scene in a fixed-size SubViewport. Headless Godot runs in a
## 64x64 window, which would make every layout assertion meaningless; a
## 1280x720 viewport lets the tests check that the UI genuinely fills a
## window (the bug that put the whole Lexicon in a top-left sliver).
func _spawn(host: Node, path: String) -> Node:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	host.add_child(viewport)
	var scene: Node = (load(path) as PackedScene).instantiate()
	viewport.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	return scene

func _despawn(host: Node, scene: Node) -> void:
	scene.get_parent().queue_free()
	await host.get_tree().process_frame

## The tallest visible Label under [param node]. A label squeezed to one
## character per line (the autowrap-in-a-flow bug) is hundreds of pixels tall;
## a healthy wrapped one is a few lines.
func _tallest_label(node: Node) -> float:
	var tallest := 0.0
	if node is Label and (node as Label).is_visible_in_tree():
		tallest = (node as Label).size.y
	for child in node.get_children():
		tallest = maxf(tallest, _tallest_label(child))
	return tallest

func _first_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _first_of_type(child, type_name)
		if found != null:
			return found
	return null

## Every Button under [param node] whose text contains [param needle].
func _buttons(node: Node, needle: String) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button and (node as Button).text.contains(needle):
		out.append(node as Button)
	for child in node.get_children():
		out.append_array(_buttons(child, needle))
	return out

#----------------------------------------------------------------------------
# LEXICON SCENE
#----------------------------------------------------------------------------
func _test_lexicon_actions(host: Node) -> void:
	# A login date in the far future means today is "already claimed".
	_fresh_game(5000, "2999-01-01")
	var scene := await _spawn(host, LEXICON_SCENE) as LexiconScene
	var balance := int(GameState.player_profile.ink_drops)
	assert_eq(balance, 5000, "setup: no daily login was paid")
	assert_true(scene._ink_label.text.contains("5000"), "the header shows the Ink balance")
	assert_eq(scene._tabs.get_tab_count(), 4, "the Lexicon has four tabs")
	assert_gt(scene._tabs.size.x, VIEWPORT_SIZE.x * 0.9, "the tab area spans the window instead of collapsing into a corner")
	assert_gt(scene._tabs.size.y, VIEWPORT_SIZE.y * 0.5, "and is tall enough to be usable")
	assert_lt(_tallest_label(scene), 150.0, "no label is squeezed into a one-character-wide column")

	var learn_buttons := _buttons(scene, "Learn - ")
	assert_gt(float(learn_buttons.size()), 5.0, "every affordable root node offers a Learn button")
	assert_eq(_buttons(scene, "Requires").size(), 14, "the 14 gated nodes are locked behind their prerequisites")

	var cost := int(LexiconData.get_node_def("bst_01").cost)
	assert_true(scene.buy_node("bst_01"), "buying a node through the scene works")
	assert_eq(int(GameState.player_profile.ink_drops), balance - cost, "and spends its cost")
	assert_true(scene._ink_label.text.contains(str(balance - cost)), "the header updates immediately")
	assert_gt(float(_buttons(scene, "Learned").size()), 0.0, "the node now reads Learned")
	assert_false(scene.buy_node("bst_03"), "a gated node is refused through the scene too")
	assert_true(scene._toast_label.text.contains("earlier"), "and the player is told why")
	assert_true(FileAccess.file_exists(SAVE_FILE), "a purchase is saved immediately")

	assert_true(scene.buy_tome("tome_healing_01"), "buying an unlocked tome works")
	assert_false(scene.buy_tome("tome_damage_01"), "a tome whose achievement is unearned is refused")
	assert_true(scene._toast_label.text.contains("locked"), "and the player is told it is locked")
	assert_true(scene.equip_tome("tome_healing_01"), "equipping works")
	assert_eq(GameState.lexicon.equipped_tomes[0], "tome_healing_01", "into slot one")
	assert_gt(float(_buttons(scene, "Unequip").size()), 0.0, "the slot offers an Unequip button")
	assert_true(scene.unequip_slot(0), "unequipping works")
	assert_false(scene.unequip_slot(0), "an empty slot cannot be unequipped")

	# What was saved is what a fresh boot would load.
	var on_disk = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	assert_true((on_disk.lexicon.vocabulary_trees.bestiary.nodes_purchased as Array).has("bst_01"), "the saved file holds the purchase")
	assert_true((on_disk.lexicon.unlocked_tomes as Array).has("tome_healing_01"), "and the owned tome")

	# Completing a tree through the scene awards Vocabulary Master.
	for node_id in ["wld_01", "wld_02", "wld_03"]:
		scene.buy_node(node_id)
	assert_true(AchievementTracker.is_earned(GameState.lexicon, "vocabulary_master"), "finishing a tree in the scene earns the achievement")

	await _despawn(host, scene)

func _test_daily_login_and_gating(host: Node) -> void:
	_fresh_game(0, "")
	var scene := await _spawn(host, LEXICON_SCENE) as LexiconScene
	var base := int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).ink_economy.daily_login_ink)
	assert_eq(int(GameState.player_profile.ink_drops), base, "opening the Lexicon the first time pays the daily login")
	assert_true(scene._toast_label.text.contains("Daily login"), "and says so")
	assert_ne(String(GameState.player_profile.last_login_date), "", "and remembers the date")
	await _despawn(host, scene)

	var before := int(GameState.player_profile.ink_drops)
	var again := await _spawn(host, LEXICON_SCENE) as LexiconScene
	assert_eq(int(GameState.player_profile.ink_drops), before, "reopening the same day pays nothing more")

	assert_eq(PlayerLevel.available_grid_sizes(int(GameState.player_profile.player_level)), [5], "setup: a new player has only 5x5")
	assert_false(again.select_grid_size(7), "a locked grid size cannot be selected")
	assert_true(again.select_grid_size(5), "the default size can")
	again.begin_delve(false)
	assert_eq(int(GameState.run_options.grid_size), 5, "Begin Delve hands the grid size to the run")
	var disabled_sizes := 0
	for button in _buttons(again, " x "):
		if button.disabled:
			disabled_sizes += 1
	assert_eq(disabled_sizes, 2, "the 7x7 and 9x9 buttons are disabled at level 1")
	await _despawn(host, again)

#----------------------------------------------------------------------------
# DUNGEON SCENE
#----------------------------------------------------------------------------

## Clears the dungeon the way the live game does: one finished encounter at a
## time through _on_combat_finished. Returns how many encounters it took.
func _clear_dungeon(scene: DungeonScene) -> int:
	var encounters := 0
	for step in range(80):
		if GameState.current_run.run_status != "in_progress":
			break
		var target := Vector2i(-1, -1)
		var clue_id := ""
		for cell in GameState.current_run.grid_state.cells:
			if cell.type == "letter" and not bool(cell.solved):
				target = Vector2i(int(cell.x), int(cell.y))
				clue_id = String(cell.clue_id)
				break
		if target.x < 0:
			break
		scene._on_combat_finished({
			"victory": true, "player_defeated": false, "cell": target, "clue_id": clue_id,
			"enemy_id": "enemy_test", "answer": ClueDatabase.get_clue(clue_id).answer,
			"attempts_used": 1, "damage_dealt": 10, "damage_taken": 0,
		})
		encounters += 1
	return encounters

func _test_full_run_settles(host: Node) -> void:
	_fresh_game(0, "2999-01-01")
	# Equip Vigor so the loadout visibly reaches the run.
	GameState.lexicon.unlocked_tomes.append("tome_vitality_01")
	TomeManager.equip(GameState.lexicon, "tome_vitality_01")

	var scene := await _spawn(host, DUNGEON_SCENE) as DungeonScene
	var player_state: Dictionary = GameState.current_run.player_state
	assert_eq(int(player_state.max_hp), 125, "the equipped tome raised max HP at run start")
	assert_eq(int(player_state.current_hp), 125, "and the player starts at full health")
	assert_true(player_state.has("loadout"), "the loadout is on the run's player_state")
	assert_true(scene.get_node("UI/MarginContainer/VBoxContainer/SubtitleLabel").text.contains("125"), "the HUD shows the boosted HP")

	var encounters := _clear_dungeon(scene)
	assert_gt(float(encounters), 0.0, "the dungeon took at least one encounter")
	assert_eq(String(GameState.current_run.run_status), "completed", "clearing the grid completes the run")
	assert_true(scene._is_input_locked, "input stays locked after the run ends")

	var summary: Dictionary = GameState.current_run.settlement
	var tally: Dictionary = GameState.current_run.tally
	assert_gt(float(tally.letters_solved), 0.0, "letters were tallied from real solve events")
	assert_gt(float(tally.words_solved), 0.0, "words were tallied")
	assert_eq(int(tally.enemies_defeated), encounters, "enemies defeated matches the fights won")
	assert_eq(int(summary.ink.base), int(player_state.total_ink_drops_this_run), "the settled haul is what the run collected")
	var per_letter := int(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).ink_economy.ink_per_letter)
	assert_gt(float(summary.ink.base), float(int(tally.letters_solved) * per_letter) - 1.0, "that haul covers every solved letter's Ink")
	assert_true(bool(summary.completed), "the summary says the run was won")
	assert_gt(float(summary.ink.completion_bonus), 0.0, "a win earns the completion bonus")
	assert_eq(int(GameState.player_profile.total_runs), 1, "the run is on the profile exactly once")
	assert_eq(int(GameState.player_profile.runs_completed), 1, "as a win")
	assert_gt(float(GameState.player_profile.ink_drops), 0.0, "and the Ink is banked")

	assert_true(FileAccess.file_exists(SAVE_FILE), "the run end saved the game")
	var on_disk = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	assert_eq(int(on_disk.player_profile.total_runs), 1, "the save holds the finished run")
	assert_eq(int(on_disk.player_profile.ink_drops), int(GameState.player_profile.ink_drops), "and the banked Ink")

	var panels := scene.get_node("UI").get_children().filter(func(child): return child is RunSummaryPanel)
	assert_eq(panels.size(), 1, "exactly one summary panel is on screen")
	await host.get_tree().process_frame
	assert_lt(_tallest_label(panels[0]), 150.0, "no summary label is squeezed into a one-character-wide column")
	var card := _first_of_type(panels[0], "PanelContainer") as PanelContainer
	assert_true(card != null, "the summary has a card")
	if card != null:
		var centre_x := card.global_position.x + card.size.x / 2.0
		assert_between(centre_x, VIEWPORT_SIZE.x / 2.0 - 20.0, VIEWPORT_SIZE.x / 2.0 + 20.0, "the summary card is centred on screen, not stuck to the left edge")
	assert_gt(float(_buttons(scene, "Return to the Lexicon").size()), 0.0, "it offers the way back to the Lexicon")
	assert_gt(float(_buttons(scene, "Delve Again").size()), 0.0, "and a way to go again")

	# Settling twice must be impossible.
	var runs_before := int(GameState.player_profile.total_runs)
	scene._end_run(true)
	scene._end_run(false)
	assert_eq(int(GameState.player_profile.total_runs), runs_before, "a finished run cannot be settled again")

	await _despawn(host, scene)

func _test_defeat_settles(host: Node) -> void:
	_fresh_game(0, "2999-01-01")
	var scene := await _spawn(host, DUNGEON_SCENE) as DungeonScene
	# Win one fight, then die in the next.
	var first_cell: Dictionary = {}
	for cell in GameState.current_run.grid_state.cells:
		if cell.type == "letter" and not bool(cell.solved):
			first_cell = cell
			break
	scene._on_combat_finished({
		"victory": true, "player_defeated": false, "cell": Vector2i(int(first_cell.x), int(first_cell.y)),
		"clue_id": first_cell.clue_id, "enemy_id": "enemy_test", "answer": ClueDatabase.get_clue(first_cell.clue_id).answer,
		"attempts_used": 1, "damage_dealt": 10, "damage_taken": 0,
	})
	var collected := int(GameState.current_run.player_state.total_ink_drops_this_run)
	assert_gt(float(collected), 0.0, "setup: the player collected some Ink")
	assert_eq(String(GameState.current_run.run_status), "in_progress", "setup: the run is still going")

	scene._on_combat_finished({
		"victory": false, "player_defeated": true, "cell": Vector2i.ZERO, "clue_id": "x",
		"enemy_id": "enemy_test", "answer": "", "attempts_used": 3, "damage_dealt": 0, "damage_taken": 100,
	})
	assert_eq(String(GameState.current_run.run_status), "failed", "dying fails the run")
	var summary: Dictionary = GameState.current_run.settlement
	var retention := float(ConfigLoader.load_json(Constants.GAME_CONFIG_PATH).ink_economy.defeat_retention)
	assert_false(bool(summary.completed), "the summary says the run was lost")
	assert_eq(int(summary.ink.total), int(floor(collected * retention)), "dying keeps only the retained share of the haul")
	assert_eq(int(GameState.statistics.total_deaths), 1, "the death is recorded")
	assert_eq(int(GameState.player_profile.runs_completed), 0, "and it is not a win")
	assert_true(scene._is_input_locked, "input is locked after dying")
	await _despawn(host, scene)

func _test_grid_size_option(host: Node) -> void:
	# A high-level player can pick 7x7; the option is consumed by the run.
	_fresh_game(PlayerLevel.ink_for_level(6), "2999-01-01")
	GameState.run_options = {"grid_size": 7}
	var scene := await _spawn(host, DUNGEON_SCENE) as DungeonScene
	assert_eq(int(GameState.current_run.grid_size), 7, "an unlocked grid size is honoured")
	assert_true(GameState.run_options.is_empty(), "and the option is consumed")
	await _despawn(host, scene)

	# A level-1 player asking for 9x9 gets the default instead.
	_fresh_game(0, "2999-01-01")
	GameState.run_options = {"grid_size": 9}
	var capped := await _spawn(host, DUNGEON_SCENE) as DungeonScene
	assert_eq(int(GameState.current_run.grid_size), 5, "a locked grid size falls back to the default")
	await _despawn(host, capped)
