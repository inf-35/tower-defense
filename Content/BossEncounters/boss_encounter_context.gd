extends RefCounted
class_name BossEncounterContext

var service: BossEncounterService ##runtime service owning this encounter instance

func _init(encounter_service: BossEncounterService) -> void:
	service = encounter_service

func get_boss() -> Unit: ##returns the active persistent boss unit
	if not is_instance_valid(service):
		return null
	return service.get_boss()

func get_subwave_index() -> int: ##returns the zero-based active subwave index
	if not is_instance_valid(service):
		return 0
	return service.get_subwave_index()

func get_subwave_elapsed() -> float: ##returns elapsed combat time for the active subwave
	if not is_instance_valid(service):
		return 0.0
	return service.get_subwave_elapsed()

func spawn_minion(unit_type: Units.Type, position: Vector2) -> Unit: ##spawns and tracks one boss minion outside ordinary wave counters
	if not is_instance_valid(service):
		return null
	return service.spawn_minion(unit_type, position)
