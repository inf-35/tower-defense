extends EffectPrototype
class_name GlobalDistributorEffect

@export var effect_to_grant: EffectPrototype
@export var tower_type_filter: Towers.Type

class GlobalDistributorState extends RefCounted:
	#track granted hosts weakly so relic removal can unwind local effects without owning tower lifetime
	var tower_refs: Array[WeakRef] = []

func _init() -> void: ##registers this as a global relic effect that only needs tower-build notifications after its initial full scan
	event_hooks = [GameEvent.EventType.TOWER_BUILT]
	global = true

func create_instance() -> EffectInstance: ##creates one runtime state object that remembers which towers received the granted local effect
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = GlobalDistributorState.new()
	return instance

func _handle_detach(instance: EffectInstance) -> void: ##removes the granted local effect from every still-live tracked tower when the relic leaves play
	var state: GlobalDistributorState = instance.state as GlobalDistributorState
	for tower_ref: WeakRef in state.tower_refs:
		var tower: Tower = tower_ref.get_ref() as Tower
		if is_instance_valid(tower):
			tower.remove_effect(effect_to_grant)
	state.tower_refs.clear()

func _handle_attach(instance: EffectInstance) -> void: ##retrofits the relic onto towers that already existed before the relic was acquired
	for t: Tower in Run.references.island.get_all_towers():
		_grant_to_tower(instance.state as GlobalDistributorState, t)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##keeps the granted local effect in sync for towers constructed after relic acquisition
	if event.event_type == GameEvent.EventType.TOWER_BUILT:
		var t: Tower = event.data.tower
		_grant_to_tower(instance.state as GlobalDistributorState, t)

func _grant_to_tower(state: GlobalDistributorState, tower: Tower) -> void: ##applies the local effect once to each qualifying tower and remembers that host for later cleanup
	if not is_instance_valid(tower):
		return
	if tower_type_filter != Towers.Type.VOID and tower.type != tower_type_filter:
		return
	if _has_tracked_tower(state, tower):
		return

	tower.apply_effect(effect_to_grant)
	state.tower_refs.append(weakref(tower))

func _has_tracked_tower(state: GlobalDistributorState, tower: Tower) -> bool: ##dedupes grants and opportunistically prunes stale weak refs left behind by destroyed towers
	var stale_refs: Array[WeakRef] = []
	for tower_ref: WeakRef in state.tower_refs:
		var tracked_tower: Tower = tower_ref.get_ref() as Tower
		if not is_instance_valid(tracked_tower):
			stale_refs.append(tower_ref)
			continue
		if tracked_tower == tower:
			return true
	for stale_ref: WeakRef in stale_refs:
		state.tower_refs.erase(stale_ref)
	return false

func get_tower_influences(candidate: Tower = null) -> Array[TowerInfluence]: ##delegates pure candidate evaluation to the local effect this global distributor grants
	if not is_instance_valid(candidate) or not is_instance_valid(effect_to_grant):
		return []
	if tower_type_filter != Towers.Type.VOID and candidate.type != tower_type_filter:
		return []
	return effect_to_grant.get_tower_influences(candidate)
