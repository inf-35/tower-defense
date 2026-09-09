extends UnitComponent
class_name HealthComponent
signal health_changed(new_health: float)

@export var health_data: Data = load("res://Content/Health/tower_default.tres") ##CANNOT BE FURTHER SPECIFIED - WILL CAUSE BUG

var _modifiers_component: ModifiersComponent

var max_health: float #updated by health setter
var health: float:
	set(new_health):
		if health_data == null:
			return
		if is_equal_approx(health, new_health):
			return

		max_health = get_stat(_modifiers_component, health_data, Attributes.id.MAX_HEALTH)
		new_health = clampf(new_health, 0.0, max_health)
		if new_health == health:
			return
		health = new_health
		health_changed.emit(health)
		UI.update_unit_health.emit(unit, max_health, health)

		#NOTE: unit.died is now executed on unit.take_hit (after it calls take_damage)

var shield: float ##not linked to a attribute, simple counter
#NOTE: shield does not support fancy effects, like boosts to shield as it is not linked to the modifiers component system

func inject_components(modifiers_component: ModifiersComponent) -> void:
	if modifiers_component != null:
		_modifiers_component = modifiers_component

		_modifiers_component.stat_changed.connect(func(attr: Attributes.id):
			if not attr == Attributes.id.MAX_HEALTH:
				return

			health = health #this triggers the health setter function, which clamps to maxhp
		)

		_modifiers_component.register_data(health_data)
		create_stat_cache(_modifiers_component, [Attributes.id.MAX_HEALTH, Attributes.id.REGENERATION, Attributes.id.REGEN_PERCENT])

	shield = health_data.max_shield
	UI.update_unit_health.emit(unit, max_health, health)

func take_damage(damage: float, breaking: bool = false) -> float: ##applies incoming damage and returns the direct health loss caused by this call
	damage = maxf(damage, 0.0)
	var absorbed_damage: float = 0 #damage absorbed by shield
	#shield phase
	if breaking:
		absorbed_damage = min(damage, shield)
		shield -= absorbed_damage
		damage -= absorbed_damage
	#health phase
	if is_zero_approx(shield): #direct damage is not taken if there is a shield remaining
		var health_damage: float = minf(damage, health)
		health -= damage
		show_damage_number(damage)
		return health_damage

	return 0.0

func show_damage_number(damage: float) -> void: ##displays the standard damage marker without changing health
	UI.floating_text_manager.show_damage_value(damage, unit)

func _ready() -> void:
	max_health = get_stat(_modifiers_component, health_data, Attributes.id.MAX_HEALTH)
	health = max_health
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_next_tick_interval = _get_initial_tick_interval()

const _TICK_INTERVAL: float = 0.25
const _TICK_STAGGER_BUCKETS: int = 32
const MAX_POISON_DAMAGE_PER_SECOND: float = 2.0
var _next_tick_interval: float = _TICK_INTERVAL

func _process(_d : float) -> void:
	if unit.abstractive:
		return
	
	_accumulated_delta += Clock.game_delta
	if _accumulated_delta > _next_tick_interval:
		_tick(_accumulated_delta)
		_accumulated_delta = 0.0
		_next_tick_interval = _TICK_INTERVAL

func _tick(delta: float) -> void:
	var regeneration: float = get_stat(_modifiers_component, health_data, Attributes.id.REGENERATION)
	var regen_percent: float = get_stat(_modifiers_component, health_data, Attributes.id.REGEN_PERCENT)
	var regen_remainder_percent: float = get_stat(_modifiers_component, health_data, Attributes.id.REGEN_REMAINDER_PERCENT)
	if is_zero_approx(regeneration) and is_zero_approx(regen_percent) and is_zero_approx(regen_remainder_percent):
		return

	var benchmark = health
	var regen_remainder_delta: float = regen_remainder_percent * max_health * delta
	var uncapped_poison_delta: float = _get_uncapped_poison_delta(delta)
	if uncapped_poison_delta < 0.0:
		regen_remainder_delta = regen_remainder_delta - uncapped_poison_delta + _cap_poison_delta(uncapped_poison_delta, delta, _get_poison_stack_count())

	health += regeneration * delta + regen_percent * max_health * delta + regen_remainder_delta
	var difference = benchmark - health
	_record_status_damage(difference, delta)
	if difference > 0.1:
		UI.floating_text_manager.show_damage_value(difference, unit, Color.TRANSPARENT, 0.8)

	if is_zero_approx(health): #we die due to a status effect
		unit.died.emit(HitReportData.blank_hit_report)

	_accumulated_delta = 0.0

