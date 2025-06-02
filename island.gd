extends Node2D
class_name Island

signal terrain_changed
signal tower_changed(tower_position: Vector2i)

var terrain_grid: Dictionary[Vector2i, Terrain.Base] = {} #primary store for all terrain
var occupied_grid: Dictionary[Vector2i, bool] = {} #whether terrain is occupied or not
var tower_grid: Dictionary[Vector2i, Towers.Type] = {}

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
	for i in 0:
		var unit : Unit = preload("res://Units/Enemies/basic_unit.tscn").instantiate()
		unit.movement_component.position = cell_to_position(active_boundary_tiles.pick_random())
		add_child(unit)
	
func construct_tower(cell: Vector2i, tower_type: Towers.Type):
	var tower: Tower = Towers.get_tower_scene(tower_type).instantiate()
	occupied_grid[cell] = true
	tower_grid[cell] = tower_type
	update_navigation(cell) #update navigation

	add_child(tower)
	tower.tower_position = cell
	terrain_changed.emit()
	tower_changed.emit(cell)

func generate_terrain():
	terrain_grid.clear()
	occupied_grid.clear()
	Navigation.grid.clear()
	#
	for x in range(-HALF, HALF+1):
		for y in range(-HALF, HALF+1):
			terrain_grid[Vector2i(x,y)] = Terrain.Base.SEA
			occupied_grid[Vector2i(x,y)] = false

	#terrain_grid[Vector2i(0,0)] = Terrain.Base.EARTH
	expand_by_block(800)
	expand_by_block(4)
	
	update_terrain()

func update_terrain():
	shore_boundary_tiles = _get_terrain_boundary(terrain_grid, terrain_grid.keys(), Terrain.Base.EARTH, Terrain.Base.SEA)
	terrain_changed.emit()
	Navigation.clear_field()
	
	queue_redraw()
	
func update_navigation(affected_cell = null):
	if affected_cell == null: 
		Navigation.grid.clear()
	
		for cell: Vector2i in terrain_grid:
			Navigation.grid[cell] = Terrain.is_navigable(terrain_grid[cell]) and (not occupied_grid[cell])
			#navigable grids have to both be of navigable terrain and are unoccupied
	else: #affected_cell is vector2i, update is targeting a specific cell
		Navigation.grid[affected_cell] = Terrain.is_navigable(terrain_grid[affected_cell]) and (not occupied_grid[affected_cell])
	Navigation.clear_field()
		
func _get_terrain_boundary(_terrain_grid: Dictionary[Vector2i, Terrain.Base] = terrain_grid, scope: Array[Vector2i] = _terrain_grid.keys(), terrain: Terrain.Base = Terrain.Base.SHORE, rim = null) -> Array[Vector2i]:
	var boundary_tiles: Array[Vector2i] = []
	# 4-way connectivity; add diagonals if you want 8-way

	for cell: Vector2i in scope:
		if _terrain_grid[cell] != terrain:
			continue
		# check neighbors
		for direction: Vector2i in DIRS:
			var neighbor: Vector2i = cell + direction
			# if neighbor is missing or not earth, this is a boundary tile
			if rim != null: #specified rim terrain
				if _terrain_grid[neighbor] == rim:
					boundary_tiles.append(cell)
					break
			elif not _terrain_grid.has(neighbor) or _terrain_grid[neighbor] != terrain:
				boundary_tiles.append(cell)
				break

	return boundary_tiles

func expand_by_block(block_size: int) -> void:
	if shore_boundary_tiles.is_empty():
		shore_boundary_tiles = [ Vector2i.ZERO ] #assume we're starting from nothing, build from origin

	# 1) pick a random starting shore tile
	var start: Vector2i = shore_boundary_tiles[randi_range(0, shore_boundary_tiles.size() - 1)]

	# 2) search along the current boundary to collect 'block_size' tiles
	var to_visit: Array[Vector2i] = [ start ]
	var to_visit_evaluation: Dictionary[Vector2i, float] = { start: start.length_squared() + 0.0 }
	var visited: Dictionary[Vector2i, bool] = {}
	var block: Array[Vector2i] = []

	while to_visit.size() > 0 and block.size() < block_size:
		var cell: Vector2i = to_visit[0]
		for cell_candidate: Vector2i in to_visit: #search for candidate with lowest heuristic
			if visited.has(cell_candidate):
				continue
			if to_visit_evaluation[cell_candidate] < to_visit_evaluation[cell]:
				cell = cell_candidate

		if terrain_grid[cell] == Terrain.Base.SEA:
			block.append(cell) #if cell is valid (ie in the sea) add to uplift block

		for d: Vector2i in DIRS: #search around current cell
			var nbr: Vector2i = cell + d
			
			if terrain_grid[nbr] != Terrain.Base.SEA:
				continue #cell invalid for uplift
			if visited.has(nbr):
				continue
				
			if not to_visit_evaluation.has(nbr): #optimise for tiles close to global origin and block origin.
				to_visit_evaluation[nbr] = nbr.length_squared() + (nbr - cell).length_squared() * 5.0 + randf() * 5.0
			to_visit.append(nbr)
			
		to_visit.erase(cell)
		visited[cell] = true

	# 3) Convert that block of shore → earth
	for cell: Vector2i in block:
		terrain_grid[cell] = Terrain.Base.EARTH
		Navigation.grid[cell] = true

	# 4) Refresh everything
	active_boundary_tiles = _get_terrain_boundary(terrain_grid, block, Terrain.Base.EARTH, Terrain.Base.SEA)
	update_terrain()

func _draw():
	for cell_pos in terrain_grid.keys():
		var rect_position: Vector2 = cell_pos * CELL_SIZE
		var rect = Rect2(rect_position, Vector2(CELL_SIZE, CELL_SIZE))
		var color: Color = Terrain.get_color(terrain_grid[cell_pos])
		draw_rect(rect, color)
