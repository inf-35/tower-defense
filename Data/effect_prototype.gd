extends Resource
class_name EffectPrototype #used for cause-and-effect structures -> this is the mere effectprototype, to see runtime behaviour 
#consult EffectInstance; for actual behaviour see sub-classes
#i.e. things like thorns

@export var effect_type: Effects.Type #id of this type of effect
var event_hooks: Array[GameEvent.EventType] #just for information, the event hooks can be found in per-handler behaviour
var duration: float = -1.0 #negative = permanent

#data containers
#@export abstract var params: Dictionary = {} #used for input params. should be exported to inspector.
#abstract var state: Dictionary = {} #used for internal state variables. should not be exposed.

enum Schedule { #schedule categories, used to enforce determinstic ordering of effects
	MULTIPLICATIVE,
	ADDITIVE,
	REACTIVE,
}

@export var schedule: Schedule = Schedule.REACTIVE #NOTE: schedule is a purely effect_prototype-handled variable

#inject handler functions into EffectInstance
var attach_handler: Callable = _handle_attach
var detach_handler: Callable = _handle_detach
var event_handler: Callable = _handle_event

func _init():
	pass

#event handlers; these are injected into EffectInstance at runtime
func _handle_attach(instance: EffectInstance) -> void: #one-time effect upon attaching to something
	pass #override

func _handle_detach(instance: EffectInstance) -> void: #undo _attach
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	pass #override in sub-classes
	
func create_instance() -> EffectInstance:
	assert("params" in self) #ensure that the subclass has parameters
	assert("state" in self) #ensure that the subclass has state
	
	var effect_instance := EffectInstance.new()
	effect_instance.effect_type = effect_type
	effect_instance.event_hooks = event_hooks
	effect_instance.duration = duration
	effect_instance.effect_prototype = self as EffectPrototype
	
	effect_instance.params = self.params.duplicate(true)
	effect_instance.state = self.state.duplicate(true)
	
	return effect_instance
	
