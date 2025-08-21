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
const NORMAL_SIZE := Vector2(10, 10)
const FOCUS_SIZE := Vector2(15, 15)
const TWEEN_TIME: float = 1.0

# a simple data class to hold the visual properties for a pip
class TimelinePipVisuals:
	var size: Vector2
	var color: Color
	var rotation: float

	func _init(p_size: Vector2, p_color: Color, p_rotation: float) -> void:
		self.size = p_size
		self.color = p_color
		self.rotation = p_rotation

# configures the pip's state from the timeline controller
func setup(p_wave_number: int, p_wave_type: Phases.WaveType) -> void:
	self.wave_number = p_wave_number
	self.wave_type = p_wave_type
	_apply_visuals_instantly()

# sets if this pip represents the currently active wave
func set_is_current(is_current: bool) -> void:
	# only update if the state is actually changing
	if self._is_current == is_current:
		return
	self._is_current = is_current

# applies the visual state instantly, without animation. used for setup.
func _apply_visuals_instantly() -> void:
	var properties: TimelinePipVisuals = get_target_visual_properties()
	pivot_offset = properties.size * 0.5
	custom_minimum_size = properties.size
	if is_instance_valid(color_rect):
		color_rect.rotation_degrees = properties.rotation
		color_rect.color = properties.color

# calculates the target visual state based on current properties
func get_target_visual_properties() -> TimelinePipVisuals:
	var intended_final_size: Vector2
	var target_color: Color
	var target_rotation: float

	if _is_current:
		intended_final_size = FOCUS_SIZE
	else:
		intended_final_size = NORMAL_SIZE

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
		_: #default to normal
			target_color = NORMAL_COLOR
			target_rotation = 0.0

	var new_target_size: Vector2 = intended_final_size

	return TimelinePipVisuals.new(new_target_size, target_color, target_rotation)
#used to query this node's final rendered width
func get_visual_width() -> float:
	var visuals: TimelinePipVisuals = get_target_visual_properties()
	#if there is no rotation, width is just the x component of size
	if visuals.rotation == 0.0:
		return visuals.size.x
	#otherwise, calculate the rotated bounding box width
	var rotation_rad: float = deg_to_rad(visuals.rotation)
	var cos_rot: float = abs(cos(rotation_rad))
	var sin_rot: float = abs(sin(rotation_rad))
	return visuals.size.x * cos_rot + visuals.size.y * sin_rot

# adds this pip's animations to a master tween from the timeline
func add_visual_tweens_to(tween: Tween) -> void:
	var properties: TimelinePipVisuals = get_target_visual_properties()
	
	tween.parallel().tween_property(self, "custom_minimum_size", properties.size, TWEEN_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	if is_instance_valid(color_rect):
		tween.parallel().tween_property(color_rect, "position", properties.size * -0.5, TWEEN_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		tween.parallel().tween_property(color_rect, "rotation_degrees", properties.rotation, TWEEN_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		tween.parallel().tween_property(color_rect, "color", properties.color, TWEEN_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# a helper for fading commanded by the timeline
func fade_to(tween: Tween, alpha: float) -> void:
	tween.parallel().tween_property(self, "modulate:a", alpha, TWEEN_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
