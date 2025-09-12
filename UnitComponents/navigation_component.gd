# navigation_component.gd
extends UnitComponent
class_name NavigationComponent

signal blocked_by_tower(tower: Tower)

var movement_component: MovementComponent
var goal: Vector2i = Vector2i.ZERO
@export var ignore_walls: bool = false

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
		
		# after advancing the waypoint, re-check our blocking status
		_re_evaluate_blocking_state()

var _current_waypoint: Vector2i

var _path: Array[Vector2i] = []:
	set(new_path):
		_path = new_path
		# use 'self.' to trigger the setter for the index
		self._current_waypoint_index = 0
		# immediately after getting a new path, check if we are blocked
		_re_evaluate_blocking_state(true)

#single, authoritative function for checking for blocking towers.
func _re_evaluate_blocking_state(check_local: bool = false) -> void:
	if unit.incorporeal:
		self.blocking_tower = null
		return

	var cells_to_check: Array[Vector2i] = []
	# 1. check the tile the unit is currently on
	if is_instance_valid(movement_component) and check_local:
		cells_to_check.append(movement_component.cell_position)
	# 2. check the next tile we are moving towards
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

func _ready():
	Navigation.field_cleared.connect(func():
		update_path()
	)
	
	_STAGGER_CYCLE = 5
	_stagger += randi_range(0, _STAGGER_CYCLE)
	
func update_path():
	var path_data: Navigation.PathData = Navigation.find_path(movement_component.cell_position, goal, ignore_walls)
	if path_data.status == Navigation.PathData.Status.building_path:
		Navigation.request_path_promise(Navigation.PathPromise.new( #request a path for later
			self,
			movement_component.cell_position,
			goal,
			ignore_walls
		))
		unit.graphics.modulate = Color(0.0, 1.0, 1.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)
	else: #path built/ no path found
		_path = path_data.path
		unit.graphics.modulate = Color(1.0, 0.0, 1.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)

func receive_path_data(path_data: Navigation.PathData): #used by Navigation to fulfill promises
	if path_data.status == Navigation.PathData.Status.building_path: #keep requesting path until we get back a good reply
		Navigation.request_path_promise(Navigation.PathPromise.new(
			self,
			movement_component.cell_position,
			goal,
			ignore_walls
		))
	else:
		_path = path_data.path
		unit.graphics.modulate = Color(1.0, 0.0, 0.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)
	
func _process(delta: float):
	_stagger += 1
	if _stagger % _STAGGER_CYCLE != 1:
		return
		
	if movement_component == null:
		return
	
	# 1. ensure we have a path
	if _path.is_empty():
		update_path()
		if _path.is_empty():
			movement_component.target_direction = Vector2.ZERO
			
			_STAGGER_CYCLE = 2
			return

	_STAGGER_CYCLE = 5
	# 2. check for a block *before* issuing any movement commands
	if is_instance_valid(blocking_tower):
		# if blocked, command the movement component to stop at its current position
		movement_component.target_position = unit.global_position
		return
	
	# 3. if not blocked, issue the command to move to the current waypoint
	movement_component.target_position = Island.cell_to_position(_current_waypoint)
	 #+ Vector2(Island.CELL_SIZE * randf_range(-0.5, 0.5), Island.CELL_SIZE * randf_range(-0.5, 0.5)) * 0.2
	
	# 4. check for arrival at the waypoint to advance the path
	if movement_component.cell_position == goal:
		return
	
	if (movement_component.position - Island.cell_to_position(_current_waypoint)).length_squared() < 50:
		# use 'self.' to trigger the setter, which will re-evaluate blocking for the next tile
		self._current_waypoint_index += 1

#TODO: implement temporal-based caches
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
