extends Node

# Signal to update static objects (performance optimization)
signal sun_changed

# The direction and length of shadows combined (offset in pixels)
var global_offset: Vector2 = Vector2(12, 18)

# The color of the shadow (e.g., black for day, teal for winter)
var shadow_color: Color = Color(0.165, 0.22, 0.33, 0.557)

func update_sun(direction: Vector2, strength: float, color: Color):
	global_offset = direction.normalized() * strength
	shadow_color = color
	sun_changed.emit()
