extends Node

const BASE_COST: int = 1
const _HYPOTHETICAL_BLOCKER_COST: int = 100
const _MAX_PATH_STEPS: int = 2000

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var grid: Dictionary[Vector2i, int] = {}
var _flow_fields: Dictionary[int, Dictionary] = {}
var _path_caches: Dictionary[int, Dictionary] = {}

class PathData:
	var path: Array[Vector2i]
	var status: Status

	enum Status {
		FOUND_PATH,
		NO_PATH,
	}

	func _init(_path: Array[Vector2i] = [], _status: PathData.Status = PathData.Status.FOUND_PATH):
		path = _path
		status = _status

func generate_field_code(goal: Vector2i, ignore_walls: bool) -> int:
	var combined_coords: int = (int(goal.y) << 32) | (goal.x & 0xFFFFFFFF)
	return (combined_coords << 1) | int(ignore_walls)

func clear_field() -> void:
	_flow_fields.clear()
	_path_caches.clear()

func clear_field_for_goal(goal: Vector2i, ignore_walls: bool) -> void:
	var key: int = generate_field_code(goal, ignore_walls)
	_flow_fields.erase(key)
	_path_caches.erase(key)

func find_path(start: Vector2i, goal: Vector2i = Vector2i.ZERO, ignore_walls: bool = false) -> PathData:
	var key: int = generate_field_code(goal, ignore_walls)
	_ensure_flow_field(goal, ignore_walls)

	var current_flow_field: Dictionary = _flow_fields[key]
	if not current_flow_field.has(start):
		return PathData.new([], PathData.Status.NO_PATH)

	var current_path_cache: Dictionary = _path_caches[key]
	if current_path_cache.has(start):
		return PathData.new(current_path_cache[start], PathData.Status.FOUND_PATH)

	var path: Array[Vector2i] = _reconstruct_path(start, goal, current_flow_field, current_path_cache)
	if start != goal and path.is_empty():
		return PathData.new([], PathData.Status.NO_PATH)

	current_path_cache[start] = path
	return PathData.new(path, PathData.Status.FOUND_PATH)

func get_hypothetical_path(start: Vector2i, goal: Vector2i, blocker_cells: Dictionary, ignore_walls: bool = false) -> PathData:
	if ignore_walls or blocker_cells.is_empty():
		return find_path(start, goal, ignore_walls)
	return _find_path_internal(start, goal, ignore_walls, blocker_cells)

func _ensure_flow_field(goal: Vector2i, ignore_walls: bool) -> void:
	var key: int = generate_field_code(goal, ignore_walls)
	if _flow_fields.has(key):
		return

	_flow_fields[key] = _build_flow_field(goal, ignore_walls)
	_path_caches[key] = {}

func _build_flow_field(goal: Vector2i, ignore_walls: bool) -> Dictionary:
	var local_flow_field: Dictionary = {}
	if not grid.has(goal):
		return local_flow_field

	var open_set := PriorityQueue.new([[_heuristic(goal, goal), goal]])
	var g_score: Dictionary = {goal: 0.0}
	local_flow_field[goal] = Vector2i.ZERO

	while open_set.size() > 0:
		var current: Vector2i = open_set.get_min()[1]
		open_set.pop()

		for dir: Vector2i in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if not grid.has(neighbor):
				continue

			var move_cost: int = BASE_COST if ignore_walls else grid[neighbor]
			var tentative_g: float = g_score[current] + float(move_cost)

			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				open_set.insert([tentative_g + _heuristic(neighbor, goal), neighbor])
				local_flow_field[neighbor] = -dir

	return local_flow_field

func _find_path_internal(start: Vector2i, goal: Vector2i, ignore_walls: bool, extra_blockers: Dictionary) -> PathData:
	if not grid.has(start) or not grid.has(goal):
		return PathData.new([], PathData.Status.NO_PATH)

	var local_flow_field: Dictionary = {}
	var open_set := PriorityQueue.new([[_heuristic(goal, goal), goal]])
	var g_score: Dictionary = {goal: 0.0}
	local_flow_field[goal] = Vector2i.ZERO

	while open_set.size() > 0:
		var current: Vector2i = open_set.get_min()[1]
		open_set.pop()

		if current == start:
			break

		for dir: Vector2i in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if not grid.has(neighbor):
				continue

			var move_cost: int = BASE_COST if ignore_walls else grid[neighbor]
			if extra_blockers.has(neighbor):
				move_cost = _HYPOTHETICAL_BLOCKER_COST

			var tentative_g: float = g_score[current] + float(move_cost)
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				open_set.insert([tentative_g + _heuristic(neighbor, goal), neighbor])
				local_flow_field[neighbor] = -dir

	if not local_flow_field.has(start):
		return PathData.new([], PathData.Status.NO_PATH)

	var path: Array[Vector2i] = _reconstruct_path(start, goal, local_flow_field)
	if start != goal and path.is_empty():
		return PathData.new([], PathData.Status.NO_PATH)
	return PathData.new(path, PathData.Status.FOUND_PATH)

func _reconstruct_path(start: Vector2i, goal: Vector2i, flow_field: Dictionary, path_cache: Dictionary = {}) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = start
	var safety: int = 0

	while current != goal:
		if path_cache.has(current):
			path.append_array(path_cache[current])
			break

		if not flow_field.has(current):
			return []

		var direction: Vector2i = flow_field[current]
		current += direction
		path.append(current)

		safety += 1
		assert(safety <= _MAX_PATH_STEPS, "Navigation: path reconstruction exceeded safety limit.")
		if safety > _MAX_PATH_STEPS:
			return []

	return path

static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return (a - b).length_squared()
