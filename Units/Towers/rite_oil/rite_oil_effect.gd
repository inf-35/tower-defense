extends EffectPrototype
class_name OilRiteEffect

@export var duration_bonus: float = 2.5

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var i := EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i): pass
func _handle_detach(_i): pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT: return
	
	var hit_data = event.data as HitData
	if not hit_data: return

	for status in hit_data.status_effects:
		var payload: Vector2 = hit_data.status_effects[status]
		# x=stacks, y=duration
		payload.y += (duration_bonus * instance.stacks)
		
		hit_data.status_effects[status] = payload
