extends Label
class_name HealthLabel

func _ready() -> void:
	UI.update_health.connect(_update_health)

	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_health(Run.player.hp)

func _update_health(hp: float) -> void:
	text = "Health: %s" % [str(roundi(hp * 10) * 0.1)] #using string formatting
