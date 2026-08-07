extends EffectPrototype
class_name FrostRiteEffect

@export var qualifying_status: Attributes.Status = Attributes.Status.FROST ##target status required before brittle can be attached
@export var brittle_effect: BrittleEffect ##temporary effect attached to frosted targets hit by the affected tower
@export var brittle_duration: float = 3.0 ##seconds brittle remains after refresh

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, qualifying_status, true)

func _handle_detach(instance: EffectInstance) -> void:
	_set_targeting_preference(instance, qualifying_status, false)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##marks frosted targets so brittle handles heavy-hit multipliers while active
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var report: HitReportData = event.data as HitReportData
	if not report:
		return

	var source_tower: Tower = instance.host as Tower
	if not is_instance_valid(source_tower) or report.source != source_tower:
		return

	var target: Unit = report.target
	if not _can_mark_brittle(target):
		return

	var brittle_instance: EffectInstance = target.get_effect_instance_by_prototype(brittle_effect)
	if not is_instance_valid(brittle_instance):
		brittle_instance = target.apply_effect(brittle_effect)
		if not is_instance_valid(brittle_instance):
			return

	brittle_instance.source = instance.source
	brittle_instance.refresh_duration(brittle_duration)
	trigger_source_tower_pulse(instance)

func _can_mark_brittle(target: Unit) -> bool:
	if not is_instance_valid(target) or not target.hostile or target.disabled:
		return false
	if not is_instance_valid(target.modifiers_component):
		return false
	if not is_instance_valid(brittle_effect):
		return false
	return target.modifiers_component.has_status(qualifying_status)
