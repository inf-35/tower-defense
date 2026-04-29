extends RefCounted
class_name TowerTopologyService

enum QueryKind { CARDINAL_RING, AXIAL_LINE, DIAGONAL_LINE, OFFSET_MASK }
enum AxisSpace { WORLD, LOCAL_FACING }

const AXIS_UP: int = 1
const AXIS_RIGHT: int = 2
const AXIS_DOWN: int = 4
const AXIS_LEFT: int = 8
const _LEGACY_AXIS_MASK: int = AXIS_UP | AXIS_RIGHT | AXIS_DOWN | AXIS_LEFT

class Query extends RefCounted: ##request object
	var kind: int
	var min_range: int
	var max_range: int
	var axis_mask: int
	var offsets: Array[Vector2i]
	var axis_space: int
	var bounds_radius: int

	func _init(
		p_kind: int = QueryKind.CARDINAL_RING,
		p_min_range: int = 1,
		p_max_range: int = 1,
		p_axis_mask: int = 0b1111, #all axes
		p_offsets: Array[Vector2i] = [],
		p_axis_space: int = AxisSpace.WORLD
	) -> void:
		kind = p_kind
		min_range = mini(p_min_range, p_max_range)
		max_range = maxi(p_min_range, p_max_range)
		axis_mask = p_axis_mask
		offsets = p_offsets.duplicate()
		axis_space = p_axis_space
		bounds_radius = max_range
		for offset: Vector2i in offsets:
			bounds_radius = maxi(bounds_radius, maxi(absi(offset.x), absi(offset.y)))

class Report extends RefCounted: ##answer object
	var pivot: Tower
	var query: Query
	var cells: Dictionary = {} ## Dictionary[Vector2i, Vector2i], local offset -> absolute cell
	var towers_by_local_offset: Dictionary[Vector2i, Tower] = {} ## Dictionary[Vector2i, Tower]
	var unique_towers: Array[Tower] = [] ##deduped towers,for multitile towers

var island: Island

var _subscriptions: Dictionary = {} ## id -> record
var _subscriptions_by_pivot: Dictionary = {} ## pivot_id -> Array[int]
var _next_subscription_id: int = 1
var _max_query_radius: int = 1
var _max_tower_span: int = 1
var _legacy_query := Query.new()

func _init(host_island: Island) -> void:
	island = host_island
	_max_tower_span = _compute_max_tower_span()

func clear() -> void:
	_subscriptions.clear()
	_subscriptions_by_pivot.clear()
	_next_subscription_id = 1
	_max_query_radius = _legacy_query.bounds_radius

func query(pivot: Tower, query_data: Query) -> Report: ##core function
	var report := Report.new()
	report.pivot = pivot
	report.query = query_data
	if not is_instance_valid(pivot) or not is_instance_valid(island):
		return report

	var seen_towers: Dictionary = {}
	for offset: Vector2i in _resolve_offsets(pivot, query_data):
		var absolute_cell := pivot.tower_position + offset
		report.cells[offset] = absolute_cell
		var tower := island.get_tower_on_tile(absolute_cell) as Tower
		if not is_instance_valid(tower):
			continue
		report.towers_by_local_offset[offset] = tower
		if seen_towers.has(tower):
			continue
		seen_towers[tower] = true
		report.unique_towers.append(tower)
	return report

func subscribe(owner: Object, pivot: Tower, query_data: Query, callback: Callable, emit_immediately: bool = true) -> int:
	var id := _next_subscription_id
	_next_subscription_id += 1
	_subscriptions[id] = {
		"owner": owner,
		"pivot": pivot,
		"query": query_data,
		"callback": callback,
		"signature": "",
	}
	var pivot_id := pivot.unit_id
	if not _subscriptions_by_pivot.has(pivot_id):
		_subscriptions_by_pivot[pivot_id] = []
	_subscriptions_by_pivot[pivot_id].append(id)
	_max_query_radius = maxi(_max_query_radius, query_data.bounds_radius)
	if emit_immediately:
		_emit_subscription(id, true)
	return id

