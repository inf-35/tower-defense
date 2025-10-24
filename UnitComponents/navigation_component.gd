# navigation_component.gd
extends UnitComponent
class_name NavigationComponent

signal blocked_by_tower(tower: Tower)

var movement_component: MovementComponent
var goal: Vector2i = Vector2i.ZERO
@export var ignore_walls: bool = false ##ignore walls during pathfinding?

# --- deviation state ---
const DEVIATION_INTERVAL: float = 0.6 # how often to pick a new random offset (in seconds)
const DEVIATION_MAGNITUDE: float = Island.CELL_SIZE * 0.3 # how far the unit can stray

var _deviation_timer: float = 0.0
var _current_deviation: Vector2 = Vector2.ZERO

var blocking_tower: Tower:
	set(nt):
		blocking_tower = nt
		blocked_by_tower.emit(blocking_tower)

func inject_components(movement: MovementComponent):
	movement_component = movement

var _current_waypoint_index: int:
	set(ncwi):
		_current_waypoint_index = ncwi
		if len(_path) > _current_waypoint_index:
			_current_waypoint = _path[_current_waypoint_index]
		_re_evaluate_blocking_state()

var _current_waypoint: Vector2i
var _path: Array[Vector2i] = []:
	set(new_path):
		_path = new_path
		self._current_waypoint_index = 0
		_re_evaluate_blocking_state(true)

# single, authoritative function for checking for blocking towers
func _re_evaluate_blocking_state(check_local: bool = false) -> void:
	if unit.incorporeal or unit.phasing:
		self.blocking_tower = null
		return

	var cells_to_check: Array[Vector2i] = []
	if is_instance_valid(movement_component) and check_local:
		cells_to_check.append(movement_component.cell_position)
	if _current_waypoint_index < _path.size():
		cells_to_check.append(_path[_current_waypoint_index])
	
	for cell: Vector2i in cells_to_check:
		var unit_on_tile: Tower = References.island.get_tower_on_tile(cell)
		if is_instance_valid(unit_on_tile) and unit_on_tile.hostile != unit.hostile and unit_on_tile.blocking:
			if self.blocking_tower != unit_on_tile:
				self.blocking_tower = unit_on_tile
				blocking_tower.died.connect(
					func(): self.blocking_tower = null,
					CONNECT_ONE_SHOT
				)
			return

	self.blocking_tower = null

# this function generates a new random offset and resets the timer
func _update_deviation() -> void:
	# reset the timer with a little randomness to desynchronize units
	_deviation_timer = DEVIATION_INTERVAL + randf_range(-0.1, 0.1)
	# generate a new random direction vector
	_current_deviation = Vector2.from_angle(randf() * TAU) * DEVIATION_MAGNITUDE

func _ready():
	Navigation.field_cleared.connect(update_path)
	_STAGGER_CYCLE = 5
	_stagger += randi_range(0, _STAGGER_CYCLE)
	
func update_path():
	var path_data: Navigation.PathData = Navigation.find_path(movement_component.cell_position, goal, ignore_walls)
	
	# when the path is updated, we must also update our deviation to ensure responsiveness
	_update_deviation()
	
	if path_data.status == Navigation.PathData.Status.BUILDING_PATH:
		Navigation.request_path_promise(Navigation.PathPromise.new(
			self, movement_component.cell_position, goal, ignore_walls
		))
	else:
		self._path = path_data.path

func receive_path_data(path_data: Navigation.PathData):
	_update_deviation() # also update deviation when a promise is fulfilled
	if path_data.status == Navigation.PathData.Status.BUILDING_PATH:
		Navigation.request_path_promise(Navigation.PathPromise.new(
			self, movement_component.cell_position, goal, ignore_walls
		))
	else:
		self._path = path_data.path
	
func _process(delta: float):
	_stagger += 1
	if _stagger % _STAGGER_CYCLE != 1:
		return
	if movement_component == null:
		return

	# --- deviation timer logic ---
	_deviation_timer -= delta
	if _deviation_timer <= 0.0:
		_update_deviation()
	
	# 1. ensure we have a path
	if _path.is_empty():
		update_path()
		if _path.is_empty():
			movement_component.target_direction = Vector2.ZERO
			_STAGGER_CYCLE = 2
			return

	_STAGGER_CYCLE = 5
	
	# 2. handle blocking state
	if is_instance_valid(blocking_tower):
		var current_cell_center: Vector2 = Island.cell_to_position(movement_component.cell_position)
		var tower_position: Vector2 = blocking_tower.global_position
		var direction_to_tower: Vector2 = (tower_position - current_cell_center).normalized()
		var target_pos: Vector2 = current_cell_center + direction_to_tower * (Island.CELL_SIZE * 0.1)
		
		# note: we do not apply deviation when blocked to ensure the unit stops neatly
		movement_component.target_position = target_pos
		return
	
	# 3. if not blocked, issue the command to move to the deviated waypoint
	var waypoint_pos: Vector2 = Island.cell_to_position(_current_waypoint)
	movement_component.target_position = waypoint_pos + _current_deviation
	
	# 4. check for arrival at the (non-deviated) waypoint to advance the path
	if movement_component.cell_position == goal:
		return
	if (movement_component.position - waypoint_pos).length_squared() < 50:
		self._current_waypoint_index += 1

