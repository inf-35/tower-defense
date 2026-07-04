extends Data
class_name ModifierDataPrototype

@export var attribute: Attributes.id = Attributes.id.MAX_HEALTH ##key for static attributes
@export var key: StringName = &"" ##key for custom attributes

@export var additive: float = 0.0
@export var multiplicative: float = 1.0 ##multiplicative (ie * 1.0)
@export var override: float = INF ##overrides all values, basically sets the attribute to this value

@export var cooldown: float = -1.0 ##negative cooldown -> permanent

func generate_modifier() -> Modifier:
	var modifier: = Modifier.new(attribute)
	if key == &"":
		modifier.attribute = attribute
	else:
		modifier.attribute = ModifiersComponent.get_dynamic_id(key)
	modifier.additive = additive
	modifier.multiplicative = multiplicative
	if override != INF:
		modifier.override = override
	modifier.cooldown = cooldown
	return modifier

func apply_single_source_stacks(modifier: Modifier, count: int) -> void: ##folds repeated contributions from one source into one modifier so local stacks add linearly while separate sources still compound
	modifier.additive = additive * count
	if modifier.attribute == Attributes.id.COOLDOWN and not is_equal_approx(multiplicative, 1.0) and is_zero_approx(additive):
		var single_rate_bonus: float = (1.0 / multiplicative) - 1.0
		modifier.multiplicative = 1.0 / (1.0 + single_rate_bonus * count)
		return

	modifier.multiplicative = 1.0 + (multiplicative - 1.0) * count
