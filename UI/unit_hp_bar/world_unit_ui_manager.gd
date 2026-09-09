extends Node2D
class_name WorldUnitUIManager

const AUTO_IMPORTANT_UNIT_THRESHOLD: int = 30
const VISIBILITY_REFRESH_INTERVAL_FRAMES: int = 10

@export var health_bar_scene: PackedScene ##pooled world-space health-bar presentation instantiated only for visible qualifying units
@export_range(0, 128, 1) var initial_pool_size: int = 12 ##bars prepared when the island starts so ordinary combat does not allocate them on first damage
@export_range(0, 256, 1) var max_retained_pool_size: int = 32 ##inactive bars retained after demand falls; excess high-water allocations are freed
@export var culling_margin: float = 10.0 ##world-space margin around the camera view that prevents bars flickering at the viewport edge

var _registered_units: Dictionary[int, WeakRef] = {}
var _active_bars: Dictionary[int, UnitHPBar] = {}
var _available_bars: Array[UnitHPBar] = []
var _hovered_unit_ids: Dictionary[int, bool] = {}
var _pending_refresh_unit_ids: Dictionary[int, bool] = {}
var _selected_unit_id: int = -1
var _visibility_refresh_frames: int = 0
var _view_rect: Rect2 = Rect2()
var _screen_unit_count: int = 0
var _has_visibility_snapshot: bool = false

func _ready() -> void: ##registers the island-owned presenter and prepares a small reusable bar pool
	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.world_unit_ui_manager = self
	if not UI.update_inspector_bar.is_connected(_on_selected_unit_changed):
		UI.update_inspector_bar.connect(_on_selected_unit_changed)

	for _index: int in initial_pool_size:
		var bar: UnitHPBar = _create_bar()
		if is_instance_valid(bar):
			_available_bars.append(bar)

func _exit_tree() -> void: ##clears the shared presentation reference when this run-owned manager leaves the tree
	if UI.world_unit_ui_manager == self:
		UI.world_unit_ui_manager = null

func _process(_delta: float) -> void: ##moves only materialized bars each frame and periodically reevaluates camera-dependent eligibility
	_flush_pending_unit_refreshes()
	_sync_active_bar_positions()
	_visibility_refresh_frames += 1
	if _visibility_refresh_frames < VISIBILITY_REFRESH_INTERVAL_FRAMES:
		return

	_visibility_refresh_frames = 0
	_refresh_all_units()

func register_unit(unit: Unit) -> void: ##tracks one real health-bearing unit without creating presentation until it qualifies
	if not _can_register_unit(unit):
		return

	var unit_instance_id: int = unit.get_instance_id()
	if _registered_units.has(unit_instance_id):
		return

	_registered_units[unit_instance_id] = weakref(unit)
	unit.health_component.health_changed.connect(_on_unit_health_changed.bind(unit_instance_id))
	unit.tree_exiting.connect(_on_unit_tree_exiting.bind(unit_instance_id), CONNECT_ONE_SHOT)
	_configure_unit_hover(unit, unit_instance_id)

	if not _has_visibility_snapshot:
		_refresh_visibility_snapshot()
	_refresh_unit(unit)

func apply_debug_visibility_flags() -> void: ##releases all bars for the no-hp-bars benchmark and rematerializes eligible bars when it is lifted
	if DebugAssistant.disable_hp_bars:
		for unit_instance_id: int in _active_bars.keys():
			_release_bar(unit_instance_id)
		return

	_refresh_all_units()

func get_registered_unit_count() -> int: ##reports model registrations separately from presentation nodes for performance diagnostics
	return _registered_units.size()

func get_active_bar_count() -> int: ##reports how many units currently materialize world-space ui
	return _active_bars.size()

func get_pooled_bar_count() -> int: ##reports retained inactive presentations available for reuse
	return _available_bars.size()

func _can_register_unit(unit: Unit) -> bool: ##rejects prototypes, bosses, and units without the model data needed by the shared presenter
	if not is_instance_valid(unit) or unit.abstractive or unit.disabled:
		return false
	if unit.has_meta(ID.UnitMeta.IS_BOSS):
		return false
	return is_instance_valid(unit.health_component)

func _configure_unit_hover(unit: Unit, unit_instance_id: int) -> void: ##preserves the existing hitbox-hover interaction while routing it through one manager
	if not is_instance_valid(unit.hitbox):
		return

	unit.hitbox.visible = true
	unit.hitbox.process_mode = Node.PROCESS_MODE_ALWAYS
	unit.hitbox.input_pickable = true
	unit.hitbox.mouse_entered.connect(_on_unit_mouse_entered.bind(unit_instance_id))
	unit.hitbox.mouse_exited.connect(_on_unit_mouse_exited.bind(unit_instance_id))

