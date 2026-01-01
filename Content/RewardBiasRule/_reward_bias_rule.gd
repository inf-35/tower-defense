extends Resource
class_name RewardBiasRule

# determines how the rule affects the weight
enum Operation {
	MULTIPLY,   ## weight = weight * value (Good for boosts like "2x chance")
	REQUIRE,    ## weight = weight * (condition ? 1 : 0) ("must have x")
}

@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 2.0 ## The multiplier applied if the condition is met (ignored for Require/Forbid)

func _check_condition() -> bool:
	return true

# public API called by RewardService
func get_multiplier() -> float:
	var condition_met: bool = _check_condition()
	
	match operation:
		Operation.REQUIRE:
			return 1.0 if condition_met else 0.0
		Operation.MULTIPLY:
			return value if condition_met else 1.0
	return 1.0
