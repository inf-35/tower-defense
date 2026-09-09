extends Node2D
class_name ObstructionWarningRenderer

@export var warning_texture: Texture2D ##texture stamped at the centre of each obstructed tile
@export var intermediate_warning_texture: Texture2D ##texture used when only wall-ignoring enemy routes cross the tile
@export var warning_texture_scale: Vector2 = Vector2(0.08, 0.08) ##world-space scale applied to the source texture
@export_range(0.0, 1.0, 0.01) var intermediate_warning_alpha: float = 0.5 ##opacity applied only to wall-ignoring-route warnings

var _primary_warning_cells: Array[Vector2i] = []
var _intermediate_warning_cells: Array[Vector2i] = []

func set_warning_cells(primary_cells: Array[Vector2i], intermediate_cells: Array[Vector2i]) -> void: ##replaces both warning tiers and redraws only when either tier changes
	if _primary_warning_cells == primary_cells and _intermediate_warning_cells == intermediate_cells:
		return

	_primary_warning_cells.assign(primary_cells)
	_intermediate_warning_cells.assign(intermediate_cells)
	queue_redraw()

func _draw() -> void: ##draws both warning tiers through the same canvas item
	_draw_warning_cells(_intermediate_warning_cells, intermediate_warning_texture, Color(1.0, 1.0, 1.0, intermediate_warning_alpha))
	_draw_warning_cells(_primary_warning_cells, warning_texture)

func _draw_warning_cells(cells: Array[Vector2i], texture: Texture2D, modulate: Color = Color.WHITE) -> void: ##stamps one texture at the centre of every cell in a warning tier
	if texture == null:
		return

	var texture_size: Vector2 = Vector2(texture.get_size()) * warning_texture_scale
	var texture_offset: Vector2 = texture_size * -0.5
	for cell: Vector2i in cells:
		var warning_rect := Rect2(Island.cell_to_position(cell) + texture_offset, texture_size)
		draw_texture_rect(texture, warning_rect, false, modulate)
