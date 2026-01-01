extends Node2D
class_name Island

@warning_ignore_start("unused_signal")
signal terrain_changed
signal tower_created(tower: Tower) ##this signal fires when a tower is created.
signal tower_changed(tower_position: Vector2i) ##fires when a tower is created, destroyed or moved. fires after tower_created
signal expansion_applied
signal navigation_grid_updated

# --- attachments ---
@export var terrain_renderer: TerrainRenderer
@export var preview_renderer: TerrainRenderer

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
	Phases.start_game()
	#register self with services that need references
	PowerService.register_island(self)
	
	# initial terrain generation
	var starting_block: Dictionary = ExpansionService.generate_initial_island_block(self, 80)
	# delegate application of the block to the TerrainService
	TerrainService.expand_island(self, starting_block)
	
	# place the player's core tower
	var keep: Tower = construct_tower_at(Vector2i.ZERO, Towers.Type.PLAYER_CORE) #NOTE: this must come first (id = 0)
	References.keep = keep
	UI.update_inspector_bar.emit(keep)
	
	update_shore_boundary()
	update_navigation_grid()
	queue_redraw()

func _setup_preview_renderer() -> void:
	preview_renderer.cell_size = CELL_SIZE
	preview_renderer.max_gradient_depth = 3.0 # tighter gradient for previews
	preview_renderer.draw_background = false # we just want the outline overlay
	
	# add to scene (z-index higher so it draws on top)
	add_child(preview_renderer)
	preview_renderer.z_index = 10 
	
	# manually override the material to use the sketch shader
	# wait for the node to be ready or force setup
	preview_renderer._setup_visuals()
	
	var sketch_mat := ShaderMaterial.new()
	sketch_mat.shader = preload("res://Shaders/sketch_terrain.gdshader")
	
	# re-use noise from main renderer if possible, or create new
	var noise = FastNoiseLite.new()
	noise.frequency = 0.02
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	
	sketch_mat.set_shader_parameter("grid_data_texture", preview_renderer._grid_texture)
	sketch_mat.set_shader_parameter("noise_texture", noise_tex)
	sketch_mat.set_shader_parameter("outline_color", Color(0, 0, 0, 0.8))
	sketch_mat.set_shader_parameter("fill_color", Color(1, 1, 1, 0.2))
	
	preview_renderer._terrain_rect.material = sketch_mat
	
# --- public api / request handlers ---
# this is the main entry point for player actions like building or selling
func request_tower_placement(cell: Vector2i, tower_type: Towers.Type, facing: Tower.Facing) -> bool:
	if tower_grid.has(cell):
		# handle selling
		if tower_type == Towers.Type.VOID:
			tower_grid[cell].sell()
			return true
		return true
	
	if TerrainService.is_area_constructable(self, facing, cell, tower_type):
		construct_tower_at(cell, tower_type, facing)
		return true
		
	return false

# public APIs (used by TerrainService)
func construct_tower_at(cell: Vector2i, tower_type: Towers.Type, tower_facing: Tower.Facing = Tower.Facing.UP, initial_state: Dictionary = {}) -> Tower:
	print("Construct tower of: ", Towers.Type.keys()[tower_type])
	var tower: Tower = Towers.create_tower(tower_type)
	var rotated_size: Vector2i = Towers.get_tower_size(tower_type)
	if (tower_facing as int) % 2 != 0:
		rotated_size = Vector2i(rotated_size.y, rotated_size.x)
	tower.size = rotated_size
	for x: int in tower.size.x:
		for y: int in tower.size.y:
			tower_grid[cell + Vector2i(x,y)] = tower
	tower.facing = tower_facing
	tower.tower_position = cell
	tower.set_initial_behaviour_state(initial_state)
	tower.add_to_group(References.TOWER_GROUP)
	
	tower.died.connect(func(_hit_report_data): update_navigation_grid()) #as unit becoems non-blocking upon unit death
	tower.tree_exiting.connect(_on_tower_destroyed.bind(tower), CONNECT_ONE_SHOT)
	
	add_child(tower)

	Player.add_to_used_capacity(Towers.get_tower_capacity(tower_type))
	_update_adjacencies_around(cell)
	update_navigation_grid()
			
	#insert the new tower in the lookup table
	if not _towers_by_type.has(tower.type):
		_towers_by_type[tower.type] = []
	_towers_by_type[tower.type].append(tower)

	tower_created.emit(tower)
	tower_changed.emit(cell)
	return tower

# request_upgrade checks funds/limits, then calls upgrade_tower
func request_upgrade(old_tower: Tower, new_type: Towers.Type) -> bool:
	if not is_instance_valid(old_tower): return false
	if old_tower.abstractive: return false
	if old_tower.current_state == Tower.State.RUINED: return false

	# check limits (if new tower type is restricted)
	if not TerrainService.is_area_constructable(self, old_tower.facing, old_tower.tower_position, new_type, true, old_tower):
		return false

	upgrade_tower(old_tower, new_type)
	return true
	
