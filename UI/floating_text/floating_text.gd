extends Label
class_name FloatingText

# --- State ---
var _velocity: Vector2
var _gravity: float
var _lifetime: float
var _age: float
var _manager_ref: FloatingTextManager

func setup(text_val: String, pos: Vector2, color: Color, velocity: Vector2, gravity: float, lifetime: float, manager) -> void:
	text = text_val
	position = pos
	modulate = color
	
	_velocity = velocity
	_gravity = gravity
	_lifetime = lifetime
	_age = 0.0
	_manager_ref = manager
	
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		_return_to_pool()
		return

	_velocity.y += _gravity * delta
	position += _velocity * delta
	
	# fade Out (Last 30% of life)
	if _age > _lifetime * 0.7:
		var fade_t = (_age - (_lifetime * 0.7)) / (_lifetime * 0.3)
		modulate.a = 1.0 - fade_t

func _return_to_pool() -> void:
	visible = false
	set_process(false)
	
	var manager: FloatingTextManager = _manager_ref
	if manager:
		manager.return_text(self)
	else:
		queue_free()
