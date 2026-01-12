# expansion_service.gd (Autoload Singleton)
extends Node

signal expansion_process_complete

#configuration
const OVERVIEW_ISLAND_OFFSET: float = 0.0 #determines how offset the island is from the centre of the screen during overviews
# --- procedural configuration ---
# A helper class to define how a specific terrain type (Bonus Tile) spawns
class TerrainGenRule extends Resource:
	@export var terrain_type: Terrain.Base ##what type of terrain is being placed
	@export var probability: float ##probability of a seed appearing at any given tile
	@export var cluster_size_min: int = 1 ##minimum size of cluster
	@export var cluster_size_max: int = 1 ##maximum size of cluster
	@export var allowed_on: Array[Terrain.Base] = [] ## terrains which this one is allowed to substitute. if empty, can spawn on 'raw' ground (EARTH)
	
	func _init(_type: Terrain.Base = Terrain.Base.EARTH, _prob: float = 0.0, _c_min: int = 1, _c_max: int = 1):
		terrain_type = _type
		probability = _prob
		cluster_size_min = _c_min
		cluster_size_max = _c_max
		
class PlacementRule extends Resource:
	@export var tower_type: Towers.Type ##tower type
	@export var tower_initial_state: Dictionary = {} ##initial state of tower
	
	@export var min_seeds: int = 1 ##minimum number of seeds
	@export var max_seeds: int = 1 ##maximum number of seeds
	@export var seed_placement: PlacementLogic ##placement logic of seed
	@export var cluster_size_min: int = 1 ##minimum cluster size
	@export var cluster_size_max: int = 1 ##maximum cluster size

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
	
	var terrain_rules: Array[TerrainGenRule] = STANDARD_EXPANSION_PARAMS.terrain_gen_rules
	terrain_rules.append(TerrainGenRule.new(Terrain.Base.HIGHLAND, 0.08, 1, 2))
	terrain_rules.append(TerrainGenRule.new(Terrain.Base.SETTLEMENT, 0.06))
	
	var breach_rule := PlacementRule.new()
	breach_rule.tower_type = Towers.Type.BREACH
	breach_rule.seed_placement = PlacementLogic.EDGE
	breach_rule.tower_initial_state = {ID.TerrainGen.SEED_DURATION_WAVES: 0}
	
	var artifact_rule := PlacementRule.new()
	artifact_rule.tower_type = Towers.Type.ARTIFACT
	artifact_rule.seed_placement = PlacementLogic.ANYWHERE
	
	var forest_rule := PlacementRule.new()
	forest_rule.tower_type = Towers.Type.FOREST
	forest_rule.seed_placement = PlacementLogic.ANYWHERE
	forest_rule.cluster_size_min = 1
	forest_rule.cluster_size_max = 6
	forest_rule.min_seeds = 1
	forest_rule.max_seeds = 1
	
	STANDARD_EXPANSION_PARAMS.placement_rules.append(breach_rule)
	#STANDARD_EXPANSION_PARAMS.placement_rules.append(artifact_rule)
	STANDARD_EXPANSION_PARAMS.placement_rules.append(forest_rule)

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
	var terrain_rules: Array[TerrainGenRule] = initial_params.terrain_gen_rules
	terrain_rules.append(TerrainGenRule.new(Terrain.Base.HIGHLAND, 0.05, 1, 2))
	# rule 1: place one active breach
	var breach_rule := PlacementRule.new()
	breach_rule.tower_type = Towers.Type.BREACH
	breach_rule.seed_placement = PlacementLogic.EDGE
	breach_rule.tower_initial_state = {"seed_duration_waves": 0} # 0 = active immediately
	
	var anomaly_rule := PlacementRule.new()
	anomaly_rule.tower_type = Towers.Type.ARTIFACT
	anomaly_rule.seed_placement = PlacementLogic.ANYWHERE
	anomaly_rule.tower_initial_state[&"reward"] = RewardService.get_rewards(1, [Reward.Type.ADD_RELIC])[0]
	#NOTE: no special terrain
	initial_params.placement_rules.append(breach_rule)
	#initial_params.placement_rules.append(anomaly_rule)
	
	return _generate_block(island, block_size, initial_params)

