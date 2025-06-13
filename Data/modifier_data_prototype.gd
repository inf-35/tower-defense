extends Data
class_name ModifierDataPrototype

@export var attribute: Attributes.id = Attributes.id.MAX_HEALTH
@export var status: Attributes.Status

@export var additive: float = 0.0
@export var multiplicative: float = 1.0 #multiplicative (ie * 1.0)
@export var override = null #overrides all values, basically sets the attribute to this value

@export var cooldown: float = -1.0 #negative cooldown -> permanent

func generate_modifier() -> Modifier:
	var modifier: = Modifier.new(attribute, status)
	modifier.attribute = attribute
	modifier.status = status
	modifier.additive = additive
	modifier.multiplicative = multiplicative
	modifier.override = override
	modifier.cooldown = cooldown
	return modifier
