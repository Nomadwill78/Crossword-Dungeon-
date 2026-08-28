## Visual grid: cell colors by state, letters, entrance/exit markers,
## reachability highlight overlay, and a simple player token. Custom-drawn
## (no per-cell nodes) so it stays cheap even at 9x9.
class_name GridRenderer
extends Node2D

var _grid_state: Dictionary = {}
var _player_grid_pos: Vector2i = Vector2i.ZERO
var _highlighted: Array = []

func initialize(grid_state: Dictionary) -> void:
	_grid_state = grid_state
	var entrance: Dictionary = grid_state.get("entrance", {"x": 0, "y": 0})
	_player_grid_pos = Vector2i(int(entrance.x), int(entrance.y))
	queue_redraw()

func move_player_to(pos: Vector2i) -> void:
	_player_grid_pos = pos
	queue_redraw()

## Any single-cell update just triggers a full redraw — cheap at this grid
## size, and correct even when solving a word reveals several cells at once.
func update_cell(_pos: Vector2i) -> void:
	queue_redraw()

func highlight_reachable_cells(cells: Array) -> void:
	_highlighted = cells
	queue_redraw()

func clear_highlights() -> void:
	_highlighted = []
	queue_redraw()

func _draw() -> void:
	if _grid_state.is_empty():
		return

	var px := Constants.CELL_PIXEL_SIZE
	var highlight_set: Dictionary = {}
	for h in _highlighted:
		highlight_set[h] = true

	for cell in _grid_state.get("cells", []):
		var x := int(cell.x)
		var y := int(cell.y)
		var rect := Rect2(Vector2(x * px, y * px), Vector2(px, px))
		var type: String = cell.type

		var color := Constants.COLOR_BLACK_CELL
		if type == "letter":
			color = Constants.COLOR_SOLVED_LETTER if bool(cell.solved) else Constants.COLOR_UNSOLVED_LETTER
		elif type == "entrance":
			color = Constants.COLOR_ENTRANCE
		elif type == "exit":
			color = Constants.COLOR_EXIT

		draw_rect(rect, color, true)
		draw_rect(rect, Constants.COLOR_GRID_LINE, false, 2.0)

		if highlight_set.has(Vector2i(x, y)):
			draw_rect(rect, Constants.COLOR_HIGHLIGHT, true)

		var label := ""
		var solved := bool(cell.get("solved", false))
		if type == "letter":
			label = String(cell.letter) if solved else "?"
		elif type in ["entrance", "exit"] and String(cell.get("letter", "")) != "":
			label = String(cell.letter)

		if label != "":
			var font := ThemeDB.fallback_font
			var font_size := ThemeDB.fallback_font_size + 8
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos := Vector2(
				x * px + (px - text_size.x) / 2.0,
				y * px + (px + text_size.y * 0.7) / 2.0
			)
			var text_color := Color.BLACK if (type == "letter" and solved) else Color.WHITE
			draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

	var center := Vector2(_player_grid_pos.x * px + px / 2.0, _player_grid_pos.y * px + px / 2.0)
	draw_circle(center, px * 0.3, Constants.COLOR_PLAYER)
