# TimelinePip.gd
extends Control
class_name TimelinePip

# --- state ---
var wave_number: int
var wave_type: Phases.WaveType
var _is_current: bool = false

# --- node references ---
@export var color_rect: ColorRect 

# --- configuration for visual states ---
const NORMAL_COLOR := Color("#ffffff")
const BOSS_COLOR := Color("#ff6347")   # tomato red
const REWARD_COLOR := Color("#ffd700") # gold
const SURGE_COLOR := Color("#add8e6")  # light blue
const NORMAL_SIZE : Vector2 = Vector2(10,10)
const FOCUS_SIZE : Vector2 = Vector2(18,18)
const TWEEN_TIME : float = 0.5

class TimelinePipVisuals:
	var size : Vector2
	var color : Color
	var rotation : float
	
	func _init(_size, _color, _rotation):
		size = _size
		color = _color
		rotation = _rotation #(in degrees)

# configures the pip's state from the timeline controller
func setup(p_wave_number: int, p_wave_type: Phases.WaveType) -> void:
	self.wave_number = p_wave_number
	self.wave_type = p_wave_type
	_apply_visuals_instantly()

# sets if this pip represents the currently active wave
func set_is_current(is_current: bool) -> void:
	if self._is_current == is_current:
		return
	self._is_current = is_current

func _apply_visuals_instantly() -> void:
	var properties: TimelinePipVisuals = _get_target_visual_properties()
	custom_minimum_size = properties.size
	rotation_degrees = properties.rotation
	if is_instance_valid(color_rect):
		color_rect.color = properties.color

# calculates the target visual state based on current properties
func _get_target_visual_properties() -> TimelinePipVisuals:
	var target_size: Vector2
	var target_color: Color
	var target_rotation: float

	# determine target size based on focus state
	if _is_current:
		target_size = FOCUS_SIZE
	else:
		target_size = NORMAL_SIZE

	# determine color and rotation based on wave type
	match wave_type:
		Phases.WaveType.BOSS:
			target_color = BOSS_COLOR
			target_rotation = 45.0
		Phases.WaveType.REWARD:
			target_color = REWARD_COLOR
			target_rotation = 0.0
		Phases.WaveType.SURGE:
			target_color = SURGE_COLOR
			target_rotation = 0.0
		_: # default to normal
			target_color = NORMAL_COLOR
			target_rotation = 0.0

	return TimelinePipVisuals.new(target_size, target_color, target_rotation)

# this function adds this pip's animations to a master tween from the timeline
func add_visual_tweens_to(tween: Tween) -> void:
	var properties: TimelinePipVisuals = _get_target_visual_properties()
	
	# add this pip's property animations to the existing, parallel tween
	tween.parallel().tween_property(self, "custom_minimum_size", properties.size, TWEEN_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	tween.parallel().tween_property(self, "rotation_degrees", properties.rotation, TWEEN_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if is_instance_valid(color_rect):
		tween.parallel().tween_property(color_rect, "color", properties.color, TWEEN_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
