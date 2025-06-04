extends Node2D
class_name Island

signal terrain_changed
signal tower_changed(tower_position: Vector2i)

var terrain_level_grid: Dictionary[Vector2i, Terrain.Level] = {}
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {} # Store for Terrain.Base
var occupied_grid: Dictionary[Vector2i, bool] = {} # Whether terrain is occupied or not
var tower_grid: Dictionary[Vector2i, Tower] = {}

var shore_boundary_tiles: Array[Vector2i] = []
var active_boundary_tiles: Array[Vector2i] = [ Vector2i.ZERO ]

const CELL_SIZE: int = 10
const GRID_SIZE: int = 50
const HALF: int = GRID_SIZE * 0.5
const SHALLOWS_RADIUS_SQUARED: float = (HALF * 0.0) ** 2
const ISLAND_RADIUS_SQUARED: float = (HALF * 0.2) ** 2

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

func spawn_enemies(wave: int):
	if active_boundary_tiles.is_empty():
		push_warning("No boundary available for spawning!")
		return

	for i in 5:
		var unit : Unit = preload("res://Units/Enemies/basic_unit.tscn").instantiate()
		add_child(unit)
		unit.movement_component.position = cell_to_position(active_boundary_tiles.pick_random())

func construct_tower(cell: Vector2i, tower_type: Towers.Type):
	var tower: Tower = Towers.get_tower_scene(tower_type).instantiate()
	occupied_grid[cell] = true
	_update_navigation(cell) # Update navigation
	tower_grid[cell] = tower

	tower.tower_data # Necessary: Evil pre-resolution hotfix
	add_child(tower)

	tower.tower_position = cell
	terrain_changed.emit()
	tower_changed.emit(cell)

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

	expand_by_block(40)
	expand_by_block(4)
	
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

# ... (rest of your Island class code below, including _draw, get_adjacent_towers etc.)
func expand_by_block(block_size: int) -> void:
	var block: Dictionary[Vector2i, Terrain.Base] = TerrainGen.generate_block(block_size)
	for cell: Vector2i in block:
		terrain_base_grid[cell] = block[cell]
		terrain_level_grid[cell] = Terrain.Level.EARTH
		Navigation.grid[cell] = true

	active_boundary_tiles = _get_terrain_boundary(terrain_level_grid, block.keys(), Terrain.Level.EARTH, Terrain.Level.SEA)
	_update_terrain()
	
var preview_grid: Dictionary[Vector2i, Terrain.Base] = {} #for preview terrain

func _draw():
	for cell_pos: Vector2i in terrain_base_grid.keys():
		var rect_position: Vector2 = cell_pos * CELL_SIZE
		var rect = Rect2(rect_position, Vector2(CELL_SIZE, CELL_SIZE))
		var color: Color = Terrain.get_color(terrain_level_grid[cell_pos], terrain_base_grid[cell_pos])
		if preview_grid.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.EARTH, preview_grid[cell_pos])
		if active_boundary_tiles.has(cell_pos):
			color = Terrain.get_color(Terrain.Level.SHORE,terrain_base_grid[cell_pos])
		draw_rect(rect, color)

# "Public" helper functions
func get_adjacent_towers(cell: Vector2i) -> Array[Tower]:
	var output: Array[Tower] = []
	for dir: Vector2i in DIRS:
		if not tower_grid.has(cell + dir):
			continue
		output.append(tower_grid[cell + dir])

	return output

func get_terrain_base(cell: Vector2i) -> Terrain.Base:
	return terrain_base_grid[cell]

func get_terrain_level(cell: Vector2i) -> Terrain.Level:
	return terrain_level_grid[cell]
