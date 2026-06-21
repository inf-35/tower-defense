@tool
extends Node2D
class_name ContactShadow

@export_group("Settings")
#the width and height of the ellipse in pixels
@export var shadow_size: Vector2 = Vector2(4.5, 2.5):
	set(value):
		shadow_size = value
		queue_redraw() #redraw immediately when changed in editor

@export var color: Color = Color("2d314756"):
	set(value):
		color = value
		queue_redraw()

#resolution of the curve (32 is usually smooth enough for small shadows)
const SEGMENTS: int = 16

func _ready() -> void:
	#ensure it draws behind the parent unit
	z_index = Layers.TERRAIN_EFFECTS
	z_as_relative = false

func _draw() -> void:
	#generate points for an ellipse
	var points: PackedVector2Array = PackedVector2Array()
	var center = Vector2.ZERO

	for i in range(SEGMENTS + 1):
		#calculate angle for this segment
		var angle = deg_to_rad(i * 360.0 / SEGMENTS)

		#create the oval shape using sin/cos math
		#we divide size by 2 because size implies diameter, math uses radius
		var x = cos(angle) * (shadow_size.x / 2.0)
		var y = sin(angle) * (shadow_size.y / 2.0)

		points.push_back(center + Vector2(x, y))

	#draw the filled shape
	draw_colored_polygon(points, color)
