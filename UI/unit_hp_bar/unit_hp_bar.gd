extends Control
class_name UnitHPBar

const HEALTH_BAR_SCALE: Vector2 = Vector2(0.1, 0.1)
const ROW_GAP: float = 0.25
const COLUMN_GAP: float = 0.25
const VERTICAL_OFFSET: Vector2 = Vector2(0, -7)
const STATUS_ICON_SCENE: PackedScene = preload("res://UI/unit_hp_bar/status_icon.tscn")

var _health_component: HealthComponent
var _parent_unit: Unit
@onready var _health_progress: TextureProgressBar = $TextureProgressBar as TextureProgressBar
var _health_value: float = 0.0
var _max_health_value: float = 1.0

var _status_icons: Dictionary[Attributes.Status, UnitStatusIcon] = {}
var _effect_icons: Dictionary[int, UnitStatusIcon] = {}
var _pending_status_icon_data: Dictionary[Attributes.Status, Vector2] = {}
var _pending_effect_icon_data: Dictionary[int, Vector2] = {}
var _effect_icon_refs: Dictionary[int, WeakRef] = {}
var _pooled_icons: Array[UnitStatusIcon] = []

var _icons_visible: bool = false
var _icons_dirty: bool = false

func setup(unit: Unit, health_comp: HealthComponent, show_icons: bool) -> void: ##binds this pooled presentation to one unit model and reconstructs only currently requested visuals
	add_to_group(DebugAssistant.GROUP_HP_BARS)
	_unbind_model()
	_parent_unit = unit
	_health_component = health_comp
	visible = not DebugAssistant.disable_hp_bars
	set_process(false)
	_clear_status_icons()
	_clear_effect_icons()
	_status_icons = {}
	_effect_icons = {}
	_pending_status_icon_data.clear()
	_pending_effect_icon_data.clear()
	_effect_icon_refs.clear()
	_icons_dirty = false
	_icons_visible = false

	if not _health_component.health_changed.is_connected(_on_health_changed):
		_health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(_health_component.health)

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

	set_icons_visible(show_icons)
	sync_world_position()

func release_for_pool() -> void: ##disconnects the current model and returns this presentation to an inert reusable state
	_unbind_model()
	_dematerialize_icons()
	_pending_status_icon_data.clear()
	_pending_effect_icon_data.clear()
	_effect_icon_refs.clear()
	_icons_dirty = false
	_icons_visible = false
	_health_value = 0.0
	_max_health_value = 1.0
	visible = false
	set_process(false)

func _exit_tree() -> void:
	_unbind_model()
	_free_all_icons()

func _unbind_model() -> void: ##removes signal ownership from the previously presented unit before this bar is rebound or pooled

	if is_instance_valid(_health_component) and _health_component.health_changed.is_connected(_on_health_changed):
		_health_component.health_changed.disconnect(_on_health_changed)

	if is_instance_valid(_parent_unit) and is_instance_valid(_parent_unit.modifiers_component):
		var modifiers_component: ModifiersComponent = _parent_unit.modifiers_component
		if modifiers_component.status_changed.is_connected(_on_status_changed):
			modifiers_component.status_changed.disconnect(_on_status_changed)

	if is_instance_valid(_parent_unit):
		if _parent_unit.effect_display_changed.is_connected(_on_effect_display_changed):
			_parent_unit.effect_display_changed.disconnect(_on_effect_display_changed)
		if _parent_unit.effect_display_removed.is_connected(_on_effect_display_removed):
			_parent_unit.effect_display_removed.disconnect(_on_effect_display_removed)

	if Pause.attached_effect_icons_changed.is_connected(_on_attached_effect_icons_changed):
		Pause.attached_effect_icons_changed.disconnect(_on_attached_effect_icons_changed)

	_health_component = null
	_parent_unit = null

