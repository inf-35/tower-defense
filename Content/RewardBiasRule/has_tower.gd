extends RewardBiasRule
class_name RuleHasTower

@export var tower_types: Array[Towers.Type]

func _check_condition() -> bool:
	for tower_type: Towers.Type in tower_types:
		#check if the player has unlocked this tower
		if Run.player.is_tower_unlocked(tower_type):
			return true
		#check if the player has placed a satisfying tower
		elif Run.references.island.get_towers_by_type(tower_type).size() > 0:
			return true

	return false