# the main public API called by Phases.gd
func generate_and_present_choices(island: Island, block_size: int, choice_count: int) -> void:
	_choices_by_id.clear()
	_hovered_choice_id = -1
	_pending_choice_id = -1
	_current_state = State.CHOOSING #set initial state
	
	var options: Array[ExpansionChoice] = []
	var rewards: Array[Reward] = RewardService.get_rewards(choice_count, [Reward.Type.ADD_RELIC])
	for i: int in range(choice_count):
		# generate the block data, which may now include a breach seed
		var expansion_params: GenerationParameters = STANDARD_EXPANSION_PARAMS.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_INTERNAL)
		#var artifact_rule: PlacementRule = expansion_params.placement_rules[1]
		#artifact_rule.tower_initial_state[&"reward"] = rewards[i]

		var block_data: Dictionary = _generate_block(island, block_size, expansion_params)
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
	# prioritise the choice currently selected
	if _pending_choice_id != -1:
		if _choices_by_id.has(_pending_choice_id) and _choices_by_id[_pending_choice_id].block_data.has(cell):
			return _choices_by_id[_pending_choice_id].block_data[cell]
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
	References.terrain_generating.emit(params) 
	var block_data: Dictionary[Vector2i, Terrain.CellData] = {}
	
	# 1. SHAPE GENERATION (BFS)
	var start_pos: Vector2i = Vector2i.ZERO if island.shore_boundary_tiles.is_empty() else island.shore_boundary_tiles.pick_random()
	var to_visit: Array[Vector2i] = [start_pos]
	var visited: Dictionary[Vector2i, bool] = {}
	var generated_coords: Array[Vector2i] = []

	while not to_visit.is_empty() and generated_coords.size() < block_size:
		var cell: Vector2i = to_visit.pop_front()
		if visited.has(cell):
			continue
		visited[cell] = true
		
		# Only expand into empty space
		if island.terrain_base_grid.get(cell) == null:
			generated_coords.append(cell)

		for dir: Vector2i in island.DIRS:
			var neighbor: Vector2i = cell + dir 
			if not visited.has(neighbor):
				to_visit.append(neighbor)
	
	if generated_coords.is_empty():
		return {}

	# 2. TERRAIN PAINTING (Bonus Tiles)
	# First, fill everything with default EARTH
	for coord: Vector2i in generated_coords:
		block_data[coord] = Terrain.CellData.new(Terrain.Base.EARTH, Towers.Type.VOID)
	
	# Now apply procedural terrain rules (Ruins, Highlands, Gold Veins, etc.)
	# We shuffle coords to prevent "top-left" bias
	var coords_pool_for_terrain = generated_coords.duplicate()
	coords_pool_for_terrain.shuffle()
	
	for rule: TerrainGenRule in params.terrain_gen_rules:
		# Determine how many "seeds" of this terrain to plant
		var target_count: int = int(generated_coords.size() * rule.probability) #pseudorandom
		if target_count <= 0: continue
		
		var placed_count: int = 0
		for i in range(coords_pool_for_terrain.size()):
			if placed_count >= target_count: break
			
			var center: Vector2i = coords_pool_for_terrain[i]
			# Check requirements (e.g. only on Earth)
			if not rule.allowed_on.is_empty():
				if not block_data[center].terrain in rule.allowed_on:
					continue
			
			# Grow the cluster
			var cluster_size: int = randi_range(rule.cluster_size_min, rule.cluster_size_max)
			var cluster_cells: Array[Vector2i] = _grow_blob_in_block(center, cluster_size, block_data)
			
			for cell: Vector2i in cluster_cells:
				block_data[cell].terrain = rule.terrain_type
			
			placed_count += 1

	# 3. FEATURE PLACEMENT (Towers / Groves)
	var available_cells: Array[Vector2i] = generated_coords.duplicate()
	
	for rule: PlacementRule in params.placement_rules:
		# "rule.count" here is interpreted as "Number of instances" OR "Number of Clusters" depending on logic
		var candidate_cells: Array[Vector2i] = _get_candidate_cells(available_cells, island, rule.seed_placement)
		
		var features_to_place: int = randi_range(rule.min_seeds, rule.max_seeds)
		var placed_features: int = 0
		while placed_features < features_to_place and not candidate_cells.is_empty():
			var seed_cell: Vector2i = candidate_cells.pick_random()
			
			# handle clustering
			var cells_to_occupy: Array[Vector2i] = []
			if rule.cluster_size_max > 1:
				# Assume 'initial_state' might contain cluster config, or use defaults
				var clump_size: int = randi_range(rule.cluster_size_min, rule.cluster_size_max)
				cells_to_occupy = _grow_blob_in_block(seed_cell, clump_size, block_data, true) # true = check for empty feature
			else:
				cells_to_occupy = [seed_cell]
				
			# Place the features
			for target_cell: Vector2i in cells_to_occupy:
				block_data[target_cell].feature = rule.tower_type
				block_data[target_cell].initial_state = rule.tower_initial_state.duplicate_deep()
				
				# Cleanup pools
				available_cells.erase(target_cell)
				if candidate_cells.has(target_cell): candidate_cells.erase(target_cell)
			placed_features += 1
			
	return block_data
	
#helper function to find valid locations based on a placement rule
func _get_candidate_cells(pool: Array[Vector2i], island: Island, placement_logic: PlacementLogic) -> Array[Vector2i]:
	match placement_logic:
		PlacementLogic.ANYWHERE:
			return pool.duplicate() # all available cells are valid
			
		PlacementLogic.EDGE:
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
	
# helper to grow a blob (for terrain patches or groves)
# center: start tile
# size: how many tiles
# block_data: context to check bounds
# check_feature_empty: if true, only grows into tiles with no existing tower/feature
func _grow_blob_in_block(center: Vector2i, size: int, block_data: Dictionary, check_feature_empty: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var open_list: Array[Vector2i] = [center]
	var processed: Dictionary[Vector2i, bool] = {center: true}
	#BFS
	while result.size() < size and not open_list.is_empty():
		var current = open_list.pop_front()
		
		# validation check
		if not block_data.has(current): continue
		if check_feature_empty and block_data[current].feature != Towers.Type.VOID: continue
		
		result.append(current)
		
		# add neighbors
		var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		neighbors.shuffle() # Randomize shape
		
		for n: Vector2i in neighbors:
			var next = current + n
			if block_data.has(next) and not processed.has(next):
				processed[next] = true
				open_list.append(next)
				
	return result

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
func _trigger_camera_focus_on_choice(_island: Island, choice_id: int) -> void:
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
