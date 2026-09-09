extends EffectPrototype
class_name ConditionalRelicEffect

enum ConditionKind {
	ADJACENT_TYPES,
	ADJACENT_TERRAINS,
	WITHIN_RANGE_OF_TYPES,
	GLOBAL_TYPES_LEFT_RIGHT,
	GLOBAL_TYPES_UP_DOWN,
	AFFECTING_RITES,
	HOST_TERRAIN,
	ADJACENT_EMPTY_CELLS,
}

##which spatial/counting rule this relic uses when evaluating each host tower
@export var condition_kind: ConditionKind = ConditionKind.ADJACENT_TYPES
##optional host filter; empty means every allied active tower can qualify
@export var host_tower_types: Array[Towers.Type] = []
##reference tower types counted by the condition; some modes instead reuse the host tower type
@export var reference_tower_types: Array[Towers.Type] = []
##reference terrain types counted by terrain-based neighborhood conditions
@export var reference_terrain_types: Array[Terrain.Base] = []
##maximum search distance for range-based conditions
@export var max_range: int = 1
##minimum count needed before the relic grants anything to a host
@export var min_count: int = 1
##whether one qualifying relic source should scale internally with the counted amount
@export var scale_with_count: bool = false
##for global left-right / up-down checks, reuse the host tower type instead of reference_tower_types
@export var match_host_type_on_both_sides: bool = false
##terrain types the host itself may stand on for terrain-based conditions
@export var host_terrain_types: Array[Terrain.Base] = []
##stat modifiers applied while a host satisfies the condition
@export var modifier_prototypes: Array[ModifierDataPrototype] = []
##optional local effect granted while the condition remains satisfied
@export var granted_effect: EffectPrototype
##stack count used when granting the optional local effect
@export var granted_effect_stacks: int = 1
##whether qualifying tower-shaped condition sources emit buff-link wisps toward the beneficiary
@export var show_condition_link_wisps: bool = true

class ConditionalRelicState extends RefCounted:
	#track runtime grants by tower id so one recalc pass can update, remove, or clean up each host deterministically
	var active_modifiers: Dictionary[int, Variant] = {}
	var active_effects: Dictionary[int, bool] = {}
	var active_counts: Dictionary[int, int] = {}
	var attached_host_only: bool = false ##whether this instance was attached intrinsically instead of registered as a global relic
	#tower lifetime is owned elsewhere, so the relic only keeps weak refs for later cleanup/removal
	var tower_refs: Dictionary[int, WeakRef] = {}
	#the island signal outlives individual effect instances, so the callable must be stored for exact disconnect
	var island_changed_callback: Callable

func _init() -> void: ##initialises a passive spatial effect for either global registration or intrinsic host attachment
	global = true
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance: ##creates isolated runtime bookkeeping so one relic copy can cleanly attach and detach its grants
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = ConditionalRelicState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void: ##subscribes to island topology/content changes and immediately evaluates current towers
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	state.attached_host_only = is_instance_valid(instance.host)
	#bind a weak ref rather than the live instance so the signal graph never owns a freed runtime object
	state.island_changed_callback = _on_island_changed.bind(weakref(instance))
	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return
	if not island.island_changed.is_connected(state.island_changed_callback):
		island.island_changed.connect(state.island_changed_callback)
	_recalculate_all(instance)

func _handle_detach(instance: EffectInstance) -> void: ##disconnects the recalc hook and removes every modifier/effect this relic copy had granted
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if state.island_changed_callback.is_valid() and is_instance_valid(island) and island.island_changed.is_connected(state.island_changed_callback):
		island.island_changed.disconnect(state.island_changed_callback)
	state.island_changed_callback = Callable()

	#remove relic-owned modifiers first, then remove any locally granted effects
	for tower_id: int in state.active_modifiers:
		var tower: Tower = _get_live_tracked_tower(state, tower_id)
		if not is_instance_valid(tower) or not is_instance_valid(tower.modifiers_component):
			continue
		for modifier: Modifier in state.active_modifiers[tower_id]:
			tower.modifiers_component.remove_modifier(modifier)

	for tower_id: int in state.active_effects:
		var tower: Tower = _get_live_tracked_tower(state, tower_id)
		if is_instance_valid(tower):
			tower.remove_effect(granted_effect)

	state.active_modifiers.clear()
	state.active_effects.clear()
	state.active_counts.clear()
	state.tower_refs.clear()

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void: ##event-driven hooks are intentionally unused here because island_changed owns invalidation
	pass

func _on_island_changed(instance_ref: WeakRef) -> void: ##signal-facing wrapper that rehydrates the runtime instance only if it still exists
	var effect_instance: EffectInstance = instance_ref.get_ref() as EffectInstance
	if not is_instance_valid(effect_instance) or not effect_instance.enabled:
		return
	_recalculate_all(effect_instance)

