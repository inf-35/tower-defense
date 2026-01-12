# amplifier_behavior.gd
extends Behavior
class_name AmplifierBehavior

# --- configuration ---
# assign a ModifierDataPrototype resource in the inspector to define the buff this amplifier provides.
@export var modifier_prototype: ModifierDataPrototype ##modifier that will be applied to adjacent towers (per adjacent amplifier)

# --- private state ---
# this dictionary tracks the modifiers this specific amplifier has applied to other towers.
# format: { Tower -> Modifier }
var _applied_modifiers: Dictionary[Tower, Modifier] = {}

# called by the unit chassis after all components are ready.
func start() -> void:
	# this behavior only makes sense on a tower.
	if not unit is Tower:
		push_warning("AmplifierBehavior can only be used on a Tower.")
		set_process(false) # disable this behavior
		return
	
	# connect to the host tower's signal to know when its neighbors change.
	var tower: Tower = unit as Tower
	if not tower.adjacency_updated.is_connected(_on_adjacency_updated):
		tower.adjacency_updated.connect(_on_adjacency_updated)
	
	# perform an initial check in case the tower is spawned next to existing towers.
	# we need to wait a frame for the island to settle its adjacency calculations.
	await get_tree().process_frame
	if is_instance_valid(tower):
		_on_adjacency_updated(tower.get_adjacent_towers())

# this is the main logic, triggered whenever the host tower's neighbors change.
func _on_adjacency_updated(new_adjacencies: Dictionary[Vector2i, Tower]) -> void:
	# fail gracefully if no modifier is defined for this amplifier.
	if not is_instance_valid(modifier_prototype):
		_clear_all_modifiers() # clear any existing effects and stop
		return

	var current_adjacent_towers: Array[Tower] = new_adjacencies.values()
	
	# --- 1. remove modifiers from towers that are no longer adjacent ---
	var towers_to_unmodify: Array[Tower]
	for affected_tower: Tower in _applied_modifiers:
		if not current_adjacent_towers.has(affected_tower):
			towers_to_unmodify.append(affected_tower)
	
	for tower: Tower in towers_to_unmodify:
		_remove_modifier_from_tower(tower)

	# --- 2. apply modifiers to newly adjacent towers ---
	for tower: Tower in current_adjacent_towers:
		if not _applied_modifiers.has(tower):
			_apply_modifier_to_tower(tower)

# this is the canonical cleanup function, called automatically when the tower is destroyed.
func _exit_tree() -> void:
	_clear_all_modifiers()

# --- private helper functions ---

func _apply_modifier_to_tower(target_tower: Tower) -> void:
	if not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
		return
	
	var new_modifier := modifier_prototype.generate_modifier()
	# brand the modifier with our host unit's ID for clear source tracking.
	new_modifier.source_id = unit.unit_id
	
	target_tower.modifiers_component.add_modifier(new_modifier)
	_applied_modifiers[target_tower] = new_modifier # track the applied modifier

func _remove_modifier_from_tower(target_tower: Tower) -> void:
	if not _applied_modifiers.has(target_tower):
		return
		
	if is_instance_valid(target_tower) and is_instance_valid(target_tower.modifiers_component):
		var modifier_to_remove: Modifier = _applied_modifiers[target_tower]
		target_tower.modifiers_component.remove_modifier(modifier_to_remove)
	
	_applied_modifiers.erase(target_tower)

func _clear_all_modifiers() -> void:
	# create a copy of the keys because we will be modifying the dictionary while iterating
	var towers_to_clear: Array[Tower] = _applied_modifiers.keys()
	for tower: Tower in towers_to_clear:
		_remove_modifier_from_tower(tower)

func get_display_data() -> Dictionary:
	# we use StringNames (&) for performance and to avoid typos.
	return {
		ID.UnitState.AMPLIFIER_MODIFIER : modifier_prototype
	}
