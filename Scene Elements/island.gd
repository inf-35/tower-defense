extends Node2D
class_name Island

# --- RETAINED SIGNALS ---
signal terrain_changed
signal expansion_applied

# --- grids & state (data container role) ---
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {}
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []
var _preview_grid: Dictionary[Vector2i, Dictionary] = {}
var _preview_tint_grid: Dictionary[Vector2i, Color] = {}

# --- constants ---
const CELL_SIZE: int = 13
const DIRS: Array[Vector2i] = [ Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) ]

func _ready():
	#register self with services that need references
	PowerService.register_island(self)
	
	# initial terrain generation
	var starting_block: Dictionary = ExpansionService._generate_block(self, 36)
	
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

# --- internal construction & update logic ---
# this function is now called by services or the public API
func construct_tower_at(cell: Vector2i, tower_type: Towers.Type, tower_facing: Tower.Facing = Tower.Facing.UP) -> Tower:
	var tower: Tower = Towers.create_tower(tower_type)
	tower_grid[cell] = tower
	
	tower.facing = tower_facing
	tower.tower_position = cell
	add_child(tower)

	tower.died.connect(_on_tower_destroyed.bind(tower), CONNECT_ONE_SHOT)
	
	# if this is a breach, register it with the spawn service
	if tower_type == Towers.Type.BREACH_SEED or tower_type == Towers.Type.BREACH:
		SpawnPointService.register_breach(tower)

	Player.add_to_used_capacity(Towers.get_tower_capacity(tower_type))
	_update_adjacencies_around(cell)
	update_navigation_grid()
	return tower

func _on_tower_destroyed(tower: Tower):
	var cell: Vector2i = tower.tower_position
	if tower_grid.has(cell):
		# Clean up grids and state
		tower_grid.erase(cell)
		Player.remove_from_used_capacity(Towers.get_tower_capacity(tower.type))
		# Update neighbors
		_update_adjacencies_around(cell)
		update_navigation_grid()
		
func update_navigation_grid() -> void:
	Navigation.grid.clear()
	for cell: Vector2i in terrain_base_grid:
		var is_navigable: bool = Terrain.is_navigable(terrain_base_grid[cell])
		var is_occupied: bool = tower_grid.has(cell)
		Navigation.grid[cell] = is_navigable and not is_occupied
	Navigation.clear_field()
#not used
func update_shore_boundary() -> void:
	# simplified logic to find all land tiles adjacent to nothing
	shore_boundary_tiles.clear()
	for cell: Vector2i in terrain_base_grid:
		for dir: Vector2i in DIRS:
			if not terrain_base_grid.has(cell + dir):
				shore_boundary_tiles.append(cell)
				break

func update_previews(preview_data: Dictionary, tint_data: Dictionary) -> void:
	_preview_grid = preview_data
	_preview_tint_grid = tint_data
	queue_redraw()

# --- RETAINED DRAWING & HELPER FUNCTIONS ---
func _draw():
	# ... (Function retained as is)
	for cell_pos: Vector2i in terrain_base_grid.keys():
		var rect_position: Vector2 = cell_pos * CELL_SIZE
		var rect = Rect2(rect_position, Vector2(CELL_SIZE, CELL_SIZE))
		var color: Color = Terrain.get_color(terrain_base_grid[cell_pos])
		if _preview_grid.has(cell_pos):
			color = color.blend(_preview_tint_grid[cell_pos])
		draw_rect(rect, color)

func _update_adjacencies_around(cell: Vector2i):
	# ... (Function retained as is)
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	if tower_grid.has(cell):
		tower_grid[cell].adjacency_updated.emit(adjacent_towers)
	
	for tower: Tower in adjacent_towers.values():
		var local_adjacencies: Dictionary[Vector2i, Tower] = get_adjacent_towers(tower.tower_position)
		tower.adjacency_updated.emit(local_adjacencies)

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

# Static position helpers are still useful.
static func position_to_cell(position: Vector2) -> Vector2i:
	return floor(position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