func _refresh_all_units() -> void: ##rebuilds the shared camera snapshot once, then applies it to every registered model
	_refresh_visibility_snapshot()
	var stale_unit_ids: Array[int] = []
	for unit_instance_id: int in _registered_units.keys():
		var unit: Unit = _get_unit(unit_instance_id)
		if not is_instance_valid(unit):
			stale_unit_ids.append(unit_instance_id)
			continue
		_refresh_unit(unit)

	for unit_instance_id: int in stale_unit_ids:
		_unregister_unit(unit_instance_id)

func _refresh_visibility_snapshot() -> void: ##calculates one camera rectangle and on-screen population count for the whole refresh pass
	_has_visibility_snapshot = false
	_screen_unit_count = 0
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.camera):
		return

	var camera: Camera = Run.references.camera
	var viewport_size: Vector2 = camera.get_viewport_rect().size / camera.zoom
	_view_rect = Rect2(camera.position - viewport_size * 0.5, viewport_size).grow(culling_margin)
	_has_visibility_snapshot = true

	for unit_instance_id: int in _registered_units.keys():
		var unit: Unit = _get_unit(unit_instance_id)
		if not _is_live_unit_on_screen(unit):
			continue
		_screen_unit_count += 1

func _refresh_unit(unit: Unit) -> void: ##materializes, updates, or releases one unit's bar according to current model and interaction state
	if not is_instance_valid(unit):
		return

	var unit_instance_id: int = unit.get_instance_id()
	if not _should_materialize_bar(unit, unit_instance_id):
		_release_bar(unit_instance_id)
		return

	var show_icons: bool = _should_materialize_icons(unit, unit_instance_id)
	var bar: UnitHPBar = _active_bars.get(unit_instance_id, null)
	if not is_instance_valid(bar):
		bar = _acquire_bar()
		if not is_instance_valid(bar):
			return
		_active_bars[unit_instance_id] = bar
		bar.setup(unit, unit.health_component, show_icons)
	else:
		bar.set_icons_visible(show_icons)
	bar.sync_world_position()

func _should_materialize_bar(unit: Unit, unit_instance_id: int) -> bool: ##matches the previous bar policy while omitting presentations outside the camera view
	if DebugAssistant.disable_hp_bars or not _is_live_unit_on_screen(unit):
		return false
	if _is_interacted_with(unit_instance_id):
		return true

	var is_damaged: bool = unit.health_component.health < unit.health_component.max_health
	if not is_damaged:
		return false
	if _is_important(unit) or Pause.show_all_health_bars:
		return true
	return _screen_unit_count < AUTO_IMPORTANT_UNIT_THRESHOLD

func _should_materialize_icons(unit: Unit, unit_instance_id: int) -> bool: ##keeps dense status displays limited to inspected, important, or explicitly requested units
	if DebugAssistant.disable_status_icons:
		return false
	return _is_interacted_with(unit_instance_id) or _is_important(unit) or Pause.show_all_health_bars

func _is_live_unit_on_screen(unit: Unit) -> bool: ##checks runtime and camera eligibility without touching combat state
	if not is_instance_valid(unit) or unit.abstractive or unit.disabled:
		return false
	if not is_instance_valid(unit.health_component) or not _has_visibility_snapshot:
		return false
	return _view_rect.has_point(unit.global_position)

func _is_interacted_with(unit_instance_id: int) -> bool: ##returns whether hover or inspector selection should force this unit's presentation
	return unit_instance_id == _selected_unit_id or _hovered_unit_ids.has(unit_instance_id)

func _is_important(unit: Unit) -> bool: ##reads the established unit metadata used by the previous per-unit bar policy
	return unit.has_meta(ID.UnitMeta.IS_IMPORTANT) and bool(unit.get_meta(ID.UnitMeta.IS_IMPORTANT))

func _sync_active_bar_positions() -> void: ##updates presentation transforms in one loop instead of one process callback per visible bar
	var stale_unit_ids: Array[int] = []
	for unit_instance_id: int in _active_bars.keys():
		var unit: Unit = _get_unit(unit_instance_id)
		var bar: UnitHPBar = _active_bars.get(unit_instance_id, null)
		if not is_instance_valid(unit) or not is_instance_valid(bar):
			stale_unit_ids.append(unit_instance_id)
			continue
		bar.sync_world_position()

	for unit_instance_id: int in stale_unit_ids:
		_unregister_unit(unit_instance_id)

