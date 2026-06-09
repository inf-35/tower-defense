extends Node2D
class_name RangeIndicator

#--- configuration ---
@export var highlight_color: Color = Color(1.0, 0.987, 0.61, 0.412)
@export var positive_highlight_color: Color = Color(0.35, 1.0, 0.45, 0.48)
@export var negative_highlight_color: Color = Color(1.0, 0.2, 0.2, 0.48)
@export var range_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var attack_area_color: Color = Color(1.0, 0.57, 0.57, 0.412)
@export var margin: int = 2
@export var line_width: float = 1.0

var _current_tower: Tower

func _ready() -> void:
	z_index = Layers.INWORLD_UI
	z_as_relative = false

func select(tower: Tower) -> void:
	_on_tower_selected(tower)

func _on_tower_selected(tower: Tower) -> void:
	_current_tower = tower
	queue_redraw()

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_current_tower):
		return

	if _current_tower.behavior:
		_current_tower.behavior.draw_visuals(self)

func draw_cell(cell: Vector2i, color: Color) -> void:
	var _margin: int = 2
	var cell_size := Island.CELL_SIZE - _margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	var rect: Rect2 = Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
	draw_rect(rect, color, false, 1.0)
