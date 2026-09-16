extends Behavior
class_name CopperRiteBehavior

const INFLUENCE_KEY: StringName = &"copper_pair"

@export var buff_duration: float = 3.0 ##game-time duration of each copied-status attack window
@export var status_feedback_delay: float = 0.1 ##game-time spacing between copied-status feedback popups from one hit

var _connected_towers: Dictionary[Tower, bool] = {}
var _active_status_windows: Dictionary[int, Array] = {}

class StatusWindow extends RefCounted:
	var payload: Dictionary[Attributes.Status, Vector2] = {}

func start() -> void:
	var tower: Tower = unit as Tower
	tower.adjacency_updated.connect(_on_adjacency_updated)
	attach()

func attach() -> void:
	sync_tower_influences()
	_refresh_connections()

func detach() -> void:
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		_disconnect_tower(tower)

	_connected_towers.clear()
	_active_status_windows.clear()
	clear_tower_influences()

func _on_adjacency_updated(_adjacency_data: AdjacencyReportData) -> void:
	sync_tower_influences()
	_refresh_connections()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes copper's two world-vertical status-sharing endpoints
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return []
	var cells: Array[Vector2i] = [
		rite_tower.tower_position + Vector2i.UP,
		rite_tower.tower_position + Vector2i.DOWN,
	]
	return [TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.LINK,
		cells
	)]

func _refresh_connections() -> void:
	var current_set: Dictionary[Tower, bool] = {}
	for tower: Tower in _get_linked_towers():
		if not is_instance_valid(tower):
			continue

		current_set[tower] = true
		if _connected_towers.has(tower):
			continue

		tower.subscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_linked_tower_pre_hit)
		tower.subscribe_event(GameEvent.EventType.HIT_DEALT, _on_linked_tower_hit_dealt)
		_connected_towers[tower] = true
		if is_instance_valid(unit.buff_component):
			unit.buff_component.activate_new_link(tower)

	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		if current_set.has(tower):
			continue
		_disconnect_tower(tower)
		_connected_towers.erase(tower)
		_clear_status_windows_for_tower(tower)

func _on_linked_tower_pre_hit(event: GameEvent) -> void: ##adds live copied-status windows to a linked tower's routed primary attack
	_apply_active_status_windows(event.unit as Tower, event.data as HitData)

func _on_linked_tower_hit_dealt(event: GameEvent) -> void: ##copies statuses applied by one linked tower into a window on its counterpart
	_add_status_window_to_counterpart(event.unit as Tower, event.data as HitReportData)

func _apply_active_status_windows(source_tower: Tower, hit_data: HitData) -> void: ##merges every live copied-status window into each primary attack from the receiving tower
	if not is_instance_valid(source_tower) or not is_instance_valid(hit_data):
		return
	if not hit_data.primary or hit_data.negate:
		return

	var tower_id: int = source_tower.unit_id
	if not _active_status_windows.has(tower_id):
		return

	var windows: Array = _active_status_windows[tower_id]
	if windows.is_empty():
		return

	for window: StatusWindow in windows:
		_merge_status_payload_max_independent(hit_data.status_effects, window.payload)
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _add_status_window_to_counterpart(source_tower: Tower, report: HitReportData) -> void: ##stores statuses applied by one linked tower as a timed infusion window on the other linked tower
	if not is_instance_valid(source_tower) or report == null:
		return
	if report.source != source_tower or report.statuses_applied.is_empty():
		return

	var counterpart: Tower = _get_counterpart(source_tower)
	if not is_instance_valid(counterpart):
		return

	var window := StatusWindow.new()
	_merge_status_payload_max_independent(window.payload, report.statuses_applied)
	if window.payload.is_empty():
		return

	var tower_id: int = counterpart.unit_id
	if not _active_status_windows.has(tower_id):
		_active_status_windows[tower_id] = []
	_active_status_windows[tower_id].append(window)
	_expire_status_window_after_delay(tower_id, window)
	_show_status_feedback_sequence(counterpart, window.payload)
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _show_status_feedback_sequence(target: Tower, payload: Dictionary[Attributes.Status, Vector2]) -> void: ##plays one yellow copied-status popup per status so multi-status hits read as several grants
	if not is_instance_valid(target) or payload.is_empty():
		return
	if not is_instance_valid(unit.buff_component):
		return

	var first: bool = true
	for status: Attributes.Status in Attributes.Status.values():
		if not payload.has(status):
			continue

		if not first:
			await get_tree().create_timer(maxf(status_feedback_delay, 0.1)).timeout
		first = false
		if not is_instance_valid(target) or not is_instance_valid(unit.buff_component):
			return

		unit.buff_component.activate_target(target, "+%s" % _get_status_feedback_name(status))

