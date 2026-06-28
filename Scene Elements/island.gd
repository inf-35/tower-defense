extends Node2D
class_name Island

@warning_ignore_start("unused_signal")
signal terrain_changed
signal tower_created(tower: Tower) ##this signal fires when a tower is created.
signal tower_changed(tower_position: Vector2i) ##fires when a tower is created, destroyed or moved. fires after tower_created
signal island_changed ##fires when anything changes
signal expansion_applied
signal navigation_grid_updated

#--- attachments ---
@export var terrain_renderer: TerrainRenderer
@export var preview_renderer: TerrainRenderer
@export var lake_preview_renderer: TerrainRenderer

#--- services ---
var expansion_service: ExpansionService
var topology_service: TowerTopologyService

#--- grids & state (data container role) ---
var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = {}
var tower_grid: Dictionary[Vector2i, Tower] = {}
var lake_seed: int = 0
var lake_cells: Dictionary[Vector2i, bool] = {}
var _ruin_sites: Dictionary[Vector2i, bool] = {}

var shore_boundary_tiles: Array[Vector2i] = []

var _preview_choices: Dictionary[int, ExpansionChoice] = {}
var _highlighted_choice_id: int = -1

#lookup caches
var _towers_by_type: Dictionary[Towers.Type, Array] = {} ##towers.type -> array[tower]

#--- constants ---
const CELL_SIZE: int = 10
const DIRS: Array[Vector2i] = [ Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) ]
#configuration
const _DEBUG_SHOW_NAVCOST: bool = false
const LAKE_FIELD_RADIUS: int = 90
const LAKE_PREVIEW_MARGIN: int = 18
const LAKE_SAFE_RADIUS: int = 5
const LAKE_NOISE_FREQUENCY: float = 0.15
const LAKE_NOISE_OCTAVES: int = 1
const LAKE_THRESHOLD: float = 0.68
const LAKE_WARP_FREQUENCY: float = 0.015
const LAKE_WARP_STRENGTH: float = 0.0
const LAKE_MIN_NEIGHBORS: int = 2
const RUIN_MIN_SPACING_RATIO: float = 0.8
const RUIN_ATTEMPTS_PER_SITE: int = 20

@export var ruin_average_spacing: float = 10.0 ##average tile spacing used when pregenerating ruin sites across the unexplored field

func _enter_tree() -> void:
	Run.begin_run(self)

func _ready() -> void:
	Run.phases.in_game = true

	terrain_changed.connect(func(): island_changed.emit())
	tower_changed.connect(func(tower_change): island_changed.emit())

	expansion_service = ExpansionService.new()
	topology_service = TowerTopologyService.new(self)
	add_child.call_deferred(expansion_service)
	_show_loading("Preparing island...", 0.0)

	_boot_game.call_deferred()
	#generate_new_island is triggered by the run phase controller

func _boot_game() -> void:
	await Run.phases.start_game(_set_loading_status)
	await Run.finalize_run_setup()
	_hide_loading()

func generate_new_island() -> void:
	_set_loading_status("Preparing terrain...", 0.66)
	terrain_renderer.start()
	_setup_preview_renderer()
	_setup_lake_preview_renderer()
	_clear_island_state()
	await get_tree().process_frame

	_set_loading_status("Sketching lakes...", 0.74)
	lake_seed = randi()
	_generate_lake_cells()
	await get_tree().process_frame

	_set_loading_status("Scattering ruins...", 0.79)
	_generate_ruin_sites()
	update_lake_preview()
	await get_tree().process_frame

	_set_loading_status("Growing island...", 0.84)
	#initial terrain generation
	var starting_block: Dictionary = expansion_service.generate_initial_island_block(self, 50)
	await get_tree().process_frame

	_set_loading_status("Painting terrain...", 0.9)
	#delegate application of the block to the terrainservice
	TerrainService.expand_island(self, starting_block)
	await get_tree().process_frame

	_set_loading_status("Placing core...", 0.96)
	#place the player's core tower
	var keep: Tower = construct_tower_at(Vector2i.ZERO, Towers.Type.PLAYER_CORE) #NOTE: this must come first (id = 0)
	Run.references.keep = keep

	update_shore_boundary()
	update_navigation_grid()
	update_lake_preview()
	queue_redraw()
	await get_tree().process_frame

