extends Node

var tower_type: Towers.Type
signal click_on_island(world_position: Vector2, tower_type: Towers.Type)

func _ready():
	UI.tower_selected.connect(func(type_id: Towers.Type): tower_type = type_id)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		# Check for left-button press
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var world_position: Vector2 = References.camera.get_global_mouse_position()
			click_on_island.emit(world_position, tower_type)
