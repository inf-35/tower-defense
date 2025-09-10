extends Camera2D
class_name Camera

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	# Check if the abstract action was just triggered this frame.
	if Input.is_action_just_pressed("zoom_in"):
		zoom *= 0.9
		
	if Input.is_action_just_pressed("zoom_out"):
		zoom /= 0.9

	position += get_viewport_rect().size / zoom * Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down") * delta * 0.5