func _show_loading(message: String, progress: float = -1.0) -> void:
	UI.loading_screen.show_loading(message, progress)

func _hide_loading() -> void:
	UI.loading_screen.hide_loading()

func _set_loading_status(message: String, progress: float = -1.0) -> void:
	UI.loading_screen.show_loading(message, progress)

func _setup_preview_renderer() -> void:
	preview_renderer.cell_size = CELL_SIZE
	preview_renderer.max_gradient_depth = 3.0 #tighter gradient for previews
	preview_renderer.draw_background = false #we just want the outline overlay

	#add to scene (z-index higher so it draws on top)
	preview_renderer.z_index = 10

	#manually override the material to use the sketch shader
	#wait for the node to be ready or force setup
	preview_renderer.start()

	var sketch_mat := ShaderMaterial.new()
	sketch_mat.shader = preload("res://Shaders/sketch_terrain.gdshader")

	#re-use noise from main renderer if possible, or create new
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

func _setup_lake_preview_renderer() -> void:
	if not is_instance_valid(lake_preview_renderer):
		return
	lake_preview_renderer.cell_size = CELL_SIZE
	lake_preview_renderer.max_gradient_depth = 2.5
	lake_preview_renderer.draw_background = false
	lake_preview_renderer.z_index = Layers.FLOATING_UI
	lake_preview_renderer.start()

	var sketch_mat := ShaderMaterial.new()
	sketch_mat.shader = preload("res://Shaders/sketch_terrain.gdshader")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.025
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	sketch_mat.set_shader_parameter("grid_data_texture", lake_preview_renderer._grid_texture)
	sketch_mat.set_shader_parameter("noise_texture", noise_tex)
	sketch_mat.set_shader_parameter("outline_color", Color(0.109, 0.239, 0.31, 0.192))
	sketch_mat.set_shader_parameter("fill_color", Color(0.252, 0.551, 0.68, 0.024))
	lake_preview_renderer._terrain_rect.material = sketch_mat

#--- public api / request handlers ---
#this is the main entry point for player actions like building or selling
func request_tower_placement(cell: Vector2i, tower_type: Towers.Type, facing: Tower.Facing) -> bool:
	if tower_grid.has(cell):
		#handle selling
		if tower_type == Towers.Type.VOID:
			tower_grid[cell].sell()
			return true
		return false

	if TerrainService.is_area_constructable(self, facing, cell, tower_type):
		construct_tower_at(cell, tower_type, facing)
		return true

	return false

#public apis (used by terrainservice)
func construct_tower_at(cell: Vector2i, tower_type: Towers.Type, tower_facing: Tower.Facing = Tower.Facing.UP, initial_state: Dictionary = {}) -> Tower:
	#print("Construct tower of: ", Towers.Type.keys()[tower_type])
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
	tower.add_to_group(Run.references.TOWER_GROUP)

	tower.died.connect(func(_hit_report_data): update_navigation_grid()) #as unit becoems non-blocking upon unit death
	tower.tree_exiting.connect(_on_tower_destroyed.bind(tower), CONNECT_ONE_SHOT)

	add_child(tower)

	Run.player.add_to_used_capacity(Towers.get_tower_capacity(tower_type), "construct %s@%s" % [tower.name, str(cell)])
	update_adjacencies_around_tower(tower)
	update_navigation_grid()

	#insert the new tower in the lookup table
	if not _towers_by_type.has(tower.type):
		_towers_by_type[tower.type] = []
	_towers_by_type[tower.type].append(tower)
	UI.update_tower_counts.emit()

	tower_created.emit(tower)
	tower_changed.emit(cell)
	return tower

