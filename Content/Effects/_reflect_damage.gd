extends EffectPrototype
class_name ReflectDamageEffect

@export var reflection: float = 0.01 ##proportion of damage reflected

func _init():
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	
func create_instance() -> EffectInstance: #must be implemented in subclasses
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(instance: EffectInstance) -> void: #one-time effect upon attaching to something
	pass

func _handle_detach(instance: EffectInstance) -> void: #undo _attach
	pass

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData

	var reflect_hit := HitData.new()
	reflect_hit.damage = hit_data.damage * reflection
	reflect_hit.source = instance.host
	reflect_hit.target = hit_data.source
	reflect_hit.recursion = hit_data.recursion + 1
	
	reflect_hit.target.deal_hit(reflect_hit)