func _recalculate_all(instance: EffectInstance) -> void: ##re-evaluates the attached host for intrinsic use, or every tower for a hostless global relic
	#first drop stale bookkeeping so evaluation only sees live hosts
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	_prune_invalid_targets(state)
	if state.attached_host_only:
		if is_instance_valid(instance.host) and instance.host is Tower:
			_evaluate_tower(instance, instance.host as Tower)
		return

	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return
	
	for tower: Tower in island.get_all_towers():
		_evaluate_tower(instance, tower)

func _get_live_island(): ##returns the current island only while it is still live and inside the tree
	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if not is_instance_valid(island) or not island.is_inside_tree():
		return null
	return island

func _get_live_tracked_tower(state: ConditionalRelicState, tower_id: int): ##re-hydrates a weakly tracked host tower for cleanup or modifier updates
	if not state.tower_refs.has(tower_id):
		return null
	var weak_ref: WeakRef = state.tower_refs[tower_id]
	var tower: Tower = weak_ref.get_ref() as Tower
	if not is_instance_valid(tower):
		return null
	return tower

func _prune_invalid_targets(state: ConditionalRelicState) -> void: ##forgets dead towers from every bookkeeping table before the next recalc mutates live hosts
	var stale_ids: Array[int] = []
	for tower_id: int in state.tower_refs:
		if is_instance_valid(_get_live_tracked_tower(state, tower_id)):
			continue
		stale_ids.append(tower_id)
	for tower_id: int in stale_ids:
		state.tower_refs.erase(tower_id)
		state.active_counts.erase(tower_id)
		state.active_modifiers.erase(tower_id)
		state.active_effects.erase(tower_id)

func _evaluate_tower(instance: EffectInstance, tower: Tower) -> void: ##applies, refreshes, or removes this relic's grants for one potential host tower
	var state: ConditionalRelicState = instance.state as ConditionalRelicState
	var evaluation: Dictionary[StringName, Variant] = _evaluate_influence_condition(tower)
	if not evaluation.get(&"valid_host", false):
		_remove_from_tower(state, tower)
		return

	var tower_id: int = tower.unit_id
	state.tower_refs[tower_id] = weakref(tower)
	var count: int = evaluation.get(&"count", 0)
	var previous_count: int = state.active_counts.get(tower_id, 0)
	state.active_counts[tower_id] = count

	#falling below the threshold tears down everything this relic had attached to that tower
	if not evaluation.get(&"active", false):
		_remove_from_tower(state, tower)
		return

	_apply_modifiers(state, tower, count)
	_apply_granted_effect(state, tower)

	#feedback only fires on first qualification or when a scaling relic gained more sources
	if previous_count < min_count or (scale_with_count and count > previous_count):
		_play_condition_link_wisps(tower)
		trigger_target_bonus_feedback(tower)

func _play_condition_link_wisps(tower: Tower) -> void: ##visualizes the concrete towers responsible for a newly activated conditional relic grant
	if not show_condition_link_wisps:
		return
	for source_tower: Tower in _get_condition_source_towers(tower):
		BuffComponent.play_link_wisp(source_tower, tower)

func _get_condition_source_towers(tower: Tower) -> Array[Tower]: ##returns live tower contributors for condition kinds that have a meaningful world-space source
	var source_towers: Array[Tower] = []
	var seen_ids: Dictionary[int, bool] = {}
	match condition_kind:
		ConditionKind.ADJACENT_TYPES:
			for candidate: Tower in tower.get_adjacent_towers().values():
				_append_condition_source(source_towers, seen_ids, candidate, tower)
		ConditionKind.WITHIN_RANGE_OF_TYPES:
			var query := TowerTopologyService.Query.new(
				TowerTopologyService.QueryKind.CARDINAL_RING,
				1,
				max_range,
				TowerTopologyService.ALL_DIRECTIONS
			)
			var report: TowerTopologyService.Report = Run.references.island.topology_service.query(tower, query)
			for candidate: Tower in report.unique_towers:
				_append_condition_source(source_towers, seen_ids, candidate, tower)
	return source_towers

func _append_condition_source(sources: Array[Tower], seen_ids: Dictionary[int, bool], candidate: Tower, host_tower: Tower) -> void: ##dedupes multi-tile contributors while applying the same filter used by condition evaluation
	if not _matches_reference_tower(candidate, host_tower):
		return
	if seen_ids.has(candidate.unit_id):
		return
	seen_ids[candidate.unit_id] = true
	sources.append(candidate)

