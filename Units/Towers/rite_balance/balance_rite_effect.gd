extends EffectPrototype
class_name BalanceRiteEffect

@export var search_radius: float = 120.0
@export var projectile_data: AttackData

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var report: HitReportData = event.data as HitReportData
	if not report or report.overkill <= 0.0:
		return

	var source_tower: Tower = instance.host as Tower
	if not is_instance_valid(source_tower) or report.source != source_tower:
		return

	if not is_instance_valid(report.target) or not report.target.hostile:
		return
	
	var origin_position: Vector2 = report.target.global_position
	var hostile: bool = report.target.hostile
	await Clock.await_game_time(0.01)
	var target: Unit = _find_nearest_enemy(origin_position, hostile)
	if not is_instance_valid(target):
		return

	trigger_source_tower_pulse(instance)
	_fire_overkill_bolt(instance, source_tower, report, origin_position, target, report.overkill * _get_effect_stacks(instance))

func _find_nearest_enemy(origin_position: Vector2, hostile: bool) -> Unit:
	var candidates: Array[Unit] = CombatManager.get_units_in_radius(search_radius, origin_position, hostile, [])
	var best_target: Unit
	var best_distance: float = INF

	for candidate: Unit in candidates:
		if not _is_valid_bolt_target(candidate):
			continue

		var distance: float = candidate.global_position.distance_squared_to(origin_position)
		if distance < best_distance:
			best_distance = distance
			best_target = candidate

	return best_target

func _fire_overkill_bolt(instance: EffectInstance, source_tower: Tower, parent_report: HitReportData, source_position: Vector2, target: Unit, damage: float) -> void:
	if projectile_data == null:
		return

	if not _is_valid_bolt_target(target):
		return

	var hit_data: HitData = projectile_data.generate_generic_hit_data()
	hit_data.source = source_tower
	hit_data.target = target
	hit_data.target_affiliation = target.hostile
	hit_data.damage = damage
	if not hit_data.derive_lineage_from(parent_report, instance):
		return

	var delivery_data: DeliveryData = projectile_data.generate_generic_delivery_data()
	delivery_data.target = target
	delivery_data.use_source_position_override = true
	delivery_data.source_position = source_position
	delivery_data.intercept_position = target.global_position

	CombatManager.resolve_hit(hit_data, delivery_data)

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)

func _is_valid_bolt_target(target: Unit) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false

	if not target.hostile or target.disabled or target.incorporeal or target.abstractive:
		return false

	if not is_instance_valid(target.health_component):
		return false

	if is_zero_approx(target.health_component.health):
		return false

	return true
