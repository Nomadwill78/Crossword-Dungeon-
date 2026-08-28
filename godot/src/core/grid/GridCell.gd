## Typed cell data for one grid tile, with Dictionary (de)serialization since
## grid_state is passed around as plain Dictionaries everywhere else
## (DungeonScene, tests, the bot) for easy JSON-style access.
class_name GridCell
extends RefCounted

var x: int
var y: int
var type: int
var letter: String = ""
var solved: bool = false
var enemy_id: String = ""
var clue_id: String = ""
var bonus = null
var bonus_claimed: bool = false

func _init(p_x: int = 0, p_y: int = 0, p_type: int = Constants.CellType.BLACK) -> void:
	x = p_x
	y = p_y
	type = p_type

func to_dict() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"type": Constants.cell_type_to_string(type),
		"letter": letter,
		"solved": solved,
		"enemy_id": enemy_id,
		"clue_id": clue_id,
		"bonus": bonus,
		"bonus_claimed": bonus_claimed,
	}

static func from_dict(d: Dictionary) -> GridCell:
	var cell := GridCell.new(
		int(d.get("x", 0)),
		int(d.get("y", 0)),
		Constants.cell_type_from_string(d.get("type", "black"))
	)
	cell.letter = d.get("letter", "")
	cell.solved = bool(d.get("solved", false))
	cell.enemy_id = d.get("enemy_id", "")
	cell.clue_id = d.get("clue_id", "")
	cell.bonus = d.get("bonus", null)
	cell.bonus_claimed = bool(d.get("bonus_claimed", false))
	return cell
