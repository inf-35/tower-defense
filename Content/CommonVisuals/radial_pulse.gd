extends Node2D
class_name RadialPulseVFX

# --- Configuration ---
@export var color: Color = Color(0.2, 1.0, 0.4, 0.8)
@export var thickness: float = 4.0

@export_group("Animation")
@export var duration: float = 0.5
@export var start_radius: float = 0.0
@export var max_radius: float = 150.0

@export_group("Shape")
@export var is_full_circle: bool = true
@export var start_angle_deg: float = -45.0 ## Only used if is_full_circle is false
@export var end_angle_deg: float = 45.0   ## Only used if is_full_circle is false

# --- State ---
var _current_radius: float = 0.0
var _age: float = 0.0

func _ready() -> void:
	_current_radius = start_radius
	
	# Start the animation sequence
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 1. Expand Radius (Decelerating outward)
	tween.tween_property(self, "_current_radius", max_radius, duration)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		
	# 2. Fade Out (Starts opaque, fades to 0)
	tween.tween_property(self, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
	# 3. Cleanup
	tween.chain().tween_callback(queue_free)

func _process(_delta: float) -> void:
	# Force redraw every frame as the radius changes
	queue_redraw()

func _draw() -> void:
	if _current_radius <= 0.1: return
	
	# draw_arc takes angles in radians. 
	# Godot's 0 angle is pointing RIGHT (East). 
	
	if is_full_circle:
		# Draw a complete circle
		# draw_arc(center, radius, start_angle, end_angle, point_count, color, width, antialiasing)
		draw_arc(Vector2.ZERO, _current_radius, 0, TAU, 64, color, thickness, true)
	else:
		# Draw a specific slice (e.g. for a Cone Attack)
		var start_rad = deg_to_rad(start_angle_deg)
		var end_rad = deg_to_rad(end_angle_deg)
		draw_arc(Vector2.ZERO, _current_radius, start_rad, end_rad, 32, color, thickness, true)
		
		# Optional: Draw the "spokes" to close the cone shape
		# var p1 = Vector2.from_angle(start_rad) * _current_radius
		# var p2 = Vector2.from_angle(end_rad) * _current_radius
		# draw_line(Vector2.ZERO, p1, color, thickness, true)
		# draw_line(Vector2.ZERO, p2, color, thickness, true)
