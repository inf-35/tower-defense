# path_renderer.gd
extends Node2D
class_name PathRenderer

# --- configuration (designer-friendly) ---
@export_category("Visuals")
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.5)
@export var line_width: float = 1.0

var SCALE_FACTOR: int = 20 #strange workaround

# --- state ---
# this cache will store the calculated paths to avoid re-querying every frame
# format: { spawn_cell: Vector2i -> path: PackedVector2Array }
var _path_cache: Dictionary[Vector2i, PackedVector2Array] = {}
var _preview_path_cache: Dictionary[Vector2i, PackedVector2Array] = {}
var _is_previewing: bool = false
var _is_preview_blocked: bool = false

func _ready() -> void:
	scale = Vector2.ONE / SCALE_FACTOR
	# listen to the island's signal to know when the navigation map has changed
	var island: Island = get_parent() as Island
	if is_instance_valid(island):
		island.navigation_grid_updated.connect(_on_navigation_grid_updated)
	else:
		push_error("PathRenderer must be a child of an Island node.")
		return
	
	# also listen for when a new pathfinding field is ready
	Navigation.field_ready.connect(func(_goal, _ignore): _on_navigation_grid_updated())

	# perform an initial update
	_on_navigation_grid_updated()
	
func update_preview(blocker_cells: Array[Vector2i]) -> void: ## for ClickHandler
	_is_previewing = true
	_preview_path_cache.clear()
	_is_preview_blocked = false
	
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	var target_cell: Vector2i = Vector2i.ZERO
	
	for start_cell: Vector2i in spawn_points:
		# use the hypothetical pathfinder
		var path_data := Navigation.get_hypothetical_path(start_cell, target_cell, blocker_cells, false)
		if path_data.status == Navigation.PathData.Status.FOUND_PATH:
			var world_points := PackedVector2Array([Island.cell_to_position(start_cell) * SCALE_FACTOR])
			for cell: Vector2i in path_data.path:
				world_points.append(Island.cell_to_position(cell) * SCALE_FACTOR)
			_preview_path_cache[start_cell] = world_points
		else:
			# if ANY spawn point is blocked, mark the whole preview as invalid (red)
			_is_preview_blocked = true
			
	queue_redraw()

func clear_preview() -> void:
	_is_previewing = false
	_preview_path_cache.clear()
	queue_redraw()

# this is the main trigger function
func _on_navigation_grid_updated() -> void:
	await get_tree().create_timer(0.2).timeout
	# clear the old path data
	_path_cache.clear()

	# get the current list of spawn points and the target
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	if spawn_points.is_empty():
		queue_redraw() # clear the drawing if there's nothing to draw
		return
		
	var target_cell: Vector2i = Vector2i.ZERO
	
	# for each spawn point, find its path to the core
	for start_cell: Vector2i in spawn_points:
		# query the navigation service. we assume enemies do not ignore walls.
		var path_data: Navigation.PathData = Navigation.find_path(start_cell, target_cell, false)
		# if a valid path was found, process and cache it
		if path_data.status == Navigation.PathData.Status.FOUND_PATH:
			var world_points := PackedVector2Array([Island.cell_to_position(start_cell) * SCALE_FACTOR])
			# convert the cell coordinates to centered world positions
			for cell: Vector2i in path_data.path:
				var cell_center_pos: Vector2 = Island.cell_to_position(cell) * SCALE_FACTOR
				world_points.append(cell_center_pos)
			
			_path_cache[start_cell] = world_points
	
	# request a redraw to display the new paths
	queue_redraw()

# this function is called by the engine to draw the visuals
func _draw() -> void:
	var cache_to_draw: Dictionary[Vector2i, PackedVector2Array] = _preview_path_cache if _is_previewing else _path_cache
	# iterate through all the cached paths and draw them
	var line_color_adjusted: Color = line_color
	line_color_adjusted.a = line_color.a / cache_to_draw.size()
	for start_cell: Vector2i in cache_to_draw:
		var path_points: PackedVector2Array = cache_to_draw[start_cell]
		if path_points.size() > 1:
			draw_polyline(path_points, line_color, line_width * SCALE_FACTOR, true)
