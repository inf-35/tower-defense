extends Node

# --- State Management ---
enum State { IDLE, PREVIEWING, TOWER_SELECTED }
var current_state: State = State.IDLE

# --- Properties ---
var enabled: bool = false
var selected_tower: Tower       # the tower instance currently selected on the map
var preview_tower_prototype: Tower   # the tower type being previewed for building
var preview_tower_position: Vector2i
var preview_tower_facing: Tower.Facing
var preview_is_valid: bool
# --- new state variable for managing "ghost" units for inspection
var _ghost_unit_for_inspection: Unit = null

var current_preview: TowerPreview

signal tower_was_selected(tower: Tower)
signal tower_was_deselected()

func start():
	# Connect to UI signal for when the player picks a tower from the build bar.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	current_preview = References.tower_preview
	enabled = true
	
	await References.references_ready
	
	UI.tower_selected.connect(_on_build_tower_selected, CONNECT_REFERENCE_COUNTED)
	UI.update_flux.connect(func(_flux: float): _update_preview_visuals(), CONNECT_REFERENCE_COUNTED)
	UI.update_capacity.connect(func(_used: float, _total: float): _update_preview_visuals(), CONNECT_REFERENCE_COUNTED)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	match current_state:
		State.IDLE:
			_handle_idle_input(event)
		State.PREVIEWING:
			_handle_preview_input(event)
		State.TOWER_SELECTED:
			_handle_tower_selected_input(event)

	# Rotation can be handled universally if a preview is active
	if current_state == State.PREVIEWING and event.is_action_pressed("rotate_preview"):
		preview_tower_facing = (preview_tower_facing + 1) % Tower.Facing.size() as Tower.Facing
		_update_preview_visuals()

func _enter_idle_state():
	# Deselect any tower and hide any preview.
	if is_instance_valid(selected_tower):
		selected_tower = null
		tower_was_deselected.emit()
	
	# CRITICAL: ensure the ghost unit is destroyed when leaving a selection state
	if is_instance_valid(_ghost_unit_for_inspection):
		_ghost_unit_for_inspection.free()
		_ghost_unit_for_inspection = null
		
	if is_instance_valid(preview_tower_prototype):
		Towers.reset_tower_prototype(preview_tower_prototype.type)
		
	if is_instance_valid(References.path_renderer):
		References.path_renderer.clear_preview()
	
	if is_instance_valid(current_preview):
		current_preview.hide()
	
	current_state = State.IDLE

func _enter_preview_state(tower: Tower):
	# If a tower was selected (or previewed), deselect it first.
	if current_state == State.TOWER_SELECTED or current_state == State.PREVIEWING:
		_enter_idle_state() # Reset to a clean state first

	current_state = State.PREVIEWING
	preview_tower_prototype = tower
	preview_tower_prototype.visible = false
	preview_tower_prototype.modulate = Color(1,1,1,0.6)
	current_preview.setup(preview_tower_prototype.type)
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

# --- Input Handlers (Called by _unhandled_input) ---

func _handle_idle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# The only thing we can do in the IDLE state is select a tower.
		var mouse_pos : Vector2 = References.camera.get_global_mouse_position()
		var cell_pos : Vector2i = Island.position_to_cell(mouse_pos)
		
		# check for a previewed feature from the ExpansionService
		var preview_data: Terrain.CellData = ExpansionService.get_preview_data_at_cell(cell_pos)
		if is_instance_valid(preview_data) and preview_data.feature != Towers.Type.VOID:
			# preview found! create a temporary "ghost" unit for inspection.
			_create_and_inspect_ghost_unit(preview_data, cell_pos)
			return # stop further processing
		
		if References.island.tower_grid.has(cell_pos):
			var clicked_tower: Tower = References.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)
		#else do nothing

func _handle_preview_input(event: InputEvent) -> void:
	# handle mouse motion to update the preview visuals
	if event is InputEventMouseMotion:
		_update_preview_visuals()

	# handle clicks to place or cancel
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			# If the placement is valid, emit the request.
			if preview_is_valid:
				# Use the last known valid position for the request.
				UI.place_tower_requested.emit(preview_tower_prototype.type, preview_tower_position, preview_tower_facing)
				#we don't transition back to idle. this allows the player to build multiple towers at once
				#this switches the inspector to the newly built tower (line below)
				if References.island.tower_grid.has(preview_tower_position):
					UI.update_inspector_bar.emit(References.island.tower_grid[preview_tower_position])

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click cancels the preview.
			_enter_idle_state()

