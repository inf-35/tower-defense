#camera.gd
extends Camera2D
class_name Camera

#configuration
const RETURN_FROM_OVERRIDE_TIME: float = 0.5 #how long it takes for the camera to snap back to position from override

var _target_position: Vector2
#--- private state for the override system ---
#this flag will disable manual controls when true
var _is_overridden: bool = false
var _is_soft_snapping: bool = false
#a reference to the active tween, so we can manage it
var _active_tween: Tween
#save camera state before override
var camera_state_cache: Array[Vector2] #[ position, zoom ]
var _is_drag_panning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_target_position = position

func _unhandled_input(event: InputEvent) -> void:
	if _is_overridden:
		return

	if _is_soft_snapping and _should_cancel_soft_snap(event):
		_cancel_soft_snap()

	#handle zoom here instead of polling input in _process(), so scrollable ui
	#controls can consume mouse wheel events before the camera ever sees them.
	if event.is_action_pressed("zoom_in"):
		zoom *= 0.9
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("zoom_out"):
		zoom /= 0.9
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.is_pressed() and ClickHandler.enabled and ClickHandler.current_state != ClickHandler.State.IDLE:
			return

		_is_drag_panning = event.is_pressed()
		get_viewport().set_input_as_handled()
		return

	if _is_drag_panning and event is InputEventMouseMotion:
		_target_position -= event.relative / zoom
		position = _target_position
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	#only allow manual camera control if no override is active
	if _is_overridden:
		return
	if _is_soft_snapping:
		return

	_target_position += get_viewport_rect().size / zoom * Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down") * delta * 0.8
	position = lerp(position, _target_position, 12.0 * delta)
#--- public api for the override system ---

#this is the main function to trigger the override.
#target_zoom should be a vector2, e.g., vector2(0.5, 0.5) for a closer view.
func override_camera(target_position: Vector2, target_zoom: Vector2, duration: float) -> void:
	#before override, save current position and zoom
	camera_state_cache = [position, zoom]
	#1. kill any previous override tween that might still be running.
	#this is critical to prevent conflicting animations.
	if is_instance_valid(_active_tween):
		_active_tween.kill()

	#2. set the state flag to disable manual controls.
	_is_overridden = true

	#3. create a new tween to handle the smooth transition.
	_active_tween = create_tween()
	_active_tween.set_parallel(true) #allow position and zoom to animate simultaneously
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE) #for a smooth slowdown

	#4. add the properties to be animated.
	_active_tween.tween_property(self, "position", target_position, duration)
	_active_tween.tween_property(self, "zoom", target_zoom, duration)

	#5. connect the finished signal to our cleanup function.
	_active_tween.finished.connect(_on_override_finished)

func snap_camera(target_position: Vector2, target_zoom: Vector2) -> void: ##instantly repositions the camera without entering override mode so manual controls remain available
	if is_instance_valid(_active_tween):
		_active_tween.kill()

	_active_tween = null
	_is_overridden = false
	_is_soft_snapping = false
	_target_position = target_position
	position = target_position
	zoom = target_zoom

func soft_snap_camera(target_position: Vector2, target_zoom: Vector2, duration: float) -> void: ##animates toward a target view without locking controls and cleanly ends in the normal free-camera state
	if is_instance_valid(_active_tween):
		_active_tween.kill()

	_is_overridden = false
	_is_soft_snapping = true
	_target_position = target_position

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(self, "position", target_position, duration)
	_active_tween.tween_property(self, "zoom", target_zoom, duration)
	_active_tween.finished.connect(_on_soft_snap_finished)

func focus_and_inspect_unit(unit: Unit, duration: float = 0.35) -> void: ##selects a runtime unit for inspection and recenters the camera on it without locking controls
	if not is_instance_valid(unit):
		return

	ClickHandler.select_entity(unit)
	soft_snap_camera(unit.global_position, zoom, duration)

#allows an external system (like a ui button) to cancel the override
func release_override() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	#the cleanup function is called directly to ensure state is reset
	_on_override_finished()
	_target_position = camera_state_cache[0]
	_active_tween = create_tween()
	_active_tween.set_parallel(true) #allow position and zoom to animate simultaneously
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE) #for a smooth slowdown
	_active_tween.tween_property(self, "position", camera_state_cache[0], RETURN_FROM_OVERRIDE_TIME)
	_active_tween.tween_property(self, "zoom", camera_state_cache[1], RETURN_FROM_OVERRIDE_TIME)

	_active_tween.finished.connect(func(): _is_overridden = false)

#--- private signal handler ---
#this function is called automatically when the override tween completes.
func _on_override_finished() -> void:
	#2. clear the reference to the now-finished tween.
	_active_tween = null

func _on_soft_snap_finished() -> void:
	_active_tween = null
	_is_soft_snapping = false
	position = _target_position

func _cancel_soft_snap() -> void:
	if not _is_soft_snapping:
		return
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = null
	_is_soft_snapping = false
	_target_position = position

func _should_cancel_soft_snap(event: InputEvent) -> bool:
	if event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out"):
		return true
	if event.is_action_pressed("pan_left") or event.is_action_pressed("pan_right") or event.is_action_pressed("pan_up") or event.is_action_pressed("pan_down"):
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		return true
	if event is InputEventMouseMotion and _is_drag_panning:
		return true
	return false
