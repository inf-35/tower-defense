extends Label
class_name FloatingText

@onready var icon_rect: TextureRect = $TextureRect

#--- state ---
var _base_z_index: int = 0
var _velocity: Vector2
var _gravity: float
var _lifetime: float
var _age: float
var _manager_ref: FloatingTextManager
var _peak_alpha: float = 1.0
var _ramp_up_ratio: float = 0.0
var _fade_out_ratio: float = 0.3
var _ignore_pause: bool = false

func _ready() -> void:
	_base_z_index = z_index
	add_to_group(DebugAssistant.GROUP_FLOATING_TEXTS)

func setup(
	text_val: String,
	pos: Vector2,
	color: Color,
	velocity: Vector2,
	gravity: float,
	lifetime: float,
	manager,
	peak_alpha: float = 1.0,
	ramp_up_ratio: float = 0.0,
	fade_out_ratio: float = 0.3,
	ignore_pause: bool = false
) -> void:
	icon_rect.visible = false
	text = text_val
	position = pos
	_apply_text_fill_color(color)
	modulate = Color.WHITE
	modulate.a = 0.0 if ramp_up_ratio > 0.0 else peak_alpha
	z_index = _base_z_index

	_velocity = velocity
	_gravity = gravity
	_lifetime = lifetime
	_age = 0.0
	_manager_ref = manager
	_peak_alpha = peak_alpha
	_ramp_up_ratio = ramp_up_ratio
	_fade_out_ratio = fade_out_ratio
	_ignore_pause = ignore_pause

	visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS if _ignore_pause else Node.PROCESS_MODE_INHERIT
	set_process(true)

func setup_icon(icon: Texture2D, pos: Vector2, color: Color, velocity: Vector2, gravity: float, lifetime: float, manager, ignore_pause: bool = false) -> void:
	icon_rect.visible = true
	icon_rect.texture = icon
	text = ""
	modulate = color
	z_index = _base_z_index

	global_position = pos
	_velocity = velocity
	_gravity = gravity
	_lifetime = lifetime
	_age = 0.0
	_manager_ref = manager
	_ignore_pause = ignore_pause

	visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS if _ignore_pause else Node.PROCESS_MODE_INHERIT
	set_process(true)

func merge_text(text_val: String, pos: Vector2, color: Color, scale_override: Vector2, z_index_offset: int, lifetime_override: float, min_remaining_lifetime: float) -> void: ##updates an active text label so repeated damage can reuse the same node
	icon_rect.visible = false
	text = text_val
	position = pos
	scale = scale_override
	_apply_text_fill_color(color)
	modulate.a = maxf(modulate.a, _peak_alpha)
	z_index = _base_z_index + z_index_offset
	if lifetime_override > 0.0:
		_lifetime = maxf(_lifetime, lifetime_override)
	var remaining_lifetime: float = _lifetime - _age
	if remaining_lifetime < min_remaining_lifetime:
		_age = maxf(0.0, _lifetime - min_remaining_lifetime)

func set_z_index_offset(offset: int) -> void: ##raises important pooled labels relative to ordinary floating text without changing their parent layer
	z_index = _base_z_index + offset

func _apply_text_fill_color(color: Color) -> void: ##tints only the label glyph fill so the existing outline remains stable
	if color.a <= 0.0:
		remove_theme_color_override(&"font_color")
		return

	add_theme_color_override(&"font_color", color)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		_return_to_pool()
		return

	_velocity.y += _gravity * delta
	position += _velocity * delta

	var ramp_up_duration: float = _lifetime * _ramp_up_ratio
	var fade_out_duration: float = _lifetime * _fade_out_ratio
	var fade_out_start: float = _lifetime - fade_out_duration

	if ramp_up_duration > 0.0 and _age < ramp_up_duration:
		modulate.a = lerpf(0.0, _peak_alpha, _age / ramp_up_duration)
	elif fade_out_duration > 0.0 and _age > fade_out_start:
		var fade_t: float = (_age - fade_out_start) / fade_out_duration
		modulate.a = lerpf(_peak_alpha, 0.0, fade_t)
	else:
		modulate.a = _peak_alpha

func _return_to_pool() -> void:
	visible = false
	set_process(false)
	process_mode = Node.PROCESS_MODE_INHERIT

	var manager: FloatingTextManager = _manager_ref
	if manager:
		manager.return_text(self)
	else:
		queue_free()