#request_upgrade checks funds/limits, then calls upgrade_tower
func request_upgrade(old_tower: Tower, new_type: Towers.Type) -> bool:
	if not is_instance_valid(old_tower): return false
	if old_tower.abstractive: return false
	if old_tower.current_state == Tower.State.RUINED: return false

	#check limits (if new tower type is restricted)
	if not TerrainService.is_area_constructable(self, old_tower.facing, old_tower.tower_position, new_type, true, old_tower):
		return false

	upgrade_tower(old_tower, new_type)
	return true

func upgrade_tower(old_tower: Tower, new_type: Towers.Type) -> void:
	var cell: Vector2i = old_tower.tower_position
	var facing: Tower.Facing = old_tower.facing

	#construct new tower
	var new_tower: Tower = construct_tower_at(cell, new_type, facing)

	#stat handover (hp)
	if is_instance_valid(new_tower.health_component) and is_instance_valid(old_tower.health_component):
		var damage: float = old_tower.health_component.max_health - old_tower.health_component.health
		new_tower.health_component.health -= damage

	#event handover (effects & behaviors & globals)
	var evt = GameEvent.new()
	evt.event_type = GameEvent.EventType.REPLACED
	evt.data = UnitReplacedData.new(old_tower, new_tower)
	#trigger local components (effects/behaviors transfer state)
	old_tower.on_event.emit(evt)

	#cleanup old tower
	old_tower.queue_free() #(automatically cleans up tower_grid)

	##visual feedback
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
	#simplified logic to find all land tiles adjacent to nothing
	shore_boundary_tiles.clear()
	for cell: Vector2i in terrain_base_grid:
		if terrain_base_grid[cell] == Terrain.Base.WATER:
			continue
		for dir: Vector2i in DIRS:
			if not terrain_base_grid.has(cell + dir):
				shore_boundary_tiles.append(cell)
				break

func is_lake_cell(cell: Vector2i) -> bool:
	return lake_cells.has(cell)

func update_lake_preview() -> void:
	if not is_instance_valid(lake_preview_renderer):
		return
	lake_preview_renderer.clear_decorations()
	lake_preview_renderer.reset_grid(get_nearby_lake_cells())
	for cell: Vector2i in get_visible_ruin_sites():
		lake_preview_renderer.set_preview_feature(cell, Towers.Type.RUINS)

func get_nearby_lake_cells() -> Array[Vector2i]:
	if terrain_base_grid.is_empty():
		return []
	var bounds := get_island_bounds()
	var min_cell := position_to_cell(bounds.position) - Vector2i.ONE * LAKE_PREVIEW_MARGIN
	var max_cell := position_to_cell(bounds.end) + Vector2i.ONE * LAKE_PREVIEW_MARGIN
	var visible_cells: Array[Vector2i] = []
	for cell: Vector2i in lake_cells:
		if terrain_base_grid.has(cell):
			continue
		if cell.x >= min_cell.x and cell.y >= min_cell.y and cell.x <= max_cell.x and cell.y <= max_cell.y:
			visible_cells.append(cell)
	return visible_cells

func get_visible_ruin_sites() -> Array[Vector2i]: ##returns the uncharted pregenerated ruin sites close enough to the explored frontier to preview
	if terrain_base_grid.is_empty():
		return []

	var bounds := get_island_bounds()
	var min_cell := position_to_cell(bounds.position) - Vector2i.ONE * LAKE_PREVIEW_MARGIN
	var max_cell := position_to_cell(bounds.end) + Vector2i.ONE * LAKE_PREVIEW_MARGIN
	var visible_sites: Array[Vector2i] = []

	for cell: Vector2i in _ruin_sites:
		if terrain_base_grid.has(cell):
			continue
		if cell.x < min_cell.x or cell.y < min_cell.y or cell.x > max_cell.x or cell.y > max_cell.y:
			continue
		visible_sites.append(cell)

	return visible_sites

