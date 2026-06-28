#navigation_component.gd
extends UnitComponent
class_name NavigationComponent

signal blocked_by_tower(tower: Tower)

var movement_component: MovementComponent
var goal: Vector2i = Vector2i.ZERO
@export var ignore_walls: bool = false

enum RouteMode {
	DIRECT_TO_GOAL,
	RAIDER_CHAIN,
}

@export var route_mode: RouteMode = RouteMode.DIRECT_TO_GOAL ##controls how this unit chooses successive navigation goals on top of the low-level pathfinder

#--- blocking state ---
var blocking_tower: Tower = null

#--- pathing state ---
var _current_waypoint_index: int = 0
var _path: Array[Vector2i] = []
var _route_spawn_cell: Vector2i = Vector2i.ZERO
var _route_spawn_cell_initialized: bool = false
var _route_waypoints: Array[Vector2i] = []
var _route_waypoint_index: int = 0

#--- deviation state (visuals only) ---
const DEVIATION_INTERVAL: float = 0.6
const DEVIATION_MAGNITUDE: float = Island.CELL_SIZE * 0.2
var _deviation_timer: float = 0.0
var _current_deviation: Vector2 = Vector2.ZERO

#--- configuration ---
const TARGET_DEVIATION_FROM_WAYPOINT: float = Island.CELL_SIZE * 0.5
const TARGET_DEVIATION_SQUARED = TARGET_DEVIATION_FROM_WAYPOINT ** 2

func inject_components(movement: MovementComponent) -> void:
	movement_component = movement

func _ready() -> void:
	#listen for global path updates (e.g. maze changed)
	Run.references.island.navigation_grid_updated.connect(update_path)
	_STAGGER_CYCLE = 5
	_stagger += randi_range(0, _STAGGER_CYCLE)

func _process(delta: float) -> void:
	if not Run.is_run_ready():
		return

	if movement_component == null:
		return

	#1. update deviation
	_deviation_timer -= delta
	if _deviation_timer <= 0.0:
		_update_deviation()

	#2. stagger logic
	_stagger += 1
	if _stagger % _STAGGER_CYCLE != 0:
		return

	var route_goal_changed: bool = _sync_route_goal()
	if route_goal_changed:
		update_path()

	#3. path maintenance
	if _path.is_empty():
		update_path()
		if _path.is_empty():
			_check_for_obstructions()
			if is_instance_valid(blocking_tower):
				_handle_blocked_state()
			else:
				movement_component.target_direction = Vector2.ZERO
			return

	#4. obstruction check
	#check the immediate next step in our plan for obstacles.
	_check_for_obstructions()

	#5. execution
	if is_instance_valid(blocking_tower):
		_handle_blocked_state()
	else:
		_handle_moving_state()

#--- core logic ---
func _check_for_obstructions() -> void:
	if unit.incorporeal or unit.phasing:
		return

	#prioritize the cell we are trying to enter (forward progress)
	var next_cell: Vector2i = _path[_current_waypoint_index] if _current_waypoint_index < _path.size() else movement_component.cell_position

	#also check the cell we are standing on (anti-stuck / built-on-top)
	var current_cell: Vector2i = movement_component.cell_position

	if not Navigation.grid.has(next_cell):
		push_warning("Navigation failed to retrieve at position: ", next_cell)
		push_warning(_path)
		return
	#look up the map note: if the corresponding cell has a base navcost, we immmediately assume it is not a valid blocker
	var tower_ahead = Run.references.island.get_tower_on_tile(next_cell) if Navigation.grid[next_cell] != Navigation.BASE_COST else null
	var tower_here = Run.references.island.get_tower_on_tile(current_cell) if Navigation.grid[current_cell] != Navigation.BASE_COST else null

	#prioritize blocking the tower ahead, fallback to the tower we are inside
	var candidate = tower_ahead if is_valid_blocker(tower_ahead) else (tower_here if is_valid_blocker(tower_here) else null)

	if candidate != blocking_tower:
		blocking_tower = candidate
		blocked_by_tower.emit(blocking_tower) #tells unit to set rangecomponent override

