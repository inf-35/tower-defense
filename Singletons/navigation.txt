extends Node

signal field_cleared()
signal field_ready(goal: Vector2i)

const DIRECTIONS: Array[Vector2i] = [
	Vector2i( 1,  0),
	Vector2i(-1,  0),
	Vector2i( 0,  1),
	Vector2i( 0, -1),
]

# Grid: Vector2i -> bool (true = walkable)
var grid: Dictionary[Vector2i, bool] = {}

# Flow field: Vector2i -> Vector2i (direction step toward goal); built at once
var flow_field: Dictionary[Vector2i, Vector2i] = {}

#Path cache: Vector2i -> Array (where Array is a path leading to Vector2i.ZERO); built across requests
var path_cache: Dictionary[Vector2i, Array] = {}

# Internal cache tracking
var _cached_goal: Vector2i = Vector2i.ZERO
var _field_built: bool = false

# Threading members -> the rationale behind side-threading here is to not cause stutters when rebuilding the field
var _build_thread: Thread
var _thread_running: bool = false

#Promise
var _path_promises: Array[PathPromise] = []

# Clears the current flow field; next find_path() rebuilds
func clear_field() -> void:
	if _thread_running and _build_thread.is_alive():
		_build_thread.wait_to_finish()
	_thread_running = false

	flow_field.clear()
	path_cache.clear()
	_field_built = false

	field_cleared.emit()

#Entry point to building the flow field
func _build_flow_field_async(goal: Vector2i) -> void:
	if _thread_running:
		return
		
	_thread_running = true
	_build_thread = Thread.new()
	_build_thread.start(_build_flow_field.bind(goal))

# Internal: runs A* from goal, filling flow_field with the best step for each cell
func _build_flow_field(goal: Vector2i) -> void:
	path_cache.clear()
	flow_field.clear()
	if not grid.has(goal):
		return

	var open_set := PriorityQueue.new([ [_heuristic(goal, goal), goal] ])
	var g_score: Dictionary[Vector2i, float] = { goal: 0.0 }
	flow_field[goal] = Vector2i.ZERO

	while open_set.size() > 0: #main a* loop
		# pick node in open_set with lowest f_score
		var current: Vector2i = open_set.get_min()[1]
		open_set.pop() #remove current from queue

		for dir: Vector2i in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if (not grid.has(neighbor)):
				continue #ignore cells out-of-bounds
				
			#evaluate move cost
			var move_cost: float
			if neighbor == goal:
				move_cost = 1.0
			elif grid[neighbor]:
				move_cost = 1.0
			elif not grid[neighbor]: #cell is blocked
				move_cost = 50.0

			var tentative_g = g_score[current] + move_cost
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				open_set.insert([
					tentative_g + _heuristic(neighbor, goal),
					neighbor
				])
				# store the step that moves toward current
				flow_field[neighbor] = -dir
	#reconverge on collector function
	_on_flow_field_built.call_deferred(goal)

# pseudo-euclidean distance heuristic
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return (a - b).length_squared()
	
func _on_flow_field_built(goal: Vector2i) -> void:
	_build_thread.wait_to_finish()
	_cached_goal = goal
	_field_built = true
	_thread_running = false
	field_ready.emit(goal)
	
	for promise: PathPromise in _path_promises: #settle promises
		if promise.goal == _cached_goal and is_instance_valid(promise.recipient):
			promise.recipient.receive_path_data(find_path(promise.position, promise.goal))

	_path_promises.clear()

# Public: returns an Array of Vector2i from start to goal (excluding start)
# Rebuilds the flow field if goal changed or cleared

class PathData: #path output/input data, includes peripheral status codes
	var path: Array[Vector2i]
	var status: Status
	
	enum Status {
		found_path, #path found, contained in path variable.
		building_path, #path still building
		no_path, #unreachable
	}
	
	func _init(_path: Array[Vector2i] = [], _status: PathData.Status = PathData.Status.found_path):
		path = _path
		status = _status
		
class PathPromise: #path promise, used to reconcile async deficits
	var recipient: NavigationComponent
	var position: Vector2i
	var goal: Vector2i
	
	func _init(_recipient: NavigationComponent, _position: Vector2i, _goal: Vector2i = Vector2i.ZERO):
		recipient = _recipient
		position = _position
		goal = _goal

func find_path(start: Vector2i, goal: Vector2i = Vector2i.ZERO) -> PathData:
	if not _field_built or goal != _cached_goal:
		_build_flow_field_async(goal)
		return PathData.new([], PathData.Status.building_path)

	var path: Array[Vector2i] = []
	var current: Vector2i = start

	while current != goal: #reconstruct path
		if not flow_field.has(current):
			return PathData.new([], PathData.Status.no_path)
			
		if path_cache.has(current):
			path.append_array(path_cache[current])
			current = goal #reached a cached path, follow down cached path to goal
		else:
			current += flow_field[current] #follow down flow field
			path.append(current)

	path_cache[start] = path #cache path at origin
	return PathData.new(path, PathData.Status.found_path)

func request_path_promise(path_promise: PathPromise):
	_path_promises.append(path_promise)
