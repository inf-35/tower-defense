extends UnitComponent
class_name NavigationComponent

var movement_component: MovementComponent

func inject_components(movement: MovementComponent):
	movement_component = movement

var goal: Vector2i = Vector2i.ZERO
var _current_waypoint_index: int:
	set(ncwi):
		_current_waypoint_index = ncwi
		if len(_path) > (_current_waypoint_index):
			_current_waypoint = _path[_current_waypoint_index]
			movement_component.target_position = Island.cell_to_position(_current_waypoint)
		else:
			movement_component.target_direction = Vector2(0,0)

var _current_waypoint: Vector2i

var _path: Array[Vector2i] = []:
	set(new_path):
		_path = new_path
		_current_waypoint_index = 0

func _ready():
	Navigation.field_cleared.connect(func():
		update_path()
	)
	
	_stagger += randi_range(0, _STAGGER_CYCLE)
	_STAGGER_CYCLE = 5
	
func update_path():
	var path_data: Navigation.PathData = Navigation.find_path(movement_component.cell_position)
	if path_data.status == Navigation.PathData.Status.building_path:
		Navigation.request_path_promise(Navigation.PathPromise.new( #request a path for later
			self,
			movement_component.cell_position,
			goal
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
			goal
		))
	else:
		_path = path_data.path
		unit.graphics.modulate = Color(1.0, 0.0, 0.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)

func get_position_in_future(t: float) -> Vector2: #returns predicted position of unit t seconds from now

	if movement_component == null or _path.is_empty():
		return unit.global_position # Not moving, will be at current position.

	var max_speed: float = unit.get_stat(Attributes.id.MAX_SPEED)

	if max_speed <= 0.0:
		return unit.global_position # Not moving.

	var total_distance_to_travel: float = max_speed * t
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
	var distance_per_cell := float(Island.CELL_SIZE)
	var num_waypoints_to_skip := int(total_distance_to_travel / distance_per_cell)

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
		# We've reached the end of the path.
		return last_safe_waypoint_pos

	var next_waypoint_pos := Island.cell_to_position(_path[final_waypoint_index + 1])
	var direction_of_final_segment = (next_waypoint_pos - last_safe_waypoint_pos).normalized()
	
	return last_safe_waypoint_pos + direction_of_final_segment * total_distance_to_travel
	
func _process(delta: float):
	_stagger += 1
	if _stagger % _STAGGER_CYCLE != 1:
		return
		
	if movement_component == null:
		return
	
	if _path.is_empty(): #path empty? get path
		update_path()
		movement_component.target_position = Island.cell_to_position(_current_waypoint)
	
	if _path.is_empty(): #path still empty? path unavailable
		movement_component.target_direction = Vector2.ZERO
		return
	
	if movement_component.cell_position == goal:
		movement_component.target_position = Island.cell_to_position(goal)
		return
	
	if (movement_component.position - Island.cell_to_position(_current_waypoint)).length_squared() < 50:
		_current_waypoint_index += 1
