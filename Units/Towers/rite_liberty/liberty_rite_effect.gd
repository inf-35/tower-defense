extends EffectPrototype
class_name LibertyRiteEffect #local effect applied by the Liberty Rite

@export var fire_rate_bonus_per_empty: float = 0.20 ## +fire rate bonus per empty adjacency

class LibertyState extends RefCounted:
	var modifier: Modifier

func _init() -> void:
	# recalculate whenever the grid changes around this tower
	event_hooks = [GameEvent.EventType.ADJACENCY_UPDATED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = LibertyState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	if instance.host is Tower:
		_update_bonus(instance)

func _handle_detach(instance: EffectInstance) -> void:
	var state := instance.state as LibertyState
	if is_instance_valid(state.modifier) and is_instance_valid(instance.host.modifiers_component):
		instance.host.modifiers_component.remove_modifier(state.modifier)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type == GameEvent.EventType.ADJACENCY_UPDATED:
		_update_bonus(instance)

func _update_bonus(instance: EffectInstance) -> void:
	var tower := instance.host as Tower
	if not is_instance_valid(tower):
		return

	var empty_count: int = 0
	var adjacent_cells: Array[Vector2i] = tower.get_adjacent_cells()
	
	for cell: Vector2i in adjacent_cells:
		if not References.island.terrain_base_grid.has(cell):
			continue

		if References.island.get_tower_on_tile(cell) == null:
			empty_count += 1

	var total_rate_bonus: float = empty_count * fire_rate_bonus_per_empty * instance.stacks
	var cooldown_mult: float = 1.0 / (1.0 + total_rate_bonus) #use the reciprocal to find cooldown bonus
	var state := instance.state as LibertyState
	
	if is_instance_valid(state.modifier):
		#update existing modifier
		if not is_equal_approx(state.modifier.multiplicative, cooldown_mult):
			state.modifier.multiplicative = cooldown_mult
			tower.modifiers_component.change_modifier(state.modifier)
	else:
		# create new modifier
		var mod := Modifier.new(Attributes.id.COOLDOWN, cooldown_mult, 0.0, -1.0)
		state.modifier = mod
		tower.modifiers_component.add_modifier(mod)
