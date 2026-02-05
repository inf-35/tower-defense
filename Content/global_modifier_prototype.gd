extends ModifierDataPrototype
class_name GlobalModifierPrototype ##used to define a global modifier

enum TargetFilter {
	ALL,
	ALL_TOWERS,
	TOWERS_BY_ELEMENT, ##towers are filtered by required_element also
	TOWERS_BY_TYPE,
	ENEMIES_ONLY,
}

@export var target_filter: TargetFilter = TargetFilter.ALL
@export var required_element: Towers.Element = Towers.Element.KINETIC
@export var required_type: Towers.Type = Towers.Type.VOID

func matches_unit(unit: Unit) -> bool:
	# 1. Filter by Type
	match target_filter:
		TargetFilter.ALL:
			return true
		TargetFilter.ALL_TOWERS:
			if unit is Tower: return true
		TargetFilter.TOWERS_BY_ELEMENT:
			if unit is Tower and required_element == Towers.get_tower_element(unit.type):
				return true
			else:
				return false
		TargetFilter.TOWERS_BY_TYPE:
			if unit is Tower and required_type == unit.type:
				return true
			else:
				return false
		TargetFilter.ENEMIES_ONLY:
			if unit.hostile: return true
			
	return true
