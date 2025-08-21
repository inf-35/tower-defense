# island.gd
# MODIFIED: This script now handles all world logic, including tower placement
# validation and power management for the towers on the island. It listens for
# signals from the Player and Towers to react to state changes.
extends Node2D
class_name Island

# --- RETAINED SIGNALS ---
signal terrain_changed
signal tower_changed(tower_position: Vector2i)
signal expansion_applied

# --- RETAINED GRIDS & STATE ---
var terrain_level_grid: Dictionary[Vector2i, Terrain.Level] = {}
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {}
var occupied_grid: Dictionary[Vector2i, bool] = {}
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []
var active_boundary_tiles: Array[Vector2i] = [ Vector2i.ZERO ]

var is_choosing_expansion: bool = false
var current_expansion_options: Array[ExpansionChoice] = []

var preview_grid: Dictionary[Vector2i, Terrain.Base] = {}
var preview_tint_grid: Dictionary[Vector2i, Color] = {}

# --- ADDED: Power Management State ---
# This state is now managed by the Island, not the Player.
var disabled_towers: Array[Tower] = []

# --- RETAINED CONSTANTS ---
const CELL_SIZE: int = 13
const GRID_SIZE: int = 50
const HALF: int = GRID_SIZE * 0.5
const DIRS: Array[Vector2i] = [ Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) ]

# --- GODOT LIFECYCLE & INITIALIZATION ---

func _ready():
	# ADDED: Connect to the Player's capacity signal to manage power status.
	# This is the key to decoupling: the Island listens for state changes.
	Player.capacity_changed.connect(_on_player_capacity_changed)

	generate_terrain()
	# MODIFIED: Use the proper request function to place the initial tower.
	# This ensures all necessary logic (signal connections, etc.) is run.
	# The cost is handled by the Player script before the game loop starts.
	request_tower_placement(Towers.Type.PLAYER_CORE, Vector2i.ZERO, Tower.Facing.UP)
	queue_redraw()

# --- PUBLIC API / REQUEST HANDLERS ---

# ADDED: A new function to handle placement requests from the Player.
func request_tower_placement(tower_type: Towers.Type = Towers.Type.VOID, cell: Vector2i = Vector2i.ZERO, tower_facing: Tower.Facing = Tower.Facing.UP) -> bool:
	"""
	Validates and executes a tower placement request. This is the single entry point
	for creating towers. Returns true on success, false on failure.
	"""
	# 0. are we trying to sell a tower?
	if tower_grid.has(cell) and tower_type == Towers.Type.VOID:
		tower_grid[cell].sell()
		return true

	# 1. World-related upgrade/placement checks (moved from Player)
	if tower_grid.has(cell):
		var host: Tower = tower_grid[cell]
		if host.type == tower_type and host.level < Towers.get_max_level(tower_type):
			# This is an upgrade. For now, we assume the player already paid.
			host.level += 1
			tower_changed.emit(cell)
			return true # Success
		return false # Cannot place on a different tower type or max level

	# 2. Terrain checks (moved from Player)
	var min_terrain = Towers.get_tower_minimum_terrain(tower_type)
	if not terrain_level_grid.has(cell) or get_terrain_level(cell) < min_terrain:
		return false

	# 3. All checks passed, construct the tower.
	_construct_tower(cell, tower_type, tower_facing)
	return true # Success

# --- INTERNAL TOWER & GRID LOGIC ---

# MODIFIED: Renamed to _construct_tower to mark as internal. It now also connects signals.
func _construct_tower(cell: Vector2i, tower_type: Towers.Type = Towers.Type.VOID, tower_facing: Tower.Facing = Tower.Facing.UP):
	var tower: Tower = Towers.create_tower(tower_type)
	
	occupied_grid[cell] = true
	_update_navigation(cell)
	tower_grid[cell] = tower
	
	tower.facing = tower_facing
	tower.tower_position = cell
	tower.flux_value = Towers.get_tower_cost(tower_type)
	#NOTE: tower's by default refund what they cost to build
	#to preserve this relationship, updating tower cost must be done after this step
	add_child(tower)

	tower.died.connect(_on_tower_destroyed.bind(tower))
	#add used capacity
	Player.add_to_used_capacity(Towers.get_tower_capacity(tower_type))

	terrain_changed.emit()
	tower_changed.emit(cell)
	update_adjacencies_around(cell)

