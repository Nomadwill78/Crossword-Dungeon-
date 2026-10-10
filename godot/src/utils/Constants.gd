## Global enums, paths, and display constants. Not an autoload — every
## member is static/const so other scripts reference it as `Constants.X`
## without needing an instance.
class_name Constants
extends RefCounted

enum CellType { BLACK, LETTER, ENTRANCE, EXIT }
enum Direction { ACROSS, DOWN }

const GAME_CONFIG_PATH := "res://data/config/game_config.json"
const GRID_PRESETS_PATH := "res://data/config/grid_presets.json"
const CLUES_PATH := "res://data/clues/clues_master.json"
const ENEMIES_PATH := "res://data/enemies/enemies_master.json"
const DICTIONARY_PATH := "res://data/dictionaries/words_en.json"
const VOCABULARY_TREES_PATH := "res://data/lexicon/vocabulary_trees.json"
const TOMES_PATH := "res://data/lexicon/tomes.json"
const ACHIEVEMENTS_PATH := "res://data/lexicon/achievements.json"
const BOSS_ROUNDS_PATH := "res://data/enemies/boss_rounds.json"
const ABILITY_RULES_PATH := "res://data/enemies/ability_rules.json"

const SAVE_PATH := "user://save_data.json"
const BACKUP_DIR := "user://backups/"

const CELL_PIXEL_SIZE := 64

const COLOR_BLACK_CELL := Color(0.08, 0.07, 0.1)
const COLOR_UNSOLVED_LETTER := Color(0.28, 0.24, 0.34)
const COLOR_SOLVED_LETTER := Color(0.72, 0.64, 0.42)
const COLOR_ENTRANCE := Color(0.35, 0.65, 0.4)
const COLOR_EXIT := Color(0.7, 0.28, 0.3)
const COLOR_HIGHLIGHT := Color(0.9, 0.85, 0.4, 0.35)
const COLOR_PLAYER := Color(0.95, 0.95, 1.0)
const COLOR_GRID_LINE := Color(0.15, 0.13, 0.18)

const CATEGORIES := [
	"FANTASY_CREATURES",
	"MAGIC_ARCANE",
	"WEAPONS_ARMOR",
	"DUNGEON_PLACES",
	"NATURE_ELEMENTS",
	"EMOTIONS_ABSTRACT",
	"GAME_JARGON",
]

static func cell_type_to_string(type: int) -> String:
	match type:
		CellType.BLACK:
			return "black"
		CellType.LETTER:
			return "letter"
		CellType.ENTRANCE:
			return "entrance"
		CellType.EXIT:
			return "exit"
	return "unknown"

static func cell_type_from_string(s: String) -> int:
	match s:
		"black":
			return CellType.BLACK
		"letter":
			return CellType.LETTER
		"entrance":
			return CellType.ENTRANCE
		"exit":
			return CellType.EXIT
	return CellType.BLACK
