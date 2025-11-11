extends Data
class_name AttackData

@export_group("Delivery")
@export var delivery_method: DeliveryData.DeliveryMethod

@export_group("Behaviour")
@export var range: float = 20.0:
	set(new_value):
		range = new_value
		value_changed.emit(Attributes.id.RANGE)
@export var cooldown: float = 1.0: ##cooldown between attacks
	set(new_value):
		cooldown = new_value
		value_changed.emit(Attributes.id.COOLDOWN)

@export_group("Hit Characteristics")
@export var radius: float = 0.0: ##range of AOE effect
	set(new_value):
		radius = new_value
		value_changed.emit(Attributes.id.RADIUS)
@export var damage: float = 0.0:
	set(new_value):
		damage = new_value
		value_changed.emit(Attributes.id.DAMAGE)
@export var breaking: bool = false ##can this attack damage shields?

@export var status_effects: Array[StatusEffectPrototype] = []
@export var modifiers: Array[ModifierDataPrototype] = []

@export_group("Presentation")
@export var vfx_on_spawn : VFXInfo #covers the projectile's lifetime, should consist of the projectile itself
@export var vfx_on_impact : VFXInfo #effects that occur when the projectile dies

@export_group("Projectile Properties")
@export var projectile_speed: float = 10.0 #only applicable for delivery_method == PROJECTILE
@export var vertical_force: float = -10.0

@export_group("Hit Properties")
@export var cone_angle: float = 0.0 #for coneAOE in degrees
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
	hit_data.expected_damage = damage
	hit_data.radius = radius
	hit_data.breaking = breaking
	hit_data.modifiers = generate_modifiers()
	hit_data.status_effects = format_status_effects()
	
	hit_data.vfx_on_impact = vfx_on_impact
	hit_data.vfx_on_spawn = vfx_on_spawn
	
	return hit_data
