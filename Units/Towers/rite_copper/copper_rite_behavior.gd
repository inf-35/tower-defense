extends Behavior
class_name CopperRiteBehavior

var _connected_towers: Dictionary[Tower, Callable] = {}
var _pending_statuses: Dictionary[Tower, Dictionary] = {}

func start() -> void:
	var tower: Tower = unit as Tower
	tower.adjacency_updated.connect(_on_adjacency_updated)
	attach()

func attach() -> void:
	_refresh_connections()

func detach() -> void:
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		_disconnect_tower(tower)

	_connected_towers.clear()
	_pending_statuses.clear()

func _on_adjacency_updated(_adj_map: Dictionary[Vector2i, Tower]) -> void:
	_refresh_connections()

func _refresh_connections() -> void:
	var current_set: Dictionary[Tower, bool] = {}
	for tower: Tower in _get_linked_towers():
		if not is_instance_valid(tower):
			continue

		current_set[tower] = true
		if _connected_towers.has(tower):
			continue

		var event_handler: Callable = _on_linked_tower_event.bind(tower)
		tower.on_event.connect(event_handler)
		_connected_towers[tower] = event_handler
		if is_instance_valid(unit.buff_component):
			unit.buff_component.activate_new_link(tower)

	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		if current_set.has(tower):
			continue
		_disconnect_tower(tower)
		_connected_towers.erase(tower)
		_pending_statuses.erase(tower)

func _on_linked_tower_event(event: GameEvent, source_tower: Tower) -> void:
	if event.event_type == GameEvent.EventType.PRE_HIT_DEALT:
		_release_pending_statuses(source_tower, event.data as HitData)
		return

	if event.event_type == GameEvent.EventType.HIT_DEALT:
		_store_statuses_for_counterpart(source_tower, event.data as HitReportData)

func _release_pending_statuses(source_tower: Tower, hit_data: HitData) -> void:
	if not is_instance_valid(source_tower) or not is_instance_valid(hit_data):
		return
	if not hit_data.primary or hit_data.negate:
		return
	if not _pending_statuses.has(source_tower):
		return

	var pending: Dictionary = _pending_statuses[source_tower]
	if pending.is_empty():
		return

	_merge_status_payload(hit_data.status_effects, pending)
	_pending_statuses.erase(source_tower)
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _store_statuses_for_counterpart(source_tower: Tower, report: HitReportData) -> void:
	if not is_instance_valid(source_tower) or report == null:
		return
	if report.source != source_tower or report.statuses_applied.is_empty():
		return

	var counterpart: Tower = _get_counterpart(source_tower)
	if not is_instance_valid(counterpart):
		return

	var pending: Dictionary = _pending_statuses.get(counterpart, {})
	_merge_status_payload(pending, report.statuses_applied)
	_pending_statuses[counterpart] = pending
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _merge_status_payload(target_payload: Dictionary, incoming_payload: Dictionary) -> void:
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

	var event_handler: Callable = _connected_towers[tower]
	if tower.on_event.is_connected(event_handler):
		tower.on_event.disconnect(event_handler)

func draw_visuals(canvas: RangeIndicator) -> void:
	_draw_global_offset_cell(canvas, Vector2i.UP)
	_draw_global_offset_cell(canvas, Vector2i.DOWN)

func _draw_global_offset_cell(canvas: RangeIndicator, offset: Vector2i) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var margin: int = 2
	var cell_size: int = Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	var pos: Vector2 = Island.cell_to_position(tower.tower_position + offset)
	var rect: Rect2 = Rect2(pos - half_size, Vector2(cell_size, cell_size))
	canvas.preview_rect(rect, canvas.highlight_color, false, 1.0)