func set_icons_visible(should_show: bool) -> void: ##materializes detailed status ui only when the manager marks the bound unit as inspectable or important
	should_show = should_show and not DebugAssistant.disable_status_icons and is_instance_valid(_parent_unit)
	if _icons_visible == should_show:
		return

	_icons_visible = should_show
	if _icons_visible:
		_refresh_icons_from_model()
		_flush_pending_icon_changes()
	else:
		_dematerialize_icons()

func apply_debug_visibility_flags() -> void: ##reapplies hp-bar and icon visibility after debug flags change during an active run
	visible = is_instance_valid(_parent_unit) and not DebugAssistant.disable_hp_bars
	if DebugAssistant.disable_status_icons:
		set_icons_visible(false)

func sync_world_position() -> void: ##places this manager-owned control at its bound unit without inheriting unit rotation or scene subtrees
	if not is_instance_valid(_parent_unit):
		return
	global_position = _parent_unit.global_position
	rotation = 0.0

func _process(_delta: float) -> void: ##flushes one queued icon batch, then sleeps until another model change requests work
	if _icons_visible and _icons_dirty:
		_flush_pending_icon_changes()
	set_process(false)

func _on_health_changed(new_health: float) -> void:
	if not is_instance_valid(_health_component):
		return
	_health_value = new_health
	_max_health_value = _health_component.max_health
	if is_instance_valid(_health_progress):
		_health_progress.max_value = _health_component.max_health
		_health_progress.value = new_health

func _on_status_changed(status: Attributes.Status, stacks: float, duration: float) -> void:
	if DebugAssistant.disable_status_icons:
		_pending_status_icon_data[status] = Vector2.ZERO
		_queue_icon_flush()
		return

	_pending_status_icon_data[status] = Vector2(stacks, duration)
	_queue_icon_flush()

func _create_status_icon(status: Attributes.Status) -> UnitStatusIcon:
	var icon: UnitStatusIcon = _acquire_icon()
	if not is_instance_valid(icon):
		return null

	_status_icons[status] = icon
	icon.setup(status)
	icon.set_process(_icons_visible)
	return icon

func _remove_status_icon(status: Attributes.Status) -> void:
	if not _status_icons.has(status):
		return

	var icon_to_remove: UnitStatusIcon = _status_icons[status]
	_status_icons.erase(status)
	if is_instance_valid(icon_to_remove):
		_pool_icon(icon_to_remove)

func _clear_status_icons() -> void:
	for icon: UnitStatusIcon in _status_icons.values():
		if is_instance_valid(icon):
			_pool_icon(icon)
	_status_icons.clear()

func _on_effect_display_changed(effect_instance: EffectInstance, stacks: float, duration: float) -> void:
	if not is_instance_valid(effect_instance):
		return

	var effect_id: int = _track_effect_instance(effect_instance)
	if effect_id == 0:
		return

	if DebugAssistant.disable_status_icons or not Pause.show_attached_effect_icons:
		_pending_effect_icon_data[effect_id] = Vector2.ZERO
		_queue_icon_flush()
		return

	if not effect_instance.should_show_status_icon():
		_pending_effect_icon_data[effect_id] = Vector2.ZERO
		_queue_icon_flush()
		return

	_pending_effect_icon_data[effect_id] = Vector2(stacks, duration)
	_queue_icon_flush()

func _on_effect_display_removed(effect_instance: EffectInstance) -> void:
	if not is_instance_valid(effect_instance):
		return

	var effect_id: int = _track_effect_instance(effect_instance)
	if effect_id == 0:
		return

	_pending_effect_icon_data[effect_id] = Vector2.ZERO
	_queue_icon_flush()

func _create_effect_icon(effect_id: int, effect_instance: EffectInstance) -> UnitStatusIcon:
	var icon: UnitStatusIcon = _acquire_icon()
	if not is_instance_valid(icon):
		return null

	_effect_icons[effect_id] = icon
	icon.setup_effect(effect_instance)
	icon.set_process(_icons_visible)
	return icon

func _remove_effect_icon(effect_id: int) -> void:
	_effect_icon_refs.erase(effect_id)
	if not _effect_icons.has(effect_id):
		return

	var icon_to_remove: UnitStatusIcon = _effect_icons[effect_id]
	_effect_icons.erase(effect_id)
	if is_instance_valid(icon_to_remove):
		_pool_icon(icon_to_remove)

