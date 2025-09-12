# camera.gd
extends Camera2D
class_name Camera

#configuration
const RETURN_FROM_OVERRIDE_TIME: float = 0.5 # how long it takes for the camera to snap back to position from override
# --- private state for the override system ---
# this flag will disable manual controls when true
var _is_overridden: bool = false
# a reference to the active tween, so we can manage it
var _active_tween: Tween
#save camera state before override
var camera_state_cache: Array[Vector2] #[ position, zoom ]

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	# only allow manual camera control if no override is active
	if _is_overridden:
		return

	# check if the abstract action was just triggered this frame.
	if Input.is_action_just_pressed("zoom_in"):
		zoom *= 0.9
		
	if Input.is_action_just_pressed("zoom_out"):
		zoom /= 0.9

	position += get_viewport_rect().size / zoom * Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down") * delta * 0.5

# --- public api for the override system ---

# this is the main function to trigger the override.
# target_zoom should be a Vector2, e.g., Vector2(0.5, 0.5) for a closer view.
func override_camera(target_position: Vector2, target_zoom: Vector2, duration: float) -> void:
	#before override, save current position and zoom
	camera_state_cache = [position, zoom]
	# 1. kill any previous override tween that might still be running.
	# this is critical to prevent conflicting animations.
	if is_instance_valid(_active_tween):
		_active_tween.kill()

	# 2. set the state flag to disable manual controls.
	_is_overridden = true
	
	# 3. create a new tween to handle the smooth transition.
	_active_tween = create_tween()
	_active_tween.set_parallel(true) # allow position and zoom to animate simultaneously
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE) # for a smooth slowdown
	
	# 4. add the properties to be animated.
	_active_tween.tween_property(self, "position", target_position, duration)
	_active_tween.tween_property(self, "zoom", target_zoom, duration)
	
	# 5. connect the finished signal to our cleanup function.
	_active_tween.finished.connect(_on_override_finished)

# allows an external system (like a UI button) to cancel the override
func release_override() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	# the cleanup function is called directly to ensure state is reset
	_on_override_finished()
	
	_active_tween = create_tween()
	_active_tween.set_parallel(true) # allow position and zoom to animate simultaneously
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE) # for a smooth slowdown
	_active_tween.tween_property(self, "position", camera_state_cache[0], RETURN_FROM_OVERRIDE_TIME)
	_active_tween.tween_property(self, "zoom", camera_state_cache[1], RETURN_FROM_OVERRIDE_TIME)
	
	_active_tween.finished.connect(func(): _is_overridden = false)

# --- private signal handler ---

# this function is called automatically when the override tween completes.
func _on_override_finished() -> void:
	# 2. clear the reference to the now-finished tween.
	_active_tween = null
