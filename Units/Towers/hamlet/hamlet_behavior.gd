extends Behavior
class_name HamletBehavior

func check_placement_validity(island: Island, cell: Vector2i, facing: int) -> Dictionary:
	var neighbors := (unit as Tower).get_adjacent_cells()
	var valid: bool = false
	#check for a village
	for n: Vector2i in neighbors:
		if island.get_tower_on_tile(n) != null:
			if island.get_tower_on_tile(n).type == Towers.Type.GENERATOR:
				valid = true

	if valid:
		return { "valid": true, "error": "" }
	else:
		return { "valid": false, "error": "Must touch a {T_GENERATOR}" }