# --- SIGNAL HANDLERS ---

# ADDED: Handles a tower being sold.
func _on_tower_destroyed(tower: Tower):
	var cell = tower.tower_position
	if tower_grid.has(cell):
		# Clean up grids and state
		tower_grid.erase(cell)
		occupied_grid[cell] = false
		_update_navigation(cell)
		# If it was a capacity provider, tell the player to remove its contribution.
		Player.remove_from_used_capacity(Towers.get_tower_capacity(tower.type))
		# Update neighbors
		update_adjacencies_around(cell)

# ADDED: Listens for player capacity changes to manage the island's power grid.
func _on_player_capacity_changed(used: float, total: float):
	print(used, " / ", total)
	if used > total:
		var deficit = used - total
		_disable_towers_for_deficit(deficit)
	else:
		_reenable_towers()

# --- MOVED & ADDED: POWER MANAGEMENT LOGIC ---
# This logic was moved from player.gd and now correctly resides in island.gd.

func _disable_towers_for_deficit(deficit: float):
	var towers: Array[Tower] = tower_grid.values()
	# Sort by most recently constructed to shut them down first.
	towers.sort_custom(func(a,b): return a.unit_id > b.unit_id)
	
	var deficit_to_fill: float = deficit
	for tower: Tower in towers:
		if deficit_to_fill <= 0:
			break
			
		# Skip essential towers, capacity providers, or already disabled towers.
		if tower in disabled_towers or \
		tower.type == Towers.Type.GENERATOR or tower.type == Towers.Type.PLAYER_CORE:
			continue
			
		if not tower.disabled:
			tower.disabled = true # Use the tower's own method.
			disabled_towers.append(tower)
			deficit_to_fill -= Towers.get_tower_capacity(tower.type)

func _reenable_towers():
	# If there's still a deficit, do nothing.
	if Player.used_capacity > Player.tower_capacity:
		return

	var capacity_surplus = Player.tower_capacity - Player.used_capacity
	
	# Iterate backwards to reactivate towers in the reverse order they were deactivated.
	for i in range(disabled_towers.size() - 1, -1, -1):
		var tower = disabled_towers[i]
		var tower_cap_cost = Towers.get_tower_capacity(tower.type)
		
		if capacity_surplus >= tower_cap_cost:
			tower.disabled = false# Use the tower's own method.
			capacity_surplus -= tower_cap_cost
			disabled_towers.remove_at(i)

# --- RETAINED: TERRAIN, NAVIGATION, & EXPANSION LOGIC ---
# The following functions are unchanged as they were already correctly placed.

func generate_terrain():
	# ... (Function retained as is)
	terrain_base_grid.clear()
	terrain_level_grid.clear()
	occupied_grid.clear()
	Navigation.grid.clear()

	for x in range(-HALF, HALF+1):
		for y in range(-HALF, HALF+1):
			terrain_base_grid[Vector2i(x, y)] = Terrain.Base.EARTH
			terrain_level_grid[Vector2i(x, y)] = Terrain.Level.SEA
			occupied_grid[Vector2i(x, y)] = false

	expand_by_block(TerrainGen.generate_block(36))
	expand_by_block(TerrainGen.generate_block(6))
	_update_terrain()

func expand_by_block(block: Dictionary[Vector2i, Terrain.Base]):
	# ... (Function retained as is)
	for cell: Vector2i in block:
		terrain_base_grid[cell] = block[cell]
		terrain_level_grid[cell] = Terrain.Level.EARTH
		occupied_grid[cell] = false
		Navigation.grid[cell] = true

	active_boundary_tiles = _get_terrain_boundary(terrain_level_grid, block.keys(), Terrain.Level.EARTH, Terrain.Level.SEA)
	_update_terrain()

