extends Object
class_name EffectInstance #used for cause-and-effect structures -> this is the mere instance, to see actual data
#see EffectPrototype and its subclasses.

var effect_prototype: EffectPrototype ##effect prototype we're based off.

var source_id: int ##id of who spawned this
var effect_type: Effects.Type ##id of this type of effect
var event_hooks: Array[GameEvent.EventType]
var duration: float = -1.0 ##negative = permanent

var stacks: int = 0 ##how many stacks of this effect (mainly used for bookkeeping)

var state: RefCounted ##strategy delegate class that stores state information
#NOTE: all queryable information about the information should be stored within state
#or within effectprototype

const GLOBAL_RECURSION_LIMIT: int = 5 ##limit for effect recursion; see Unit effect parsing

var host: Unit ##to which unit does this effect apply onto
var global: bool = false ##whether this effect is a local(unit-wise) or global (game-wise) effect

func _init():
	pass
	
func detach() -> void:
	if is_instance_valid(host):
		effect_prototype.detach_handler.call(self)
	
func attach_to(_host: Unit) -> void:
	detach()
	host = _host
	
	if is_instance_valid(host) and not host.disabled: #reject if host is disabled
		effect_prototype.attach_handler.call(self)

func attach_global() -> void: ##for attaching as a global effect
	effect_prototype.attach_handler.call(self)

func handle_event_unfiltered(event: GameEvent) -> void: #called by Unit in setup_event_bus
	if not global:
		if not is_instance_valid(host): #reject if host is dead
			return
		
		if host.disabled: #reject if host is disabled
			return
	
	effect_prototype.event_handler.call(self, event)
