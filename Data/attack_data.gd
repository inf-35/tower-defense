extends Data
class_name AttackData

@export var range: float = 20.0
@export var cooldown: float = 1.0
@export var radius: float = 0.0

@export var damage: float = 0.0
@export var modifiers: Array[ModifierDataPrototype] = []
#see unit.gd, deal_hit and take_hit, and HitData

func generate_modifiers() -> Array[Modifier]: #transform Array[ModifierDataPrototype] -> Array[Modifier]
	var modifier_instances: Array[Modifier] = []
	for modifier_prototype: ModifierDataPrototype in modifiers:
		modifier_instances.append(modifier_prototype.generate_modifier())
	
	return modifier_instances

func generate_hit_data() -> HitData:
	var hit_data := HitData.new()
	hit_data.damage = damage
	hit_data.modifiers = generate_modifiers()
	
	return hit_data