func unsubscribe(owner: Object, subscription_id: int = -1) -> void:
	var ids: Array[int] = []
	if subscription_id != -1:
		ids.append(subscription_id)
	else:
		for id: int in _subscriptions:
			if _subscriptions[id]["owner"] == owner:
				ids.append(id)
	for id: int in ids:
		_remove_subscription(id)

func notify_tower_changed(changed_tower: Tower) -> void:
	if not is_instance_valid(changed_tower):
		return
	var affected: Dictionary = { changed_tower: true }
	for cell: Vector2i in changed_tower.get_occupied_cells():
		for pivot: Tower in _get_candidate_pivots(cell):
			affected[pivot] = true
	for pivot: Tower in affected:
		_emit_legacy_adjacency(pivot)
		_emit_subscriptions_for_pivot(pivot)

func _emit_legacy_adjacency(pivot: Tower) -> void:
	if not is_instance_valid(pivot):
		return
	pivot.adjacency_updated.emit(query(pivot, _legacy_query).towers_by_local_offset)

func _emit_subscriptions_for_pivot(pivot: Tower) -> void:
	if not is_instance_valid(pivot):
		return
	var pivot_id := pivot.unit_id
	if not _subscriptions_by_pivot.has(pivot_id):
		return
	for id: int in (_subscriptions_by_pivot[pivot_id] as Array):
		_emit_subscription(id)

func _emit_subscription(id: int, force: bool = false) -> void:
	var record: Dictionary = _subscriptions.get(id, {})
	if record.is_empty():
		return
	var owner := record["owner"] as Object
	var pivot := record["pivot"] as Tower
	var callback := record["callback"] as Callable
	if not is_instance_valid(owner) or not is_instance_valid(pivot) or not callback.is_valid():
		_remove_subscription(id)
		return
	var report := query(pivot, record["query"])
	var signature := _build_signature(report)
	if force or record["signature"] != signature:
		record["signature"] = signature
		_subscriptions[id] = record
		callback.call(report)

func _remove_subscription(id: int) -> void:
	var record: Dictionary = _subscriptions.get(id, {})
	if record.is_empty():
		return
	var pivot := record["pivot"] as Tower
	if is_instance_valid(pivot):
		var pivot_id := pivot.unit_id
		if _subscriptions_by_pivot.has(pivot_id):
			(_subscriptions_by_pivot[pivot_id] as Array).erase(id)
			if (_subscriptions_by_pivot[pivot_id] as Array).is_empty():
				_subscriptions_by_pivot.erase(pivot_id)
	_subscriptions.erase(id)
	_recalculate_max_query_radius()

func _get_candidate_pivots(changed_cell: Vector2i) -> Array[Tower]: ##for a changed target cell, get all pivot towers this change could potentially affect
	var pivots: Dictionary = {}
	var radius := _max_query_radius + _max_tower_span
	for x in range(changed_cell.x - radius, changed_cell.x + radius + 1):
		for y in range(changed_cell.y - radius, changed_cell.y + radius + 1):
			var tower := island.get_tower_on_tile(Vector2i(x, y)) as Tower
			if is_instance_valid(tower):
				pivots[tower] = true
	var output: Array[Tower] = []
	for tower: Tower in pivots:
		output.append(tower)
	return output

func _resolve_offsets(pivot: Tower, query_data: Query) -> Array[Vector2i]: ##converts query objects into vector2i local offsets
	var base_size := pivot.size
	if query_data.axis_space == AxisSpace.LOCAL_FACING and (pivot.facing as int) % 2 != 0:
		base_size = Vector2i(base_size.y, base_size.x)
	var offsets := _build_offsets(base_size, query_data)
	if query_data.axis_space == AxisSpace.WORLD or pivot.facing == Tower.Facing.UP:
		return offsets
	var rotated: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		rotated.append(_rotate_offset(offset, base_size, pivot.facing))
	return rotated

