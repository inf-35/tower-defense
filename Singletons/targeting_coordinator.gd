extends Node #TargetingCoordinator

var damage_reservations: Dictionary[Unit, float] = {}
#records expected damage dealt to enemy, prevents two towers "overkilling" a unit.
func add_damage(unit: Variant, damage: float): 
	if not is_instance_valid(unit):
		return

	if not damage_reservations.has(unit):
		damage_reservations[unit] = damage
	else:
		damage_reservations[unit] += damage

func clear_damage(unit):
	if not is_instance_valid(unit):
		return
		
	damage_reservations.erase(unit)
	
func is_unit_overkilled(unit: Unit) -> bool: #prevents overkill on units
	if not damage_reservations.has(unit):
		return false
		
	if damage_reservations[unit] >= unit.health_component.health:
		return true
	else:
		return false
