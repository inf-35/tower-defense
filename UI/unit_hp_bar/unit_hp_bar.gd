extends ProgressBar
class_name UnitHPBar

var bar_size: Vector2 = Vector2(5, 1.2)

var _health_component: HealthComponent
var _parent_unit: Node2D

var _status_icons: Dictionary[Attributes.Status, UnitStatusIcon]

const VERTICAL_OFFSET: Vector2 = Vector2(0,-5)

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
	position = VERTICAL_OFFSET - bar_size * 0.5
	step = 0.01
	
	if unit.modifiers_component:
		unit.modifiers_component.status_changed.connect(_on_status_changed)

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
	
func _on_status_changed(status: Attributes.Status, stacks: float, duration: float):
	if stacks <= 0.0: #removal
		if not _status_icons.has(status):
			return
			
		var icon_to_remove: UnitStatusIcon = _status_icons[status]
		_status_icons.erase(status)
		icon_to_remove.free()
		_reposition_icons()
		return
	
	else: #addition/refresh
		if not _status_icons.has(status):
			_status_icons[status] = preload("res://UI/unit_hp_bar/status_icon.tscn").instantiate()
			_status_icons[status].setup(status)
			add_child(_status_icons[status])

		_status_icons[status].update_data(stacks, duration)
		_reposition_icons() 
		
func _reposition_icons() -> void:
	var active_icons: Array[UnitStatusIcon] = _status_icons.values()
	var spacing: float = 2.0
	
	var total_width: float = 0.0
	#pre-position
	for icon: Control in active_icons:
		var w: float = icon.size.x * icon.scale.x
		total_width += w
	
	var accumulated_width: float = 0.0
	for icon: Control in active_icons:
		var w: float = icon.size.x * icon.scale.x
		icon.position = VERTICAL_OFFSET
		icon.position.x = 0.0 - total_width * 0.5 + w * 0.5 + accumulated_width
		accumulated_width += w
		
		