func get_tower_influences(candidate: Tower = null) -> Array[TowerInfluence]: ##describes an active global grant through the same mutation-free surface used by tower behaviors
	var influences: Array[TowerInfluence] = []
	var evaluation: Dictionary[StringName, Variant] = _evaluate_influence_condition(candidate)
	if not evaluation.get(&"active", false):
		return influences
	var cells: Array[Vector2i] = candidate.get_occupied_cells()
	if not modifier_prototypes.is_empty():
		influences.append(TowerInfluence.for_cells(&"conditional_modifiers", TowerInfluence.Kind.MODIFIER, cells, null, modifier_prototypes))
	if is_instance_valid(granted_effect):
		influences.append(TowerInfluence.for_cells(&"conditional_effect", TowerInfluence.Kind.EFFECT, cells, granted_effect))
	if influences.is_empty():
		influences.append(TowerInfluence.for_cells(&"conditional_trigger", TowerInfluence.Kind.TRIGGER, cells))
	return influences

func _evaluate_influence_condition(tower: Tower) -> Dictionary[StringName, Variant]: ##separates pure host/count evaluation from live modifier, effect, feedback, and bookkeeping mutation
	var valid_host: bool = _is_valid_host(tower)
	var count: int = _count_matches(tower) if valid_host else 0
	return {
		&"valid_host": valid_host,
		&"active": valid_host and count >= min_count,
		&"count": count,
		&"required_count": min_count,
	}

func _is_valid_host(tower: Tower) -> bool: ##filters evaluation down to live allied active towers and the optional host type whitelist
	if not is_instance_valid(tower):
		return false
	if tower.hostile or tower.is_queued_for_deletion():
		return false
	if tower.current_state != Tower.State.ACTIVE:
		return false
	if host_tower_types.is_empty():
		return true
	return host_tower_types.has(tower.type)

func _count_matches(tower: Tower) -> int: ##normalizes the authored condition kinds behind one integer count/boolean-as-count interface
	match condition_kind:
		ConditionKind.ADJACENT_TYPES:
			return _count_adjacent_types(tower)
		ConditionKind.ADJACENT_TERRAINS:
			return _count_adjacent_terrains(tower)
		ConditionKind.WITHIN_RANGE_OF_TYPES:
			return _count_within_range_of_types(tower)
		ConditionKind.GLOBAL_TYPES_LEFT_RIGHT:
			return int(_has_global_types_on_both_sides(tower, true))
		ConditionKind.GLOBAL_TYPES_UP_DOWN:
			return int(_has_global_types_on_both_sides(tower, false))
		ConditionKind.AFFECTING_RITES:
			return _count_affecting_rites(tower)
		ConditionKind.HOST_TERRAIN:
			return int(_matches_host_terrain(tower))
		ConditionKind.ADJACENT_EMPTY_CELLS:
			return _count_adjacent_empty_cells(tower)
	return 0

func _count_adjacent_types(tower: Tower) -> int: ##dedupes by tower reference so multi-tile neighbors only contribute once
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

func _count_adjacent_terrains(tower: Tower) -> int: ##counts adjacent cells whose terrain matches any authored reference terrain type
	if reference_terrain_types.is_empty():
		return 0

	var count: int = 0
	for cell: Vector2i in tower.get_adjacent_cells():
		var terrain_base: Terrain.Base = Run.references.island.get_terrain_base(cell)
		for reference_terrain: Terrain.Base in reference_terrain_types:
			if not Terrain.matches_reference_terrain(terrain_base, reference_terrain):
				continue
			count += 1
			break
	return count

func _count_adjacent_empty_cells(tower: Tower) -> int: ##matches liberty's notion of free adjacencies by counting in-bounds adjacent cells with no tower on them
	var count: int = 0
	for cell: Vector2i in tower.get_adjacent_cells():
		if not Run.references.island.terrain_base_grid.has(cell):
			continue
		if Run.references.island.get_tower_on_tile(cell) == null:
			count += 1
	return count

func _count_within_range_of_types(tower: Tower) -> int: ##uses topology queries so larger range checks stay aligned with the shared adjacency/query system
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

func _has_global_types_on_both_sides(tower: Tower, horizontal: bool) -> bool: ##answers the bookends-style "something exists on both sides" condition without constructing a full path/query object
	var matching_types: Array = []
	if match_host_type_on_both_sides:
		matching_types = [tower.type]
	else:
		matching_types.assign(reference_tower_types)
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

func _count_affecting_rites(tower: Tower) -> int: ##counts distinct rite sources already influencing the tower, across both effect and modifier channels
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

