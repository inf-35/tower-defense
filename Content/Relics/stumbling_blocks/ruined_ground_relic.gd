# ruined_ground_slow_effect.gd
extends GlobalEffect
class_name RuinedGroundRelic

# --- configuration (designer-friendly) ---
@export_category("Effect")
# attribute to modify
@export var modifier: ModifierDataPrototype
# --- state ---
# this dictionary tracks which units this relic is currently slowing
# and the specific modifier instance it applied to them.
var _slowed_units: Dictionary[Unit, Modifier] = {}

func initialise() -> void:
	# connect to the new global signal for unit movement
	References.unit_changed_cell.connect(_on_unit_cell_changed)

# this is the core of the relic's logic
func _on_unit_cell_changed(unit: Unit, old_cell: Vector2i, new_cell: Vector2i) -> void:
	# this effect only applies to hostile units
	if not is_instance_valid(unit) or not unit.hostile:
		return

	var is_on_ruin: bool = Player.ruin_service.is_cell_ruined(new_cell)
	var was_on_ruin: bool = Player.ruin_service.is_cell_ruined(old_cell)
	var is_currently_slowed: bool = _slowed_units.has(unit)

	# --- case 1: unit has moved onto a ruined tile and isn't slowed yet ---
	if is_on_ruin and not is_currently_slowed:
		if is_instance_valid(unit.modifiers_component):
			# apply the status effect directly. we use add_status which is better
			# for stackable effects like this than a raw modifier.
			var modifier_instance: Modifier = modifier.generate_modifier()
			modifier_instance.cooldown = -1.0 #we handle modifier removal manually
			unit.modifiers_component.add_modifier(modifier_instance)
			_slowed_units[unit] = modifier_instance # mark this unit as affected
	
	# --- case 2: unit has moved off a ruined tile and was being slowed by us ---
	elif not is_on_ruin and was_on_ruin and is_currently_slowed:
		if is_instance_valid(unit.modifiers_component):
			# remove the stacks we added.
			# we add a negative amount to counteract the original application.
			unit.modifiers_component.remove_modifier(_slowed_units[unit])
			_slowed_units.erase(unit) # unmark this unit
			
