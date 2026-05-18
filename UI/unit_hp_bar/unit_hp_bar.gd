extends ProgressBar
class_name UnitHPBar

var bar_size: Vector2 = Vector2(5, 1.2)

var _health_component: HealthComponent
var _parent_unit: Node2D

var _status_icons: Dictionary[Attributes.Status, UnitStatusIcon]

var _is_hovered: bool = false
var _is_selected: bool = false
var _is_important: bool = false

const VERTICAL_OFFSET: Vector2 = Vector2(0,-5)

func setup(unit: Unit, health_comp: HealthComponent) -> void:
	add_to_group(DebugAssistant.GROUP_HP_BARS)
	_parent_unit = unit
	_health_component = health_comp
	_status_icons = {}

	_health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(_health_component.health)
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
		
	if unit.has_meta(ID.UnitMeta.IS_IMPORTANT) and unit.get_meta(ID.UnitMeta.IS_IMPORTANT):
		_is_important = true
	UI.update_inspector_bar.connect(_on_global_selection_changed)
	_evaluate_visibility()
	
func _evaluate_visibility() -> void: ## visibility state machine
	var is_alive = value > 0
	var is_damaged = value < max_value
	var has_intent = _is_hovered or _is_selected or (_is_important and is_damaged)
	
	# bar (and all child status icons) are only visible if intended and alive
	visible = has_intent

func _process(_delta):
	if is_instance_valid(_parent_unit) and visible:
		rotation = -_parent_unit.rotation #counter rotate
		
func _on_health_changed(new_health: float) -> void:
	value = new_health
	max_value = _health_component.max_health # Update max in case of buffs
	_evaluate_visibility()
	## Visibility Logic:
	## Show if damaged (health < max) AND alive (health > 0)
	#var is_damaged = new_health < max_value
	#var is_alive = new_health > 0
	#
	#visible = is_damaged and is_alive
	
func _on_status_changed(status: Attributes.Status, stacks: float, duration: float):
	if DebugAssistant.disable_status_icons:
		if _status_icons.has(status):
			var icon_to_remove: UnitStatusIcon = _status_icons[status]
			_status_icons.erase(status)
			icon_to_remove.free()
			_reposition_icons()
		return

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
			add_child.call_deferred(_status_icons[status])
			_status_icons[status].ready.connect(func():
				_status_icons[status].setup(status)
				_status_icons[status].update_data(stacks, duration)
				_reposition_icons()
				CONNECT_ONE_SHOT
			)
			return

		_status_icons[status].update_data(stacks, duration)
		_reposition_icons()
		
# hitbox interaction handlers (see unit._attach_health_bar)
func on_mouse_entered() -> void:
	_is_hovered = true
	_evaluate_visibility()

func on_mouse_exited() -> void:
	_is_hovered = false
	_evaluate_visibility()

func _on_global_selection_changed(selected_unit: Unit) -> void:
	# Toggle selection state based on if we are the chosen one
	_is_selected = (selected_unit == _parent_unit)
	_evaluate_visibility()
	
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
