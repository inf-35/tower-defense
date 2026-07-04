extends EffectPrototype
class_name ConditionalRelicEffect

enum ConditionKind {
	ADJACENT_TYPES,
	WITHIN_RANGE_OF_TYPES,
	GLOBAL_TYPES_LEFT_RIGHT,
	GLOBAL_TYPES_UP_DOWN,
	AFFECTING_RITES,
}

@export var condition_kind: ConditionKind = ConditionKind.ADJACENT_TYPES
@export var host_tower_types: Array[Towers.Type] = []
@export var reference_tower_types: Array[Towers.Type] = []
@export var max_range: int = 1
@export var min_count: int = 1
@export var scale_with_count: bool = false
@export var match_host_type_on_both_sides: bool = false
@export var modifier_prototypes: Array[ModifierDataPrototype] = []
@export var granted_effect: EffectPrototype
@export var granted_effect_stacks: int = 1

class ConditionalRelicState extends RefCounted:
	var active_modifiers: Dictionary[Tower, Array] = {}
	var active_effects: Dictionary[Tower, bool] = {}
	var active_counts: Dictionary[Tower, int] = {}
	var island_changed_callback: Callable

func _init() -> void:
	global = true
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = ConditionalRelicState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	state.island_changed_callback = _recalculate_all.bind(instance)
	if not Run.references.island.island_changed.is_connected(state.island_changed_callback):
		Run.references.island.island_changed.connect(state.island_changed_callback)
	_recalculate_all(instance)

func _handle_detach(instance: EffectInstance) -> void:
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	if state.island_changed_callback.is_valid() and Run.references.island.island_changed.is_connected(state.island_changed_callback):
		Run.references.island.island_changed.disconnect(state.island_changed_callback)

	for tower: Tower in state.active_modifiers:
		if not is_instance_valid(tower) or not is_instance_valid(tower.modifiers_component):
			continue
		for modifier: Modifier in state.active_modifiers[tower]:
			tower.modifiers_component.remove_modifier(modifier)

	for tower: Tower in state.active_effects:
		if is_instance_valid(tower):
			tower.remove_effect(granted_effect)

	state.active_modifiers.clear()
	state.active_effects.clear()
	state.active_counts.clear()

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void:
	pass

func _recalculate_all(instance: EffectInstance) -> void: ##re-evaluates every allied tower against this relic's current spatial condition
	_prune_invalid_targets(instance.state as ConditionalRelicState)
	for tower: Tower in Run.references.island.get_tree().get_nodes_in_group(Run.references.TOWER_GROUP):
		if not is_instance_valid(tower):
			continue
		_evaluate_tower(instance, tower)

func _prune_invalid_targets(state: ConditionalRelicState) -> void:
	for tower: Tower in state.active_counts.keys():
		if is_instance_valid(tower):
			continue
		state.active_counts.erase(tower)
	for tower: Tower in state.active_modifiers.keys():
		if is_instance_valid(tower):
			continue
		state.active_modifiers.erase(tower)
	for tower: Tower in state.active_effects.keys():
		if is_instance_valid(tower):
			continue
		state.active_effects.erase(tower)

func _evaluate_tower(instance: EffectInstance, tower: Tower) -> void:
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	if not _is_valid_host(tower):
		_remove_from_tower(state, tower)
		return

	var count: int = _count_matches(tower)
	var previous_count: int = state.active_counts.get(tower, 0)
	state.active_counts[tower] = count

	if count < min_count:
		_remove_from_tower(state, tower)
		return

	_apply_modifiers(state, tower, count)
	_apply_granted_effect(state, tower)

	if previous_count < min_count or (scale_with_count and count > previous_count):
		trigger_target_bonus_feedback(tower)

func _is_valid_host(tower: Tower) -> bool:
	if not is_instance_valid(tower):
		return false
	if tower.hostile or tower.is_queued_for_deletion():
		return false
	if tower.current_state != Tower.State.ACTIVE:
		return false
	if host_tower_types.is_empty():
		return true
	return host_tower_types.has(tower.type)

func _count_matches(tower: Tower) -> int:
	match condition_kind:
		ConditionKind.ADJACENT_TYPES:
			return _count_adjacent_types(tower)
		ConditionKind.WITHIN_RANGE_OF_TYPES:
			return _count_within_range_of_types(tower)
		ConditionKind.GLOBAL_TYPES_LEFT_RIGHT:
			return int(_has_global_types_on_both_sides(tower, true))
		ConditionKind.GLOBAL_TYPES_UP_DOWN:
			return int(_has_global_types_on_both_sides(tower, false))
		ConditionKind.AFFECTING_RITES:
			return _count_affecting_rites(tower)
	return 0

func _count_adjacent_types(tower: Tower) -> int:
	var seen_towers: Dictionary[Tower, bool] = {}
	var count: int = 0
	for neighbor: Tower in tower.get_adjacent_towers().values():
		if not _matches_reference_tower(neighbor, tower):
			continue
		if seen_towers.has(neighbor):
			continue
		seen_towers[neighbor] = true
		count += 1
	return count

func _count_within_range_of_types(tower: Tower) -> int:
	var query := TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.CARDINAL_RING,
		1,
		max_range,
		TowerTopologyService.ALL_DIRECTIONS
	)
	var report: TowerTopologyService.Report = Run.references.island.topology_service.query(tower, query)
	var count: int = 0
	for other_tower: Tower in report.unique_towers:
		if _matches_reference_tower(other_tower, tower):
			count += 1
	return count

