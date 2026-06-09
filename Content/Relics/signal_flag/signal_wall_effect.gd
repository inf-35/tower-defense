extends EffectPrototype
class_name SignalWallEffect ##local payload

@export var counter_attack_chance: float = 1.0 ##chance for an incoming hit to queue adjacent retaliatory attacks
@export var adjacent_type_filter: Towers.Type = Towers.Type.VOID ##optional tower filter; void means any adjacent attacker can trigger

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]

func create_instance() -> EffectInstance: ##creates the stateless local effect instance
	var i := EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i: EffectInstance) -> void:
	pass

func _handle_detach(_i: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##queues adjacent attacks so their next emitted payload derives from this trigger
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var wall = instance.host as Tower
	if not is_instance_valid(wall): return

	if randf() > counter_attack_chance: return

	_trigger_neighbors(instance, event.data, wall)

func _trigger_neighbors(instance: EffectInstance, parent_data: EventData, wall: Tower) -> void: ##arms each adjacent tower with a one-shot lineage override before its next attack
	var neighbors: Dictionary[Vector2i, Tower] = wall.get_adjacent_towers()

	for neighbor: Tower in neighbors.values():
		if not is_instance_valid(neighbor): continue

		if adjacent_type_filter != Towers.Type.VOID and neighbor.type != adjacent_type_filter:
			continue

		if is_instance_valid(neighbor.attack_component):
			neighbor.attack_component.queue_next_attack_context(parent_data, instance)
			neighbor.attack_component.current_cooldown = 0.0
			UI.floating_text_manager.show_icon(icon, neighbor.position)
