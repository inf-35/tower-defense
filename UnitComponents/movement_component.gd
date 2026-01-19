extends UnitComponent
class_name MovementComponent

signal movement_to_cell(origin: Vector2i, destination: Vector2i)

var _modifiers_component: ModifiersComponent

@export var face_towards_movement: bool = true
@export var movement_data: MovementData = load("res://Content/Movement/default_mvmt.tres")

@export var jiggle_enabled: bool = true
@export var jiggle_speed: float = 12.0 ## how fast the cycle runs
@export var jiggle_angle: float = 8.0 ## max rotation in degrees (Waddle)
@export var bounce_amount: float = 0.1 ## scale stretch amount (Bounce)

var graphics: Node2D
var _walk_cycle_time: float = 0.0

const _ERROR_SQUARED: float = 2.0 ** 2  #allowable error for units from target position

var position: Vector2:
	set(new_position):
		position = new_position
		unit.global_position = position
		
		if _stagger % 8 == 0:
			cell_position = Island.position_to_cell(position)

var direction: Vector2
var cell_position: Vector2i:
	set(new_cell_position):
		if cell_position == new_cell_position:
			return
			
		movement_to_cell.emit(cell_position, new_cell_position)
		cell_position = new_cell_position

var target_position: Vector2
var target_direction: Vector2:
	set(ntd):
		target_direction = ntd.normalized()

var velocity: Vector2
var speed_control: float = 1.0 #goes from 0 to 1, how fast this unit is deciding to move at

func inject_components(n_graphics: Node2D, modifiers_component = null):
	graphics = n_graphics
	if modifiers_component == null:
		return

	_modifiers_component = modifiers_component
	_modifiers_component.register_data(movement_data)
	create_stat_cache(_modifiers_component, [Attributes.id.MAX_SPEED, Attributes.id.ACCELERATION, Attributes.id.TURN_SPEED])
	
func _ready():
	_STAGGER_CYCLE = 3
	_stagger = randi_range(0, _STAGGER_CYCLE)
	position = position #trigger setter functions, esp. cell
	cell_position = Island.position_to_cell(position)
	unit.position = position

func _physics_process(_delta: float) -> void:
	_stagger += 1
	_accumulated_delta += Clock.physics_game_delta

	var local_max_speed: float = get_stat(_modifiers_component, movement_data, Attributes.id.MAX_SPEED)
	#var local_acceleration: float = get_stat(_modifiers_component, movement_data, Attributes.id.ACCELERATION)
	
	if movement_data == null:
		return  # no data → do nothing

	if not movement_data.mobile:
		return
		
	if _accumulated_delta > 0.08:
		if target_position:
			if (target_position - position).length_squared() > _ERROR_SQUARED:
				target_direction = (target_position - position) #recalculate target direction
			else:
				target_direction = Vector2.ZERO
			
		_update_walk_cycle(_accumulated_delta)
		_accumulated_delta = 0.0 #reset accumulated delta

	velocity = target_direction * local_max_speed * speed_control
	
	if face_towards_movement and velocity.length_squared() > 0.01:
		unit.rotation = velocity.angle()
		
	position += velocity * Clock.physics_game_delta

func _update_walk_cycle(delta: float) -> void:
	if not jiggle_enabled or not is_instance_valid(graphics):
		return
		
	# Check if we are moving significantly
	if velocity.length_squared() > 5.0:
		_walk_cycle_time += delta * jiggle_speed
		
		# A. Rotation Waddle (Left <-> Right)
		# We use Sine for smooth oscillation
		var rot_rads = deg_to_rad(jiggle_angle)
		var waddle = sin(_walk_cycle_time) * rot_rads
		
		# Since 'unit.rotation' handles the facing direction, 
		# we just set the child graphics rotation relative to it.
		graphics.rotation = waddle
		
		# B. Scale Bounce (Squash/Stretch)
		# We use abs(sin) or sin(2x) to make it bounce twice per waddle cycle (each step)
		# Adding 1.0 ensures we oscillate around normal size
		var bounce = abs(sin(_walk_cycle_time)) * bounce_amount
		
		# Stretch Y slightly, Squash X slightly to preserve apparent volume
		graphics.scale = Vector2(1.0 - (bounce * 0.3), 1.0 + bounce) * Vector2(0.096, 0.096)
		
	else:
		# Return to neutral pose when stopped
		var return_speed = delta * 10.0
		graphics.rotation = lerp_angle(graphics.rotation, 0.0, return_speed)
		graphics.scale = graphics.scale.lerp(Vector2.ONE * Vector2(0.096, 0.096), return_speed)
		
		# Reset timer logic to keep phase consistent on restart
		if graphics.scale.is_equal_approx(Vector2.ONE * Vector2(0.096, 0.096)):
			_walk_cycle_time = 0.0
