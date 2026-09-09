extends EffectPrototype
class_name BookendsEffect

##modifiers granted once to each tower that belongs to a same-type horizontal triple
@export var modifier_prototypes: Array[ModifierDataPrototype] = []

class BookendsState extends RefCounted:
	var active_modifiers: Dictionary[int, Array] = {}
	var tower_refs: Dictionary[int, WeakRef] = {}
	var island_changed_callback: Callable

func _init() -> void: ##registers bookends as a global topology-maintained relic effect
	global = true
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance: ##creates isolated modifier bookkeeping for this relic copy
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = BookendsState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void: ##subscribes to island changes and evaluates the current line formations
	var state: BookendsState = instance.state as BookendsState
	state.island_changed_callback = _on_island_changed.bind(weakref(instance))

	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return
	if not island.island_changed.is_connected(state.island_changed_callback):
		island.island_changed.connect(state.island_changed_callback)
	_recalculate_all(instance)

func _handle_detach(instance: EffectInstance) -> void: ##disconnects island updates and removes every modifier this relic owns
	var state: BookendsState = instance.state as BookendsState
	var island: Island = _get_live_island()
	if state.island_changed_callback.is_valid() and is_instance_valid(island) and island.island_changed.is_connected(state.island_changed_callback):
		island.island_changed.disconnect(state.island_changed_callback)
	state.island_changed_callback = Callable()

	for tower_id: int in state.active_modifiers.keys():
		_remove_modifiers_from_tower(state, tower_id)

	state.active_modifiers.clear()
	state.tower_refs.clear()

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void: ##bookends is topology-driven rather than event-driven
	pass

func _on_island_changed(instance_ref: WeakRef) -> void: ##rehydrates the effect instance from the island signal without keeping it alive
	var instance: EffectInstance = instance_ref.get_ref() as EffectInstance
	if not is_instance_valid(instance) or not instance.enabled:
		return
	_recalculate_all(instance)

func _recalculate_all(instance: EffectInstance) -> void: ##rebuilds the set of towers currently belonging to horizontal same-type triples
	var state: BookendsState = instance.state as BookendsState
	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return

	var desired_towers: Dictionary[int, Tower] = {}
	for tower: Tower in island.get_all_towers():
		if not _is_valid_tower(tower):
			continue
		if not _is_in_horizontal_triple(tower, island):
			continue
		desired_towers[tower.unit_id] = tower

	_reconcile_modifier_set(state, desired_towers)

func _get_live_island() -> Island: ##returns the current island only while it can safely answer topology queries
	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if not is_instance_valid(island) or not island.is_inside_tree():
		return null
	return island

func _is_in_horizontal_triple(tower: Tower, island: Island) -> bool: ##checks the three possible contiguous horizontal triples that can contain this tower
	for start_offset: int in range(-2, 1):
		if _matches_horizontal_triple_from(tower, island, tower.tower_position + Vector2i(start_offset, 0)):
			return true
	return false

func get_tower_influences(candidate: Tower = null) -> Array[TowerInfluence]: ##reports bookends only for candidates currently belonging to a valid same-type horizontal triple
	var island: Island = _get_live_island()
	if not _is_valid_tower(candidate) or not is_instance_valid(island):
		return []
	if not _is_in_horizontal_triple(candidate, island):
		return []
	return [TowerInfluence.for_cells(
		&"bookends",
		TowerInfluence.Kind.MODIFIER,
		candidate.get_occupied_cells(),
		null,
		modifier_prototypes
	)]

func _matches_horizontal_triple_from(tower: Tower, island: Island, start_cell: Vector2i) -> bool: ##returns true when three distinct same-type towers occupy consecutive horizontal cells
	var seen_towers: Dictionary[int, bool] = {}
	for offset: int in range(3):
		var candidate: Tower = island.get_tower_on_tile(start_cell + Vector2i(offset, 0))
		if not _is_valid_tower(candidate):
			return false
		if candidate.type != tower.type:
			return false
		if seen_towers.has(candidate.unit_id):
			return false
		seen_towers[candidate.unit_id] = true
	return true

func _is_valid_tower(tower: Tower) -> bool: ##filters bookends participation to live allied active towers
	if not is_instance_valid(tower):
		return false
	if tower.hostile or tower.is_queued_for_deletion():
		return false
	return tower.current_state == Tower.State.ACTIVE

func _reconcile_modifier_set(
	state: BookendsState,
	desired_towers: Dictionary[int, Tower]
) -> void: ##adds missing role modifiers and removes role modifiers from towers that no longer qualify
	var stale_ids: Array[int] = []
	for tower_id: int in state.active_modifiers.keys():
		if not desired_towers.has(tower_id):
			stale_ids.append(tower_id)

	for tower_id: int in stale_ids:
		_remove_modifiers_from_tower(state, tower_id)

	for tower_id: int in desired_towers:
		var tower: Tower = desired_towers[tower_id]
		state.tower_refs[tower_id] = weakref(tower)
		if state.active_modifiers.has(tower_id):
			continue
		_apply_modifiers(state, tower)

func _apply_modifiers(
	state: BookendsState,
	tower: Tower
) -> void: ##creates this role's modifiers once for a newly qualifying tower
	if modifier_prototypes.is_empty() or not is_instance_valid(tower.modifiers_component):
		return

	var modifiers: Array[Modifier] = []
	for modifier_prototype: ModifierDataPrototype in modifier_prototypes:
		var modifier: Modifier = modifier_prototype.generate_modifier()
		modifier.source_id = -1
		tower.modifiers_component.add_modifier(modifier)
		modifiers.append(modifier)
	state.active_modifiers[tower.unit_id] = modifiers
	_play_formation_source_wisps(tower)
	trigger_target_bonus_feedback(tower)

func _play_formation_source_wisps(tower: Tower) -> void: ##links the other members of one qualifying horizontal triple to its newly buffed beneficiary
	var island: Island = _get_live_island()
	if not is_instance_valid(island):
		return
	for start_offset: int in range(-2, 1):
		var start_cell: Vector2i = tower.tower_position + Vector2i(start_offset, 0)
		if not _matches_horizontal_triple_from(tower, island, start_cell):
			continue
		for offset: int in range(3):
			var source_tower: Tower = island.get_tower_on_tile(start_cell + Vector2i(offset, 0))
			if source_tower != tower:
				BuffComponent.play_link_wisp(source_tower, tower)
		return

func _remove_modifiers_from_tower(
	state: BookendsState,
	tower_id: int
) -> void: ##removes one role's modifiers from a tracked tower if that tower is still alive
	var tower: Tower = _get_tracked_tower(state, tower_id)
	if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
		for modifier: Modifier in state.active_modifiers[tower_id]:
			tower.modifiers_component.remove_modifier(modifier)
	state.active_modifiers.erase(tower_id)
	state.tower_refs.erase(tower_id)

func _get_tracked_tower(state: BookendsState, tower_id: int) -> Tower: ##resolves a weakly tracked tower for cleanup without owning its lifetime
	if not state.tower_refs.has(tower_id):
		return null
	var tower_ref: WeakRef = state.tower_refs[tower_id]
	return tower_ref.get_ref() as Tower
