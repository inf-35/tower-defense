extends Label
class_name CapacityLabel

func _ready() -> void:
	UI.update_capacity.connect(_update_capacity)
	
	if Player:
		_update_capacity(Player.used_capacity, Player.tower_capacity)
	
func _update_capacity(used: float, total: float): 
	text = "Capacity: %s / %s" % [str(roundi(used * 10) * 0.1), str(roundi(total * 10) * 0.1)] # Using string formatting
