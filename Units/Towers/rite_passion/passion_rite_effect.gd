extends EffectPrototype
class_name PassionRiteEffect

@export var required_status: Attributes.Status = Attributes.Status.BURN ##enemy status that converts the damage penalty into burn-stack scaling
@export var no_status_damage_multiplier: float = 0.75 ##damage multiplier against enemies without the required status
@export var damage_bonus_per_status_stack: float = 1.0 ##1.0 = +100% damage per target status stack per overlapping rite

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

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##converts burn stacks on the target into a local damage amplifier
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if hit_data == null or hit_data.negate:
		return

	var target: Unit = hit_data.target
	if not is_instance_valid(target) or not target.hostile or not is_instance_valid(target.modifiers_component):
		return

	var status_stacks: float = target.modifiers_component.get_status_count(required_status)
	if status_stacks <= 0.0:
		hit_data.damage *= no_status_damage_multiplier
		return

	hit_data.damage *= 1.0 + (status_stacks * damage_bonus_per_status_stack * float(maxi(instance.stacks, 1)))
	trigger_source_tower_pulse(instance)