func is_valid_blocker(tower: Tower) -> bool:
	return is_instance_valid(tower) and tower.blocking and tower.hostile != unit.hostile

func _handle_blocked_state() -> void:
	#visual adjustment: nudge slightly towards the wall so it looks like they are hitting it
	var tower_pos = blocking_tower.global_position
	var my_pos = unit.global_position
	movement_component.velocity = Vector2.ZERO
	#var nudge = (tower_pos - my_pos).normalized() * Island.CELL_SIZE * 0.1
	#movement_component.velocity += nudge
	movement_component.target_position = Island.cell_to_position(Island.position_to_cell(unit.global_position)) + (tower_pos - my_pos).normalized() * Island.CELL_SIZE * 0.3

func _handle_moving_state() -> void:
	#standard path following
	var waypoint_pos: Vector2 = Island.cell_to_position(_path[_current_waypoint_index])

	#apply visual deviation (drunk walk)
	movement_component.target_position = waypoint_pos + _current_deviation

	#check for arrival
	#we use a distance check squared for performance
	if unit.global_position.distance_squared_to(waypoint_pos) < TARGET_DEVIATION_SQUARED: #approx 10 pixels
		#advance to next waypoint
		_current_waypoint_index = min(_current_waypoint_index + 1, _path.size() - 1)
		#update blocking state immediately on cell change to be responsive
		_check_for_obstructions()

#--- navigation integration ---

func update_path() -> void:
	_sync_route_goal()
	var path_data = Navigation.find_path(movement_component.cell_position, goal, ignore_walls)
	_process_path_result(path_data)

func _process_path_result(path_data: Navigation.PathData) -> void:
	_update_deviation()
	self._path = path_data.path
	self._current_waypoint_index = 0 #reset progress on new path
	#important: check if the new path spawns us directly into a wall
	_check_for_obstructions()

func _update_deviation() -> void:
	_deviation_timer = DEVIATION_INTERVAL + randf_range(-0.1, 0.1)
	_current_deviation = Vector2.from_angle(randf() * TAU) * DEVIATION_MAGNITUDE

#--- public api (prediction) ---

func get_position_in_future(t: float) -> Vector2:
	if movement_component == null:
		return unit.global_position

	var max_speed: float = unit.get_stat(Attributes.id.MAX_SPEED)

	if max_speed <= 0.0:
		return unit.global_position #not moving.

	if _path.is_empty():
		return unit.global_position + t * (Vector2(goal) - unit.global_position).normalized() * max_speed

	#--- manual frame-by-frame simulation ---
	var time_to_simulate := t
	var simulated_position := unit.global_position
	var simulated_waypoint_index := _current_waypoint_index

	#we use a fixed physics tick rate for a stable and predictable simulation.
	#using the actual delta from _process would be non-deterministic.
	const SIMULATION_TICK_RATE: float = 1.0 / 30.0 #simulate at 30 fps

	while time_to_simulate > 0 and simulated_waypoint_index < _path.size():
		var target_waypoint_pos := Island.cell_to_position(_path[simulated_waypoint_index])
		var direction_to_waypoint = (target_waypoint_pos - simulated_position).normalized()

		#calculate the distance this unit will travel in one simulation tick.
		var distance_this_tick = max_speed * SIMULATION_TICK_RATE

		var distance_to_waypoint = simulated_position.distance_to(target_waypoint_pos)

		if distance_this_tick >= distance_to_waypoint:
			#we will reach or pass the waypoint in this tick.
			#move directly to the waypoint and advance to the next.
			simulated_position = target_waypoint_pos
			simulated_waypoint_index += 1
		else:
			#move along the path for one tick's worth of distance.
			simulated_position += direction_to_waypoint * distance_this_tick

		time_to_simulate -= SIMULATION_TICK_RATE
	return simulated_position

