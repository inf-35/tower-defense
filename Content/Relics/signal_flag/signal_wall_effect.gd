extends EffectPrototype
class_name SignalWallEffect ##local payload

@export var counter_attack_chance: float = 1.0 ## 100% chance to trigger neighbors
@export var adjacent_type_filter: Towers.Type = Towers.Type.VOID ## VOID = trigger any tower

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i): pass
func _handle_detach(_i): pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var wall = instance.host as Tower
	if not is_instance_valid(wall): return
	
	if randf() > counter_attack_chance: return
	
	_trigger_neighbors(wall)

func _trigger_neighbors(wall: Tower) -> void:
	var neighbors := wall.get_adjacent_towers()
	
	for neighbor: Tower in neighbors.values():
		if not is_instance_valid(neighbor): continue

		if adjacent_type_filter != Towers.Type.VOID and neighbor.type != adjacent_type_filter:
			continue

		if is_instance_valid(neighbor.attack_component):
			neighbor.attack_component.current_cooldown = 0.0