func _generate_lake_cells() -> void:
	lake_cells.clear()
	var lake_noise := _make_lake_noise(lake_seed, LAKE_NOISE_FREQUENCY, LAKE_NOISE_OCTAVES)
	var warp_noise := _make_lake_noise(lake_seed + 1013, LAKE_WARP_FREQUENCY, 2)
	for x in range(-LAKE_FIELD_RADIUS, LAKE_FIELD_RADIUS + 1):
		for y in range(-LAKE_FIELD_RADIUS, LAKE_FIELD_RADIUS + 1):
			var cell: Vector2i = Vector2i(x, y)
			var distance: float = Vector2(cell).length()
			if distance < LAKE_SAFE_RADIUS or distance > LAKE_FIELD_RADIUS:
				continue
			if _lake_score(cell, lake_noise, warp_noise) >= LAKE_THRESHOLD:
				lake_cells[cell] = true
	_prune_lake_speckles()

func _make_lake_noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value % 2147483647
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise

func _lake_score(cell: Vector2i, lake_noise: FastNoiseLite, warp_noise: FastNoiseLite) -> float:
	var pos: Vector2 = Vector2(cell)
	var domain_warp: Vector2 = Vector2(
		warp_noise.get_noise_2d(pos.x, pos.y),
		warp_noise.get_noise_2d(pos.x + 137.0, pos.y - 59.0)
	) * LAKE_WARP_STRENGTH
	var sample_pos := pos + domain_warp
	return (lake_noise.get_noise_2d(sample_pos.x, sample_pos.y) + 1.0) * 0.5

func _prune_lake_speckles() -> void:
	var removed: Array[Vector2i] = []
	for cell: Vector2i in lake_cells:
		var neighbors: int = 0
		for dir: Vector2i in DIRS:
			if lake_cells.has(cell + dir):
				neighbors += 1
		if neighbors < LAKE_MIN_NEIGHBORS:
			removed.append(cell)
	for cell: Vector2i in removed:
		lake_cells.erase(cell)

func _generate_ruin_sites() -> void: ##pregenerates ruin sites on the outer field so expansion generation can consume a stable source of truth
	_ruin_sites.clear()

	var average_spacing: float = maxf(ruin_average_spacing, 1.0)
	var radius_limit: float = float(LAKE_FIELD_RADIUS - LAKE_PREVIEW_MARGIN)
	var field_area: float = PI * maxf((radius_limit * radius_limit) - float(LAKE_SAFE_RADIUS * LAKE_SAFE_RADIUS), 0.0)
	var target_sites: int = maxi(int(round(field_area / (average_spacing * average_spacing))), 0)
	var min_spacing_squared: float = pow(average_spacing * RUIN_MIN_SPACING_RATIO, 2.0)
	var max_attempts: int = maxi(target_sites * RUIN_ATTEMPTS_PER_SITE, RUIN_ATTEMPTS_PER_SITE)
	var attempts: int = 0

	while _ruin_sites.size() < target_sites and attempts < max_attempts:
		attempts += 1
		var candidate: Vector2i = _roll_ruin_candidate(radius_limit)
		if not _is_valid_ruin_site(candidate, min_spacing_squared):
			continue
		_ruin_sites[candidate] = true

func _roll_ruin_candidate(radius_limit: float) -> Vector2i:
	var radius: float = sqrt(randf()) * radius_limit
	var angle: float = randf() * TAU
	return Vector2i(roundi(cos(angle) * radius), roundi(sin(angle) * radius))

