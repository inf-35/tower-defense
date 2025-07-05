extends Node2D
class_name Island

signal terrain_changed
signal tower_changed(tower_position: Vector2i)
signal expansion_applied

var terrain_level_grid: Dictionary[Vector2i, Terrain.Level] = {}
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {} # Store for Terrain.Base
var occupied_grid: Dictionary[Vector2i, bool] = {} # Whether terrain is occupied or not
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []
var active_boundary_tiles: Array[Vector2i] = [ Vector2i.ZERO ]

var is_choosing_expansion: bool = false
var current_expansion_options: Array[ExpansionChoice] = []

const CELL_SIZE: int = 13
const GRID_SIZE: int = 50
const HALF: int = GRID_SIZE * 0.5

const DIRS: Array[Vector2i] = [
	Vector2i( 1,  0),
	Vector2i(-1,  0),
	Vector2i( 0,  1),
	Vector2i( 0, -1),
]

static func position_to_cell(position: Vector2) -> Vector2i:
	return floor(position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5

func _ready():
	generate_terrain()
	construct_tower(Vector2i.ZERO, Towers.Type.PLAYER_CORE)
	queue_redraw()

func construct_tower(cell: Vector2i, tower_type: Towers.Type = Towers.Type.VOID, tower_facing: Tower.Facing = Tower.Facing.UP):
	if tower_type == Towers.Type.VOID:
		if tower_grid.has(cell) and is_instance_valid(tower_grid[cell]):
			tower_grid[cell].queue_free()
		update_adjacencies_around(cell)
		return

	var tower: Tower = Towers.create_tower(tower_type)
	occupied_grid[cell] = true
	_update_navigation(cell) # Update navigation
	tower_grid[cell] = tower

	tower.type # Necessary: Evil pre-resolution hotfix
	tower.facing = tower_facing
	add_child(tower)

	tower.tower_position = cell
	terrain_changed.emit()
	tower_changed.emit(cell)
	update_adjacencies_around(cell)
	
func update_adjacencies_around(cell: Vector2i): #allows neighbouring tiles to detect updated adjacencies
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	if tower_grid.has(cell): #update our own adjacencies
		tower_grid[cell].adjacency_updated.emit(adjacent_towers)
	
	for tower: Tower in adjacent_towers.values(): #conversely we also have to update neighbours
		var local_adjacencies: Dictionary[Vector2i, Tower] = get_adjacent_towers(tower.tower_position)
		tower.adjacency_updated.emit(local_adjacencies)

func generate_terrain():
	terrain_base_grid.clear()
	terrain_level_grid.clear()
	occupied_grid.clear()
	Navigation.grid.clear()

	# Generate terrain grid with base and level types
	for x in range(-HALF, HALF+1):
		for y in range(-HALF, HALF+1):
			terrain_base_grid[Vector2i(x, y)] = Terrain.Base.EARTH
			terrain_level_grid[Vector2i(x, y)] = Terrain.Level.SEA
			occupied_grid[Vector2i(x, y)] = false

	expand_by_block(TerrainGen.generate_block(35))
	expand_by_block(TerrainGen.generate_block(6))
	
	_update_terrain()

func _update_terrain():
	shore_boundary_tiles = _get_terrain_boundary(terrain_level_grid, terrain_level_grid.keys(), Terrain.Level.EARTH, Terrain.Level.SEA)
	terrain_changed.emit()
	Navigation.clear_field()
	queue_redraw()

func _update_navigation(affected_cell = null):
	if affected_cell == null:
		Navigation.grid.clear()

		for cell: Vector2i in terrain_base_grid:
			Navigation.grid[cell] = Terrain.is_navigable(terrain_base_grid[cell]) and (not occupied_grid[cell])
	else: # Affected cell, update targeting specific cell
		Navigation.grid[affected_cell] = Terrain.is_navigable(terrain_base_grid[affected_cell]) and (not occupied_grid[affected_cell])
	Navigation.clear_field()

func _get_terrain_boundary(_terrain_grid: Dictionary[Vector2i, Terrain.Level] = terrain_level_grid, scope: Array[Vector2i] = terrain_level_grid.keys(), terrain: Terrain.Level = Terrain.Level.EARTH, rim = null) -> Array[Vector2i]:
	var boundary_tiles: Array[Vector2i] = []

	for cell: Vector2i in scope:
		if _terrain_grid[cell] != terrain:
			continue
		# Check neighbors
		for direction: Vector2i in DIRS:
			var neighbor: Vector2i = cell + direction
			if rim != null: # Specified rim terrain
				if _terrain_grid[neighbor] == rim:
					boundary_tiles.append(cell)
					break
			elif not _terrain_grid.has(neighbor) or _terrain_grid[neighbor] != terrain:
				boundary_tiles.append(cell)
				break

	return boundary_tiles
#expansion mechanism
func expand_by_block(block: Dictionary[Vector2i, Terrain.Base]) -> void:
	for cell: Vector2i in block:
		terrain_base_grid[cell] = block[cell]
		terrain_level_grid[cell] = Terrain.Level.EARTH
		occupied_grid[cell] = false
		Navigation.grid[cell] = true

	active_boundary_tiles = _get_terrain_boundary(terrain_level_grid, block.keys(), Terrain.Level.EARTH, Terrain.Level.SEA)
	_update_terrain()
	
var preview_grid: Dictionary[Vector2i, Terrain.Base] = {} #for preview terrain
var preview_tint_grid: Dictionary[Vector2i, Color] = {} #preview tints

#expansion
func present_expansion_choices(options: Array[ExpansionChoice]): #entry point to expansion, called by Phases
	is_choosing_expansion = true
	current_expansion_options = options
	
	preview_grid.clear() #clear preview
	for option: ExpansionChoice in options:
		if option and option.block_data: # Check if option and its block_data are valid
			var rand_color: Color = Color(randf(), randf(), randf(), 0.5)
			for world_cell: Vector2i in option.block_data:
				# Store the Terrain.Base type for preview drawing
				preview_grid[world_cell] = option.block_data[world_cell]
				preview_tint_grid[world_cell] = rand_color
	queue_redraw()

func select_expansion(choice_id: int):
	if not is_choosing_expansion:
		push_warning("Island: Tried to select expansion when not in choice mode.")
		# emit expansion_applied to potentially unstuck Phases
		expansion_applied.emit()
		return

	var chosen_option: ExpansionChoice = null
	for option: ExpansionChoice in current_expansion_options: #retrieve corresponding option
		if option and option.id == choice_id:
			chosen_option = option
			break
	
	if chosen_option and chosen_option.block_data and not chosen_option.block_data.is_empty():
		apply_expansion_option(chosen_option) # This will handle state clearing and signal
	else:
		push_error("Island: Selected expansion choice_id '" + str(choice_id) + "' not found or has no data.")
	# Clear preview state and emit signal to allow game to continue
	preview_grid.clear()
	is_choosing_expansion = false
	current_expansion_options.clear()
	
	queue_redraw()
	
	expansion_applied.emit() # Allow game to resume
	
func apply_expansion_option(option: ExpansionChoice):
	expand_by_block(option.block_data)
	
	if is_choosing_expansion: # Clear preview state if we were in choice mode
		preview_grid.clear()
		is_choosing_expansion = false
		current_expansion_options.clear()

func _draw():
	for cell_pos: Vector2i in terrain_base_grid.keys():
		var rect_position: Vector2 = cell_pos * CELL_SIZE
		var rect = Rect2(rect_position, Vector2(CELL_SIZE, CELL_SIZE))
		var color: Color = Terrain.get_color(terrain_level_grid[cell_pos], terrain_base_grid[cell_pos])
		if active_boundary_tiles.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.SHORE, terrain_base_grid[cell_pos])
		if preview_grid.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.EARTH, preview_grid[cell_pos]).blend(preview_tint_grid[cell_pos])
		draw_rect(rect, color)

# "Public" helper functions
func get_adjacent_towers(cell: Vector2i) -> Dictionary[Vector2i, Tower]: #returns tower with their local direction
	var output: Dictionary[Vector2i, Tower] = {}
	for dir: Vector2i in DIRS:
		if not tower_grid.has(cell + dir):
			continue
		output[dir] = tower_grid[cell + dir]

	return output

func is_occupied(cell: Vector2i) -> bool:
	if occupied_grid.has(cell):
		return occupied_grid[cell]
	else:
		return false

func get_terrain_base(cell: Vector2i) -> Terrain.Base:
	return terrain_base_grid[cell]

func get_terrain_level(cell: Vector2i) -> Terrain.Level:
	if terrain_level_grid.has(cell):
		return terrain_level_grid[cell]
	else:
		#push_warning("couldnt get terrain level reading at, ", str(cell))
		return Terrain.Level.SEA
