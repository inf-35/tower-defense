extends Node2D
class_name FloatingTextManager

# --- Configuration ---
@export var text_scene: PackedScene
@export var initial_pool_size: int = 30

@export_group("Physics Defaults")
@export var default_velocity_min: Vector2 = Vector2(-2, -5)
@export var default_velocity_max: Vector2 = Vector2(2, -8)
@export var default_gravity: float = 10.0
@export var default_lifetime: float = 0.5

# --- State ---
var _pool: Array[FloatingText] = []
var _active_count: int = 0

func _ready() -> void:
	UI.floating_text_manager = self
	
	# Pre-populate
	if text_scene:
		for i in range(initial_pool_size):
			_create_new_text()

# --- Public API ---

func show_value(value: float, world_pos: Vector2, color: Color = Color.WHITE, scale_mod: float = 1.0) -> void:
	var str_val = str(snappedf(value, 0.1))
	var final_color = color
	var scale_mult = scale_mod
	
	_spawn_text(str_val, world_pos, final_color, scale_mult)

func show_text(text: String, world_pos: Vector2, color: Color) -> void:
	_spawn_text(text, world_pos, color, 1.0)

func _spawn_text(txt: String, pos: Vector2, col: Color, scale_mod: float) -> void:
	var instance: FloatingText
	
	if _pool.is_empty():
		instance = _create_new_text()
	else:
		instance = _pool.pop_back()
		
	_active_count += 1

	var vel = Vector2(
		randf_range(default_velocity_min.x, default_velocity_max.x),
		randf_range(default_velocity_min.y, default_velocity_max.y)
	) * scale_mod

	instance.scale = Vector2(0.06, 0.06) * scale_mod
	
	instance.setup(txt, pos, col, vel, default_gravity, default_lifetime, self)

func _create_new_text() -> FloatingText:
	var t = text_scene.instantiate() as FloatingText
	t.visible = false
	t.set_process(false)
	add_child(t)
	return t

func return_text(text: FloatingText) -> void:
	_pool.append(text)
	_active_count -= 1
