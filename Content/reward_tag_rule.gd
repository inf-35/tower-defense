extends Resource
class_name RewardTagRule

##defines how matching any configured tower tag should affect a reward's weight
enum Operation {
	MULTIPLY,
	REQUIRE,
}

@export var tags: Array[Towers.Tag] = []
@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 2.0 ##multiplier applied when a multiply rule matches

##returns true when the player's currently available towers or rites satisfy this rule
func is_satisfied(owned_tags: Dictionary[Towers.Tag, bool]) -> bool:
	for tag: Towers.Tag in tags:
		if owned_tags.get(tag, false):
			return true
	return false

##returns the weight multiplier contributed by this rule against the current owned tag set
func get_multiplier(owned_tags: Dictionary[Towers.Tag, bool]) -> float:
	var condition_met: bool = is_satisfied(owned_tags)

	match operation:
		Operation.REQUIRE:
			return 1.0 if condition_met else 0.0
		Operation.MULTIPLY:
			return value if condition_met else 1.0
	return 1.0
