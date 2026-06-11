extends EffectPrototype
class_name SapphireIdolEffect

@export var qualifying_status: Attributes.Status = Attributes.Status.FROST ##when this status is applied, the relic prolongs the victim's active statuses
@export var minimum_duration: float = 1.0 ##all timed statuses on the victim are raised to at least this much remaining duration

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]
	global = true

func create_instance() -> EffectInstance: ##creates a stateless global relic effect that reacts after statuses have already been applied to the victim
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##only runs when the hit actually applied frost, then prolongs every timed status on that enemy to the configured floor
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var hit_report: HitReportData = event.data as HitReportData
	if not is_instance_valid(hit_report) or not is_instance_valid(hit_report.target):
		return

	var target: Unit = hit_report.target
	if not target.hostile or not hit_report.statuses_applied.has(qualifying_status):
		return

	if not is_instance_valid(target.modifiers_component):
		return

	var duration_floor: float = minimum_duration * float(maxi(instance.stacks, 1))
	if duration_floor <= 0.0:
		return

	_prolong_statuses(target.modifiers_component, duration_floor)

func _prolong_statuses(modifiers_component: ModifiersComponent, duration_floor: float) -> void: ##raises all active timed statuses to at least the requested remaining lifetime without disturbing stacks
	for status_type: Attributes.Status in modifiers_component._status_effects:
		var status: StatusEffect = modifiers_component._status_effects[status_type]
		if not is_instance_valid(status) or not is_instance_valid(status.timer):
			continue

		var remaining_duration: float = status.timer.duration - status.timer.time_elapsed
		if remaining_duration >= duration_floor:
			continue

		status.timer.duration = status.timer.time_elapsed + duration_floor
		status.cooldown = maxf(status.cooldown, duration_floor)
		modifiers_component.status_changed.emit(status.type, status.stack, duration_floor)
