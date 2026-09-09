extends EffectPrototype
class_name ScoutingGogglesEffect

@export var max_bonus: float = 1.2 ##maximum bonus damage reached at or beyond the configured distance
@export var min_distance: float = 20.0 ##distance in world units at which damage bonus remains at minimum (0.0)
@export var max_distance: float = 100.0 ##distance in world units at which the damage bonus reaches its maximum

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData
	if not is_instance_valid(hit_data) or hit_data.negate:
		return

	var source_tower: Tower = hit_data.source as Tower
	var target: Unit = event.unit
	if not _is_valid_attack(source_tower, target):
		return

	var distance: float = source_tower.global_position.distance_to(target.global_position)
	var bonus_proportion: float = clampf((distance - min_distance) / maxf(max_distance - min_distance, 0.001), 0.0, 1.0)
	hit_data.damage *= 1.0 + (max_bonus * bonus_proportion)

func _is_valid_attack(source_tower: Tower, target: Unit) -> bool:
	if not is_instance_valid(source_tower) or source_tower.hostile:
		return false
	if not is_instance_valid(target) or not target.hostile:
		return false
	return true
