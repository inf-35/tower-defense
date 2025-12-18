extends EffectPrototype
class_name DeathOnWaveEffect

@export var waves_to_death: int = 2

class DeathOnWaveState extends RefCounted:
	var local_counter: int = 0

func _init():
	event_hooks = [GameEvent.EventType.WAVE_STARTED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = DeathOnWaveState.new()
	return instance

func _handle_attach(instance: EffectInstance):
	var state := instance.state as DeathOnWaveState
	state.local_counter = waves_to_death

func _handle_detach(instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
		
	var state := instance.state as DeathOnWaveState
	state.local_counter -= 1
	if state.local_counter <= 0:
		instance.host.died.emit()
