extends Behavior
class_name ForestBehavior

var _shadows: Sprite2D

func start() -> void:
	_shadows = graphics.get_node("Shadows")
	match Phases.current_game_environment:
		Phases.GameEnvironment.WOODS:
			(graphics as Sprite2D).texture = preload("res://Assets/trees.png")
			_shadows.texture = preload("res://Assets/forest_shadow.png")
			_shadows.position = Vector2(0.0, 33.33) #empirical values based on manual fitting
			_shadows.scale = Vector2(1.047, 1.032)
		Phases.GameEnvironment.WINTER:
			(graphics as Sprite2D).texture = preload("res://Assets/pines.png")
			_shadows.texture = preload("res://Assets/pine_shadows.png")
			_shadows.position = Vector2(0.0, 25.0)
			_shadows.scale = Vector2(1.047, 1.032)
