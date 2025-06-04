extends EffectPrototype
class_name WaveBuffEffect

var reflection: float = 0.001

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
