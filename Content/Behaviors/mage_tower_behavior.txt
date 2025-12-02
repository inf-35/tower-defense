# mage_tower_behavior.gd
extends Behavior
class_name MageTowerBehavior

signal _carrier_signal #NOTE: this simulates a static signal, and is an unfortunate hack
static var _singleton := MageTowerBehavior.new()
static var mage_changed := Signal(_singleton._carrier_signal)

const MAGE_TOWER_GROUP: StringName = &"mage_towers"

# --- configuration (designer-friendly) ---
@export var modifier_prototype: ModifierDataPrototype ## the modifier to apply per valid diagonal Mage tower 

# --- state ---
var _buff_modifier: Modifier = null
var _current_stacks: int = 0

# this function is called by the unit's initialize() method
func start() -> void:
	# 1. register this tower with the group for discovery by others
	unit.add_to_group(MAGE_TOWER_GROUP)
	mage_changed.emit()
	# ensure we are removed from the group upon death to trigger updates for others
	unit.died.connect(
		func(): 
			unit.remove_from_group(MAGE_TOWER_GROUP)
			mage_changed.emit()
	)

	# 2. connect to the grid change signal to know when to update our buff
	mage_changed.connect(_recalculate_buff)
	
	# 3. perform an initial calculation
	_recalculate_buff()

# this is the main trigger, called only when the tower layout changes
func _recalculate_buff() -> void:
	if not is_instance_valid(unit):
		return

	var diagonal_mages_count: int = 0
	var my_pos: Vector2i = unit.tower_position
	
	# iterate through all other mages in the group
	for other_mage: Node in get_tree().get_nodes_in_group(MAGE_TOWER_GROUP):
		if other_mage == unit:
			continue # don't check against self

		var other_pos: Vector2i = other_mage.tower_position
		
		# --- check 1: is it on a diagonal axis? ---
		if abs(my_pos.x - other_pos.x) == abs(my_pos.y - other_pos.y):
			diagonal_mages_count += 1
	
	# only update the modifier if the number of stacks has actually changed
	if diagonal_mages_count != _current_stacks:
		_current_stacks = diagonal_mages_count
		_apply_or_update_buff()

# this helper function manages the modifier on the tower
func _apply_or_update_buff() -> void:
	if not is_instance_valid(modifiers_component):
		return
		
	# if there are no stacks, remove any existing buff
	if _current_stacks == 0:
		if is_instance_valid(_buff_modifier):
			modifiers_component.remove_modifier(_buff_modifier)
			_buff_modifier = null
		return

	# if a buff modifier doesn't exist yet, create it
	if not is_instance_valid(_buff_modifier):
		_buff_modifier = modifier_prototype.generate_modifier()
		# we will set the values below before adding it
		modifiers_component.add_modifier(_buff_modifier)

	# update the modifier's properties based on the stack count
	_buff_modifier.multiplicative = pow(modifier_prototype.multiplicative, _current_stacks)
	_buff_modifier.additive = modifier_prototype.additive * _current_stacks
	
	# notify the component that the modifier's values have changed
	modifiers_component.change_modifier(_buff_modifier)

# this tower uses the standard attack loop, so its update function uses the default
