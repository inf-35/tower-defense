extends EffectPrototype
class_name HealthRatioDamageEffect

@export var max_bonus_multiplier: float = 1.0 ##maximum extra damage at the qualifying health endpoint
@export var use_current_health: bool = true ##true scales with current hp, false scales with missing hp

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

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##scales outgoing damage by the target's current or missing health ratio
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate:
		return

	var target: Unit = hit_data.target
	if not is_instance_valid(target) or not is_instance_valid(target.health_component):
		return
	if target.health_component.max_health <= 0.0:
		return

	var hp_ratio: float = target.health_component.health / target.health_component.max_health
	var scaling_ratio: float = hp_ratio if use_current_health else 1.0 - hp_ratio
	var multiplier: float = 1.0 + scaling_ratio * max_bonus_multiplier * maxf(float(instance.stacks), 1.0)
	hit_data.damage *= multiplier
	trigger_source_tower_pulse(instance)
