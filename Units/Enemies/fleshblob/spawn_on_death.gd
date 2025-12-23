extends EffectPrototype
class_name SpawnOnDeathEffect

@export var spawn_unit_type: Units.Type = Units.Type.BASIC
@export var spawn_count: int = 3
@export var spread_radius: float = 10.0

func _init() -> void:
	event_hooks = [GameEvent.EventType.DIED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return

	if event.unit != instance.host:
		return
		
	_spawn_children(instance.host.global_position)

func _spawn_children(origin_pos: Vector2) -> void:
	var island = References.island
	if not is_instance_valid(island):
		return
		
	for i in spawn_count:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(0, spread_radius) #small random enemy
		Waves.spawn_enemy(spawn_unit_type, origin_pos + offset)