func upgrade_tower(old_tower: Tower, new_type: Towers.Type) -> void:
	var cell: Vector2i = old_tower.tower_position
	var facing: Tower.Facing = old_tower.facing
	
	# construct new tower
	var new_tower: Tower = construct_tower_at(cell, new_type, facing)
	
	# stat handover (hp)
	if is_instance_valid(new_tower.health_component) and is_instance_valid(old_tower.health_component):
		var damage: float = old_tower.health_component.max_health - old_tower.health_component.health
		new_tower.health_component.health -= damage

	# event handover (effects & behaviors & globals)
	var evt = GameEvent.new()
	evt.event_type = GameEvent.EventType.REPLACED
	evt.data = UnitReplacedData.new(old_tower, new_tower)
	# trigger local Components (Effects/Behaviors transfer state)
	old_tower.on_event.emit(evt)
	
	# cleanup old tower
	old_tower.queue_free() #(automatically cleans up tower_grid)
	
	## Visual Feedback
	#VFXManager.play_vfx(ID.Particles.CONSTRUCTION_PUFF, new_tower.global_position, Vector2.UP)

func update_navigation_grid() -> void:
	Navigation.grid.clear()

	for cell: Vector2i in terrain_base_grid:
		var is_navigable: bool = Terrain.is_navigable(terrain_base_grid[cell])
		var is_occupied: bool = tower_grid.has(cell)
		if Terrain.is_navigable(terrain_base_grid[cell]):
			if is_occupied and tower_grid[cell].blocking:
				Navigation.grid[cell] = tower_grid[cell].get_navcost_for_cell(cell)
			else:
				Navigation.grid[cell] = Navigation.BASE_COST

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
	
	preview_renderer.clear_decorations() #clear previous tower previews
	
	# by default, show ALL choices as a faint outline
	var all_preview_cells: Array[Vector2i] = []
	for choice in _preview_choices.values():
		all_preview_cells.append_array(choice.block_data.keys())
		
	preview_renderer.reset_grid(all_preview_cells)
	
	# set to "passive" style
	preview_renderer.set_color_param("outline_color", Color(0, 0, 0, 0.4)) # gray/faint
	preview_renderer.set_color_param("fill_color", Color(1, 1, 1, 0.1))

# called by ExpansionService to tell the island which choice to highlight
func set_highlighted_choice(choice_id: int = -1) -> void:
	if _highlighted_choice_id == choice_id:
		return
		
	_highlighted_choice_id = choice_id
	preview_renderer.clear_decorations() #clear previous tower previews
	
	if choice_id == -1: #nothing is selected!
		# revert to showing all choices faintly
		var all_cells: Array[Vector2i] = []
		for choice in _preview_choices.values():
			all_cells.append_array(choice.block_data.keys())
		preview_renderer.reset_grid(all_cells)
		preview_renderer.set_color_param("outline_color", Color(0.16, 0.16, 0.16, 0.4))
		preview_renderer.set_color_param("fill_color", Color(1, 1, 1, 0.1))
		
		#stamp all features from all choices
		for local_choice_id: int in _preview_choices:
			var choice: ExpansionChoice = _preview_choices[local_choice_id]
			for cell: Vector2i in choice.block_data:
				var cell_data: Terrain.CellData = choice.block_data[cell]
				if cell_data.feature != Towers.Type.VOID:
					preview_renderer.set_preview_feature(cell, cell_data.feature)
	
	elif _preview_choices.has(choice_id):
		# show ONLY the highlighted choice, with strong distinct style
		var active_choice: ExpansionChoice = _preview_choices[choice_id]
		var cells: Array[Vector2i] = []
		cells.append_array(active_choice.block_data.keys())
		
		preview_renderer.reset_grid(cells)
		preview_renderer.set_color_param("outline_color", Color(0.27, 0.27, 0.27, 0.576)) # solid black
		preview_renderer.set_color_param("fill_color", Color(0.4, 0.8, 0.6, 0.0)) # slight green tint
		
		for cell: Vector2i in active_choice.block_data:
			var cell_data: Terrain.CellData = active_choice.block_data[cell]
			
			if cell_data.feature != Towers.Type.VOID:
				preview_renderer.set_preview_feature(cell, cell_data.feature)
	
#signal handlers
func _on_tower_destroyed(tower: Tower):
	var cell: Vector2i = tower.tower_position
	#clear tower grid
	for local_cell: Vector2i in tower.get_occupied_cells():
		if not tower_grid[local_cell] == tower: #dont clear other towers' cells (i.e. upgrades)
			continue
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
