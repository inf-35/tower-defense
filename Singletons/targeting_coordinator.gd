extends Node #TargetingCoordinator

var damage_reservations: Dictionary[Unit, float] = {}

func add_damage(unit: Unit, damage: float):
	if not is_instance_valid(unit):
		return

	if not damage_reservations.has(unit):
		damage_reservations[unit] = damage
	else:
		damage_reservations[unit] += damage

func is_unit_overkilled(unit: Unit) -> bool: #prevents overkill on units
	if not damage_reservations.has(unit):
		return false
		
	if damage_reservations[unit] >= unit.health_component.health:
		return true
	else:
		return false
