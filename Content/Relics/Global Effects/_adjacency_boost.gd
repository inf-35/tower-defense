# adjacency_boost_effect.gd
extends GlobalEffect
class_name AdjacencyBoostEffect

# --- configuration (designer-friendly) ---
# these are now exported, allowing designers to configure the effect in the editor
@export_category("Targeting")
@export var host_tower_type: Towers.Type ## the type of tower that receives the buff. VOID = all are accepted
@export var adjacent_tower_type: Towers.Type ## the type of tower that provides the buff. VOID = all are accepted

@export_category("Effect")
@export var _modifier_prototype: ModifierDataPrototype ## the modifier to apply per adjacent stack

# --- state ---
# this now tracks the number of active stacks and the modifier instance
# { Tower -> {STACKS: int, MODIFIER: Modifier} }
var _buffed_towers: Dictionary[Tower, Dictionary] = {}
# constant keys
const STACKS: StringName = &"stacks"
const MODIFIER: StringName = &"modifier"

func initialise() -> void:
	References.island.tower_created.connect(_on_tower_created)
	
	# evaluate all existing towers immediately
	for tower: Tower in get_tree().get_nodes_in_group(References.TOWER_GROUP):
		_on_tower_created(tower)

func _on_tower_created(tower: Tower) -> void:
	# connect to the tower's own adjacency update signal
	tower.adjacency_updated.connect(func(_adjacencies): _evaluate_tower(tower))
	# run an initial check
	_evaluate_tower(tower)

# this function contains the core stacking and modifier logic
func _evaluate_tower(tower: Tower) -> void:
	if not is_instance_valid(tower) or (tower.type != host_tower_type and host_tower_type != Towers.Type.VOID):
		# if this tower is not the type we want to buff, ensure any old buffs are removed
		_remove_buff(tower)
		return

	# count how many adjacent towers match the required type
	var adjacent_stacks: int = 0
	for adjacent_tower: Tower in tower.get_adjacent_towers().values():
		if is_instance_valid(adjacent_tower) and (adjacent_tower.type == adjacent_tower_type or adjacent_tower_type == Towers.Type.VOID):
			adjacent_stacks += 1
	
	# if there are stacks to apply, add or update the buff
	if adjacent_stacks > 0:
		_apply_or_update_buff(tower, adjacent_stacks)
	# otherwise, remove any existing buff
	else:
		_remove_buff(tower)

func _apply_or_update_buff(tower: Tower, stacks: int) -> void:
	# if the tower is already buffed, we update its existing modifier
	if _buffed_towers.has(tower):
		var existing_data: Dictionary = _buffed_towers[tower] 
		# no change needed if the stack count is the same
		if existing_data[STACKS] == stacks:
			return
		
		var modifier: Modifier = existing_data[MODIFIER]
		# update the modifier's properties directly
		modifier.multiplicative = pow(_modifier_prototype.multiplicative, stacks)
		modifier.additive = _modifier_prototype.additive * stacks
		
		# notify the component that the modifier has changed
		tower.modifiers_component.change_modifier(modifier)
		existing_data[STACKS] = stacks
	# if the tower is not yet buffed, create a new modifier
	else:
		var new_modifier := _modifier_prototype.generate_modifier()
		new_modifier.multiplicative = pow(_modifier_prototype.multiplicative, stacks)
		new_modifier.additive = _modifier_prototype.additive * stacks
		
		tower.modifiers_component.add_modifier(new_modifier)
		_buffed_towers[tower] = {STACKS: stacks, MODIFIER: new_modifier}

func _remove_buff(tower: Tower) -> void:
	if _buffed_towers.has(tower):
		var data: Dictionary = _buffed_towers[tower]
		tower.modifiers_component.remove_modifier(data[MODIFIER])
		_buffed_towers.erase(tower)
