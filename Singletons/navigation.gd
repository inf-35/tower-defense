extends Node

signal field_cleared()
signal field_ready(goal: Vector2i, ignore_walls: bool)

const DIRECTIONS: Array[Vector2i] = [
	Vector2i( 1,  0),
	Vector2i(-1,  0),
	Vector2i( 0,  1),
	Vector2i( 0, -1),
]

# Grid: Vector2i -> int (navcost)
var grid: Dictionary[Vector2i, int] = {}
#flow_fields containes multiple flow fields indexed by 64-bit field code (see generate_field_code)
#flow field: Vector2i -> Vector2i (direction step toward goal); built at once
var _flow_fields: Dictionary[int, Dictionary] = {}
#path_caches contains multiple path caches indexed by field code
#path cache: Vector2i -> Array (where Array is a path leading to Vector2i.ZERO); built across requests
var _path_caches: Dictionary[int, Dictionary] = {}
#multiple threads, one per field code
#threading members -> the rationale behind side-threading here is to not cause stutters when rebuilding the field
var _build_threads: Dictionary[int, Thread]
#Promise
var _path_promises: Array[PathPromise] = []

func generate_field_code(goal: Vector2i, ignore_walls: bool) -> int:
	# step 1: combine the two 32-bit integers from the goal vector into one 64-bit integer.
	# we cast 'y' to a 64-bit int, shift it left by 32 bits to make room for 'x',
	# and then perform a bitwise OR with 'x'.
	# the 'x' component is masked with 0xFFFFFFFF to prevent sign extension issues
	# with negative coordinates, ensuring the hash is stable and correct.
	var combined_coords: int = (int(goal.y) << 32) | (goal.x & 0xFFFFFFFF)
	# step 2: shift the combined coordinate hash left by one bit.
	# this vacates the least significant bit (LSB), making a space for our boolean flag.
	var shifted_hash: int = combined_coords << 1
	# step 3: convert the boolean to an integer (0 or 1) and place it in the LSB.
	var wall_bit: int = int(ignore_walls)
	# the final hash is the combination of the coordinate data and the boolean flag.
	# every unique combination of inputs will produce a unique integer output.
	return shifted_hash | wall_bit

# Clears the current flow field; next find_path() rebuilds
func clear_field() -> void:
	for goal in _build_threads:
		var thread: Thread = _build_threads[goal]
		if thread.is_alive():
			thread.wait_to_finish()

	_flow_fields.clear()
	_path_caches.clear()

	field_cleared.emit()

func clear_field_for_goal(goal: Vector2i, ignore_walls : bool) -> void:
	var key : int = generate_field_code(goal, ignore_walls)
	
	if _build_threads.has(key):
		var thread: Thread = _build_threads[key]
		if thread.is_alive():
			thread.wait_to_finish()
		_build_threads.erase(key)

	if _flow_fields.has(key):
		_flow_fields.erase(key)
	if _path_caches.has(key):
		_path_caches.erase(key)
	
func _build_flow_field_async(goal: Vector2i, ignore_walls: bool) -> void:
	var key: int = generate_field_code(goal, ignore_walls)
	if _build_threads.has(key):
		return
	
	var build_thread := Thread.new()
	_build_threads[key] = build_thread
	
	# --- THE CRITICAL FIX ---
	# create a deep copy of the grid at this exact moment in time.
	# this is a complete, consistent snapshot of the world state.
	var grid_snapshot: Dictionary[Vector2i, int] = grid.duplicate(true)
	
	# pass this safe, local copy to the thread. the thread will no longer
	# touch the global 'self.grid' variable.
	build_thread.start(_build_flow_field.bind(goal, ignore_walls, grid_snapshot))

#this function computes a local field and returns it
#this is CRITICAL for thread safety, as it no longer writes to a shared global variable
func _build_flow_field(goal: Vector2i, ignore_walls: bool, p_grid: Dictionary[Vector2i, int]) -> Dictionary[Vector2i, Vector2i]:
	var local_flow_field: Dictionary[Vector2i, Vector2i] = {}
	if not p_grid.has(goal):
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
			if (not p_grid.has(neighbor)):
				continue #ignore cells out-of-bounds
				
			#evaluate move cost
			var move_cost: int
			var base_nav_cost: int = p_grid.get(neighbor, 0)
			
			if ignore_walls:
				move_cost = 0
			else:
				move_cost = base_nav_cost

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
	_on_flow_field_built.call_deferred(goal, ignore_walls, local_flow_field)
	return local_flow_field
#pseudo-euclidean distance heuristic
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return (a - b).length_squared()
	
func _on_flow_field_built(goal: Vector2i, ignore_walls: bool, new_flow_field: Dictionary[Vector2i, Vector2i]) -> void:
	var key: int = generate_field_code(goal, ignore_walls)
	#ensure the thread from the dictionary is the one we wait 
	if _build_threads.has(key):
		_build_threads.erase(key) # remove from the list of running threads
	
	_flow_fields[key] = new_flow_field
	_path_caches[key] = {} # create a fresh path cache for this new field
	field_ready.emit(goal, ignore_walls) # signal that a field for this specific goal is ready
	#we cant iterate while removing promises, so we create a new array
	var promises_to_keep: Array[PathPromise] = []
	for promise: PathPromise in _path_promises: 
		if promise.goal == goal and promise.ignore_walls == ignore_walls and is_instance_valid(promise.recipient): #find fitting promises
			promise.recipient.receive_path_data(find_path(promise.position, promise.goal, promise.ignore_walls))
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
		FOUND_PATH, #path found, contained in path variable.
		BUILDING_PATH, #path still building
		NO_PATH, #unreachable
	}
	
	func _init(_path: Array[Vector2i] = [], _status: PathData.Status = PathData.Status.FOUND_PATH):
		path = _path
		status = _status
		
class PathPromise: #path promise, used to reconcile async deficits
	var recipient: NavigationComponent
	var position: Vector2i
	var goal: Vector2i
	var ignore_walls : bool
	
	func _init(_recipient: NavigationComponent, _position: Vector2i, _goal: Vector2i = Vector2i.ZERO, _ignore_walls : bool = false):
		recipient = _recipient
		position = _position
		goal = _goal
		ignore_walls = _ignore_walls

func find_path(start: Vector2i, goal: Vector2i = Vector2i.ZERO, ignore_walls: bool = false) -> PathData:
	var key: int = generate_field_code(goal, ignore_walls)
	# if a field for this goal isn't built yet...
	if not _flow_fields.has(key):
		# ...check if it's currently being built. if not, start building it.
		if not _build_threads.has(key):
			_build_flow_field_async(goal, ignore_walls)
		return PathData.new([], PathData.Status.BUILDING_PATH) #agent will keep calling us until we fulfill our promise

	# retrieve the specific flow field and path cache for this goal (by reference)
	var current_flow_field: Dictionary = _flow_fields[key]
	var current_path_cache: Dictionary = _path_caches[key]

	var path: Array[Vector2i] = []
	var current: Vector2i = start

	while current != goal: # reconstruct path from the specific field
		if not current_flow_field.has(current):
			return PathData.new([], PathData.Status.NO_PATH)
			
		if current_path_cache.has(current):
			path.append_array(current_path_cache[current])
			current = goal
		else:
			current += current_flow_field[current]
			path.append(current)

	current_path_cache[start] = path # cache the path in the correct cache
	return PathData.new(path, PathData.Status.FOUND_PATH)

func request_path_promise(path_promise: PathPromise):
	_path_promises.append(path_promise)
