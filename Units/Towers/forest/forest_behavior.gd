extends Behavior
class_name ForestBehavior

var _shadows: Sprite2D

func start() -> void:
	_shadows = graphics.get_node("Shadows")
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return
	(graphics as Sprite2D).texture = profile.forest_texture
	_shadows.texture = profile.forest_shadow_texture
	_shadows.position = profile.forest_shadow_position
	_shadows.scale = profile.forest_shadow_scale
