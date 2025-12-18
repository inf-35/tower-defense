extends EffectPrototype
class_name EnfiladeEffect

@export var modifier: ModifierDataPrototype

func _init() -> void:
	event_hooks = [GameEvent.EventType.TOWER_BUILT]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	print("ALLAn")
	if event.event_type != GameEvent.EventType.TOWER_BUILT:
		return
	#check if mid-battle
	print(Phases.GamePhase.keys()[Phases.current_phase])
	if Phases.current_phase != Phases.GamePhase.COMBAT_WAVE:
		return
	#get data
	var data := event.data as BuildTowerData
	if not data or not is_instance_valid(data.tower):
		return
		
	var new_tower: Tower = data.tower
	if not is_instance_valid(new_tower.modifiers_component):
		return

	new_tower.modifiers_component.add_modifier(modifier.generate_modifier())