func _is_valid_ruin_site(cell: Vector2i, min_spacing_squared: float) -> bool: ##keeps ruin sites off lakes, away from the keep, and reasonably spaced from each other
	var radius_squared: int = cell.x * cell.x + cell.y * cell.y
	if radius_squared <= LAKE_SAFE_RADIUS * LAKE_SAFE_RADIUS:
		return false
	if radius_squared >= LAKE_FIELD_RADIUS * LAKE_FIELD_RADIUS:
		return false
	if lake_cells.has(cell):
		return false

	for existing_cell: Vector2i in _ruin_sites:
		if existing_cell.distance_squared_to(cell) < min_spacing_squared:
			return false

	return true

func has_ruin_site(cell: Vector2i) -> bool: ##checks whether a ruin site was pregenerated at this cell and has not yet been charted
	return _ruin_sites.has(cell)

func update_previews(choices_by_id: Dictionary[int, ExpansionChoice]) -> void:
	_preview_choices = choices_by_id
	_highlighted_choice_id = -1 #reset highlight
	queue_redraw()

	preview_renderer.clear_decorations() #clear previous tower previews

	#by default, show all choices as a faint outline
	var all_preview_cells: Array[Vector2i] = []
	for choice in _preview_choices.values():
		all_preview_cells.append_array(_choice_land_cells(choice))

	preview_renderer.reset_grid(all_preview_cells)
	update_lake_preview()

	#set to "passive" style
	preview_renderer.set_color_param("outline_color", Color(0, 0, 0, 0.4)) #gray/faint
	preview_renderer.set_color_param("fill_color", Color(1, 1, 1, 0.1))

#called by expansion_service to tell the island which choice to highlight
func set_highlighted_choice(choice_id: int = -1) -> void:
	if _highlighted_choice_id == choice_id:
		return

	_highlighted_choice_id = choice_id
	preview_renderer.clear_decorations() #clear previous tower previews

	if choice_id == -1: #nothing is selected!
		#revert to showing all choices faintly
		var all_cells: Array[Vector2i] = []
		for choice in _preview_choices.values():
			all_cells.append_array(_choice_land_cells(choice))
		preview_renderer.reset_grid(all_cells)
		preview_renderer.set_color_param("outline_color", Color(0.16, 0.16, 0.16, 0.4))
		preview_renderer.set_color_param("fill_color", Color(1, 1, 1, 0.1))

		#stamp all features from all choices
		for local_choice_id: int in _preview_choices:
			var choice: ExpansionChoice = _preview_choices[local_choice_id]
			for cell: Vector2i in choice.block_data:
				var cell_data: Terrain.CellData = choice.block_data[cell]
				if cell_data.terrain == Terrain.Base.WATER:
					continue
				preview_renderer.update_decoration(cell, cell_data.terrain)
				if cell_data.feature != Towers.Type.VOID:
					preview_renderer.set_preview_feature(cell, cell_data.feature)

	elif _preview_choices.has(choice_id):
		#show only the highlighted choice, with strong distinct style
		var active_choice: ExpansionChoice = _preview_choices[choice_id]
		var cells: Array[Vector2i] = _choice_land_cells(active_choice)

		preview_renderer.reset_grid(cells)
		preview_renderer.set_color_param("outline_color", Color(0.27, 0.27, 0.27, 0.576)) #solid black
		preview_renderer.set_color_param("fill_color", Color(0.4, 0.8, 0.6, 0.0)) #slight green tint

		for cell: Vector2i in active_choice.block_data:
			var cell_data: Terrain.CellData = active_choice.block_data[cell]
			if cell_data.terrain == Terrain.Base.WATER:
				continue
			preview_renderer.update_decoration(cell, cell_data.terrain)
			if cell_data.feature != Towers.Type.VOID:
				preview_renderer.set_preview_feature(cell, cell_data.feature)

func _choice_land_cells(choice: ExpansionChoice) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in choice.block_data:
		if choice.block_data[cell].terrain != Terrain.Base.WATER:
			cells.append(cell)
	return cells

