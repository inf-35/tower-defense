extends Node

var tower_type: Towers.Type
var tower_facing: Tower.Facing
var is_valid: bool
var tower_position: Vector2i

@onready var current_preview: TowerPreview = References.tower_preview

signal click_on_island(world_position: Vector2, tower_type: Towers.Type, tower_facing: Tower.Facing)

func _ready():
	UI.tower_selected.connect(_on_tower_selected)

# --- In _on_tower_selected(type_id) ---
func _on_tower_selected(type_id: Towers.Type):
	tower_type = type_id
	References.tower_preview.setup(tower_type)

# --- In _process(_delta) ---
#func _process(_delta):
	#if not is_instance_valid(current_preview):
		#return
		#
	#var mouse_pos = get_global_mouse_position()
	#var cell = Island.position_to_cell(mouse_pos)
	#current_preview.global_position = Island.cell_to_position(cell)
	#
	## Check for validity
	#var is_valid = Player.has_blueprint(tower_type) and \
				   #Player.flux >= Towers.tower_stats[tower_type].flux_cost and \
				   #not References.island.occupied_grid[cell] and \
				   #Towers.tower_stats[tower_type].construct <= References.island.get_terrain_level(cell)
				   #
	## Update the preview's visuals every frame
	#current_preview.update_visuals(is_valid, current_rotation)


# --- In _unhandled_input(event) ---
func _unhandled_input(event: InputEvent) -> void:
	# Rotation input is simpler: just update the direction vector.
	# The _process loop will handle applying the visual rotation.
	var world_camera_position: Vector2 = References.camera.get_global_mouse_position()
	
	if event is InputEventMouseMotion and is_instance_valid(current_preview):
		tower_position = Island.position_to_cell(world_camera_position)
		is_valid = Player.has_blueprint(tower_type) and \
							Player.flux >= Towers.tower_stats[tower_type].flux_cost and \
							not References.island.is_occupied(tower_position) and \
							Towers.tower_stats[tower_type].construct <= References.island.get_terrain_level(tower_position)

		current_preview.update_visuals(is_valid, tower_facing, tower_position)

	if is_instance_valid(current_preview) and event.is_action_pressed("rotate_preview"):
		# Rotate the direction vector counter-clockwise
		tower_facing = (tower_facing + 1) % 4
		current_preview.update_visuals(is_valid, tower_facing, tower_position)

	# The rest of the input handling (left/right click) remains identical.
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		# Check for left-button press
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			click_on_island.emit(world_camera_position, tower_type, tower_facing)
		# ... (same as before)
