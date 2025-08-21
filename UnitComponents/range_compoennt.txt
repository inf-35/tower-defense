extends UnitComponent
class_name RangeComponent
#responsible for identifying targets for towers
var area: Area2D

var _enemies_in_range: Array[Unit] = []
var targeting_mode: TargetingMode = TargetingMode.CLOSEST

var attack_component: AttackComponent
var modifiers_component: ModifiersComponent

enum TargetingMode {
	CLOSEST,
	MOST_HEALTH,
	FASTEST,
	SCATTER,
}

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

func get_target():
	if _enemies_in_range.is_empty():
		return null
	
	match targeting_mode:
		TargetingMode.CLOSEST:
			var record_distance: float = INF
			var record_unit: Unit
			for enemy: Unit in _enemies_in_range:
				var distance: float = enemy.movement_component.position.length_squared()
				if Targeting.is_unit_overkilled(enemy):
					continue
				if distance < record_distance:
					record_distance = distance
					record_unit = enemy
			
			return record_unit
		TargetingMode.MOST_HEALTH:
			var record_health: float = -INF
			var record_unit: Unit
			for enemy: Unit in _enemies_in_range:
				var health: float = enemy.health_component.health
				if Targeting.is_unit_overkilled(enemy):
					continue
				if health > record_health:
					record_health = health
					record_unit = enemy
			
			return record_unit
		TargetingMode.SCATTER:
			return _enemies_in_range.pick_random()
		_:
			return _enemies_in_range[0]
