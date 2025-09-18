extends UnitComponent
class_name RangeComponent
#responsible for identifying targets for towers
var area: Area2D

var _enemies_in_range: Array[Unit] = []
@export var targeting_mode: TargetingMode = TargetingMode.CLOSEST
# if this is set, get_target will prioritize it over all other logic.
var priority_target_override: Unit = null

var attack_component: AttackComponent
var modifiers_component: ModifiersComponent

enum TargetingMode {
	CLOSEST,
	MOST_HEALTH,
	FASTEST,
	SCATTER,
}

func _ready():
	set_process(false)

func inject_components(_attack_component: AttackComponent, _modifiers_component: ModifiersComponent):
	attack_component = _attack_component
	modifiers_component = _modifiers_component
	
	if attack_component == null or modifiers_component == null:
		return
	
	area = Area2D.new() #generate range area
	area.name = "Range"
	unit.add_child.call_deferred(area)
	
	var shape := CircleShape2D.new()
	shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child.call_deferred(collision)
	#set detection bitmasks
	area.collision_layer = 0
	area.collision_mask = 0b0000_0010 if unit.hostile else 0b0000_0001
	area.monitoring = true
	area.monitorable = false
	
	modifiers_component.stat_changed.connect(func(attr: Attributes.id): #change radius of detection area to fit range
		if not attr == Attributes.id.RANGE:
			return

		shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)
	)
		
	area.area_entered.connect(func(enemy_area_candidate: Area2D):
		if not enemy_area_candidate is Hitbox:
			return
			
		if enemy_area_candidate.unit == null:
			return

		if enemy_area_candidate.unit.hostile == unit.hostile: #same affiliation
			return
		
		_enemies_in_range.append(enemy_area_candidate.unit)
	)
	
	area.area_exited.connect(func(exiting_area_candidate: Area2D):
		if not exiting_area_candidate is Hitbox:
			return
			
		if exiting_area_candidate.unit == null:
			return
			
		_enemies_in_range.erase(exiting_area_candidate.unit)
	)

func is_target_valid(unit: Unit) -> bool:
	if not is_instance_valid(unit.movement_component) or not is_instance_valid(unit.health_component):
		return false

	if Targeting.is_unit_overkilled(unit):
		return false
		
	if unit.incorporeal:
		return false
		
	return true
	
func get_target():
	if _enemies_in_range.is_empty():
		return null
	
	if is_instance_valid(priority_target_override):
		# check if the override target is still in range.
		if _enemies_in_range.has(priority_target_override):
			return priority_target_override
		else:
			# if the override target is dead or out of range, clear it and fall back to normal targeting.
			priority_target_override = null 
	
	match targeting_mode:
		TargetingMode.CLOSEST:
			var record_distance: float = INF
			var record_unit: Unit
			for enemy: Unit in _enemies_in_range:
				if not is_target_valid(enemy):
					continue
				var distance: float = (enemy.position - unit.position).length_squared()
				if distance < record_distance:
					record_distance = distance
					record_unit = enemy
			
			return record_unit
		TargetingMode.MOST_HEALTH:
			var record_health: float = -INF
			var record_unit: Unit
			for enemy: Unit in _enemies_in_range:
				if not is_target_valid(enemy):
					continue
				var health: float = enemy.health_component.health
				if health > record_health:
					record_health = health
					record_unit = enemy
			
			return record_unit
		TargetingMode.SCATTER:
			return _enemies_in_range.pick_random()
		_:
			return _enemies_in_range[0]
