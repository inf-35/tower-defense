extends EffectPrototype
class_name PlagueRiteEffect

@export var required_status: Attributes.Status = Attributes.Status.POISON ##status that must already be present on the hit enemy
@export var spread_status: Attributes.Status = Attributes.Status.POISON ##status applied to the nearest uninfected enemy
@export var spread_stacks: float = 1.0 ##stacks spread per effect stack
@export var spread_duration: float = 2.0 ##duration of the spread status
@export var spread_radius: float = 45.0 ##search radius around the hit enemy

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

	var spread_target: Unit = _find_nearest_uninfected_enemy(poisoned_target)
	if not is_instance_valid(spread_target):
		return

	var stacks: float = spread_stacks * float(maxi(instance.stacks, 1))
	var did_apply_status: bool = spread_target.modifiers_component.add_status(spread_status, stacks, spread_duration, source_tower.unit_id)
	if not did_apply_status:
		return

	if is_instance_valid(icon):
		UI.floating_text_manager.show_icon(icon, spread_target.global_position)
	trigger_source_tower_pulse(instance)

func _is_valid_infected_target(target: Unit) -> bool:
	if not is_instance_valid(target) or not target.hostile or target.disabled:
		return false
	if not is_instance_valid(target.modifiers_component):
		return false
	return target.modifiers_component.has_status(required_status)

func _find_nearest_uninfected_enemy(origin: Unit) -> Unit:
	var nearest_enemy: Unit = null
	var nearest_distance_squared: float = INF

	for unit_node: Node in origin.get_tree().get_nodes_in_group(DebugAssistant.GROUP_UNITS):
		var candidate: Unit = unit_node as Unit
		if not _is_valid_spread_target(origin, candidate):
			continue

		var distance_squared: float = origin.global_position.distance_squared_to(candidate.global_position)
		if distance_squared >= nearest_distance_squared:
			continue

		nearest_distance_squared = distance_squared
		nearest_enemy = candidate

	return nearest_enemy

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
