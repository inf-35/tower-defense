extends EffectPrototype

class GuardshelmState extends RefCounted:
	var island_ref: WeakRef
	var changed_callback: Callable
	var tower_refs: Dictionary[int, WeakRef] = {}
	var disabled_tower_ids: Dictionary[int, bool] = {}
	var connected_tower_ids: Dictionary[int, bool] = {}
	var refresh_queued: bool = false

func _init() -> void:
	global = true
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance: ##keeps connectivity and the towers disabled by this relic in one local state
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = GuardshelmState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void: ##binds to the actual island and evaluates any towers already placed or restored
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return
	var state: GuardshelmState = instance.state as GuardshelmState
	var island: Island = Run.references.island
	state.island_ref = weakref(island)
	state.changed_callback = _queue_refresh.bind(weakref(instance))
	island.island_changed.connect(state.changed_callback)
	_queue_refresh(weakref(instance))

func _handle_detach(instance: EffectInstance) -> void: ##restores only towers this relic disabled, without waking ruins or retaining a destroyed island
	var state: GuardshelmState = instance.state as GuardshelmState
	var island: Island = state.island_ref.get_ref() as Island if state.island_ref != null else null
	if is_instance_valid(island) and island.island_changed.is_connected(state.changed_callback):
		island.island_changed.disconnect(state.changed_callback)
	state.island_ref = null
	state.changed_callback = Callable()
	state.refresh_queued = false
	var tower_refs: Dictionary[int, WeakRef] = state.tower_refs.duplicate()
	var disabled_tower_ids: Array[int] = state.disabled_tower_ids.keys()
	state.tower_refs.clear()
	state.disabled_tower_ids.clear()
	state.connected_tower_ids.clear()
	var operation_changed: bool = false
	for tower_id: int in disabled_tower_ids:
		var tower: Tower = tower_refs[tower_id].get_ref() as Tower
		if is_instance_valid(tower):
			operation_changed = _set_tower_disabled(tower, false) or operation_changed
	if operation_changed and is_instance_valid(island) and not island.game_ending:
		island.island_changed.emit()

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void: ##required effect hook; island invalidation owns this passive effect's updates
	pass

func _queue_refresh(instance_ref: WeakRef) -> void: ##coalesces construction, loading, upgrades, and ruin changes until the board is stable
	var instance: EffectInstance = instance_ref.get_ref() as EffectInstance
	if not is_instance_valid(instance) or not instance.enabled:
		return
	var state: GuardshelmState = instance.state as GuardshelmState
	if state.refresh_queued:
		return
	state.refresh_queued = true
	_refresh_connections.call_deferred(instance_ref)

func _refresh_connections(instance_ref: WeakRef) -> void: ##flood-fills cardinal footprint adjacency once, then applies the resulting connected set
	var instance: EffectInstance = instance_ref.get_ref() as EffectInstance
	if not is_instance_valid(instance) or not instance.enabled:
		return
	var state: GuardshelmState = instance.state as GuardshelmState
	state.refresh_queued = false
	var island: Island = state.island_ref.get_ref() as Island if state.island_ref != null else null
	if not is_instance_valid(island) or island.game_ending or not island.is_inside_tree():
		return
	var candidates: Dictionary[int, Tower] = {}
	for tower: Tower in island.get_all_towers():
		if not _is_network_tower(tower):
			continue
		var tower_id: int = tower.get_instance_id()
		candidates[tower_id] = tower
	state.connected_tower_ids = _get_connected_tower_ids(island)
	#disabled towers remain graph candidates so reconnecting a whole branch can wake it in one pass.
	var operation_changed: bool = false
	for tower_id: int in state.tower_refs.keys():
		if candidates.has(tower_id):
			continue
		var old_tower: Tower = state.tower_refs[tower_id].get_ref() as Tower
		state.tower_refs.erase(tower_id)
		if state.disabled_tower_ids.has(tower_id):
			state.disabled_tower_ids.erase(tower_id)
			if is_instance_valid(old_tower):
				operation_changed = _set_tower_disabled(old_tower, false) or operation_changed
	for tower_id: int in candidates:
		var tower: Tower = candidates[tower_id]
		if not state.tower_refs.has(tower_id) and is_instance_valid(tower.health_component):
			#save restoration creates towers before relics; preserve their health fraction when the hp bonus arrives.
			var previous_max: float = tower.health_component.max_health
			var current_max: float = tower.get_stat(Attributes.id.MAX_HEALTH)
			if previous_max > 0.0 and current_max > previous_max:
				tower.health_component.health *= current_max / previous_max
		state.tower_refs[tower_id] = weakref(tower)
		if state.connected_tower_ids.has(tower_id):
			if state.disabled_tower_ids.has(tower_id):
				state.disabled_tower_ids.erase(tower_id)
				operation_changed = _set_tower_disabled(tower, false) or operation_changed
		elif not tower.disabled:
			#record ownership before lifecycle hooks can trigger further board updates.
			state.disabled_tower_ids[tower_id] = true
			operation_changed = _set_tower_disabled(tower, true) or operation_changed
	if operation_changed:
		#other spatial effects should evaluate the completed batch, not a half-awake branch.
		island.island_changed.emit()

