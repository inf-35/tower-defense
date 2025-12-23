extends EffectPrototype
class_name SepsisEffect

@export var qualifying_status: Attributes.Status = Attributes.Status.BLEED
@export var target_status: Attributes.Status = Attributes.Status.POISON
@export var duration_multiplier: float = 1.5 ## 1.5 = +50% Duration

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var hit_data := event.data as HitData
	if not hit_data:
		return

	var victim: Unit = event.unit
	if not is_instance_valid(victim) or not is_instance_valid(victim.modifiers_component):
		return

	if not victim.modifiers_component.has_status(qualifying_status):
		return

	if not hit_data.status_effects.has(target_status):
		return

	# status effects are stored as Vector2(stacks, duration)
	var current_payload: Vector2 = hit_data.status_effects[target_status]
	current_payload.y *= duration_multiplier
	hit_data.status_effects[target_status] = current_payload