func _get_initial_tick_interval() -> float: ##distributes first maintenance ticks so units keep identical integration without converging on one frame
	if not is_instance_valid(unit) or unit.abstractive:
		return _TICK_INTERVAL

	var stagger_bucket: int = unit.get_instance_id() % _TICK_STAGGER_BUCKETS
	return _TICK_INTERVAL * float(stagger_bucket + 1) / float(_TICK_STAGGER_BUCKETS)

func _get_uncapped_poison_delta(delta: float) -> float:
	if not is_instance_valid(_modifiers_component):
		return 0.0
	if not _modifiers_component.has_status(Attributes.Status.POISON):
		return 0.0

	var poison_stacks: float = _get_poison_stack_count()
	var poison_data: Attributes.StatusAttributeData = Attributes.status_effects[Attributes.Status.POISON].get_attribute_data(Attributes.id.REGEN_REMAINDER_PERCENT)
	if poison_data == null:
		return 0.0

	return poison_data.additive_per_stack * poison_stacks * max_health * delta

func _get_poison_stack_count() -> float:
	if not is_instance_valid(_modifiers_component):
		return 0.0
	return _modifiers_component.get_status_count(Attributes.Status.POISON)

func _cap_poison_delta(poison_delta: float, delta: float, poison_stacks: float) -> float:
	return -minf(-poison_delta, MAX_POISON_DAMAGE_PER_SECOND * poison_stacks * delta)

func _record_status_damage(net_damage: float, delta: float) -> void: ##allocates net tick damage across any active status effects that directly drive regen-based attrition
	if net_damage <= 0.0:
		return
	if not is_instance_valid(_modifiers_component):
		return
	if not Run.has_active_run() or not is_instance_valid(Run.damage_tracker):
		return

	var contributions: Dictionary[Attributes.Status, float] = {}
	var total_negative_contribution: float = 0.0
	for status_type: Attributes.Status in _modifiers_component._status_effects:
		var status: StatusEffect = _modifiers_component._status_effects[status_type]
		var status_data: Attributes.StatusEffectData = Attributes.status_effects[status.type]

		var contribution: float = 0.0
		for attribute_data: Attributes.StatusAttributeData in status_data.attributes:
			contribution += _get_status_damage_contribution(status, attribute_data, delta)

		if contribution <= 0.0:
			continue

		contributions[status_type] = contribution
		total_negative_contribution += contribution

	if total_negative_contribution <= 0.0:
		return

	var clamped_damage: float = minf(net_damage, total_negative_contribution)
	for status_type: Attributes.Status in contributions:
		var share: float = contributions[status_type] / total_negative_contribution
		Run.damage_tracker.record_status_damage(status_type, clamped_damage * share)

func _get_status_damage_contribution(status: StatusEffect, attribute_data: Attributes.StatusAttributeData, delta: float) -> float: ##returns positive expected damage caused by one regen-like status attribute row
	if not DamageTrackerService.STATUS_DAMAGE_ATTRIBUTES.has(attribute_data.attribute):
		return 0.0

	var contribution: float = 0.0
	match attribute_data.attribute:
		Attributes.id.REGENERATION:
			contribution = -(attribute_data.additive_per_stack * status.stack * delta)
		Attributes.id.REGEN_PERCENT:
			contribution = -(attribute_data.additive_per_stack * status.stack * max_health * delta)
		Attributes.id.REGEN_REMAINDER_PERCENT:
			contribution = -(attribute_data.additive_per_stack * status.stack * max_health * delta)
			if status.type == Attributes.Status.POISON:
				contribution = -_cap_poison_delta(-contribution, delta, status.stack)

	return maxf(contribution, 0.0)

func get_save_data() -> Dictionary:
	return {
		"max_health": max_health,
		"health": health,
		"shield": shield,
	}