func _has_global_types_on_both_sides(tower: Tower, horizontal: bool) -> bool:
	var matching_types: Array = [tower.type] if match_host_type_on_both_sides else reference_tower_types
	if matching_types.is_empty():
		return false

	var found_negative: bool = false
	var found_positive: bool = false
	for tower_type: Towers.Type in matching_types:
		for other_tower: Tower in Run.references.island.get_towers_by_type(tower_type):
			if not _is_valid_host_candidate(other_tower, tower):
				continue
			if horizontal:
				if other_tower.tower_position.y != tower.tower_position.y:
					continue
				if other_tower.tower_position.x < tower.tower_position.x:
					found_negative = true
				elif other_tower.tower_position.x > tower.tower_position.x:
					found_positive = true
			else:
				if other_tower.tower_position.x != tower.tower_position.x:
					continue
				if other_tower.tower_position.y < tower.tower_position.y:
					found_negative = true
				elif other_tower.tower_position.y > tower.tower_position.y:
					found_positive = true
			if found_negative and found_positive:
				return true
	return false

func _count_affecting_rites(tower: Tower) -> int:
	var source_rites: Dictionary[int, bool] = {}
	var active_rite_source_ids: Dictionary[int, bool] = _collect_active_rite_source_ids()
	for schedule_dictionary: Dictionary in tower.effects.values():
		for effect_instances: Array in schedule_dictionary.values():
			for effect_instance: EffectInstance in effect_instances:
				if not is_instance_valid(effect_instance.source) or not effect_instance.source is Tower:
					continue
				var source_tower: Tower = effect_instance.source as Tower
				if not Towers.is_tower_rite(source_tower.type):
					continue
				source_rites[source_tower.unit_id] = true

	if is_instance_valid(tower.modifiers_component):
		for modifier: Modifier in tower.modifiers_component._modifiers:
			if not active_rite_source_ids.has(modifier.source_id):
				continue
			source_rites[modifier.source_id] = true

	return source_rites.size()

func _collect_active_rite_source_ids() -> Dictionary[int, bool]:
	var rite_source_ids: Dictionary[int, bool] = {}
	for other_tower: Tower in Run.references.island.get_tree().get_nodes_in_group(Run.references.TOWER_GROUP):
		if not is_instance_valid(other_tower):
			continue
		if other_tower.hostile or other_tower.is_queued_for_deletion():
			continue
		if other_tower.current_state != Tower.State.ACTIVE:
			continue
		if not Towers.is_tower_rite(other_tower.type):
			continue
		rite_source_ids[other_tower.unit_id] = true
	return rite_source_ids

func _matches_reference_tower(candidate: Tower, host_tower: Tower) -> bool:
	if not _is_valid_host_candidate(candidate, host_tower):
		return false
	if match_host_type_on_both_sides:
		return candidate.type == host_tower.type
	if reference_tower_types.is_empty():
		return true
	return reference_tower_types.has(candidate.type)

func _is_valid_host_candidate(candidate: Tower, host_tower: Tower) -> bool:
	if not is_instance_valid(candidate):
		return false
	if host_tower != null and candidate == host_tower:
		return false
	if candidate.hostile or candidate.is_queued_for_deletion():
		return false
	return candidate.current_state == Tower.State.ACTIVE

func _apply_modifiers(state: ConditionalRelicState, tower: Tower, count: int) -> void:
	if modifier_prototypes.is_empty() or not is_instance_valid(tower.modifiers_component):
		return

	if not state.active_modifiers.has(tower):
		var new_modifiers: Array[Modifier] = []
		for modifier_prototype: ModifierDataPrototype in modifier_prototypes:
			var modifier: Modifier = modifier_prototype.generate_modifier()
			_apply_scaled_values(modifier, modifier_prototype, count)
			tower.modifiers_component.add_modifier(modifier)
			new_modifiers.append(modifier)
		state.active_modifiers[tower] = new_modifiers
		return

	var active_modifiers: Array[Modifier] = state.active_modifiers[tower]
	for i: int in range(mini(active_modifiers.size(), modifier_prototypes.size())):
		var active_modifier: Modifier = active_modifiers[i]
		var modifier_prototype: ModifierDataPrototype = modifier_prototypes[i]
		_apply_scaled_values(active_modifier, modifier_prototype, count)
		tower.modifiers_component.change_modifier(active_modifier)

func _apply_scaled_values(modifier: Modifier, modifier_prototype: ModifierDataPrototype, count: int) -> void:
	if not scale_with_count:
		return

	modifier_prototype.apply_single_source_stacks(modifier, count)

func _apply_granted_effect(state: ConditionalRelicState, tower: Tower) -> void:
	if not is_instance_valid(granted_effect) or state.active_effects.has(tower):
		return

	tower.apply_effect(granted_effect, granted_effect_stacks)
	state.active_effects[tower] = true

func _remove_from_tower(state: ConditionalRelicState, tower: Tower) -> void:
	state.active_counts.erase(tower)

	if state.active_modifiers.has(tower):
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			for modifier: Modifier in state.active_modifiers[tower]:
				tower.modifiers_component.remove_modifier(modifier)
		state.active_modifiers.erase(tower)

	if state.active_effects.has(tower):
		if is_instance_valid(tower):
			tower.remove_effect(granted_effect)
		state.active_effects.erase(tower)
