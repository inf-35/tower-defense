# expansion_service.gd (Autoload Singleton)
extends Node

signal expansion_process_complete

#configuration
const OVERVIEW_ISLAND_OFFSET: float = 0.0 #determines how offset the island is from the centre of the screen during overviews
#expansion state
# --- state machine ---
enum State { IDLE, CHOOSING, CONFIRMING }
var _current_state: State = State.IDLE
var _choices_by_id: Dictionary[int, ExpansionChoice] = {}
var _hovered_choice_id: int = -1 # -1 means no choice is hovered
var _pending_choice_id: int = -1 # the choice waiting for confirmation

var STANDARD_EXPANSION_PARAMS: GenerationParameters = GenerationParameters.new({
	&"ruins_chance" : 0.08,
	&"breach_seed_duration": 2,
	&"spawn_breach": true,
})

class GenerationParameters:
	# --- terrain composition rules ---
	var ruins_chance: float = 0.1
	# --- feature spawning rules ---
	var spawn_breach: bool = true
	# --- feature state rules ---
	# this will be used to populate the 'initial_state' packet for generated towers
	var breach_seed_duration: int = 2
	
	func _init(params: Dictionary = {}):
		for parameter in params:
			if parameter in self:
				self[parameter] = params[parameter]

func _ready():
	set_process(false)
	
	UI.choice_hovered.connect(_on_choice_hovered)
	UI.choice_unhovered.connect(_on_choice_unhovered)
	# the first click on an option triggers a preview, not a selection
	UI.choice_focused.connect(_on_expansion_option_clicked)
	# the confirmation button press triggers the final selection
	UI.choice_selected.connect(_on_expansion_confirmed)

#helper function for creating the initial island
func generate_initial_island_block(island: Island, block_size: int) -> Dictionary:
	# --- EDITED SECTION START ---
	# for the very first block, we create a custom ruleset in code
	var initial_params := GenerationParameters.new()
	initial_params.ruins_chance = 0.05 # lower chance of ruins at the start
	initial_params.spawn_breach = true
	# the key requirement: the initial breach is already active
	initial_params.breach_seed_duration = 0
	
	return _generate_block(island, block_size, initial_params)

# the main public API called by Phases.gd
func generate_and_present_choices(island: Island, block_size: int, choice_count: int) -> void:
	_choices_by_id.clear()
	_hovered_choice_id = -1
	_pending_choice_id = -1
	_current_state = State.CHOOSING #set initial state
	
	var options: Array[ExpansionChoice] = []
	for i: int in range(choice_count):
		# generate the block data, which may now include a breach seed
		var block_data: Dictionary = _generate_block(island, block_size, STANDARD_EXPANSION_PARAMS)
		if block_data.is_empty():
			continue
			
		var choice := ExpansionChoice.new(i, block_data)
		options.append(choice)
		_choices_by_id[i] = choice # store for easy lookup

	if options.is_empty():
		push_warning("ExpansionService: All generated options were empty. Skipping.")
		expansion_process_complete.emit() # must emit to unblock the phase manager
		return

	island.update_previews(_choices_by_id)
	UI.display_expansion_choices.emit(options) #now await choice_focused -> _on_expansion_option_clicked
	_trigger_camera_overview(island) #initial overview of all choices

# applies the chosen expansion, called by PhaseManager
func select_expansion(island: Island, choice_id: int) -> void:
	if not _choices_by_id.has(choice_id):
		expansion_process_complete.emit()
		return

	var chosen_option: ExpansionChoice = _choices_by_id[choice_id]
	TerrainService.expand_island(island, chosen_option.block_data)
	
	_clear_expansion_state(island)
	expansion_process_complete.emit()
	UI.hide_expansion_choices.emit()
	UI.hide_expansion_confirmation.emit()
	
# called when the UI emits that a choice button is being hovered
func _on_choice_hovered(choice_id: int) -> void:
	if _current_state != State.CHOOSING:
		return
	_hovered_choice_id = choice_id
	# command the island to update its visual highlighting
	References.island.set_highlighted_choice(choice_id)

# called when the UI emits that the mouse has left a choice button
func _on_choice_unhovered(_choice_id: int) -> void:
	if _current_state != State.CHOOSING:
		return
	_hovered_choice_id = -1
	References.island.set_highlighted_choice(-1)

# called when the player clicks an expansion option for the first time
func _on_expansion_option_clicked(choice_id: int) -> void:
	# this action is only valid when in the main choosing states
	if _current_state != State.CHOOSING and _current_state != State.CONFIRMING:
		return

	_current_state = State.CONFIRMING
	_pending_choice_id = choice_id
	
	# highlight the selected choice and focus the camera on it
	References.island.set_highlighted_choice(choice_id)
	_trigger_camera_focus_on_choice(References.island, choice_id)
	
	# command the UI to show the confirmation button
	UI.display_expansion_confirmation.emit(choice_id) #now await _on_expansion_confirmed()

# called when the player clicks the separate "confirm" button
func _on_expansion_confirmed(_choice_id: int) -> void:
	# this action is only valid when we are waiting for a confirmation
	if _current_state != State.CONFIRMING:
		return
		
	# execute the selection using the stored pending choice ID
	select_expansion(References.island, _pending_choice_id)
	
func _clear_expansion_state(island: Island) -> void:
	_current_state = State.IDLE
	_choices_by_id.clear()
	_hovered_choice_id = -1
	island.update_previews({}) # clear all previews from the island
	
	var camera: Camera = References.camera
	camera.release_override()

