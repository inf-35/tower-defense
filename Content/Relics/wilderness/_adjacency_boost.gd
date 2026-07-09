extends EffectPrototype
class_name AdjacencyBoostEffect

@export_category("Targeting")
@export var host_tower_type: Towers.Type = Towers.Type.VOID ##type receiving buff. void = all
@export var adjacent_tower_type: Towers.Type = Towers.Type.VOID ##type providing buff. void = all

@export_category("Effect")
@export var modifier_prototype: ModifierDataPrototype ##the modifier to apply per satisfying adjacent tower

class AdjacencyState extends RefCounted:
	var active_modifiers: Dictionary[Tower, Modifier] = {}
	var active_counts: Dictionary[Tower, int] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.ADJACENCY_UPDATED, GameEvent.EventType.TOWER_BUILT]
	global = true

#--- instance factory ---
func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = AdjacencyState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	#first evaluate all towers
	for tower: Tower in Run.references.island.get_all_towers():
		_evaluate_tower(instance, tower)

func _handle_detach(instance: EffectInstance) -> void:
	#when the relic is lost, strip all modifiers we applied.
	var state: AdjacencyState = instance.state as AdjacencyState

	for tower: Tower in state.active_modifiers:
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			var mod: Modifier = state.active_modifiers[tower]
			tower.modifiers_component.remove_modifier(mod)

	state.active_modifiers.clear()
	state.active_counts.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	#if event.event_type == GameEvent.EventType.REPLACED:
		#_handle_replace(instance, event)
	if not event.unit is Tower:
		return

	var target_tower: Tower = event.unit as Tower

	#re-evaluate the specific tower that changed.
	#note: island.gd usually emits adjacency updates for neighbors too,
	#so we don't need to manually scan neighbors of the target here
	_evaluate_tower(instance, target_tower)

func _evaluate_tower(_instance: EffectInstance, tower: Tower) -> void:
	var state: AdjacencyState = _instance.state as AdjacencyState
	if not _is_valid_host(tower):
		_remove_buff_from_tower(state, tower)
		return

	var adjacent_stacks: int = 0
	for neighbor: Tower in tower.get_adjacent_towers().values():
		if _matches_adjacent_tower(neighbor, tower):
			adjacent_stacks += 1

	var previous_stacks: int = state.active_counts.get(tower, 0)
	state.active_counts[tower] = adjacent_stacks
	if adjacent_stacks > 0:
		_apply_buff_to_tower(state, tower, adjacent_stacks)
		if previous_stacks == 0 or adjacent_stacks > previous_stacks:
			trigger_target_bonus_feedback(tower)
	else:
		_remove_buff_from_tower(state, tower)

func _apply_buff_to_tower(state: AdjacencyState, tower: Tower, stacks: int) -> void:
	if not is_instance_valid(tower.modifiers_component):
		return

	if state.active_modifiers.has(tower):
		var mod: Modifier = state.active_modifiers[tower]
		var old_mult: float = mod.multiplicative
		var old_add: float = mod.additive
		modifier_prototype.apply_single_source_stacks(mod, stacks)
		if not is_equal_approx(mod.multiplicative, old_mult) or not is_equal_approx(mod.additive, old_add):
			tower.modifiers_component.change_modifier(mod)
	else:
		var new_mod: Modifier = modifier_prototype.generate_modifier()
		modifier_prototype.apply_single_source_stacks(new_mod, stacks)
		tower.modifiers_component.add_modifier(new_mod)
		state.active_modifiers[tower] = new_mod

func _remove_buff_from_tower(state: AdjacencyState, tower: Tower) -> void:
	state.active_counts.erase(tower)
	if state.active_modifiers.has(tower):
		var mod: Modifier = state.active_modifiers[tower]
		if is_instance_valid(tower.modifiers_component):
			tower.modifiers_component.remove_modifier(mod)
		state.active_modifiers.erase(tower)

func _is_valid_host(tower: Tower) -> bool:
	if not is_instance_valid(tower):
		return false
	if tower.hostile or tower.is_queued_for_deletion():
		return false
	if tower.current_state != Tower.State.ACTIVE:
		return false
	if host_tower_type == Towers.Type.VOID:
		return true
	return tower.type == host_tower_type

func _matches_adjacent_tower(candidate: Tower, host_tower: Tower) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate == host_tower:
		return false
	if candidate.hostile or candidate.is_queued_for_deletion():
		return false
	if candidate.current_state != Tower.State.ACTIVE:
		return false
	if adjacent_tower_type == Towers.Type.VOID:
		return true
	return candidate.type == adjacent_tower_type
