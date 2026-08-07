extends EffectPrototype
class_name PlagueRiteEffect

@export var required_status: Attributes.Status = Attributes.Status.POISON ##status that must already be present on the hit enemy
@export var spread_status: Attributes.Status = Attributes.Status.POISON ##status applied to the nearest uninfected enemy
@export var stack_multiplier: float = 1.0 ##multiplier applied to the infected target's current stacks
@export var spread_duration: float = 2.0 ##duration of the spread status
@export var spread_radius: float = 45.0 ##search radius around the hit enemy
@export var projectile_count: int = 2 ##maximum number of venom bolts fired from one infected target
@export var projectile_data: AttackData ##small projectile used to carry the copied status

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, required_status, true)

func _handle_detach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, required_status, false)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##spreads poison from a poisoned hit target without adding direct damage
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var report: HitReportData = event.data as HitReportData
	if not report:
		return

	var source_tower: Tower = instance.host as Tower
	if not is_instance_valid(source_tower) or report.source != source_tower:
		return

	var poisoned_target: Unit = report.target
	if not _is_valid_infected_target(poisoned_target):
		return

	var stacks: float = poisoned_target.modifiers_component.get_status_count(required_status) * stack_multiplier * float(maxi(instance.stacks, 1))
	if stacks <= 0.0:
		return

	var spread_targets: Array[Unit] = _find_nearest_uninfected_enemies(poisoned_target, projectile_count)
	if spread_targets.is_empty():
		return

	for spread_target: Unit in spread_targets:
		_fire_projectile(instance, source_tower, poisoned_target, spread_target, report, stacks)

func _fire_projectile(
	instance: EffectInstance,
	source_tower: Tower,
	origin: Unit,
	target: Unit,
	trigger_report: HitReportData,
	stacks: float
) -> void:
	if projectile_data == null:
		push_warning("PlagueRiteEffect: triggered but no projectile_data assigned.")
		return

	var hit_data: HitData = projectile_data.generate_generic_hit_data()
	if not hit_data.derive_lineage_from(trigger_report, instance):
		return

	hit_data.source = trigger_report.get_source_unit(source_tower)
	hit_data.target = target
	hit_data.target_affiliation = target.hostile
	hit_data.attack_id = AttackComponent.get_next_attack_id()
	hit_data.primary = false
	hit_data.status_effects[spread_status] = Vector2(stacks, spread_duration)

	var delivery_data: DeliveryData = projectile_data.generate_generic_delivery_data()
	delivery_data.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT
	delivery_data.use_source_position_override = true
	delivery_data.source_position = origin.global_position
	delivery_data.intercept_position = target.global_position

	CombatManager.resolve_hit(hit_data, delivery_data)
	trigger_source_tower_pulse(instance)

func _is_valid_infected_target(target: Unit) -> bool:
	if not is_instance_valid(target) or not target.hostile or target.disabled:
		return false
	if not is_instance_valid(target.modifiers_component):
		return false
	return target.modifiers_component.has_status(required_status)

func _find_nearest_uninfected_enemies(origin: Unit, count: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	if count <= 0:
		return targets

	var candidates: Array[Unit] = []

	for unit_node: Node in origin.get_tree().get_nodes_in_group(DebugAssistant.GROUP_UNITS):
		var candidate: Unit = unit_node as Unit
		if not _is_valid_spread_target(origin, candidate):
			continue

		candidates.append(candidate)

	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return origin.global_position.distance_squared_to(a.global_position) < origin.global_position.distance_squared_to(b.global_position)
	)

	for candidate: Unit in candidates:
		targets.append(candidate)
		if targets.size() >= count:
			break

	return targets

func _is_valid_spread_target(origin: Unit, candidate: Unit) -> bool:
	if not is_instance_valid(candidate) or candidate == origin:
		return false
	if not candidate.hostile or candidate.disabled or candidate.is_queued_for_deletion():
		return false
	if not is_instance_valid(candidate.modifiers_component):
		return false
	if candidate.modifiers_component.has_status(spread_status):
		return false
	return origin.global_position.distance_squared_to(candidate.global_position) <= spread_radius * spread_radius
