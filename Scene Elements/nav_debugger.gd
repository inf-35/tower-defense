extends Node2D
class_name NavigationDebugger

# --- Configuration ---
@export var show_overlay: bool = true
@export var draw_costs: bool = true
@export var draw_flow_arrows: bool = false
@export var simulation_speed: float = 0.05 # Seconds per step (lower is faster)

# --- Colors ---
const COL_WALL = Color(1.0, 0.0, 0.0, 0.4)    # Red: Impassable
const COL_OPEN = Color(0.0, 1.0, 0.0, 0.4)    # Green: In Open Set (Candidates)
const COL_CLOSED = Color(0.0, 0.0, 1.0, 0.2)  # Blue: Closed Set (Visited)
const COL_CURRENT = Color(1.0, 1.0, 0.0, 0.8) # Yellow: Currently Processing
const COL_PATH = Color(1.0, 1.0, 1.0, 1.0)    # White: Final Path
const COL_ARROW = Color(0.0, 1.0, 1.0, 0.6)   # Cyan: Flow Direction

# --- State ---
var _font: Font
var _sim_running: bool = false
var _sim_open_set_visual: Array[Vector2i] = []
var _sim_closed_set_visual: Array[Vector2i] = []
var _sim_current_tile: Vector2i = Vector2i(-999, -999)
var _sim_final_path: Array[Vector2i] = []

# --- Inputs for Sim ---
var _sim_start: Vector2i = Vector2i.ZERO
var _sim_goal: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_font = ThemeDB.get_fallback_font()
	# Connect to real navigation updates to keep the background grid sync'd
	Navigation.field_cleared.connect(queue_redraw)
	if is_instance_valid(References.island):
		References.island.navigation_grid_updated.connect(queue_redraw)

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return

	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_Q:
			show_overlay = not show_overlay
			queue_redraw()
		
		# Press 'R' to run simulation between Mouse and Center (or last start)
		if event.pressed and event.keycode == KEY_R:
			var mouse_cell = Island.position_to_cell(get_global_mouse_position())
			run_simulation(mouse_cell, Vector2i.ZERO) # Default to center
			
	# Left Click to set Start, Right Click to set Goal for simulation
	if event is InputEventMouseButton and event.pressed:
		var cell = Island.position_to_cell(get_global_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT:
			_sim_start = cell
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_sim_goal = cell
			run_simulation(_sim_start, _sim_goal)

func _draw() -> void:
	if not show_overlay: return
	
	# 1. Draw Real World Data (Static Grid)
	_draw_grid_state()
	
	# 2. Draw Simulation State (The Animation)
	if _sim_running or not _sim_final_path.is_empty():
		_draw_simulation_overlay()
		
	# 3. Draw Real Unit Paths (Live)
	if not _sim_running:
		_draw_live_unit_paths()

# --- Visualization Logic ---

func _draw_grid_state() -> void:
	var cell_size = Island.CELL_SIZE
	
	for cell: Vector2i in Navigation.grid:
		var cost = Navigation.grid[cell]
		if cost == 0: continue
		
		var pos = Island.cell_to_position(cell)
		var rect = Rect2(pos - Vector2(cell_size, cell_size)/2.0, Vector2(cell_size, cell_size))
		
		# Draw Obstacle
		draw_rect(rect, COL_WALL, true)
		
		# Draw Cost Text
		if draw_costs:
			draw_string(_font, pos + Vector2(-4, 4), str(cost), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

func _draw_simulation_overlay() -> void:
	var cell_size = Island.CELL_SIZE
	var half = Vector2(cell_size, cell_size) / 2.0
	
	# Draw Closed Set (Visited)
	for cell in _sim_closed_set_visual:
		var pos = Island.cell_to_position(cell)
		draw_rect(Rect2(pos - half, Vector2(cell_size, cell_size)), COL_CLOSED, true)
		
	# Draw Open Set (Candidates)
	for cell in _sim_open_set_visual:
		var pos = Island.cell_to_position(cell)
		draw_rect(Rect2(pos - half, Vector2(cell_size, cell_size)), COL_OPEN, true)
		
	# Draw Current Head
	if _sim_current_tile != Vector2i(-999, -999):
		var pos = Island.cell_to_position(_sim_current_tile)
		draw_rect(Rect2(pos - half, Vector2(cell_size, cell_size)), COL_CURRENT, true)
		
	# Draw Final Path
	if _sim_final_path.size() > 1:
		var points = PackedVector2Array()
		for p in _sim_final_path:
			points.append(Island.cell_to_position(p))
		draw_polyline(points, COL_PATH, 3.0)

func _draw_live_unit_paths() -> void:
	# Debug active units in the game
	for unit in get_tree().get_nodes_in_group("active_enemies"):
		if is_instance_valid(unit.navigation_component) and not unit.navigation_component._path.is_empty():
			var points = PackedVector2Array()
			points.append(unit.global_position)
			
			var nav = unit.navigation_component
			# Draw from current waypoint onwards
			for i in range(nav._current_waypoint_index, nav._path.size()):
				points.append(Island.cell_to_position(nav._path[i]))
			
			if points.size() > 1:
				draw_polyline(points, Color(1, 0.5, 0, 0.5), 2.0)

# --- The Simulation Core ---
# This replicates the Navigation.gd logic but yields execution for visualization

func run_simulation(start: Vector2i, goal: Vector2i) -> void:
	_sim_running = true
	_sim_start = start
	_sim_goal = goal
	_sim_open_set_visual.clear()
	_sim_closed_set_visual.clear()
	_sim_final_path.clear()
	_sim_current_tile = start
	
	print("Debugger: Starting Path Simulation from ", start, " to ", goal)
	
	# --- A* REPLICATION START ---
	# Note: This simulates the 'build_flow_field' logic but targeted for a specific path
	
	var open_set = [] # Simple array for sim, not PriorityQueue for simplicity in visualization
	open_set.append({ "pos": start, "f": 0, "g": 0 })
	
	var came_from = {} # To reconstruct path
	var g_score = { start: 0 }
	
	while not open_set.is_empty():
		# Sort to simulate Priority Queue
		open_set.sort_custom(func(a, b): return a.f < b.f)
		var current_node = open_set.pop_front()
		var current = current_node.pos
		
		_sim_current_tile = current
		_sim_open_set_visual.erase(current)
		_sim_closed_set_visual.append(current)
		queue_redraw()
		
		# VISUAL DELAY
		await get_tree().create_timer(simulation_speed).timeout
		
		if current == goal:
			_reconstruct_sim_path(came_from, current)
			_sim_running = false
			return
			
		for dir in Navigation.DIRECTIONS:
			var neighbor = current + dir
			
			if not Navigation.grid.has(neighbor):
				continue # Out of bounds
				
			# Cost Logic (Replicated from Navigation.gd)
			var base_cost = Navigation.grid[neighbor]
			# Simulate 'ignore_walls = false'
			if base_cost >= 255: # Assuming 255 is wall
				continue
				
			var tentative_g = g_score[current] + base_cost
			
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f = tentative_g + (neighbor - goal).length_squared()
				
				# Add to open set if not there
				var in_open = false
				for item in open_set:
					if item.pos == neighbor:
						in_open = true
						item.f = f # Update F
						item.g = tentative_g
						break
				if not in_open:
					open_set.append({ "pos": neighbor, "f": f, "g": tentative_g })
					_sim_open_set_visual.append(neighbor)
					
	print("Debugger: No path found in simulation.")
	_sim_running = false
	queue_redraw()

func _reconstruct_sim_path(came_from: Dictionary, current: Vector2i) -> void:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	_sim_final_path = path
	queue_redraw()
