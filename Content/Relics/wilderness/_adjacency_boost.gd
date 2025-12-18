extends EffectPrototype
class_name AdjacencyBoostEffect

@export_category("Targeting")
@export var host_tower_type: Towers.Type = Towers.Type.VOID ## type receiving buff. VOID = all
@export var adjacent_tower_type: Towers.Type = Towers.Type.VOID ## type providing buff. VOID = all

@export_category("Effect")
@export var modifier_prototype: ModifierDataPrototype ## the modifier to apply per satisfying adjacent tower

class AdjacencyState extends RefCounted:
	var active_modifiers: Dictionary[Tower, Modifier] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.ADJACENCY_UPDATED]
	global = true

# --- Instance Factory ---
func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = AdjacencyState.new()
	return instance

# --- Logic Handlers ---

func _handle_attach(instance: EffectInstance) -> void:
	# first evaluate all towers
	var all_towers: Array = References.island.get_tree().get_nodes_in_group(References.TOWER_GROUP)
	for tower: Node in all_towers:
		if tower is Tower:
			_evaluate_tower(instance, tower)

func _handle_detach(instance: EffectInstance) -> void:
	# when the relic is lost, strip all modifiers we applied.
	var state := instance.state as AdjacencyState
	
	for tower: Tower in state.active_modifiers:
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			var mod: Modifier = state.active_modifiers[tower]
			tower.modifiers_component.remove_modifier(mod)
	
	state.active_modifiers.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.ADJACENCY_UPDATED:
		return

	if not event.unit is Tower:
		return
		
	var target_tower: Tower = event.unit as Tower
	
	# re-evaluate the specific tower that changed.
	# NOTE: Island.gd usually emits adjacency updates for neighbors too, 
	# so we don't need to manually scan neighbors of the target here
	_evaluate_tower(instance, target_tower)

func _evaluate_tower(instance: EffectInstance, tower: Tower) -> void:
	var state := instance.state as AdjacencyState
	
	# check if this tower is a valid host
	if not is_instance_valid(tower):
		return
		
	# if host_tower_type is set, ignore towers that don't match
	if host_tower_type != Towers.Type.VOID and tower.type != host_tower_type:
		_remove_buff_from_tower(state, tower)
		return

	# count valid neighbors
	var adjacent_stacks: int = 0
	var neighbors: Dictionary[Vector2i, Tower] = tower.get_adjacent_towers()
	
	for neighbor: Tower in neighbors.values():
		if is_instance_valid(neighbor):
			# Check neighbor type condition
			if adjacent_tower_type == Towers.Type.VOID or neighbor.type == adjacent_tower_type:
				adjacent_stacks += 1
	
	# apply or update modifier
	if adjacent_stacks > 0:
		_apply_buff_to_tower(state, tower, adjacent_stacks)
	else:
		_remove_buff_from_tower(state, tower)

func _apply_buff_to_tower(state: AdjacencyState, tower: Tower, stacks: int) -> void:
	if not is_instance_valid(tower.modifiers_component):
		return

	if state.active_modifiers.has(tower):
		# update existing modifier
		var mod: Modifier = state.active_modifiers[tower]
		
		# calculate new values
		var new_mult: float = modifier_prototype.multiplicative * stacks
		var new_add: float = modifier_prototype.additive * stacks

		if not is_equal_approx(mod.multiplicative, new_mult) or not is_equal_approx(mod.additive, new_add):
			mod.multiplicative = new_mult
			mod.additive = new_add
			tower.modifiers_component.change_modifier(mod)
	else:
		# create new modifier
		var new_mod: Modifier = modifier_prototype.generate_modifier()
		new_mod.multiplicative = modifier_prototype.multiplicative * stacks
		new_mod.additive = modifier_prototype.additive * stacks
		
		tower.modifiers_component.add_modifier(new_mod)
		state.active_modifiers[tower] = new_mod

func _remove_buff_from_tower(state: AdjacencyState, tower: Tower) -> void:
	if state.active_modifiers.has(tower):
		var mod: Modifier = state.active_modifiers[tower]
		if is_instance_valid(tower.modifiers_component):
			tower.modifiers_component.remove_modifier(mod)
		state.active_modifiers.erase(tower)
