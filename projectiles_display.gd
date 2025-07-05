extends Node2D

var marker_position: Vector2

func _draw():
	var inner_color = Color(1.0, 0.0, 0.0, 0.2)
	draw_circle(marker_position, 10.0, inner_color)