func _clear_effect_icons() -> void:
	for icon: UnitStatusIcon in _effect_icons.values():
		if is_instance_valid(icon):
			_pool_icon(icon)
	_effect_icons.clear()

func _queue_icon_flush() -> void:
	_icons_dirty = true
	if _icons_visible:
		set_process(true)

func _flush_pending_icon_changes() -> void:
	if not _icons_visible:
		return

	_icons_dirty = false
	var layout_dirty: bool = false

	var status_changes := _pending_status_icon_data.duplicate()
	_pending_status_icon_data.clear()
	for status: Attributes.Status in status_changes:
		var status_payload: Vector2 = status_changes[status]
		if DebugAssistant.disable_status_icons or status_payload.x <= 0.0:
			layout_dirty = _status_icons.has(status) or layout_dirty
			_remove_status_icon(status)
			continue

		var status_icon: UnitStatusIcon = _status_icons.get(status, null)
		if not is_instance_valid(status_icon):
			_status_icons.erase(status)
			status_icon = _create_status_icon(status)
			layout_dirty = true

		if is_instance_valid(status_icon):
			status_icon.update_data(status_payload.x, status_payload.y)

	var effect_changes := _pending_effect_icon_data.duplicate()
	_pending_effect_icon_data.clear()
	for effect_id: int in effect_changes:
		var effect_payload: Vector2 = effect_changes[effect_id]
		var effect_instance: EffectInstance = _get_effect_instance(effect_id)
		if DebugAssistant.disable_status_icons or not Pause.show_attached_effect_icons or effect_payload.x <= 0.0:
			layout_dirty = _effect_icons.has(effect_id) or layout_dirty
			_remove_effect_icon(effect_id)
			continue
		if not is_instance_valid(effect_instance) or not effect_instance.should_show_status_icon():
			layout_dirty = _effect_icons.has(effect_id) or layout_dirty
			_remove_effect_icon(effect_id)
			continue

		var effect_icon: UnitStatusIcon = _effect_icons.get(effect_id, null)
		if not is_instance_valid(effect_icon):
			_effect_icons.erase(effect_id)
			effect_icon = _create_effect_icon(effect_id, effect_instance)
			layout_dirty = true

		if is_instance_valid(effect_icon):
			effect_icon.update_data(effect_payload.x, effect_payload.y)

	if layout_dirty:
		_reposition_icons()
	_sync_active_icon_processing()

func _refresh_icons_from_model() -> void:
	if not _icons_visible:
		_pending_status_icon_data.clear()
		_pending_effect_icon_data.clear()
		_clear_status_icons()
		_clear_effect_icons()
		_reposition_icons()
		return

	if DebugAssistant.disable_status_icons:
		_pending_status_icon_data.clear()
		_pending_effect_icon_data.clear()
		_clear_status_icons()
		_clear_effect_icons()
		_reposition_icons()
		return

	var parent_unit: Unit = _parent_unit as Unit
	if not is_instance_valid(parent_unit):
		return

	var active_statuses: Dictionary[Attributes.Status, bool] = {}
	if is_instance_valid(parent_unit.modifiers_component):
		for status: StatusEffect in parent_unit.modifiers_component.get_active_statuses():
			if not is_instance_valid(status):
				continue
			active_statuses[status.type] = true
			_pending_status_icon_data[status.type] = Vector2(status.stack, _get_status_display_duration(status))

	for status: Attributes.Status in _status_icons:
		if active_statuses.has(status):
			continue
		_pending_status_icon_data[status] = Vector2.ZERO

	if Pause.show_attached_effect_icons:
		parent_unit.refresh_effect_displays()
	else:
		for effect_id: int in _effect_icons:
			_pending_effect_icon_data[effect_id] = Vector2.ZERO

	_queue_icon_flush()

