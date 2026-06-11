extends EffectPrototype
class_name EpidemicEffect

@export var poison_status: Attributes.Status = Attributes.Status.POISON
@export var search_radius: float = 40.0
@export var poison_duration: float = 1.0
@export var projectile_data: AttackData

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

	if not is_instance_valid(victim.modifiers_component):
		return

	var poison_stacks: float = _get_status_stacks(victim, poison_status)
	if poison_stacks <= 0.0:
		return

	var target: Unit = _find_target(victim)
	if not is_instance_valid(target):
		return

	_fire_projectile(instance, victim, target, hit_data, poison_stacks * _get_effect_stacks(instance))

func _find_target(origin_unit: Unit) -> Unit:
	var candidates: Array[Unit] = CombatManager.get_units_in_radius(
		search_radius,
		origin_unit.global_position,
		origin_unit.hostile,
		[origin_unit]
	)

	candidates.shuffle()
	for candidate: Unit in candidates:
		if _is_valid_target(candidate):
			return candidate

	return null

func _fire_projectile(instance: EffectInstance, origin_unit: Unit, target: Unit, trigger_hit: HitData, poison_stacks: float) -> void:
	if projectile_data == null:
		push_warning("EpidemicEffect: triggered but no projectile_data assigned.")
		return

	var hit_data: HitData = projectile_data.generate_generic_hit_data()
	if not hit_data.derive_lineage_from(trigger_hit, instance):
		return
	hit_data.source = null
	hit_data.target = target
	hit_data.target_affiliation = origin_unit.hostile
	hit_data.status_effects[poison_status] = Vector2(poison_stacks, poison_duration)

	var delivery_data: DeliveryData = projectile_data.generate_generic_delivery_data()
	delivery_data.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT
	delivery_data.use_source_position_override = true
	delivery_data.source_position = origin_unit.global_position
	delivery_data.intercept_position = target.global_position
	
	await Clock.await_game_time(0.15)
	if target:
		CombatManager.resolve_hit(hit_data, delivery_data)

func _get_status_stacks(unit: Unit, status: Attributes.Status) -> float:
	if not is_instance_valid(unit) or not is_instance_valid(unit.modifiers_component):
		return 0.0

	return unit.modifiers_component.get_status_count(status)

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)

func _is_valid_target(candidate: Unit) -> bool: ##keeps epidemic focused on fresh hosts so one poisoned enemy does not keep recirculating poison into another
	if not is_instance_valid(candidate) or not is_instance_valid(candidate.health_component):
		return false

	return _get_status_stacks(candidate, poison_status) <= 0.0
