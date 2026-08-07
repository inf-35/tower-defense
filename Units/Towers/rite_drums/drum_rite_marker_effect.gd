extends EffectPrototype
class_name DrumRiteMarkerEffect

func _init() -> void: ##marks a tower as affected by drums without adding extra event behavior
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void:
	pass