func _handle_tower_selected_input(event: InputEvent) -> void:
	# Any click while a tower is selected will deselect it.
	if event is InputEventMouseButton and event.is_pressed():
		var cell_pos : Vector2i = Island.position_to_cell(References.camera.get_global_mouse_position())
		
		# check for previews first
		var preview_data: Terrain.CellData = ExpansionService.get_preview_data_at_cell(cell_pos)
		if is_instance_valid(preview_data) and preview_data.feature != Towers.Type.VOID:
			_create_and_inspect_ghost_unit(preview_data, cell_pos)
			return
		
		if References.island.tower_grid.has(cell_pos): #seamlessly switches between towers
			var clicked_tower = References.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)
		else: #otherwise transition to idle
			_enter_idle_state()

# --- Helper Functions ---
func _update_preview_visuals():
	if not preview_tower_prototype:
		return
		
	if current_state != State.PREVIEWING:
		return
	
	var mouse_pos : Vector2 = References.camera.get_global_mouse_position()
	var base_size: Vector2i = Towers.get_tower_size(preview_tower_prototype.type)
	var effective_size: Vector2i = base_size
	if int(preview_tower_facing) % 2 != 0:
		effective_size = Vector2i(base_size.y, base_size.x)
	var center_offset: Vector2i = effective_size * 0.5
	preview_tower_position = Island.position_to_cell(mouse_pos) - center_offset
	
	if preview_tower_position != preview_tower_prototype.tower_position or preview_tower_facing != preview_tower_prototype.facing:
		preview_tower_prototype.tower_position = preview_tower_position
		preview_tower_prototype.facing = preview_tower_facing
		
		var occupied_cells: Array[Vector2i] = []
		var size := preview_tower_prototype.size
			
		for x in range(size.x):
			for y in range(size.y):
				occupied_cells.append(preview_tower_position + Vector2i(x, y))

		# 2. Send to Renderer
		if is_instance_valid(References.path_renderer):
			References.path_renderer.update_preview(occupied_cells)

	preview_is_valid = TerrainService.is_area_constructable(References.island, preview_tower_facing, preview_tower_position, preview_tower_prototype.type, true)

	current_preview.update_visuals(preview_is_valid, preview_tower_facing, preview_tower_position)
	
# new helper to create and manage the temporary inspection unit
func _create_and_inspect_ghost_unit(cell_data: Terrain.CellData, cell_pos: Vector2i) -> void: ##for terrain preview!
	# first, clean up any previous state
	_enter_idle_state()
	
	# create the temporary tower instance
	_ghost_unit_for_inspection = Towers.create_tower(cell_data.feature)
	if not is_instance_valid(_ghost_unit_for_inspection):
		return # failed to create
		
	# configure the ghost unit
	_ghost_unit_for_inspection.abstractive = true # IMPORTANT: prevents it from interacting with gameplay
	_ghost_unit_for_inspection.visible = false
	_ghost_unit_for_inspection.tower_position = cell_pos
	print("Ghost unit: ", cell_pos)
	# pass the preview's initial state data to the ghost unit so its behavior is configured correctly
	if not cell_data.initial_state.is_empty():
		_ghost_unit_for_inspection.set_initial_behaviour_state(cell_data.initial_state)
	
	# add it to the scene tree so it's a valid node
	add_child(_ghost_unit_for_inspection)
	
	# transition to the TOWER_SELECTED state using the ghost unit
	# we don't call the full _enter_tower_selected_state because we don't want to
	# clear the ghost; we just set the state and tell the inspector to update.
	current_state = State.TOWER_SELECTED
	selected_tower = _ghost_unit_for_inspection
	tower_was_selected.emit(selected_tower)
	UI.update_inspector_bar.emit(selected_tower)

# --- Signal Connections ---
func _on_build_tower_selected(tower: Tower):
	# The UI is requesting to start building a tower.
	_enter_preview_state(tower)