func _get_status_display_duration(status: StatusEffect) -> float:
	if is_instance_valid(status.timer) and status.timer.is_active:
		return maxf(status.timer.duration - status.timer.time_elapsed, 0.0)
	return status.cooldown

func _track_effect_instance(effect_instance: EffectInstance) -> int:
	if not is_instance_valid(effect_instance):
		return 0

	var effect_id: int = effect_instance.get_instance_id()
	_effect_icon_refs[effect_id] = weakref(effect_instance)
	return effect_id

func _get_effect_instance(effect_id: int) -> EffectInstance:
	if not _effect_icon_refs.has(effect_id):
		return null

	var effect_ref: WeakRef = _effect_icon_refs[effect_id]
	if not is_instance_valid(effect_ref):
		_effect_icon_refs.erase(effect_id)
		return null

	var effect_instance: EffectInstance = effect_ref.get_ref() as EffectInstance
	if not is_instance_valid(effect_instance):
		_effect_icon_refs.erase(effect_id)
		return null

	return effect_instance

func _dematerialize_icons() -> void:
	if _status_icons.is_empty() and _effect_icons.is_empty():
		return

	_clear_status_icons()
	_clear_effect_icons()
	_reposition_icons()

func _acquire_icon() -> UnitStatusIcon:
	while not _pooled_icons.is_empty():
		var pooled_icon: UnitStatusIcon = _pooled_icons.pop_back()
		if is_instance_valid(pooled_icon):
			pooled_icon.visible = true
			return pooled_icon

	var icon: UnitStatusIcon = STATUS_ICON_SCENE.instantiate() as UnitStatusIcon
	if is_instance_valid(icon):
		add_child(icon)
	return icon

func _pool_icon(icon: UnitStatusIcon) -> void:
	if not is_instance_valid(icon):
		return
	if _pooled_icons.has(icon):
		return

	icon.prepare_for_pool()
	_pooled_icons.append(icon)

func _sync_active_icon_processing() -> void:
	for icon: UnitStatusIcon in _status_icons.values():
		if is_instance_valid(icon):
			icon.visible = _icons_visible
			icon.set_process(_icons_visible)
	for icon: UnitStatusIcon in _effect_icons.values():
		if is_instance_valid(icon):
			icon.visible = _icons_visible
			icon.set_process(_icons_visible)

func _free_all_icons() -> void:
	for icon: UnitStatusIcon in _status_icons.values():
		if is_instance_valid(icon):
			icon.queue_free()
	for icon: UnitStatusIcon in _effect_icons.values():
		if is_instance_valid(icon):
			icon.queue_free()
	for icon: UnitStatusIcon in _pooled_icons:
		if is_instance_valid(icon):
			icon.queue_free()

	_status_icons.clear()
	_effect_icons.clear()
	_pooled_icons.clear()
	_pending_status_icon_data.clear()
	_pending_effect_icon_data.clear()
	_effect_icon_refs.clear()

func _on_attached_effect_icons_changed(is_enabled: bool) -> void:
	if not is_enabled:
		_pending_effect_icon_data.clear()
		_clear_effect_icons()
		_reposition_icons()
		return

	if not is_instance_valid(_parent_unit) or not _icons_visible:
		return

	_parent_unit.refresh_effect_displays()
	_queue_icon_flush()

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

	var health_origin: Vector2 = VERTICAL_OFFSET - health_size * 0.5
	if is_instance_valid(_health_progress):
		_health_progress.position = health_origin

	var accumulated_width: float = health_origin.x + (health_size.x - icon_row_width) * 0.5
	var icon_y: float = health_origin.y - icon_row_height - COLUMN_GAP
	for icon: Control in active_icons:
		var icon_size: Vector2 = _get_control_visual_size(icon)
		icon.position = Vector2(accumulated_width, icon_y + (icon_row_height - icon_size.y) * 0.5)
		accumulated_width += icon_size.x + ROW_GAP

func _get_control_visual_size(control: Control) -> Vector2:
	if not is_instance_valid(control):
		return Vector2.ZERO
	return control.size * control.scale
