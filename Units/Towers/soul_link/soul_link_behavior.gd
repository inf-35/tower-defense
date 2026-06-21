extends Behavior
class_name SoulLinkBehavior

var _forward_tower: Tower
var _back_tower: Tower

func start() -> void:
	_connect_island_updates()
	_refresh_links()

func attach() -> void:
	_connect_island_updates()
	_refresh_links()

func detach() -> void:
	_disconnect_island_updates()
	_disconnect_forward_tower()
	_back_tower = null

func _exit_tree() -> void:
	detach()

func _connect_island_updates() -> void:
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	if island.island_changed.is_connected(_refresh_links):
		return

	island.island_changed.connect(_refresh_links)

func _disconnect_island_updates() -> void:
	if not Run.references:
		return
	
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	if island.island_changed.is_connected(_refresh_links):
		island.island_changed.disconnect(_refresh_links)

func _refresh_links() -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive:
		return

	var forward_direction: Vector2i = tower.get_forward_direction()
	var new_forward_tower: Tower = _get_tower_at_offset(forward_direction)
	var new_back_tower: Tower = _get_tower_at_offset(-forward_direction)

	if not _is_linkable_tower(new_forward_tower):
		new_forward_tower = null

	if not _is_linkable_tower(new_back_tower):
		new_back_tower = null

	if new_forward_tower != _forward_tower:
		_disconnect_forward_tower()
		_forward_tower = new_forward_tower
		_connect_forward_tower()

	_back_tower = new_back_tower

func _get_tower_at_offset(offset: Vector2i) -> Tower:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or offset == Vector2i.ZERO:
		return null

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return null

	return island.get_tower_on_tile(tower.tower_position + offset)

func _connect_forward_tower() -> void:
	if not is_instance_valid(_forward_tower):
		return

	if _forward_tower.on_event.is_connected(_on_forward_tower_event):
		return

	_forward_tower.on_event.connect(_on_forward_tower_event)

func _disconnect_forward_tower() -> void:
	if not is_instance_valid(_forward_tower):
		_forward_tower = null
		return

	if _forward_tower.on_event.is_connected(_on_forward_tower_event):
		_forward_tower.on_event.disconnect(_on_forward_tower_event)

	_forward_tower = null

func _on_forward_tower_event(event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	if unit.disabled:
		return

	if not _is_linkable_tower(_back_tower):
		return

	var incoming_hit: HitData = event.data as HitData
	if not is_instance_valid(incoming_hit) or incoming_hit.negate:
		return

	incoming_hit.negate = true
	var transferred_hit: HitData = _create_transferred_hit(incoming_hit)
	if not is_instance_valid(transferred_hit):
		return

	_back_tower.take_hit(transferred_hit)

func _create_transferred_hit(incoming_hit: HitData) -> HitData:
	var transferred_hit: HitData = incoming_hit.duplicate() as HitData
	transferred_hit.negate = false
	transferred_hit.target = _back_tower
	transferred_hit.target_affiliation = _back_tower.hostile
	if not transferred_hit.derive_lineage_from(incoming_hit, self):
		return null
	transferred_hit.velocity = (_back_tower.global_position - _forward_tower.global_position).normalized()
	return transferred_hit

func _is_linkable_tower(candidate: Tower) -> bool:
	if not is_instance_valid(candidate):
		return false

	if candidate == unit:
		return false

	if candidate.current_state != Tower.State.ACTIVE:
		return false

	if not is_instance_valid(candidate.health_component):
		return false

	if candidate.health_component.health <= 0.0:
		return false

	return true

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var start_pos: Vector2 = Island.cell_to_position(tower.tower_position)
	var forward_direction: Vector2i = tower.get_forward_direction()

	_draw_adjacent_link(canvas, start_pos, tower.tower_position + forward_direction, canvas.positive_highlight_color)
	_draw_adjacent_link(canvas, start_pos, tower.tower_position - forward_direction, canvas.negative_highlight_color)

func _draw_adjacent_link(canvas: RangeIndicator, start_pos: Vector2, cell: Vector2i, color: Color) -> void:
	var end_pos: Vector2 = Island.cell_to_position(cell)
	canvas.preview_line(start_pos, end_pos, color, 2.0)
	canvas.draw_cell(cell, color)
