extends Data
class_name ModifierDataPrototype

@export var attribute: Attributes.id = Attributes.id.MAX_HEALTH

@export var additive: float = 0.0
@export var multiplicative: float = 1.0 #multiplicative (ie * 1.0)
@export var override: float = INF #overrides all values, basically sets the attribute to this value

@export var cooldown: float = -1.0 #negative cooldown -> permanent

func generate_modifier() -> Modifier:
	var modifier: = Modifier.new(attribute)
	modifier.attribute = attribute
	modifier.additive = additive
	modifier.multiplicative = multiplicative
	if override != INF:
		modifier.override = override
	modifier.cooldown = cooldown
	return modifier