#signal handlers
func _on_tower_destroyed(tower: Tower) -> void:
	var cell: Vector2i = tower.tower_position
	#clear tower grid
	for local_cell: Vector2i in tower.get_occupied_cells():
		if not tower_grid.has(local_cell):
			continue
		if not tower_grid[local_cell] == tower: #dont clear other towers' cells (i.e. upgrades)
			continue
		tower_grid.erase(local_cell)
	update_adjacencies_around_tower(tower)
	#update capacity, caches, navigation
	Run.player.remove_from_used_capacity(Towers.get_tower_capacity(tower.type), "destroy %s@%s" % [tower.name, str(cell)])
	update_navigation_grid()
	if _towers_by_type.has(tower.type):
		_towers_by_type[tower.type].erase(tower)
	tower_changed.emit(cell)
	UI.update_tower_counts.emit()

func update_adjacencies_around_tower(tower: Tower) -> void:
	if is_instance_valid(topology_service):
		topology_service.notify_tower_changed(tower)

func _update_adjacencies_around(cell: Vector2i) -> void:
	var adjacent_towers: Dictionary[Vector2i, Tower] = get_adjacent_towers(cell)
	for tower: Tower in adjacent_towers.values():
		update_adjacencies_around_tower(tower)

#static data access functions
func get_towers_by_type(type: Towers.Type) -> Array[Tower]:
	var typesafe : Array[Tower]
	typesafe.assign(_towers_by_type.get(type, []))
	return typesafe

func get_raid_targets() -> Array[Tower]: ##returns all live non-ruined settlement-style towers that raiders should visit before heading to the keep
	var raid_targets: Array[Tower] = []
	for tower_type: Towers.Type in [Towers.Type.GENERATOR, Towers.Type.HAMLET]:
		for tower: Tower in get_towers_by_type(tower_type):
			if not is_instance_valid(tower):
				continue
			if tower.current_state == Tower.State.RUINED:
				continue
			raid_targets.append(tower)
	return raid_targets

func get_tower_on_tile(cell: Vector2i) -> Tower:
	return tower_grid.get(cell, null)

func get_adjacent_towers(cell: Vector2i) -> Dictionary[Vector2i, Tower]: ##get towers adjacent to a single cell
	#NOTE: tower.get_adjacent_towers() should preferably be used instead if the Tower reference is first known
	var output: Dictionary[Vector2i, Tower] = {}
	for dir: Vector2i in DIRS:
		if tower_grid.has(cell + dir):
			output[dir] = tower_grid[cell + dir]
	return output

func get_terrain_base(cell : Vector2i) -> Terrain.Base:
	return terrain_base_grid.get(cell, Terrain.Base.EARTH)

#calculates the total bounding box of all existing terrain tiles.
func get_island_bounds() -> Rect2:
	if terrain_base_grid.is_empty():
		return Rect2(global_position, Vector2.ONE * CELL_SIZE)

	#find the min and max cell coordinates
	var min_coord: Vector2i = Vector2i(INF, INF)
	var max_coord: Vector2i = Vector2i(-INF, -INF)
	for cell: Vector2i in terrain_base_grid.keys():
		min_coord.x = min(min_coord.x, cell.x)
		min_coord.y = min(min_coord.y, cell.y)
		max_coord.x = max(max_coord.x, cell.x)
		max_coord.y = max(max_coord.y, cell.y)

	#convert the cell-based rect to a world-coordinate rect
	var top_left_pos: Vector2 = Island.cell_to_position(min_coord)
	var size_in_cells: Vector2i = (max_coord - min_coord) + Vector2i.ONE
	var size_in_pixels: Vector2 = Vector2(size_in_cells) * CELL_SIZE

	return Rect2(top_left_pos, size_in_pixels)

