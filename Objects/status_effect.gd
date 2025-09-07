extends RefCounted
class_name StatusEffect #status effect, creates and updates underlying modifiers

var type: Attributes.Status #diegetic status (ie frost, poison, fire etc.)
var stack: float = 1.0
var cooldown: float = 1.0 #negative = permanent
var source_id: int #TODO: actually make this work
#runtime variables
var timer: Clock.GameTimer # a direct reference to the timer node that controls this status's lifecycle
var _modifier: Modifier #the modifier underlying this status effect

func _init(_status: Attributes.Status, _stack: float, _cooldown: float, _source_id: int):
	type = _status
	stack = _stack
	cooldown = _cooldown
	source_id = _source_id

# this new function encapsulates the logic for refreshing an existing status
func refresh(new_stack: float, new_cooldown: float) -> void:
	# 1. stack precedence: the new stack is the HIGHEST of the old or new value
	self.stack = max(self.stack, new_stack)
	# 2. duration precedence: the new duration is the LONGEST of what remains or the new cooldown
	var remaining_time: float = 0.0
	if is_instance_valid(timer):
		remaining_time = timer.duration

	var new_duration: float = max(remaining_time, new_cooldown)
	# restart the timer with the new, dominant duration
	if is_instance_valid(timer) and new_duration > 0.0:
		timer.duration = new_duration

		
# this function is called when the timer runs out
func on_timeout() -> void:
	self.stack = 0
	# the ModifiersComponent will see stack=0 and handle the removal
# called when the status is being removed to ensure cleanup
func cleanup() -> void:
	pass

func can_stack() -> bool:
	return Attributes.status_effects[type].can_stack
	
func attribute() -> Attributes.id:
	return Attributes.status_effects[type].attribute
