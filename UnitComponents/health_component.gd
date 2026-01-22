extends UnitComponent
class_name HealthComponent
signal health_changed(new_health: float)

@export var aes: float
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

func inject_components(modifiers_component: ModifiersComponent):
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

func take_damage(damage: float, breaking: bool = false):
	var absorbed_damage: float = 0 #damage absorbed by shield
	#shield phase
	if breaking:
		absorbed_damage = min(damage, shield)
		shield -= absorbed_damage
		damage -= absorbed_damage
	#health phase
	if is_zero_approx(shield): #direct damage is not taken if there is a shield remaining
		health -= damage
		UI.floating_text_manager.show_value(damage, unit.global_position)

func _ready():
	max_health = get_stat(_modifiers_component, health_data, Attributes.id.MAX_HEALTH)
	health = max_health
	#_STAGGER_CYCLE = 5
	#_stagger = randi_range(0, _STAGGER_CYCLE)
	
const _TICK_INTERVAL: float = 0.25
func _process(_d : float) -> void:
	_accumulated_delta += Clock.game_delta
	if _accumulated_delta > _TICK_INTERVAL:
		_tick(_accumulated_delta)
		_accumulated_delta = 0.0
	
func _tick(delta: float) -> void:
	var regeneration: float = get_stat(_modifiers_component, health_data, Attributes.id.REGENERATION)
	var regen_percent: float = get_stat(_modifiers_component, health_data, Attributes.id.REGEN_PERCENT)
	if is_zero_approx(regeneration) and is_zero_approx(regen_percent):
		return
	
	var benchmark = health
	health += regeneration * delta + regen_percent * max_health * delta
	var difference = benchmark - health
	if difference > 0.1:
		UI.floating_text_manager.show_value(difference, unit.global_position, Color.WHITE, 0.8)
	
	if is_zero_approx(health): #we die due to a status effect
		unit.died.emit(HitReportData.blank_hit_report)
	
	_accumulated_delta = 0.0
