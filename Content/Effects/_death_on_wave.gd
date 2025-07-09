extends EffectPrototype
class_name DeathOnWaveEffect

@export var params: Dictionary = {
	"waves_to_death": 2,
}

var state: Dictionary = {
	"local_counter": 0,
}

func _handle_attach(instance: EffectInstance):
	assert(instance.params.has("waves_to_death") and instance.state.has("local_counter"))
	instance.state.local_counter = instance.params.counter

func _handle_event(instance: EffectInstance, event: GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
		
	assert(instance.params.has("waves_to_death") and instance.state.has("local_counter"))
	
	instance.state.local_counter -= 1
	if instance.state.local_counter <= 0:
		instance.host.died.emit()
