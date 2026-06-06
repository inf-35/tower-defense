extends Resource
class_name RewardBiasRule

#determines how the rule affects the weight
enum Operation {
	MULTIPLY,   ##weight = weight * value (good for boosts like "2x chance")
	REQUIRE,    ##weight = weight * (condition ? 1 : 0) ("must have x")
}

@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 2.0 ##the multiplier applied if the condition is met (ignored for require/forbid)

func _check_condition() -> bool:
	return true

#public api called by rewardservice
func get_multiplier() -> float:
	var condition_met: bool = _check_condition()

	match operation:
		Operation.REQUIRE:
			return 1.0 if condition_met else 0.0
		Operation.MULTIPLY:
			return value if condition_met else 1.0
	return 1.0
