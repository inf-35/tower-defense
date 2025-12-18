extends EffectPrototype
class_name HitDealtDebugEffect

@export var message: String = "pew!"

class HitDebugState extends RefCounted:
	var counter: int = 0
	
func _init():
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = HitDebugState.new()
	
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	#one-time effect upon attaching to something
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	#undo _attach
	pass

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return
	
	assert(instance.params.has("message") and instance.state.has("counter"))
	instance.state.counter += 1
	
