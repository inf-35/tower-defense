extends EffectPrototype
class_name PlagueRiteEffect

@export var required_status: Attributes.Status = Attributes.Status.POISON ##status that must already be present on the hit enemy
@export var spread_status: Attributes.Status = Attributes.Status.POISON ##status applied to the nearest uninfected enemy
@export var stack_multiplier: float = 1.0 ##multiplier applied to the infected target's current stacks
@export var spread_duration: float = 2.0 ##duration of the spread status
@export var spread_radius: float = 45.0 ##search radius around the hit enemy
@export var projectile_count: int = 2 ##maximum number of venom bolts fired from one infected target
@export var projectile_data: AttackData ##small projectile used to carry the copied status

class PlagueRiteState extends RefCounted:
	var pending_targets: Dictionary[int, WeakRef] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = PlagueRiteState.new()
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
	if report.has_lineage_producer(instance):
		_release_pending_target(instance, report.target)
		return

	var poisoned_target: Unit = report.target
	if not _is_valid_infected_target(poisoned_target):
		return

	var stacks: float = poisoned_target.modifiers_component.get_status_count(required_status) * stack_multiplier * float(maxi(instance.stacks, 1))
	if stacks <= 0.0:
		return

	var spread_targets: Array[Unit] = _find_nearest_uninfected_enemies(instance, poisoned_target, projectile_count)
	if spread_targets.is_empty():
		return

	var projectile_fired: bool = false
	for spread_target: Unit in spread_targets:
		projectile_fired = _fire_projectile(instance, source_tower, poisoned_target, spread_target, report, stacks) or projectile_fired

	if projectile_fired:
		trigger_source_tower_pulse(instance)

func _fire_projectile(
	instance: EffectInstance,
	source_tower: Tower,
	origin: Unit,
	target: Unit,
	trigger_report: HitReportData,
	stacks: float
) -> bool: ##launches one lineage-safe spread bolt and reserves its target until that bolt reports back
	if projectile_data == null:
		push_warning("PlagueRiteEffect: triggered but no projectile_data assigned.")
		return false

	var hit_data: HitData = projectile_data.generate_generic_hit_data()
	if not hit_data.derive_lineage_from(trigger_report, instance):
		return false

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

	_reserve_pending_target(instance, target)
	CombatManager.resolve_hit(hit_data, delivery_data)
	return true

func _is_valid_infected_target(target: Unit) -> bool:
	if not is_instance_valid(target) or not target.hostile or target.disabled:
		return false
	if not is_instance_valid(target.modifiers_component):
		return false
	return target.modifiers_component.has_status(required_status)

func _find_nearest_uninfected_enemies(instance: EffectInstance, origin: Unit, count: int) -> Array[Unit]: ##selects only the nearest few eligible enemies from the shared radius-query surface without sorting the full crowd
	var targets: Array[Unit] = []
	if count <= 0:
		return targets

	_prune_pending_targets(instance)
	var state: PlagueRiteState = instance.state as PlagueRiteState
	var origin_position: Vector2 = origin.global_position
	var nearest_distances: Array[float] = []
	var candidates: Array[Unit] = CombatManager.get_units_in_radius(spread_radius, origin_position, true)
	for candidate: Unit in candidates:
		if not _is_valid_spread_target(origin, candidate, state):
			continue

		var distance_squared: float = origin_position.distance_squared_to(candidate.global_position)
		var insert_index: int = 0
		while insert_index < nearest_distances.size() and distance_squared >= nearest_distances[insert_index]:
			insert_index += 1
		if insert_index >= count:
			continue

		targets.insert(insert_index, candidate)
		nearest_distances.insert(insert_index, distance_squared)
		if targets.size() > count:
			targets.pop_back()
			nearest_distances.pop_back()

	return targets

func _is_valid_spread_target(origin: Unit, candidate: Unit, state: PlagueRiteState) -> bool: ##rejects invalid, infected, or already-reserved enemies returned by the hostile-unit radius query
	if not is_instance_valid(candidate) or candidate == origin:
		return false
	if not candidate.hostile or candidate.disabled or candidate.is_queued_for_deletion():
		return false
	if not is_instance_valid(candidate.modifiers_component):
		return false
	if state.pending_targets.has(candidate.get_instance_id()):
		return false
	if candidate.modifiers_component.has_status(spread_status):
		return false
	return true

func _reserve_pending_target(instance: EffectInstance, target: Unit) -> void: ##marks one enemy as already claimed by a bolt from this effect instance
	var state: PlagueRiteState = instance.state as PlagueRiteState
	if state == null or not is_instance_valid(target):
		return

	state.pending_targets[target.get_instance_id()] = weakref(target)

func _release_pending_target(instance: EffectInstance, target: Unit) -> void: ##releases a spread reservation when this instance's child hit reports its arrival
	var state: PlagueRiteState = instance.state as PlagueRiteState
	if state == null or not is_instance_valid(target):
		return

	state.pending_targets.erase(target.get_instance_id())

func _prune_pending_targets(instance: EffectInstance) -> void: ##removes reservations whose targets died before their abstract projectile arrived
	var state: PlagueRiteState = instance.state as PlagueRiteState
	if state == null or state.pending_targets.is_empty():
		return

	var stale_target_ids: Array[int] = []
	for target_id: int in state.pending_targets:
		var target_ref: WeakRef = state.pending_targets[target_id]
		if not is_instance_valid(target_ref) or not is_instance_valid(target_ref.get_ref()):
			stale_target_ids.append(target_id)

	for target_id: int in stale_target_ids:
		state.pending_targets.erase(target_id)
