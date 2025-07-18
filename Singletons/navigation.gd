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

#flow_fields containes multiple flow fields indexed by goal position
#flow field: Vector2i -> Vector2i (direction step toward goal); built at once
var _flow_fields: Dictionary[Vector2i, Dictionary] = {}
#path_caches contains multiple path caches indexed by goal position
#path cache: Vector2i -> Array (where Array is a path leading to Vector2i.ZERO); built across requests
var _path_caches: Dictionary[Vector2i, Dictionary] = {}
#multiple threads, one per goal.
#threading members -> the rationale behind side-threading here is to not cause stutters when rebuilding the field
var _build_threads: Dictionary[Vector2i, Thread]
#Promise
var _path_promises: Array[PathPromise] = []

# Clears the current flow field; next find_path() rebuilds
func clear_field() -> void:
	for goal in _build_threads:
		var thread: Thread = _build_threads[goal]
		if thread.is_alive():
			thread.wait_to_finish()

	_flow_fields.clear()
	_path_caches.clear()

	field_cleared.emit()

func clear_field_for_goal(goal: Vector2i) -> void:
	if _build_threads.has(goal):
		var thread: Thread = _build_threads[goal]
		if thread.is_alive():
			thread.wait_to_finish()
		_build_threads.erase(goal)

	if _flow_fields.has(goal):
		_flow_fields.erase(goal)
	if _path_caches.has(goal):
		_path_caches.erase(goal)

#entry point to building the flow field
func _build_flow_field_async(goal: Vector2i) -> void:
	#prevent starting a new thread if one for this goal is alr running
	if _build_threads.has(goal):
		return
	
	var build_thread := Thread.new()
	_build_threads[goal] = build_thread
	build_thread.start(_build_flow_field.bind(goal))

#this function now computes a local field and returns it
#this is CRITICAL for thread safety, as it no longer writes to a shared global variable

#NOTE: this function reads goal and grid in an unsafe manner. 
#the reason this code is acceptably safe is not because race conditions are impossible
#but bc its resilient to stale data, and the write operations on grid are strictly controlled.
func _build_flow_field(goal: Vector2i) -> Dictionary[Vector2i, Vector2i]:
	var local_flow_field: Dictionary[Vector2i, Vector2i] = {}
	if not grid.has(goal):
		return local_flow_field
	
	var open_set := PriorityQueue.new([ [_heuristic(goal, goal), goal] ])
	var g_score: Dictionary[Vector2i, float] = { goal: 0.0 }
	local_flow_field[goal] = Vector2i.ZERO

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
				local_flow_field[neighbor] = -dir
	#reconverge on collector function
	_on_flow_field_built.call_deferred(goal, local_flow_field)
	return local_flow_field

#pseudo-euclidean distance heuristic
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return (a - b).length_squared()
	
func _on_flow_field_built(goal: Vector2i, new_flow_field: Dictionary[Vector2i, Vector2i]) -> void:
	#ensure the thread from the dictionary is the one we wait 
	if _build_threads.has(goal):
		_build_threads[goal].wait_to_finish()
		_build_threads.erase(goal) # remove from the list of running threads
	
	_flow_fields[goal] = new_flow_field
	_path_caches[goal] = {} # create a fresh path cache for this new field
	field_ready.emit(goal) # signal that a field for this specific goal is ready
	#we cant iterate while removing promises, so we create a new array
	var promises_to_keep: Array[PathPromise] = []
	for promise: PathPromise in _path_promises: 
		if promise.goal == goal and is_instance_valid(promise.recipient): #find fitting promises
			promise.recipient.receive_path_data(find_path(promise.position, promise.goal))
		else:
			promises_to_keep.append(promise) # keep promises for other goals
	_path_promises = promises_to_keep
	#NOTE: if we were running stale, clear_field will immediately discard our work after this

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
	# if a field for this goal isn't built yet...
	if not _flow_fields.has(goal):
		# ...check if it's currently being built. if not, start building it.
		if not _build_threads.has(goal):
			_build_flow_field_async(goal)
		return PathData.new([], PathData.Status.building_path)

	# retrieve the specific flow field and path cache for this goal
	var current_flow_field: Dictionary = _flow_fields[goal]
	var current_path_cache: Dictionary = _path_caches[goal]

	var path: Array[Vector2i] = []
	var current: Vector2i = start

	while current != goal: # reconstruct path from the specific field
		if not current_flow_field.has(current):
			return PathData.new([], PathData.Status.no_path)
			
		if current_path_cache.has(current):
			path.append_array(current_path_cache[current])
			current = goal
		else:
			current += current_flow_field[current]
			path.append(current)

	current_path_cache[start] = path # cache the path in the correct cache
	return PathData.new(path, PathData.Status.found_path)

func request_path_promise(path_promise: PathPromise):
	_path_promises.append(path_promise)
