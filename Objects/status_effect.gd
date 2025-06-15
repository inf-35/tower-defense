extends RefCounted
class_name StatusEffect #status effect, creates and updates underlying modifiers

var type: Attributes.Status #diegetic status (ie frost, poison, fire etc.)
var stack: float = 1.0
var cooldown: float = 1.0 #negative = permanent

var _modifier: Modifier #the modifier underlying this status effect

var source_id: int #TODO: actually make this work

func _init(_status: Attributes.Status, _stack: float):
	type = _status
	stack = _stack

func can_stack() -> bool:
	return Attributes.status_effects[type].can_stack
	
func attribute() -> Attributes.id:
	return Attributes.status_effects[type].attribute
