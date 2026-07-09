extends Resource
class_name RewardTowerRule

##defines how matching any configured tower type should affect a reward's weight
enum Operation {
	MULTIPLY,
	REQUIRE,
}

@export var tower_types: Array[Towers.Type] = []
@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 2.0 ##multiplier applied when a multiply rule matches

func is_satisfied(owned_tower_types: Dictionary[Towers.Type, bool]) -> bool: ##returns true when the player's currently available towers or rites satisfy this rule
	for tower_type: Towers.Type in tower_types:
		if owned_tower_types.get(tower_type, false):
			return true
	return false

func get_multiplier(owned_tower_types: Dictionary[Towers.Type, bool]) -> float: ##returns the weight multiplier contributed by this rule against the current owned tower set
	var condition_met: bool = is_satisfied(owned_tower_types)

	match operation:
		Operation.REQUIRE:
			return 1.0 if condition_met else 0.0
		Operation.MULTIPLY:
			return value if condition_met else 1.0
	return 1.0
