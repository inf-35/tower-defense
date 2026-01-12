extends EffectPrototype
class_name CapacityGeneratorEffect

@export var base_capacity: float = 0.0
@export var bonus_terrain_type: Terrain.Base = Terrain.Base.EARTH
@export var bonus_capacity_amount: float = 0.0

class CapacityState extends RefCounted:
	var last_capacity_generation: float = 0.0

func _init() -> void:
	event_hooks =  [GameEvent.EventType.ADJACENCY_UPDATED, GameEvent.EventType.DIED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = CapacityState.new()
	return instance

func _handle_attach(instance: EffectInstance):
	var state := instance.state as CapacityState
	var initial_contribution: float = _calculate_contribution(instance)
	state.last_capacity_generation = initial_contribution
	Player.add_to_total_capacity(initial_contribution)

func _handle_detach(instance: EffectInstance):
	var state := instance.state as CapacityState
	Player.remove_from_total_capacity(state.last_capacity_generation)
	state.last_capacity_generation = 0.0

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type == GameEvent.EventType.ADJACENCY_UPDATED:
		_handle_adjacency_updated(instance)

func _handle_adjacency_updated(instance: EffectInstance):
	var state := instance.state as CapacityState
	# this function handles dynamic updates while the effect is active.
	# for example, if the terrain under the tower is changed by an expansion.
	var old_contribution: float = state.last_capacity_generation
	var new_contribution: float = _calculate_contribution(instance)
	# if the contribution hasn't changed, do nothing.
	if is_equal_approx(old_contribution, new_contribution):
		return
	# calculate, apply delta between the new and old values.
	Player.add_to_total_capacity(new_contribution - old_contribution)
	# update the state to reflect the new contribution amount for future calculations.
	state.last_capacity_generation = new_contribution
	
	print("Capacity contribution changed by %f" % str(new_contribution - old_contribution))
	
func _calculate_contribution(instance: EffectInstance) -> float:
	if not is_instance_valid(instance.host):
		return 0.0

	var total_contribution: float = base_capacity

	var host_terrain: Terrain.Base = instance.host.get_terrain_base()
	if host_terrain == bonus_terrain_type:
		total_contribution += bonus_capacity_amount
	
	return total_contribution
