extends EffectPrototype
class_name AlchemistsStoneEffect

@export var damage_bonus_per_extra_status: float = 0.30

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

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data:
		return

	var victim: Unit = event.unit
	if not is_instance_valid(victim) or not victim.hostile:
		return

	var statuslikes: Dictionary = victim.get_statuslikes()
	var statuses: Array[StatusEffect]
	statuses.assign(statuslikes.get(&"statuses", []))
	var effects: Array[EffectInstance]
	effects.assign(statuslikes.get(&"effects", []))
	var unique_statuses: int = statuses.size() + effects.size()
	var extra_statuses: int = maxi(unique_statuses - 1, 0)
	if extra_statuses <= 0:
		return

	hit_data.damage *= 1.0 + (extra_statuses * damage_bonus_per_extra_status * _get_effect_stacks(instance))

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
