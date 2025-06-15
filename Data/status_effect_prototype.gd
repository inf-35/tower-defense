extends Data
class_name StatusEffectPrototype

@export var type: Attributes.Status
@export var stack: float = 1.0
@export var cooldown: float = -1.0 #negative = permanent
