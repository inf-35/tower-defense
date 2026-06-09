extends EffectPrototype
class_name WeregildEffect

@export var flux_per_tower_death: float = 3.0

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

	if Run.phases.current_phase != Run.phases.GamePhase.COMBAT_WAVE:
		return

	var tower: Tower = event.unit as Tower
	if not is_instance_valid(tower) or tower.hostile or tower.environmental:
		return

	var report: HitReportData = event.data as HitReportData
	if not report or not report.death_caused:
		return

	Run.player.flux += flux_per_tower_death * _get_effect_stacks(instance)

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
