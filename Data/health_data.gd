extends Data
class_name HealthData

@export_category("Health")
@export var max_health: float = 10.0:
	set(new_value):
		max_health = new_value
		value_changed.emit(Attributes.id.MAX_HEALTH)
@export var regeneration: float = 0.0:
	set(new_value):
		regeneration = new_value
		value_changed.emit(Attributes.id.REGENERATION)
@export var regen_percent: float = 0.0:
	set(new_value):
		regen_percent = new_value
		value_changed.emit(Attributes.id.REGEN_PERCENT)
