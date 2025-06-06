extends Resource
class_name EffectPrototype #used for cause-and-effect structures -> this is the mere effectprototype, to see runtime behaviour 
#consult EffectInstance; for actual behaviour see sub-classes
#i.e. things like thorns

var effect_type: Effects.Type #id of this type of effect
var event_hooks: Array[GameEvent.EventType] #just for information, the event hooks can be found in per-handler behaviour
var duration: float = -1.0 #negative = permanent

#neat container for arbitrary params
#@export params: Dictionary = {} (please find in sub-classes)

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
	assert("params" in self) #ensure that the subclass that class this has the variable params
	
	var effect_instance := EffectInstance.new()
	effect_instance.effect_type = effect_type
	effect_instance.event_hooks = event_hooks
	effect_instance.duration = duration
	effect_instance.effect_prototype = self as EffectPrototype
	effect_instance.params = self.params
	
	return effect_instance
	
