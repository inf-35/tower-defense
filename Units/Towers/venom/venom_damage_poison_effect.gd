extends EffectPrototype
class_name VenomDamagePoisonEffect

@export var base_poison_stacks: float = 0.0 ##extra poison stacks applied before damage scaling
@export var damage_per_poison_stack: float = 0.5 ##real damage taken required for each poison stack applied by venom
@export var max_poison_stacks: float = 5.0 ##maximum poison stacks applied from one venom hit
@export var poison_duration: float = 0.533333 ##duration of poison applied by venom's damage-scaling effect

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

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##applies poison from venom hits according to post-mitigation damage actually taken
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var report: HitReportData = event.data as HitReportData
	if report == null:
		return

	var source_tower: Tower = instance.host as Tower
	if not is_instance_valid(source_tower) or report.source != source_tower:
		return

	var target: Unit = report.target
	if not _can_apply_poison(target):
		return

	var poison_stacks: float = _get_poison_stacks(report.damage_caused)
	if poison_stacks <= 0.0:
		return

	var did_apply_status: bool = target.modifiers_component.add_status(
		Attributes.Status.POISON,
		poison_stacks,
		poison_duration,
		source_tower.unit_id
	)
	if did_apply_status:
		report.statuses_applied[Attributes.Status.POISON] = Vector2(poison_stacks, poison_duration)

func _can_apply_poison(target: Unit) -> bool: ##filters out dead, invalid, or statusless targets before applying venom's dynamic poison
	if not is_instance_valid(target) or target.disabled:
		return false
	return is_instance_valid(target.modifiers_component)

func _get_poison_stacks(damage_taken: float) -> float: ##converts real damage taken into capped poison stacks in full damage chunks
	if damage_per_poison_stack <= 0.0:
		return 0.0

	var raw_stacks: float = ceilf(damage_taken / damage_per_poison_stack) + base_poison_stacks
	return float(clamp(raw_stacks, 0, max_poison_stacks))