func _build_offsets(size: Vector2i, query_data: Query) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var seen: Dictionary = {}
	if query_data.kind == QueryKind.OFFSET_MASK:
		for offset: Vector2i in query_data.offsets:
			_push_offset(offsets, seen, offset)
		return offsets
	for distance in range(query_data.min_range, query_data.max_range + 1):
		match query_data.kind:
			QueryKind.CARDINAL_RING:
				_add_axis_offsets(offsets, seen, size, distance, _LEGACY_AXIS_MASK)
			QueryKind.AXIAL_LINE:
				_add_axis_offsets(offsets, seen, size, distance, query_data.axis_mask)
			QueryKind.DIAGONAL_LINE:
				if query_data.axis_mask & AXIS_UP and query_data.axis_mask & AXIS_LEFT:
					_push_offset(offsets, seen, Vector2i(-distance, -distance))
				if query_data.axis_mask & AXIS_UP and query_data.axis_mask & AXIS_RIGHT:
					_push_offset(offsets, seen, Vector2i(size.x - 1 + distance, -distance))
				if query_data.axis_mask & AXIS_DOWN and query_data.axis_mask & AXIS_RIGHT:
					_push_offset(offsets, seen, Vector2i(size.x - 1 + distance, size.y - 1 + distance))
				if query_data.axis_mask & AXIS_DOWN and query_data.axis_mask & AXIS_LEFT:
					_push_offset(offsets, seen, Vector2i(-distance, size.y - 1 + distance))
	return offsets

func _add_axis_offsets(offsets: Array[Vector2i], seen: Dictionary, size: Vector2i, distance: int, axis_mask: int) -> void:
	if axis_mask & AXIS_UP:
		for x in range(size.x):
			_push_offset(offsets, seen, Vector2i(x, -distance))
	if axis_mask & AXIS_RIGHT:
		for y in range(size.y):
			_push_offset(offsets, seen, Vector2i(size.x - 1 + distance, y))
	if axis_mask & AXIS_DOWN:
		for x in range(size.x):
			_push_offset(offsets, seen, Vector2i(x, size.y - 1 + distance))
	if axis_mask & AXIS_LEFT:
		for y in range(size.y):
			_push_offset(offsets, seen, Vector2i(-distance, y))

func _push_offset(offsets: Array[Vector2i], seen: Dictionary, offset: Vector2i) -> void:
	if seen.has(offset):
		return
	seen[offset] = true
	offsets.append(offset)

func _rotate_offset(offset: Vector2i, base_size: Vector2i, facing: Tower.Facing) -> Vector2i:
	match facing:
		Tower.Facing.RIGHT:
			return Vector2i(base_size.y - 1 - offset.y, offset.x)
		Tower.Facing.DOWN:
			return Vector2i(base_size.x - 1 - offset.x, base_size.y - 1 - offset.y)
		Tower.Facing.LEFT:
			return Vector2i(offset.y, base_size.x - 1 - offset.x)
		_:
			return offset

func _build_signature(report: Report) -> String:
	var offsets: Array[Vector2i] = []
	offsets.assign(report.cells.keys())
	offsets.sort_custom(_sort_offsets)
	var parts := PackedStringArray()
	parts.append(str(report.pivot.tower_position))
	parts.append(str(report.pivot.facing))
	for offset: Vector2i in offsets:
		var tower := report.towers_by_local_offset.get(offset) as Tower
		parts.append("%d,%d=%d" % [offset.x, offset.y, tower.get_instance_id() if is_instance_valid(tower) else 0])
	return "|".join(parts)

func _sort_offsets(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x

func _compute_max_tower_span() -> int:
	var max_span := 1
	for tower_data in Towers.tower_stats.values():
		max_span = maxi(max_span, maxi(tower_data.size.x, tower_data.size.y))
	return max_span

func _recalculate_max_query_radius() -> void:
	_max_query_radius = _legacy_query.bounds_radius
	for record: Dictionary in _subscriptions.values():
		_max_query_radius = maxi(_max_query_radius, (record["query"] as Query).bounds_radius)
