extends Node2D
class_name Island

@warning_ignore_start("unused_signal")
signal terrain_changed
signal tower_created(tower: Tower)
signal tower_changed(tower_position: Vector2i) # this signal fires after adjacencies, navigation, etc. has been resolved
signal expansion_applied
signal navigation_grid_updated

# --- grids & state (data container role) ---
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {}
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []

var _preview_choices: Dictionary[int, ExpansionChoice] = {}
var _highlighted_choice_id: int = -1

#lookup caches
var _towers_by_type: Dictionary[Towers.Type, Array] = {} ##Towers.Type -> Array[Tower]

# --- constants ---
const CELL_SIZE: int = 10
const DIRS: Array[Vector2i] = [ Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) ]
#configuration
const _DEBUG_SHOW_NAVCOST: bool = false

func _ready():
	#register self with services that need references
	PowerService.register_island(self)
	
	# initial terrain generation
	var starting_block: Dictionary = ExpansionService.generate_initial_island_block(self, 50)
	# 3. delegate application of the block to the TerrainService
	TerrainService.expand_island(self, starting_block)
	
	# 4. place the player's core tower
	construct_tower_at(Vector2i.ZERO, Towers.Type.PLAYER_CORE) #NOTE: this must come first (id = 0)
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
		tower_grid[cell].level += 1
		return true
	
	if TerrainService.is_area_constructable(self, cell, tower_type):
		construct_tower_at(cell, tower_type, facing)
		return true
		
	return false

# public APIs (used by TerrainService)
func construct_tower_at(cell: Vector2i, tower_type: Towers.Type, tower_facing: Tower.Facing = Tower.Facing.UP, initial_state: Dictionary = {}) -> Tower:
	print("Construct tower of: ", Towers.Type.keys()[tower_type])
	var tower: Tower = Towers.create_tower(tower_type)
	var tower_size: Vector2i = Vector2i(Vector2(Towers.get_tower_size(tower_type)).rotated(tower_facing * 0.5 * PI))
	
	tower.size = tower_size
	for x: int in tower_size.x:
		for y: int in tower_size.y:
			tower_grid[cell + Vector2i(x,y)] = tower
	tower.facing = tower_facing
	tower.tower_position = cell
	tower.set_initial_behaviour_state(initial_state)
	tower.add_to_group(References.TOWER_GROUP)
	add_child(tower)
	#NOTE: tower.died cannot be used here due to the ruins system
	tower.tree_exiting.connect(_on_tower_destroyed.bind(tower), CONNECT_ONE_SHOT)

	Player.add_to_used_capacity(Towers.get_tower_capacity(tower_type))
	_update_adjacencies_around(cell)
	update_navigation_grid()
	
	# --- apply terrain modifiers ---
	# after the tower is created and has its components, check the terrain it's on
	if is_instance_valid(tower.modifiers_component):
		# get the terrain base at the tower's location
		var terrain_base: Terrain.Base = self.terrain_base_grid.get(cell, Terrain.Base.EARTH)
		# get the list of modifier prototypes associated with this terrain
		var modifier_prototypes: Array[ModifierDataPrototype] = Terrain.get_modifiers_for_base(terrain_base)
		
		for proto: ModifierDataPrototype in modifier_prototypes:
			var new_modifier: Modifier = proto.generate_modifier()
			# add the modifier as a PERMANENT modifier, as it's tied to the static world state
			tower.modifiers_component.add_permanent_modifier(new_modifier)
			
	#insert the new tower in the lookup table
	if not _towers_by_type.has(tower.type):
		_towers_by_type[tower.type] = []
	_towers_by_type[tower.type].append(tower)

	tower_created.emit(tower)
	tower_changed.emit(cell)
	return tower

func update_navigation_grid() -> void:
	Navigation.grid.clear()

	for cell: Vector2i in terrain_base_grid:
		var is_navigable: bool = Terrain.is_navigable(terrain_base_grid[cell])
		var is_occupied: bool = tower_grid.has(cell)
		if Terrain.is_navigable(terrain_base_grid[cell]):
			if is_occupied:
				Navigation.grid[cell] = Towers.get_tower_navcost(tower_grid[cell].type)
			else:
				Navigation.grid[cell] = 0

	Navigation.clear_field()
	
	navigation_grid_updated.emit()
	queue_redraw()

