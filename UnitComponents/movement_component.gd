extends UnitComponent
class_name MovementComponent

signal movement_to_cell(origin: Vector2i, destination: Vector2i)

var _modifiers_component: ModifiersComponent

@export var movement_data: MovementData = preload("res://Data/Movement/default_mvmt.tres")
var graphics: Node2D

const _ERROR_SQUARED: float = 2.0 ** 2  #allowable error for units from target position

var position: Vector2:
	set(new_position):
		position = new_position
		cell_position = Island.position_to_cell(position)
		unit.position = position

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
	unit.position = position

func _physics_process(delta: float) -> void:
	#_stagger += 1
	#_accumulated_delta += delta
		#
	#if _stagger % _STAGGER_CYCLE != 1:
		#return
	
	var local_max_speed: float = get_stat(_modifiers_component, movement_data, Attributes.id.MAX_SPEED)
	var local_acceleration: float = get_stat(_modifiers_component, movement_data, Attributes.id.ACCELERATION)
		
	if movement_data == null:
		return  # no data → do nothing

	if not movement_data.mobile:
		return

	if target_position:
		if (target_position - position).length_squared() > _ERROR_SQUARED:
			target_direction = (target_position - position) #recalculate target direction
		else:
			target_direction = Vector2.ZERO

	# accelerate/decelerate to match max_speed
	var target_speed = local_max_speed
	if target_direction.length_squared() < 0.0001: #Vector2.ZERO
		target_speed = 0.0

	velocity = velocity.move_toward(
		target_direction * target_speed,
		local_acceleration * delta,
	)

	position += velocity * delta
	
	#_accumulated_delta = 0.0 #reset accumulated delta
