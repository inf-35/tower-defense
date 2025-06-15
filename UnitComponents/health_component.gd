extends UnitComponent
class_name HealthComponent

signal died()
signal health_changed(new_health: float)

@export var health_data: HealthData = preload("res://Data/Health/tower_default.tres")

var _modifiers_component: ModifiersComponent

var max_health: float #updated by health setter
var health: float = get_stat(_modifiers_component, health_data, Attributes.id.MAX_HEALTH):
	set(new_health):
		if health_data == null:
			return
		
		max_health = get_stat(_modifiers_component, health_data, Attributes.id.MAX_HEALTH)
		new_health = clampf(new_health, 0.0, max_health)
		if new_health == health:
			return
		health = new_health
		health_changed.emit(health)
		if health < 0.01:
			died.emit()

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
	
	if not unit.get_node_or_null("Hitbox"):
		var hitbox := Hitbox.new() #generate range area
		hitbox.name = "Hitbox"
		hitbox.unit = unit
		unit.add_child.call_deferred(hitbox)
		
		var shape := RectangleShape2D.new()
		shape.size = Vector2(Island.CELL_SIZE, Island.CELL_SIZE)
		
		var collision := CollisionShape2D.new()
		collision.shape = shape
		hitbox.add_child.call_deferred(collision)
		#set detection bitmasks
		hitbox.collision_layer = 0b0000_0001 if unit.hostile else 0b0000_0010
		hitbox.collision_mask = 0
		hitbox.monitoring = false
		hitbox.monitorable = true


func _ready():
	_STAGGER_CYCLE = 5
	_stagger = randi_range(0, _STAGGER_CYCLE)
	

func _process(delta : float) -> void:
	#_stagger += 1
	#_accumulated_delta += delta
	#if _stagger % _STAGGER_CYCLE != 1:
		#return
		
	var regeneration: float = get_stat(_modifiers_component, health_data, Attributes.id.REGENERATION)
	var regen_percent: float = get_stat(_modifiers_component, health_data, Attributes.id.REGEN_PERCENT)
	if regeneration == 0 and regen_percent == 0:
		return
		
	health += regeneration * delta + regen_percent * max_health * delta
	_accumulated_delta = 0.0
