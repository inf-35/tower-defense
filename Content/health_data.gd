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

@export_category("Auxillary")
@export var damage_taken: float = 1.0: ##damage taken (in terms of proportion, 0 -> invincibility)
	set(new_value):
		damage_taken = new_value
		value_changed.emit(Attributes.id.DAMAGE_TAKEN)
@export var flat_damage_taken: float = 0.0: ##additionally taken flat damage per hit
	set(new_value):
		flat_damage_taken = new_value
		value_changed.emit(Attributes.id.FLAT_DAMAGE_TAKEN)
@export var max_shield: float = 0.0