# procedural generation logic
func _generate_block(island: Island, block_size: int, params: GenerationParameters) -> Dictionary[Vector2i, Terrain.CellData]:
	var block_data: Dictionary[Vector2i, Terrain.CellData] = {}
	
	var start_pos: Vector2i = Vector2i.ZERO if island.shore_boundary_tiles.is_empty() else island.shore_boundary_tiles.pick_random()
	var to_visit: Array[Vector2i] = [start_pos]
	var visited: Dictionary[Vector2i, bool] = {}
	var generated_coords: Array[Vector2i] = []

	# this is a simplified breadth-first search to find adjacent sea tiles
	while not to_visit.is_empty() and generated_coords.size() < block_size:
		var cell: Vector2i = to_visit.pop_front()
		if visited.has(cell):
			continue
		visited[cell] = true
		
		# only sea tiles can be converted to land
		if island.terrain_base_grid.get(cell) == null: # a proxy for being SEA
			generated_coords.append(cell)

		for dir: Vector2i in island.DIRS:
			var neighbor: Vector2i = cell + dir
			if not visited.has(neighbor):
				to_visit.append(neighbor)
	
	if generated_coords.is_empty():
		return {}
	# assign terrain base to the chosen coordinates
	for coord: Vector2i in generated_coords:
		block_data[coord] = Terrain.CellData.new(Terrain.Base.EARTH, Towers.Type.VOID)
		
		var base: Terrain.Base = Terrain.Base.EARTH if randf() > params.ruins_chance else Terrain.Base.RUINS
		block_data[coord].terrain = base

	# --- Breach Spawning Logic ---
	# find a suitable edge tile on the *newly generated* block to place the seed
	var potential_breach_locations: Array[Vector2i] = []
	for coord: Vector2i in generated_coords:
		for dir: Vector2i in island.DIRS:
			var neighbor: Vector2i = coord + dir
			# an edge tile is one that is adjacent to a tile not in our new block
			if not block_data.has(neighbor):
				potential_breach_locations.append(coord)
				break
	
	if not potential_breach_locations.is_empty():
		var breach_cell: Vector2i = potential_breach_locations.pick_random()
		block_data[breach_cell].feature = Towers.Type.BREACH
		block_data[breach_cell].initial_state[ID.UnitState.SEED_DURATION_WAVES] = params.breach_seed_duration

	return block_data

func _trigger_camera_overview(island: Island) -> void:
	# 1. get references and handle invalid states
	var camera: Camera = References.camera
	if not is_instance_valid(camera) or not is_instance_valid(island):
		push_warning("ExpansionService: Camera or Island is not valid, cannot trigger overview.")
		return
	# 2. get the island's bounds and the camera's viewport size
	var island_bounds: Rect2 = island.get_island_bounds()
	print(island_bounds)
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	# 3. guard against a zero-sized island to prevent division by zero
	if island_bounds.size.x <= 0 or island_bounds.size.y <= 0:
		return
	# 5. calculate the required zoom level
	var longest_distance: float = max(island_bounds.size.x, island_bounds.size.y)
	# the final zoom must be the larger of the two ratios to ensure everything fits
	var required_zoom_level: float = 4.0 / (longest_distance * 0.01) #this is derived from the camera's default zoom and the island's intiial size (1/100)
	print(1 / required_zoom_level)

	var target_zoom: Vector2 = Vector2.ONE * required_zoom_level
	
	# 4. calculate the target position (the center of the island)
	var target_position: Vector2 = island_bounds.get_center() + Vector2(island_bounds.size.x * 0.5, 0) + Vector2(OVERVIEW_ISLAND_OFFSET * viewport_size.x / required_zoom_level, 0)

	# 6. command the camera to execute the transition
	camera.override_camera(target_position, target_zoom, 0.75)
	
# new helper to calculate bounds and focus on a single choice
func _trigger_camera_focus_on_choice(island: Island, choice_id: int) -> void:
	var camera: Camera = References.camera
	if not is_instance_valid(camera) or not _choices_by_id.has(choice_id):
		return

	var choice: ExpansionChoice = _choices_by_id[choice_id]
	if choice.block_data.is_empty():
		return

	# 1. calculate the bounding box of just this one choice
	var choice_bounds := Rect2(choice.block_data.keys()[0], Vector2.ONE)
	for cell: Vector2i in choice.block_data:
		choice_bounds = choice_bounds.expand(cell)
	
	# 2. convert from grid coordinates to world coordinates
	var world_bounds := Rect2(
		Island.cell_to_position(choice_bounds.position),
		choice_bounds.size * Island.CELL_SIZE + Vector2.ONE * Island.CELL_SIZE #this is to account for the 0.5 cell_size on each side
	)
	
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	if world_bounds.size.x <= 0 or world_bounds.size.y <= 0:
		return

	# 3. reuse the zoom formula to frame the selection
	var longest_distance: float = max(world_bounds.size.x, world_bounds.size.y)
	var required_zoom_level: float = 4.0 / (longest_distance * 0.01)
	var target_zoom: Vector2 = Vector2.ONE * required_zoom_level
	
	# 4. calculate the target position (the center of the choice)
	var target_position: Vector2 = world_bounds.get_center() + Vector2(world_bounds.size.x * 0.5, 0) + Vector2(OVERVIEW_ISLAND_OFFSET * viewport_size.x / required_zoom_level, 0)

	# 5. command the camera to execute the transition
	camera.override_camera(target_position, target_zoom, 0.5)
