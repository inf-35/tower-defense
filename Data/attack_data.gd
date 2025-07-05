extends Data
class_name AttackData

@export var delivery_method: DeliveryData.DeliveryMethod

@export var range: float = 20.0:
	set(new_value):
		range = new_value
		value_changed.emit(Attributes.id.RANGE)
@export var cooldown: float = 1.0:
	set(new_value):
		cooldown = new_value
		value_changed.emit(Attributes.id.COOLDOWN)
@export var radius: float = 0.0:
	set(new_value):
		radius = new_value
		value_changed.emit(Attributes.id.RADIUS)
@export var damage: float = 0.0:
	set(new_value):
		damage = new_value
		value_changed.emit(Attributes.id.DAMAGE)

@export var status_effects: Array[StatusEffectPrototype] = []
@export var modifiers: Array[ModifierDataPrototype] = []

@export_category("Projectile Properties")
@export var projectile_speed: float = 10.0 #only applicable for delivery_method == PROJECTILE
@export var vertical_force: float = -10.0
#see unit.gd, deal_hit and take_hit, and HitData

func generate_modifiers() -> Array[Modifier]: #transform Array[ModifierDataPrototype] -> Array[Modifier]
	var modifier_instances: Array[Modifier] = []
	for modifier_prototype: ModifierDataPrototype in modifiers:
		modifier_instances.append(modifier_prototype.generate_modifier())
	
	return modifier_instances
	
func format_status_effects() -> Dictionary[Attributes.Status, Vector2]: #see HitData for requirements
	var output: Dictionary[Attributes.Status, Vector2] = {}
	for status_effect: StatusEffectPrototype in status_effects:
		var vector: Vector2 = Vector2(status_effect.stack, status_effect.cooldown)
		output[status_effect.type] = vector
	
	return output

func generate_hit_data() -> HitData:
	var hit_data := HitData.new()
	hit_data.damage = damage
	hit_data.modifiers = generate_modifiers()
	hit_data.status_effects = format_status_effects()
	
	return hit_data
