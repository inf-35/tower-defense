extends EffectPrototype
class_name RupturedHeartEffect

@export var poison_status: Attributes.Status = Attributes.Status.POISON
@export var damage_per_stack: float = 2.0
@export var explosion_data: AttackData

func _init() -> void:
	event_hooks = [GameEvent.EventType.DIED]
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
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dying_unit: Unit = event.unit
	if not is_instance_valid(dying_unit) or not dying_unit.hostile:
		return

	if not is_instance_valid(dying_unit.modifiers_component):
		return

	var poison_stacks: float = _get_status_stacks(dying_unit, poison_status)
	if poison_stacks <= 0.0:
		return
	_trigger_explosion(instance, dying_unit, event.data as HitReportData, poison_stacks * _get_effect_stacks(instance))

func _trigger_explosion(instance: EffectInstance, dying_unit: Unit, hit_report: HitReportData, poison_stacks: float) -> void:
	if explosion_data == null:
		push_warning("RupturedHeartEffect: triggered but no explosion_data assigned.")
		return

	var hit_data: HitData = explosion_data.generate_generic_hit_data()
	hit_data.source = hit_report.source if hit_report != null and is_instance_valid(hit_report.source) else null
	hit_data.target = null
	hit_data.target_affiliation = dying_unit.hostile
	hit_data.damage = poison_stacks * damage_per_stack
	if not hit_data.derive_lineage_from(hit_report, instance):
		return

	var delivery_data: DeliveryData = explosion_data.generate_generic_delivery_data()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = dying_unit.global_position
	delivery_data.intercept_position = dying_unit.global_position
	
	await Clock.await_game_time(0.2)
	CombatManager.resolve_hit(hit_data, delivery_data)

func _get_status_stacks(unit: Unit, status: Attributes.Status) -> float:
	if not unit.modifiers_component._status_effects.has(status):
		return 0.0

	var status_effect: StatusEffect = unit.modifiers_component._status_effects[status]
	return status_effect.stack

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
