extends Control
class_name UnitHPBar

const HEALTH_BAR_SCALE: Vector2 = Vector2(0.15, 0.15)
const ROW_GAP: float = 0.25
const COLUMN_GAP: float = 0.25
const AUTO_IMPORTANT_UNIT_THRESHOLD: int = 30
const VISIBILITY_REFRESH_INTERVAL_FRAMES: int = 10
const VERTICAL_OFFSET: Vector2 = Vector2(0, -5)
const STATUS_ICON_SCENE: PackedScene = preload("res://UI/unit_hp_bar/status_icon.tscn")

var _health_component: HealthComponent
var _parent_unit: Node2D
@onready var _health_progress: TextureProgressBar = $TextureProgressBar as TextureProgressBar
var _health_value: float = 0.0
var _max_health_value: float = 1.0

var _status_icons: Dictionary[Attributes.Status, UnitStatusIcon] = {}
var _effect_icons: Dictionary[EffectInstance, UnitStatusIcon] = {}

var _is_hovered: bool = false
var _is_selected: bool = false
var _is_important: bool = false
var _visibility_refresh_frames: int = 0

static var _cached_screen_unit_count_frame: int = -1
static var _cached_screen_unit_count: int = 0

func setup(unit: Unit, health_comp: HealthComponent) -> void:
	add_to_group(DebugAssistant.GROUP_HP_BARS)
	_parent_unit = unit
	_health_component = health_comp
	_clear_status_icons()
	_clear_effect_icons()
	_status_icons = {}
	_effect_icons = {}

	if not _health_component.health_changed.is_connected(_on_health_changed):
		_health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(_health_component.health)
	visible = false

	size = Vector2.ZERO
	if is_instance_valid(_health_progress):
		_health_progress.scale = HEALTH_BAR_SCALE
		_health_progress.position = Vector2.ZERO
		_health_progress.step = 0.01
	_reposition_icons()

	if unit.modifiers_component:
		if not unit.modifiers_component.status_changed.is_connected(_on_status_changed):
			unit.modifiers_component.status_changed.connect(_on_status_changed)

	if not unit.effect_display_changed.is_connected(_on_effect_display_changed):
		unit.effect_display_changed.connect(_on_effect_display_changed)
	if not unit.effect_display_removed.is_connected(_on_effect_display_removed):
		unit.effect_display_removed.connect(_on_effect_display_removed)
	if not Pause.attached_effect_icons_changed.is_connected(_on_attached_effect_icons_changed):
		Pause.attached_effect_icons_changed.connect(_on_attached_effect_icons_changed)
	if Pause.show_attached_effect_icons:
		unit.refresh_effect_displays()

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

	if is_instance_valid(_parent_unit):
		var parent_unit: Unit = _parent_unit as Unit
		if parent_unit.effect_display_changed.is_connected(_on_effect_display_changed):
			parent_unit.effect_display_changed.disconnect(_on_effect_display_changed)
		if parent_unit.effect_display_removed.is_connected(_on_effect_display_removed):
			parent_unit.effect_display_removed.disconnect(_on_effect_display_removed)

	if Pause.attached_effect_icons_changed.is_connected(_on_attached_effect_icons_changed):
		Pause.attached_effect_icons_changed.disconnect(_on_attached_effect_icons_changed)

	if UI.update_inspector_bar.is_connected(_on_global_selection_changed):
		UI.update_inspector_bar.disconnect(_on_global_selection_changed)

func _evaluate_visibility() -> void:
	var is_damaged: bool = _health_value < _max_health_value
	var has_intent: bool = _is_hovered or _is_selected or ((_is_important or _is_conditionally_important()) and is_damaged)

	visible = has_intent

func _process(_delta: float) -> void:
	if is_instance_valid(_parent_unit) and visible:
		rotation = -_parent_unit.rotation

	_visibility_refresh_frames += 1
	if _visibility_refresh_frames < VISIBILITY_REFRESH_INTERVAL_FRAMES:
		return

	_visibility_refresh_frames = 0
	if _health_value < _max_health_value:
		_evaluate_visibility()

func _on_health_changed(new_health: float) -> void:
	_health_value = new_health
	_max_health_value = _health_component.max_health
	if is_instance_valid(_health_progress):
		_health_progress.max_value = _health_component.max_health
		_health_progress.value = new_health
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

func _on_effect_display_changed(effect_instance: EffectInstance, stacks: float, duration: float) -> void:
	if DebugAssistant.disable_status_icons or not Pause.show_attached_effect_icons:
		_remove_effect_icon(effect_instance)
		return

	if not is_instance_valid(effect_instance) or not effect_instance.should_show_status_icon():
		_remove_effect_icon(effect_instance)
		return

	if stacks <= 0.0:
		_remove_effect_icon(effect_instance)
		return

	var icon: UnitStatusIcon = _effect_icons.get(effect_instance, null)
	if not is_instance_valid(icon):
		_effect_icons.erase(effect_instance)
		icon = _create_effect_icon(effect_instance)

	if not is_instance_valid(icon):
		return

	icon.update_data(stacks, duration)
	_reposition_icons()

