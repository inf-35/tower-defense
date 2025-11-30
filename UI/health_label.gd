extends Label
class_name HealthLabel

func _ready() -> void:
	UI.update_health.connect(_update_health)
	
	if Player:
		_update_health(Player.hp)
	
func _update_health(hp: float): 
	text = "Health: %s" % [str(roundi(hp * 10) * 0.1)] # Using string formatting
