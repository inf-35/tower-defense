extends Behavior
class_name ArcherBehavior

# --- state ---
# the distance from the keep (grid 0,0) at which the unit switches to siege mode
var siege_distance: float

func start() -> void:
	siege_distance = unit.global_position.distance_squared_to(Island.cell_to_position(Vector2i.ZERO)) - Island.CELL_SIZE #start at the unit's spawn location and move in
	_attempt_navigate_to_origin()
	# ensure we start by moving towards the objective
	_move_towards_keep()

func update(delta: float) -> void:
	_cooldown += delta
	
	# 1. calculate distance to the keep (origin)
	# we use the island helper to get the true world position of grid (0,0)
	var origin_pos: Vector2 = Island.cell_to_position(Vector2i.ZERO)
	var dist_sq_to_origin: float = unit.global_position.distance_squared_to(origin_pos)
	var siege_sq: float = siege_distance ** 2
	
	# 2. check for valid targets
	# we check if the range component has found anything we can shoot at.
	var has_target: bool = false
	if is_instance_valid(range_component):
		# get_target() returns a Unit or null
		has_target = range_component.get_target() != null
	
	# 3. determine state (siege vs march)
	# if we are close enough AND we have something to shoot, we hold position.
	if dist_sq_to_origin <= siege_sq and has_target:
		_hold_position()
	else:
		# otherwise (too far away, or sitting at the siege line with no targets), we push forward.
		_move_towards_keep()
		
	# 4. execute attack
	# this helper checks cooldowns and attacks the target if available
	_attempt_simple_attack()

func _move_towards_keep() -> void:
	siege_distance -= Island.CELL_SIZE * 2 #decrease siege distance
	if is_instance_valid(navigation_component):
		# standard behavior: pathfind to the center of the map
		navigation_component.goal = Vector2i.ZERO

func _hold_position() -> void:
	if is_instance_valid(navigation_component) and is_instance_valid(movement_component):
		# 1. tell navigation we want to stay exactly where we are
		# this prevents the pathfinder from trying to generate a path to (0,0)
		navigation_component.goal = movement_component.cell_position
		
		# 2. force physics stop
		# we manually zero the direction to prevent sliding if the navigation logic 
		# ran before this script in the frame
		movement_component.target_direction = Vector2.ZERO
