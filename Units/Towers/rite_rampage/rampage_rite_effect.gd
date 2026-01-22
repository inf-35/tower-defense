extends EffectPrototype
class_name RampageRiteEffect

@export var trigger_chance: float = 0.50

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i): pass
func _handle_detach(_i): pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT: return
	
	var hit_report = event.data as HitReportData
	if not hit_report or not hit_report.death_caused: return

	if randf() > (trigger_chance * instance.stacks): return

	var killer = event.unit
	if is_instance_valid(killer) and is_instance_valid(killer.attack_component):
		killer.attack_component.current_cooldown = 0.0
