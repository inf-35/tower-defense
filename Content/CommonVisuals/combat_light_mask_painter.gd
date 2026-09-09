extends Node2D
class_name CombatLightMaskPainter

var _lights: Array[Dictionary] = []

func _ready() -> void:
	material = _make_additive_material()

func set_lights(lights: Array[Dictionary]) -> void: ##replaces the current screen-space light list and schedules one mask redraw
	_lights = lights
	queue_redraw()

func _draw() -> void:
	for light_data: Dictionary in _lights:
		var light_texture: Texture2D = light_data.get("texture", null) as Texture2D
		if light_texture == null:
			continue

		var energy: float = float(light_data.get("energy", 0.0))
		if energy <= 0.0:
			continue

		var position: Vector2 = light_data.get("position", Vector2.ZERO)
		var radius: float = float(light_data.get("radius", 0.0))
		if radius <= 0.0:
			continue

		var light_color: Color = light_data.get("color", Color.WHITE)
		var rect := Rect2(position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
		draw_texture_rect(light_texture, rect, false, Color(light_color.r * energy, light_color.g * energy, light_color.b * energy, energy))

func _make_additive_material() -> CanvasItemMaterial: ##lets overlapping tower glows accumulate in the offscreen light mask before the cap is applied
	var additive_material := CanvasItemMaterial.new()
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive_material