func _flush_pending_unit_refreshes() -> void: ##coalesces health-driven eligibility changes until after model signals finish dispatching
	if _pending_refresh_unit_ids.is_empty():
		return

	var pending_unit_ids: Array[int] = []
	pending_unit_ids.assign(_pending_refresh_unit_ids.keys())
	_pending_refresh_unit_ids.clear()
	for unit_instance_id: int in pending_unit_ids:
		var unit: Unit = _get_unit(unit_instance_id)
		if is_instance_valid(unit):
			_refresh_unit(unit)

func _acquire_bar() -> UnitHPBar: ##reuses an inactive presentation before growing the pool to meet visible demand
	while not _available_bars.is_empty():
		var bar: UnitHPBar = _available_bars.pop_back()
		if is_instance_valid(bar):
			return bar
	return _create_bar()

func _create_bar() -> UnitHPBar: ##instantiates one presentation node through the inspector-authored scene
	if not is_instance_valid(health_bar_scene) or not health_bar_scene.can_instantiate():
		push_error("WorldUnitUIManager: health bar scene is missing or cannot be instantiated.")
		return null

	var bar: UnitHPBar = health_bar_scene.instantiate() as UnitHPBar
	if not is_instance_valid(bar):
		push_error("WorldUnitUIManager: health bar scene did not instantiate UnitHPBar.")
		return null

	add_child(bar)
	bar.release_for_pool()
	return bar

func _release_bar(unit_instance_id: int) -> void: ##unbinds a presentation and retains only the configured inactive high-water pool
	if not _active_bars.has(unit_instance_id):
		return

	var bar: UnitHPBar = _active_bars[unit_instance_id]
	_active_bars.erase(unit_instance_id)
	if not is_instance_valid(bar):
		return

	bar.release_for_pool()
	if _available_bars.size() < max_retained_pool_size:
		_available_bars.append(bar)
	else:
		bar.queue_free()

func _unregister_unit(unit_instance_id: int) -> void: ##drops one dead model and any temporary presentation or interaction state associated with it
	_release_bar(unit_instance_id)
	_registered_units.erase(unit_instance_id)
	_hovered_unit_ids.erase(unit_instance_id)
	_pending_refresh_unit_ids.erase(unit_instance_id)
	if _selected_unit_id == unit_instance_id:
		_selected_unit_id = -1

func _get_unit(unit_instance_id: int) -> Unit: ##resolves a weak registration without retaining units beyond their normal lifecycle
	var unit_ref: WeakRef = _registered_units.get(unit_instance_id, null)
	if not is_instance_valid(unit_ref):
		return null
	return unit_ref.get_ref() as Unit

func _on_unit_health_changed(_health: float, unit_instance_id: int) -> void: ##queues one eligibility refresh after the current health signal has finished dispatching
	_pending_refresh_unit_ids[unit_instance_id] = true

func _on_unit_tree_exiting(unit_instance_id: int) -> void: ##releases pooled ui before the model's component references become invalid
	_unregister_unit(unit_instance_id)

func _on_unit_mouse_entered(unit_instance_id: int) -> void: ##forces an on-screen hovered unit into the active presentation set
	_hovered_unit_ids[unit_instance_id] = true
	var unit: Unit = _get_unit(unit_instance_id)
	if is_instance_valid(unit):
		_refresh_unit(unit)

func _on_unit_mouse_exited(unit_instance_id: int) -> void: ##returns a no-longer-hovered unit to ordinary damage and importance eligibility
	_hovered_unit_ids.erase(unit_instance_id)
	var unit: Unit = _get_unit(unit_instance_id)
	if is_instance_valid(unit):
		_refresh_unit(unit)

func _on_selected_unit_changed(selected_unit: Unit) -> void: ##moves forced presentation from the previous inspector target to the newly selected unit
	var previous_unit_id: int = _selected_unit_id
	_selected_unit_id = selected_unit.get_instance_id() if is_instance_valid(selected_unit) else -1

	var previous_unit: Unit = _get_unit(previous_unit_id)
	if is_instance_valid(previous_unit):
		_refresh_unit(previous_unit)
	if is_instance_valid(selected_unit) and _registered_units.has(_selected_unit_id):
		_refresh_unit(selected_unit)
