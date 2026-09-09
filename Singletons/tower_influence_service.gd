extends RefCounted
class_name TowerInfluenceService

var revision: int = 0 ##increments whenever indexed spatial relationships change

var _next_registration_id: int = 1
var _registrations_by_owner: Dictionary[int, Dictionary] = {}
var _registrations_by_cell: Dictionary[Vector2i, Array] = {}

func sync_influences(owner: Object, source: Tower, influences: Array[TowerInfluence]) -> void: ##atomically replaces every tower-indexed relationship described by one behavior
	if not is_instance_valid(owner) or not is_instance_valid(source):
		return

	var owner_id: int = owner.get_instance_id()
	_clear_owner_id(owner_id)
	var owner_registrations: Dictionary = {}
	for influence: TowerInfluence in influences:
		if influence == null or influence.scope != TowerInfluence.Scope.TOWER:
			continue
		if influence.key == &"" or owner_registrations.has(influence.key):
			continue
		influence.registration_id = _next_registration_id
		_next_registration_id += 1
		influence.owner_ref = weakref(owner)
		influence.source_ref = weakref(source)
		influence.cells = _dedupe_cells(influence.cells)
		owner_registrations[influence.key] = influence
		for cell: Vector2i in influence.cells:
			if not _registrations_by_cell.has(cell):
				_registrations_by_cell[cell] = []
			_registrations_by_cell[cell].append(influence)
	if not owner_registrations.is_empty():
		_registrations_by_owner[owner_id] = owner_registrations
	revision += 1

func clear_owner(owner: Object) -> void: ##removes every spatial relationship published by one behavior during detach or teardown
	if not is_instance_valid(owner):
		return
	var owner_id: int = owner.get_instance_id()
	if not _registrations_by_owner.has(owner_id):
		return
	_clear_owner_id(owner_id)
	revision += 1

func get_influences_for_tower(tower: Tower) -> Array[TowerInfluence]: ##dedupes multi-cell intersections and returns only relationships whose cheap target filters accept the candidate
	var matches: Array[TowerInfluence] = []
	if not is_instance_valid(tower):
		return matches

	var seen: Dictionary[int, bool] = {}
	for cell: Vector2i in tower.get_occupied_cells():
		if not _registrations_by_cell.has(cell):
			continue
		var registrations: Array = _registrations_by_cell[cell].duplicate()
		for influence: TowerInfluence in registrations:
			if not influence.is_valid():
				_prune_stale_registration(influence)
				continue
			if seen.has(influence.registration_id) or not influence.matches_tower(tower):
				continue
			seen[influence.registration_id] = true
			matches.append(influence)
	return matches

func get_matching_global_relics(tower: Tower) -> Array[RelicData]: ##evaluates owned global modifiers and introspectable effects without expanding global rules into every map cell
	var matches: Array[RelicData] = []
	if not is_instance_valid(tower) or not is_instance_valid(Run.player):
		return matches

	for relic: RelicData in Run.player.active_relics:
		if not is_instance_valid(relic):
			continue
		var active: bool = false
		for modifier_prototype: GlobalModifierPrototype in relic.modifier_prototypes:
			if modifier_prototype.matches_unit(tower):
				active = true
				break
		if not active and is_instance_valid(relic.global_effect):
			active = not relic.global_effect.get_tower_influences(tower).is_empty()
		if active:
			matches.append(relic)
	return matches

func clear() -> void: ##drops all board-owned registrations when the island resets or leaves the run
	_registrations_by_owner.clear()
	_registrations_by_cell.clear()
	_next_registration_id = 1
	revision += 1

func _remove_registration(influence: TowerInfluence) -> void: ##erases one registration from each cell bucket without scanning unrelated map cells
	if influence == null:
		return
	for cell: Vector2i in influence.cells:
		if not _registrations_by_cell.has(cell):
			continue
		_registrations_by_cell[cell].erase(influence)
		if _registrations_by_cell[cell].is_empty():
			_registrations_by_cell.erase(cell)

func _clear_owner_id(owner_id: int) -> void: ##removes one owner's complete registration set without incrementing revision mid-replacement
	if not _registrations_by_owner.has(owner_id):
		return
	var owner_registrations: Dictionary = _registrations_by_owner[owner_id]
	for influence: TowerInfluence in owner_registrations.values():
		_remove_registration(influence)
	_registrations_by_owner.erase(owner_id)

func _prune_stale_registration(influence: TowerInfluence) -> void: ##cleans weakly-owned records encountered during queries after an unexpected owner teardown
	if influence == null:
		return
	_remove_registration(influence)
	for owner_id: int in _registrations_by_owner.keys():
		var owner_registrations: Dictionary = _registrations_by_owner[owner_id]
		for key: StringName in owner_registrations.keys():
			if owner_registrations[key] != influence:
				continue
			owner_registrations.erase(key)
			break
		if owner_registrations.is_empty():
			_registrations_by_owner.erase(owner_id)
		break
	revision += 1

func _dedupe_cells(cells: Array[Vector2i]) -> Array[Vector2i]: ##keeps one registration reference per cell even when a multi-tile topology query produces repeated coordinates
	var output: Array[Vector2i] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		output.append(cell)
	return output
