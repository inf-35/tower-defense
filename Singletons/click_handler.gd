extends Node

# --- State Management ---
enum State { IDLE, PREVIEWING, TOWER_SELECTED }
var current_state: State = State.IDLE

# --- Properties ---
var selected_tower: Tower       # The tower instance currently selected on the map.
var preview_tower_type: Towers.Type   # The tower type being previewed for building.
var preview_tower_facing: Tower.Facing
var preview_is_valid: bool
var preview_tower_position: Vector2i

@onready var current_preview: TowerPreview = References.tower_preview

signal tower_was_selected(tower: Tower)
signal tower_was_deselected()

# --- Engine Callbacks ---
func _ready():
	# Connect to UI signal for when the player picks a tower from the build bar.
	UI.tower_selected.connect(_on_build_tower_selected)

func _unhandled_input(event: InputEvent) -> void:
	# This function now acts as a simple dispatcher, sending input
	# to the correct handler based on our current state.
	match current_state:
		State.IDLE:
			_handle_idle_input(event)
		State.PREVIEWING:
			_handle_preview_input(event)
		State.TOWER_SELECTED:
			_handle_tower_selected_input(event)
			
	# Rotation can be handled universally if a preview is active
	if current_state == State.PREVIEWING and event.is_action_pressed("rotate_preview"):
		preview_tower_facing = (preview_tower_facing + 1) % 4
		_update_preview_visuals()

# --- State Transition Functions ---

func _enter_idle_state():
	# Deselect any tower and hide any preview.
	if is_instance_valid(selected_tower):
		selected_tower = null
		tower_was_deselected.emit()
	
	if is_instance_valid(current_preview):
		current_preview.hide()
	
	current_state = State.IDLE

func _enter_preview_state(type_id: Towers.Type):
	# If a tower was selected, deselect it first.
	if current_state == State.TOWER_SELECTED:
		_enter_idle_state() # Reset to a clean state first

	current_state = State.PREVIEWING
	preview_tower_type = type_id
	current_preview.setup(preview_tower_type)
	current_preview.show()
	# Trigger an immediate update of the preview at the current mouse position.
	_update_preview_visuals()

func _enter_tower_selected_state(tower: Tower):
	# If we were previewing, cancel it.
	if current_state == State.PREVIEWING:
		_enter_idle_state() # Reset to a clean state first

	current_state = State.TOWER_SELECTED
	selected_tower = tower
	tower_was_selected.emit(selected_tower)
	UI.update_inspector_bar.emit(selected_tower)
	print(selected_tower, " select tower")

# --- Input Handlers (Called by _unhandled_input) ---

func _handle_idle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# The only thing we can do in the IDLE state is select a tower.
		var mouse_pos : Vector2 = References.camera.get_global_mouse_position()
		var cell_pos : Vector2i = Island.position_to_cell(mouse_pos)
		
		if References.island.tower_grid.has(cell_pos):
			var clicked_tower = References.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)

func _handle_preview_input(event: InputEvent) -> void:
	# Handle mouse motion to update the preview visuals.
	if event is InputEventMouseMotion:
		_update_preview_visuals()

	# Handle clicks to place or cancel.
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			# If the placement is valid, emit the request.
			if preview_is_valid:
				# Use the last known valid position for the request.
				UI.place_tower_requested.emit(preview_tower_type, preview_tower_position, preview_tower_facing)
				#we don't transition back to idle. this allows the player to build multiple towers at once
				UI.update_inspector_bar.emit(References.island.tower_grid[preview_tower_position])
				#this switches the inspector to the newly built tower
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click cancels the preview.
			_enter_idle_state()

func _handle_tower_selected_input(event: InputEvent) -> void:
	# Any click while a tower is selected will deselect it.
	if event is InputEventMouseButton and event.is_pressed():
		var cell_pos : Vector2i = Island.position_to_cell(References.camera.get_global_mouse_position())
		if References.island.tower_grid.has(cell_pos): #seamlessly switches between towers
			var clicked_tower = References.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)
		else: #otherwise transition to idle
			_enter_idle_state()

# --- Helper Functions ---

func _update_preview_visuals():
	# This function centralizes the logic for updating the preview.
	var mouse_pos : Vector2 = References.camera.get_global_mouse_position()
	preview_tower_position = Island.position_to_cell(mouse_pos)

	preview_is_valid = Player.has_capacity(preview_tower_type) and \
		Player.flux >= Towers.get_tower_cost(preview_tower_type) and \
		(not References.island.is_occupied(preview_tower_position) or References.island.tower_grid[preview_tower_position].type == preview_tower_type) and \
		Towers.get_tower_minimum_terrain(preview_tower_type) <= References.island.get_terrain_level(preview_tower_position)

	current_preview.update_visuals(preview_is_valid, preview_tower_facing, preview_tower_position)

# --- Signal Connections ---

func _on_build_tower_selected(type_id: Towers.Type):
	# The UI is requesting to start building a tower.
	_enter_preview_state(type_id)
