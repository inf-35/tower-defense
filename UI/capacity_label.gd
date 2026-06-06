extends Label
class_name CapacityLabel

func _ready() -> void:
	UI.update_capacity.connect(_update_capacity)

	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_capacity(Run.player.used_capacity, Run.player.tower_capacity)

func _update_capacity(used: float, total: float) -> void:
	text = "Capacity: %s / %s" % [str(roundi(used * 10) * 0.1), str(roundi(total * 10) * 0.1)] #using string formatting
