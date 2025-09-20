extends SubViewport
class_name UIViewport

@onready var window: Window = get_tree().get_root()
var BASE_SIZE: Vector2i = Vector2i(1080, 1080)

func _ready():
	DisplayServer.window_set_min_size(Vector2i(100,100))
	window.size_changed.connect(_on_window_size_changed)
	
func _on_window_size_changed():
	var scaling: float
	scaling = maxf(float(BASE_SIZE.x) / window.size.x, 1.0)
	scaling = maxf(maxf(float(BASE_SIZE.y) / window.size.y, 1.0), scaling)
	var render_size: Vector2i = window.size * scaling

	size_2d_override = render_size
	print(window.size, " * ", scaling, " = ", render_size)
