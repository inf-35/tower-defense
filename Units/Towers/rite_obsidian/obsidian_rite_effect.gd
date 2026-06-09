extends EffectPrototype
class_name ObsidianRiteEffect

@export var converted_duration: float = 3.0

const CONVERTED_STATUSES: Array[Attributes.Status] = [
	Attributes.Status.FROST,
	Attributes.Status.BLEED,
	Attributes.Status.CURSED,
]

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
	if not report:
		return

	var source_tower: Tower = instance.host as Tower
	if not is_instance_valid(source_tower) or report.source != source_tower:
		return

	var target: Unit = report.target
	if not is_instance_valid(target) or not target.hostile:
		return

	if not is_instance_valid(target.modifiers_component):
		return

	if not target.modifiers_component._status_effects.has(Attributes.Status.BURN):
		return

	var burn_status: StatusEffect = target.modifiers_component._status_effects[Attributes.Status.BURN]
	var converted_stacks: float = burn_status.stack * _get_effect_stacks(instance)
	if converted_stacks <= 0.0:
		return

	var duration: float = _get_remaining_duration(burn_status)
	burn_status.stack = 0.0
	target.modifiers_component.update_status(burn_status)

	for status: Attributes.Status in CONVERTED_STATUSES:
		target.modifiers_component.add_status(status, converted_stacks, duration, source_tower.unit_id)

func _get_remaining_duration(status: StatusEffect) -> float:
	if is_instance_valid(status.timer):
		return maxf(status.timer.duration - status.timer.time_elapsed, 0.1)

	return converted_duration

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
