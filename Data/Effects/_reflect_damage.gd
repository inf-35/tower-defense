extends EffectPrototype
class_name ReflectDamageEffect

@export var params: Dictionary = {
	"reflection": 0.001,
}

var state: Dictionary = {}

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	assert(instance.params.has("reflection"))

	var hit_data: HitData = event.data as HitData

	var reflect_hit := HitData.new()
	reflect_hit.damage = hit_data.damage * instance.params.reflection
	reflect_hit.source = instance.host
	reflect_hit.target = hit_data.source
	
	reflect_hit.target.deal_hit(reflect_hit)
