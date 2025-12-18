extends EffectPrototype
class_name SubprimeEffect

@export var maximum_bonus: float = 1.0 ##how much more flux is earned at zero distance as a proportion of the original flux earned
@export var gradient_floor: float = 200.0 
@export var gradient_ceiling: float = 30.0

func _init():
	event_hooks = [GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	return return_generic_instance()

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return
	
	var target: Unit = event.unit #unit which died
	var hit_report_data: HitReportData = event.data as HitReportData
	
	if not target.hostile:
		return #only care about hostile kills
		
	if not hit_report_data.death_caused:
		return #only care about kills
	
	var distance: float = (target.global_position).length()
	var proportion: float = clampf((gradient_floor - distance) / (gradient_floor - gradient_ceiling), 0.0, 1.0)
	hit_report_data.flux_value *= 1.0 + proportion * maximum_bonus
	#this modified flux value will be passed into on_killed
	pass
