extends EffectPrototype
class_name FistRiteEffect

@export var multiplier_per_status: float = 3.0 ##base damage multiplier applied once per unique status consumed by one rite stack

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data:
		return
	if hit_data.negate:
		return

	var target: Unit = hit_data.target
	if not is_instance_valid(target):
		return

	var statuslikes: Dictionary = target.get_statuslikes()
	var statuses: Array[StatusEffect]
	statuses.assign(statuslikes.get(&"statuses", []))
	var effect_instances: Array[EffectInstance]
	effect_instances.assign(statuslikes.get(&"effects", []))
	var consumed_count: int = 0

	for status: StatusEffect in statuses:
		if not is_instance_valid(status):
			continue
		if status.stack <= 0.0:
			continue

		status.stack = 0.0
		target.modifiers_component.update_status(status)
		consumed_count += 1

	for effect_instance: EffectInstance in effect_instances:
		if not is_instance_valid(effect_instance):
			continue
		if not is_instance_valid(effect_instance.effect_prototype):
			continue

		target.remove_effect(effect_instance.effect_prototype)
		consumed_count += 1

	if consumed_count <= 0:
		return

	var total_multiplier: float = pow(get_multiplier_per_status(instance), float(consumed_count))
	hit_data.damage *= total_multiplier
	trigger_source_tower_pulse(instance)

func get_multiplier_per_status(instance: EffectInstance) -> float: ##returns the per-status multiplier after stacked rite copies compound logically
	return pow(multiplier_per_status, float(get_effect_stack_count(instance)))

func get_effect_stack_count(instance: EffectInstance) -> int: ##returns the active rite stack count, treating lone instances as one stack
	return maxi(instance.stacks, 1)
