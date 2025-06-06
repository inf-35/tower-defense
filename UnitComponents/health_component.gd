extends UnitComponent
class_name HealthComponent

signal died()
signal health_changed(new_health: float)

@export var health_data: HealthData = preload("res://Data/Health/tower_default.tres")

var _modifiers_component: ModifiersComponent

var health: float = health_data.max_health:
	set(new_health):
		health = new_health
		if health_data == null:
			return
		
		new_health = clampf(new_health, 0.0, health_data.max_health)
		if new_health == health:
			return
		
		health = new_health
		health_changed.emit(health)
		if health < 0.01:
			died.emit()

func inject_components(modifiers_component: ModifiersComponent):
	if modifiers_component != null:
		_modifiers_component = modifiers_component
		_modifiers_component.register_data(health_data)
		create_stat_cache(_modifiers_component, [Attributes.id.MAX_HEALTH, Attributes.id.REGENERATION])

func _ready():
	_STAGGER_CYCLE = 5
	_stagger = randi_range(0, _STAGGER_CYCLE)

func _process(delta : float) -> void:
	#_stagger += 1
	#_accumulated_delta += delta
	#if _stagger % _STAGGER_CYCLE != 1:
		#return
		
	var regeneration: float = get_stat(_modifiers_component, health_data, Attributes.id.REGENERATION)
		
	health += regeneration * delta
	_accumulated_delta = 0.0
