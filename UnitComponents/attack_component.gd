extends UnitComponent
class_name AttackComponent
#polymorphic, stateless class that takes in AttackData and executes attacks
class AttackLineageContext extends RefCounted:
	var lineage: EventLineage = EventLineage.new()
	var recursion: int = 0
	var clear_attack_id: bool = false
	var use_source_position_override: bool = false
	var source_position: Vector2 = Vector2.ZERO
	var use_damage_override: bool = false
	var damage_override: float = 0.0

@export var attack_data: Data ##must resolve to attackdata and stay registered with modifiers
@export var muzzle: Marker2D ##optional origin marker for projectile and hitscan attacks
var _modifiers_component: ModifiersComponent
var _queued_attack_parent_data: EventData
var _queued_attack_producer: Object
var _queued_attack_use_source_position_override: bool = false
var _queued_attack_source_position: Vector2 = Vector2.ZERO
var _queued_attack_use_damage_override: bool = false
var _queued_attack_damage_override: float = 0.0

#proxy variables
var damage: float:
	get():
		return get_stat(_modifiers_component, attack_data, Attributes.id.DAMAGE)
var radius: float:
	get():
		if attack_data.delivery_method == DeliveryData.DeliveryMethod.CONE_AOE:
			return get_stat(_modifiers_component, attack_data, Attributes.id.RANGE)
		return get_stat(_modifiers_component, attack_data, Attributes.id.RADIUS)
var cooldown: float:
	get():
		return get_stat(_modifiers_component, attack_data, Attributes.id.COOLDOWN)
var range: float:
	get():
		return get_stat(_modifiers_component, attack_data, Attributes.id.RANGE)

var current_cooldown: float = 0.0 ##centralised value for cooldown to next attack, starts at cooldown and ticks towards zero

static var _next_attack_id: int = 1

static func get_next_attack_id() -> int:
	var attack_id: int = _next_attack_id
	_next_attack_id += 1
	return attack_id

func _ready() -> void: ##starts cooldown ticking and desyncs identical towers a little
	set_process(true)
	current_cooldown += randf_range(0.0, 1.0)

func _process(_delta: float) -> void: ##ticks attack cooldown in game time
	current_cooldown -= Clock.game_delta

func inject_components(modifiers_component: ModifiersComponent) -> void: ##registers attack data against the host modifier stack
	_modifiers_component = modifiers_component
	_modifiers_component.register_data(attack_data)
	create_stat_cache(_modifiers_component, [Attributes.id.DAMAGE, Attributes.id.RADIUS, Attributes.id.COOLDOWN])

func refresh_cooldown() -> void: ##resets the local cooldown using the current modified attack rate
	current_cooldown = get_stat(_modifiers_component, attack_data, Attributes.id.COOLDOWN)

func queue_next_attack_context(
	parent_data: EventData,
	producer: Object,
	use_source_position_override: bool = false,
	source_position: Vector2 = Vector2.ZERO,
	use_damage_override: bool = false,
	damage_override: float = 0.0
) -> void: ##arms the next logical attack to inherit lineage and optional one-shot overrides from an external producer
	if not is_instance_valid(parent_data) or not is_instance_valid(producer):
		_clear_queued_attack_context()
		return

	_queued_attack_parent_data = parent_data
	_queued_attack_producer = producer
	_queued_attack_use_source_position_override = use_source_position_override
	_queued_attack_source_position = source_position
	_queued_attack_use_damage_override = use_damage_override
	_queued_attack_damage_override = damage_override

