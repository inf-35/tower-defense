extends Unit
class_name Tower

@export var type: Towers.Type

var tower_position: Vector2i = Vector2i.ZERO:
	set(new_pos):
		tower_position = new_pos
		movement_component.position = Island.cell_to_position(tower_position)