func fast_get_position_in_future(t: float) -> Vector2: #returns predicted position of unit t seconds from now
	if movement_component == null or _path.is_empty():
		return unit.global_position #not moving, will be at current position.

	var max_speed: float = unit.get_stat(Attributes.id.MAX_SPEED)

	if max_speed <= 0.0:
		return unit.global_position #not moving.

	var total_distance_to_travel: float = max_speed * t * 0.7
	var current_pos: Vector2 = unit.global_position
	var simulated_waypoint_index: int = _current_waypoint_index

	#--- optimization step 1: account for the partial first step ---
	var first_waypoint_pos := Island.cell_to_position(_path[simulated_waypoint_index])
	var distance_to_first_waypoint := current_pos.distance_to(first_waypoint_pos)

	if total_distance_to_travel <= distance_to_first_waypoint:
		#will not even reach the next waypoint.
		var direction = (first_waypoint_pos - current_pos).normalized()
		return current_pos + direction * total_distance_to_travel

	#we reached the first waypoint, so subtract that distance and time.
	total_distance_to_travel -= distance_to_first_waypoint
	simulated_waypoint_index += 1

	#--- optimization step 2: skip full waypoints ---
	#all subsequent waypoints are a fixed distance apart (assuming no diagonals in path).
	var distance_per_cell = Island.CELL_SIZE
	var num_waypoints_to_skip := int(total_distance_to_travel / Island.CELL_SIZE)

	var final_waypoint_index = min(
		simulated_waypoint_index + num_waypoints_to_skip,
		_path.size() - 1
	)

	#jump our simulation state directly to this "last safe waypoint".
	var last_safe_waypoint_pos: Vector2 = Island.cell_to_position(_path[final_waypoint_index])
	var distance_skipped: float = (final_waypoint_index - simulated_waypoint_index) * distance_per_cell
	total_distance_to_travel -= distance_skipped

	#--- final step: simulate the remaining partial step ---
	if final_waypoint_index + 1 >= _path.size():
		#we've reached the end of the path
		return last_safe_waypoint_pos

	var next_waypoint_pos := Island.cell_to_position(_path[final_waypoint_index + 1])
	var direction_of_final_segment = (next_waypoint_pos - last_safe_waypoint_pos).normalized()

	return last_safe_waypoint_pos + direction_of_final_segment * total_distance_to_travel

func _sync_route_goal() -> bool: ##keeps the effective navigation goal aligned with the component-owned route mode state
	if route_mode != RouteMode.RAIDER_CHAIN:
		return false

	if not _route_spawn_cell_initialized:
		_route_spawn_cell = movement_component.cell_position
		_route_spawn_cell_initialized = true

	if _route_waypoints.is_empty():
		_route_waypoints = _load_route_waypoints()
		_route_waypoint_index = 0

	while _route_waypoint_index < _route_waypoints.size():
		var target_cell: Vector2i = _route_waypoints[_route_waypoint_index]
		var target_tower: Tower = _get_route_target_at(target_cell)
		if is_instance_valid(target_tower):
			if goal != target_cell:
				goal = target_cell
				return true
			return false
		_route_waypoint_index += 1

	if goal != Vector2i.ZERO:
		goal = Vector2i.ZERO
		return true

	return false

func _load_route_waypoints() -> Array[Vector2i]: ##loads the frozen combat route for this spawn when available and otherwise falls back to the live raid target chain
	if is_instance_valid(Run.waves):
		var frozen_waypoints: Array[Vector2i] = Run.waves.get_frozen_raider_waypoints(_route_spawn_cell, ignore_walls)
		if not frozen_waypoints.is_empty():
			return frozen_waypoints

	if not is_instance_valid(Run.references.island):
		return []

	return RaiderRoutePlanner.get_waypoint_cells_for_spawn(_route_spawn_cell, Run.references.island.get_raid_targets())

func _get_route_target_at(cell: Vector2i) -> Tower: ##resolves the current waypoint anchor cell into a live raid target tower if one still exists there
	if not is_instance_valid(Run.references.island):
		return null

	var tower: Tower = Run.references.island.get_tower_on_tile(cell)
	if not is_instance_valid(tower):
		return null
	if tower.current_state == Tower.State.RUINED:
		return null
	if not Towers.is_raid_target(tower.type):
		return null
	return tower

func get_save_data() -> Dictionary:
	return {} #nothing to save!
