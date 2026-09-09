extends EffectPrototype
class_name CapacityGeneratorEffect

@export var base_capacity: float = 0.0
@export var bonus_terrain_type: Terrain.Base = Terrain.Base.EARTH
@export var bonus_capacity_amount: float = 0.0
@export var adjacent_water_capacity_amount: float = 0.0 ##extra population generated for each cardinal adjacent waterlike tile

class CapacityState extends RefCounted:
	var last_capacity_generation: float = 0.0

func _debug_capacity(instance: EffectInstance, action: String, delta: float = 0.0) -> void: ##prints opt-in capacity deltas for tracing population changes without affecting normal runs
	if not Run.player.DEBUG_CAPACITY:
		return
	var host_name := "<no host>" if not is_instance_valid(instance.host) else "%s@%s" % [instance.host.name, str(instance.host.tower_position)]
	print("[CapacityEffect] %s | host=%s | delta=%s | last=%s" % [
		action,
		host_name,
		str(delta),
		str((instance.state as CapacityState).last_capacity_generation),
	])

static func _static_init() -> void:
	ModifiersComponent.register_dynamic_attribute(&"capacity")

func _init() -> void:
	event_hooks =  [GameEvent.EventType.ADJACENCY_UPDATED, GameEvent.EventType.DIED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = CapacityState.new()
	return instance

func _handle_display_attach(instance: EffectInstance) -> void: ##registers the authored minimum capacity value for prototype and tooltip displays
	instance.host.modifiers_component.register_dynamic_stat(&"capacity", _calculate_display_contribution())

func _handle_attach(instance: EffectInstance) -> void: ##adds this effect's current calculated population contribution to the player cap
	var state: CapacityState = instance.state as CapacityState
	var initial_contribution: float = _calculate_contribution(instance)
	state.last_capacity_generation = initial_contribution
	instance.host.modifiers_component.register_dynamic_stat(&"capacity", initial_contribution)
	Run.player.add_to_total_capacity(initial_contribution, "attach %s" % instance.host.name)
	_debug_capacity(instance, "attach", initial_contribution)

func _handle_detach(instance: EffectInstance) -> void: ##removes the last recorded contribution when this tower stops providing population
	var state: CapacityState = instance.state as CapacityState
	Run.player.remove_from_total_capacity(state.last_capacity_generation, "detach %s" % instance.host.name)
	_debug_capacity(instance, "detach", -state.last_capacity_generation)
	instance.host.modifiers_component.register_dynamic_stat(&"capacity", 0.0)
	state.last_capacity_generation = 0.0

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##refreshes terrain-sensitive capacity when the host tower receives an adjacency update
	if event.event_type == GameEvent.EventType.ADJACENCY_UPDATED:
		_handle_adjacency_updated(instance)

func _handle_adjacency_updated(instance: EffectInstance) -> void: ##applies only the delta between old and new calculated contribution
	var state: CapacityState = instance.state as CapacityState
	var old_contribution: float = state.last_capacity_generation
	var new_contribution: float = _calculate_contribution(instance)
	if is_equal_approx(old_contribution, new_contribution):
		return

	var delta := new_contribution - old_contribution
	Run.player.add_to_total_capacity(delta, "adjacency %s" % instance.host.name)
	state.last_capacity_generation = new_contribution
	instance.host.modifiers_component.register_dynamic_stat(&"capacity", new_contribution)
	_debug_capacity(instance, "adjacency_updated", delta)

func _calculate_contribution(instance: EffectInstance) -> float: ##calculates the live population contribution from base, host terrain, and optional adjacent water
	if not is_instance_valid(instance.host):
		return 0.0

	var total_contribution: float = base_capacity

	var host_terrain: Terrain.Base = instance.host.get_terrain_base()
	if host_terrain == bonus_terrain_type:
		total_contribution += bonus_capacity_amount

	total_contribution += _count_adjacent_waterlike_tiles(instance.host) * adjacent_water_capacity_amount

	return total_contribution

func _count_adjacent_waterlike_tiles(host: Unit) -> int: ##counts cardinal adjacent waterlike cells for settlement-style capacity scaling
	if is_zero_approx(adjacent_water_capacity_amount):
		return 0

	var tower: Tower = host as Tower
	if not is_instance_valid(tower):
		return 0
	if not is_instance_valid(Run.references.island):
		return 0

	var count: int = 0
	for cell: Vector2i in tower.get_adjacent_cells():
		if not Run.references.island.terrain_base_grid.has(cell):
			continue
		if Terrain.is_waterlike(Run.references.island.terrain_base_grid[cell]):
			count += 1
	return count

func _calculate_display_contribution() -> float: ##returns a conservative stat-display value when live board adjacency is not available
	return base_capacity + bonus_capacity_amount + adjacent_water_capacity_amount
