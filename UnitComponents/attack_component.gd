extends UnitComponent
class_name AttackComponent
#polymorphic, stateless class that takes in AttackData and executes attacks
@export var attack_data: Data ##must be AttackData, but cannot be further specified due to strange engine bug
@export var muzzle: Marker2D ##where the bullets are coming from
var _modifiers_component: ModifiersComponent

var current_cooldown: float = 0.0 ##centralised value for cooldown to next attack, starts at cooldown and ticks towards zero

func _ready():
	set_process(true)

func _process(_delta: float):
	current_cooldown -= Clock.game_delta

func inject_components(modifiers_component: ModifiersComponent):
	_modifiers_component = modifiers_component
	_modifiers_component.register_data(attack_data)
	create_stat_cache(_modifiers_component, [Attributes.id.DAMAGE, Attributes.id.RADIUS, Attributes.id.COOLDOWN])

func attack(target: Unit, intercept_override: Vector2 = Vector2.ZERO):
	if attack_data == null:
		return
		
	current_cooldown = get_stat(_modifiers_component, attack_data, Attributes.id.COOLDOWN) #reset cooldown
	#NOTE: this must be before the actual attack execution
	var delivery_data := DeliveryData.new()
	delivery_data.delivery_method = attack_data.delivery_method
	delivery_data.cone_angle = attack_data.cone_angle
	delivery_data.target = target
	if intercept_override != Vector2.ZERO:
		delivery_data.projectile_speed = attack_data.projectile_speed
		delivery_data.intercept_position = intercept_override
	else:
		if delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT\
		or delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED:
			delivery_data.projectile_speed = attack_data.projectile_speed
			delivery_data.projectile_lifetime = attack_data.projectile_lifetime
			delivery_data.intercept_position = predict_intercept_position(unit, target, delivery_data.projectile_speed)
		else:
			delivery_data.intercept_position = target.global_position
	
	var hit_data: HitData = attack_data.generate_hit_data() 
	hit_data.source = unit
	hit_data.target = target
	hit_data.damage = get_stat(_modifiers_component, attack_data, Attributes.id.DAMAGE)
	hit_data.radius = get_stat(_modifiers_component, attack_data, Attributes.id.RADIUS)
	if delivery_data.delivery_method == DeliveryData.DeliveryMethod.CONE_AOE:
		hit_data.radius = get_stat(_modifiers_component, attack_data, Attributes.id.RANGE)
		##range is used inplace of radius in cone aoe towers (i.e. flamethrower, frost)
	hit_data.target_affiliation = target.hostile
	hit_data.expected_damage = hit_data.damage
	
	for modifier: Modifier in hit_data.modifiers:
		modifier.source_id = unit.unit_id

	unit.deal_hit(hit_data, delivery_data)

#used for projectile-based attacks with non-zero traverse times
const MAXIMUM_ACCEPTABLE_INACCURACY: float = 1.0
const MAXIMUM_ITERATIONS: int = 10
static func predict_intercept_position(source_unit: Unit, target_unit: Unit, projectile_speed: float, fast: bool = true, time_offset: float = 0.0) -> Vector2:
	#print("START ESTIMATE ---------------------------------------------------")
	# Get the enemy's future position prediction function from its navigation component.
	var enemy_nav_comp = target_unit.navigation_component
	if enemy_nav_comp == null:
		return target_unit.global_position # Can't predict, just aim at current position.

	var my_pos = source_unit.global_position if not is_instance_valid(source_unit.attack_component.muzzle) \
		else source_unit.attack_component.muzzle.global_position
	var enemy_pos = target_unit.global_position
	# Start with a first guess: how long would it take to hit the enemy's current position?
	var previous_estimate: Vector2 #previous estimate for enemy's position @ intercept
	var estimated_travel_time: float = my_pos.distance_to(enemy_pos) / projectile_speed + time_offset
	var inaccuracy: float = INF #estimated inaccuracy (difference between each iteration)
	var current_iteration: int = 0
	#Refine guess until we converge within MAXIMUM_ACCEPTABLE_INACCURACY (or hit max iterations)
	while inaccuracy > MAXIMUM_ACCEPTABLE_INACCURACY and current_iteration <= MAXIMUM_ITERATIONS:
		current_iteration += 1
		var future_enemy_pos: Vector2 = enemy_nav_comp.get_position_in_future(estimated_travel_time) if not fast else enemy_nav_comp.fast_get_position_in_future(estimated_travel_time)
		if previous_estimate: #if we do have a previous estimate (false for 1st iteration)
			inaccuracy = (future_enemy_pos - previous_estimate).length()
		#revise time estimate using new position estimate
		estimated_travel_time = my_pos.distance_to(future_enemy_pos) / projectile_speed + time_offset
		previous_estimate = future_enemy_pos #save current estimate into previous estimate
	#after a few iterations we should converge to a fairly accurate answer
	return enemy_nav_comp.get_position_in_future(estimated_travel_time) if not fast else enemy_nav_comp.fast_get_position_in_future(estimated_travel_time)
