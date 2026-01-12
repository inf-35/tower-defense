extends Data
class_name AttackData

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
@export var projectile_lifetime: float = -1.0 ##lifetime of projectile before despawning (negative = infinite)

@export_group("Projectile Simulated")
@export var pierce: int = 1 ##how many times does this projectile pierce through enemies? (-1 = infinite)
@export var stop_on_walls: bool = true ##does this projectile stop on walls?

@export_group("Hit Properties")
@export var cone_angle: float = 0.0 ##for coneAOE in degrees, note: 0.0 means full-cone implicitly
#see unit.gd, deal_hit and take_hit, and HitData

func generate_modifiers() -> Array[Modifier]: #transform Array[ModifierDataPrototype] -> Array[Modifier]
	var modifier_instances: Array[Modifier] = []
	for modifier_prototype: ModifierDataPrototype in modifiers:
		modifier_instances.append(modifier_prototype.generate_modifier())
	
	return modifier_instances
	
func format_status_effects() -> Dictionary[Attributes.Status, Vector2]: #see HitData for requirements
	var output: Dictionary[Attributes.Status, Vector2] = {}
	for status_effect: StatusEffectPrototype in status_effects:
		if not status_effect: continue
		var vector: Vector2 = Vector2(status_effect.stack, status_effect.cooldown)
		output[status_effect.type] = vector
	
	return output

func generate_generic_hit_data() -> HitData: ##generates a generic (unitless) hitdata as opposed to attack_component. ...
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

func generate_generic_delivery_data() -> DeliveryData: ##generates a generic (unitless) deliverydata as opposed to attack_component. ...
	var delivery_data := DeliveryData.new()
	delivery_data.delivery_method = delivery_method
	delivery_data.cone_angle = cone_angle
	delivery_data.projectile_speed = projectile_speed
	delivery_data.projectile_lifetime = projectile_lifetime
	
	if delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT\
	or delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED:
		delivery_data.projectile_lifetime = projectile_lifetime
		delivery_data.pierce = pierce
		delivery_data.stop_on_walls = stop_on_walls
		#delivery_data.intercept_position = predict_intercept_position(unit, target, delivery_data.projectile_speed)

	return delivery_data
