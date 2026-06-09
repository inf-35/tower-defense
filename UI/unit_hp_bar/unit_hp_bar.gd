extends ProgressBar
class_name UnitHPBar

var bar_size: Vector2 = Vector2(5, 1.2)

var _health_component: HealthComponent
var _parent_unit: Node2D

var _status_icons: Dictionary[Attributes.Status, UnitStatusIcon] = {}

var _is_hovered: bool = false
var _is_selected: bool = false
var _is_important: bool = false

const VERTICAL_OFFSET: Vector2 = Vector2(0,-5)
const STATUS_ICON_SCENE: PackedScene = preload("res://UI/unit_hp_bar/status_icon.tscn")

func setup(unit: Unit, health_comp: HealthComponent) -> void:
	add_to_group(DebugAssistant.GROUP_HP_BARS)
	_parent_unit = unit
	_health_component = health_comp
	_clear_status_icons()
	_status_icons = {}

	if not _health_component.health_changed.is_connected(_on_health_changed):
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
		if not unit.modifiers_component.status_changed.is_connected(_on_status_changed):
			unit.modifiers_component.status_changed.connect(_on_status_changed)

	if unit.has_meta(ID.UnitMeta.IS_IMPORTANT) and unit.get_meta(ID.UnitMeta.IS_IMPORTANT):
		_is_important = true
	if not UI.update_inspector_bar.is_connected(_on_global_selection_changed):
		UI.update_inspector_bar.connect(_on_global_selection_changed)
	_evaluate_visibility()

func _exit_tree() -> void:
	_clear_status_icons()

	if is_instance_valid(_health_component) and _health_component.health_changed.is_connected(_on_health_changed):
		_health_component.health_changed.disconnect(_on_health_changed)

	if is_instance_valid(_parent_unit) and is_instance_valid(_parent_unit.modifiers_component):
		var modifiers_component: ModifiersComponent = _parent_unit.modifiers_component
		if modifiers_component.status_changed.is_connected(_on_status_changed):
			modifiers_component.status_changed.disconnect(_on_status_changed)

	if UI.update_inspector_bar.is_connected(_on_global_selection_changed):
		UI.update_inspector_bar.disconnect(_on_global_selection_changed)

func _evaluate_visibility() -> void:
	var is_damaged = value < max_value
	var has_intent = _is_hovered or _is_selected or (_is_important and is_damaged)

	visible = has_intent

func _process(_delta: float) -> void:
	if is_instance_valid(_parent_unit) and visible:
		rotation = -_parent_unit.rotation

func _on_health_changed(new_health: float) -> void:
	value = new_health
	max_value = _health_component.max_health
	_evaluate_visibility()

func _on_status_changed(status: Attributes.Status, stacks: float, duration: float) -> void:
	if DebugAssistant.disable_status_icons:
		_remove_status_icon(status)
		return

	if stacks <= 0.0:
		_remove_status_icon(status)
		return

	var icon: UnitStatusIcon = _status_icons.get(status, null)
	if not is_instance_valid(icon):
		_status_icons.erase(status)
		icon = _create_status_icon(status)

	if not is_instance_valid(icon):
		return

	icon.update_data(stacks, duration)
	_reposition_icons()

func _create_status_icon(status: Attributes.Status) -> UnitStatusIcon:
	var icon: UnitStatusIcon = STATUS_ICON_SCENE.instantiate() as UnitStatusIcon
	if not is_instance_valid(icon):
		return null

	_status_icons[status] = icon
	add_child(icon)
	icon.setup(status)
	return icon

func _remove_status_icon(status: Attributes.Status) -> void:
	if not _status_icons.has(status):
		return

	var icon_to_remove: UnitStatusIcon = _status_icons[status]
	_status_icons.erase(status)
	if is_instance_valid(icon_to_remove):
		icon_to_remove.queue_free()
		_reposition_icons()

func _clear_status_icons() -> void:
	for icon: UnitStatusIcon in _status_icons.values():
		if is_instance_valid(icon):
			icon.queue_free()
	_status_icons.clear()

func on_mouse_entered() -> void:
	_is_hovered = true
	_evaluate_visibility()

func on_mouse_exited() -> void:
	_is_hovered = false
	_evaluate_visibility()

func _on_global_selection_changed(selected_unit) -> void:
	_is_selected = (selected_unit == _parent_unit)
	_evaluate_visibility()

func _reposition_icons() -> void:
	var active_icons: Array[UnitStatusIcon] = _status_icons.values()

	var total_width: float = 0.0
	for icon: Control in active_icons:
		var w: float = icon.size.x * icon.scale.x
		total_width += w

	var accumulated_width: float = 0.0
	for icon: Control in active_icons:
		var w: float = icon.size.x * icon.scale.x
		icon.position = VERTICAL_OFFSET
		icon.position.x = 0.0 - total_width * 0.5 + w * 0.5 + accumulated_width
		accumulated_width += w
