# amplifier_effect.gd
extends EffectPrototype
class_name AmplifierEffect

# --- parameters ---
# these are configured in the inspector for this effect resource.
@export var params: Dictionary = {
	"modifier_prototype": null, #ModifierDataPrototype: the modifier to apply to adjacent towers
}

# --- state ---
# this is the runtime state for each instance of the effect.
var state: Dictionary = {
	"applied_modifiers": {}, #Dictionary[Tower, Modifier]: tracks which towers we've modified
}

# called when the effect is removed from its host tower.
# ensures all buffs are cleaned up properly.
func _handle_detach(instance: EffectInstance) -> void:
	_clear_all_modifiers(instance)

# the main logic, triggered by game events.
func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	# we only care about adjacency updates.
	if event.event_type != GameEvent.EventType.ADJACENCY_UPDATED:
		return

	# --- prerequisite checks ---
	assert(instance.params.has("modifier_prototype"))
	assert(instance.state.has("applied_modifiers"))
	assert(instance.host is Tower)

	var adjacency_data: AdjacencyReportData = event.data as AdjacencyReportData
	
	# sanity check to ensure we are processing the correct event.
	if adjacency_data.pivot != instance.host:
		push_error("Amplifier: received wrong adjacency report for pivot: ", adjacency_data.pivot, " on host: ", instance.host)
		return
	
	var modifier_prototype: ModifierDataPrototype = instance.params.modifier_prototype
	# fail gracefully if no modifier is defined for this amplifier.
	if not is_instance_valid(modifier_prototype):
		_clear_all_modifiers(instance) # clear any existing effects and stop
		return

	# --- state retrieval ---
	var applied_modifiers: Dictionary = instance.state.applied_modifiers
	var current_adjacent_towers: Array[Tower] = adjacency_data.adjacent_towers.values()

	# --- comparison and update logic ---
	# 1. identify towers that are no longer adjacent and remove their modifiers.
	var towers_to_unmodify: Array[Tower]
	for affected_tower: Tower in applied_modifiers:
		if not current_adjacent_towers.has(affected_tower):
			towers_to_unmodify.append(affected_tower)
	
	for tower: Tower in towers_to_unmodify:
		if is_instance_valid(tower): #ensure tower still exists
			var modifier_to_remove: Modifier = applied_modifiers[tower]
			tower.modifiers_component.remove_modifier(modifier_to_remove)
		applied_modifiers.erase(tower)

	# 2. identify newly adjacent towers and apply modifiers to them.
	for tower: Tower in current_adjacent_towers:
		if not applied_modifiers.has(tower):
			var new_modifier := modifier_prototype.generate_modifier()
			tower.modifiers_component.add_modifier(new_modifier)
			applied_modifiers[tower] = new_modifier # track the applied modifier

# private helper to remove all modifiers created by this effect instance.
func _clear_all_modifiers(instance: EffectInstance) -> void:
	assert(instance.state.has("applied_modifiers"))
	
	var applied_modifiers: Dictionary = instance.state.applied_modifiers

	for affected_tower: Tower in applied_modifiers:
		print("Removing modifier at affected tower: ", affected_tower)
		if is_instance_valid(affected_tower):
			var modifier_to_remove: Modifier = applied_modifiers[affected_tower]
			affected_tower.modifiers_component.remove_modifier(modifier_to_remove)
	
	applied_modifiers.clear()