func present_expansion_choices(options: Array[ExpansionChoice]):
	# ... (Function retained as is)
	is_choosing_expansion = true
	current_expansion_options = options
	preview_grid.clear()
	for option: ExpansionChoice in options:
		if option and option.block_data:
			var rand_color: Color = Color(randf(), randf(), randf(), 0.5)
			for world_cell: Vector2i in option.block_data:
				preview_grid[world_cell] = option.block_data[world_cell]
				preview_tint_grid[world_cell] = rand_color
	queue_redraw()
	
func select_expansion(choice_id: int):
	# ... (Function retained as is)
	if not is_choosing_expansion:
		expansion_applied.emit()
		return

	var chosen_option: ExpansionChoice = null
	for option: ExpansionChoice in current_expansion_options:
		if option and option.id == choice_id:
			chosen_option = option
			break
	
	if chosen_option and chosen_option.block_data and not chosen_option.block_data.is_empty():
		apply_expansion_option(chosen_option)
	
	preview_grid.clear()
	is_choosing_expansion = false
	current_expansion_options.clear()
	queue_redraw()
	expansion_applied.emit()
	
func apply_expansion_option(option: ExpansionChoice):
	# ... (Function retained as is)
	expand_by_block(option.block_data)
	if is_choosing_expansion:
		preview_grid.clear()
		is_choosing_expansion = false
		current_expansion_options.clear()

func _update_terrain():
	# ... (Function retained as is)
	shore_boundary_tiles = _get_terrain_boundary(terrain_level_grid, terrain_level_grid.keys(), Terrain.Level.EARTH, Terrain.Level.SEA)
	terrain_changed.emit()
	Navigation.clear_field()
	queue_redraw()

func _update_navigation(affected_cell = null):
	# ... (Function retained as is)
	if affected_cell == null:
		Navigation.grid.clear()
		for cell: Vector2i in terrain_base_grid:
			Navigation.grid[cell] = Terrain.is_navigable(terrain_base_grid[cell]) and (not occupied_grid[cell])
	else:
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

# --- RETAINED DRAWING & HELPER FUNCTIONS ---
func _draw():
	# ... (Function retained as is)
	for cell_pos: Vector2i in terrain_base_grid.keys():
		var rect_position: Vector2 = cell_pos * CELL_SIZE
		var rect = Rect2(rect_position, Vector2(CELL_SIZE, CELL_SIZE))
		var color: Color = Terrain.get_color(terrain_level_grid[cell_pos], terrain_base_grid[cell_pos])
		if active_boundary_tiles.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.SHORE, terrain_base_grid[cell_pos])
		if preview_grid.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.EARTH, preview_grid[cell_pos]).blend(preview_tint_grid[cell_pos])
		draw_rect(rect, color)

func update_adjacencies_around(cell: Vector2i):
	# ... (Function retained as is)
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	if tower_grid.has(cell):
		tower_grid[cell].adjacency_updated.emit(adjacent_towers)
	
	for tower: Tower in adjacent_towers.values():
		var local_adjacencies: Dictionary[Vector2i, Tower] = get_adjacent_towers(tower.tower_position)
		tower.adjacency_updated.emit(local_adjacencies)

func is_occupied(cell: Vector2i) -> bool:
	if occupied_grid.has(cell):
		return occupied_grid[cell]
	else:
		return false

func get_tower_on_tile(cell: Vector2i):
	return tower_grid.get(cell, null)

func get_adjacent_towers(cell: Vector2i) -> Dictionary[Vector2i, Tower]:
	# ... (Function retained as is)
	var output: Dictionary[Vector2i, Tower] = {}
	for dir: Vector2i in DIRS:
		if tower_grid.has(cell + dir):
			output[dir] = tower_grid[cell + dir]
	return output
	
func get_terrain_level(cell: Vector2i) -> Terrain.Level:
	# ... (Function retained as is)
	if terrain_level_grid.has(cell):
		return terrain_level_grid[cell]
	return Terrain.Level.SEA
	
func get_terrain_base(cell : Vector2i) -> Terrain.Base:
	return terrain_base_grid.get(cell, Terrain.Base.EARTH)

# Static position helpers are still useful.
static func position_to_cell(position: Vector2) -> Vector2i:
	return floor(position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
