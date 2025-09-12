extends Node2D
class_name Island

# --- RETAINED SIGNALS ---
signal terrain_changed
signal expansion_applied

# --- grids & state (data container role) ---
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {}
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []
var _preview_grid: Dictionary[Vector2i, Terrain.CellData] = {}
var _preview_tint_grid: Dictionary[Vector2i, Color] = {}

var _preview_choices: Dictionary[int, ExpansionChoice] = {}
var _highlighted_choice_id: int = -1

# --- constants ---
const CELL_SIZE: int = 10
const DIRS: Array[Vector2i] = [ Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) ]

func _ready():
	#register self with services that need references
	PowerService.register_island(self)
	
	# initial terrain generation
	var starting_block: Dictionary = ExpansionService.generate_initial_island_block(self, 36)
	# 3. delegate application of the block to the TerrainService
	TerrainService.expand_island(self, starting_block)
	
	# 4. place the player's core tower
	construct_tower_at(Vector2i.ZERO, Towers.Type.PLAYER_CORE)
	update_shore_boundary()
	update_navigation_grid()
	queue_redraw()
	
	# --- public api / request handlers ---

# this is the main entry point for player actions like building or selling
func request_tower_placement(cell: Vector2i, tower_type: Towers.Type, facing: Tower.Facing) -> bool:
	if tower_grid.has(cell):
		# handle selling
		if tower_type == Towers.Type.VOID:
			tower_grid[cell].sell()
			return true
		# handle upgrading (can be expanded)
		return false
	
	if TerrainService.is_cell_constructable(self, cell, tower_type):
		construct_tower_at(cell, tower_type, facing)
		return true
		
	return false

# public APIs (used by TerrainService)
func construct_tower_at(cell: Vector2i, tower_type: Towers.Type, tower_facing: Tower.Facing = Tower.Facing.UP, initial_state: Dictionary = {}) -> Tower:
	print("Construct tower of: ", Towers.Type.keys()[tower_type])
	var tower: Tower = Towers.create_tower(tower_type)
	tower_grid[cell] = tower
	tower.facing = tower_facing
	tower.tower_position = cell
	tower.set_initial_behaviour_state(initial_state)
	add_child(tower)
	
	tower.died.connect(_on_tower_destroyed.bind(tower), CONNECT_ONE_SHOT)

	Player.add_to_used_capacity(Towers.get_tower_capacity(tower_type))
	_update_adjacencies_around(cell)
	update_navigation_grid()
	return tower

func update_navigation_grid() -> void:
	Navigation.grid.clear()
	for cell: Vector2i in terrain_base_grid:
		var is_navigable: bool = Terrain.is_navigable(terrain_base_grid[cell])
		var is_occupied: bool = tower_grid.has(cell)
		Navigation.grid[cell] = is_navigable and not is_occupied
	Navigation.clear_field()

func update_shore_boundary() -> void: #DEPRECATED
	# simplified logic to find all land tiles adjacent to nothing
	shore_boundary_tiles.clear()
	for cell: Vector2i in terrain_base_grid:
		for dir: Vector2i in DIRS:
			if not terrain_base_grid.has(cell + dir):
				shore_boundary_tiles.append(cell)
				break

func update_previews(choices_by_id: Dictionary[int, ExpansionChoice]) -> void:
	_preview_choices = choices_by_id
	_highlighted_choice_id = -1 # reset highlight
	queue_redraw()

# called by ExpansionService to tell the island which choice to highlight
func set_highlighted_choice(choice_id: int = -1) -> void:
	if _highlighted_choice_id != choice_id:
		_highlighted_choice_id = choice_id
		queue_redraw()

# --- updated drawing logic ---
func _draw() -> void:
	# 1. draw base terrain
	for cell_pos: Vector2i in terrain_base_grid:
		var rect := Rect2(cell_pos * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
		var color := Terrain.get_color(terrain_base_grid[cell_pos])
		draw_rect(rect, color)
	
	# 2. draw previews on top
	for choice_id: int in _preview_choices:
		var choice: ExpansionChoice = _preview_choices[choice_id]
		var is_highlighted: bool = (choice_id == _highlighted_choice_id)
		
		for cell_pos: Vector2i in choice.block_data:
			var cell_data: Terrain.CellData = choice.block_data[cell_pos]
			var rect := Rect2(cell_pos * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
			
			# determine color and draw the base preview
			var base_color := Terrain.get_color(cell_data.terrain)
			var preview_color := base_color.lightened(0.2) if is_highlighted else base_color
			draw_rect(rect, preview_color)

			# draw a highlight border if this choice is hovered
			if is_highlighted:
				draw_rect(rect, Color.WHITE, false, 2.0)

			# draw tower previews (e.g., for breach seeds)
			if cell_data.feature != Towers.Type.VOID:
				var center: Vector2 = Vector2(cell_pos * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
				var tower_color: Color = Color.CRIMSON if is_highlighted else Color.DARK_RED
				draw_circle(center, CELL_SIZE * 0.4, tower_color)

func _on_tower_destroyed(tower: Tower):
	var cell: Vector2i = tower.tower_position
	if tower_grid.has(cell):
		# Clean up grids and state
		tower_grid.erase(cell)
		Player.remove_from_used_capacity(Towers.get_tower_capacity(tower.type))
		# Update neighbors
		_update_adjacencies_around(cell)
		update_navigation_grid()

func _update_adjacencies_around(cell: Vector2i):
	# ... (Function retained as is)
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	if tower_grid.has(cell):
		tower_grid[cell].adjacency_updated.emit(adjacent_towers)
	
	for tower: Tower in adjacent_towers.values():
		var local_adjacencies: Dictionary[Vector2i, Tower] = get_adjacent_towers(tower.tower_position)
		tower.adjacency_updated.emit(local_adjacencies)

#static data access functions
func get_tower_on_tile(cell: Vector2i):
	return tower_grid.get(cell, null)

func get_adjacent_towers(cell: Vector2i) -> Dictionary[Vector2i, Tower]:
	# ... (Function retained as is)
	var output: Dictionary[Vector2i, Tower] = {}
	for dir: Vector2i in DIRS:
		if tower_grid.has(cell + dir):
			output[dir] = tower_grid[cell + dir]
	return output
	
func get_terrain_base(cell : Vector2i) -> Terrain.Base:
	return terrain_base_grid.get(cell, Terrain.Base.EARTH)
	
# calculates the total bounding box of all existing terrain tiles.
func get_island_bounds() -> Rect2:
	if terrain_base_grid.is_empty():
		return Rect2(global_position, Vector2.ONE * CELL_SIZE)

	# find the min and max cell coordinates
	var min_coord := Vector2i(INF, INF)
	var max_coord := Vector2i(-INF, -INF)
	for cell: Vector2i in terrain_base_grid.keys():
		min_coord.x = min(min_coord.x, cell.x)
		min_coord.y = min(min_coord.y, cell.y)
		max_coord.x = max(max_coord.x, cell.x)
		max_coord.y = max(max_coord.y, cell.y)

	# convert the cell-based rect to a world-coordinate rect
	var top_left_pos: Vector2 = Island.cell_to_position(min_coord)
	var size_in_cells: Vector2i = (max_coord - min_coord) + Vector2i.ONE
	var size_in_pixels: Vector2 = Vector2(size_in_cells) * CELL_SIZE
	
	return Rect2(top_left_pos, size_in_pixels)

# static position helpers
static func position_to_cell(position: Vector2) -> Vector2i:
	return floor(position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
