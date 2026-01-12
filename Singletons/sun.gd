extends Node

# Signal to update static objects (performance optimization)
signal sun_changed

# The direction and length of shadows combined (offset in pixels)
# (5, 5) means shadows fall 5 pixels to the right and 5 down.
var global_offset: Vector2 = Vector2(10, 20)

# The color of the shadow (e.g., black for day, teal for winter)
var shadow_color: Color = Color(0.176, 0.19, 0.28, 0.557)

func update_sun(direction: Vector2, strength: float, color: Color):
	global_offset = direction.normalized() * strength
	shadow_color = color
	sun_changed.emit()
