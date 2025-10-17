# expansion_service.gd (Autoload Singleton)
extends Node

signal expansion_process_complete

#configuration
const OVERVIEW_ISLAND_OFFSET: float = 0.0 #determines how offset the island is from the centre of the screen during overviews
# --- state machine ---
enum State { IDLE, CHOOSING, CONFIRMING }
var _current_state: State = State.IDLE
var _choices_by_id: Dictionary[int, ExpansionChoice] = {}
var _hovered_choice_id: int = -1 # -1 means no choice is hovered
var _pending_choice_id: int = -1 # the choice waiting for confirmation

var STANDARD_EXPANSION_PARAMS: GenerationParameters #see _init for definition

# --- terrain generation ---
enum PlacementLogic {
	ANYWHERE,
	EDGE,
}

func _init():
	STANDARD_EXPANSION_PARAMS = GenerationParameters.new()
	STANDARD_EXPANSION_PARAMS.ruins_chance = 0.10
	
	var breach_rule := PlacementRule.new()
	breach_rule.tower_type = Towers.Type.BREACH
	breach_rule.placement = PlacementRule.PlacementLogic.EDGE
	breach_rule.initial_state = {ID.TerrainGen.SEED_DURATION_WAVES: 2}
	
	var anomaly_rule := PlacementRule.new()
	anomaly_rule.tower_type = Towers.Type.ANOMALY
	anomaly_rule.placement = PlacementRule.PlacementLogic.EDGE
	anomaly_rule.initial_state = {}
	
	STANDARD_EXPANSION_PARAMS.placement_rules.append(breach_rule)
	STANDARD_EXPANSION_PARAMS.placement_rules.append(anomaly_rule)

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
	# for the very first block, we create a custom ruleset in code
	var initial_params := GenerationParameters.new()
	initial_params.ruins_chance = 0.05 # lower chance of ruins at the start
	# rule 1: place one active breach
	var breach_rule := PlacementRule.new()
	breach_rule.tower_type = Towers.Type.BREACH
	breach_rule.placement = PlacementRule.PlacementLogic.EDGE
	breach_rule.initial_state = {"seed_duration_waves": 0} # 0 = active immediately
	
	initial_params.placement_rules.append(breach_rule)
	
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
		var anomaly_rule: PlacementRule = STANDARD_EXPANSION_PARAMS.placement_rules[1]
		var seed: float = randf_range(0.0, 1.0)
		anomaly_rule.initial_state["_anomaly_data"] = AnomalyData.new(
			Reward.new(
				Reward.Type.UNLOCK_TOWER,
				{
					ID.Rewards.TOWER_TYPE: Towers.Type.CANNON
				}
			) if seed > 0.7 else 
			(
				Reward.new(
					Reward.Type.UNLOCK_TOWER,
					{
						ID.Rewards.TOWER_TYPE: Towers.Type.MINIGUN
					}
				) if seed > 0.3 else 
				Reward.new(
					Reward.Type.ADD_RELIC,
					{
						ID.Rewards.RELIC: Relics.TOWER_SPEED_UP
					}
				)
			)
			,
			2
		)
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
	