func _on_effect_display_removed(effect_instance: EffectInstance) -> void:
	_remove_effect_icon(effect_instance)

func _create_effect_icon(effect_instance: EffectInstance) -> UnitStatusIcon:
	var icon: UnitStatusIcon = STATUS_ICON_SCENE.instantiate() as UnitStatusIcon
	if not is_instance_valid(icon):
		return null

	_effect_icons[effect_instance] = icon
	add_child(icon)
	icon.setup_effect(effect_instance)
	return icon

func _remove_effect_icon(effect_instance: EffectInstance) -> void:
	if not _effect_icons.has(effect_instance):
		return

	var icon_to_remove: UnitStatusIcon = _effect_icons[effect_instance]
	_effect_icons.erase(effect_instance)
	if is_instance_valid(icon_to_remove):
		icon_to_remove.queue_free()
		_reposition_icons()

func _clear_effect_icons() -> void:
	for icon: UnitStatusIcon in _effect_icons.values():
		if is_instance_valid(icon):
			icon.queue_free()
	_effect_icons.clear()

func _on_attached_effect_icons_changed(is_enabled: bool) -> void:
	if not is_enabled:
		_clear_effect_icons()
		return

	if not is_instance_valid(_parent_unit):
		return

	var parent_unit: Unit = _parent_unit as Unit
	parent_unit.refresh_effect_displays()

func on_mouse_entered() -> void:
	_is_hovered = true
	_evaluate_visibility()

func on_mouse_exited() -> void:
	_is_hovered = false
	_evaluate_visibility()

func _on_global_selection_changed(selected_unit) -> void:
	_is_selected = (selected_unit == _parent_unit)
	_evaluate_visibility()

func _is_conditionally_important() -> bool: ##applies the low-population and settings-driven hp bar visibility rules for otherwise unimportant units
	if Pause.show_all_health_bars:
		return true

	return _get_cached_screen_unit_count() < AUTO_IMPORTANT_UNIT_THRESHOLD

static func _get_cached_screen_unit_count() -> int: ##counts real units in the current camera view once per frame so hp bar visibility checks stay cheap
	var current_frame: int = Engine.get_process_frames()
	if _cached_screen_unit_count_frame == current_frame:
		return _cached_screen_unit_count

	_cached_screen_unit_count_frame = current_frame
	_cached_screen_unit_count = _count_screen_units()
	return _cached_screen_unit_count

static func _count_screen_units() -> int:
	if not is_instance_valid(Run.references):
		return 0
	if not is_instance_valid(Run.references.camera):
		return 0

	var camera: Camera = Run.references.camera
	var viewport_size: Vector2 = camera.get_viewport_rect().size / camera.zoom
	var view_rect := Rect2(camera.position - viewport_size * 0.5, viewport_size)
	var unit_count: int = 0
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not is_instance_valid(scene_tree):
		return 0

	for unit_node: Node in scene_tree.get_nodes_in_group(DebugAssistant.GROUP_UNITS):
		var unit: Unit = unit_node as Unit
		if not is_instance_valid(unit):
			continue
		if unit.abstractive or unit.disabled:
			continue
		if not view_rect.has_point(unit.global_position):
			continue

		unit_count += 1

	return unit_count

func _reposition_icons() -> void:
	var active_icons: Array[UnitStatusIcon]
	active_icons.assign(_status_icons.values())
	var effect_icon_values: Array[UnitStatusIcon]
	effect_icon_values.assign(_effect_icons.values())
	active_icons.append_array(effect_icon_values)

	var health_size: Vector2 = _get_control_visual_size(_health_progress)
	var icon_row_width: float = 0.0
	var icon_row_height: float = 0.0
	for icon: Control in active_icons:
		var icon_size: Vector2 = _get_control_visual_size(icon)
		icon_row_height = maxf(icon_row_height, icon_size.y)
		if icon_row_width > 0.0:
			icon_row_width += ROW_GAP
		icon_row_width += icon_size.x

	var total_width: float = maxf(health_size.x, icon_row_width)
	var total_height: float = health_size.y
	if not active_icons.is_empty():
		total_height += icon_row_height + COLUMN_GAP

	position = VERTICAL_OFFSET - Vector2(total_width, total_height) * 0.5
	if is_instance_valid(_health_progress):
		var health_y: float = 0.0
		if not active_icons.is_empty():
			health_y = icon_row_height + COLUMN_GAP
		_health_progress.position = Vector2((total_width - health_size.x) * 0.5, health_y)

	var accumulated_width: float = (total_width - icon_row_width) * 0.5
	for icon: Control in active_icons:
		var icon_size: Vector2 = _get_control_visual_size(icon)
		icon.position = Vector2(accumulated_width, (icon_row_height - icon_size.y) * 0.5)
		accumulated_width += icon_size.x + ROW_GAP

func _get_control_visual_size(control: Control) -> Vector2:
	if not is_instance_valid(control):
		return Vector2.ZERO
	return control.size * control.scale
