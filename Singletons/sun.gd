extends Node

#signal to update static objects (performance optimization)
signal sun_changed

#the direction and length of shadows combined (offset in pixels)
var global_offset: Vector2 = Vector2(20, 28)

#the color of the shadow (e.g., black for day, teal for winter)
var shadow_color: Color = Color(0.165, 0.22, 0.33, 0.4)

func update_sun(direction: Vector2, strength: float, color: Color) -> void:
	global_offset = direction.normalized() * strength
	shadow_color = color
	sun_changed.emit()
