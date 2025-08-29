# expansion_service.gd (Autoload Singleton)
extends Node

signal expansion_process_complete

var is_choosing_expansion: bool = false
var _current_expansion_options: Array[ExpansionChoice] = []

# the main public API called by Phases.gd
func generate_and_present_choices(island: Island, block_size: int, choice_count: int) -> void:
	var options: Array[ExpansionChoice] = []
	for i: int in range(choice_count):
		# generate the block data, which may now include a breach seed
		var block_data: Dictionary = _generate_block(island, block_size)
		if block_data.is_empty():
			continue
		options.append(ExpansionChoice.new(i, block_data))

	if options.is_empty():
		push_warning("ExpansionService: All generated options were empty. Skipping.")
		expansion_process_complete.emit() # must emit to unblock the phase manager
		return

	is_choosing_expansion = true
	_current_expansion_options = options
	
	var preview_grid: Dictionary[Vector2i, Terrain.CellData] = {}
	var tint_grid: Dictionary[Vector2i, Color] = {}
	for option: ExpansionChoice in options:
		var rand_color := Color(randf(), randf(), randf(), 0.5)
		for cell: Vector2i in option.block_data:
			preview_grid[cell] = option.block_data[cell]
			tint_grid[cell] = rand_color
	
	island.update_previews(preview_grid, tint_grid)
	UI.display_expansion_choices.emit(options)

# applies the chosen expansion
func select_expansion(island: Island, choice_id: int) -> void:
	if not is_choosing_expansion:
		expansion_process_complete.emit()
		return

	var chosen_option: ExpansionChoice = null
	for option: ExpansionChoice in _current_expansion_options:
		if option.id == choice_id:
			chosen_option = option
			break
	
	if chosen_option and not chosen_option.block_data.is_empty():
		TerrainService.expand_island(island, chosen_option.block_data)
	
	_clear_expansion_state(island)
	expansion_process_complete.emit()
	UI.hide_expansion_choices.emit()

func _clear_expansion_state(island: Island) -> void:
	is_choosing_expansion = false
	_current_expansion_options.clear()
	island.update_previews({}, {})

# procedural generation logic, adapted from the old TerrainGen
func _generate_block(island: Island, block_size: int) -> Dictionary[Vector2i, Terrain.CellData]:
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
		
		var base: Terrain.Base = Terrain.Base.EARTH if randf() > 0.08 else Terrain.Base.RUINS
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
		block_data[breach_cell].behavior_packet[&"seed_duration_waves"] = 0

	return block_data
