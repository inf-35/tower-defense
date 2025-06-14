extends Object
class_name EffectInstance #used for cause-and-effect structures -> this is the mere instance, to see actual data
#see EffectPrototype and its subclasses.
#i.e. things like thorns

var effect_prototype: EffectPrototype #effect prototype we're based off.

var source_id: int #id of who spawned this
var effect_type: Effects.Type #id of this type of effect
var event_hooks: Array[GameEvent.EventType]
var duration: float = -1.0 #negative = permanent

#var stack: int = 1: #how many "stacks" of the same effect do we have
	#set(new_stack):
		#stack = new_stack
		#if stack <= 0:
			#free()

var params: Dictionary = {} #for input parameters
var state: Dictionary = {} #for internal state variables

const GLOBAL_RECURSION_LIMIT: int = 0 #limit for effect recursion; see Unit effect parsing

var host: Unit #to which unit does this effect apply onto

func _init():
	pass
	
func detach() -> void:
	if is_instance_valid(host):
		effect_prototype.detach_handler.call(self)
	
func attach_to(_host: Unit) -> void:
	if is_instance_valid(host):
		effect_prototype.detach_handler.call(self)
	
	host = _host
	effect_prototype.attach_handler.call(self)

func handle_event_unfiltered(event: GameEvent) -> void: #called by Unit in setup_event_bus
	if not is_instance_valid(host): #reject if host is dead
		return
	
	#for i in stack:
	effect_prototype.event_handler.call(self, event)
