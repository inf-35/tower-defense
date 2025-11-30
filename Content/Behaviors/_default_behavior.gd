extends Behavior
class_name DefaultBehavior

func update(delta: float) -> void:
	_cooldown += delta
	_attempt_simple_attack()
