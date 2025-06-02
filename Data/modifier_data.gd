extends Resource
class_name ModifierData

@export var attribute: Attributes.id = Attributes.id.MAX_HEALTH
@export var status: Attributes.Status


@export var additive: float = 0.0
@export var multiplicative: float = 1.0 #multiplicative (ie * 1.0)
@export var override = null #overrides all values, basically sets the attribute to this value

@export var cooldown: float = -1.0 #negative cooldown -> permanent
