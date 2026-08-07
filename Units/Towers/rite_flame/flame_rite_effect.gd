extends EffectPrototype
class_name FlameRiteEffect

@export var required_status: Attributes.Status = Attributes.Status.BURN ##enemy status required before affected towers can deal damage
@export var no_status_damage_multiplier: float = 0.5 ##0.5 = half damage against enemies without the required status
@export var damage_multiplier: float = 2.0 ##2.0 = 200% damage against enemies with the required status

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, required_status, true)

func _handle_detach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, required_status, false)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##turns flame rite into a burn-gated damage operator
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if hit_data == null or hit_data.negate:
		return

	var target: Unit = hit_data.target
	if not is_instance_valid(target) or not target.hostile or not is_instance_valid(target.modifiers_component):
		return

	if not target.modifiers_component.has_status(required_status):
		hit_data.damage = hit_data.damage * no_status_damage_multiplier
		return

	hit_data.damage = hit_data.damage * (1.0 + ((damage_multiplier - 1.0) * instance.stacks))
	trigger_source_tower_pulse(instance)
