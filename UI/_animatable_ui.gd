extends Control
class_name AnimatableUI

# --- Configuration ---
@export_group("References")
@export var content: Control ## The actual visual element to animate. Must be a child of this node.

@export_group("Entrance Animation")
@export var auto_play_entrance: bool = false
@export var slide_offset: Vector2 = Vector2(0, 50) ## Start position offset (relative to 0,0)
@export var entrance_duration: float = 0.4
@export var entrance_delay: float = 0.0

@export_group("Hover Animation")
@export var hover_enabled: bool = true
@export var hover_scale: Vector2 = Vector2(1.05, 1.05)
@export var hover_duration: float = 0.1

@export_group("Idle Animation")
@export var idle_sway_enabled: bool = false
@export var idle_sway_angle: float = 2.0 ## Max rotation degrees (sways between -angle and +angle)
@export var idle_sway_duration: float = 4.0 ## Time for a full cycle (Left -> Right -> Left)
@export var idle_random_phase: bool = true ## Randomizes start time slightly to desync multiple items

@export_group("Tween Settings")
@export var transition_type: Tween.TransitionType = Tween.TRANS_CUBIC
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

# --- State ---
var _current_tween: Tween
var _idle_tween: Tween # Track idle separately so entrance/hover don't kill it

func _ready() -> void:
	# 1. Validation and Setup
	if not content:
		if get_child_count() > 0 and get_child(0) is Control:
			content = get_child(0)
		else:
			push_warning("AnimatableUI: No content node assigned or found.")
			return

	# 2. Setup Pivot for correct scaling/rotation
	call_deferred("_update_content_pivot")
	
	# 3. Connect signals
	content.mouse_entered.connect(_on_mouse_entered)
	content.mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)

	# 4. Animations
	if auto_play_entrance:
		# Start invisible and offset
		content.modulate.a = 0.0
		content.position = slide_offset
		animate_entrance()
	
	# Idle triggers immediately; it interacts nicely with entrance because
	# entrance handles Position/Alpha, while Idle handles Rotation.
	if idle_sway_enabled:
		_start_idle_animation()

# --- Core Logic ---

func _update_content_pivot() -> void:
	if not content: return
	content.size = size
	# Center pivot is crucial for both Scaling (Hover) and Rotation (Idle)
	content.pivot_offset = size / 2.0

func _on_resized() -> void:
	_update_content_pivot()

# --- Animation API ---

func animate_entrance(custom_delay: float = -1.0) -> void:
	if not content: return
	
	var d = entrance_delay if custom_delay < 0 else custom_delay
	
	# Only kill the movement/fade tween, leave idle tween alone
	if _current_tween: _current_tween.kill()
	_current_tween = create_tween().set_parallel(true)
	
	# 1. Slide to (0,0)
	_current_tween.tween_property(content, "position", Vector2.ZERO, entrance_duration)\
		.set_trans(transition_type).set_ease(ease_type).set_delay(d)
		
	# 2. Fade In
	_current_tween.tween_property(content, "modulate:a", 1.0, entrance_duration)\
		.set_trans(Tween.TRANS_LINEAR).set_delay(d)

func snap_to_default() -> void:
	if _current_tween: _current_tween.kill()
	content.position = Vector2.ZERO
	content.scale = Vector2.ONE
	content.rotation = 0.0
	content.modulate.a = 1.0

# --- Idle Logic ---

func _start_idle_animation() -> void:
	if not content: return
	if _idle_tween: _idle_tween.kill()
	
	# Calculate a random duration offset to prevent robotic synchronization
	var duration = idle_sway_duration
	if idle_random_phase:
		duration += randf_range(-0.5, 0.5)
	
	# To make the loop seamless, we first tween from 0 to the start angle (Right),
	# then we start the infinite loop (Right -> Left -> Right).


	_idle_tween = create_tween()
	_idle_tween.set_trans(Tween.TRANS_SINE)
	_idle_tween.set_parallel(false)
	_idle_tween.set_loops()
	_idle_tween.tween_property(content, "rotation", deg_to_rad(idle_sway_angle), duration * 0.5).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(content, "rotation", deg_to_rad(-idle_sway_angle), duration * 0.5).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.play()

# --- Hover Logic ---

func _on_mouse_entered() -> void:
	if not hover_enabled or not content: return
	
	# We use a separate tween for scale so it doesn't conflict with position/rotation
	var hover_tween = create_tween()
	hover_tween.tween_property(content, "scale", hover_scale, hover_duration)\
		.set_trans(transition_type).set_ease(ease_type)

func _on_mouse_exited() -> void:
	if not hover_enabled or not content: return
	
	var hover_tween = create_tween()
	hover_tween.tween_property(content, "scale", Vector2.ONE, hover_duration)\
		.set_trans(transition_type).set_ease(ease_type)

# --- Manual Control ---

func look_at_mouse(strength: float = 10.0) -> void:
	if not content: return
	var local_mouse = get_local_mouse_position()
	var center = size / 2.0
	var offset = (local_mouse - center).normalized() * strength
	content.position = offset