func get_position_in_future(t: float) -> Vector2:
	if movement_component == null:
		return unit.global_position
		
	var max_speed: float = unit.get_stat(Attributes.id.MAX_SPEED)
	
	if max_speed <= 0.0:
		return unit.global_position # Not moving.
		
	if _path.is_empty():
		return unit.global_position + t * (Vector2(goal) - unit.global_position).normalized() * max_speed

	# --- Manual Frame-by-Frame Simulation ---
	var time_to_simulate := t
	var simulated_position := unit.global_position
	var simulated_waypoint_index := _current_waypoint_index
	
	# We use a fixed physics tick rate for a stable and predictable simulation.
	# Using the actual delta from _process would be non-deterministic.
	const SIMULATION_TICK_RATE: float = 1.0 / 30.0 # Simulate at 30 FPS

	while time_to_simulate > 0 and simulated_waypoint_index < _path.size():
		var target_waypoint_pos := Island.cell_to_position(_path[simulated_waypoint_index])
		var direction_to_waypoint = (target_waypoint_pos - simulated_position).normalized()
		
		# Calculate the distance this unit will travel in one simulation tick.
		var distance_this_tick = max_speed * SIMULATION_TICK_RATE
		
		var distance_to_waypoint = simulated_position.distance_to(target_waypoint_pos)

		if distance_this_tick >= distance_to_waypoint:
			# We will reach or pass the waypoint in this tick.
			# Move directly to the waypoint and advance to the next.
			simulated_position = target_waypoint_pos
			simulated_waypoint_index += 1
		else:
			# Move along the path for one tick's worth of distance.
			simulated_position += direction_to_waypoint * distance_this_tick
		
		time_to_simulate -= SIMULATION_TICK_RATE
	return simulated_position

func fast_get_position_in_future(t: float) -> Vector2: #returns predicted position of unit t seconds from now
	if movement_component == null or _path.is_empty():
		return unit.global_position # Not moving, will be at current position.

	var max_speed: float = unit.get_stat(Attributes.id.MAX_SPEED)

	if max_speed <= 0.0:
		return unit.global_position # Not moving.

	var total_distance_to_travel: float = max_speed * t * 0.7
	var current_pos: Vector2 = unit.global_position
	var simulated_waypoint_index: int = _current_waypoint_index
	
	# --- Optimization Step 1: Account for the partial first step ---
	var first_waypoint_pos := Island.cell_to_position(_path[simulated_waypoint_index])
	var distance_to_first_waypoint := current_pos.distance_to(first_waypoint_pos)

	if total_distance_to_travel <= distance_to_first_waypoint:
		# Will not even reach the next waypoint.
		var direction = (first_waypoint_pos - current_pos).normalized()
		return current_pos + direction * total_distance_to_travel

	# We reached the first waypoint, so subtract that distance and time.
	total_distance_to_travel -= distance_to_first_waypoint
	simulated_waypoint_index += 1

	# --- Optimization Step 2: Skip full waypoints ---
	# All subsequent waypoints are a fixed distance apart (assuming no diagonals in path).
	var distance_per_cell = Island.CELL_SIZE
	var num_waypoints_to_skip := int(total_distance_to_travel / Island.CELL_SIZE)

	var final_waypoint_index = min(
		simulated_waypoint_index + num_waypoints_to_skip,
		_path.size() - 1
	)

	# Jump our simulation state directly to this "last safe waypoint".
	var last_safe_waypoint_pos: Vector2 = Island.cell_to_position(_path[final_waypoint_index])
	var distance_skipped: float = (final_waypoint_index - simulated_waypoint_index) * distance_per_cell
	total_distance_to_travel -= distance_skipped

	# --- Final Step: Simulate the remaining partial step ---
	if final_waypoint_index + 1 >= _path.size():
		# We've reached the end of the path
		return last_safe_waypoint_pos

	var next_waypoint_pos := Island.cell_to_position(_path[final_waypoint_index + 1])
	var direction_of_final_segment = (next_waypoint_pos - last_safe_waypoint_pos).normalized()

	return last_safe_waypoint_pos + direction_of_final_segment * total_distance_to_travel
