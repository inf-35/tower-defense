extends EffectPrototype
class_name HitDealtDebugEffect

@export var params: Dictionary = {
	"message": "pew pew!",
}

var state: Dictionary = {
	"counter" = 0
}

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return
	
	assert(instance.params.has("message") and instance.state.has("counter"))

	var hit_data: HitReportData = event.data as HitReportData

	print(instance.params.message," ",instance.state.counter)
	instance.state.counter += 1
	
