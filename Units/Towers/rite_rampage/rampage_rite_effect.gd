extends EffectPrototype
class_name RampageRiteEffect

@export var trigger_chance: float = 0.50
@export var max_chain_count: int = 3 ##maximum number of rampage-produced attacks allowed in one recursive lineage

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i) -> void: pass
func _handle_detach(_i) -> void: pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT: return

	var hit_report: HitReportData = event.data as HitReportData
	if not hit_report or not hit_report.death_caused: return
	var safe_chain_count: int = maxi(max_chain_count, 1)
	if hit_report.get_lineage_producer_count(instance) >= safe_chain_count: return

	if randf() > (trigger_chance * instance.stacks): return

	var killer: Unit = event.unit
	if is_instance_valid(killer) and is_instance_valid(killer.attack_component):
		killer.attack_component.queue_next_attack_context(hit_report, instance, false, Vector2.ZERO, false, 0.0, safe_chain_count)
		killer.attack_component.current_cooldown = 0.1
		if killer is Tower:
			if is_instance_valid(hit_report.target):
				BuffComponent.play_link_wisp_from_position(hit_report.target.global_position, killer)
			var source_tower: Tower = _resolve_source_tower(instance)
			if is_instance_valid(source_tower):
				BuffComponent.play_link_wisp(source_tower, killer)
			trigger_target_bonus_feedback(killer as Tower)
		trigger_source_tower_pulse(instance)