func pull_attack_context() -> AttackLineageContext: ##builds a reusable lineage stamp for one logical attack and consumes any queued override
	var attack_context := AttackLineageContext.new()

	if is_instance_valid(_queued_attack_parent_data) and is_instance_valid(_queued_attack_producer):
		attack_context.use_source_position_override = _queued_attack_use_source_position_override
		attack_context.source_position = _queued_attack_source_position
		attack_context.use_damage_override = _queued_attack_use_damage_override
		attack_context.damage_override = _queued_attack_damage_override

		var template_data := EventData.new()
		if not template_data.derive_lineage_from(_queued_attack_parent_data, _queued_attack_producer):
			_clear_queued_attack_context()
			return null

		attack_context.lineage = template_data.lineage.duplicate()
		attack_context.recursion = template_data.recursion
		_clear_queued_attack_context()
		return attack_context

	if _queued_attack_parent_data != null or _queued_attack_producer != null:
		_clear_queued_attack_context()

	var template_data := EventData.new()
	template_data.seed_root_lineage(unit)
	attack_context.lineage = template_data.lineage.duplicate()
	return attack_context

func create_derived_attack_context(
	parent_data: EventData,
	producer: Object,
	use_source_position_override: bool = false,
	source_position: Vector2 = Vector2.ZERO,
	use_damage_override: bool = false,
	damage_override: float = 0.0
) -> AttackLineageContext: ##builds a one-off derived context for explicit follow-up attacks without consuming the queued root-followup slot
	if not is_instance_valid(parent_data) or not is_instance_valid(producer):
		return null

	var template_data := EventData.new()
	if not template_data.derive_lineage_from(parent_data, producer):
		return null

	var attack_context := AttackLineageContext.new()
	attack_context.lineage = template_data.lineage.duplicate()
	attack_context.recursion = template_data.recursion
	attack_context.clear_attack_id = true
	attack_context.use_source_position_override = use_source_position_override
	attack_context.source_position = source_position
	attack_context.use_damage_override = use_damage_override
	attack_context.damage_override = damage_override
	return attack_context

func apply_attack_context(hit_data: HitData, attack_context: AttackLineageContext) -> bool: ##copies a prepared lineage stamp onto a hit and clears root-only attack identity for derived attacks
	if not is_instance_valid(hit_data) or not is_instance_valid(attack_context):
		return false

	hit_data.lineage = attack_context.lineage.duplicate()
	hit_data.recursion = attack_context.recursion
	if attack_context.use_damage_override:
		hit_data.damage = attack_context.damage_override

	if attack_context.clear_attack_id:
		hit_data.attack_id = 0

	return true

func attack(target: Unit, intercept_override: Vector2 = Vector2.ZERO, spend_cooldown: bool = true) -> void: ##builds a standard single-target attack, optionally spending cooldown, while honouring one-shot lineage overrides
	var attack_context: AttackLineageContext = pull_attack_context()
	if not is_instance_valid(attack_context):
		return

	_attack_with_context(target, attack_context, intercept_override, spend_cooldown)

func attack_with_context(target: Unit, attack_context: AttackLineageContext, intercept_override: Vector2 = Vector2.ZERO, spend_cooldown: bool = true) -> void: ##fires one attack using an explicit lineage context, bypassing the queued root-followup slot
	if not is_instance_valid(attack_context):
		return

	_attack_with_context(target, attack_context, intercept_override, spend_cooldown)

func _attack_with_context(target: Unit, attack_context: AttackLineageContext, intercept_override: Vector2 = Vector2.ZERO, spend_cooldown: bool = true) -> void: ##shared execution path for both normal attacks and immediate explicit follow-up attacks
	if attack_data == null or not is_instance_valid(target):
		return

	if spend_cooldown:
		refresh_cooldown()

	var delivery_data: DeliveryData = generate_delivery_data()
	if attack_context.use_source_position_override:
		delivery_data.use_source_position_override = true
		delivery_data.source_position = attack_context.source_position

	if intercept_override != Vector2.ZERO:
		delivery_data.intercept_position = intercept_override
	else:
		if delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT\
		or delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED:
			delivery_data.intercept_position = predict_intercept_position(unit, target, delivery_data.projectile_speed)
		else:
			delivery_data.intercept_position = target.global_position

	delivery_data.target = target

	var hit_data: HitData = generate_hit_data(delivery_data)
	hit_data.target = target
	hit_data.target_affiliation = target.hostile
	hit_data.attack_id = get_next_attack_id()

	if not apply_attack_context(hit_data, attack_context):
		return

	unit.deal_hit(hit_data, delivery_data)