# returns the CellData for a previewed tile, or null if no preview exists there.
func get_preview_data_at_cell(cell: Vector2i) -> Terrain.CellData:
	if _current_state == State.IDLE:
		return null
	# iterate through the choices to find which one, if any, contains this cell
	for choice: ExpansionChoice in _choices_by_id.values():
		if choice.block_data.has(cell):
			return choice.block_data[cell]

	return null
	
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

	# simplified breadth-first search to find adjacent sea tiles (find tile-coordinates to expand)
	while not to_visit.is_empty() and generated_coords.size() < block_size:
		var cell: Vector2i = to_visit.pop_front()
		if visited.has(cell):
			continue
		visited[cell] = true
		
		# only empty tiles can be converted to land
		if island.terrain_base_grid.get(cell) == null:
			generated_coords.append(cell)

		for dir: Vector2i in island.DIRS:
			var neighbor: Vector2i = cell + dir #NOTE: we also visit non-empty tiles. this allows more "smooth" expansion blobs
			if not visited.has(neighbor):
				to_visit.append(neighbor)
	
	if generated_coords.is_empty():
		return {}
	# assign terrain base to the chosen coordinates
	for coord: Vector2i in generated_coords:
		block_data[coord] = Terrain.CellData.new(Terrain.Base.EARTH, Towers.Type.VOID)
		
		var base: Terrain.Base = Terrain.Base.EARTH if randf() > params.ruins_chance else Terrain.Base.RUINS
		block_data[coord].terrain = base
		
	# --- Feature Placement Pipeline ---
	# 2. create a mutable pool of available locations for feature placement
	var available_cells: Array[Vector2i] = generated_coords.duplicate()
	# 3. iterate through the rules defined in the GenerationParameters
	for rule: PlacementRule in params.placement_rules:
		# find all cells in the pool that are valid for this rule's placement logic
		var candidate_cells: Array[Vector2i] = _get_candidate_cells(available_cells, island, rule.placement)
		# place the feature 'count' times
		for i: int in rule.count:
			if candidate_cells.is_empty():
				# if we run out of valid spots, break the inner loop and move to the next rule
				break
			
			# pick a random valid cell
			var chosen_cell: Vector2i = candidate_cells.pick_random()
			
			# place the feature
			block_data[chosen_cell].feature = rule.tower_type
			block_data[chosen_cell].initial_state = rule.initial_state
			
			# CRITICAL: remove the chosen cell from all pools to prevent conflicts
			candidate_cells.erase(chosen_cell)
			available_cells.erase(chosen_cell)
	return block_data
	
#helper function to find valid locations based on a placement rule
func _get_candidate_cells(pool: Array[Vector2i], island: Island, placement_logic: PlacementRule.PlacementLogic) -> Array[Vector2i]:
	match placement_logic:
		PlacementRule.PlacementLogic.ANYWHERE:
			return pool # all available cells are valid
			
		PlacementRule.PlacementLogic.EDGE:
			var edge_cells: Array[Vector2i] = []
			for cell: Vector2i in pool:
				var is_edge: bool = false
				for dir: Vector2i in island.DIRS:
					# an edge tile is one that is adjacent to the existing island or sea (a non-pool tile)
					if not pool.has(cell + dir):
						is_edge = true
						break
				if is_edge:
					edge_cells.append(cell)
			return edge_cells
			
	return [] # fallback

func _trigger_camera_overview(island: Island) -> void:
	# 1. get references and handle invalid states
	var camera: Camera = References.camera
	if not is_instance_valid(camera) or not is_instance_valid(island):
		push_warning("ExpansionService: Camera or Island is not valid, cannot trigger overview.")
		return
	# 2. get the island's bounds and the camera's viewport size
	var island_bounds: Rect2 = island.get_island_bounds()
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	# 3. guard against a zero-sized island to prevent division by zero
	if island_bounds.size.x <= 0 or island_bounds.size.y <= 0:
		return
	# 4. calculate the required zoom level
	var longest_distance: float = max(island_bounds.size.x, island_bounds.size.y)
	# the final zoom must be the larger of the two ratios to ensure everything fits
	var required_zoom_level: float = 4.0 / (longest_distance * 0.01) #this is derived from the camera's default zoom and the island's intiial size (1/100)

	var target_zoom: Vector2 = Vector2.ONE * required_zoom_level
	
	# 5. calculate the target position (offset such that the rightmots edge of the island appears at the centre of the screen, offset by OVERVIEW_ISLAND_OFFSET
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
	
	# 4. calculate the target position (see above, but this time for the selection in particular)
	var target_position: Vector2 = world_bounds.get_center() + Vector2(world_bounds.size.x * 0.5, 0) + Vector2(OVERVIEW_ISLAND_OFFSET * viewport_size.x / required_zoom_level, 0)

	# 5. command the camera to execute the transition
	camera.override_camera(target_position, target_zoom, 0.5)
