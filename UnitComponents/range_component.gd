extends UnitComponent
class_name RangeComponent
#responsible for identifying targets for towers
@export var area: Area2D

var _enemies_in_range: Array[Unit] = []

func _ready():
	area.area_entered.connect(func(enemy_area_candidate: Area2D):
		if not enemy_area_candidate is Hitbox:
			return
			
		if enemy_area_candidate.unit == null:
			return
			
		if not enemy_area_candidate.unit.hostile:
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

	return _enemies_in_range[0]
