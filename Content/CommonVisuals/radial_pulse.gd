@tool
extends Node2D
class_name RadialPulseVFX

@export var filled: bool = false
@export var thickness: float = 4.0
@export var color_gradient: Gradient ## defines the color and opacity over the effect's lifetime

@export_group("animation")
@export var autostart: bool = true:
	set(na):
		autostart = na
		if autostart:
			reset()
			start()
@export var destroy_on_finish: bool = false ## turn off if you plan to manually reset and restart
@export var duration: float = 0.5
@export var start_radius: float = 0.0
@export var max_radius: float = 150.0

@export_group("shape")
@export var is_full_circle: bool = true
@export var start_angle_deg: float = -45.0 
@export var end_angle_deg: float = 45.0   

var _current_radius: float = 0.0
var _progress: float = 0.0 ## 0.0 to 1.0, tracks animation completion for gradient sampling
var _tween: Tween

func _ready() -> void:
	reset()
	if autostart:
		start()

func start() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
		
	_tween = create_tween()
	_tween.set_parallel(true)
	
	# expand radius
	_tween.tween_property(self, "_current_radius", max_radius, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# track overall progress for color sampling
	_tween.tween_property(self, "_progress", 1.0, duration)\
		.set_trans(Tween.TRANS_LINEAR)
		
	_tween.chain().tween_callback(_on_finish)

func reset() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
		
	_current_radius = start_radius
	_progress = 0.0
	queue_redraw()

func _on_finish() -> void:
	if destroy_on_finish:
		queue_free()

func _process(_delta: float) -> void:
	# only ask the rendering server to redraw if we are actively animating
	if is_instance_valid(_tween) and _tween.is_running():
		queue_redraw()

func _draw() -> void:
	if _current_radius <= 0.1: 
		return
	
	var current_color: Color = Color.WHITE
	if color_gradient:
		current_color = color_gradient.sample(_progress)
	
	if is_full_circle:
		if filled:
			draw_circle(Vector2.ZERO, _current_radius, current_color)
		else:
			draw_arc(Vector2.ZERO, _current_radius, 0, TAU, 64, current_color, thickness, true)
	else:
		var start_rad = deg_to_rad(start_angle_deg)
		var end_rad = deg_to_rad(end_angle_deg)
		
		if filled:
			# build a polygon for a filled slice
			var points := PackedVector2Array()
			points.append(Vector2.ZERO) # center point
			
			var steps: int = 32
			for i in range(steps + 1):
				var angle = lerpf(start_rad, end_rad, float(i) / steps)
				points.append(Vector2.from_angle(angle) * _current_radius)
				
			var colors := PackedColorArray([current_color])
			draw_polygon(points, colors)
		else:
			# draw outline and spokes
			draw_arc(Vector2.ZERO, _current_radius, start_rad, end_rad, 32, current_color, thickness, true)
			
			var p1 = Vector2.from_angle(start_rad) * _current_radius
			var p2 = Vector2.from_angle(end_rad) * _current_radius
			draw_line(Vector2.ZERO, p1, current_color, thickness, true)
			draw_line(Vector2.ZERO, p2, current_color, thickness, true)