func update_shore_boundary() -> void: #used for expansion
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
		
#signal handlers
func _on_tower_destroyed(tower: Tower):
	var cell: Vector2i = tower.tower_position
	#clear tower grid
	for local_cell: Vector2i in tower.get_occupied_cells():
		tower_grid.erase(local_cell)
		_update_adjacencies_around(cell) #update adjacencies
	#update capacity, caches, navigation
	Player.remove_from_used_capacity(Towers.get_tower_capacity(tower.type))
	update_navigation_grid()
	_towers_by_type[tower.type].erase(tower)
	tower_changed.emit(cell)

func _update_adjacencies_around(cell: Vector2i):
	# ... (Function retained as is)
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	if tower_grid.has(cell):
		tower_grid[cell].adjacency_updated.emit(adjacent_towers)
	
	for tower: Tower in adjacent_towers.values():
		var local_adjacencies: Dictionary[Vector2i, Tower] = get_adjacent_towers(tower.tower_position)
		tower.adjacency_updated.emit(local_adjacencies)

# --- updated drawing logic ---
func _draw() -> void:
	# 1. draw terrain outlines
	# --- 1. identify the unique set of vertices to draw on ---
	var vertices_to_draw: Dictionary[Vector2i, bool] = {} # use a dictionary as a hash set for automatic deduplication

	# iterate through every cell that is part of the terrain
	for cell_pos: Vector2i in terrain_base_grid:
		# for each cell, we are interested in its four corner vertices.
		# by adding all four to a dictionary, we ensure that shared vertices
		# between adjacent cells are only stored once.
		vertices_to_draw[cell_pos] = true                        # top-left corner
		vertices_to_draw[cell_pos + Vector2i(1, 0)] = true       # top-right corner
		vertices_to_draw[cell_pos + Vector2i(0, 1)] = true       # bottom-left corner
		vertices_to_draw[cell_pos + Vector2i(1, 1)] = true       # bottom-right corner

	# --- 2. load the texture resource once ---
	var cross_texture: Texture2D = preload("res://Assets/grid_outline.svg")
	var cross_color: Color = Color.WHITE # define a base color for the crosses

	# --- 3. render one cross at each unique vertex ---
	for vertex_pos: Vector2i in vertices_to_draw:
		# calculate the world position of the vertex (the grid line intersection)
		var world_pos: Vector2 = Vector2(vertex_pos * CELL_SIZE) - Vector2.ONE * CELL_SIZE * 0.5
		
		# calculate the rect needed to draw the texture *centered* on the vertex.
		# we start at the world position and subtract half the texture's size.
		var centered_rect := Rect2(world_pos, Vector2.ONE * CELL_SIZE)
		
		# draw the texture at the calculated position
		draw_texture_rect(cross_texture, centered_rect.grow(-4.0), false, cross_color)
	
	# 2. draw icons
	for cell_pos: Vector2i in terrain_base_grid:
		draw_texture_rect(Terrain.get_icon(terrain_base_grid[cell_pos]), Rect2(cell_pos * CELL_SIZE, Vector2.ONE * CELL_SIZE).grow(-4.0), false)
	
	# 3. draw previews on top
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
		
	#3 debug:
	if _DEBUG_SHOW_NAVCOST:
		for cell: Vector2i in Navigation.grid:
			var score: int = Navigation.grid[cell]
			draw_rect(Rect2(cell * CELL_SIZE, Vector2.ONE * CELL_SIZE), Color(score * 0.05, score * 0.05, score * 0.05))

#static data access functions
func get_towers_by_type(type: Towers.Type) -> Array:
	return _towers_by_type.get(type, [])

func get_tower_on_tile(cell: Vector2i):
	return tower_grid.get(cell, null)

func get_adjacent_towers(cell: Vector2i) -> Dictionary[Vector2i, Tower]:
	#NOTE: tower.get_adjacent_towers() should preferably be used instead if the Tower reference is first known
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
static func position_to_cell(_position: Vector2) -> Vector2i:
	return floor(_position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
