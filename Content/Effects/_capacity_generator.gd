extends EffectPrototype
class_name CapacityGeneratorEffect

@export var params: Dictionary = {
	"base_capacity" : 0.0, #base capacity produced
	"terrain_conditional_capacity" : [Terrain.Base.EARTH, 0.0], #terrain conditional capacity
	#in format [Terrain.Base, capacity granted]
}

var state: Dictionary = {
	"last_capacity_generation" : 0.0,
}

func _handle_attach(instance: EffectInstance):
	var initial_contribution: float = _calculate_contribution(instance)
	instance.state.last_capacity_generation = initial_contribution
	Player.add_to_total_capacity(initial_contribution)

func _handle_detach(instance: EffectInstance):
	var amount_to_remove: float = instance.state.get("last_capacity_generation", 0.0)
	Player.remove_from_total_capacity(amount_to_remove)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	# this function handles dynamic updates while the effect is active.
	# for example, if the terrain under the tower is changed by an expansion.
	var old_contribution: float = instance.state.get("last_capacity_generation", 0.0)
	var new_contribution: float = _calculate_contribution(instance)
	# if the contribution hasn't changed, do nothing.
	if is_equal_approx(old_contribution, new_contribution):
		return
	# calculate, apply delta between the new and old values.
	Player.add_to_total_capacity(new_contribution - old_contribution)
	# update the state to reflect the new contribution amount for future calculations.
	instance.state.last_capacity_generation = new_contribution
	
	print("Capacity contribution changed by %f" % str(new_contribution - old_contribution))
	
func _calculate_contribution(instance: EffectInstance) -> float:
	if not is_instance_valid(instance.host):
		return 0.0
	
	assert(instance.params.has("base_capacity"))
	assert(instance.params.has("terrain_conditional_capacity"))
	assert(instance.state.has("last_capacity_generation"))

	var total_contribution: float = instance.params.get("base_capacity", 0.0)

	var host_terrain: Terrain.Base = instance.host.get_terrain_base()
	var terrain_condition: Array = instance.params.get("terrain_conditional_capacity", [])
	if terrain_condition.size() == 2:
		#[Terrain.Base, capacity (float)]
		var required_terrain: Terrain.Base = terrain_condition[0]
		var capacity_bonus: float = terrain_condition[1]
	
		if host_terrain == required_terrain:
			total_contribution += capacity_bonus
	#TODO: more checks?
	return total_contribution
