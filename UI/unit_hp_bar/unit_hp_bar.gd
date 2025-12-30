extends ProgressBar
class_name UnitHPBar

var bar_size: Vector2 = Vector2(5, 1.2)

var _health_component: HealthComponent
var _parent_unit: Node2D

func setup(unit: Unit, health_comp: HealthComponent) -> void:
	_parent_unit = unit
	_health_component = health_comp
	
	_health_component.health_changed.connect(_on_health_changed)
	visible = false
	
	var max_hp: float = unit.get_stat(Attributes.id.MAX_HEALTH)
	var scale_factor: float = log(max_hp*0.5 + 1) * 0.5
	bar_size.x *= scale_factor + 1
	bar_size.y *= scale_factor * 0.25 + 1
	
	size = bar_size
	position = Vector2(0, -5) - bar_size * 0.5
	

func _process(_delta):
	if is_instance_valid(_parent_unit):
		rotation = -_parent_unit.rotation #counter rotate
		
func _on_health_changed(new_health: float) -> void:
	value = new_health
	max_value = _health_component.max_health # Update max in case of buffs
	
	# Visibility Logic:
	# Show if damaged (health < max) AND alive (health > 0)
	var is_damaged = new_health < max_value
	var is_alive = new_health > 0
	
	visible = is_damaged and is_alive