func _matches_host_terrain(tower: Tower) -> bool: ##keeps terrain-gated relics on the same count-based interface as the other conditional modes
	if host_terrain_types.is_empty():
		return false
	var host_terrain: Terrain.Base = tower.get_terrain_base()
	for reference_terrain: Terrain.Base in host_terrain_types:
		if Terrain.matches_reference_terrain(host_terrain, reference_terrain):
			return true
	return false

func _collect_active_rite_source_ids() -> Dictionary[int, bool]: ##builds a live membership set so modifier source ids can be filtered down to currently active rite towers
	var rite_source_ids: Dictionary[int, bool] = {}
	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return rite_source_ids
	for other_tower: Tower in island.get_all_towers():
		if other_tower.hostile or other_tower.is_queued_for_deletion():
			continue
		if other_tower.current_state != Tower.State.ACTIVE:
			continue
		if not Towers.is_tower_rite(other_tower.type):
			continue
		rite_source_ids[other_tower.unit_id] = true
	return rite_source_ids

func _matches_reference_tower(candidate: Tower, host_tower: Tower) -> bool: ##checks whether a candidate tower counts toward the current host's authored condition
	if not _is_valid_host_candidate(candidate, host_tower):
		return false
	if match_host_type_on_both_sides:
		return candidate.type == host_tower.type
	if reference_tower_types.is_empty():
		return true
	return reference_tower_types.has(candidate.type)

func _is_valid_host_candidate(candidate: Tower, host_tower: Tower) -> bool: ##shared liveness filter for towers considered by the condition counters
	if not is_instance_valid(candidate):
		return false
	if host_tower != null and candidate == host_tower:
		return false
	if candidate.hostile or candidate.is_queued_for_deletion():
		return false
	return candidate.current_state == Tower.State.ACTIVE

func _apply_modifiers(state: ConditionalRelicState, tower: Tower, count: int) -> void: ##creates modifier instances once, then only mutates their values on future recalc passes
	if modifier_prototypes.is_empty() or not is_instance_valid(tower.modifiers_component):
		return

	var tower_id: int = tower.unit_id
	if not state.active_modifiers.has(tower_id):
		var new_modifiers: Array[Modifier] = []
		for modifier_prototype: ModifierDataPrototype in modifier_prototypes:
			var modifier: Modifier = modifier_prototype.generate_modifier()
			_apply_scaled_values(modifier, modifier_prototype, count)
			tower.modifiers_component.add_modifier(modifier)
			new_modifiers.append(modifier)
		state.active_modifiers[tower_id] = new_modifiers
		return

	var active_modifiers: Array[Modifier] = state.active_modifiers[tower_id]
	for i: int in range(mini(active_modifiers.size(), modifier_prototypes.size())):
		var active_modifier: Modifier = active_modifiers[i]
		var modifier_prototype: ModifierDataPrototype = modifier_prototypes[i]
		_apply_scaled_values(active_modifier, modifier_prototype, count)
		tower.modifiers_component.change_modifier(active_modifier)

func _apply_scaled_values(modifier: Modifier, modifier_prototype: ModifierDataPrototype, count: int) -> void: ##lets one relic source scale internally with count while still remaining a single modifier source
	if not scale_with_count:
		return

	modifier_prototype.apply_single_source_stacks(modifier, count)

func _apply_granted_effect(state: ConditionalRelicState, tower: Tower) -> void: ##grants the optional local effect at most once per tower and tracks that fact separately from stat modifiers
	var tower_id: int = tower.unit_id
	if not is_instance_valid(granted_effect):
		return

	var existing_instances: Array[EffectInstance] = tower.get_effect_instances_by_prototype(granted_effect)
	if existing_instances.size() > 1:
		#collapse any accidental duplicates back into one canonical local effect instance
		tower.remove_effect(granted_effect)
		existing_instances.clear()

	if not existing_instances.is_empty():
		existing_instances[0].stacks = granted_effect_stacks
		state.active_effects[tower_id] = true
		return

	tower.apply_effect(granted_effect, granted_effect_stacks)
	state.active_effects[tower_id] = true

func _remove_from_tower(state: ConditionalRelicState, tower: Tower) -> void: ##central teardown path for one tower, used both when conditions fail and when hosts become invalid
	var tower_id: int = tower.unit_id
	state.active_counts.erase(tower_id)

	if state.active_modifiers.has(tower_id):
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			for modifier: Modifier in state.active_modifiers[tower_id]:
				tower.modifiers_component.remove_modifier(modifier)
		state.active_modifiers.erase(tower_id)

	if state.active_effects.has(tower_id):
		if is_instance_valid(tower):
			tower.remove_effect(granted_effect)
		state.active_effects.erase(tower_id)
	if not state.active_counts.has(tower_id) and not state.active_modifiers.has(tower_id) and not state.active_effects.has(tower_id):
		state.tower_refs.erase(tower_id)