func get_placement_error(instance: EffectInstance, island: Island, cell: Vector2i, tower_type: Towers.Type, facing: Tower.Facing, exclude_tower: Tower = null) -> String: ##rejects footprints without a cardinal edge touching the keep-connected component
	var prototype: Tower = Towers.get_tower_prototype(tower_type)
	if prototype.hostile or prototype.environmental or tower_type == Towers.Type.PLAYER_CORE:
		return ""
	var state: GuardshelmState = instance.state as GuardshelmState
	var connected: Dictionary[int, bool] = state.connected_tower_ids
	if state.refresh_queued or is_instance_valid(exclude_tower):
		#previews may arrive before deferred invalidation; upgrades must not count their old footprint as a bridge.
		connected = _get_connected_tower_ids(island, exclude_tower)
	var size: Vector2i = Tower.get_rotated_size(Towers.get_tower_size(tower_type), facing)
	var boundary_cells: Array[Vector2i] = []
	for x: int in size.x:
		boundary_cells.append(cell + Vector2i(x, -1))
		boundary_cells.append(cell + Vector2i(x, size.y))
	for y: int in size.y:
		boundary_cells.append(cell + Vector2i(-1, y))
		boundary_cells.append(cell + Vector2i(size.x, y))
	for boundary_cell: Vector2i in boundary_cells:
		var neighbor: Tower = island.get_tower_on_tile(boundary_cell)
		if _is_network_tower(neighbor) and neighbor != exclude_tower and connected.has(neighbor.get_instance_id()):
			return ""
	return "Guardshelm: Must connect to the Keep through allied towers."

func _is_network_tower(tower: Tower) -> bool: ##keeps placement and runtime connectivity on the same rules, including disabled branches
	return is_instance_valid(tower) and not tower.abstractive and not tower.hostile and not tower.environmental and not tower.is_queued_for_deletion() and tower.current_state == Tower.State.ACTIVE

func _get_connected_tower_ids(island: Island, exclude_tower: Tower = null) -> Dictionary[int, bool]: ##collects keep-rooted components through the same flood-fill used by tower networks
	var connected: Dictionary[int, bool] = {}
	for keep: Tower in island.get_towers_by_type(Towers.Type.PLAYER_CORE):
		if not _is_network_tower(keep) or keep == exclude_tower or connected.has(keep.get_instance_id()):
			continue
		connected[keep.get_instance_id()] = true
		for neighbor: Tower in island.topology_service.get_connected_towers(keep, _is_network_tower, exclude_tower):
			connected[neighbor.get_instance_id()] = true
	return connected

func _set_tower_disabled(tower: Tower, is_disabled: bool) -> bool: ##applies this relic's local suspension through existing tower and effect lifecycle hooks
	if tower.disabled == is_disabled or tower.abstractive or tower.current_state != Tower.State.ACTIVE or not tower.is_inside_tree() or tower.is_queued_for_deletion():
		return false
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island) or tower.get_parent() != Run.references.island or Run.references.island.game_ending:
		return false
	tower.disabled = is_disabled
	if is_instance_valid(tower.combat_light):
		tower.combat_light.available = not is_disabled and not tower.environmental and not tower.hostile
	if is_instance_valid(tower.behavior):
		if is_disabled:
			tower.behavior.detach()
		else:
			tower.behavior.attach()
	for prototype: EffectPrototype in tower.effect_prototypes.duplicate():
		var effect: EffectInstance = tower.get_effect_instance_by_prototype(prototype)
		if not is_instance_valid(effect):
			continue
		if is_disabled:
			effect.detach()
		else:
			effect.attach_to(tower)
	UI.update_unit_state.emit(tower)
	return true