func generate_delivery_data() -> DeliveryData: ##builds mutable delivery data using the current authored attack profile
	var delivery_data := DeliveryData.new()
	delivery_data.delivery_method = attack_data.delivery_method
	delivery_data.cone_angle = attack_data.cone_angle
	delivery_data.projectile_speed = attack_data.projectile_speed

	if delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT\
	or delivery_data.delivery_method == DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED:
		delivery_data.projectile_lifetime = attack_data.projectile_lifetime
		delivery_data.pierce = attack_data.pierce
		delivery_data.stop_on_walls = attack_data.stop_on_walls

	return delivery_data

func generate_hit_data(delivery_data: DeliveryData = null) -> HitData: ##builds mutable hit data using current stats, statuses, and modifiers
	var hit_data := HitData.new()
	hit_data.damage = get_stat(_modifiers_component, attack_data, Attributes.id.DAMAGE)
	hit_data.radius = get_stat(_modifiers_component, attack_data, Attributes.id.RADIUS)
	if delivery_data and delivery_data.delivery_method == DeliveryData.DeliveryMethod.CONE_AOE:
		hit_data.radius = get_stat(_modifiers_component, attack_data, Attributes.id.RANGE)
		#range is used inplace of radius in cone aoe towers (i.e. flamethrower, frost)

	hit_data.breaking = attack_data.breaking
	hit_data.modifiers = attack_data.generate_modifiers()
	for modifier: Modifier in hit_data.modifiers:
		modifier.source_id = unit.unit_id
	hit_data.status_effects = attack_data.format_status_effects()

	hit_data.vfx_on_impact = attack_data.vfx_on_impact
	hit_data.vfx_on_spawn = attack_data.vfx_on_spawn

	hit_data.source = unit

	return hit_data

func _clear_queued_attack_context() -> void: ##drops any pending external lineage override after it is spent or invalidated
	_queued_attack_parent_data = null
	_queued_attack_producer = null
	_queued_attack_use_source_position_override = false
	_queued_attack_source_position = Vector2.ZERO
	_queued_attack_use_damage_override = false
	_queued_attack_damage_override = 0.0

#used for projectile-based attacks with non-zero traverse times
const MAXIMUM_ACCEPTABLE_INACCURACY: float = 1.0
const MAXIMUM_ITERATIONS: int = 10
static func predict_intercept_position(source_unit: Unit, target_unit: Unit, projectile_speed: float, fast: bool = true, time_offset: float = 0.0) -> Vector2:
	#print("START ESTIMATE ---------------------------------------------------")
	#get the enemy's future position prediction function from its navigation component.
	var enemy_nav_comp = target_unit.navigation_component
	if enemy_nav_comp == null:
		return target_unit.global_position #can't predict, just aim at current position.

	var my_pos = source_unit.global_position if not is_instance_valid(source_unit.attack_component.muzzle) \
		else source_unit.attack_component.muzzle.global_position
	var enemy_pos = target_unit.global_position
	#start with a first guess: how long would it take to hit the enemy's current position?
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

func get_save_data() -> Dictionary:
	return {} #everything here thats persistent is typically run by modifiers component
#NOTE: currently radius is calibrated(?) incorrectly
func setup_radial_pulse(radial_pulse: RadialPulseVFX, vfx_info: VFXInfo) -> void:
	radial_pulse.start_radius = radius * 0.75 * 0.5
	radial_pulse.max_radius = radius * 0.5
	radial_pulse.color_gradient = vfx_info.color_gradient
	radial_pulse.is_full_circle = vfx_info.is_full_circle
	radial_pulse.start_angle_deg = vfx_info.start_angle_deg
	radial_pulse.end_angle_deg = vfx_info.end_angle_deg