func _get_status_feedback_name(status: Attributes.Status) -> String: ##formats copied status enum names for compact world feedback
	return String(Attributes.Status.keys()[status]).to_lower()

func _expire_status_window_after_delay(tower_id: int, window: StatusWindow) -> void: ##removes one copied-status window after the authored game-time duration
	await Clock.await_game_time(maxf(buff_duration, 0.0))
	_remove_status_window(tower_id, window)

func _remove_status_window(tower_id: int, window: StatusWindow) -> void: ##removes one tracked window without touching overlapping copied-status windows
	if not _active_status_windows.has(tower_id):
		return

	var windows: Array = _active_status_windows[tower_id]
	windows.erase(window)
	if not windows.is_empty():
		_active_status_windows[tower_id] = windows
		return

	_active_status_windows.erase(tower_id)

func _clear_status_windows_for_tower(tower: Tower) -> void: ##drops copied-status windows when a tower stops being affected by this copper rite
	if not is_instance_valid(tower):
		return

	_active_status_windows.erase(tower.unit_id)

func _merge_status_payload_max_independent(target_payload: Dictionary, incoming_payload: Dictionary) -> void:
	for status: Attributes.Status in incoming_payload:
		var incoming: Vector2 = incoming_payload[status]
		if incoming.x <= 0.0:
			continue

		var current: Vector2 = target_payload.get(status, Vector2.ZERO)
		current.x = maxf(current.x, incoming.x)
		current.y = maxf(current.y, incoming.y)
		target_payload[status] = current

func _get_linked_towers() -> Array[Tower]:
	var linked_towers: Array[Tower] = []
	var top_tower: Tower = _get_tower_at_global_offset(Vector2i.UP)
	var bottom_tower: Tower = _get_tower_at_global_offset(Vector2i.DOWN)
	if is_instance_valid(top_tower):
		linked_towers.append(top_tower)
	if is_instance_valid(bottom_tower) and bottom_tower != top_tower:
		linked_towers.append(bottom_tower)
	return linked_towers

func _get_counterpart(source_tower: Tower) -> Tower:
	var top_tower: Tower = _get_tower_at_global_offset(Vector2i.UP)
	var bottom_tower: Tower = _get_tower_at_global_offset(Vector2i.DOWN)
	if source_tower == top_tower:
		return bottom_tower
	if source_tower == bottom_tower:
		return top_tower
	return null

func _get_tower_at_global_offset(offset: Vector2i) -> Tower:
	var rite_tower: Tower = unit as Tower
	var island: Island = Run.references.island
	if not is_instance_valid(rite_tower) or not is_instance_valid(island):
		return null
	return island.get_tower_on_tile(rite_tower.tower_position + offset)

func _disconnect_tower(tower: Tower) -> void:
	if not is_instance_valid(tower) or not _connected_towers.has(tower):
		return

	tower.unsubscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_linked_tower_pre_hit)
	tower.unsubscribe_event(GameEvent.EventType.HIT_DEALT, _on_linked_tower_hit_dealt)
