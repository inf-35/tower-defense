extends Behavior
class_name IronRiteBehavior

@export var overkill_transfer_ratio: float = 0.2 ##portion of front-tower overkill banked for the back tower

var _connected_towers: Dictionary[Tower, Callable] = {}
var _pending_damage: Dictionary[Tower, float] = {}

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
	_pending_damage.clear()

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
		_pending_damage.erase(tower)

func _on_linked_tower_event(event: GameEvent, source_tower: Tower) -> void:
	if event.event_type == GameEvent.EventType.PRE_HIT_DEALT:
		_release_pending_damage(source_tower, event.data as HitData)
		return

	if event.event_type == GameEvent.EventType.HIT_DEALT:
		_store_overkill(source_tower, event.data as HitReportData)

func _release_pending_damage(source_tower: Tower, hit_data: HitData) -> void:
	if source_tower != _get_back_tower():
		return
	if not is_instance_valid(hit_data) or not hit_data.primary or hit_data.negate:
		return

	var damage: float = _pending_damage.get(source_tower, 0.0)
	if damage <= 0.0:
		return

	hit_data.damage += damage
	_pending_damage.erase(source_tower)
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _store_overkill(source_tower: Tower, report: HitReportData) -> void:
	if source_tower != _get_front_tower():
		return
	if report == null or report.source != source_tower or report.overkill <= 0.0:
		return

	var back_tower: Tower = _get_back_tower()
	if not is_instance_valid(back_tower):
		return

	var stored_damage: float = report.overkill * maxf(overkill_transfer_ratio, 0.0)
	if stored_damage <= 0.0:
		return

	_pending_damage[back_tower] = _pending_damage.get(back_tower, 0.0) + stored_damage
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _get_linked_towers() -> Array[Tower]:
	var linked_towers: Array[Tower] = []
	var front_tower: Tower = _get_front_tower()
	var back_tower: Tower = _get_back_tower()
	if is_instance_valid(front_tower):
		linked_towers.append(front_tower)
	if is_instance_valid(back_tower) and back_tower != front_tower:
		linked_towers.append(back_tower)
	return linked_towers

func _get_front_tower() -> Tower:
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return null
	return _get_tower_at_offset(rite_tower.get_forward_direction())

func _get_back_tower() -> Tower:
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return null
	return _get_tower_at_offset(-rite_tower.get_forward_direction())

func _get_tower_at_offset(offset: Vector2i) -> Tower:
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
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return

	_draw_offset_cell(canvas, rite_tower.get_forward_direction(), canvas.input_color)
	_draw_offset_cell(canvas, -rite_tower.get_forward_direction(), canvas.highlight_color)

func _draw_offset_cell(canvas: RangeIndicator, offset: Vector2i, color: Color) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var margin: int = 2
	var cell_size: int = Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	var pos: Vector2 = Island.cell_to_position(tower.tower_position + offset)
	var rect: Rect2 = Rect2(pos - half_size, Vector2(cell_size, cell_size))
	canvas.preview_rect(rect, color, false, 1.0)