func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	#serialise terrain grid
	var terrain_export: Dictionary = {}
	for cell: Vector2i in terrain_base_grid:
		var key = "%d,%d" % [cell.x, cell.y]
		terrain_export[key] = terrain_base_grid[cell] #enum int
	data["terrain"] = terrain_export
	data["lake_seed"] = lake_seed
	data["ruin_sites"] = _serialize_ruin_sites()

	data["maximum_unit_id"] = Run.references.current_unit_id
	data["maximum_stat_id"] = Run.references.current_stat_id

	var tower_list: Dictionary[int, Dictionary] = {}
	var processed_towers: Dictionary[Tower, bool] = {}

	for cell: Vector2i in tower_grid:
		var tower: Tower = tower_grid[cell]
		if not is_instance_valid(tower): continue
		if processed_towers.has(tower): continue

		processed_towers[tower] = true

		#delegate to Tower for its specific state
		var t_data = tower.get_save_data()
		tower_list[tower.unit_id] = t_data

	data["towers"] = tower_list

	return data

func load_save_data(data: Dictionary) -> void:
	terrain_renderer.start()
	_setup_preview_renderer()
	_setup_lake_preview_renderer()
	#clear existing world
	_clear_island_state()
	lake_seed = int(data.get("lake_seed", randi()))
	_generate_lake_cells()
	_generate_ruin_sites()
	_deserialize_ruin_sites(data.get("ruin_sites", []))
	#restore terrain
	var terrain_import: Dictionary = data.get("terrain", {})
	var edits: Dictionary[Vector2i, Terrain.CellData] = {}
	for key: String in terrain_import:
		var parts = key.split(",")
		if parts.size() == 2:
			var cell: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
			var type = int(terrain_import[key])
			edits[cell] = Terrain.CellData.new(type, Towers.Type.VOID)
	TerrainService.expand_island(self, edits)

	var tower_list: Dictionary = data.get("towers", [])
	var sorted_unit_ids: Array[int] = []
	for unit_id in tower_list.keys():
		sorted_unit_ids.append(int(unit_id))
	sorted_unit_ids.sort()

	for unit_id: int in sorted_unit_ids:
		var t_data: Dictionary = tower_list[str(unit_id)]
		var type = int(t_data.get("type", Towers.Type.VOID))
		var pos_x = int(t_data.get("tower_position_x", 0))
		var pos_y = int(t_data.get("tower_position_y", 0))
		var facing = int(t_data.get("facing", 0))
		var level = int(t_data.get("level", 0))
		var cell: Vector2i = Vector2i(pos_x, pos_y)
		#construct the base tower
		var tower = construct_tower_at(cell, type, facing)

		if is_instance_valid(tower):
			tower.level = level
			tower.load_save_data(t_data)

	Run.references.current_unit_id = data["maximum_unit_id"]
	Run.references.current_stat_id = data["maximum_stat_id"]

	#finalize
	update_shore_boundary()
	update_navigation_grid()
	update_lake_preview()

func _clear_island_state() -> void:
	#wipe grid
	terrain_base_grid.clear()
	tower_grid.clear()
	lake_cells.clear()
	_ruin_sites.clear()
	_towers_by_type.clear()
	if is_instance_valid(topology_service):
		topology_service.clear()

	#wipe nodes
	for tower in get_tree().get_nodes_in_group(Run.references.TOWER_GROUP):
		tower.queue_free()

	#clear terrain visuals
	if is_instance_valid(terrain_renderer):
		#reset the grid data in renderer
		terrain_renderer.reset_grid([])
	if is_instance_valid(lake_preview_renderer):
		lake_preview_renderer.reset_grid([])

func _serialize_ruin_sites() -> Array[String]:
	var output: Array[String] = []
	for cell: Vector2i in _ruin_sites:
		output.append("%d,%d" % [cell.x, cell.y])
	return output

func _deserialize_ruin_sites(serialized_cells: Array) -> void:
	if serialized_cells.is_empty():
		return

	_ruin_sites.clear()
	for value: Variant in serialized_cells:
		var text: String = str(value)
		var parts: PackedStringArray = text.split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		_ruin_sites[cell] = true

#static position helpers
static func position_to_cell(_position: Vector2) -> Vector2i:
	return floor(_position / CELL_SIZE)

static func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
