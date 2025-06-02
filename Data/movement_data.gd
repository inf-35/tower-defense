extends Data
class_name MovementData

@export var mobile: bool = true #whether the unit is able to move

@export_category("Speed")
@export var max_speed: float = 100.0:
	set(new_value):
		max_speed = new_value
		value_changed.emit(Attributes.id.MAX_SPEED)
@export var acceleration: float = 100.0:
	set(new_value):
		acceleration = new_value
		value_changed.emit(Attributes.id.ACCELERATION)

@export_category("Turning")
@export var turn_speed: float = 360.0: # degrees per second
	set(new_value):
		turn_speed = new_value
		value_changed.emit(Attributes.id.TURN_SPEED)  
